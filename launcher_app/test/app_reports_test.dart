import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/app_report/launcher_report_collector.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/screens/app_report/app_report_dialog.dart';
import 'package:launcher_app/src/screens/app_report/app_report_form.dart';
import 'package:launcher_app/src/screens/app_report/app_report_images_section.dart';
import 'package:launcher_app/src/screens/app_report/app_report_preview_section.dart';
import 'package:launcher_app/src/screens/app_report/app_reports_settings_card.dart';
import 'package:launcher_app/src/screens/app_report/crash_prompt_dialog.dart';
import 'package:launcher_app/src/screens/app_report/reports_management_dialog.dart';
import 'package:launcher_app/src/services/file_reveal.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';

/// תור והיסטוריה בזיכרון: קבצים אמיתיים אינם מסתיימים בתוך `testWidgets`.
class _MemoryService extends AppReportService {
  _MemoryService({this.respond = _sentResponse})
      : super(
          directory: '',
          client: MockClient((_) async => http.Response('', 500)),
        );

  static AppReportDeliveryResult _sentResponse(AppReport report) =>
      AppReportDeliveryResult(
        status: AppReportDeliveryStatus.sent,
        report: report.copyWith(
          issueNumber: 42,
          issueUrl: 'https://github.com/Otzaria/Otzaria_Offline_update/'
              'issues/42',
        ),
      );

  final AppReportDeliveryResult Function(AppReport) respond;
  final List<AppReport> sentReports = [];
  final List<AppReport> pending = [];
  final List<AppReport> history = [];

  @override
  Future<AppReportDeliveryResult> send(AppReport report) async {
    sentReports.add(report);
    final result = respond(report);
    if (result.isSent) history.insert(0, result.report);
    if (result.isQueued) pending.add(report);
    return result;
  }

  /// הרשומה כבר אינה בתור (נשלחה ברקע או הועברה ל-.bad).
  bool reportNotPending = false;

  @override
  Future<AppReportDeliveryResult> submitPendingReport(AppReport report) {
    if (reportNotPending) {
      return Future.value(
        AppReportDeliveryResult(
          status: AppReportDeliveryStatus.failed,
          report: report,
          failureReason: AppReportFailureReason.notPending,
        ),
      );
    }
    pending.removeWhere((r) => r.reportId == report.reportId);
    return send(report);
  }

  final changeCtl = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => changeCtl.stream;

  int pendingListCalls = 0;

  /// כשמוצב — הקריאה הראשונה לרשימה ממתינה לו.
  Completer<void>? firstListGate;

  @override
  Future<List<AppReport>> getPendingReports() async {
    pendingListCalls++;
    // הרשימה נלכדת לפני ההמתנה: תוצאה ישנה שמגיעה באיחור.
    final snapshot = List.of(pending);
    final gate = firstListGate;
    if (pendingListCalls == 1 && gate != null) await gate.future;
    return snapshot;
  }

  @override
  Future<int> getPendingReportsCount() async => pending.length;
  @override
  Future<List<AppReport>> getSentReports() async => List.of(history);
  @override
  Future<int> getSentReportsTotal() async => history.length;
  @override
  Future<void> deletePendingReport(String reportId) async =>
      pending.removeWhere((r) => r.reportId == reportId);
  @override
  Future<void> deleteSentReport(String reportId) async =>
      history.removeWhere((r) => r.reportId == reportId);
  @override
  Future<void> clearPendingReports() async => pending.clear();
  @override
  Future<void> clearSentReports() async => history.clear();
  int flushCalls = 0;
  int? lastFlushMax;
  FlushOutcome flushOutcome = const FlushOutcome();

  @override
  Future<FlushOutcome> flush({
    int maxRequests = AppReportService.maxBackgroundFlushPerRun,
  }) async {
    flushCalls++;
    lastFlushMax = maxRequests;
    return flushOutcome;
  }

  @override
  void startAutomaticFlush() {}
}

class _MemorySettings extends SettingsController {
  _MemorySettings([this._value = const AppSettings()]) : super(dataDir: '');

  AppSettings _value;

  @override
  AppSettings get settings => _value;

  @override
  Future<void> update(AppSettings next) async {
    _value = next;
    notifyListeners();
  }
}

class _FakeCollector implements AppReportAttachmentsCollector {
  @override
  Future<AppReportAttachments> collect() async => const AppReportAttachments(
        diagnostics: {
          'system': {'osVersion': '"Windows 11 Pro" 10.0 (Build 26100)'},
        },
        errorLog: '2026-10-09T10:00:00.000 [ERROR] boom',
      );
}

class _FakeImages extends AppReportImageSource {
  const _FakeImages();

  @override
  Future<PickedImages> pickFiles(
    String dialogTitle,
    List<AppReportImage> existing,
  ) async =>
      PickedImages([
        AppReportImage(
          bytes: Uint8List.fromList(const [1, 2, 3]),
          fileName: 'shot.png',
          mimeType: 'image/png',
        ),
      ]);
}

AppReportsController _controller(
  _MemoryService service, {
  _MemorySettings? settings,
  String logsDirectory = '',
}) =>
    AppReportsController(
      service: service,
      collector: _FakeCollector(),
      settings: settings ?? _MemorySettings(),
      logsDirectory: logsDirectory,
      redactor: AppReportRedactor(environment: const {}),
      appVersion: '0.25',
      host: 'PC1',
      // תהליך ההפעלה הקודמת מת — בלי בדיקת תהליך אמיתית של המערכת.
      isProcessAlive: (_) => false,
    );

AppReport _report(String id, {String title = 'דיווח'}) => AppReport(
      reportId: id,
      type: AppReportType.bug,
      trigger: AppReportTrigger.manual,
      title: title,
      description: 'd',
      reporterEmail: 'a@b.co',
      appVersion: '0.25',
      platform: 'windows',
      createdAt: DateTime.utc(2026, 10, 1),
    );

Future<void> _open(WidgetTester tester, WidgetBuilder builder) async {
  useViewSize(tester, const Size(1200, 1600));
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => Center(
          child: ActionButtonProbe(onPressed: () {
            showDialog<void>(context: context, builder: builder);
          }),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('probe')));
  await tester.pumpAndSettle();
}

/// כמו `wrap`, ועם `navigatorKey` — ממנו `UiSnack` מוצא את ה-Overlay.
Widget _app(Widget child) => MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL'), Locale('en')],
      locale: const Locale('he', 'IL'),
      builder: (context, navigator) => AppStringsScope(
        strings: AppL10n.stringsFor(AppLanguage.hebrew),
        child: navigator ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: child),
    );

/// כפתור פשוט שפותח את הדיאלוג הנבדק.
class ActionButtonProbe extends StatelessWidget {
  const ActionButtonProbe({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(key: const ValueKey('probe'), onTap: onPressed);
}

Future<void> _drainSnack(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 8));

void main() {
  final t = stringsOf().appReports;

  group('AppSettings — reports', () {
    test('מצב הקריסה והמייל נשמרים ונקראים', () {
      const settings = AppSettings(
        crashReportMode: AppCrashReportMode.always,
        reportSenderEmails: {'PC1': 'a@b.co'},
      );
      final back = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(back.crashReportMode, AppCrashReportMode.always);
      expect(back.reportSenderEmails, {'PC1': 'a@b.co'});
      expect(AppSettings.fromJson(const {}).crashReportMode,
          AppCrashReportMode.ask);
    });
  });

  group('AppReportDialog', () {
    testWidgets('שולח עם product, זוכר את המייל ומציג את מספר ה-issue',
        (tester) async {
      final service = _MemoryService();
      final settings = _MemorySettings();
      final reports = _controller(service, settings: settings);
      await _open(
        tester,
        (_) =>
            AppReportDialog(reports: reports, imageSource: const _FakeImages()),
      );

      await tester.enterText(
          find.byKey(const ValueKey('app-report-title')), 'כותרת');
      await tester.enterText(
          find.byKey(const ValueKey('app-report-description')), 'תיאור');
      await tester.enterText(
          find.byKey(const ValueKey('app-report-email')), 'me@x.com');
      await tester.tap(find.byKey(const ValueKey('app-report-image-area')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-report-image-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app-report-send')));
      await tester.pumpAndSettle();

      final sent = service.sentReports.single;
      expect(sent.product, AppReport.offlineUpdateProduct);
      expect(sent.toApiPayload()['product'], 'offline-update');
      expect(sent.trigger, AppReportTrigger.manual);
      expect(sent.title, 'כותרת');
      expect(sent.images.single.fileName, 'shot.png');
      expect(sent.errorLog, contains('boom'));
      expect(settings.settings.reportSenderEmails, {'PC1': 'me@x.com'});
      expect(find.byType(AppReportDialog), findsNothing);
      expect(find.text(t.sentSnack(42)), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('בלי תיאור ומייל — לא נשלח, והשדה מסומן', (tester) async {
      final service = _MemoryService();
      await _open(
          tester, (_) => AppReportDialog(reports: _controller(service)));

      await tester.enterText(
          find.byKey(const ValueKey('app-report-title')), 'כותרת');
      await tester.tap(find.byKey(const ValueKey('app-report-send')));
      await tester.pumpAndSettle();

      expect(service.sentReports, isEmpty);
      expect(find.text(t.descriptionRequired), findsOneWidget);
      expect(find.text(t.descriptionRequiredSnack), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('התצוגה המקדימה מראה את הדיווח, האבחון והיומן', (tester) async {
      await _open(
        tester,
        (_) => AppReportDialog(reports: _controller(_MemoryService())),
      );
      await tester.tap(find.byKey(const ValueKey('app-report-toggle-preview')));
      await tester.pumpAndSettle();

      final preview = tester
          .widget<SelectableText>(
            find.descendant(
              of: find.byKey(const ValueKey('app-report-preview-report')),
              matching: find.byType(SelectableText),
            ),
          )
          .data!;
      expect(preview, contains('"product": "offline-update"'));
      expect(preview, contains('"osVersion"'));
      expect(
        preview,
        contains(ReportSystemInfo.osVersion().replaceAll('"', r'\"')),
      );
      expect(find.text('diagnostics.json'), findsOneWidget);
      expect(find.text('launcher.log'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app-report-include-log')));
      await tester.pumpAndSettle();
      expect(find.text('launcher.log'), findsNothing);
    });

    testWidgets('כשל זמני — נשמר בתור והודעה מתאימה', (tester) async {
      final service = _MemoryService(
        respond: (r) => AppReportDeliveryResult(
          status: AppReportDeliveryStatus.queued,
          report: r,
        ),
      );
      await _open(
          tester, (_) => AppReportDialog(reports: _controller(service)));
      await tester.enterText(
          find.byKey(const ValueKey('app-report-title')), 'כותרת');
      await tester.enterText(
          find.byKey(const ValueKey('app-report-description')), 'תיאור');
      await tester.enterText(
          find.byKey(const ValueKey('app-report-email')), 'me@x.com');
      await tester.tap(find.byKey(const ValueKey('app-report-send')));
      await tester.pumpAndSettle();
      expect(service.pending, hasLength(1));
      expect(find.text(t.queuedSnack), findsOneWidget);
      await _drainSnack(tester);
    });
  });

  group('CrashPromptDialog', () {
    CrashCandidate candidate() => CrashCandidate(
          previousSession: SessionLock(
            pid: 1,
            version: '0.24',
            startedAt: DateTime.utc(2026, 10, 1),
          ),
          entries: const [],
          signature: const CrashSignature(
            exceptionType: 'StateError',
            frames: ['A.b (package:launcher_app/a.dart)'],
          ),
          hasStartupStall: false,
        );

    testWidgets('שליחה: crash_prompt עם החתימה, בלי מייל חובה, ושמירת המצב',
        (tester) async {
      final service = _MemoryService();
      final settings = _MemorySettings();
      final reports = _controller(service, settings: settings);
      await _open(
        tester,
        (_) => CrashPromptDialog(reports: reports, candidate: candidate()),
      );
      expect(find.text(t.crashTitle), findsOneWidget);

      await tester.tap(find.text(t.crashNextAlways));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crash-prompt-send')));
      await tester.pumpAndSettle();

      final sent = service.sentReports.single;
      expect(sent.trigger, AppReportTrigger.crashPrompt);
      expect(sent.type, AppReportType.crash);
      expect(sent.title, 'StateError');
      expect(sent.signature!.exceptionType, 'StateError');
      expect(sent.product, AppReport.offlineUpdateProduct);
      expect(settings.settings.crashReportMode, AppCrashReportMode.always);
      expect(find.byType(CrashPromptDialog), findsNothing);
      await _drainSnack(tester);
    });

    testWidgets('"אל תשלח" עם "אל תשאל שוב" — לא נשלח והמצב נשמר',
        (tester) async {
      final service = _MemoryService();
      final settings = _MemorySettings();
      await _open(
        tester,
        (_) => CrashPromptDialog(
          reports: _controller(service, settings: settings),
          candidate: candidate(),
        ),
      );
      await tester.tap(find.text(t.crashNextNever));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crash-prompt-dismiss')));
      await tester.pumpAndSettle();

      expect(service.sentReports, isEmpty);
      expect(settings.settings.crashReportMode, AppCrashReportMode.never);
      expect(find.text(t.crashDismissedSnack), findsOneWidget);
      await _drainSnack(tester);
    });
  });

  group('הכרטיס בהגדרות וחלון הניהול', () {
    testWidgets('הכרטיס מסכם את התור ומשנה את מצב הקריסה', (tester) async {
      final service = _MemoryService()..pending.add(_report('p1'));
      final settings = _MemorySettings();
      final reports = _controller(service, settings: settings);
      await tester.pumpWidget(wrap(AppReportsSettingsCard(reports: reports)));
      await reports.refresh();
      await tester.pumpAndSettle();

      expect(find.text(t.manageTileSubtitle(1, 0)), findsOneWidget);
      // מרכז הסגמנט ולא מרכז התווית: בגופן הבדיקה התווית גולשת מתחת לכפתור.
      final segment = tester.getRect(
        find.byType(SegmentedButton<AppCrashReportMode>),
      );
      await tester.tapAt(
        Offset(
          tester.getCenter(find.text(t.crashModeNever)).dx,
          segment.center.dy,
        ),
      );
      await tester.pumpAndSettle();
      expect(settings.settings.crashReportMode, AppCrashReportMode.never);
    });

    testWidgets('ניהול: מחיקה מהתור, שליחה, וקישור ל-issue', (tester) async {
      final service = _MemoryService()
        ..pending.addAll([_report('p1', title: 'ראשון'), _report('p2')])
        ..history.add(
          _report('s1', title: 'נשלח').copyWith(
            issueNumber: 7,
            issueUrl: 'https://github.com/Otzaria/Otzaria_Offline_update/'
                'issues/7',
          ),
        );
      final opened = <String>[];
      final reports = _controller(service);
      await _open(
        tester,
        (_) => ReportsManagementDialog(
          reports: reports,
          openUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      );

      expect(find.text(t.pendingCount(2)), findsOneWidget);
      expect(find.text('ראשון'), findsOneWidget);

      final firstTile = find.byKey(const ValueKey('app-report-pending-p1'));
      await tester.tap(
        find.descendant(of: firstTile, matching: find.text(t.deleteButton)),
      );
      await tester.pumpAndSettle();
      expect(service.pending.map((r) => r.reportId), ['p2']);
      await _drainSnack(tester);

      final second = find.byKey(const ValueKey('app-report-pending-p2'));
      await tester.tap(
        find.descendant(of: second, matching: find.text(t.sendOneButton)),
      );
      await tester.pumpAndSettle();
      expect(service.pending, isEmpty);
      expect(service.sentReports.single.reportId, 'p2');
      await _drainSnack(tester);

      await tester.tap(find.byKey(const ValueKey('app-report-open-issue-s1')));
      await tester.pumpAndSettle();
      expect(opened.single, endsWith('/issues/7'));
    });
  });

  group('runCrashCheck', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('launcher_crash_'));
    tearDown(() {
      LauncherCrashSession.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    void writeCrashOf(String logs, {String? host}) {
      final start = DateTime.now().subtract(const Duration(hours: 1));
      Directory(logs).createSync(recursive: true);
      File(p.join(logs, UncleanExitDetector.lockFileName)).writeAsStringSync(
        jsonEncode({
          'pid': 999999,
          'version': '0.24',
          'startedAt': start.toUtc().toIso8601String(),
          'host': host ?? UncleanExitDetector.localHost(),
        }),
      );
      File(p.join(logs, 'launcher.log')).writeAsStringSync(
        '${start.add(const Duration(minutes: 1)).toIso8601String()} [ERROR] '
        '${LauncherLogFormat.uncaughtMessage(LauncherLogFormat.zoneError, StateError('x'))}\n'
        'error: Bad state: x\n',
      );
    }

    test('ask: ההצעה מוצגת, והנעילה החדשה נכתבת', () async {
      final logs = p.join(tmp.path, 'logs');
      writeCrashOf(logs);
      final service = _MemoryService();
      final reports = _controller(service, logsDirectory: logs);
      CrashCandidate? shown;
      final outcome = await reports.runCrashCheck(
        showPrompt: (c) async {
          shown = c;
          return true;
        },
      );
      expect(outcome, CrashReportOutcome.prompted);
      expect(shown!.signature!.exceptionType, 'StateError');
      expect(service.sentReports, isEmpty);
      final lock = SessionLock.tryParse(
        File(p.join(logs, UncleanExitDetector.lockFileName)).readAsStringSync(),
      )!;
      expect(lock.pid, pid);

      LauncherCrashSession.markCleanExitSync();
      expect(
        File(p.join(logs, UncleanExitDetector.lockFileName)).existsSync(),
        isFalse,
      );
    });

    test('always: נשלח אוטומטית עם product', () async {
      final logs = p.join(tmp.path, 'logs');
      writeCrashOf(logs);
      final service = _MemoryService();
      final reports = _controller(
        service,
        logsDirectory: logs,
        settings: _MemorySettings(
          const AppSettings(crashReportMode: AppCrashReportMode.always),
        ),
      );
      final outcome = await reports.runCrashCheck(showPrompt: (_) async {
        fail('לא אמור לשאול');
      });
      expect(outcome, CrashReportOutcome.sentAutomatically);
      final sent = service.sentReports.single;
      expect(sent.trigger, AppReportTrigger.autoCrash);
      expect(sent.product, AppReport.offlineUpdateProduct);
    });

    test('נעילה ממחשב אחר — לא שואלים ולא שולחים', () async {
      final logs = p.join(tmp.path, 'logs');
      writeCrashOf(logs, host: 'ANOTHER-PC');
      final service = _MemoryService();
      final reports = _controller(
        service,
        logsDirectory: logs,
        settings: _MemorySettings(
          const AppSettings(crashReportMode: AppCrashReportMode.always),
        ),
      );
      final outcome = await reports.runCrashCheck(showPrompt: (_) async {
        fail('לא אמור לשאול');
      });
      expect(outcome, isNull);
      expect(service.sentReports, isEmpty);
    });

    test('בלי נעילה — אין מועמד', () async {
      final reports = _controller(
        _MemoryService(),
        logsDirectory: p.join(tmp.path, 'logs'),
      );
      expect(
        await reports.runCrashCheck(showPrompt: (_) async => true),
        isNull,
      );
    });
  });

  group('LauncherReportCollector', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('launcher_collect_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('יומן מהשבוע, מוסתר, ואבחון בלי נתיבים', () async {
      final now = DateTime(2026, 10, 9, 12);
      File(p.join(tmp.path, 'launcher.log')).writeAsStringSync(
        '${now.subtract(const Duration(days: 9)).toIso8601String()} [INFO] old\n'
        '${now.subtract(const Duration(hours: 1)).toIso8601String()} [INFO] '
        r'path C:\Users\Moshe\x'
        '\n',
      );
      final collector = LauncherReportCollector(
        logsDirectory: tmp.path,
        state: () => {'readOnly': false},
        environment: const {'USERPROFILE': r'C:\Users\Moshe'},
        clock: () => now,
      );
      final attachments = await collector.collect();
      expect(attachments.errorLog, isNot(contains('old')));
      expect(attachments.errorLog, contains(r'%USERPROFILE%\x'));
      expect(attachments.diagnostics['state'], {'readOnly': false});
      expect(
        (attachments.diagnostics['appInfo'] as Map)['product'],
        'offline-update',
      );
      expect(
        (attachments.diagnostics['system'] as Map)['osVersion'],
        ReportSystemInfo.osVersion(),
      );
    });
  });

  group('דחייה סופית — הטופס נשאר פתוח עם הטקסט', () {
    AppReportDeliveryResult rejected(AppReport r) => AppReportDeliveryResult(
          status: AppReportDeliveryStatus.failed,
          report: r,
          failureReason: AppReportFailureReason.rejected,
          httpStatus: 422,
          rejectedField: 'description',
        );

    testWidgets('הטופס הידני', (tester) async {
      final service = _MemoryService(respond: rejected);
      await _open(
          tester, (_) => AppReportDialog(reports: _controller(service)));
      await tester.enterText(
          find.byKey(const ValueKey('app-report-title')), 'כותרת');
      await tester.enterText(
          find.byKey(const ValueKey('app-report-description')), 'תיאור ארוך');
      await tester.enterText(
          find.byKey(const ValueKey('app-report-email')), 'me@x.com');
      await tester.tap(find.byKey(const ValueKey('app-report-send')));
      await tester.pumpAndSettle();

      expect(find.byType(AppReportDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('app-report-description')),
          matching: find.text('תיאור ארוך'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('app-report-title')),
          matching: find.text('כותרת'),
        ),
        findsOneWidget,
      );
      expect(find.text(t.descriptionRequired), findsOneWidget);
      expect(find.text(t.rejectedSnack('description')), findsOneWidget);
      // חזר למצב רגיל: אפשר לתקן ולשלוח שוב.
      final send = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('app-report-send')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(send.onPressed, isNotNull);
      await _drainSnack(tester);
    });

    testWidgets('ההצעה אחרי קריסה', (tester) async {
      final service = _MemoryService(respond: rejected);
      await _open(
        tester,
        (_) => CrashPromptDialog(
          reports: _controller(service),
          candidate: CrashCandidate(
            previousSession: SessionLock(
              pid: 1,
              version: '0.24',
              startedAt: DateTime.utc(2026, 10, 1),
            ),
            entries: const [],
            signature: null,
            hasStartupStall: false,
          ),
        ),
      );
      await tester.enterText(
          find.byKey(const ValueKey('crash-prompt-description')), 'הקלדתי');
      await tester.tap(find.byKey(const ValueKey('crash-prompt-send')));
      await tester.pumpAndSettle();
      expect(find.byType(CrashPromptDialog), findsOneWidget);
      expect(find.text('הקלדתי'), findsOneWidget);
      await _drainSnack(tester);
    });
  });

  group('הטופס — תצוגה מקדימה מול מה שנשלח', () {
    test('הרשומה בתצוגה זהה לגוף הנשלח, והצרופות אינן מוסתרות שוב', () async {
      final reports = _controller(_MemoryService());
      final form = AppReportForm(
        reports: reports,
        trigger: AppReportTrigger.manual,
      );
      await form.loadAttachments();
      form.update(
        title: 'כותרת a@b.com',
        description: r'ב-C:\Users\ZEEVLE~1\x',
        email: 'me@x.com',
      );
      final report = form.buildReport();
      final payload = report.toApiPayload();

      // טקסט המשתמש הוסתר; המייל של המדווח נשאר.
      expect(payload['title'], 'כותרת <email>');
      expect(payload['description'], r'ב-%USERPROFILE%\x');
      expect(payload['reporterEmail'], 'me@x.com');
      expect(payload['product'], 'offline-update');

      final previewFields = AppReportPreviewSection.reportFields(report);
      expect(previewFields, {...payload}..remove('attachments'));

      // הצרופות הן בדיוק מה שנאסף — אותם אובייקטים, בלי הסתרה נוספת.
      expect(identical(report.diagnostics, form.diagnostics), isTrue);
      expect(report.errorLog, form.errorLog);

      form.update(includeDiagnostics: false);
      expect(form.buildReport().diagnostics, isNull);
      expect(form.buildReport().errorLog, form.errorLog);
    });

    test('מזהה ומועד קבועים בין בנייה לבנייה (אותו דיווח בשליחה חוזרת)',
        () async {
      final form = AppReportForm(
        reports: _controller(_MemoryService()),
        trigger: AppReportTrigger.manual,
      );
      expect(form.buildReport().reportId, form.buildReport().reportId);
    });
  });

  group('בחירת תמונות', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('launcher_images_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String write(String name, List<int> bytes) =>
        (File(p.join(tmp.path, name))..writeAsBytesSync(bytes)).path;

    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2];
    const jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2];
    final gif = [...'GIF89a'.codeUnits, 1, 2];

    test('ה-mimeType נקבע מהבייטים, לא מהסיומת', () async {
      final picked = await AppReportImageSource.loadPaths([
        write('a.png', png),
        write('b.png', jpeg),
        write('c.gif', gif),
        write('d.jpg', [...'GIF87a'.codeUnits, 0]),
      ]);
      expect(
        picked.images.map((i) => i.mimeType),
        ['image/png', 'image/jpeg', 'image/gif', 'image/gif'],
      );
      expect(picked.images.map((i) => i.fileName),
          ['a.png', 'b.png', 'c.gif', 'd.jpg']);
      expect(picked.unreadable, 0);
      expect(picked.tooLarge, isFalse);
    });

    test('קובץ שאינו תמונה בפועל, ריק או חסר — לא נקרא', () async {
      final picked = await AppReportImageSource.loadPaths([
        write('fake.png', 'not an image at all'.codeUnits),
        write('empty.png', const []),
        p.join(tmp.path, 'missing.png'),
        write('ok.png', png),
      ]);
      expect(picked.images.single.fileName, 'ok.png');
      expect(picked.unreadable, 3);
    });

    test('גדול מהמקסימום נדחה לפי הגודל, בלי לקרוא אותו', () async {
      final big = write(
        'big.png',
        [...png, ...List.filled(AppReportImage.maxBytes, 0)],
      );
      final picked = await AppReportImageSource.loadPaths([big]);
      expect(picked.images, isEmpty);
      expect(picked.tooLarge, isTrue);
      expect(picked.unreadable, 0);
    });
  });

  group('כרטיס ההגדרות וניהול — שליחה עכשיו', () {
    testWidgets('תקרת הסבב אינה כשל, וכשל זמני כן', (tester) async {
      final service = _MemoryService()..pending.add(_report('p1'));
      await _open(
        tester,
        (_) => ReportsManagementDialog(reports: _controller(service)),
      );

      service.flushOutcome = const FlushOutcome(sent: 4, capped: true);
      await tester.tap(find.byKey(const ValueKey('app-reports-flush')));
      await tester.pumpAndSettle();
      expect(service.lastFlushMax, AppReportService.maxManualFlushPerRun);
      expect(find.text(t.flushRemainingSnack(4, 1)), findsOneWidget);
      await _drainSnack(tester);

      service.flushOutcome =
          const FlushOutcome(stoppedOnTransientFailure: true);
      await tester.tap(find.byKey(const ValueKey('app-reports-flush')));
      await tester.pumpAndSettle();
      expect(find.text(t.flushFailedSnack(1)), findsOneWidget);
      await _drainSnack(tester);
    });
  });

  group('מצב סייפר בהצעה אחרי קריסה', () {
    testWidgets('נעול: בחירה שאינה "שאל" דורשת סיסמה, ובלעדיה לא נשמרת',
        (tester) async {
      final settings = _MemorySettings(
        AppSettings(
          saferModeEnabled: true,
          saferModePassword: SaferModePassword.encode('1234'),
        ),
      );
      final gate = SaferModeGate(settings);
      expect(gate.isLocked, isTrue);
      final reports = _controller(_MemoryService(), settings: settings);
      await _open(
        tester,
        (_) => CrashPromptDialog(
          reports: reports,
          saferMode: gate,
          candidate: CrashCandidate(
            previousSession: SessionLock(
              pid: 1,
              version: '0.24',
              startedAt: DateTime.utc(2026, 10, 1),
            ),
            entries: const [],
            signature: null,
            hasStartupStall: false,
          ),
        ),
      );

      await tester.tap(find.text(t.crashNextNever));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crash-prompt-dismiss')));
      await tester.pumpAndSettle();
      expect(
          find.text(stringsOf().saferMode.verifySettingsHint), findsOneWidget);

      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pumpAndSettle();
      expect(settings.settings.crashReportMode, AppCrashReportMode.ask);
      await _drainSnack(tester);
    });
  });

  test('כתובת הדואר נשמרת לפי שם המחשב', () async {
    final settings = _MemorySettings();
    final here = _controller(_MemoryService(), settings: settings);
    await here.saveEmail('me@x.com');
    expect(here.savedEmail, 'me@x.com');

    final elsewhere = AppReportsController(
      service: _MemoryService(),
      collector: _FakeCollector(),
      settings: settings,
      logsDirectory: '',
      host: 'PC2',
    );
    expect(elsewhere.savedEmail, '');
    expect(settings.settings.reportSenderEmails, {'PC1': 'me@x.com'});
  });

  test('קטע היומן: נתיב מוחלט מחוץ לפרופיל מצטמצם לשם הקובץ', () async {
    final tmp = Directory.systemTemp.createTempSync('launcher_paths_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final now = DateTime(2026, 10, 9, 12);
    File(p.join(tmp.path, 'launcher.log')).writeAsStringSync(
      '${now.subtract(const Duration(hours: 1)).toIso8601String()} [INFO] '
      r'copy D:\Private\Folder\book.db and /Volumes/Stick/x/y.json'
      '\n',
    );
    final collector = LauncherReportCollector(
      logsDirectory: tmp.path,
      state: () => const {},
      environment: const {},
      clock: () => now,
    );
    final log = await collector.collectLog();
    expect(log, contains('copy book.db and y.json'));
    expect(log, isNot(contains('Private')));
    expect(log, isNot(contains('Volumes')));
  });

  group('סיכום "שלח עכשיו" וחלון הניהול', () {
    Future<_MemoryService> openWithPending(WidgetTester tester) async {
      final service = _MemoryService()..pending.add(_report('p1'));
      await _open(
        tester,
        (_) => ReportsManagementDialog(reports: _controller(service)),
      );
      return service;
    }

    testWidgets('כשל מקומי בלי שום שליחה: הודעת כשל, לא "נשלחו 0"',
        (tester) async {
      final service = await openWithPending(tester);
      service.flushOutcome = const FlushOutcome(failed: 2);
      await tester.tap(find.byKey(const ValueKey('app-reports-flush')));
      await tester.pumpAndSettle();
      expect(find.text(t.flushErrorSnack(2)), findsOneWidget);
      expect(find.text(t.flushSentSnack(0)), findsNothing);
      await _drainSnack(tester);
    });

    testWidgets('חלק נשלחו וחלק נכשלו מקומית: הכשל אינו מוסתר', (tester) async {
      final service = await openWithPending(tester);
      service.flushOutcome = const FlushOutcome(sent: 2, failed: 1);
      await tester.tap(find.byKey(const ValueKey('app-reports-flush')));
      await tester.pumpAndSettle();
      expect(find.text(t.flushPartialSnack(2, 1)), findsOneWidget);
      expect(find.text(t.flushSentSnack(2)), findsNothing);
      await _drainSnack(tester);
    });

    testWidgets('דחיות שרת מוזכרות', (tester) async {
      final service = await openWithPending(tester);
      service.flushOutcome = const FlushOutcome(sent: 1, dropped: 2);
      await tester.tap(find.byKey(const ValueKey('app-reports-flush')));
      await tester.pumpAndSettle();
      expect(find.text(t.flushDroppedSnack(1, 2)), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('תקרה עם עוד בתור: אומרים שנשארו', (tester) async {
      final service = await openWithPending(tester);
      service.flushOutcome = const FlushOutcome(sent: 8, capped: true);
      await tester.tap(find.byKey(const ValueKey('app-reports-flush')));
      await tester.pumpAndSettle();
      expect(find.text(t.flushRemainingSnack(8, 1)), findsOneWidget);
      await _drainSnack(tester);
    });

    testWidgets('שליחה של רשומה שכבר אינה בתור: הודעה, בלי שליחה, וריענון',
        (tester) async {
      final service = await openWithPending(tester);
      service.reportNotPending = true;
      final before = service.pendingListCalls;
      final tile = find.byKey(const ValueKey('app-report-pending-p1'));
      await tester.tap(
        find.descendant(of: tile, matching: find.text(t.sendOneButton)),
      );
      await tester.pumpAndSettle();
      expect(find.text(t.notPendingSnack), findsOneWidget);
      expect(service.sentReports, isEmpty);
      expect(service.pendingListCalls, greaterThan(before));
      await _drainSnack(tester);
    });

    testWidgets('אירועים חופפים מתכנסים לטעינה אחת, והחדשה מנצחת',
        (tester) async {
      useViewSize(tester, const Size(1200, 1600));
      final service = _MemoryService()
        ..pending.add(_report('p1', title: 'ישן'))
        ..firstListGate = Completer<void>();
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ActionButtonProbe(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    ReportsManagementDialog(reports: _controller(service)),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('probe')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      service.pending
        ..clear()
        ..add(_report('p2', title: 'חדש'));
      for (var i = 0; i < 3; i++) {
        service.changeCtl.add(null);
      }
      await tester.pump();
      service.firstListGate!.complete();
      await tester.pumpAndSettle();

      expect(service.pendingListCalls, 2);
      expect(find.text('חדש'), findsOneWidget);
      expect(find.text('ישן'), findsNothing);
    });
  });

  group('הטופס — הסתרה בשליחה ובחירת תמונות', () {
    test('צרופות שהאוסף לא הסתיר מוסתרות בשליחה', () async {
      final service = _MemoryService();
      final reports = AppReportsController(
        service: service,
        collector: _LeakyCollector(),
        settings: _MemorySettings(),
        logsDirectory: '',
        redactor: AppReportRedactor(environment: const {}),
        host: 'PC1',
      );
      final form = AppReportForm(
        reports: reports,
        trigger: AppReportTrigger.manual,
      );
      await form.loadAttachments();
      form.update(title: 't', description: 'd', email: 'me@x.com');
      await form.submit();

      final sent = service.sentReports.single;
      expect(sent.errorLog, contains('<email>'));
      expect(sent.errorLog, isNot(contains('leak@x.com')));
      expect(sent.reporterEmail, 'me@x.com');
    });

    group('loadPaths — עצירה במכסה', () {
      late Directory tmp;
      setUp(() => tmp = Directory.systemTemp.createTempSync('launcher_lim_'));
      tearDown(() => tmp.deleteSync(recursive: true));

      const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      String write(String name, int size) {
        final file = File(p.join(tmp.path, name))
          ..writeAsBytesSync([...png, ...List.filled(size - png.length, 0)]);
        return file.path;
      }

      test('אחרי מספר התמונות המרבי הקבצים הבאים אינם נקראים', () async {
        final paths = [
          for (var i = 0; i < AppReportImage.maxCount; i++) write('$i.png', 20),
          // קבצים חסרים: אילו נקראו, היו נספרים כ"לא נקראו".
          p.join(tmp.path, 'never1.png'),
          p.join(tmp.path, 'never2.png'),
        ];
        final picked = await AppReportImageSource.loadPaths(paths);
        expect(picked.images, hasLength(AppReportImage.maxCount));
        expect(picked.unreadable, 0);
        expect(picked.limit, AppReportImageRejection.tooMany);
      });

      test('התמונות הקיימות נספרות במכסה', () async {
        final existing = [
          for (var i = 0; i < 3; i++)
            AppReportImage(
              bytes: Uint8List(10),
              fileName: 'e$i.png',
              mimeType: 'image/png',
            ),
        ];
        final picked = await AppReportImageSource.loadPaths(
          [
            write('a.png', 20),
            write('b.png', 20),
            p.join(tmp.path, 'never.png'),
          ],
          existing: existing,
        );
        expect(picked.images, hasLength(2));
        expect(picked.unreadable, 0);
        expect(picked.limit, AppReportImageRejection.tooMany);
      });

      test('הנפח הכולל: קובץ שחורג ממנו אינו נקרא, אך קטן שאחריו נכנס',
          () async {
        const big = AppReportImage.maxBytes - 10;
        final picked = await AppReportImageSource.loadPaths([
          write('a.png', big),
          write('b.png', big),
          write('c.png', big),
          write('d.png', big),
          write('e.png', 20),
        ]);
        // כמו `mergeAppReportImages`: d נדחה, e עדיין נכנס.
        expect(
          picked.images.map((i) => i.fileName),
          ['a.png', 'b.png', 'c.png', 'e.png'],
        );
        expect(picked.limit, AppReportImageRejection.totalTooLarge);
        expect(picked.unreadable, 0);
      });
    });
  });

  group('נעילת ההפעלה מוקדמת ועמידה בכשל', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('launcher_begin_'));
    tearDown(() {
      LauncherCrashSession.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('begin כותב את הנעילה בלי להמתין להצעה, וקריאה חוזרת משתפת', () async {
      final first = LauncherCrashSession.begin(
        logsDirectory: tmp.path,
        version: '0.25',
      );
      final second = LauncherCrashSession.begin(
        logsDirectory: tmp.path,
        version: '9.9',
      );
      expect(identical(first, second), isTrue);
      await first;
      final lock = SessionLock.tryParse(
        File(p.join(tmp.path, UncleanExitDetector.lockFileName))
            .readAsStringSync(),
      )!;
      expect(lock.version, '0.25');
    });

    test('זיהוי שזורק: הנעילה נפתחת בכל זאת, ואין מועמד', () async {
      final candidate = await LauncherCrashSession.detectAndStartSession(
        logsDirectory: tmp.path,
        version: '0.25',
        detector: _ThrowingDetector(tmp.path),
      );
      expect(candidate, isNull);
      expect(
        File(p.join(tmp.path, UncleanExitDetector.lockFileName)).existsSync(),
        isTrue,
      );
      // והסגירה המסודרת מוחקת אותה — ה-detector נרשם גם אחרי הכשל.
      LauncherCrashSession.markCleanExitSync();
      expect(
        File(p.join(tmp.path, UncleanExitDetector.lockFileName)).existsSync(),
        isFalse,
      );
    });
  });

  test('openGithubUrl דוחה כל כתובת שאינה https://github.com', () async {
    expect(await _openRejected('http://github.com/x'), isFalse);
    expect(await _openRejected('https://evil.com/x'), isFalse);
    expect(await _openRejected('https://user@github.com/x'), isFalse);
    expect(await _openRejected('not a url'), isFalse);
    expect(AppL10n.strings.appReports.cardTitle, isNotEmpty);
  });
}

/// כל הכתובות כאן נדחות לפני שתהליך כלשהו רץ — הבדיקה אינה פותחת דפדפן.
Future<bool> _openRejected(String url) => FileReveal.openGithubUrl(url);

/// אוסף שלא הסתיר דבר — ההגנה בשליחה היא שמסתירה.
class _LeakyCollector implements AppReportAttachmentsCollector {
  @override
  Future<AppReportAttachments> collect() async => const AppReportAttachments(
        diagnostics: {'who': 'leak@x.com'},
        errorLog: '2026-10-09T10:00:00.000 [INFO] mail leak@x.com',
      );
}

class _ThrowingDetector extends UncleanExitDetector {
  _ThrowingDetector(String logs) : super(logsDirectory: logs);

  @override
  Future<CrashCandidate?> detectPreviousCrash() async =>
      throw StateError('isolate failed');
}
