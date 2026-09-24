// דיווחי הטעויות בלאנצ'ר: הדיאלוג בעלייה, כפתור ההעלאה בכרטיס ההורדות,
// ההסבר לפני יותר ממנה אחת, ועצירה והמשך. בלי `dart:io` ובלי רשת — התיבה
// בזיכרון, התור של אוצריא מזויף והשרת `MockClient`.

import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/error_reports_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/error_reports_flow.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';

Map<String, dynamic> _report(String id) => OutboxReport.fileJson(
      reportId: id,
      bookTitle: 'ספר',
      createdAt: '2026-09-01T10:00:00Z',
      body: {'report_id': id},
    );

class _MemoryOutbox implements ReportOutbox {
  final reports = <OutboxReport>[];

  void add(String id) =>
      reports.add(OutboxReport.fromJson(_report(id), filePath: id));

  @override
  Future<List<OutboxReport>> list() async => List.of(reports);

  @override
  Future<void> remove(OutboxReport report) async =>
      reports.removeWhere((r) => r.reportId == report.reportId);

  @override
  Future<void> write(String reportId, Map<String, dynamic> fileJson) async {
    await discard(reportId);
    reports.add(OutboxReport.fromJson(fileJson, filePath: reportId));
  }

  @override
  Future<void> discard(String reportId) async =>
      reports.removeWhere((r) => r.reportId == reportId);
}

/// התור של אוצריא בזיכרון: [pendingCount] דיווחים, ו-[partialError] מדמה
/// שורה אחת שלא הועברה.
class _FakeQueue implements OtzariaReportQueue {
  _FakeQueue(this.pendingCount, {this.partialError});

  final int pendingCount;
  final String? partialError;

  @override
  Future<int> countSendable() async => pendingCount;

  @override
  Future<QueueCollectResult> collectTo(ReportOutbox outbox) async {
    for (var i = 0; i < pendingCount; i++) {
      await outbox.write('new$i', _report('new$i'));
    }
    return (collected: pendingCount, error: partialError);
  }
}

void main() {
  final t = stringsOf().errorReports;
  late _MemoryOutbox outbox;
  late DateTime now;

  setUp(() {
    outbox = _MemoryOutbox();
    now = DateTime.utc(2026, 9, 1);
  });

  ErrorReportsController controller({
    int pending = 0,
    String? partialError,
    http.Client? client,
    ReportDelay? delay,
  }) =>
      ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async =>
            _FakeQueue(pending, partialError: partialError),
        uploader: ErrorReportUploader(
          httpClient:
              client ?? MockClient((_) async => http.Response('{}', 200)),
          // המתנה אמיתית בתוך ה-fake-async: `pump` מקדם אותה, והשעון איתה.
          delay: delay ??
              (d) async {
                await Future<void>.delayed(d);
                now = now.add(d);
              },
          clock: () => now,
        ),
      );

  /// מארח מינימלי שמחזיק `BuildContext` תחת ה-Navigator, כדי להפעיל את הזרימות.
  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext ctx;
    await pumpScreen(
      tester,
      Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.shrink();
      })),
    );
    return ctx;
  }

  /// אוצריא "פתוחה" לפי [running], שהבדיקה יכולה להפוך באמצע.
  var running = false;
  Future<ReportOfferOutcome> offer(
    BuildContext ctx,
    ErrorReportsController c, {
    bool readOnly = false,
  }) =>
      offerErrorReportCollection(
        ctx,
        c,
        readOnly: readOnly,
        isOtzariaRunning: () async => running,
      );

  setUp(() => running = false);

  group('איסוף בעלייה', () {
    testWidgets('אוצריא פתוחה → אין דיאלוג, וההצעה לא "נוצלה"', (tester) async {
      final c = controller(pending: 2);
      final ctx = await host(tester);
      running = true;
      unawaited(offer(ctx, c));
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);

      // אחרי שנסגרה — ההצעה עדיין עומדת.
      running = false;
      unawaited(offer(ctx, c));
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsOneWidget);
    });

    testWidgets('כונן לקריאה בלבד → אין דיאלוג', (tester) async {
      final c = controller(pending: 2);
      final ctx = await host(tester);
      unawaited(offer(ctx, c, readOnly: true));
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);
    });

    testWidgets('אוצריא נפתחה בזמן שהדיאלוג חיכה → לא אוספים', (tester) async {
      final c = controller(pending: 2);
      final ctx = await host(tester);
      late ReportOfferOutcome outcome;
      unawaited(offer(ctx, c).then((o) => outcome = o));
      await tester.pumpAndSettle();
      running = true;
      await tester.tap(find.text(t.collectConfirm));
      await tester.pumpAndSettle();
      expect(outcome, ReportOfferOutcome.otzariaOpened);
      expect(outbox.reports, isEmpty);
    });

    testWidgets('N>0 → דיאלוג, ו"איסוף" מביא את הדיווחים לתיבה',
        (tester) async {
      final c = controller(pending: 3);
      final ctx = await host(tester);
      unawaited(offer(ctx, c));
      await tester.pumpAndSettle();

      expect(find.text(t.collectDialogTitle), findsOneWidget);
      expect(find.text(t.collectDialogContent(3)), findsOneWidget);
      await tester.tap(find.text(t.collectConfirm));
      await tester.pumpAndSettle();

      expect(outbox.reports, hasLength(3));
      expect(c.outboxCount, 3);
    });

    testWidgets('0 ממתינים → אין דיאלוג', (tester) async {
      final c = controller(pending: 0);
      final ctx = await host(tester);
      unawaited(offer(ctx, c));
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);
    });

    testWidgets('"לא עכשיו" — ולא שואלים שוב באותה הרצה', (tester) async {
      final c = controller(pending: 2);
      final ctx = await host(tester);
      unawaited(offer(ctx, c));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.collectLater));
      await tester.pumpAndSettle();
      expect(outbox.reports, isEmpty);

      unawaited(offer(ctx, c));
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);
    });
  });

  group('כפתור ההעלאה בכרטיס ההורדות', () {
    late Directory tempDir;
    late OtzariaModuleController otzaria;
    late LibraryModuleController library;
    late PluginsModuleController plugins;
    late LauncherUpdateController launcherUpdate;
    late SettingsController settings;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('error_reports_test');
      otzaria = OtzariaModuleController(dataDir: tempDir.path);
      library = LibraryModuleController(dataDir: tempDir.path);
      plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
      launcherUpdate = LauncherUpdateController(dataDir: tempDir.path);
      settings = SettingsController(dataDir: tempDir.path);
    });

    tearDown(() {
      otzaria.dispose();
      library.dispose();
      plugins.dispose();
      launcherUpdate.dispose();
      settings.dispose();
      tempDir.deleteSync(recursive: true);
    });

    HomeScreen home(
      ErrorReportsController reports, {
      bool readOnly = false,
      Future<void> Function()? onUpload,
    }) =>
        HomeScreen(
          readOnly: readOnly,
          otzaria: otzaria,
          library: library,
          plugins: plugins,
          launcherUpdate: launcherUpdate,
          settings: settings,
          otzariaIsRunning: false,
          onCloseOtzaria: () async => true,
          isDownloading: false,
          isCancellingDownload: false,
          isCheckingOnline: false,
          longTaskRunning: false,
          onProcessStateChanged: () async => false,
          onCheckOnline: () async {},
          onDownloadAll: () async {},
          onCancelDownload: () async {},
          onDownloadLauncherUpdate: () async {},
          onInstallLauncherUpdate: () async {},
          onRequestReindex: () async {},
          onGoToOtzaria: () {},
          onGoToLibrary: () {},
          errorReports: reports,
          onUploadErrorReports: onUpload ?? () async {},
        );

    testWidgets('מופיע רק כשיש דיווחים בתיבה', (tester) async {
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c));
      expect(find.textContaining(t.uploadButton(0)), findsNothing);

      outbox
        ..add('a')
        ..add('b');
      await c.refreshOutbox();
      await tester.pump();
      expect(find.text(t.uploadButton(2)), findsOneWidget);
    });

    testWidgets('לא מופיע כשהכונן לקריאה בלבד', (tester) async {
      outbox.add('a');
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c, readOnly: true));
      expect(find.text(t.uploadButton(1)), findsNothing);
    });

    testWidgets('יותר מ-8 → הסבר קודם; עצירה בהמתנה, והמשך מהמקום',
        (tester) async {
      for (var i = 0; i < 10; i++) {
        outbox.add('r$i');
      }
      final c = controller();
      await c.refreshOutbox();
      late BuildContext ctx;
      await pumpScreen(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return home(c, onUpload: () => uploadErrorReports(ctx, c));
        }),
      );

      await tester.tap(find.text(t.uploadButton(10)));
      await tester.pumpAndSettle();
      final minutes = c.estimateMinutes(10);
      expect(
          find.text(t.uploadLongDialogContent(10, 8, minutes)), findsOneWidget);
      await tester.tap(find.text(t.uploadLongDialogConfirm));
      await tester.pump();
      await tester.pump();

      // המנה הראשונה נשלחה, ועכשיו ממתינים לשרת — עם ספירה לאחור.
      expect(outbox.reports, hasLength(2));
      expect(c.isUploading, isTrue);
      expect(find.textContaining(t.uploadWaitingStage(65)), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(t.uploadWaitingStage(64)), findsOneWidget);

      await tester.tap(find.text(t.uploadStopButton));
      await tester.pump();
      await tester.pump();
      expect(c.isUploading, isFalse);
      expect(outbox.reports, hasLength(2));
      expect(find.text(t.uploadButton(2)), findsOneWidget);

      // המשך אחרי שהחלון נסגר: שניים ≤ 8, ולכן בלי דיאלוג.
      now = now.add(const Duration(minutes: 2));
      await tester.tap(find.text(t.uploadButton(2)));
      await tester.pump();
      await tester.pump();
      expect(find.text(t.uploadLongDialogTitle), findsNothing);
      expect(outbox.reports, isEmpty);
      expect(find.textContaining(t.uploadButton(0)), findsNothing);
      // ההמתנה שננטשה בעצירה עוד תלויה בשעון המזויף.
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('הבקר', () {
    group('איתור התור', () {
      late Directory temp;
      late String dataRoot;
      late String launch;
      setUp(() {
        temp = Directory.systemTemp.createTempSync('report_queue_locate');
        // אוצריא ניידת: שורש הנתונים ליד ה-exe, בלי תלות במשתני הסביבה.
        final exeDir = p.join(temp.path, 'otzaria');
        launch = p.join(exeDir, 'otzaria.exe');
        File(launch).createSync(recursive: true);
        File(p.join(exeDir, 'portable.marker')).createSync();
        dataRoot = p.join(exeDir, 'otzaria_data');
      });
      tearDown(() => temp.deleteSync(recursive: true));

      Future<OtzariaReportQueue?> resolve() =>
          ErrorReportsController.resolveOtzariaReportQueue(
            launchPath: launch,
            locator: LibraryDbLocator(
              stateStore: LibraryStateStore(p.join(temp.path, 's.json')),
            ),
          );

      test('user_state.db תחת <dataRoot>/databases נמצא', () async {
        File(p.join(dataRoot, 'databases', 'user_state.db'))
            .createSync(recursive: true);
        final queue = await resolve();
        expect(queue, isA<UserStateReportQueue>());
        expect((queue! as UserStateReportQueue).dbPath,
            p.join(dataRoot, 'databases', 'user_state.db'));
      });

      test('התור עדיין ב-Hive (לא הועבר) — לא נוגעים', () async {
        File(p.join(dataRoot, 'databases', 'user_state.db'))
            .createSync(recursive: true);
        File(p.join(dataRoot, 'error_reports_queue.hive')).createSync();
        expect(await resolve(), isNull);
      });

      test('אין מסד — null, ושום תיקייה אינה נוצרת', () async {
        expect(await resolve(), isNull);
        expect(Directory(dataRoot).existsSync(), isFalse);
      });
    });

    test('כשל חלקי באיסוף — מה שהועבר נספר, והשגיאה נמסרת', () async {
      final c = controller(pending: 2, partialError: 'partial');
      await c.pendingToOffer();
      final outcome = await c.collect();
      expect(outcome.collected, 2);
      expect(outcome.error, stringsOf().errorReportsDomain.someNotCollected);
      expect(c.outboxCount, 2);
      c.dispose();
    });

    test('סגירה באמצע העלאה: עוצרת, סוגרת את הלקוח ואינה מודיעה למת', () async {
      for (var i = 0; i < 10; i++) {
        outbox.add('r$i');
      }
      final client = _TrackingClient();
      // ההמתנה בין המנות לעולם אינה מסתיימת מעצמה — רק עצירה מוציאה ממנה.
      final c = controller(
        client: client,
        delay: (_) => Completer<void>().future,
      );
      var notified = 0;
      c.addListener(() => notified++);
      final upload = c.upload();
      while (!(c.progress?.isWaiting ?? false)) {
        await Future<void>.delayed(Duration.zero);
      }
      c.dispose();
      final result = await upload;
      final afterDispose = notified;
      await Future<void>.delayed(Duration.zero);

      expect(result?.cancelled, isTrue);
      expect(result?.sent, 8);
      expect(client.closed, isTrue);
      expect(notified, afterDispose);
    });

    test('תיבה שאינה נקראת (כונן נשלף) — תוצאה עם שגיאה, לא חריג', () async {
      final c = ErrorReportsController(
        outbox: _BrokenOutbox(),
        resolveQueue: () async => null,
        uploader: ErrorReportUploader(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      final result = await c.upload();
      expect(result?.error, isNotNull);
      expect(result?.total, 0);
      c.dispose();
    });
  });
}

class _TrackingClient extends MockClient {
  _TrackingClient() : super((_) async => http.Response('{}', 200));

  var closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _BrokenOutbox implements ReportOutbox {
  @override
  Future<List<OutboxReport>> list() async =>
      throw const FileSystemException('drive removed');

  @override
  Future<void> remove(OutboxReport report) async {}

  @override
  Future<void> write(String reportId, Map<String, dynamic> fileJson) async {}

  @override
  Future<void> discard(String reportId) async {}
}
