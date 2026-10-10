import 'dart:async';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../app_report/launcher_crash_session.dart';
import '../app_report/launcher_report_collector.dart';
import '../self_update/launcher_version.dart';
import '../services/app_logger.dart';
import '../settings/settings_controller.dart';

/// הדיווחים של הלאנצ'ר על עצמו: התור, ההיסטוריה, השליחה ברקע והטיפול
/// בקריסה של ההפעלה הקודמת — כמו `AppReportService` ו-`CrashReportFlow`
/// של אוצריא. ראו `error_reports_manager/README.md`.
class AppReportsController extends ChangeNotifier {
  AppReportsController({
    required this.service,
    required this.collector,
    required this.settings,
    required this.logsDirectory,
    AutoCrashReportThrottle? throttle,
    AppReportRedactor? redactor,
    this.appVersion = launcherVersion,
    String? host,
    this.isProcessAlive,
  })  : host = host ?? UncleanExitDetector.localHost(),
        throttle = throttle ?? AutoCrashReportThrottle.inLogs(logsDirectory),
        redactor = redactor ?? AppReportRedactor.fromPlatform() {
    _changes = service.changes.listen((_) => unawaited(refresh()));
  }

  /// התור ב-`<stateDir>/reports/launcher`, הנעילה והמגבלה ליד היומן.
  factory AppReportsController.forState({
    required String stateDir,
    required String logsDirectory,
    required SettingsController settings,
  }) {
    late final AppReportsController controller;
    controller = AppReportsController(
      service: AppReportService(
        directory: AppReportService.dirIn(stateDir),
        log: (message) => AppLogger.maybeInstance?.warn(message),
      ),
      collector: LauncherReportCollector(
        logsDirectory: logsDirectory,
        state: () => controller.stateProvider(),
      ),
      settings: settings,
      logsDirectory: logsDirectory,
    );
    return controller;
  }

  final AppReportService service;
  final AppReportAttachmentsCollector collector;
  final SettingsController settings;
  final String logsDirectory;
  final AutoCrashReportThrottle throttle;
  final AppReportRedactor redactor;
  final String appVersion;

  /// בדיקת תהליך מוזרקת; `null` = הבדיקה האמיתית של המערכת.
  final bool Function(int pid)? isProcessAlive;

  /// שם המחשב — מפתח הכתובת השמורה (ראו `AppSettings.reportSenderEmails`).
  final String host;

  /// מצב המודולים לאבחון; `AppShell` מציב אותו, כי שם חיים המודולים.
  Map<String, dynamic> Function() stateProvider = () => const {};

  late final StreamSubscription<void> _changes;
  bool _disposed = false;

  int _pendingCount = 0;
  int _sentTotal = 0;
  int get pendingCount => _pendingCount;
  int get sentTotal => _sentTotal;

  AppCrashReportMode get crashMode => settings.settings.crashReportMode;

  /// הכתובת השמורה, המשותפת לטופס ולשליחה האוטומטית.
  String get savedEmail =>
      (settings.settings.reportSenderEmails[host] ?? '').trim();

  Future<void> setCrashMode(AppCrashReportMode mode) async {
    if (mode == crashMode) return;
    await settings.update(settings.settings.copyWith(crashReportMode: mode));
  }

  Future<void> saveEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || trimmed == savedEmail) return;
    await settings.update(
      settings.settings.copyWith(
        reportSenderEmails: {
          ...settings.settings.reportSenderEmails,
          host: trimmed,
        },
      ),
    );
  }

  Future<void> refresh() async {
    try {
      final (pending, sent) = await (
        service.getPendingReportsCount(),
        service.getSentReportsTotal(),
      ).wait;
      if (_disposed) return;
      _pendingCount = pending;
      _sentTotal = sent;
      notifyListeners();
    } catch (error) {
      AppLogger.maybeInstance?.warn('קריאת תור הדיווחים נכשלה: $error');
    }
  }

  /// שליחה מיידית של התור ואחת לחמש דקות — כמו `startAutomaticFlush` באוצריא.
  void startBackground() {
    unawaited(refresh());
    service.startAutomaticFlush();
  }

  /// זיהוי קריסה של ההפעלה הקודמת ופתיחת הנעילה של הנוכחית; ההחלטה מה
  /// לעשות — לפי ההגדרה. נקרא אחרי הפריים הראשון (AGENTS §5.9).
  Future<CrashReportOutcome?> runCrashCheck({
    required Future<bool> Function(CrashCandidate candidate) showPrompt,
  }) async {
    try {
      final candidate = await LauncherCrashSession.begin(
        logsDirectory: logsDirectory,
        version: appVersion,
        isProcessAlive: isProcessAlive,
      );
      if (candidate == null) return null;
      AppLogger.maybeInstance?.warn(
        'ההפעלה הקודמת נסגרה באופן לא צפוי: ${candidate.signature}',
      );
      return await crashFlow(showPrompt: showPrompt).handle(candidate);
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('בדיקת הקריסה נכשלה', error, stack);
      return null;
    }
  }

  @visibleForTesting
  CrashReportFlow crashFlow({
    required Future<bool> Function(CrashCandidate candidate) showPrompt,
  }) =>
      CrashReportFlow(
        showPrompt: showPrompt,
        service: service,
        collector: collector,
        throttle: throttle,
        readMode: () => crashMode,
        savedEmail: () => savedEmail,
        appVersion: appVersion,
        fallbackTitle: AppL10n.strings.appReports.crashFallbackTitle,
        redactor: redactor,
      );

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    service.dispose();
    super.dispose();
  }
}
