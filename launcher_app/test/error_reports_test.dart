// דיווחי הטעויות בלאנצ'ר: הדיאלוג בעלייה, כפתור ההעלאה בכרטיס ההורדות,
// ההסבר לפני יותר ממנה אחת, ועצירה והמשך. בלי `dart:io` ובלי רשת — התיבה
// בזיכרון, התור של אוצריא מזויף והשרת `MockClient`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/error_reports_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/search_feedback_controller.dart';
import 'package:launcher_app/src/screens/error_reports_flow.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/reports_upload_flow.dart';
import 'package:launcher_app/src/screens/reports_upload_section.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/services/report_offer_trigger.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'test_harness.dart';
import 'test_support.dart';

Map<String, dynamic> _report(String id) => OutboxReport.fileJson(
      reportId: id,
      bookTitle: 'ספר',
      createdAt: '2026-09-01T10:00:00Z',
      body: {'report_id': id},
    );

// box של hive_ce 2.20.2 עם שני דיווחים ב-pending_reports ואחד ב-sent_reports.
final _hiveWithPending = base64.decode(
  'UQAAAAEPcGVuZGluZ19yZXBvcnRzCgIAAAALAgAAAAQCAAAAaWQEAQAAAHgEAQAAAG4BAAAAAAAA'
  '8D8LAQAAAAQCAAAAaWQEAQAAAHmDJV/vLQAAAAEMc2VudF9yZXBvcnRzCgEAAAALAQAAAAQCAAAA'
  'aWQEAQAAAHrN8gho',
);
const _hiveSentOnly =
    'LQAAAAEMc2VudF9yZXBvcnRzCgEAAAALAQAAAAQCAAAAaWQEAQAAAHFFK9r/';

class _MemoryOutbox implements ReportOutbox {
  final reports = <OutboxReport>[];
  Future<void> Function()? beforeList;

  void add(String id) =>
      reports.add(OutboxReport.fromJson(_report(id), filePath: id));

  @override
  Future<List<OutboxReport>> list() async {
    await beforeList?.call();
    return List.of(reports);
  }

  @override
  Future<int> count() async {
    await beforeList?.call();
    return reports.length;
  }

  @override
  Future<Uint8List> requestBody(OutboxReport report) async =>
      OutboxReport.requestBodyOf(_report(report.reportId));

  @override
  Future<void> remove(OutboxReport report) async =>
      reports.removeWhere((r) => r.reportId == report.reportId);

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {
    await discard(reportId);
    reports.add(OutboxReport.fromJson(
      jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>,
      filePath: reportId,
    ));
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
      await outbox.write('new$i', OutboxReport.encodeFile(_report('new$i')));
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
          httpClient: client ??
              MockClient((_) async => http.Response('{"success":true}', 200)),
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

  group('הסבר חד-פעמי על הדיווחים', () {
    const key = NoticesSeenStore.errorReportsIntro;

    testWidgets('בהרצה הראשונה מופיע, ו"הבנתי" רושם שהוצג', (tester) async {
      final store = MemoryNoticesStore();
      final ctx = await host(tester);
      unawaited(showErrorReportsIntroOnce(ctx, store));
      await tester.pumpAndSettle();

      expect(find.text(t.introDialogTitle), findsOneWidget);
      expect(find.text(t.introDialogContent), findsOneWidget);
      // עוד לא נסגר — עוד לא נרשם.
      expect(store.marked, isEmpty);

      await tester.tap(find.text(t.introDialogConfirm));
      await tester.pumpAndSettle();

      expect(find.text(t.introDialogTitle), findsNothing);
      expect(store.marked, [key]);
    });

    testWidgets('Esc נחשב "נראה"', (tester) async {
      final store = MemoryNoticesStore();
      final ctx = await host(tester);
      unawaited(showErrorReportsIntroOnce(ctx, store));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text(t.introDialogTitle), findsNothing);
      expect(store.marked, [key]);
    });

    testWidgets('פעם אחת בלבד: מי שכבר ראה לא רואה שוב', (tester) async {
      final store = MemoryNoticesStore();
      final ctx = await host(tester);
      unawaited(showErrorReportsIntroOnce(ctx, store));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.introDialogConfirm));
      await tester.pumpAndSettle();

      late bool shownAgain;
      unawaited(
        showErrorReportsIntroOnce(ctx, store).then((v) => shownAgain = v),
      );
      await tester.pumpAndSettle();

      expect(shownAgain, isFalse);
      expect(find.text(t.introDialogTitle), findsNothing);
    });

    testWidgets('הודעה שכבר נרשמה במחשב הזה אינה מופיעה', (tester) async {
      final ctx = await host(tester);
      unawaited(
        showErrorReportsIntroOnce(ctx, MemoryNoticesStore(seen: {key})),
      );
      await tester.pumpAndSettle();

      expect(find.text(t.introDialogTitle), findsNothing);
    });

    testWidgets('כונן לקריאה בלבד: מופיע בנוסח שאומר שאי אפשר לאסוף',
        (tester) async {
      final store = MemoryNoticesStore();
      final ctx = await host(tester);
      unawaited(showErrorReportsIntroOnce(ctx, store, readOnly: true));
      await tester.pumpAndSettle();

      expect(find.text(t.introDialogContentReadOnly), findsOneWidget);
      expect(find.text(t.introDialogContent), findsNothing);
      await tester.tap(find.text(t.introDialogConfirm));
      await tester.pumpAndSettle();
      expect(store.marked, [key]);
    });

    testWidgets('כונן מלא: מופיע בנוסח שמבקש לפנות מקום ולא בנוסח הנעילה',
        (tester) async {
      final store = MemoryNoticesStore();
      final ctx = await host(tester);
      unawaited(
        showErrorReportsIntroOnce(ctx, store, readOnly: true, driveFull: true),
      );
      await tester.pumpAndSettle();

      expect(find.text(t.introDialogContentReadOnlyDriveFull), findsOneWidget);
      expect(find.text(t.introDialogContentReadOnly), findsNothing);
      expect(find.text(t.introDialogContent), findsNothing);
      await tester.tap(find.text(t.introDialogConfirm));
      await tester.pumpAndSettle();
      expect(store.marked, [key]);
    });

    testWidgets('אי אפשר להציג עכשיו → לא מוצג ולא נרשם', (tester) async {
      final store = MemoryNoticesStore();
      final ctx = await host(tester);
      late bool shown;
      unawaited(
        showErrorReportsIntroOnce(
          ctx,
          store,
          waitUntilFree: () async => false,
        ).then((v) => shown = v),
      );
      await tester.pumpAndSettle();

      expect(shown, isFalse);
      expect(find.text(t.introDialogTitle), findsNothing);
      expect(store.marked, isEmpty);
    });

    testWidgets('הנוסח באנגלית קיים ושונה מהעברי', (tester) async {
      final en = stringsOf(AppLanguage.english).errorReports;

      expect(en.introDialogTitle, isNotEmpty);
      expect(en.introDialogContent, isNot(t.introDialogContent));
      expect(en.introDialogContentReadOnly, isNot(en.introDialogContent));
      expect(
        en.introDialogContentReadOnlyDriveFull,
        isNot(en.introDialogContentReadOnly),
      );
    });
  });

  group('הצעה מחדש אחרי סגירת אוצריא', () {
    testWidgets('נפתחה בעלייה ונסגרה אחר כך → ההצעה מופיעה', (tester) async {
      final c = controller(pending: 2);
      final ctx = await host(tester);
      final trigger = ReportOfferTrigger(() async {
        await offer(ctx, c);
      });

      running = true;
      trigger.onRunningState(running: true);
      await trigger.request();
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);

      running = false;
      trigger.onRunningState(running: false);
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsOneWidget);
    });

    testWidgets('אוצריא שנפתחה ונסגרה במהלך ההרצה → דיווחים חדשים מוצעים',
        (tester) async {
      var pending = 0;
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(pending),
      );
      final ctx = await host(tester);
      final trigger = ReportOfferTrigger(() async {
        await offer(ctx, c);
      });

      await trigger.request();
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);

      running = true;
      trigger.onRunningState(running: true);
      pending = 2;
      running = false;
      trigger.onRunningState(running: false);
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogContent(2)), findsOneWidget);
    });

    testWidgets('מי שסירב לא נשאל שוב על אותם דיווחים, אבל כן על חדשים',
        (tester) async {
      var pending = 2;
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(pending),
      );
      final ctx = await host(tester);
      final trigger = ReportOfferTrigger(() async {
        await offer(ctx, c);
      });

      unawaited(trigger.request());
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.collectLater));
      await tester.pumpAndSettle();

      trigger.onRunningState(running: true);
      trigger.onRunningState(running: false);
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsNothing);

      pending = 3;
      trigger.onRunningState(running: true);
      trigger.onRunningState(running: false);
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogContent(3)), findsOneWidget);
    });

    test('בקשה שמגיעה באמצע הצעה רצה שוב אחריה, בלי להיערם', () async {
      final gate = Completer<void>();
      var runs = 0;
      final trigger = ReportOfferTrigger(() async {
        runs++;
        if (runs == 1) await gate.future;
      });

      final first = trigger.request();
      await trigger.request();
      await trigger.request();
      expect(runs, 1);
      gate.complete();
      await first;
      expect(runs, 2);
    });

    test('בזמן העלאה או איסוף אין הצעה, ואיסוף והעלאה אינם חופפים', () async {
      final c = controller(pending: 2);
      expect(await c.pendingToOffer(), 2);

      c.isUploading = true;
      expect(await c.pendingToOffer(), 0);
      expect((await c.collect()).collected, 0);
      expect(outbox.reports, isEmpty);
      c.isUploading = false;

      c.isCollecting = true;
      expect(await c.pendingToOffer(), 0);
      outbox.add('a');
      expect(await c.upload(), isNull);
      expect(outbox.reports, hasLength(1));
      c.isCollecting = false;

      expect(await c.pendingToOffer(), 2);
    });
    test('ספירה אחרי ספירה: הצעה שלא נענתה אינה נצרכת', () async {
      final c = controller(pending: 2);
      expect(await c.pendingToOffer(), 2);
      expect(await c.pendingToOffer(), 2);
      c.markDeclined(2);
      expect(await c.pendingToOffer(), 0);
    });

    test('הצעה שנדחתה בזמן משימה ארוכה רצה מחדש כשהיא מסתיימת', () async {
      var busy = true;
      var runs = 0;
      final trigger =
          ReportOfferTrigger(() async => runs++, isBusy: () => busy);

      trigger.onRunningState(running: true);
      trigger.onRunningState(running: false);
      await Future<void>.delayed(Duration.zero);
      expect(runs, 0);

      trigger.resume();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 0);

      busy = false;
      trigger.resume();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 1);

      trigger.resume();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 1);
    });

    test('הצעה שהוכרזה כדחויה מבפנים רצה מחדש ב-resume', () async {
      var runs = 0;
      late ReportOfferTrigger trigger;
      const busy = false;
      trigger = ReportOfferTrigger(() async {
        runs++;
        if (runs == 1) trigger.defer();
      }, isBusy: () => busy);

      await trigger.request();
      expect(runs, 1);
      trigger.resume();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 2);
    });

    test('סירוב נשמר גם כשחלק מהדיווחים כבר אינם בתור', () async {
      var pending = 5;
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(pending),
      );
      c.markDeclined(5);
      expect(await c.pendingToOffer(), 0);
      pending = 2;
      expect(await c.pendingToOffer(), 0);
      pending = 3;
      expect(await c.pendingToOffer(), 0);
    });
  });

  test('דיווח בודד בעברית בלשון יחיד', () {
    expect(t.uploadButton(1), contains('1 דיווח '));
    expect(t.uploadPendingOffline(1), contains('1 דיווח.'));
    expect(t.uploadPendingUnchecked(1), contains('1 דיווח.'));
    expect(t.uploadSummary(1, 0, 0), 'נשלח 1 דיווח');
    expect(t.uploadButton(3), contains('3 דיווחים'));
  });

  test('ניסוח יחיד בעברית: פועל וספירה', () {
    expect(t.uploadPendingOffline(1), startsWith('ממתין להעלאה 1 דיווח'));
    expect(t.uploadPendingOffline(2), startsWith('ממתינים להעלאה 2 דיווחים'));
    final library = stringsOf().libraryDomain;
    expect(
      library.semanticFeedbackUploaded(1, 1),
      'נשלחה 1 רשומת נתוני אימון; נשארה 1 בכונן',
    );
    expect(
      library.semanticFeedbackUploaded(2, 3),
      'נשלחו 2 רשומות נתוני אימון; נשארו 3 בכונן',
    );
    expect(
      library.semanticFeedbackCollected(1),
      'נאספה 1 רשומת נתוני אימון לכונן',
    );
  });

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
    ReportsUploadOutcome? outcome;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('error_reports_test');
      otzaria = OtzariaModuleController(dataDir: tempDir.path);
      library = LibraryModuleController(dataDir: tempDir.path);
      plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
      launcherUpdate = LauncherUpdateController(dataDir: tempDir.path);
      settings = SettingsController(dataDir: tempDir.path);
      outcome = null;
      otzaria.onlineCheckedAt = DateTime.utc(2026, 9, 1);
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
      SearchFeedbackController? feedback,
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
          searchFeedback: feedback,
          isUploadingReports: false,
          onUploadReports: onUpload ?? () async {},
        );

    testWidgets('כפתור אחד מעלה את שני הסוגים, והכמות בו היא הסכום',
        (tester) async {
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      outbox
        ..add('a')
        ..add('b');
      final transport = _CountFeedback(carried: 3);
      final feedback = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
      );
      addTearDown(feedback.dispose);
      final c = controller();
      await c.refreshOutbox();
      await feedback.refreshOutbox();
      final libraryT = stringsOf().libraryDomain;
      late BuildContext ctx;
      await pumpScreen(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return home(
            c,
            feedback: feedback,
            onUpload: () async => outcome = await uploadAllReports(
              ctx,
              errorReports: c,
              searchFeedback: feedback,
            ),
          );
        }),
      );

      expect(find.text(t.uploadButton(5)), findsOneWidget);
      expect(find.text(libraryT.semanticFeedbackUploadAction), findsNothing);
      expect(find.text(libraryT.semanticFeedbackUploadBody(3)), findsNothing);

      await tester.tap(find.text(t.uploadButton(5)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libraryT.semanticFeedbackUploadAction));
      await tester.pumpAndSettle();

      expect(outbox.reports, isEmpty);
      expect(transport.uploads, 1);
      debugPrint = originalPrint;
      expect(outcome?.severity, ReportsUploadSeverity.success);
      expect(printed, [
        'UiSnack ללא overlay: ${t.uploadSummary(2, 0, 0)}\n'
            '${libraryT.semanticFeedbackUploaded(3, 0)}',
      ]);
    });

    testWidgets('אין חיבור: נשאר הכיתוב בלבד, וכשהחיבור חוזר הכפתור מופיע',
        (tester) async {
      outbox
        ..add('a')
        ..add('b');
      final transport = _CountFeedback(carried: 1);
      final feedback = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
      );
      addTearDown(feedback.dispose);
      final c = controller();
      await c.refreshOutbox();
      await feedback.refreshOutbox();
      otzaria.onlineCheckError = 'no network';

      await pumpScreen(tester, home(c, feedback: feedback));
      expect(find.text(t.uploadPendingOffline(3)), findsOneWidget);
      expect(find.text(t.uploadButton(3)), findsNothing);

      otzaria.onlineCheckError = null;
      await pumpScreen(tester, home(c, feedback: feedback));
      expect(find.text(t.uploadPendingOffline(3)), findsNothing);
      expect(find.text(t.uploadButton(3)), findsOneWidget);
    });

    testWidgets('בלי בדיקה מקוונת מוצלחת אין כפתור', (tester) async {
      outbox.add('a');
      otzaria.onlineCheckedAt = null;
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c));
      expect(find.text(t.uploadPendingUnchecked(1)), findsOneWidget);
      expect(find.text(t.uploadButton(1)), findsNothing);
      expect(find.text(t.uploadPendingOffline(1)), findsNothing);
    });

    testWidgets('עצירה בין שלבי ההעלאה משאירה את המשוב בכונן', (tester) async {
      outbox.add('a');
      final c = controller();
      await c.refreshOutbox();
      final transport = _CountFeedback(carried: 2);
      final feedback = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
      );
      addTearDown(feedback.dispose);
      final gate = Completer<void>();
      outbox.beforeList =
          () => outbox.reports.isEmpty ? gate.future : Future<void>.value();
      var stopped = false;
      late BuildContext ctx;
      await pumpScreen(tester, Builder(builder: (context) {
        ctx = context;
        return ReportsUploadSection(
          errorReports: c,
          searchFeedback: feedback,
          connection: true,
          isUploadingAll: true,
          busy: false,
          onUpload: null,
          onStop: () => stopped = true,
        );
      }));
      final uploading = uploadAllReports(
        ctx,
        errorReports: c,
        searchFeedback: feedback,
        isCancelled: () => stopped,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
          find.text(stringsOf().libraryDomain.semanticFeedbackUploadAction));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.isUploading, isFalse);
      expect(feedback.isUploading, isFalse);
      await tester.tap(find.text(t.uploadStopButton));
      gate.complete();
      await tester.pump();
      final result = await uploading;
      expect(transport.uploads, 0);
      expect(transport.carried, 2);
      expect(result?.severity, ReportsUploadSeverity.info);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('רק בדיקת הלאנצ׳ר הצליחה: אפשר להעלות', (tester) async {
      outbox.add('a');
      otzaria.onlineCheckedAt = null;
      launcherUpdate.onlineCheckedAt = DateTime.utc(2026, 10, 13);
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c));
      expect(find.text(t.uploadButton(1)), findsOneWidget);
    });

    testWidgets('משוב שזורק: סיכום הדיווחים שהועלו נשמר', (tester) async {
      outbox.add('a');
      final transport = _CountFeedback(carried: 2, throwOnUpload: true);
      final feedback = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
      );
      addTearDown(feedback.dispose);
      final c = controller();
      await c.refreshOutbox();
      await feedback.refreshOutbox();
      final libraryT = stringsOf().libraryDomain;
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      late BuildContext ctx;
      await pumpScreen(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return home(
            c,
            feedback: feedback,
            onUpload: () async => outcome = await uploadAllReports(
              ctx,
              errorReports: c,
              searchFeedback: feedback,
            ),
          );
        }),
      );
      await tester.tap(find.text(t.uploadButton(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libraryT.semanticFeedbackUploadAction));
      await tester.pumpAndSettle();
      debugPrint = originalPrint;
      expect(outcome?.severity, ReportsUploadSeverity.error);

      expect(outbox.reports, isEmpty);
      expect(printed, [
        'UiSnack ללא overlay: ${t.uploadSummary(1, 0, 0)}\n'
            '${libraryT.semanticFeedbackFailed}',
      ]);
    });

    testWidgets('דיווחים שנכשלו: המשוב לא עולה, ונשאר בסיכום כממתין',
        (tester) async {
      outbox.add('a');
      final transport = _CountFeedback(carried: 2);
      final feedback = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
      );
      addTearDown(feedback.dispose);
      final c = controller(
        client: MockClient((_) async => http.Response('oops', 500)),
      );
      await c.refreshOutbox();
      await feedback.refreshOutbox();
      final libraryT = stringsOf().libraryDomain;
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      late BuildContext ctx;
      await pumpScreen(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return home(
            c,
            feedback: feedback,
            onUpload: () async => outcome = await uploadAllReports(
              ctx,
              errorReports: c,
              searchFeedback: feedback,
            ),
          );
        }),
      );
      await tester.tap(find.text(t.uploadButton(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libraryT.semanticFeedbackUploadAction));
      await tester.pumpAndSettle();
      debugPrint = originalPrint;
      expect(outcome?.severity, ReportsUploadSeverity.error);

      expect(transport.uploads, 0);
      expect(transport.carried, 2);
      expect(printed, hasLength(1));
      expect(printed.single, contains(libraryT.semanticFeedbackUploaded(0, 2)));
    });

    testWidgets('העלאת דיווחים שחזרה null אינה נספרת כהצלחה', (tester) async {
      outbox.add('a');
      final c = _NullUploadReports(
        outbox: outbox,
        resolveQueue: () async => null,
      );
      await c.refreshOutbox();
      final ctx = await host(tester);
      final result = await uploadAllReports(ctx, errorReports: c);

      expect(result?.severity, ReportsUploadSeverity.info);
      expect(result?.message, t.uploadCollectingBusy);
    });
    testWidgets('איסוף רץ: לחיצה על העלאה מודיעה ואינה מדלגת בשקט',
        (tester) async {
      final transport = _CountFeedback(carried: 2);
      final feedback = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
      )..isCollecting = true;
      addTearDown(feedback.dispose);
      final c = controller();
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      final ctx = await host(tester);
      await uploadAllReports(ctx, errorReports: c, searchFeedback: feedback);
      debugPrint = originalPrint;

      expect(transport.uploads, 0);
      expect(printed, ['UiSnack ללא overlay: ${t.uploadCollectingBusy}']);
    });
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
          return home(
            c,
            onUpload: () => uploadAllReports(ctx, errorReports: c),
          );
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

      Future<List<String>> unmigrated() =>
          ErrorReportsController.unmigratedLegacyReports(
            launchPath: launch,
            locator: LibraryDbLocator(
              stateStore: LibraryStateStore(p.join(temp.path, 's.json')),
            ),
          );

      void userStateDb({List<String> kinds = const []}) {
        final path = p.join(dataRoot, 'databases', 'user_state.db');
        Directory(p.dirname(path)).createSync(recursive: true);
        final db = sqlite3.open(path)
          ..execute(
            'CREATE TABLE pending_reports (id INTEGER PRIMARY KEY, '
            'kind TEXT NOT NULL, payload_json TEXT NOT NULL, '
            'created_at INTEGER NOT NULL)',
          );
        for (final kind in kinds) {
          db.execute(
            'INSERT INTO pending_reports (kind, payload_json, created_at) '
            "VALUES (?, '{}', 0)",
            [kind],
          );
        }
        db.close();
      }

      for (final box in [
        'error_reports_queue',
        'app_reports_queue',
        'plugin_reports_queue',
      ]) {
        test('$box.hive שנשאר אחרי ההעברה אינו חוסם את האיסוף', () async {
          userStateDb(kinds: ['$box/sent_reports']);
          File(p.join(dataRoot, '$box.hive'))
              .writeAsBytesSync(_hiveWithPending);

          expect(await resolve(), isA<UserStateReportQueue>());
          expect(await unmigrated(), isEmpty);
        });

        test('$box.hive ריק אינו נחשב תור שלא הועבר', () async {
          userStateDb();
          File(p.join(dataRoot, '$box.hive')).createSync();

          expect(await resolve(), isA<UserStateReportQueue>());
          expect(await unmigrated(), isEmpty);
        });

        test('$box.hive עם היסטוריה בלבד — אין הודעה', () async {
          userStateDb();
          File(p.join(dataRoot, '$box.hive'))
              .writeAsBytesSync(base64.decode(_hiveSentOnly));

          expect(await unmigrated(), isEmpty);
        });

        test(
            '$box.hive עם ממתינים ובלי שום שורה שלו במסד — מדווח, והאיסוף ממשיך',
            () async {
          userStateDb();
          File(p.join(dataRoot, '$box.hive'))
              .writeAsBytesSync(_hiveWithPending);

          expect(await resolve(), isA<UserStateReportQueue>());
          expect(await unmigrated(), [box]);
        });
      }

      test('reportsQueueFormat מ-otzaria_capabilities.json עובר לתור',
          () async {
        userStateDb();
        File(p.join(dataRoot, OtzariaCapabilities.fileName))
            .writeAsStringSync('{"formatVersion":1,"reportsQueueFormat":1}');

        final queue = await resolve() as UserStateReportQueue;

        expect(queue.reportsQueueFormat, 1);
      });

      test('בלי otzaria_capabilities.json — לפי user_version כמו קודם',
          () async {
        userStateDb();

        final queue = await resolve() as UserStateReportQueue;

        expect(queue.reportsQueueFormat, isNull);
      });

      test('אין מסד — null, ושום תיקייה אינה נוצרת', () async {
        expect(await resolve(), isNull);
        expect(Directory(dataRoot).existsSync(), isFalse);
      });
    });

    testWidgets('תורי Hive שלא הועברו — הודעה ברורה, ואחריה ההצעה לאסוף',
        (tester) async {
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(2),
        findUnmigratedLegacy: () async => ['error_reports_queue'],
      );
      addTearDown(c.dispose);
      final ctx = await host(tester);
      final notices = MemoryNoticesStore();

      unawaited(offerErrorReportCollection(
        ctx,
        c,
        isOtzariaRunning: () async => false,
        notices: notices,
      ));
      await tester.pumpAndSettle();
      expect(find.text(t.legacyReportsDialogTitle), findsOneWidget);
      expect(find.text(t.legacyReportsDialogContent), findsOneWidget);

      await tester.tap(find.text(t.introDialogConfirm));
      await tester.pumpAndSettle();
      expect(find.text(t.collectDialogTitle), findsOneWidget);
      expect(notices.marked, [NoticesSeenStore.legacyReportsNotice]);
    });

    testWidgets('הודעת ה-Hive הישן — פעם אחת בלבד במחשב', (tester) async {
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(0),
        findUnmigratedLegacy: () async => ['error_reports_queue'],
      );
      addTearDown(c.dispose);
      final ctx = await host(tester);

      unawaited(offerErrorReportCollection(
        ctx,
        c,
        isOtzariaRunning: () async => false,
        notices: MemoryNoticesStore(
          seen: {NoticesSeenStore.legacyReportsNotice},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(t.legacyReportsDialogTitle), findsNothing);
    });

    test('כל איסוף קורא מחדש את התור ואת היכולות של אוצריא', () async {
      var resolved = 0;
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async {
          resolved++;
          return _FakeQueue(resolved == 1 ? 1 : 0);
        },
      );
      addTearDown(c.dispose);

      expect(await c.pendingToOffer(), 1);
      expect((await c.collect()).collected, 0);
      expect(resolved, 2);
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
          httpClient:
              MockClient((_) async => http.Response('{"success":true}', 200)),
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
  _TrackingClient()
      : super((_) async => http.Response('{"success":true}', 200));

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
  Future<int> count() async => throw const FileSystemException('drive removed');

  @override
  Future<Uint8List> requestBody(OutboxReport report) async =>
      throw const FileSystemException('drive removed');

  @override
  Future<void> remove(OutboxReport report) async {}

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {}

  @override
  Future<void> discard(String reportId) async {}
}

class _CountFeedback extends SearchFeedbackTransport {
  _CountFeedback({required this.carried, this.throwOnUpload = false})
      : super('unused',
            client: MockClient((_) async => http.Response('{}', 200)));

  int carried;
  final bool throwOnUpload;
  int uploads = 0;

  @override
  Future<int> count() async => carried;

  @override
  Future<SearchFeedbackUploadResult> upload() async {
    uploads++;
    if (throwOnUpload) throw StateError('boom');
    final sent = carried;
    carried = 0;
    return (sent: sent, rejected: 0, remaining: 0);
  }
}

class _NullUploadReports extends ErrorReportsController {
  _NullUploadReports({required super.outbox, required super.resolveQueue});

  @override
  Future<ReportUploadResult?> upload() async => null;
}
