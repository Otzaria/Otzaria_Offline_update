import 'dart:ffi' show Abi;
import 'dart:io';

import '../port/app_report.dart';
import '../port/app_report_redactor.dart';
import 'app_report_service.dart';
import 'unclean_exit_detector.dart';

/// מצב הדיווח אחרי קריסה, כפי שהוא שמור בהגדרות.
enum AppCrashReportMode {
  ask('ask'),
  always('always'),
  never('never');

  const AppCrashReportMode(this.wireName);

  final String wireName;

  static AppCrashReportMode parse(Object? raw) =>
      AppCrashReportMode.values.firstWhere(
        (mode) => mode.wireName == raw,
        orElse: () => AppCrashReportMode.ask,
      );
}

/// הפעולה שההפעלה הנוכחית תבצע בעקבות קריסה של ההפעלה הקודמת.
enum CrashReportAction { none, prompt, sendAutomatically }

/// ההכרעה מה לעשות עם קריסה שזוהתה: מצב ההגדרה × המועמד × המגבלה.
abstract final class CrashReportDecision {
  /// מפתח המגבלה לקריסה בלי חתימה. באוצריא זו הכותרת הכללית עצמה; כאן
  /// הכותרת מתורגמת, והמפתח אסור שישתנה עם השפה.
  static const String fallbackThrottleKey = 'unexpected-exit';

  static CrashReportAction decide({
    required AppCrashReportMode mode,
    required CrashCandidate? candidate,
    required bool throttleAllows,
  }) {
    if (candidate == null || mode == AppCrashReportMode.never) {
      return CrashReportAction.none;
    }
    if (mode == AppCrashReportMode.always) {
      return throttleAllows
          ? CrashReportAction.sendAutomatically
          : CrashReportAction.none;
    }
    return CrashReportAction.prompt;
  }

  /// כותרת הדיווח: סוג החריגה מהחתימה, ואם אין — [fallbackTitle].
  static String titleFor(
    CrashCandidate candidate, {
    required String fallbackTitle,
  }) {
    final exceptionType = candidate.signature?.exceptionType.trim() ?? '';
    return exceptionType.isEmpty ? fallbackTitle : exceptionType;
  }

  /// מפתח המגבלה. קריסה בלי חתימה מקובצת תחת מפתח קבוע.
  static String throttleKeyFor(CrashCandidate candidate) {
    final signature = candidate.signature;
    if (signature == null || signature.exceptionType.trim().isEmpty) {
      return fallbackThrottleKey;
    }
    return signature.hash;
  }
}

/// מה שקרה בפועל עם קריסה שזוהתה בעלייה.
enum CrashReportOutcome { ignored, throttled, prompted, sentAutomatically }

/// הצרופות של דיווח: מפת האבחון וקטע היומן, כבר אחרי הסתרת מידע אישי.
class AppReportAttachments {
  const AppReportAttachments({
    required this.diagnostics,
    required this.errorLog,
  });

  final Map<String, dynamic> diagnostics;
  final String errorLog;
}

/// אוסף הצרופות. המימוש בלאנצ'ר: האבחון צריך את Flutter (מסכים, שפה).
abstract interface class AppReportAttachmentsCollector {
  Future<AppReportAttachments> collect();
}

/// גרסת מערכת ההפעלה וארכיטקטורה — בלי להריץ תהליכים חיצוניים.
abstract final class ReportSystemInfo {
  static String osVersion() {
    try {
      return normalizeOsVersion(
        Platform.operatingSystemVersion,
        isWindows: Platform.isWindows,
      );
    } catch (_) {
      return '';
    }
  }

  /// Windows 11 מדווח את עצמו "Windows 10" (גם ב-`ProductName`) מטעמי תאימות;
  /// רק מספר ה-build מבדיל. סטייה מכוונת מאוצריא, ששולחת את הטקסט הגולמי.
  static String normalizeOsVersion(String raw, {required bool isWindows}) {
    if (!isWindows) return raw;
    final build = RegExp(r'Build (\d+)').firstMatch(raw);
    final number = build == null ? null : int.tryParse(build.group(1)!);
    if (number == null || number < 22000) return raw;
    return raw.replaceFirst(RegExp(r'Windows 10(?!\d)'), 'Windows 11');
  }

  /// `x64` / `arm64` / … לפי ה-ABI של התהליך. תהליך x64 באמולציה על מעבד ARM
  /// מזוהה לפי `PROCESSOR_IDENTIFIER` ומדווח `x64-on-arm64`.
  static String detectArch({Abi? abi, Map<String, String>? environment}) {
    final current = abi ?? Abi.current();
    final name = current.toString();
    final underscore = name.indexOf('_');
    var arch = underscore < 0 ? name : name.substring(underscore + 1);
    if (arch == 'ia32') arch = 'x86';
    if (current == Abi.windowsX64) {
      final env = environment ?? Platform.environment;
      final identifier = env['PROCESSOR_IDENTIFIER'] ?? '';
      if (identifier.toUpperCase().contains('ARM')) return 'x64-on-arm64';
    }
    return arch;
  }
}

/// הטיפול בקריסה של ההפעלה הקודמת: לפי ההגדרה — התעלמות, שליחה אוטומטית
/// (בכפוף למגבלה) או הצגת ההצעה למשתמש.
class CrashReportFlow {
  CrashReportFlow({
    required this.showPrompt,
    required AppReportService service,
    required AppReportAttachmentsCollector collector,
    required AutoCrashReportThrottle throttle,
    required AppCrashReportMode Function() readMode,
    required String Function() savedEmail,
    required this.appVersion,
    required this.fallbackTitle,
    AppReportRedactor? redactor,
    DateTime Function()? clock,
  })  : _service = service,
        _collector = collector,
        _throttle = throttle,
        _readMode = readMode,
        _savedEmail = savedEmail,
        _redactor = redactor ?? AppReportRedactor.fromPlatform(),
        _clock = clock ?? DateTime.now;

  /// מציג את ההצעה למשתמש; מחזיר false כשאין עדיין Navigator להציג בו.
  final Future<bool> Function(CrashCandidate candidate) showPrompt;

  final String appVersion;

  /// הכותרת לקריסה בלי חתימה, בשפת הממשק.
  final String fallbackTitle;

  final AppReportService _service;
  final AppReportAttachmentsCollector _collector;
  final AutoCrashReportThrottle _throttle;
  final AppCrashReportMode Function() _readMode;
  final String Function() _savedEmail;
  final AppReportRedactor _redactor;
  final DateTime Function() _clock;

  Future<CrashReportOutcome> handle(CrashCandidate candidate) async {
    final mode = _readMode();
    final throttleKey = CrashReportDecision.throttleKeyFor(candidate);
    final throttleAllows = mode != AppCrashReportMode.always ||
        await _throttle.canReport(
          signatureHash: throttleKey,
          appVersion: appVersion,
        );

    switch (CrashReportDecision.decide(
      mode: mode,
      candidate: candidate,
      throttleAllows: throttleAllows,
    )) {
      case CrashReportAction.none:
        return mode == AppCrashReportMode.always
            ? CrashReportOutcome.throttled
            : CrashReportOutcome.ignored;
      case CrashReportAction.prompt:
        final shown = await showPrompt(candidate);
        return shown ? CrashReportOutcome.prompted : CrashReportOutcome.ignored;
      case CrashReportAction.sendAutomatically:
        await _sendAutomatically(candidate);
        // נרשם גם כשהדיווח רק נשמר בתור — אחרת עלייה חוזרת תשלח אותו שוב.
        await _throttle.recordReported(
          signatureHash: throttleKey,
          appVersion: appVersion,
        );
        return CrashReportOutcome.sentAutomatically;
    }
  }

  Future<void> _sendAutomatically(CrashCandidate candidate) async {
    AppReportAttachments? attachments;
    try {
      attachments = await _collector.collect();
    } catch (_) {
      // דיווח בלי צרופות עדיף על דיווח שלא נשלח.
    }
    final email = _savedEmail().trim();
    final report = AppReport(
      reportId: AppReport.generateReportId(),
      type: AppReportType.crash,
      trigger: AppReportTrigger.autoCrash,
      title: CrashReportDecision.titleFor(
        candidate,
        fallbackTitle: fallbackTitle,
      ),
      // מייל שמור לא תקין היה נדחה ב-422 ומוחק את הדיווח — שולחים בלעדיו.
      reporterEmail: AppReport.isValidEmail(email) ? email : '',
      appVersion: appVersion,
      platform: AppReport.currentPlatform(),
      osVersion: ReportSystemInfo.osVersion(),
      arch: ReportSystemInfo.detectArch(),
      signature: candidate.signature,
      createdAt: _clock(),
      diagnostics: attachments?.diagnostics,
      errorLog: attachments?.errorLog,
      product: AppReport.offlineUpdateProduct,
    ).redactedWith(_redactor);
    await _service.send(report);
  }
}
