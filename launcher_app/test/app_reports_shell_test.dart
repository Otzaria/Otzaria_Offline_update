// בדיקות החיווט של הדיווחים ב-[AppShell]: ההפעלה אחרי הפריים הראשון, ושני
// דיאלוגים שמופיעים מעצמם בעלייה אינם עולים יחד.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/screens/app_report/crash_prompt_dialog.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';
import 'test_support.dart';

/// שירות שסופר הפעלות, ושואל אם עץ המסך כבר נבנה ברגע ההפעלה.
class _CountingService extends AppReportService {
  _CountingService()
      : super(
          directory: '',
          client: MockClient((_) async => http.Response('', 500)),
        );

  int starts = 0;
  bool? homeBuiltAtStart;

  @override
  void startAutomaticFlush() {
    starts++;
    homeBuiltAtStart = find.byType(HomeScreen).evaluate().isNotEmpty;
  }

  @override
  Future<int> getPendingReportsCount() async => 0;
  @override
  Future<int> getSentReportsTotal() async => 0;
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

class _Collector implements AppReportAttachmentsCollector {
  @override
  Future<AppReportAttachments> collect() async =>
      const AppReportAttachments(diagnostics: {}, errorLog: '');
}

void main() {
  late Directory tempDir;
  late SettingsController settings;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('app_reports_shell');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    await settings.update(const AppSettings(autoCheckUpdates: false));
  });

  tearDown(() async {
    LauncherCrashSession.resetForTest();
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  AppReportsController controller(
    AppReportService service, {
    String logs = '',
  }) =>
      AppReportsController(
        service: service,
        collector: _Collector(),
        settings: settings,
        logsDirectory: logs,
        redactor: AppReportRedactor(environment: const {}),
        isProcessAlive: (_) => false,
      );

  Widget shell(AppReportsController reports, MemoryNoticesStore notices) =>
      wrap(
        AppShell(
          dataDir: tempDir.path,
          settings: settings,
          runningLocator: const _NeverRunningLocator(),
          noticesStore: notices,
          showWindowButtons: false,
          appReports: reports,
        ),
      );

  testWidgets('השליחה ברקע מופעלת אחרי הפריים הראשון, לא ב-initState',
      (tester) async {
    useViewSize(tester, const Size(1400, 1000));
    final service = _CountingService();
    final reports = controller(service);
    await tester.pumpWidget(
      shell(
        reports,
        MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
      ),
    );
    await tester.pump();

    expect(service.starts, 1);
    expect(service.homeBuiltAtStart, isTrue);
  });

  testWidgets('בלי הדיווחים (בדיקות אחרות) — אין הפעלה', (tester) async {
    useViewSize(tester, const Size(1400, 1000));
    await tester.pumpWidget(
      wrap(
        AppShell(
          dataDir: tempDir.path,
          settings: settings,
          runningLocator: const _NeverRunningLocator(),
          noticesStore:
              MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
          showWindowButtons: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('ההסבר החד-פעמי וההצעה אחרי קריסה לא עולים יחד', (tester) async {
    useViewSize(tester, const Size(1400, 1000));
    final logs = p.join(tempDir.path, 'logs')..toString();
    Directory(logs).createSync(recursive: true);
    final start = DateTime.now().subtract(const Duration(hours: 1));
    File(p.join(logs, UncleanExitDetector.lockFileName)).writeAsStringSync(
      jsonEncode({
        'pid': 999999,
        'version': '0.24',
        'startedAt': start.toUtc().toIso8601String(),
        'host': UncleanExitDetector.localHost(),
      }),
    );
    File(p.join(logs, 'launcher.log')).writeAsStringSync(
      '${start.add(const Duration(minutes: 1)).toIso8601String()} [ERROR] '
      '${LauncherLogFormat.uncaughtMessage(LauncherLogFormat.zoneError, StateError('x'))}\n',
    );
    final reports = controller(_CountingService(), logs: logs);
    // לא נראה עדיין: ההסבר החד-פעמי רוצה לעלות באותה עלייה.
    final notices = MemoryNoticesStore();
    final intro = stringsOf().errorReports.introDialogConfirm;
    final crash = stringsOf().appReports.crashTitle;

    var maxOpen = 0;
    var sawIntro = false;
    var sawCrash = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(shell(reports, notices));
      for (var i = 0; i < 80 && !(sawIntro && sawCrash); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        final introOpen = find.text(intro).evaluate().isNotEmpty;
        final crashOpen = find.byType(CrashPromptDialog).evaluate().isNotEmpty;
        final open = (introOpen ? 1 : 0) + (crashOpen ? 1 : 0);
        if (open > maxOpen) maxOpen = open;
        if (introOpen) {
          sawIntro = true;
          await tester.tap(find.text(intro));
          await tester.pump();
        }
        if (crashOpen) {
          sawCrash = true;
          expect(find.text(crash), findsOneWidget);
        }
      }
      // המסך טוען ברקע (קטלוג התוספים, תור הדיווחים) בקבצים אמיתיים: ממתינים
      // שיסתיימו *לפני* ההשמדה, אחרת ה-controller משתמש בעצמו אחרי dispose.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    expect(sawIntro, isTrue);
    expect(sawCrash, isTrue);
    expect(maxOpen, 1);
  });

  group('ההצעה אחרי קריסה ממתינה לדיאלוג פתוח', () {
    /// מחליף את הזיהוי האמיתי: ההצעה מתבקשת מיד אחרי ש-[release] מושלם.
    _PromptingController promptingController() => _PromptingController(
          service: _CountingService(),
          collector: _Collector(),
          settings: settings,
          logsDirectory: '',
          redactor: AppReportRedactor(environment: const {}),
        );

    Future<void> openBlocker(WidgetTester tester) async {
      unawaited(showDialog<void>(
        context: tester.element(find.byType(HomeScreen)),
        builder: (_) => const AlertDialog(title: Text('חוסם')),
      ));
      await tester.pump();
      expect(find.text('חוסם'), findsOneWidget);
    }

    testWidgets('מעבר לדקה לא מוותר, והיא מופיעה כשהדיאלוג נסגר',
        (tester) async {
      useViewSize(tester, const Size(1400, 1000));
      final reports = promptingController();
      await tester.pumpWidget(
        shell(
          reports,
          MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
        ),
      );
      await tester.pump();
      await openBlocker(tester);

      reports.release.complete();
      // יותר מ-120 המתנות של חצי שנייה — מה שהיה מוותר קודם.
      await tester.pump(const Duration(seconds: 90));
      expect(reports.shown, isNull, reason: 'עדיין ממתינה');
      expect(find.byType(CrashPromptDialog), findsNothing);

      Navigator.of(tester.element(find.byType(HomeScreen))).pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CrashPromptDialog), findsOneWidget);
      expect(reports.shown, isNull, reason: 'הדיאלוג פתוח, ה-future ממתין');
    });

    testWidgets('השמדת המסגרת באמצע ההמתנה מבטלת אותה, בלי טיימר תלוי',
        (tester) async {
      useViewSize(tester, const Size(1400, 1000));
      final reports = promptingController();
      await tester.pumpWidget(
        shell(
          reports,
          MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
        ),
      );
      await tester.pump();
      await openBlocker(tester);
      reports.release.complete();
      await tester.pump(const Duration(seconds: 2));
      expect(reports.shown, isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(reports.shown, isFalse);
      // טיימר שנשאר תלוי היה מפיל את הבדיקה בסיומה.
    });
  });
}

class _PromptingController extends AppReportsController {
  _PromptingController({
    required super.service,
    required super.collector,
    required super.settings,
    required super.logsDirectory,
    required super.redactor,
  });

  final Completer<void> release = Completer<void>();
  bool? shown;

  @override
  Future<CrashReportOutcome?> runCrashCheck({
    required Future<bool> Function(CrashCandidate candidate) showPrompt,
  }) async {
    await release.future;
    shown = await showPrompt(
      CrashCandidate(
        previousSession: SessionLock(
          pid: 1,
          version: '0.24',
          startedAt: DateTime.utc(2026, 10, 1),
        ),
        entries: const [],
        signature: null,
        hasStartupStall: false,
      ),
    );
    return CrashReportOutcome.prompted;
  }
}
