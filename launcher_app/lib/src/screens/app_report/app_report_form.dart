import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';

import '../../app_report/app_report_draft_store.dart';
import '../../controllers/app_reports_controller.dart';
import '../../services/app_logger.dart';

/// שלב השליחה של הטופס.
enum AppReportSubmission { idle, sending, finished }

/// מצב טופס הדיווח: איסוף הצרופות, עריכה ושליחה — פורט של `AppReportBloc`
/// של אוצריא, כ-[ChangeNotifier] (בלאנצ'ר אין bloc).
class AppReportForm extends ChangeNotifier {
  AppReportForm({
    required this.reports,
    required this.trigger,
    this.initialType,
    this.initialTitle = '',
    this.signature,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        type = initialType,
        title = initialTitle,
        email = reports.savedEmail;

  final AppReportsController reports;
  final AppReportTrigger trigger;
  final AppReportType? initialType;
  final String initialTitle;
  final CrashSignature? signature;
  final DateTime Function() _clock;

  /// הצרופות עדיין נאספות; הטופס עדיין לא מוצג.
  bool collecting = true;

  AppReportType? type;
  String title;
  String description = '';
  String steps = '';
  String email;

  /// הצרופות שנאספו, כבר אחרי הסתרת מידע אישי. `null` כשהאיסוף נכשל.
  Map<String, dynamic>? diagnostics;
  String? errorLog;
  bool includeDiagnostics = true;
  bool includeErrorLog = true;
  List<AppReportImage> images = const [];

  AppReportSubmission submission = AppReportSubmission.idle;
  AppReportDeliveryResult? result;

  /// השדה שנכשל בבדיקת התקינות המקומית.
  String? invalidField;

  bool _disposed = false;

  bool get isSending => submission == AppReportSubmission.sending;
  bool get isFinished => submission == AppReportSubmission.finished;

  Future<void> loadAttachments() async {
    try {
      final attachments = await reports.collector.collect();
      diagnostics = attachments.diagnostics;
      errorLog = attachments.errorLog;
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('איסוף צרופות הדיווח נכשל', error, stack);
    }
    collecting = false;
    _notify();
  }

  void update({
    AppReportType? type,
    String? title,
    String? description,
    String? steps,
    String? email,
    bool? includeDiagnostics,
    bool? includeErrorLog,
    List<AppReportImage>? images,
  }) {
    if (isSending) return;
    this.type = type ?? this.type;
    this.title = title ?? this.title;
    this.description = description ?? this.description;
    this.steps = steps ?? this.steps;
    this.email = email ?? this.email;
    this.includeDiagnostics = includeDiagnostics ?? this.includeDiagnostics;
    this.includeErrorLog = includeErrorLog ?? this.includeErrorLog;
    this.images = images == null ? this.images : List.unmodifiable(images);
    if (type != null || title != null || description != null || email != null) {
      invalidField = null;
    }
    _notify();
  }

  /// רק לדיווח הידני: לדיווח על קריסה יש חתימה ומזהה משלו.
  bool get supportsDraft =>
      trigger == AppReportTrigger.manual && reports.drafts != null;

  /// ממלא את הטופס מטיוטה שנשמרה. מחזיר `true` כשהייתה כזו.
  Future<bool> restoreDraft() async {
    if (!supportsDraft) return false;
    final draft = await reports.drafts!.load();
    if (draft == null || _disposed || isSending) return false;
    type = draft.type ?? type;
    title = draft.title;
    description = draft.description;
    steps = draft.steps;
    includeDiagnostics = draft.includeDiagnostics;
    includeErrorLog = draft.includeErrorLog;
    images = List.unmodifiable(draft.images);
    _notify();
    return true;
  }

  AppReportDraft get draft => AppReportDraft(
        type: type,
        title: title,
        description: description,
        steps: steps,
        includeDiagnostics: includeDiagnostics,
        includeErrorLog: includeErrorLog,
        images: images,
      );

  Future<void> saveDraft() async {
    if (supportsDraft) await reports.drafts!.save(draft);
  }

  Future<void> discardDraft() async {
    if (supportsDraft) await reports.drafts!.discard();
  }

  /// בודק, שומר את המייל ושולח. מחזיר את השדה הלא תקין, או `null`.
  Future<String?> submit() async {
    if (collecting || isSending || isFinished) return null;
    if (type == null) {
      invalidField = 'type';
      _notify();
      return invalidField;
    }
    // בשליחה, פעם אחת, גם על הצרופות: ההסתרה אידמפוטנטית, ונכונותה אינה
    // תלויה במימוש של האוסף לבדו.
    final report = buildReport().redactedWith(reports.redactor);
    final invalid = report.validate();
    if (invalid != null) {
      invalidField = invalid;
      _notify();
      return invalid;
    }
    submission = AppReportSubmission.sending;
    _notify();
    await reports.saveEmail(report.reporterEmail);
    try {
      result = await reports.service.send(report);
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('שליחת הדיווח נכשלה', error, stack);
      // כשל לא צפוי (דיסק) אינו מאבד את הטופס — אפשר לנסות שוב.
      submission = AppReportSubmission.idle;
      _notify();
      rethrow;
    }
    final outcome = result!;
    if (outcome.isFailed) {
      // דחייה סופית: הטופס נשאר פתוח עם הטקסט, והשדה שהשרת דחה מסומן.
      invalidField = _knownField(outcome.rejectedField);
      submission = AppReportSubmission.idle;
      _notify();
      return null;
    }
    submission = AppReportSubmission.finished;
    try {
      await discardDraft();
    } on FileSystemException catch (error) {
      AppLogger.maybeInstance?.warn('מחיקת טיוטת הדיווח נכשלה: $error');
    }
    _notify();
    return null;
  }

  /// השדה שהשרת דחה, אם הטופס מכיר אותו.
  static String? _knownField(String? field) =>
      const {'title', 'description', 'reporterEmail'}.contains(field)
          ? field
          : null;

  /// השרת דחה את הדיווח (400/413/422/409 חוזר) — לא נשמר לשליחה חוזרת.
  bool get wasRejected => result?.isFailed ?? false;

  int get otherAttachmentBytes =>
      _buildReport(type ?? AppReportType.bug).otherAttachmentBytes;

  /// הדיווח שיישלח ויוצג בתצוגה המקדימה; רק טקסטי המשתמש מוסתרים כאן.
  /// הצרופות הוסתרו כבר באיסוף, ולא עוברות הסתרה מחדש בכל הקלדה.
  AppReport buildReport() => _buildReport(type!);

  AppReport _buildReport(AppReportType reportType) {
    final fields = AppReport(
      reportId: _reportId,
      type: reportType,
      trigger: trigger,
      title: title,
      description: description,
      stepsToReproduce: steps,
      reporterEmail: email.trim(),
      appVersion: reports.appVersion,
      platform: AppReport.currentPlatform(),
      osVersion: ReportSystemInfo.osVersion(),
      arch: ReportSystemInfo.detectArch(),
      signature: signature,
      createdAt: _createdAt,
      images: images,
      product: AppReport.offlineUpdateProduct,
    ).redactedWith(reports.redactor);
    return fields.copyWith(
      diagnostics: includeDiagnostics ? diagnostics : null,
      errorLog: includeErrorLog ? errorLog : null,
    );
  }

  /// מזהה ומועד אחד לטופס: לחיצה חוזרת על "שלח" אחרי כשל היא אותו דיווח.
  late final String _reportId = AppReport.generateReportId();
  late final DateTime _createdAt = _clock();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
