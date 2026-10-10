import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../self_update/launcher_version.dart';
import '../self_update/payload_check.dart';

/// אוסף את האבחון ואת קטע היומן לדיווח על הלאנצ'ר. כל מקטע עמיד לכשל:
/// מקטע שנכשל נרשם כ-`{'error': ...}` ואינו מפיל את השאר.
class LauncherReportCollector implements AppReportAttachmentsCollector {
  LauncherReportCollector({
    required this.logsDirectory,
    required this.state,
    Map<String, String>? environment,
    DateTime Function()? clock,
  })  : _environment = _relevant(environment ?? _platformEnvironment()),
        _redactor = AppReportRedactor(
          environment: _relevant(environment ?? _platformEnvironment()),
        ),
        _clock = clock ?? DateTime.now;

  /// רק מה שההסתרה צריכה — והמפה עוברת ל-isolate, ולכן פשוטה וקטנה.
  static const _environmentKeys = ['USERPROFILE', 'HOME', 'USERNAME', 'USER'];

  static Map<String, String> _platformEnvironment() {
    try {
      return Platform.environment;
    } catch (_) {
      return const {};
    }
  }

  static Map<String, String> _relevant(Map<String, String> all) => {
        for (final key in _environmentKeys)
          if (all[key] case final value?) key: value,
      };

  /// טווח הזמן של רשומות היומן שנכנסות לדיווח.
  static const Duration logWindow = Duration(days: 7);
  static const int maxLogBytes = 200 * 1000;

  final String logsDirectory;

  /// מצב המודולים בלבד — בלי נתיבים ושמות קבצים של המשתמש.
  final Map<String, dynamic> Function() state;

  final Map<String, String> _environment;
  final AppReportRedactor _redactor;
  final DateTime Function() _clock;

  @override
  Future<AppReportAttachments> collect() async {
    final results = await Future.wait([collectDiagnostics(), collectLog()]);
    return AppReportAttachments(
      diagnostics: results[0] as Map<String, dynamic>,
      errorLog: results[1] as String,
    );
  }

  /// מפת האבחון: גרסאות, מערכת ומצב המודולים.
  Future<Map<String, dynamic>> collectDiagnostics() async {
    final diagnostics = <String, dynamic>{
      'collectedAt': _clock().toUtc().toIso8601String(),
      'appInfo': await _guard('appInfo', () async => appInfo()),
      'system': await _guard('system', () async => systemInfo()),
      'state': await _guard('state', () async => state()),
    };
    try {
      return Map<String, dynamic>.from(
          _redactor.redactJson(diagnostics) as Map);
    } catch (error) {
      // מפה שאי אפשר להסתיר בה בוודאות לא יוצאת מהמחשב.
      return {'error': 'redaction failed: $error'};
    }
  }

  /// רשומות `launcher.log` (וקובץ הסבב) מהשבוע האחרון, החדשות בגבול הגודל,
  /// אחרי הסתרה וצמצום נתיבים לשם הקובץ. שמות קבצים עשויים להופיע בקטע.
  Future<String> collectLog() async {
    final since = _clock().subtract(logWindow);
    final parts = <String>[];
    for (final name in LauncherLogFormat.fileNames) {
      final file = File(p.join(logsDirectory, name));
      try {
        if (!await file.exists()) continue;
        parts.add(await UncleanExitDetector.readTail(file, 4 * 1000 * 1000));
      } catch (error) {
        parts.add('[$name unavailable: $error]');
      }
    }
    if (parts.isEmpty) return '';
    final content = parts.join('\n');
    return _excerptInIsolate(content, since, _environment);
  }

  /// חיתוך, הסתרה וצמצום של 200KB בתוך isolate: regex על יומן שלם מקפיא את
  /// הממשק. סטטית, ועם ערכים פשוטים בלבד — סגירה לא תלכוד את `this`.
  static Future<String> _excerptInIsolate(
    String content,
    DateTime since,
    Map<String, String> environment,
  ) =>
      Isolate.run(() {
        final excerpt = recentLauncherLogExcerpt(
          content,
          since: since,
          maxBytes: maxLogBytes,
        );
        final redacted =
            AppReportRedactor(environment: environment).redactText(excerpt);
        return AppReportRedactor.reducePaths(redacted);
      });

  static Map<String, dynamic> appInfo() => {
        'product': AppReport.offlineUpdateProduct,
        'launcherVersion': launcherVersion,
        if (PayloadCheck.stubPayloadVersion() case final payload?)
          'payloadVersion': payload,
        'executable': p.basename(Platform.resolvedExecutable),
        'debug': kDebugMode,
      };

  /// מערכת ההפעלה, ארכיטקטורה, שפה ומסכים — בלי להריץ תהליכים חיצוניים.
  @visibleForTesting
  static Map<String, dynamic> systemInfo() {
    final info = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'osVersion': ReportSystemInfo.osVersion(),
      'arch': ReportSystemInfo.detectArch(),
      'processAbi': Abi.current().toString(),
      'processors': Platform.numberOfProcessors,
      'dartVersion': Platform.version.split(' ').first,
    };
    try {
      final dispatcher = PlatformDispatcher.instance;
      info['locale'] = dispatcher.locale.toLanguageTag();
      info['locales'] =
          dispatcher.locales.map((l) => l.toLanguageTag()).toList();
      info['textScaleFactor'] = dispatcher.textScaleFactor;
      info['displays'] = [
        for (final display in dispatcher.displays)
          {
            'width': display.size.width,
            'height': display.size.height,
            'devicePixelRatio': display.devicePixelRatio,
            'refreshRate': display.refreshRate,
          },
      ];
      info['views'] = [
        for (final view in dispatcher.views)
          {
            'physicalWidth': view.physicalSize.width,
            'physicalHeight': view.physicalSize.height,
            'devicePixelRatio': view.devicePixelRatio,
          },
      ];
    } catch (error) {
      info['displayError'] = '$error';
    }
    return info;
  }

  static Future<Map<String, dynamic>> _guard(
    String name,
    Future<Map<String, dynamic>> Function() body,
  ) async {
    try {
      return await body();
    } catch (error) {
      return {'error': '$error'};
    }
  }
}
