// בדיקות לתוכנות נוספות. הכלל שנבדק שוב ושוב כאן הוא **"ריק = בלתי
// נראה"**: משתמש שלא הוסיף תוכנה לא אמור לפגוש שום סימן לתכונה הזו.

import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_settings_card.dart';
import 'package:launcher_app/src/screens/custom_apps/installer_kind_label.dart';
import 'package:launcher_app/src/services/announced_apps_store.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';

void main() {
  late Directory tempDir;
  late CustomAppsController controller;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('custom_apps_ui');
    controller = CustomAppsController(
      mirrorRootDir: p.join(tempDir.path, 'mirror'),
    );
  });

  tearDown(() {
    controller.dispose();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// רושם תוכנה על הדיסק ומרענן. קריאות דיסק אמיתיות אינן מסתיימות בתוך
  /// ה-fake-async של testWidgets, ולכן הכול ב-runAsync לפני ה-pump.
  Future<void> addApp(
    WidgetTester tester, {
    String id = 'demo',
    String name = 'תוכנת דמו',
    String? description,
    String? exeName,
    AppSourceKind source = AppSourceKind.manual,
    bool withInstaller = false,
    bool portableFile = false,
  }) async {
    await tester.runAsync(() async {
      await controller.add(
        AppDescriptor(
          id: id,
          name: name,
          description: description,
          portableFile: portableFile,
          sourceKind: source,
          github: source == AppSourceKind.github
              ? const GithubSource(
                  owner: 'someone',
                  repo: 'their-app',
                  assetPattern: r'^App\-\d+\.exe$',
                )
              : null,
          detect: AppDetectRules(exeName: exeName),
        ),
      );
      if (withInstaller) {
        final source = File(p.join(tempDir.path, 'Demo-Setup.exe'))
          ..writeAsStringSync('x');
        await controller.attachInstaller(
          id,
          sourcePath: source.path,
          version: '1.4.2',
        );
      }
    });
  }

  group('ריק = בלתי נראה', () {
    testWidgets('אין תוכנות — הדגל שמסתיר את פריט הניווט כבוי', (tester) async {
      await tester.runAsync(controller.load);
      expect(controller.hasApps, isFalse);
    });

    testWidgets('כרטיס ההגדרות כן מוצג — הוא הכניסה הראשונה', (tester) async {
      await tester.runAsync(controller.load);
      await pumpScreen(tester, CustomAppsSettingsCard(controller: controller));

      expect(find.text('תוכנות נוספות'), findsWidgets);
      expect(find.text('לא נוספו תוכנות'), findsOneWidget);
      expect(find.text('הוספת תוכנה'), findsOneWidget);
    });

    testWidgets('תוכנה ראשונה מדליקה את פריט הניווט', (tester) async {
      await addApp(tester);
      expect(controller.hasApps, isTrue);
    });
  });

  group('מסך התוכנות', () {
    testWidgets('שם ותיאור מוצגים כפי שהם — תוכן שאינו מתורגם', (tester) async {
      await addApp(
        tester,
        name: 'התוכנה של יוסי',
        description: 'כלי לחישוב זמנים',
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('התוכנה של יוסי'), findsOneWidget);
      expect(find.text('כלי לחישוב זמנים'), findsOneWidget);
    });

    testWidgets('בלי קובץ — אומר זאת, ואין כפתור התקנה', (tester) async {
      await addApp(tester, exeName: 'demo.exe');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.textContaining('עוד לא הורד קובץ התקנה'), findsOneWidget);
      expect(find.text('התקנה'), findsNothing);
    });

    testWidgets('עם קובץ — מציג את הגרסה השמורה ומאפשר התקנה', (tester) async {
      await addApp(tester, exeName: 'demo.exe', withInstaller: true);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.textContaining('על הכונן: גרסה 1.4.2'), findsOneWidget);
      expect(find.text('התקנה'), findsOneWidget);
    });

    // ההבחנה החשובה: "לא חיפשנו" אינו "חיפשנו ולא מצאנו".
    testWidgets('בלי שם קובץ הרצה אינו מדווח "אינה מותקנת"', (tester) async {
      await addApp(tester);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.textContaining('לא ניתן לזהות'), findsOneWidget);
      expect(find.textContaining('אינה מותקנת'), findsNothing);
    });

    testWidgets('עם שם קובץ הרצה שלא נמצא — כן "אינה מותקנת"', (tester) async {
      await addApp(tester, exeName: 'no-such-app-anywhere.exe');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.textContaining('אינה מותקנת'), findsOneWidget);
    });

    testWidgets('כפתורי הרשת מוצגים רק לתוכנה מגיטהאב', (tester) async {
      await addApp(tester, id: 'local', name: 'מקומית');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('הורדה לכונן'), findsNothing);

      await addApp(tester,
          id: 'gh', name: 'מגיטהאב', source: AppSourceKind.github);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('הורדה לכונן'), findsOneWidget);
      expect(find.text('בדיקה ברשת'), findsOneWidget);
    });

    testWidgets('בחירת מיקום ידנית מוצגת כשיש מה לחפש ולא נמצא',
        (tester) async {
      await addApp(tester, exeName: 'no-such-app-anywhere.exe');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('בחירת מיקום ידנית'), findsOneWidget);
    });

    // בלי שם קובץ הרצה אין מה לחפש בתיקייה שייבחר — הכפתור היה חסר משמעות.
    testWidgets('בלי שם קובץ הרצה אין בחירת מיקום ידנית', (tester) async {
      await addApp(tester);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('בחירת מיקום ידנית'), findsNothing);
    });

    // כל הניהול עבר להגדרות — במסך נשאר רק מה שעושים עם התוכנה עצמה.
    testWidgets('אין במסך הוספה, עריכה או הסרה', (tester) async {
      await addApp(tester);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('הוספת תוכנה'), findsNothing);
      expect(find.byTooltip('עריכה'), findsNothing);
      expect(find.byTooltip('הסרה מהרשימה'), findsNothing);
    });

    testWidgets('כמה תוכנות — כולן מוצגות', (tester) async {
      await addApp(tester, id: 'a', name: 'ראשונה');
      await addApp(tester, id: 'b', name: 'שנייה');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('ראשונה'), findsOneWidget);
      expect(find.text('שנייה'), findsOneWidget);
    });

    // ההמתנה לרישום ההסרה יכולה להימשך עד דקה, כי קוד יציאה 0 של מתקין אינו
    // אומר שהרישום כבר נכתב. בלי השורה הזו זה נראה כתקיעה.
    testWidgets('בזמן הלמידה מוצגת הודעה ולא מסך קפוא', (tester) async {
      await addApp(tester, name: 'בלמידה');
      controller.isLearning = true;
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.textContaining('מזהה את ההתקנה'), findsOneWidget);
    });

    testWidgets('כשאין למידה ההודעה אינה מוצגת', (tester) async {
      await addApp(tester, name: 'רגילה');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.textContaining('מזהה את ההתקנה'), findsNothing);
    });
  });

  /// חלק ג': הטופס אינו שואל "לאן זה מותקן" ו"איך נקרא ה-exe" — שתי שאלות
  /// שאי אפשר לענות עליהן במחשב המקוון, שבו התוכנה כלל אינה מותקנת.
  group('למידת הזיהוי', () {
    testWidgets('שדות הזיהוי מוצגים כאופציונליים, ולא כדרישה', (tester) async {
      await tester.runAsync(controller.load);
      await pumpScreen(tester, CustomAppsSettingsCard(controller: controller));
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();

      expect(find.textContaining('אפשר להשאיר ריק'), findsNWidgets(2));
    });

    /// ⚠️ הבאג שהיה כאן: הצעת שם ה-exe לקחה את **הראשון** מ-`listSync()` —
    /// סדר לא מובטח, בלי לפסול `unins000.exe` ובלי לפסול עזרי Flutter.
    /// בתיקייה של אפליקציית Flutter זה מחזיר את `crashpad_handler.exe`.
    testWidgets('סורק ה-exe אינו בוחר עזר של Flutter או uninstaller',
        (tester) async {
      final dir = Directory(p.join(tempDir.path, 'Installed'))
        ..createSync(recursive: true);
      for (final name in [
        'crashpad_handler.exe',
        'unins000.exe',
        'realapp.exe',
      ]) {
        File(p.join(dir.path, name)).writeAsStringSync('x');
      }

      final found = await tester.runAsync(
        () => CustomAppsController.findInstalledExe(dir.path, const []),
      );
      expect(p.basename(found!), 'realapp.exe');
    });

    testWidgets('רמז שם מנצח גם כשיש exe אחר בתיקייה', (tester) async {
      final dir = Directory(p.join(tempDir.path, 'Installed2'))
        ..createSync(recursive: true);
      for (final name in ['aaa.exe', 'myapp.exe']) {
        File(p.join(dir.path, name)).writeAsStringSync('x');
      }

      final found = await tester.runAsync(
        () => CustomAppsController.findInstalledExe(
          dir.path,
          InstallLearner.nameHintsFor(name: 'MyApp'),
        ),
      );
      expect(p.basename(found!), 'myapp.exe');
    });
  });

  /// חלק ד': הקובץ שנוסף אינו בהכרח מתקין. שני דברים נבדקים כאן — מה
  /// שהטופס **מציג** על הקובץ, ומה שהטופס **שואל** ואי אפשר להסיק לבד.
  group('סוג הקובץ שנוסף', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.runAsync(controller.load);
      await pumpScreen(tester, CustomAppsSettingsCard(controller: controller));
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();
    }

    testWidgets('הטופס שואל אם הקובץ הוא התוכנה עצמה', (tester) async {
      await openForm(tester);

      expect(find.text('הקובץ הוא התוכנה עצמה'), findsOneWidget);
      expect(find.textContaining('תישאלו לאן להעתיק'), findsOneWidget);
    });

    // הריחרוח עצמו נבדק ב-custom_apps_manager; כאן נבדק שיש לו תרגום, ושהוא
    // אומר את מה שבאמת קורה ולא רק את שם ה-framework.
    testWidgets('לכל סוג התקנה יש שם שמוצג למשתמש', (tester) async {
      final t = AppL10n.strings.customApps;

      for (final kind in CustomInstallerKind.values) {
        expect(installerKindLabelOf(kind, t), isNotEmpty, reason: kind.id);
      }
      expect(
          installerKindLabelOf(CustomInstallerKind.zipPortable, t), 'ארכיון');
    });

    // ההצהרה נשמרת ברשומה — היא הדבר היחיד על הקובץ שאי אפשר להריח.
    testWidgets('ההצהרה נשמרת, ושורדת עריכה של שם', (tester) async {
      await addApp(tester, id: 'nayad', portableFile: true);
      expect(controller.apps.single.descriptor.portableFile, isTrue);

      await tester.runAsync(
        () => controller.update(
          controller.apps.single.descriptor.copyWith(name: 'שם חדש'),
        ),
      );
      expect(controller.apps.single.descriptor.portableFile, isTrue);
    });
  });

  group('המרשם', () {
    // המרשם כולו נערך מההגדרות — שורה לתוכנה, ובכל שורה עריכה והסרה.
    testWidgets('כל תוכנה מקבלת שורה בהגדרות, עם עריכה והסרה', (tester) async {
      await addApp(tester, id: 'a', name: 'ראשונה');
      await addApp(tester, id: 'b', name: 'שנייה');
      await pumpScreen(tester, CustomAppsSettingsCard(controller: controller));

      expect(find.text('ראשונה'), findsOneWidget);
      expect(find.text('שנייה'), findsOneWidget);
      expect(find.byTooltip('עריכה'), findsNWidgets(2));
      expect(find.byTooltip('הסרה מהרשימה'), findsNWidgets(2));
    });

    testWidgets('עריכה משנה את הרשומה ואינה יוצרת שנייה', (tester) async {
      await addApp(tester, id: 'a', name: 'השם הישן', withInstaller: true);

      await tester.runAsync(
        () => controller.update(
          const AppDescriptor(
            id: 'a',
            name: 'השם החדש',
            sourceKind: AppSourceKind.manual,
            detect: AppDetectRules(exeName: 'demo.exe'),
          ),
        ),
      );

      expect(controller.apps, hasLength(1));
      expect(controller.apps.single.descriptor.name, 'השם החדש');
      // הקובץ שכבר על הכונן שייך לתיקיית המזהה, והעריכה אינה נוגעת בו.
      expect(controller.apps.single.storedInstaller?.version, '1.4.2');
    });

    testWidgets('עריכה של תוכנה שאינה רשומה אינה מוסיפה אותה', (tester) async {
      await tester.runAsync(controller.load);

      final ok = await tester.runAsync(
        () => controller.update(
          const AppDescriptor(
            id: 'no-such-app',
            name: 'רפאים',
            sourceKind: AppSourceKind.manual,
          ),
        ),
      );

      expect(ok, isFalse);
      expect(controller.hasApps, isFalse);
    });

    testWidgets('הסרה מוציאה מהרשימה', (tester) async {
      await addApp(tester, id: 'a', name: 'להסרה');
      expect(controller.hasApps, isTrue);

      await tester.runAsync(() => controller.remove('a'));
      expect(controller.hasApps, isFalse);
    });

    testWidgets('מזהה כפול נדחה ואינו דורס', (tester) async {
      await addApp(tester, id: 'same', name: 'המקורית');
      await addApp(tester, id: 'same', name: 'המתחזה');

      expect(controller.apps, hasLength(1));
      expect(controller.apps.single.descriptor.name, 'המקורית');
    });
  });

  /// חלק ה': ההודעה שנפתחת בכניסה למסך. שני הכללים שנבדקים כאן הם
  /// **"רק מי שנכנס ללשונית רואה אותה"** ו**"שותקים כשלא באמת יודעים"**.
  group('הודעת מה שממתין על הכונן', () {
    CustomAppView viewOf({
      String? storedVersion,
      String? exeName = 'demo.exe',
      String? installedVersion,
      bool isInstalled = false,
    }) =>
        CustomAppView(
          entry: CustomAppEntry(
            descriptor: AppDescriptor(
              id: 'a',
              name: 'תוכנה',
              sourceKind: AppSourceKind.manual,
              detect: AppDetectRules(exeName: exeName),
            ),
            installer: storedVersion == null
                ? null
                : StoredInstaller(
                    fileName: 'App.exe',
                    version: storedVersion,
                    sizeBytes: 1,
                    addedAt: DateTime(2026),
                  ),
          ),
          installed: isInstalled
              ? CustomAppInstallState(
                  version: installedVersion,
                  installDir: r'C:\App',
                  launchPath: r'C:\App\demo.exe',
                )
              : null,
        );

    test('קובץ על הכונן שאינו מותקן כאן — תוכנה חדשה', () {
      expect(
        viewOf(storedVersion: '1.4.2').pending,
        CustomAppPending.notInstalled,
      );
    });

    test('על הכונן גרסה חדשה מהמותקנת — עדכון', () {
      expect(
        viewOf(
                storedVersion: '1.4.2',
                isInstalled: true,
                installedVersion: '1.4.0')
            .pending,
        CustomAppPending.newerOnDrive,
      );
    });

    test('אותה גרסה, וגם מותקנת חדשה יותר — אין מה לומר', () {
      expect(
        viewOf(
                storedVersion: '1.4.2',
                isInstalled: true,
                installedVersion: '1.4.2')
            .pending,
        CustomAppPending.none,
      );
      expect(
        viewOf(
                storedVersion: '1.4.2',
                isInstalled: true,
                installedVersion: '1.5.0')
            .pending,
        CustomAppPending.none,
      );
    });

    // "לא ידוע" אינו "יש עדכון". שתי השתיקות שבלעדיהן ההודעה הייתה קופצת
    // בכל כניסה, לנצח, על תוכנה שאיש אינו יודע מה מצבה.
    test('גרסה מותקנת שלא ניתן לקרוא — שותקים', () {
      expect(
        viewOf(storedVersion: '1.4.2', isInstalled: true).pending,
        CustomAppPending.none,
      );
    });

    test('בלי שם קובץ הרצה — שותקים, כי לא ידוע אם מותקנת', () {
      expect(
        viewOf(storedVersion: '1.4.2', exeName: null).pending,
        CustomAppPending.none,
      );
    });

    test('בלי קובץ על הכונן — אין מה להתקין', () {
      expect(viewOf().pending, CustomAppPending.none);
    });

    testWidgets('בכניסה למסך ההודעה נפתחת, ומונה את התוכנות', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      final t = stringsOf().customApps;
      expect(find.text(t.pendingDialogTitle(1)), findsOneWidget);
      expect(
        find.text(t.pendingDialogNotInstalledRow('1.4.2')),
        findsOneWidget,
      );
    });

    testWidgets('כשאין מה להתקין אין הודעה', (tester) async {
      await addApp(tester, exeName: 'no-such-app-anywhere.exe');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(stringsOf().customApps.pendingDialogIntro),
        findsNothing,
      );
    });

    // המסך נבנה רק בכניסה ללשונית (`AppShell._builtScreens`) — ולכן מי
    // שאינו נכנס אליה אינו רואה דבר, גם כשיש מה להתקין.
    testWidgets('בלי כניסה למסך אין הודעה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(tester, CustomAppsSettingsCard(controller: controller));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(stringsOf().customApps.pendingDialogIntro),
        findsNothing,
      );
    });

    testWidgets('ההודעה נפתחת פעם אחת, ולא בכל רענון', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      final title = stringsOf().customApps.pendingDialogTitle(1);
      await tester.tap(find.text(stringsOf().common.close));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);

      // רענון של הרשימה אינו כניסה מחדש למסך.
      await tester.pumpWidget(wrap(CustomAppsScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
    });
  });

  // ההודעה אמורה לקפוץ פעם אחת **בכל מחשב**: תוכנה שכבר הוכרזה כאן לא
  // מכריזה על עצמה שוב בהרצה הבאה, גם כשהיא עדיין אינה מותקנת.
  group('הודעה פעם אחת בכל מחשב', () {
    CustomAppsController persisting() => CustomAppsController(
          mirrorRootDir: p.join(tempDir.path, 'mirror'),
          stateDir: tempDir.path,
        );

    test('הרישום נשמר לפי שם המחשב', () async {
      final store = AnnouncedAppsStore(tempDir.path, hostName: 'PC-A');
      await store.record(['demo']);

      expect(await store.load(), {'demo'});
      // כונן שעבר למחשב אחר — שם ההודעה עוד לא נאמרה.
      expect(
        await AnnouncedAppsStore(tempDir.path, hostName: 'PC-B').load(),
        isEmpty,
      );
    });

    testWidgets('אחרי שההודעה נאמרה, הרצה חדשה שותקת', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );

      await tester.runAsync(() async {
        final first = persisting();
        await first.load();
        expect(first.unannouncedApps, hasLength(1));
        await first.markAnnounced(first.unannouncedApps);
        first.dispose();

        // הרצה חדשה: אותו כונן, אותו מחשב, אותה תוכנה שאינה מותקנת.
        final second = persisting();
        await second.load();
        expect(second.pendingApps, hasLength(1));
        expect(second.unannouncedApps, isEmpty);
        second.dispose();
      });
    });

    testWidgets('תוכנה שכבר הוכרזה אינה פותחת את החלון', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await tester.runAsync(() => controller.markAnnounced(controller.apps));
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(stringsOf().customApps.pendingDialogIntro),
        findsNothing,
      );
    });

    testWidgets('תוכנה חדשה שנוספה אחר כך כן מכריזה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await tester.runAsync(() => controller.markAnnounced(controller.apps));
      await addApp(
        tester,
        id: 'demo2',
        name: 'תוכנה נוספת',
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );

      expect(controller.unannouncedApps, hasLength(1));
      expect(controller.unannouncedApps.single.descriptor.id, 'demo2');
    });
  });
}
