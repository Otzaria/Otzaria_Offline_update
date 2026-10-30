// דיווחי הטעויות בלאנצ'ר: דיאלוג האיסוף וכפתור ההעלאה שבדף הדיווחים,
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
import 'package:launcher_app/src/screens/error_reports_flow.dart';
import 'package:launcher_app/src/screens/home/home_page.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/screens/reports/reports_page.dart';
import 'package:launcher_app/src/screens/reports_upload_flow.dart';
import 'package:launcher_app/src/services/report_offer_trigger.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/home_guidance_session.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart'
    show ActionButton, AppDialog;
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'reports_page_finders.dart';
import 'test_harness.dart';

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
  Future<void> Function()? beforeCount;

  void add(String id) =>
      reports.add(OutboxReport.fromJson(_report(id), filePath: id));

  @override
  Future<List<OutboxReport>> list() async {
    return List.of(reports);
  }

  @override
  Future<int> count() async {
    await beforeCount?.call();
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

  setUp(() => running = false);

  // ההסבר הוא הודעה בבית ולא דיאלוג. "פעם במחשב" ו"נרשם רק אחרי הבנתי"
  // נבדקים בסשן (`app_session_test`) ובמסגרת (`app_shell_test`).
  group('הסבר חד-פעמי על הדיווחים — ההודעה בבית', () {
    HomeViewModel model({bool readOnly = false, bool driveFull = false}) =>
        HomeViewModel(
          guidance: deriveHomeGuidance(
            GuidanceFacts(
              readOnly: readOnly,
              driveFull: driveFull,
              online: false,
            ),
          ),
          reportsIntro: true,
        );

    /// בהודעה שבבית שתי הפסקאות של הדו-שיח מתחברות לאחת.
    String para(String text) => text.replaceAll('\n\n', ' ');

    testWidgets('מופיעה עם "הבנתי", והלחיצה מדווחת', (tester) async {
      var dismissed = 0;
      await pumpScreen(
        tester,
        HomePage(
          model: model(),
          actions: HomeActions(onDismissReportsIntro: () => dismissed++),
        ),
      );

      expect(find.text(t.introDialogTitle), findsOneWidget);
      expect(find.text(para(t.introDialogContent)), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text(t.introDialogConfirm));
      expect(dismissed, 1);
    });

    testWidgets('כונן לקריאה בלבד: בנוסח שאומר שאי אפשר לאסוף', (
      tester,
    ) async {
      await pumpScreen(tester, HomePage(model: model(readOnly: true)));

      expect(find.text(para(t.introDialogContentReadOnly)), findsOneWidget);
      expect(find.text(para(t.introDialogContent)), findsNothing);
    });

    testWidgets('כונן מלא: בנוסח שמבקש לפנות מקום ולא בנוסח הנעילה', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        HomePage(model: model(readOnly: true, driveFull: true)),
      );

      expect(
        find.text(para(t.introDialogContentReadOnlyDriveFull)),
        findsOneWidget,
      );
      expect(find.text(para(t.introDialogContentReadOnly)), findsNothing);
      expect(find.text(para(t.introDialogContent)), findsNothing);
    });

    test('הנוסח באנגלית קיים ושונה מהעברי', () {
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
    /// מה שהספירה מצאה בכל ריצה של הטריגר — רק כשאוצריא סגורה.
    ReportOfferTrigger counting(ErrorReportsController c, List<int> seen) =>
        ReportOfferTrigger(() async {
          if (!running) seen.add(await c.pendingToOffer());
        });

    test('נפתחה בעלייה ונסגרה אחר כך → נספר', () async {
      final c = controller(pending: 2);
      final seen = <int>[];
      final trigger = counting(c, seen);

      running = true;
      trigger.onRunningState(running: true);
      await trigger.request();
      expect(seen, isEmpty);

      running = false;
      trigger.onRunningState(running: false);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [2]);
    });

    test('אוצריא שנפתחה ונסגרה במהלך ההרצה → דיווחים חדשים נספרים', () async {
      var pending = 0;
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(pending),
      );
      final seen = <int>[];
      final trigger = counting(c, seen);

      await trigger.request();
      expect(seen, [0]);

      running = true;
      trigger.onRunningState(running: true);
      pending = 2;
      running = false;
      trigger.onRunningState(running: false);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [0, 2]);
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
  });

  test('דיווח בודד בעברית בלשון יחיד', () {
    final pages = stringsOf().pages;
    expect(pages.repWaitingTitle(1), '1 דיווח ממתין לשליחה');
    expect(pages.repStoredTitle(1), '1 דיווח שמור בכונן');
    expect(t.uploadSummary(1, 0, 0), 'נשלח 1 דיווח');
    expect(pages.repWaitingTitle(3), contains('3 דיווחים'));
  });

  test('ניסוח יחיד בעברית: פועל וספירה', () {
    final pages = stringsOf().pages;
    expect(pages.repWaitingTitle(1), startsWith('1 דיווח ממתין'));
    expect(pages.repWaitingTitle(2), startsWith('2 דיווחים ממתינים'));
  });

  group('איסוף לכונן מדף הדיווחים', () {
    Future<DriveCollectOutcome> collect(
      ErrorReportsController c, {
      bool readOnly = false,
      int disclosedReports = 1,
    }) =>
        collectReportsToDrive(
          c,
          readOnly: readOnly,
          isOtzariaRunning: () async => running,
          disclosedReports: disclosedReports,
        );

    List<String> captureSnacks() {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('UiSnack') ?? false) messages.add(message!);
      };
      addTearDown(() => debugPrint = previous);
      return messages;
    }

    testWidgets('collects immediately without a dialog', (tester) async {
      final queue = _QaQueue(2);
      final c = ErrorReportsController(
          outbox: outbox, resolveQueue: () async => queue);
      addTearDown(c.dispose);
      await host(tester);
      expect(await collect(c), DriveCollectOutcome.collected);
      await tester.pump();
      expect(find.byType(AppDialog), findsNothing);
      expect(queue.collections, 1);
      expect(outbox.reports, hasLength(2));
      await tester.pump(const Duration(seconds: 7));
    });

    test('empty reports never collect', () async {
      final c = controller();
      addTearDown(c.dispose);
      expect(await collect(c), DriveCollectOutcome.nothing);
      expect(outbox.reports, isEmpty);
    });

    test('new reports require an updated disclosure before collection',
        () async {
      final queue = _QaQueue(2);
      final c = ErrorReportsController(
          outbox: outbox, resolveQueue: () async => queue);
      addTearDown(c.dispose);
      final messages = captureSnacks();
      expect(await collect(c, disclosedReports: 0),
          DriveCollectOutcome.disclosureStale);
      expect(messages.single, contains(t.collectDisclosureRefreshedSnack));
      expect(queue.collections, 0);
      expect(outbox.reports, isEmpty);
      expect(
          await collect(c, disclosedReports: 2), DriveCollectOutcome.collected);
      expect(outbox.reports, hasLength(2));
    });

    for (final partial in [false, true]) {
      test('the collection summary covers reports only ($partial)', () async {
        final queue = _QaQueue(2, partial: partial);
        final c = ErrorReportsController(
            outbox: outbox, resolveQueue: () async => queue);
        addTearDown(c.dispose);
        final messages = captureSnacks();
        expect(await collect(c), DriveCollectOutcome.collected);
        expect(queue.pending, partial ? 1 : 0);
        expect(outbox.reports, hasLength(partial ? 1 : 2));
        expect(c.isCollecting, isFalse);
        expect(messages, hasLength(1));
        expect(
            messages.single,
            endsWith(partial
                ? t.collectPartialSnack(
                    1, stringsOf().errorReportsDomain.someNotCollected)
                : t.collectedSnack(2)));
      });
    }

    test('reopening Otzaria while counting prevents collection', () async {
      final queue = _QaQueue(2, onCount: () => running = true);
      final c = ErrorReportsController(
          outbox: outbox, resolveQueue: () async => queue);
      addTearDown(c.dispose);
      final messages = captureSnacks();
      expect(await collect(c), DriveCollectOutcome.otzariaOpen);
      expect(queue.collections, 0);
      expect(outbox.reports, isEmpty);
      expect(messages.single, contains(t.collectOtzariaOpenSnack));
    });

    for (final readOnly in [false, true]) {
      test('collection preserves the read-only guard ($readOnly)', () async {
        final c = controller(pending: 2);
        addTearDown(c.dispose);
        expect(
            await collect(c, readOnly: readOnly),
            readOnly
                ? DriveCollectOutcome.blocked
                : DriveCollectOutcome.collected);
        expect(outbox.reports, hasLength(readOnly ? 0 : 2));
      });
    }

    test('open Otzaria preserves reports for collection after closing',
        () async {
      final c = controller(pending: 2);
      addTearDown(c.dispose);
      final messages = captureSnacks();
      running = true;
      expect(await collect(c), DriveCollectOutcome.otzariaOpen);
      expect(outbox.reports, isEmpty);
      expect(messages, [contains(t.collectOtzariaOpenSnack)]);
      running = false;
      expect(await collect(c), DriveCollectOutcome.collected);
      expect(outbox.reports, hasLength(2));
    });

    testWidgets('legacy Hive notice does not interrupt collection',
        (tester) async {
      final c = ErrorReportsController(
        outbox: outbox,
        resolveQueue: () async => _FakeQueue(2),
        findUnmigratedLegacy: () async => ['error_reports_queue'],
      );
      addTearDown(c.dispose);
      await host(tester);
      final result = collect(c);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(await result, DriveCollectOutcome.collected);
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('הגילוי על הפרטיות לצד כפתור האיסוף', () {
    final g = stringsOf().guide;

    ReportsPage page({
      int reports = 0,
      bool busy = false,
      bool readOnly = false,
      VoidCallback? onCollect,
    }) =>
        ReportsPage(
          errorReports: null,
          connection: null,
          isUploadingAll: false,
          busy: busy,
          reportsToCollect: reports,
          onCollect: onCollect ?? () {},
          onUpload: null,
          readOnly: readOnly,
        );

    Finder inDisclosure(String text) => find.descendant(
          of: find.byKey(ShellKeys.reportsDisclosure),
          matching: find.text(text),
        );

    testWidgets('דיווחים: מה יועתק, בלי הצפנה, למי — מעל כפתור "איסוף לכונן"',
        (tester) async {
      var collected = 0;
      await pumpScreen(tester, page(reports: 2, onCollect: () => collected++));

      final button = find.byKey(ShellKeys.reportsCollect);
      expect(button, findsOneWidget);
      expect(find.text(g.reportsCollectButton), findsOneWidget);
      expect(
        find.text(g.reportsCollectTitle(reports: 2, searchRecords: 0)),
        findsOneWidget,
      );
      expect(inDisclosure(g.reportsDisclosureReports), findsOneWidget);
      expect(inDisclosure(g.reportsDisclosureStorage), findsOneWidget);
      // רשומות החיפוש — שורה נפרדת, רק כשיש כאלה.
      expect(find.text(g.reportsDisclosureSearch), findsNothing);
      expect(
        tester.getBottomLeft(find.byKey(ShellKeys.reportsDisclosure)).dy,
        lessThanOrEqualTo(tester.getTopLeft(button).dy),
      );

      await tester.tap(button);
      expect(collected, 1);
    });

    testWidgets('בלי כפתור אין גילוי, ובכונן מוגן אין אף אחד מהם', (
      tester,
    ) async {
      await pumpScreen(tester, page());
      expect(find.byKey(ShellKeys.reportsCollect), findsNothing);
      expect(find.byKey(ShellKeys.reportsDisclosure), findsNothing);

      await pumpScreen(tester, page(reports: 2, readOnly: true));
      expect(find.byKey(ShellKeys.reportsCollect), findsNothing);
      expect(find.byKey(ShellKeys.reportsDisclosure), findsNothing);
    });

    test('הנוסח שומר את מה שהדיאלוג הישן הבטיח', () {
      for (final strings in [
        AppL10n.stringsFor(AppLanguage.hebrew),
        AppL10n.stringsFor(AppLanguage.english),
      ]) {
        final guide = strings.guide;
        final he = strings == AppL10n.stringsFor(AppLanguage.hebrew);
        expect(guide.reportsDisclosureStorage,
            contains(he ? 'בלי הצפנה' : 'unencrypted'));
        expect(guide.reportsDisclosureStorage,
            contains(he ? 'מי שמחזיק בכונן' : 'anyone holding the drive'));
        expect(guide.reportsDisclosureReports,
            contains(he ? 'כתובת הדואר האלקטרוני' : 'email address'));
        expect(guide.reportsDisclosureReports,
            contains(he ? 'צילומי מסך' : 'screenshots'));
        expect(guide.reportsDisclosureReports,
            contains(he ? 'זיכרון התוכנה ברגע הקריסה' : 'app memory'));
        // רק תמונות אפשר לצרף, והפרטים הטכניים נוסעים עם הדיווח.
        expect(guide.reportsDisclosureReports,
            contains(he ? 'תמונות שצירפת' : 'images you attached'));
        expect(guide.reportsDisclosureReports,
            isNot(contains(he ? 'קבצים' : 'files')));
        expect(guide.reportsDisclosureReports,
            contains(he ? 'פרטים טכניים' : 'technical details'));
        expect(guide.reportsDisclosureSearch,
            contains(he ? 'מילות החיפוש' : 'search terms'));
        expect(guide.reportsDisclosureSearch,
            contains(he ? 'המפתח האנונימי' : 'anonymous key'));
      }
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

    ReportsPage home(
      ErrorReportsController reports, {
      bool readOnly = false,
      Future<void> Function()? onUpload,
      bool busy = false,
      bool? uploadBusy,
    }) =>
        ReportsPage(
          errorReports: reports,
          connection: connectionOf([
            (otzaria.onlineCheckedAt, otzaria.onlineCheckError),
            (library.onlineCheckedAt, library.onlineCheckError),
            (plugins.onlineCheckedAt, plugins.onlineCheckError),
            (launcherUpdate.onlineCheckedAt, launcherUpdate.onlineCheckError),
          ]),
          isUploadingAll: false,
          busy: busy,
          uploadBusy: uploadBusy,
          reportsToCollect: 0,
          onCollect: () {},
          onUpload: onUpload ?? () async {},
          readOnly: readOnly,
        );

    testWidgets('הכפתור מעלה את הדיווחים בלבד, והסיכום הוא שלהם בלבד',
        (tester) async {
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      outbox
        ..add('a')
        ..add('b');
      final c = controller();
      await c.refreshOutbox();
      late BuildContext ctx;
      await pumpScreen(
        tester,
        Builder(builder: (context) {
          ctx = context;
          return home(
            c,
            onUpload: () async =>
                outcome = await uploadAllReports(ctx, errorReports: c),
          );
        }),
      );

      expect(sendOffer(2), findsOneWidget);
      await tester.tap(sendOffer(2));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(outbox.reports, isEmpty);
      debugPrint = originalPrint;
      expect(outcome?.severity, ReportsUploadSeverity.success);
      expect(printed, ['UiSnack ללא overlay: ${t.uploadSummary(2, 0, 0)}']);
    });

    // הורדה או סנכרון תוספים השביתו את השליחה, אף שאינם נוגעים בתיבה.
    testWidgets('איסוף חסום (התקנה כאן) — השליחה פתוחה; חסימת שליחה סוגרת',
        (tester) async {
      outbox
        ..add('a')
        ..add('b');
      final c = controller();
      await c.refreshOutbox();
      var uploads = 0;

      await pumpScreen(
        tester,
        home(c, busy: true, uploadBusy: false, onUpload: () async => uploads++),
      );
      expect(sendOffer(2), findsOneWidget);
      expect(find.text(stringsOf().pages.pageBusyNote), findsNothing);
      await tester.tap(sendOffer(2));
      expect(uploads, 1);

      await pumpScreen(tester, home(c, uploadBusy: true));
      expect(
        tester.widget<ActionButton>(sendOffer(2)).onPressed,
        isNull,
      );
      expect(find.text(stringsOf().pages.pageBusyNote), findsOneWidget);
    });

    testWidgets('אין חיבור: נשאר הכיתוב בלבד, וכשהחיבור חוזר הכפתור מופיע',
        (tester) async {
      outbox
        ..add('a')
        ..add('b');
      final c = controller();
      await c.refreshOutbox();
      otzaria.onlineCheckError = 'no network';

      await pumpScreen(tester, home(c));
      expect(storedOffline(2), findsOneWidget);
      expect(sendOffer(2), findsNothing);

      otzaria.onlineCheckError = null;
      await pumpScreen(tester, home(c));
      expect(storedOffline(2), findsNothing);
      expect(sendOffer(2), findsOneWidget);
    });

    testWidgets('בלי בדיקה מקוונת מוצלחת אין כפתור', (tester) async {
      outbox.add('a');
      otzaria.onlineCheckedAt = null;
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c));
      expect(storedUnchecked(1), findsOneWidget);
      expect(sendOffer(1), findsNothing);
      expect(storedOffline(1), findsNothing);
    });

    testWidgets('רק בדיקת הלאנצ׳ר הצליחה: אפשר להעלות', (tester) async {
      outbox.add('a');
      otzaria.onlineCheckedAt = null;
      launcherUpdate.onlineCheckedAt = DateTime.utc(2026, 10, 13);
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c));
      expect(sendOffer(1), findsOneWidget);
    });

    testWidgets('העלאה שנכשלה: שגיאה אחת, בלי שורות נוספות', (tester) async {
      outbox.add('a');
      final c = controller(
        client: MockClient((_) async => http.Response('oops', 500)),
      );
      await c.refreshOutbox();
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      final ctx = await host(tester);
      final result = await uploadAllReports(ctx, errorReports: c);
      await tester.pumpAndSettle();
      debugPrint = originalPrint;

      expect(result?.severity, ReportsUploadSeverity.error);
      expect(outbox.reports, hasLength(1));
      expect(printed, hasLength(1));
      expect(printed.single, startsWith('UiSnack'));
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
      outbox.add('a');
      final c = controller()..isCollecting = true;
      await c.refreshOutbox();
      final printed = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      final ctx = await host(tester);
      await uploadAllReports(ctx, errorReports: c);
      debugPrint = originalPrint;

      expect(outbox.reports, hasLength(1));
      expect(printed, ['UiSnack ללא overlay: ${t.uploadCollectingBusy}']);
    });
    testWidgets('מופיע רק כשיש דיווחים בתיבה', (tester) async {
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c));
      expect(sendOffer(0), findsNothing);

      outbox
        ..add('a')
        ..add('b');
      await c.refreshOutbox();
      await tester.pump();
      expect(sendOffer(2), findsOneWidget);
    });

    testWidgets('לא מופיע כשהכונן לקריאה בלבד', (tester) async {
      outbox.add('a');
      final c = controller();
      await c.refreshOutbox();
      await pumpScreen(tester, home(c, readOnly: true));
      expect(sendOffer(1), findsNothing);
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

      await tester.tap(sendOffer(10));
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
      expect(sendOffer(2), findsOneWidget);

      // המשך אחרי שהחלון נסגר: שניים ≤ 8, ולכן בלי דיאלוג.
      now = now.add(const Duration(minutes: 2));
      await tester.tap(sendOffer(2));
      await tester.pump();
      await tester.pump();
      expect(find.text(t.uploadLongDialogTitle), findsNothing);
      expect(outbox.reports, isEmpty);
      expect(sendOffer(0), findsNothing);
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

class _QaQueue implements OtzariaReportQueue {
  _QaQueue(this.pending, {this.onCount, this.partial = false});

  int pending;
  int collections = 0;
  final void Function()? onCount;
  final bool partial;

  @override
  Future<int> countSendable() async {
    onCount?.call();
    return pending;
  }

  @override
  Future<QueueCollectResult> collectTo(ReportOutbox outbox) async {
    collections++;
    final moved = partial ? pending - 1 : pending;
    for (var i = 0; i < moved; i++) {
      await outbox.write('qa$i', OutboxReport.encodeFile(_report('qa$i')));
    }
    pending -= moved;
    return (collected: moved, error: partial ? 'report disk failure' : null);
  }
}

class _NullUploadReports extends ErrorReportsController {
  _NullUploadReports({required super.outbox, required super.resolveQueue});

  @override
  Future<ReportUploadResult?> upload() async => null;
}
