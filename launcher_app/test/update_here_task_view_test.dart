import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/tasks/task_parts.dart';
import 'package:launcher_app/src/screens/tasks/update_here_task_view.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaUserError;

import 'task_fixtures.dart';
import 'test_harness.dart';

void main() {
  final t = stringsOf().task;
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> show(WidgetTester tester, String name) =>
      pumpScreen(tester, taskScenario(name, calls: calls),
          size: const Size(1000, 1400));

  List<StageState> stageStates(WidgetTester tester) => tester
      .widgetList<StageRow>(find.byType(StageRow))
      .map((r) => r.state)
      .toList();

  ResultBadge badge(WidgetTester tester) =>
      tester.widget<ResultBadge>(find.byType(ResultBadge));

  testWidgets('הכלי פועל כמנהל בחשבון אחר: "ביטול" ו"המשך בכל זאת"',
      (tester) async {
    await show(tester, 'otherUser');
    expect(find.text(t.otherUserTitle), findsOneWidget);
    // ההתקנה תיכנס לחשבון של המנהל — וההמלצה היא בלי "הפעל כמנהל".
    final body = t.otherUserBody(firstInstall: false, account: 'Admin');
    expect(find.text(body), findsOneWidget);
    expect(body, contains('Admin'));
    expect(t.otherUserHint, contains('בלי'));
    await tester.tap(find.text(t.continueAnyway));
    await tester.tap(find.text(stringsOf().common.cancel));
    expect(calls, ['respond true', 'respond false']);
  });

  testWidgets('צריך לסגור את אוצריא — "סגירה והמשך" ראשי, ותוספים נאמרים',
      (tester) async {
    await show(tester, 'close');
    expect(find.text(t.closeTitle), findsOneWidget);
    expect(find.text(t.closeHint(plugins: true)), findsOneWidget);
    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.taskPrimary));
    expect(primary.text, t.closeOtzariaAndContinue);
    await tester.tap(find.byKey(ShellKeys.taskPrimary));
    expect(calls, ['respond true']);
  });

  testWidgets('שלב הספרייה: התקדמות מה-progress, "אל תנתק את הכונן"',
      (tester) async {
    final progress = ValueNotifier(0);
    var fraction = 0.1;
    var parentBuilds = 0;
    await pumpScreen(
      tester,
      Builder(builder: (context) {
        parentBuilds++;
        return UpdateHereTaskView(
          task: updateScenarios['instLib']!,
          libraryProgress: progress,
          librarySnapshot: () =>
              LibraryApplySnapshot(fraction: fraction, stage: 'מחיל'),
          actions: UpdateHereActions(
            onRespond: (_) {},
            onStopWaiting: () {},
            onFinishWithoutWaiting: () {},
            onLaunch: () {},
            onHome: () {},
            onRetry: () {},
            onOpenPage: (_) {},
          ),
        );
      }),
    );
    expect(find.text(t.updatingLibrary), findsOneWidget);
    expect(find.text(t.stepOf(1, 3)), findsOneWidget);
    expect(find.text(t.keepDrive), findsOneWidget);
    expect(stageStates(tester),
        [StageState.current, StageState.waiting, StageState.waiting]);
    expect(find.text('10% · ${t.libraryVersion(27)}'), findsOneWidget);

    fraction = 0.46;
    progress.value++;
    await tester.pump();
    expect(parentBuilds, 1);
    expect(find.text('46% · ${t.libraryVersion(27)}'), findsOneWidget);
  });

  testWidgets('שלב התוכנה: האשף פתוח — פס בלי ערך ו"הפסק להמתין"',
      (tester) async {
    await show(tester, 'instApp');
    expect(find.text(t.updatingApp), findsOneWidget);
    expect(find.text(t.appWizardOpen), findsOneWidget);
    expect(stageStates(tester),
        [StageState.done, StageState.current, StageState.waiting]);
    final bars = tester.widgetList<AppProgressBar>(find.byType(AppProgressBar));
    expect(bars.single.value, isNull);
    await tester.tap(find.byKey(ShellKeys.taskStopWaiting));
    expect(calls, ['stop waiting']);
    expect(find.text(t.keepDrive), findsNothing);
  });

  testWidgets('שלב התוספים: "נשלח לאוצריא", לעולם לא "אושר"; "סיום בלי לחכות"',
      (tester) async {
    await show(tester, 'instPlug');
    expect(find.text(t.sendingPlugins), findsOneWidget);
    expect(find.text('לוח שנה עברי · ${t.pluginRowSent}'), findsOneWidget);
    expect(find.text('מזומנים · ${t.pluginRowWaiting}'), findsOneWidget);
    await tester.tap(find.text(t.finishWithoutWaiting));
    expect(calls, ['finish now']);
  });

  testWidgets('אוצריא מעודכנת: סיכום, אינדוקס ו"מעבר לאוצריא"', (tester) async {
    await show(tester, 'installDone');
    expect(find.text(t.updatedTitle), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.ok);
    expect(
      find.text(t.doneHereBody(
        firstInstall: false,
        app: true,
        library: true,
        plugins: true,
      )),
      findsOneWidget,
    );
    expect(find.text(t.pluginsSent), findsOneWidget);
    expect(find.text(t.reindexTitle), findsOneWidget);
    await tester.tap(find.byKey(ShellKeys.taskReindex));
    await tester.tap(find.text(t.toOtzaria));
    expect(calls, ['reindex', 'launch']);
  });

  testWidgets('בלי תוספים — "פתח את אוצריא"; בלי אינדוקס — אין שורה',
      (tester) async {
    await show(tester, 'firstDone');
    expect(find.text(t.installedTitle), findsOneWidget);
    expect(find.text(stringsOf().guide.launchButton), findsOneWidget);
    expect(find.text(t.reindexTitle), findsNothing);
  });

  testWidgets('האשף נסגר לפני הסוף: רגוע, והספרייה שעודכנה נשארת',
      (tester) async {
    await show(tester, 'wizardClosed');
    expect(find.text(t.wizardClosedTitle), findsOneWidget);
    expect(
      find.text(t.wizardClosedBody(firstInstall: false, libraryDone: true)),
      findsOneWidget,
    );
    expect(badge(tester).kind, ResultBadgeKind.calm);
    await tester.tap(find.text(stringsOf().common.retry));
    expect(calls, ['retry']);
  });

  testWidgets('סירוב לסגור באמצע — "העדכון נעצר", לא כשל', (tester) async {
    await pumpScreen(
      tester,
      UpdateHereTaskView(
        task: const UpdateHereTask(
          phase: UpdateHereTaskPhase.cancelledByUser,
          stages: [GuidanceItem.library, GuidanceItem.app],
        ),
        libraryProgress: ValueNotifier(0),
        librarySnapshot: () => const LibraryApplySnapshot(),
        actions: UpdateHereActions(
          onRespond: (_) {},
          onStopWaiting: () {},
          onFinishWithoutWaiting: () {},
          onLaunch: () {},
          onHome: () {},
          onRetry: () {},
          onOpenPage: (_) {},
        ),
      ),
    );
    expect(find.text(t.stoppedTitle), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.calm);
  });

  testWidgets('עדכון הספרייה נכשל: אדום, ההודעה, "נסה שוב" ודף הספרייה',
      (tester) async {
    await show(tester, 'instFail');
    expect(find.text(t.libraryFailedTitle), findsOneWidget);
    expect(badge(tester).kind, ResultBadgeKind.error);
    expect(find.textContaining('נדרשים 2.4 GB'), findsOneWidget);
    expect(find.textContaining(t.libraryFailedKeep), findsOneWidget);
    expect(find.byKey(ShellKeys.taskElevation), findsNothing);
    await tester.tap(find.text(stringsOf().common.retry));
    await tester.tap(find.text(t.toLibraryPage));
    expect(calls, ['retry', 'page library']);
  });

  testWidgets('כשל בשלב התוספים: אוצריא עודכנה, והתוספים לא נשלחו',
      (tester) async {
    await show(tester, 'pluginsFail');
    expect(find.text(t.pluginsFailedTitle), findsOneWidget);
    expect(find.text(t.appFailedTitle), findsNothing);
    final keep = t.pluginsFailedKeep(firstInstall: false, appDone: true);
    expect(find.text(keep), findsOneWidget);
    expect(keep, contains('עודכנה'));
    expect(find.textContaining(t.appFailedKeep), findsNothing);
    expect(find.textContaining('FileSystemException'), findsNothing);
    await tester.tap(find.text(t.toPluginsPage));
    expect(calls, ['page plugins']);
  });

  testWidgets('כשל הרשאות בהתקנה ראשונה: "ההתקנה נכשלה", בלי "מותקנת לכל"',
      (tester) async {
    await show(tester, 'firstFailAdmin');
    expect(find.text(t.permissionInstallFailedTitle), findsOneWidget);
    expect(find.text(t.permissionFailedTitle), findsNothing);
    expect(find.text(t.permissionAppInstallBody), findsOneWidget);
    expect(find.text(t.permissionAppBody), findsNothing);
  });

  testWidgets('כשל הרשאות: גוף ידידותי, השגיאה בפרטים, בלי כפתור לדף',
      (tester) async {
    await show(tester, 'instFailAdmin');
    expect(find.text(t.permissionFailedTitle), findsOneWidget);
    expect(find.text(t.permissionAppBody), findsOneWidget);
    expect(find.byKey(ShellKeys.taskElevation), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ShellKeys.taskElevation),
        matching: find.text(t.elevateTitle),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Access is denied'), findsNothing);
    expect(find.byKey(ShellKeys.taskSecondary), findsNothing);
    final primary =
        tester.widget<ActionButton>(find.byKey(ShellKeys.taskPrimary));
    expect(primary.text, t.elevateButton);
    await tester.tap(find.text(t.techDetails));
    await tester.pump();
    expect(find.textContaining('Access is denied'), findsOneWidget);
    await tester.tap(find.byKey(ShellKeys.taskPrimary));
    expect(calls, ['elevate']);
  });

  testWidgets('התקנה ראשונה: אוצריא שהאשף פתח — "סגירת אוצריא והמשך"',
      (tester) async {
    await show(tester, 'firstClose');
    expect(find.text(t.closeAfterWizardBody), findsOneWidget);
    expect(find.text(t.libraryWaitingClose), findsOneWidget);
    await tester.tap(find.text(t.closeOtzariaAndContinue));
    await tester.tap(find.text(stringsOf().common.cancel));
    expect(calls, ['respond true', 'respond false']);
  });

  group('תיקוני QA של 2b', () {
    testWidgets('אחרי "הפסק להמתין" בעדכון: לא "מעודכנת", ותוספים לא נשלחו',
        (tester) async {
      await show(tester, 'stoppedDone');
      expect(find.text(t.stoppedWaitingTitle), findsOneWidget);
      expect(find.text(t.updatedTitle), findsNothing);
      expect(
        find.text(t.stoppedWaitingBody(firstInstall: false, libraryDone: true)),
        findsOneWidget,
      );
      expect(find.text(t.pluginsAfterInstall), findsOneWidget);
      expect(find.text(t.pluginsSent), findsNothing);
      expect(badge(tester).kind, ResultBadgeKind.calm);
      // לתוכנה אין דף — הכפתור הוא "חזרה לבית", ופעם אחת בלבד.
      expect(
        tester.widget<ActionButton>(find.byKey(ShellKeys.taskPrimary)).text,
        t.backHome,
      );
      expect(find.text(t.backHome), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['page app']);
    });

    testWidgets('"הפסק להמתין" בהתקנה ראשונה — בלי "אוצריא נשארה פתוחה"',
        (tester) async {
      await show(tester, 'firstStopped');
      expect(find.text(t.stoppedWaitingTitle), findsOneWidget);
      expect(find.text(t.stoppedBody), findsNothing);
      expect(find.text(stringsOf().common.retry), findsNothing);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['page app']);
    });

    testWidgets('האשף עדיין פתוח אחרי הזמן הקצוב — לא "נסגר לפני הסוף"',
        (tester) async {
      await show(tester, 'wizardStillOpen');
      expect(find.text(t.wizardStillOpenTitle), findsOneWidget);
      expect(find.text(t.wizardClosedTitle), findsNothing);
      expect(find.text(t.backHome), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.taskPrimary));
      expect(calls, ['page app']);
    });

    testWidgets('כשל בהתקנת התוכנה: "נסה שוב" ו"חזרה לבית", בלי דף תוכנה',
        (tester) async {
      await show(tester, 'appFail');
      expect(find.text(t.appFailedTitle), findsOneWidget);
      expect(find.byKey(ShellKeys.taskSecondary), findsNothing);
      await tester.tap(find.text(t.backHome));
      expect(calls, ['page app']);
    });

    testWidgets('מסירה מעורבת: רק מה שנשלח נקרא "נשלח"', (tester) async {
      await show(tester, 'pluginsMixed');
      expect(find.text(t.pluginsSent), findsNothing);
      expect(
        find.text('${t.pluginsSentNames('לוח שנה עברי')} · '
            '${t.pluginsNotSent('מזומנים')}'),
        findsOneWidget,
      );
      expect(
        find.text(t.doneHereBody(
          firstInstall: false,
          app: false,
          library: false,
          plugins: true,
        )),
        findsOneWidget,
      );
    });

    testWidgets('ספרייה שהותקנה עם הערה — הצלחה, וההערה בשורה', (tester) async {
      await show(tester, 'libraryNote');
      expect(find.text(t.installedTitle), findsOneWidget);
      expect(badge(tester).kind, ResultBadgeKind.ok);
      expect(find.textContaining('בחר אותה בהגדרות'), findsOneWidget);
      expect(find.text(t.libraryFailedTitle), findsNothing);
      // הגוף לא מבטיח "מוכנות ללימוד" כשההערה אומרת שאוצריא לא תמצא אותה.
      final body = t.doneHereBody(
        firstInstall: true,
        app: true,
        library: true,
        plugins: false,
        libraryNote: true,
      );
      expect(find.text(body), findsOneWidget);
      expect(body, isNot(contains('מוכנות ללימוד')));
    });

    testWidgets('ממתין לסגירת אוצריא — מנעול ולא טבעת מסתובבת', (tester) async {
      await show(tester, 'firstClose');
      final library = tester
          .widgetList<StageRow>(find.byType(StageRow))
          .firstWhere((r) => r.title == t.componentLibrary);
      expect(library.state, StageState.current);
      expect(library.mark, isA<Icon>());
    });

    testWidgets('שלב הספרייה: האומדן מוצג כשידוע', (tester) async {
      await pumpScreen(
        tester,
        UpdateHereTaskView(
          task: const UpdateHereTask(
            phase: UpdateHereTaskPhase.running,
            stages: [GuidanceItem.library],
            libraryMinutes: (low: 3, high: 12),
          ),
          libraryProgress: ValueNotifier(0),
          librarySnapshot: () => const LibraryApplySnapshot(),
          actions: UpdateHereActions(
            onRespond: (_) {},
            onStopWaiting: () {},
            onFinishWithoutWaiting: () {},
            onLaunch: () {},
            onHome: () {},
            onRetry: () {},
            onOpenPage: (_) {},
          ),
        ),
      );
      expect(find.text(t.libraryBody(3, 12)), findsOneWidget);
    });

    test('הודעת כשל: מקומית לגוף, טקסט חריג לפרטים בלבד', () {
      expect(
        splitFailureMessage('אין מספיק מקום\nפרט נוסף'),
        (body: 'אין מספיק מקום', details: 'פרט נוסף'),
      );
      expect(
        splitFailureMessage('Bad state: Access is denied (OS Error 5)'),
        (body: null, details: 'Bad state: Access is denied (OS Error 5)'),
      );
      expect(splitFailureMessage(null), (body: null, details: null));
      // כשל פנימי לפרטים; כשל של otzaria_manager — נוסח מתורגם, לגוף.
      expect(
        splitFailureMessage(StateError('No element').toString()),
        (body: null, details: 'Bad state: No element'),
      );
      expect(
        splitFailureMessage(OtzariaUserError('אוצריא לא נמצאה').toString()),
        (body: 'אוצריא לא נמצאה', details: null),
      );
    });

    test('כיוון הפרטים הטכניים לפי התו החזק הראשון', () {
      expect(
          textDirectionOf('library: Bad state: אין מקום'), TextDirection.ltr);
      // עברית יורשת את כיוון השפה — לא TextDirection.rtl מפורש.
      expect(textDirectionOf('אין מספיק מקום (C:)'), isNull);
      expect(textDirectionOf('12345'), TextDirection.ltr);
    });
  });

  group('העתקה מהפרטים הטכניים', () {
    const raw = 'library: חסר מקום — נדרשים \u20661.5\u00a0GB\u2069';
    const clean = 'library: חסר מקום — נדרשים 1.5 GB';
    late List<String?> copied;

    Future<void> open(WidgetTester tester) async {
      copied = [];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpScreen(
        tester,
        const Material(child: TechDetails(text: raw)),
        size: const Size(800, 600),
      );
      await tester.tap(find.text(t.techDetails));
      await tester.pump();
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+C על הסימון — בלי תווי הבידוד', (tester) async {
      await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copied, [clean]);
    });

    testWidgets('טקסט שהתקצר — סימון ישן אינו מפיל את Ctrl+C', (tester) async {
      await open(tester);
      await pumpScreen(
        tester,
        const Material(child: TechDetails(text: 'x')),
        size: const Size(800, 600),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(copied, isEmpty);
    });

    testWidgets('"העתקה" בתפריט הלחיצה הימנית — בלי תווי הבידוד',
        (tester) async {
      await open(tester);
      await tester.tap(
        find.byType(SelectableText),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SelectableText));
      await tester.tap(
          find.text(MaterialLocalizations.of(context).copyButtonLabel).last);
      await tester.pump();
      expect(copied, [clean]);
    });
  });

  group('חלון צר או נמוך', () {
    // 1000×580: מחשב נייד 1366×768 בהגדלה של 125% — רחב, אבל נמוך.
    // 1000×720: גודל הפתיחה של החלון (`main.cpp`).
    const sizes = [
      Size(760, 560),
      Size(900, 560),
      Size(1000, 560),
      Size(801, 600),
      Size(1000, 580),
      Size(1000, 700),
      Size(1000, 720),
      Size(1000, 760),
      Size(1366, 768),
      Size(1000, 1000),
    ];
    for (final language in AppLanguage.values) {
      for (final size in sizes) {
        for (final name in taskScenarioNames) {
          testWidgets(
              '$name ב-${size.width.toInt()}×${size.height.toInt()} '
              '(${language.name}): הפעולה הראשית גלויה בלי גלילה',
              (tester) async {
            await pumpScreen(tester, taskScenarioInWindow(name),
                size: size, language: language);
            await tester.pump();
            expect(tester.takeException(), isNull);
            final primary = find.byKey(ShellKeys.taskPrimary);
            final bar = find.byKey(const ValueKey('task.result.actions'));
            // כל מסך תוצאה: הפעולות בפס הקבוע שבתחתית.
            if (find.byType(TaskResult).evaluate().isNotEmpty) {
              expect(bar, findsOneWidget, reason: name);
              expect(tester.getRect(bar).bottom, size.height, reason: name);
              expect(
                find.descendant(of: bar, matching: primary),
                findsOneWidget,
                reason: name,
              );
            }
            if (primary.evaluate().isEmpty) return;
            final rect = tester.getRect(primary);
            expect(rect.top, greaterThanOrEqualTo(36), reason: name);
            expect(rect.bottom, lessThanOrEqualTo(size.height), reason: name);
          });
        }
      }
    }

    testWidgets('פעולות התוצאה קבועות בתחתית בכל גודל, והתוכן ממורכז מעליהן',
        (tester) async {
      for (final size in const [Size(1000, 580), Size(1000, 1000)]) {
        await pumpScreen(
          tester,
          taskScenarioInWindow('installDone'),
          size: size,
        );
        final bar = find.byKey(const ValueKey('task.result.actions'));
        expect(bar, findsOneWidget);
        expect(tester.getRect(bar).bottom, size.height);
      }
      // בחלון גבוה התג לא נצמד לראש: התוכן ממורכז בשטח שמעל הפס.
      final badgeTop = tester.getRect(find.byType(ResultBadge)).top;
      expect(badgeTop, greaterThan(36 + 40));
    });

    testWidgets('חלון צר וגבוה — התוכן ממורכז גם שם', (tester) async {
      const size = Size(760, 1000);
      await pumpScreen(tester, taskScenarioInWindow('installDone'), size: size);
      final bar = find.byKey(const ValueKey('task.result.actions'));
      expect(tester.getRect(bar).bottom, size.height);
      final badgeTop = tester.getRect(find.byType(ResultBadge)).top;
      expect(badgeTop, greaterThan(36 + 40));
    });

    testWidgets('שורות השלב קומפקטיות, והתג 56', (tester) async {
      await pumpScreen(
        tester,
        taskScenarioInWindow('installDone'),
        size: const Size(760, 560),
      );
      expect(tester.getSize(find.byType(ResultBadge)).width, 56);
      await pumpScreen(
        tester,
        taskScenarioInWindow('instApp'),
        size: const Size(760, 560),
      );
      expect(
        tester
            .widgetList<StageRow>(find.byType(StageRow))
            .map((r) => r.compact),
        everyElement(isTrue),
      );
    });
  });
}
