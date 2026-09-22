// בדיקות לתוכנות נוספות. הכלל שנבדק שוב ושוב כאן הוא **"ריק = בלתי
// נראה"**: משתמש שלא הוסיף תוכנה לא אמור לפגוש שום סימן לתכונה הזו.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
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
    String? longDescription,
    List<String> categories = const [],
    bool autoIcon = true,
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
          longDescription: longDescription,
          categorySlugs: categories,
          autoIcon: autoIcon,
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

    // הכרטיס נושא פעולה ראשית אחת; "הורדה לכונן" היא זו כשאין מה להתקין.
    testWidgets('כפתור ההורדה בכרטיס רק לתוכנה מגיטהאב', (tester) async {
      await addApp(tester, id: 'local', name: 'מקומית');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('הורדה לכונן'), findsNothing);

      await addApp(tester,
          id: 'gh', name: 'מגיטהאב', source: AppSourceKind.github);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('הורדה לכונן'), findsOneWidget);
      // "בדיקה ברשת" עברה לדף התוכנה — בכרטיס יש פעולה אחת בלבד.
      expect(find.text('בדיקה ברשת'), findsNothing);
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

    // הבקשה שחזרה מהמשתמשים: לא לסגור את החלון ולחפש את הכרטיס.
    testWidgets('לכל שורה בחלון יש כפתור התקנה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      // אחד בחלון, ואחד בכרטיס שמאחוריו.
      expect(find.text(stringsOf().common.install), findsNWidgets(2));
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

  group('הורדה לכל התוכנות — רק למה שיש בו חדש', () {
    /// קונטרולר שהרשת שלו מזויפת — הדרך היחידה לבדוק הורדה מרוכזת בלי
    /// לצאת לגיטהאב.
    Future<({CustomAppsController controller, _FakeManager fake})>
        fakeController(
      Map<String, String> online, {
      required List<String> ids,
      String storedVersion = '1.4.2',
    }) async {
      final root = p.join(tempDir.path, 'fake-mirror');
      final fake = _FakeManager(
        mirrorRootDir: root,
        online: online,
        sourceFile: File(p.join(tempDir.path, 'Fake-Setup.exe'))
          ..writeAsStringSync('x'),
      );
      final built = CustomAppsController(mirrorRootDir: root, manager: fake);
      for (final id in ids) {
        await built.add(
          AppDescriptor(
            id: id,
            name: id,
            sourceKind: AppSourceKind.github,
            github: const GithubSource(
              owner: 'someone',
              repo: 'their-app',
              assetPattern: r'^App\-\d+\.exe$',
            ),
            detect: const AppDetectRules(),
          ),
        );
        await built.attachInstaller(
          id,
          sourcePath: fake.sourceFile.path,
          version: storedVersion,
        );
      }
      return (controller: built, fake: fake);
    }

    testWidgets('הכפתור מוצג רק כשיש מקור מקוון', (tester) async {
      final t = stringsOf().customApps;
      await addApp(tester, id: 'local', name: 'מקומית');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text(t.downloadAllButton), findsNothing);

      await addApp(
        tester,
        id: 'gh',
        name: 'מגיטהאב',
        source: AppSourceKind.github,
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text(t.downloadAllButton), findsOneWidget);
      expect(find.text(t.checkAllOnlineButton), findsOneWidget);
    });

    // ההורדה כותבת לכונן, וכונן מוגן מפני כתיבה אינו יכול לקבל אותה.
    testWidgets('בכונן לקריאה בלבד אין כלל כרטיס פעולות מרוכזות',
        (tester) async {
      final t = stringsOf().customApps;
      await addApp(tester, id: 'gh', source: AppSourceKind.github);
      await pumpScreen(
        tester,
        CustomAppsScreen(controller: controller, readOnly: true),
      );

      expect(find.text(t.downloadAllButton), findsNothing);
      expect(find.text(t.checkAllOnlineButton), findsNothing);
    });

    testWidgets('מה שכבר נבדק ונמצא מעודכן — אינו יורד שוב', (tester) async {
      late ({int checked, int downloaded, int failed, int notChecked}) result;
      late _FakeManager fake;
      await tester.runAsync(() async {
        final built = await fakeController({'a': '1.4.2'}, ids: ['a']);
        fake = built.fake;
        await built.controller.load();
        await built.controller.checkAllOnline();
        result = await built.controller.downloadAllOutdated();
        built.controller.dispose();
      });

      expect(fake.downloaded, isEmpty);
      expect(result.checked, 1);
      expect(result.downloaded, 0);
    });

    testWidgets('יורדת רק התוכנה שיש לה ברשת גרסה חדשה', (tester) async {
      late ({int checked, int downloaded, int failed, int notChecked}) result;
      late _FakeManager fake;
      await tester.runAsync(() async {
        final built = await fakeController(
          {'old': '2.0.0', 'current': '1.4.2'},
          ids: ['old', 'current'],
        );
        fake = built.fake;
        await built.controller.load();
        // בלי בדיקה מוקדמת: ההורדה המרוכזת בודקת בעצמה.
        result = await built.controller.downloadAllOutdated();
        built.controller.dispose();
      });

      expect(fake.downloaded, ['old']);
      expect(result.downloaded, 1);
      expect(result.failed, 0);
      expect(result.checked, 2);
    });

    // "לא נבדק" אינו "מעודכן" — הוא נספר בנפרד ונאמר למשתמש.
    testWidgets('תוכנה שהבדיקה שלה נכשלה נספרת ואינה יורדת', (tester) async {
      late ({int checked, int downloaded, int failed, int notChecked}) result;
      late _FakeManager fake;
      await tester.runAsync(() async {
        final built = await fakeController(
          {'ok': '2.0.0'},
          ids: ['ok', 'offline'],
        );
        fake = built.fake;
        fake.failFor.add('offline');
        await built.controller.load();
        result = await built.controller.downloadAllOutdated();
        built.controller.dispose();
      });

      expect(fake.downloaded, ['ok']);
      expect(result.notChecked, 1);
      expect(result.checked, 1);
      expect(result.downloaded, 1);
    });
  });

  // הפריסה החדשה: רשת כרטיסים, סרגל קטגוריות ודף לכל תוכנה — אותם
  // רכיבים של חנות התוספים (`screens/store_kit/`).
  group('רשת, קטגוריות ודף התוכנה', () {
    /// מוסיף קטגוריה ומחזיר את ה-slug שלה. השם בעברית, ולכן ה-slug נגזר
    /// מהבסיס הקבוע — הוא מפתח ואינו מוצג.
    Future<String> addCategory(WidgetTester tester, String name) async {
      late String slug;
      await tester.runAsync(() async {
        slug = (await controller.addCategory(name))!;
      });
      return slug;
    }

    testWidgets('לחיצה על כרטיס פותחת את דף התוכנה', (tester) async {
      await addApp(
        tester,
        name: 'תוכנת דמו',
        longDescription: 'הסבר ארוך על מה התוכנה יודעת לעשות',
        exeName: 'no-such-app-anywhere.exe',
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      // התיאור המורחב שייך לדף בלבד — הכרטיס ברשת בגובה קבוע.
      expect(find.textContaining('הסבר ארוך'), findsNothing);

      await tester.tap(find.text('לפרטים מלאים'));
      await tester.pumpAndSettle();

      expect(find.text('חזרה לתוכנות'), findsOneWidget);
      expect(find.text('על התוכנה'), findsOneWidget);
      expect(find.textContaining('הסבר ארוך'), findsOneWidget);
      expect(find.text('מידע כללי'), findsOneWidget);
    });

    // הפעולות שירדו מהכרטיס חייבות להיות זמינות אי-שם, וזה המקום.
    testWidgets('כל הפעולות יושבות בדף התוכנה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        source: AppSourceKind.github,
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.text('לפרטים מלאים'));
      await tester.pumpAndSettle();

      expect(find.text('בחירת מיקום ידנית'), findsOneWidget);
      expect(find.text('בדיקה ברשת'), findsOneWidget);
      expect(find.text('הורדה לכונן'), findsOneWidget);
    });

    testWidgets('חזרה מדף התוכנה מחזירה לרשת', (tester) async {
      await addApp(tester, name: 'תוכנת דמו');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.text('לפרטים מלאים'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('חזרה לתוכנות'));
      await tester.pumpAndSettle();

      expect(find.text('לפרטים מלאים'), findsOneWidget);
      expect(find.text('חזרה לתוכנות'), findsNothing);
    });

    // סרגל עם פריט אחד הוא רעש שגוזל רוחב — ולכן אינו קיים.
    testWidgets('בלי קטגוריות אין סרגל צד', (tester) async {
      await addApp(tester);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('קטגוריות'), findsNothing);
      expect(find.text('כל התוכנות'), findsNothing);
    });

    testWidgets('קטגוריה בסרגל מסננת את הרשת', (tester) async {
      final slug = await addCategory(tester, 'כלי לימוד');
      await addApp(tester, id: 'a', name: 'ראשונה', categories: [slug]);
      await addApp(tester, id: 'b', name: 'שנייה');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('ראשונה'), findsOneWidget);
      expect(find.text('שנייה'), findsOneWidget);

      // הראשון הוא פריט הסרגל; השני הוא גלולת הקטגוריה שעל הכרטיס.
      await tester.tap(find.text('כלי לימוד').first);
      await tester.pumpAndSettle();

      expect(find.text('ראשונה'), findsOneWidget);
      expect(find.text('שנייה'), findsNothing);
    });

    testWidgets('"ללא קטגוריה" מוצג רק כשיש מה לאסוף לתוכו', (tester) async {
      final slug = await addCategory(tester, 'כלי לימוד');
      await addApp(tester, id: 'a', name: 'ראשונה', categories: [slug]);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('ללא קטגוריה'), findsNothing);

      await addApp(tester, id: 'b', name: 'שנייה');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('ללא קטגוריה'), findsOneWidget);

      await tester.tap(find.text('ללא קטגוריה'));
      await tester.pumpAndSettle();
      expect(find.text('שנייה'), findsOneWidget);
      expect(find.text('ראשונה'), findsNothing);
    });

    // שיוך לקטגוריה שנמחקה במחשב אחר אינו מעלים את התוכנה מהמסך.
    testWidgets('שיוך לקטגוריה שאינה קיימת נחשב "ללא קטגוריה"', (tester) async {
      await addCategory(tester, 'כלי לימוד');
      await addApp(tester, name: 'יתומה', categories: const ['אבודה']);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      await tester.tap(find.text('ללא קטגוריה'));
      await tester.pumpAndSettle();
      expect(find.text('יתומה'), findsOneWidget);
    });

    testWidgets('גלריית צילומי המסך מוצגת בדף כשיש תמונות', (tester) async {
      await addApp(tester, name: 'תוכנת דמו');
      await tester.runAsync(() async {
        final shot = File(p.join(tempDir.path, 'shot.png'))
          ..writeAsBytesSync(_onePixelPng);
        await controller.saveMedia('demo', screenshotSources: [shot.path]);
      });
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.text('לפרטים מלאים'));
      await tester.pumpAndSettle();

      expect(find.text('צילומי מסך'), findsOneWidget);
    });

    testWidgets('בלי תמונות אין סעיף צילומי מסך', (tester) async {
      await addApp(tester, name: 'תוכנת דמו');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.text('לפרטים מלאים'));
      await tester.pumpAndSettle();

      expect(find.text('צילומי מסך'), findsNothing);
    });

    testWidgets('כרטיס עמוס בכרטיס הצר ביותר אינו גולש', (tester) async {
      final slug = await addCategory(tester, 'כלי לימוד');
      for (var i = 0; i < 4; i++) {
        await addApp(
          tester,
          id: 'app-$i',
          name: 'שם ארוך במיוחד לתוכנה שנועד לתפוס שתי שורות שלמות',
          description:
              'תקציר ארוך שנמשך על פני כמה שורות כדי לבדוק שהכרטיס אינו '
              'גולש גם כשהטקסט מגיע למקסימום השורות המותר בו',
          categories: [slug],
          exeName: 'no-such-app-anywhere.exe',
        );
      }

      // שני רוחבים צרים ושניים רחבים, שתי השפות, וכל ההגדלות שהמשתמש
      // יכול לבחור — ומעליהן ההגדלה של המערכת.
      for (final width in [584.0, 700.0, 1160.0]) {
        for (final language in AppLanguage.values) {
          for (final scale in [0.9, 1.0, 1.15, 1.3, 1.5]) {
            // עץ נקי בין שילוב לשילוב: `RenderFlex` מדווח על גלישה **פעם
            // אחת** לכל render object, ובלי איפוס שילוב גולש נבלע בשקט.
            useViewSize(tester, Size(width, 1400));
            AppL10n.use(language);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpWidget(
              wrap(
                MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: CustomAppsScreen(controller: controller),
                ),
                language: language,
              ),
            );
            await tester.pump();

            expect(
              tester.takeException(),
              isNull,
              reason: 'הכרטיס גלש ברוחב $width, שפה $language, הגדלה $scale',
            );
          }
        }
      }
      AppL10n.use(AppLanguage.hebrew);
    });
  });

  // ⚠️ `BoxFit.cover` ממלא את המסגרת וחותך את מה שחורג — ואייקון ריבועי
  // במסגרת רחבה נחתך מלמעלה ומלמטה. זה היה הבאג "האייקון בורח מהמסגרת".
  group('תצוגת האייקון', () {
    Finder iconImage() => find.byType(Image);

    testWidgets('אייקון נכנס שלם, ואינו נמתח מעבר לגודלו', (tester) async {
      await addApp(tester, name: 'תוכנת דמו');
      await tester.runAsync(() async {
        final png = File(p.join(tempDir.path, 'icon.png'))
          ..writeAsBytesSync(_onePixelPng);
        await controller.saveMedia('demo', iconSource: png.path);
      });
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      final image = tester.widget<Image>(iconImage().first);
      expect(image.fit, BoxFit.contain);
      // ורוחב התצוגה מוגבל — אייקון של 256 אינו נמתח לרוחב הכרטיס.
      expect(tester.getSize(iconImage().first).width, lessThanOrEqualTo(96));
    });
  });

  // האייקון הוא **ברירת מחדל ולא בקשה**: מי שהוסיף תוכנה ולא בחר תמונה
  // מקבל את האייקון של קובץ ההרצה, בלי להגדיר דבר.
  group('אייקון אוטומטי', () {
    /// קונטרולר על אותה מראה, עם חילוץ מזויף — החילוץ האמיתי מריץ
    /// PowerShell, ואין לו מה לעשות בסוויטה.
    ({CustomAppsController controller, List<String> asked}) withExtractor({
      bool succeeds = true,
    }) {
      final asked = <String>[];
      final built = CustomAppsController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        extractIcon: (exe) async {
          asked.add(exe);
          if (!succeeds) return null;
          final png = File(p.join(tempDir.path, 'extracted.png'))
            ..writeAsBytesSync(_onePixelPng);
          return png.path;
        },
      );
      addTearDown(built.dispose);
      return (controller: built, asked: asked);
    }

    testWidgets('אייקון חסר מתמלא מקובץ ההתקנה שעל הכונן', (tester) async {
      await addApp(tester, withInstaller: true);
      final built = withExtractor();

      await tester.runAsync(() async {
        await built.controller.load();
        await built.controller.fillMissingIcons();
      });

      expect(built.controller.apps.single.descriptor.iconFile, 'icon.png');
      // המקור הוא המתקין ששמור על הכונן — הקובץ היחיד שקיים במחשב המקוון.
      expect(built.asked.single, endsWith('Demo-Setup.exe'));
    });

    testWidgets('בלי קובץ שאפשר לחלץ ממנו — לא נוגעים', (tester) async {
      await addApp(tester);
      final built = withExtractor();

      await tester.runAsync(() async {
        await built.controller.load();
        await built.controller.fillMissingIcons();
      });

      expect(built.asked, isEmpty);
      expect(built.controller.apps.single.descriptor.iconFile, isNull);
    });

    // הסרה מפורשת של אייקון היא החלטה של המשתמש, ולא מצב להשלים.
    testWidgets('אייקון שהוסר במפורש אינו חוזר', (tester) async {
      await addApp(tester, withInstaller: true, autoIcon: false);
      final built = withExtractor();

      await tester.runAsync(() async {
        await built.controller.load();
        await built.controller.fillMissingIcons();
      });

      expect(built.asked, isEmpty);
      expect(built.controller.apps.single.descriptor.iconFile, isNull);
    });

    testWidgets('אייקון שנבחר ידנית אינו נדרס', (tester) async {
      await addApp(tester, withInstaller: true);
      final built = withExtractor();

      await tester.runAsync(() async {
        final chosen = File(p.join(tempDir.path, 'chosen.png'))
          ..writeAsBytesSync(_onePixelPng);
        await built.controller.load();
        await built.controller.saveMedia('demo', iconSource: chosen.path);
        await built.controller.fillMissingIcons();
      });

      expect(built.asked, isEmpty);
      expect(built.controller.apps.single.descriptor.iconFile, 'icon.png');
    });

    // ⚠️ `saveMedia` כותב את כל המדיה מחדש. בלי שהמילוי ימסור את צילומי
    // המסך הקיימים, הוספת האייקון הייתה מוחקת אותם.
    testWidgets('המילוי אינו מוחק את צילומי המסך', (tester) async {
      await addApp(tester, withInstaller: true);
      final built = withExtractor();

      await tester.runAsync(() async {
        final shot = File(p.join(tempDir.path, 'shot.png'))
          ..writeAsBytesSync(_onePixelPng);
        await built.controller.load();
        await built.controller
            .saveMedia('demo', screenshotSources: [shot.path]);
        await built.controller.fillMissingIcons();
      });

      final descriptor = built.controller.apps.single.descriptor;
      expect(descriptor.iconFile, 'icon.png');
      expect(descriptor.screenshotFiles, ['screenshot-1.png']);
    });

    // הכונן מוגן מפני כתיבה — והמילוי כותב אליו.
    testWidgets('במצב קריאה בלבד אין מילוי', (tester) async {
      await addApp(tester, withInstaller: true);
      final built = withExtractor();

      await tester.runAsync(() async {
        await built.controller.load();
        await built.controller.fillMissingIcons(readOnly: true);
      });

      expect(built.asked, isEmpty);
    });

    // כל ניסיון עולה תהליך PowerShell, ותוכנה בלי אייקון בקובץ תיכשל בכל
    // פעם מחדש — הרענון הבא אינו אמור לשלם על זה שוב.
    testWidgets('ניסיון שנכשל אינו חוזר בכל רענון', (tester) async {
      await addApp(tester, withInstaller: true);
      final built = withExtractor(succeeds: false);

      await tester.runAsync(() async {
        await built.controller.load();
        await built.controller.fillMissingIcons();
        await built.controller.fillMissingIcons();
      });

      expect(built.asked, hasLength(1));
      expect(built.controller.apps.single.descriptor.iconFile, isNull);
    });
  });
}

/// מנהל שהרשת שלו מזויפת: [peekLatestOnline] מחזיר את מה שהבדיקה אמורה
/// למצוא, וההורדה רק רושמת קובץ שכבר יושב על הדיסק.
class _FakeManager extends CustomAppsManager {
  _FakeManager({
    required String mirrorRootDir,
    required this.online,
    required this.sourceFile,
  }) : super(
          resolveMirrorDir: () async => mirrorRootDir,
          readVersion: _noVersion,
        );

  /// הגרסה שכל תוכנה "תמצא" ברשת, לפי מזהה.
  final Map<String, String> online;
  final File sourceFile;

  /// מזהים שהבדיקה שלהם תיכשל — כמו מחשב בלי רשת.
  final Set<String> failFor = {};

  /// מה שהורד בפועל. זו הטענה שנבדקת: רק מה שיש בו חדש.
  final List<String> downloaded = [];

  static String? _noVersion(String _) => null;

  @override
  Future<GithubRelease?> peekLatestOnline(AppDescriptor descriptor) async {
    if (failFor.contains(descriptor.id)) throw const SocketException('אין רשת');
    final version = online[descriptor.id];
    return version == null
        ? null
        : GithubRelease(
            tagName: version,
            isPrerelease: false,
            assets: const [],
          );
  }

  @override
  Future<StoredInstaller> downloadFromGithub(
    String id, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloaded.add(id);
    return attachInstaller(
      id,
      sourcePath: sourceFile.path,
      version: online[id]!,
    );
  }
}

/// PNG אמיתי בגודל פיקסל אחד — `Image.file` על קובץ שאינו תמונה מדווח
/// שגיאת פענוח, וזו הייתה נספרת בבדיקה כחריג.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);
