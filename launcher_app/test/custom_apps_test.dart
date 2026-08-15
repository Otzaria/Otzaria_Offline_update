// בדיקות לתוכנות נוספות. הכלל שנבדק שוב ושוב כאן הוא **"ריק = בלתי
// נראה"**: משתמש שלא הוסיף תוכנה לא אמור לפגוש שום סימן לתכונה הזו.

import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_settings_card.dart';
import 'package:launcher_app/src/screens/custom_apps/installer_kind_label.dart';
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

    testWidgets('כפתור ההוספה תמיד בתחתית המסך', (tester) async {
      await addApp(tester);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.text('הוספת תוכנה'), findsOneWidget);
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
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
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
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
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
    testWidgets('לכל כרטיס יש כפתור עריכה', (tester) async {
      await addApp(tester, name: 'לעריכה');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      expect(find.byTooltip('עריכה'), findsOneWidget);
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
}
