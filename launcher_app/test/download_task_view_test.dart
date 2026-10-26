import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/screens/tasks/download_task_view.dart';
import 'package:launcher_app/src/screens/tasks/task_parts.dart';
import 'package:launcher_app/src/services/byte_size.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

import 'task_fixtures.dart';
import 'test_harness.dart';

void main() {
  final t = stringsOf().task;
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> show(WidgetTester tester, String name) =>
      pumpScreen(tester, taskScenario(name, calls: calls),
          size: const Size(1000, 1400));

  ResultBadge badge(WidgetTester tester) =>
      tester.widget<ResultBadge>(find.byType(ResultBadge));

  String? line(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data;

  String? percent(WidgetTester tester) => line(tester, 'task.download.percent');

  testWidgets('an incompatible installer has a visible actionable explanation',
      (tester) async {
    downloadScenarios['installerRequired'] = const DownloadTask(
        phase: DownloadTaskPhase.failed,
        failure: DownloadFailure(DownloadFailureKind.libraryInstaller));
    addTearDown(() => downloadScenarios.remove('installerRequired'));
    await show(tester, 'installerRequired');
    expect(find.text(stringsOf().libraryScreen.downloadNeedsOtzariaInstaller),
        findsOneWidget);
  });

  testWidgets(
      'a limited download shows its qualification instead of unqualified success',
      (tester) async {
    final note = stringsOf().libraryScreen.downloadNewerNeedsOtzaria('33');
    downloadScenarios['limitedLibrary'] = DownloadTask(
        phase: DownloadTaskPhase.done,
        components: const [MirrorComponent.library],
        notes: [note]);
    addTearDown(() => downloadScenarios.remove('limitedLibrary'));
    await show(tester, 'limitedLibrary');
    expect(find.text(note), findsOneWidget);
    expect(find.text(t.doneBody), findsNothing);
    await pumpScreen(tester, taskScenario('limitedLibrary'),
        size: const Size(760, 560));
    expect(find.text(note), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('שאלת החיפוש החכם', () {
    testWidgets('המומלץ מסומן מראש, ו"התחלת ההורדה" עונה "לא"', (tester) async {
      await show(tester, 'semantic');
      expect(find.text(t.semanticTitle), findsOneWidget);
      final cards = tester.widgetList<OptionCard>(find.byType(OptionCard));
      expect(cards.map((c) => c.selected), [true, false]);
      expect(cards.first.title, t.semanticNoTitle);

      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['answer false remember=false']);
    });

    testWidgets('בחירה ב"כן" עונה "כן", ו"חזרה" מבטלת בלי להוריד',
        (tester) async {
      await show(tester, 'semantic');
      await tester.tap(find.text(t.semanticYesTitle));
      await tester.pump();
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      await tester.tap(find.text(t.back));
      expect(calls, ['answer true remember=false', 'answer null']);
    });

    testWidgets('"אל תציג שוב" נמסר עם התשובה; "חזרה" אינה זוכרת דבר',
        (tester) async {
      await show(tester, 'semantic');
      expect(find.text(t.semanticRemember), findsOneWidget);
      await tester.tap(find.text(t.semanticRemember));
      await tester.pump();
      await tester.tap(find.text(t.back));
      await tester.tap(find.text(t.semanticYesTitle));
      await tester.pump();
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['answer null', 'answer true remember=true']);
    });

    testWidgets('הגדרות נעולות בסיסמה — בלי "אל תציג שוב"', (tester) async {
      await pumpScreen(
        tester,
        taskScenario('semantic', calls: calls, canRemember: false),
        size: const Size(1000, 1400),
      );
      expect(find.byKey(ShellKeys.taskSemanticRemember), findsNothing);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['answer false remember=false']);
    });
  });

  group('התקדמות', () {
    testWidgets('אחוז, שם השלב ושורות הרכיבים — רק מתוך ה-progress',
        (tester) async {
      final progress = ValueNotifier(0);
      var snapshot = const DownloadSnapshot(
        current: MirrorComponent.library,
        fraction: 0.42,
      );
      var parentBuilds = 0;
      await pumpScreen(
        tester,
        Builder(builder: (context) {
          parentBuilds++;
          return DownloadTaskView(
            task: downloadScenarios['download']!,
            progress: progress,
            snapshot: () => snapshot,
            actions: DownloadTaskActions(
              onAnswer: (_) {},
              onCancel: () => calls.add('cancel'),
              onRetry: () {},
              onHome: () {},
              onHere: () {},
            ),
          );
        }),
      );
      // הגדול כולל: רכיב אחד שהסתיים ועוד 42% מהשני; הרכיב בשורה שלו.
      expect(percent(tester), '47%');
      expect(find.text('42%'), findsOneWidget);
      expect(find.text(t.downloadingStep(t.stepLibrary, 2, 3)), findsOneWidget);
      final rows = tester.widgetList<StageRow>(find.byType(StageRow)).toList();
      expect(rows.map((r) => r.state), [
        StageState.done,
        StageState.current,
        StageState.waiting,
      ]);

      snapshot = const DownloadSnapshot(
        current: MirrorComponent.plugins,
        fraction: 0.9,
      );
      progress.value++;
      await tester.pump();
      expect(parentBuilds, 1);
      expect(percent(tester), '96%');
      expect(find.text('90%'), findsOneWidget);
      expect(find.text(t.downloadingStep(t.stepPlugins, 3, 3)), findsOneWidget);
      expect(
        tester.widgetList<StageRow>(find.byType(StageRow)).last.state,
        StageState.current,
      );

      await tester.tap(find.byKey(ShellKeys.taskCancel));
      expect(calls, ['cancel']);
    });

    testWidgets('שורות ממתינות מראות גודל צפוי, וסך הכול רק כשהכול ידוע',
        (tester) async {
      const mb = 1024 * 1024;
      final progress = ValueNotifier(0);
      var snapshot = const DownloadSnapshot(
        current: MirrorComponent.app,
        received: 10 * mb,
        total: 120 * mb,
        fraction: 10 / 120,
      );
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: const DownloadTask(
            phase: DownloadTaskPhase.running,
            components: [
              MirrorComponent.app,
              MirrorComponent.library,
              MirrorComponent.plugins,
            ],
            expectedBytes: {
              MirrorComponent.app: 240 * mb,
              MirrorComponent.plugins: 5 * mb,
            },
          ),
          progress: progress,
          snapshot: () => snapshot,
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      List<String?> details() => [
            for (final row
                in tester.widgetList<StageRow>(find.byType(StageRow)))
              row.detail,
          ];

      expect(details(), [
        '8% · ${formatBytes(120 * mb)}',
        t.stageWaiting,
        '${t.stageWaiting} · ${t.approxSize(formatBytes(5 * mb))}',
      ]);
      // לספרייה אין גודל צפוי — סך הכול היה ממציא מספר.
      expect(line(tester, 'task.download.total'), ' ');

      snapshot = const DownloadSnapshot(
        current: MirrorComponent.library,
        received: 0,
        total: 1024 * mb,
        fraction: 0,
      );
      progress.value++;
      await tester.pump();
      expect(
        line(tester, 'task.download.total'),
        t.downloadTotal(formatBytes((240 + 1024 + 5) * mb)),
      );
    });

    testWidgets('הספרייה: "בודק", אחר כך הגודל המדויק, והגודל האמיתי גובר',
        (tester) async {
      const mb = 1024 * 1024;
      final progress = ValueNotifier(0);
      DownloadSnapshot app(LibrarySizeProbe? probe) => DownloadSnapshot(
            current: MirrorComponent.app,
            received: 10 * mb,
            total: 240 * mb,
            fraction: 10 / 240,
            libraryProbe: probe,
          );
      var snapshot = app(const LibrarySizeProbe.checking());
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: const DownloadTask(
            phase: DownloadTaskPhase.running,
            components: [MirrorComponent.app, MirrorComponent.library],
            expectedBytes: {MirrorComponent.app: 240 * mb},
          ),
          progress: progress,
          snapshot: () => snapshot,
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      String? libraryRow() =>
          tester.widgetList<StageRow>(find.byType(StageRow)).last.detail;
      Future<void> next(DownloadSnapshot value) async {
        snapshot = value;
        progress.value++;
        await tester.pump();
      }

      expect(libraryRow(), '${t.stageWaiting} · ${t.sizeChecking}');
      expect(line(tester, 'task.download.total'), ' ');

      await next(app(const LibrarySizeProbe.known(12 * mb)));
      expect(
        libraryRow(),
        '${t.stageWaiting} · ${t.approxSize(formatBytes(12 * mb))}',
      );
      expect(
        line(tester, 'task.download.total'),
        t.downloadTotal(formatBytes((240 + 12) * mb)),
      );

      await next(const DownloadSnapshot(
        current: MirrorComponent.library,
        received: 0,
        total: 15 * mb,
        fraction: 0,
        libraryProbe: LibrarySizeProbe.known(12 * mb),
      ));
      expect(libraryRow(), '0% · ${formatBytes(15 * mb)}');
      expect(
        line(tester, 'task.download.total'),
        t.downloadTotal(formatBytes((240 + 15) * mb)),
      );
    });

    testWidgets('בדיקה שנכשלה משאירה "ממתין" בלי מספר ובלי סך הכול',
        (tester) async {
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: const DownloadTask(
            phase: DownloadTaskPhase.running,
            components: [MirrorComponent.app, MirrorComponent.library],
            expectedBytes: {MirrorComponent.app: 1024},
          ),
          progress: ValueNotifier(0),
          snapshot: () => const DownloadSnapshot(
            current: MirrorComponent.app,
            libraryProbe: LibrarySizeProbe.failed(),
          ),
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      expect(
        tester.widgetList<StageRow>(find.byType(StageRow)).last.detail,
        t.stageWaiting,
      );
      expect(line(tester, 'task.download.total'), ' ');
    });

    testWidgets('האחוז לא יורד כשהרכיב מפסיק לדווח חלק, ובלי בייטים אין מהירות',
        (tester) async {
      final progress = ValueNotifier(0);
      var snapshot = const DownloadSnapshot(
        current: MirrorComponent.library,
        fraction: 0.42,
        received: 42,
        total: 100,
      );
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: downloadScenarios['download']!,
          progress: progress,
          snapshot: () => snapshot,
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      expect(percent(tester), '47%');

      // הספרייה: התקבלו בייטים, אבל הסכום לא ידוע — `fraction` חוזר null.
      snapshot = const DownloadSnapshot(
        current: MirrorComponent.library,
        received: 60,
      );
      progress.value++;
      await tester.pump();
      expect(percent(tester), '47%');

      snapshot = const DownloadSnapshot(current: MirrorComponent.plugins);
      progress.value++;
      await tester.pump();
      expect(percent(tester), '66%');
      expect(line(tester, 'task.download.speed'), ' ');
      await tester.pump(const Duration(seconds: 10));
      expect(line(tester, 'task.download.speed'), ' ');
    });

    testWidgets(
        'הספרייה עוברת מספירת קבצים לבייטים — האחוז ממשיך לעלות, לא עומד',
        (tester) async {
      final progress = ValueNotifier(0);
      var snapshot = const DownloadSnapshot(
        current: MirrorComponent.library,
        fraction: 0.9,
      );
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: downloadScenarios['download']!,
          progress: progress,
          snapshot: () => snapshot,
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      Future<String?> at(double fraction) async {
        snapshot = DownloadSnapshot(
          current: MirrorComponent.library,
          fraction: fraction,
        );
        progress.value++;
        await tester.pump();
        return percent(tester);
      }

      expect(percent(tester), '63%');
      // ספירת הקבצים הגיעה ל-0.9, והבייטים מתחילים מ-0.05.
      expect(await at(0.05), '63%');
      expect(await at(0.5), '64%');
      expect(await at(0.8), '65%');
      expect(await at(1), '66%');
      // רכיב חדש מתחיל מחדש בלי ירושה מהקודם.
      snapshot = const DownloadSnapshot(
        current: MirrorComponent.plugins,
        fraction: 0.5,
      );
      progress.value++;
      await tester.pump();
      expect(percent(tester), '83%');
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('מהירות וזמן שנותר אחרי שנייה של מדידה', (tester) async {
      final progress = ValueNotifier(0);
      var now = DateTime(2026, 10, 23);
      const mb = 1024 * 1024;
      var received = 0;
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: downloadScenarios['download']!,
          progress: progress,
          clock: () => now,
          snapshot: () => DownloadSnapshot(
            current: MirrorComponent.library,
            fraction: received / (100 * mb),
            received: received,
            total: 100 * mb,
          ),
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      // שתי השורות במקומן כבר עכשיו — בלי קפיצה כשהמהירות מגיעה.
      expect(line(tester, 'task.download.speed'), t.speedPending);
      final top = tester.getTopLeft(find.byType(RowsCard)).dy;

      now = now.add(const Duration(seconds: 2));
      received = 20 * mb;
      progress.value++;
      await tester.pump();
      expect(
        line(tester, 'task.download.speed'),
        '${formatRate(10.0 * mb)} · ${t.lessThanMinuteLeft}',
      );
      expect(
        line(tester, 'task.download.bytes'),
        t.bytesLine(
          t.componentLibrary,
          formatBytes(20 * mb),
          formatBytes(100 * mb),
        ),
      );
      expect(tester.getTopLeft(find.byType(RowsCard)).dy, top);
      expect(find.text('20% · ${formatBytes(100 * mb)}'), findsOneWidget);

      // תקוע: בלי דיווחים, אחרי כמה שניות — "ממתין לנתונים" ולא ערך קפוא.
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(line(tester, 'task.download.speed'), t.speedStalled);
    });

    testWidgets('זמן שנותר: "נותרו שתי דקות", לא "1 דקה" ולא "0 דקות"',
        (tester) async {
      final progress = ValueNotifier(0);
      var now = DateTime(2026, 10, 23);
      const mb = 1024 * 1024;
      var received = 0;
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: downloadScenarios['download']!,
          progress: progress,
          clock: () => now,
          snapshot: () => DownloadSnapshot(
            current: MirrorComponent.library,
            fraction: received / (1000 * mb),
            received: received,
            total: 1000 * mb,
          ),
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () {},
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      now = now.add(const Duration(seconds: 10));
      received = 100 * mb; // 10 MB/s, נותרו 90 שניות
      progress.value++;
      await tester.pump();
      expect(
        line(tester, 'task.download.speed'),
        '${formatRate(10.0 * mb)} · ${t.minutesLeft(2)}',
      );
      expect(t.minutesLeft(2), 'נותרו שתי דקות');
    });

    testWidgets('בזמן ביטול — הכפתור מושבת ואומר "מבטל"', (tester) async {
      await pumpScreen(
        tester,
        DownloadTaskView(
          task: downloadScenarios['download']!,
          progress: ValueNotifier(0),
          snapshot: () => const DownloadSnapshot(),
          cancelling: true,
          actions: DownloadTaskActions(
            onAnswer: (_) {},
            onCancel: () => calls.add('cancel'),
            onRetry: () {},
            onHome: () {},
            onHere: () {},
          ),
        ),
      );
      final cancel =
          tester.widget<ActionButton>(find.byKey(ShellKeys.taskCancel));
      expect(cancel.text, t.cancelling);
      expect(cancel.onPressed, isNull);
    });
  });

  testWidgets('בוטלה: הכונן חזר כמו שהיה, ו"הורדה מחדש"', (tester) async {
    await show(tester, 'cancelled');
    expect(find.text(t.cancelledTitle), findsOneWidget);
    expect(find.text(t.cancelledBody), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.calm);
    await tester.tap(find.text(t.downloadAgain));
    await tester.tap(find.text(t.backHome));
    expect(calls, ['retry', 'home']);
  });

  testWidgets('בוטלה אחרי שרכיב ירד עד הסוף — אומר מה נשאר בכונן',
      (tester) async {
    await pumpScreen(
      tester,
      DownloadTaskView(
        task: const DownloadTask(
          phase: DownloadTaskPhase.cancelled,
          kept: [MirrorComponent.app, MirrorComponent.library],
        ),
        progress: ValueNotifier(0),
        snapshot: () => const DownloadSnapshot(),
        actions: DownloadTaskActions(
          onAnswer: (_) {},
          onCancel: () {},
          onRetry: () {},
          onHome: () {},
          onHere: () {},
        ),
      ),
    );
    expect(
      find.text(t.cancelledKeptBody('${t.stepApp} ו${t.stepLibrary}')),
      findsOneWidget,
    );
    expect(find.text(t.cancelledBody), findsNothing);
  });

  testWidgets('בוטלה ושחזור הכונן נכשל — נאמר בכנות', (tester) async {
    await pumpScreen(
      tester,
      DownloadTaskView(
        task: const DownloadTask(
          phase: DownloadTaskPhase.cancelled,
          revertFailed: true,
        ),
        progress: ValueNotifier(0),
        snapshot: () => const DownloadSnapshot(),
        actions: DownloadTaskActions(
          onAnswer: (_) {},
          onCancel: () {},
          onRetry: () {},
          onHome: () {},
          onHere: () {},
        ),
      ),
    );
    expect(find.text(t.cancelledRevertFailedBody), findsOneWidget);
    expect(find.text(t.cancelledBody), findsNothing);
  });

  group('הכונן מוכן', () {
    testWidgets('מה ירד, "מה עכשיו" ו"לעדכן גם במחשב הזה"', (tester) async {
      await show(tester, 'dlDone');
      expect(find.text(t.doneTitle), findsOneWidget);
      expect(badge(tester).kind, ResultBadgeKind.ok);
      expect(find.text(t.doneAppValue('0.9.96')), findsOneWidget);
      expect(find.text(t.doneLibraryValue(27)), findsOneWidget);
      expect(find.text(t.donePluginsValue(12)), findsOneWidget);
      expect(find.text(t.whatNow), findsOneWidget);
      expect(find.text(t.whatNowConnect), findsOneWidget);
      expect(find.text(t.doneBody), findsOneWidget);
      // "עדכוני אוצריא" מודגש בשלב 3.
      final step = tester.widget<GuideStep>(
        find.byWidgetPredicate((w) => w is GuideStep && w.number == 3),
      );
      expect(step.strong, stringsOf().shell.appTitle);
      await tester.tap(find.text(t.updateHereToo));
      await tester.tap(find.text(t.backHome));
      expect(calls, ['here', 'home']);
    });

    for (final offer in DownloadHereOffer.values) {
      testWidgets('הפעולות לפי המחשב הזה: $offer', (tester) async {
        await pumpScreen(
          tester,
          DownloadTaskView(
            task: const DownloadTask(
              phase: DownloadTaskPhase.done,
              components: [MirrorComponent.library],
              skipped: [MirrorComponent.app],
            ),
            progress: ValueNotifier(0),
            snapshot: () => const DownloadSnapshot(),
            done: DownloadDoneInfo(offer: offer),
            actions: DownloadTaskActions(
              onAnswer: (_) {},
              onCancel: () {},
              onRetry: () {},
              onHome: () {},
              onHere: () {},
            ),
          ),
        );
        expect(find.text(t.doneSkipped(t.componentApp)), findsOneWidget);
        expect(find.text(t.updateHereToo),
            offer == DownloadHereOffer.update ? findsOneWidget : findsNothing);
        expect(find.text(t.installHereToo),
            offer == DownloadHereOffer.install ? findsOneWidget : findsNothing);
        expect(find.text(t.finish),
            offer == DownloadHereOffer.update ? findsNothing : findsOneWidget);
      });
    }
  });

  group('כשל — בתוך החלון', () {
    testWidgets('אין רשת: תג רגוע, "נסה שוב", ופרטים טכניים מקופלים',
        (tester) async {
      await show(tester, 'dlError');
      expect(find.text(t.networkTitle), findsOneWidget);
      expect(find.text(t.networkBody(t.stepLibrary)), findsOneWidget);
      expect(badge(tester).kind, ResultBadgeKind.calm);
      expect(badge(tester).icon, FluentIcons.wifi_off_24_regular);
      expect(find.textContaining('SocketException'), findsNothing);

      await tester.tap(find.text(t.techDetails));
      await tester.pump();
      expect(find.textContaining('SocketException'), findsOneWidget);
      await tester.tap(find.text(stringsOf().common.retry));
      expect(calls, ['retry']);
    });

    testWidgets('תעודה שנדחתה: מסנן אינטרנט, רגוע, "נסה שוב"', (tester) async {
      await show(tester, 'dlBlocked');
      expect(find.text(t.filterTitle), findsOneWidget);
      expect(find.text(t.filterBody(t.stepLibrary)), findsOneWidget);
      expect(find.text(t.networkTitle), findsNothing);
      expect(badge(tester).kind, ResultBadgeKind.calm);
      expect(find.text(stringsOf().common.retry), findsOneWidget);
    });

    testWidgets('שבת: רגוע, ובלי "נסה שוב"', (tester) async {
      await show(tester, 'dlShabbat');
      expect(find.text(t.shabbatTitle), findsOneWidget);
      expect(badge(tester).kind, ResultBadgeKind.calm);
      expect(find.text(stringsOf().common.retry), findsNothing);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['home']);
    });

    testWidgets('אין מקום: נדרשים ופנויים, ו"נסה שוב"', (tester) async {
      await show(tester, 'dlSpace');
      expect(find.text(t.spaceTitle), findsOneWidget);
      expect(find.text(t.spaceBody('1.2 GB', '0.4 GB')), findsOneWidget);
      expect(find.text(stringsOf().common.retry), findsOneWidget);
    });

    testWidgets('שגיאה אמיתית: תג אדום, ומה שירד נשמר', (tester) async {
      await show(tester, 'dlFail');
      expect(find.text(t.otherTitle(t.stepLibrary)), findsOneWidget);
      expect(find.text(t.otherBody), findsOneWidget);
      expect(badge(tester).kind, ResultBadgeKind.error);
    });
  });

  group('תיקוני QA של 2b', () {
    testWidgets('"מתכונן להורדה" — יש "ביטול"', (tester) async {
      await show(tester, 'preparing');
      expect(find.text(t.preparingTitle), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.taskCancel));
      expect(calls, ['cancel preparing']);
    });

    testWidgets('לא ירד דבר — לא "כל העדכונים ירדו"', (tester) async {
      await show(tester, 'dlNothing');
      expect(find.text(t.doneNothingBody), findsOneWidget);
      expect(find.text(t.doneBody), findsNothing);
    });

    testWidgets('בלי שאלת "אפשר לשנות בדף ספריית אוצריא", ועם הגילוי על ההסכמה',
        (tester) async {
      await show(tester, 'semantic');
      expect(find.textContaining('בדף ספריית אוצריא'), findsNothing);
      expect(find.text(t.semanticYesBody), findsOneWidget);
      expect(t.semanticYesBody, contains('נתוני אימון'));
    });
  });
}
