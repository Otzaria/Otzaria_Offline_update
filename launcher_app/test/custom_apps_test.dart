// בדיקות לתוכנות נוספות. הכלל שנבדק שוב ושוב כאן הוא **"ריק = בלתי
// נראה"**: משתמש שלא הוסיף תוכנה לא אמור לפגוש שום סימן לתכונה הזו.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_detail_view.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_form_source.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_install_action.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_store_card.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_manage_page.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_settings_card.dart';
import 'package:launcher_app/src/screens/custom_apps/installer_kind_label.dart';
import 'package:launcher_app/src/screens/store_kit/store_kit.dart';
import 'package:launcher_app/src/services/announced_apps_store.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/byte_size.dart';
import 'package:launcher_app/src/services/custom_app_detection_snapshot.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
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
    bool interactiveInstall = false,
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
          interactiveInstall: interactiveInstall,
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

  /// פעולה שהתחילה מלחיצה כותבת לדיסק מתוך ה-fake-async; נותנים לקריאות
  /// האמיתיות לרוץ, ומריצים את ההמשכים שלהן בין לבין.
  Future<void> settleDisk(WidgetTester tester) async {
    // שני סבבים לפחות: ההמשך שאחרי סגירת דיאלוג עוד לא התחיל לכתוב.
    for (var i = 0; i < 100 && (i < 2 || controller.isBusy); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// דף הניהול — נפתח מהגדרות › תוכנות נוספות (ראו app_shell_test).
  Future<void> openManager(WidgetTester tester) async {
    await pumpScreen(tester, CustomAppsManagePage(controller: controller));
    await tester.pumpAndSettle();
  }

  group('ריק = בלתי נראה', () {
    testWidgets('אין תוכנות — הדגל שמסתיר את פריט הניווט כבוי', (tester) async {
      await tester.runAsync(controller.load);
      expect(controller.hasApps, isFalse);
    });

    // בהגדרות נשארה שורה אחת בלבד, וכל תפקידה לפתוח את מסך הניהול.
    testWidgets('שורת ההגדרות כן מוצגת — היא הכניסה הראשונה', (tester) async {
      await tester.runAsync(controller.load);
      await pumpScreen(tester,
          CustomAppsSettingsCard(controller: controller, onOpenManager: () {}));

      final t = stringsOf().customApps;
      // שורה לחיצה אחת: "ניהול", ופירוט שאומר שעוד אין תוכנות.
      expect(find.text(t.manageRowTitle), findsOneWidget);
      expect(find.text(t.emptyHint), findsOneWidget);
      final row = tester.widget<AppRow>(find.byType(AppRow));
      expect(row.onTap, isNotNull);
      // ההוספה עברה למסך הניהול — בהגדרות אין יותר שום פעולה על המרשם.
      expect(find.text('הוספת תוכנה'), findsNothing);
      expect(find.text('ניהול קטגוריות'), findsNothing);
    });

    testWidgets('מסך הניהול נפתח מהשורה, ובו הכול', (tester) async {
      await tester.runAsync(controller.load);
      await openManager(tester);

      expect(find.text('ניהול התוכנות הנוספות'), findsOneWidget);
      expect(find.text('הוספת תוכנה'), findsOneWidget);
      expect(
          find.text(stringsOf().customApps.manageEmptyTitle), findsOneWidget);
    });

    testWidgets('תוכנה ראשונה מדליקה את פריט הניווט', (tester) async {
      await addApp(tester);
      expect(controller.hasApps, isTrue);
    });
  });

  group('מסך התוכנות', () {
    testWidgets('"כל התוכנות" ריק: הסבר ומעבר לניהול', (tester) async {
      final t = stringsOf().customApps;
      await tester.runAsync(controller.load);
      var opened = 0;
      await pumpScreen(
        tester,
        CustomAppsScreen(controller: controller, onOpenManage: () => opened++),
      );
      await tester.pump();

      expect(find.text(t.manageEmptyTitle), findsOneWidget);
      expect(find.text(t.emptyCategoryTitle), findsNothing);
      await tester.tap(find.text(t.openManagerButton));
      expect(opened, 1);

      expect(find.text(t.manageEmptyBody), findsOneWidget);

      // בכונן מוגן אין כניסה לניהול — וגם אין כפתור, ולא מבטיחים הוספה.
      await pumpScreen(
        tester,
        CustomAppsScreen(controller: controller, readOnly: true),
      );
      await tester.pump();
      expect(find.text(t.openManagerButton), findsNothing);
      expect(find.text(t.manageEmptyBody), findsNothing);
      expect(find.text(t.emptyReadOnlyBody), findsOneWidget);
    });

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

      expect(
        find.text(stringsOf().customApps.versionLabel('1.4.2')),
        findsOneWidget,
      );
      expect(find.text('התקנה'), findsOneWidget);
      // בכרטיס אין הערה: "התקנה" כבר אומרת שהיא אינה מותקנת.
      expect(find.byType(StoreNote), findsNothing);
      // ובדף: "בכונן │ 1.4.2" — הערך בלבד, בלי לחזור על התווית.
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();
      final t = stringsOf().customApps;
      expect(find.text(t.infoStored), findsOneWidget);
      expect(find.text('1.4.2'), findsOneWidget);
      expect(find.textContaining(t.infoStored), findsOneWidget);
    });

    // ההבחנה החשובה: "לא חיפשנו" אינו "חיפשנו ולא מצאנו".
    testWidgets('בלי שם קובץ הרצה אינו מדווח "אינה מותקנת"', (tester) async {
      await addApp(tester);
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      final t = stringsOf().customApps;
      expect(find.text(t.infoInstalled), findsOneWidget);
      expect(find.text(t.valueUnknown), findsOneWidget);
      expect(find.text(t.valueNo), findsNothing);
    });

    testWidgets('עם שם קובץ הרצה שלא נמצא — כן "אינה מותקנת"', (tester) async {
      await addApp(tester, exeName: 'no-such-app-anywhere.exe');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      expect(find.text(stringsOf().customApps.valueNo), findsOneWidget);
    });

    // הכרטיס נושא פעולה ראשית אחת; "הורדה לכונן" היא זו כשאין מה להתקין.
    testWidgets('כפתור ההורדה בכרטיס רק לתוכנה מגיטהאב', (tester) async {
      await addApp(tester, id: 'local', name: 'מקומית');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('הורדה לכונן'), findsNothing);

      await addApp(
        tester,
        id: 'gh',
        name: 'מגיטהאב',
        source: AppSourceKind.github,
      );
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
      expect(
          find.byTooltip(stringsOf().customApps.removeTooltip), findsNothing);
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

    testWidgets('שורת ההורדה בדף התוכנה מתעדכנת מדיווח התקדמות בלבד', (
      tester,
    ) async {
      await addApp(tester, id: 'gh', source: AppSourceKind.github);
      controller.downloadingId = 'gh';
      controller.downloadReceived = 10;
      controller.downloadTotal = 100;
      var stateNotifications = 0;
      controller.addListener(() => stateNotifications++);

      await pumpScreen(
        tester,
        CustomAppDetailView(
          controller: controller,
          app: controller.apps.single,
          readOnly: false,
          onInstall: () {},
          onLaunch: () {},
          onDownload: () {},
          onPickLocation: () {},
          onCategorySelected: (_) {},
        ),
      );
      expect(find.text('10%'), findsOneWidget);

      controller.downloadReceived = 2048;
      controller.downloadTotal = 4096;
      controller.notifyProgress();
      await tester.pump();

      expect(find.text('50%'), findsOneWidget);
      expect(find.text(formatBytesProgress(2048, 4096)!), findsOneWidget);
      expect(stateNotifications, 0);
    });

    testWidgets('"נוסף לכונן" אחרי חצות מוצג ביום המקומי', (tester) async {
      // addedAt נרשם כזמן מקומי; קריאה ב-UTC הייתה מראה את אתמול (י"ב).
      controller.apps = [
        CustomAppView(
          entry: CustomAppEntry(
            descriptor: const AppDescriptor(
              id: 'late',
              name: 'נוספה בלילה',
              sourceKind: AppSourceKind.manual,
              detect: AppDetectRules(),
            ),
            installer: StoredInstaller(
              fileName: 'App.exe',
              version: '1.0.0',
              sizeBytes: 1,
              addedAt: DateTime(2026, 10, 24, 0, 30),
            ),
          ),
        ),
      ];

      await pumpScreen(
        tester,
        CustomAppDetailView(
          controller: controller,
          app: controller.apps.single,
          readOnly: false,
          onInstall: () {},
          onLaunch: () {},
          onDownload: () {},
          onPickLocation: () {},
          onCategorySelected: (_) {},
        ),
      );

      expect(find.text('י"ג חשוון ה\'תשפ"ז'), findsOneWidget);
    });

    testWidgets('שורת "הורדת הכול" מתעדכנת מדיווח התקדמות בלבד', (
      tester,
    ) async {
      await addApp(tester, id: 'gh', source: AppSourceKind.github);
      controller.downloadAllTotal = 4;
      controller.downloadAllDone = 1;
      var stateNotifications = 0;
      controller.addListener(() => stateNotifications++);

      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      expect(find.text('25%'), findsOneWidget);

      final t = stringsOf().customApps;
      controller.downloadAllDone = 3;
      controller.downloadReceived = 2048;
      controller.downloadTotal = 4096;
      controller.notifyProgress();
      await tester.pump();

      expect(find.text(t.downloadingAllLabel(3, 4)), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text(formatBytesProgress(2048, 4096)!), findsOneWidget);
      expect(stateNotifications, 0);
    });
  });

  /// חלק ג': הטופס אינו שואל "לאן זה מותקן" ו"איך נקרא ה-exe" — שתי שאלות
  /// שאי אפשר לענות עליהן במחשב המקוון, שבו התוכנה כלל אינה מותקנת.
  group('למידת הזיהוי', () {
    testWidgets('שדות הזיהוי מוצגים כאופציונליים, ולא כדרישה', (tester) async {
      await tester.runAsync(controller.load);
      await openManager(tester);
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();

      expect(find.textContaining('אפשר להשאיר ריק'), findsNWidgets(2));
    });

    testWidgets('סורק ה-exe אינו בוחר עזר של Flutter או uninstaller', (
      tester,
    ) async {
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
        () => CustomAppsController.findInstalledExe(
          dir.path,
          const [],
          platform: OtzariaTargetPlatform.windows,
        ),
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
          platform: OtzariaTargetPlatform.windows,
        ),
      );
      expect(p.basename(found!), 'myapp.exe');
    });

    test('כללים שנלמדו ולא נשמרו נרשמים כאזהרה בלוג', () async {
      AppLogger.resetForTest();
      final logger = await AppLogger.init(tempDir.path);
      addTearDown(AppLogger.resetForTest);

      CustomAppsController.logLearnedRulesNotSaved(
        'org.example.app',
        const FileSystemException('read-only', r'E:\apps\descriptor.json'),
      );
      await logger.flush();

      final warning = File(logger.filePath)
          .readAsLinesSync()
          .where((line) => line.contains('WARN'))
          .single;
      expect(warning, contains('org.example.app'));
      expect(warning, contains('read-only'));
    });
  });

  /// חלק ד': הקובץ שנוסף אינו בהכרח מתקין. שני דברים נבדקים כאן — מה
  /// שהטופס **מציג** על הקובץ, ומה שהטופס **שואל** ואי אפשר להסיק לבד.
  group('סוג הקובץ שנוסף', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.runAsync(controller.load);
      await openManager(tester);
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();
    }

    testWidgets('הטופס שואל אם הקובץ הוא התוכנה עצמה', (tester) async {
      await openForm(tester);

      expect(find.text('הקובץ הוא התוכנה עצמה'), findsOneWidget);
      expect(find.textContaining('תישאל לאן להעתיק'), findsOneWidget);
    });

    testWidgets('בחירת ארכיון המקור של Audacity נדחית ואפשר לבחור מתקין',
        (tester) async {
      await openForm(tester);
      const source = GithubAsset(
        name: 'audacity-sources-4.0.1.tar.xz',
        downloadUrl: 'https://example.test/source.tar.xz',
        sizeBytes: 100,
      );
      const installer = GithubAsset(
        name: 'audacity-win-4.0.1-x64.exe',
        downloadUrl: 'https://example.test/installer.exe',
        sizeBytes: 200,
      );
      CustomAppGithubSection section() => tester.widget<CustomAppGithubSection>(
            find.byType(CustomAppGithubSection),
          );

      section().onSelectAsset(source);
      await tester.pumpAndSettle();
      expect(section().selectedAsset, isNull);
      expect(section().error, contains(source.name));

      section().onSelectAsset(installer);
      await tester.pumpAndSettle();
      expect(section().selectedAsset, installer);
      expect(section().error, isNull);
    });

    testWidgets('קובץ מקומי שאינו נתמך נדחה, ובחירת EXE אחריו מנקה את השגיאה',
        (tester) async {
      final picker = _FakeFilePicker();
      FilePicker.platform = picker;
      addTearDown(() => picker.active = false);
      const sourceName = 'audacity-sources-4.0.1.tar.xz';
      final exe = p.join(tempDir.path, 'audacity-win-4.0.1-x64.exe');
      await tester.runAsync(() => File(exe).writeAsString('MZ'));

      // החזרת המיקוד לחלון אחרי הבורר עוברת בערוץ פלטפורמה אמיתי.
      Future<void> pick(String path) async {
        picker.next = path;
        await tester.tap(find.descendant(
            of: find.byType(CustomAppLocalFileSection),
            matching:
                find.text(AppL10n.strings.customApps.pickInstallerButton)));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }

      CustomAppLocalFileSection section() =>
          tester.widget(find.byType(CustomAppLocalFileSection));

      await openForm(tester);
      await tester.tap(find.text(AppL10n.strings.customApps.sourceFileOption));
      await tester.pumpAndSettle();

      await pick(p.join(tempDir.path, sourceName));
      expect(picker.lastExtensions, ['exe', 'msi', 'zip']);
      expect(section().path, isNull);
      expect(section().error, contains(sourceName));
      expect(find.textContaining(sourceName), findsOneWidget);

      await pick(exe);
      expect(section().path, exe);
      expect(section().error, isNull);
    });

    Finder switchOf(String label) => find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(FormCheckRow),
          ),
          matching: find.byType(Checkbox),
        );

    // pumpAndSettle אינו נרגע אחרי שמירה אמיתית; מחכים לרשומה עצמה.
    Future<void> saveForm(
      WidgetTester tester,
      bool Function(AppDescriptor saved) done,
    ) async {
      await tester.tap(find.text('שמירה'));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (done(controller.apps.single.descriptor)) return;
      }
      fail('השמירה לא הגיעה לרשומה');
    }

    testWidgets('עריכה שומרת בחירה בהתקנה רגילה', (tester) async {
      await addApp(tester, withInstaller: true, autoIcon: false);
      await openManager(tester);
      await tester.tap(find.byTooltip('עריכה'));
      await tester.pumpAndSettle();

      final toggle = switchOf('התקנה רגילה במקום התקנה מהירה');
      expect(tester.widget<Checkbox>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump();

      await saveForm(tester, (d) => d.interactiveInstall);
      expect(controller.apps.single.descriptor.interactiveInstall, isTrue);
    });

    testWidgets('סימון "התוכנה עצמה" מבטל בשמירה את ההתקנה הרגילה',
        (tester) async {
      await addApp(
        tester,
        interactiveInstall: true,
        withInstaller: true,
        autoIcon: false,
      );
      await openManager(tester);
      await tester.tap(find.byTooltip('עריכה'));
      await tester.pumpAndSettle();

      final interactive = switchOf('התקנה רגילה במקום התקנה מהירה');
      expect(tester.widget<Checkbox>(interactive).value, isTrue);
      await tester.tap(switchOf('הקובץ הוא התוכנה עצמה'));
      await tester.pump();
      expect(interactive, findsNothing);

      await saveForm(tester, (d) => d.portableFile);
      final saved = controller.apps.single.descriptor;
      expect(saved.portableFile, isTrue);
      expect(saved.interactiveInstall, isFalse);
    });

    // הריחרוח עצמו נבדק ב-custom_apps_manager; כאן נבדק שיש לו תרגום, ושהוא
    // אומר את מה שבאמת קורה ולא רק את שם ה-framework.
    testWidgets('לכל סוג התקנה יש שם שמוצג למשתמש', (tester) async {
      final t = AppL10n.strings.customApps;

      for (final kind in CustomInstallerKind.values) {
        expect(installerKindLabelOf(kind, t), isNotEmpty, reason: kind.id);
      }
      expect(
        installerKindLabelOf(CustomInstallerKind.zipPortable, t),
        'קובץ דחוס (ZIP)',
      );
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
    // המרשם כולו נערך במסך הניהול — שורה לתוכנה, ובכל שורה עריכה והסרה.
    testWidgets('כל תוכנה מקבלת שורה בניהול, עם עריכה והסרה', (tester) async {
      await addApp(tester, id: 'a', name: 'ראשונה');
      await addApp(tester, id: 'b', name: 'שנייה');
      await openManager(tester);

      expect(find.text('ראשונה'), findsOneWidget);
      expect(find.text('שנייה'), findsOneWidget);
      expect(find.byTooltip('עריכה'), findsNWidgets(2));
      expect(find.byTooltip(stringsOf().customApps.removeTooltip),
          findsNWidgets(2));
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

    testWidgets('הוספה, צירוף שנכשל וניסיון חוזר — רשומה אחת ללא כפילות', (
      tester,
    ) async {
      const first = AppDescriptor(
        id: 'retry',
        name: 'שם ראשון',
        sourceKind: AppSourceKind.manual,
      );
      const second = AppDescriptor(
        id: 'retry',
        name: 'שם מתוקן',
        sourceKind: AppSourceKind.manual,
        detect: AppDetectRules(exeName: 'retry.exe'),
      );
      final missing = p.join(tempDir.path, 'missing-Setup.exe');
      final present = File(p.join(tempDir.path, 'Retry-Setup.exe'))
        ..writeAsStringSync('x');

      await tester.runAsync(() async {
        expect(await controller.add(first), isTrue);
        expect(
          await controller.attachInstaller(
            'retry',
            sourcePath: missing,
            version: '1',
          ),
          isNull,
        );
        expect(controller.errorMessage, isNotNull);
        expect(controller.apps, hasLength(1));
        expect(controller.apps.single.storedInstaller, isNull);

        expect(await controller.update(second), isTrue);
        final stored = await controller.attachInstaller(
          'retry',
          sourcePath: present.path,
          version: '2.0',
        );
        expect(stored, isNotNull);
        expect(await controller.update(second), isTrue);
      });

      expect(controller.apps, hasLength(1));
      expect(controller.apps.single.descriptor.name, 'שם מתוקן');
      expect(controller.apps.single.storedInstaller?.version, '2.0');
      expect(
        Directory(p.join(tempDir.path, 'mirror', 'apps'))
            .listSync()
            .whereType<Directory>(),
        hasLength(1),
      );
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

    testWidgets('תיקייה שלא נטענה תופסת את המזהה שלה', (tester) async {
      await addApp(tester, id: 'shown', name: 'מוצגת');
      Directory(p.join(tempDir.path, 'mirror', 'apps', 'Hidden'))
          .createSync(recursive: true);
      await tester.runAsync(controller.load);

      expect(controller.apps, hasLength(1));
      expect(controller.takenIds, containsAll(['shown', 'hidden']));
    });
  });

  /// סדר התצוגה. נשמר ל-`apps/order.json` ונוסע על הכונן, ולכן הבדיקה
  /// הקובעת היא שהוא שורד טעינה מחדש ולא רק מסדר את מה שבזיכרון.
  group('סדר התוכנות', () {
    /// שלוש תוכנות שהסדר האלפביתי שלהן ידוע, כדי שהזזה תהיה נראית לעין.
    Future<void> addThree(WidgetTester tester) async {
      await addApp(tester, id: 'alef', name: 'א');
      await addApp(tester, id: 'bet', name: 'ב');
      await addApp(tester, id: 'gimel', name: 'ג');
    }

    List<String> idsOf() => [for (final a in controller.apps) a.descriptor.id];

    testWidgets('בלי סדר שמור — מיון לפי שם', (tester) async {
      await addThree(tester);
      expect(idsOf(), ['alef', 'bet', 'gimel']);
    });

    testWidgets('הזזה למטה מחליפה עם הבאה, ושורדת טעינה מחדש', (tester) async {
      await addThree(tester);
      await tester.runAsync(() => controller.moveApp(0, 1));

      expect(idsOf(), ['bet', 'alef', 'gimel']);
      await tester.runAsync(controller.load);
      expect(idsOf(), ['bet', 'alef', 'gimel']);
    });

    testWidgets('הזזה למעלה היא ההפך המדויק', (tester) async {
      await addThree(tester);
      await tester.runAsync(() => controller.moveApp(2, 1));

      expect(idsOf(), ['alef', 'gimel', 'bet']);
    });

    testWidgets('אינדקס מחוץ לתחום אינו משנה דבר', (tester) async {
      await addThree(tester);
      await tester.runAsync(() => controller.moveApp(0, 9));

      expect(idsOf(), ['alef', 'bet', 'gimel']);
    });

    // תוכנה שהוסרה נעלמת מהרשימה, והסדר של השאר נשאר כפי שהיה.
    testWidgets('הסרה אינה מבלבלת את הסדר', (tester) async {
      await addThree(tester);
      await tester.runAsync(() => controller.moveApp(2, 0));
      await tester.runAsync(() => controller.remove('alef'));

      expect(idsOf(), ['gimel', 'bet']);
    });

    testWidgets('החיצים במסך הניהול מזיזים בפועל', (tester) async {
      await addThree(tester);
      await openManager(tester);

      // "למקום הקודם" בכרטיס השני — מקדים אותו לפני הראשון.
      await tester.tap(find.byTooltip('הזזה למקום הקודם').at(1));
      await tester.pumpAndSettle();

      expect(idsOf(), ['bet', 'alef', 'gimel']);
    });

    testWidgets('בקצוות החץ המתאים כבוי', (tester) async {
      await addThree(tester);
      await openManager(tester);

      IconButton buttonAt(String tooltip, int index) =>
          tester.widget<IconButton>(
            find.descendant(
              of: find.byTooltip(tooltip).at(index),
              matching: find.byType(IconButton),
            ),
          );

      expect(buttonAt('הזזה למקום הקודם', 0).onPressed, isNull);
      expect(buttonAt('הזזה למקום הבא', 2).onPressed, isNull);
      expect(buttonAt('הזזה למקום הבא', 0).onPressed, isNotNull);
    });

    testWidgets('תוכנה אחת — אין רמז על סדר', (tester) async {
      await addApp(tester, id: 'solo', name: 'יחידה');
      await openManager(tester);

      expect(find.textContaining('גררו כרטיס'), findsNothing);
    });

    /// גוררים כרטיס אל מקומו של אחר — בצעדים, כמו עכבר אמיתי.
    Future<void> dragOnto(WidgetTester tester, Finder from, Finder to) async {
      final start = tester.getCenter(from);
      final delta = tester.getCenter(to) - start;
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(delta / 10);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('גרירת כרטיס אל מקומו של אחר מזיזה בפועל', (tester) async {
      await addThree(tester);
      await openManager(tester);
      expect(find.byTooltip('גרירה לשינוי הסדר'), findsNWidgets(3));

      final handles = find.byTooltip('גרירה לשינוי הסדר');
      await dragOnto(tester, handles.at(0), find.text('ב'));
      expect(idsOf(), ['bet', 'alef', 'gimel']);
      // עד שהסדר נשמר הקונטרולר עסוק, והגרירה כבויה.
      await settleDisk(tester);

      // ולכיוון ההפוך: האחרונה אל מקום הראשונה.
      await dragOnto(tester, handles.at(2), find.text('ב'));
      expect(idsOf(), ['gimel', 'bet', 'alef']);
    });

    // הניהול מסדר את הרשימה המלאה — גם כשבחנות פתוחה קטגוריה.
    testWidgets('דף הניהול מציג את כל התוכנות, גם כשבחנות פתוחה קטגוריה', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await controller.load();
        await controller.addCategory('כלים');
      });
      final slug = controller.categories.single.slug;
      await addApp(tester, id: 'alef', name: 'א', categories: [slug]);
      await addApp(tester, id: 'bet', name: 'ב');
      await addApp(tester, id: 'gimel', name: 'ג', categories: [slug]);
      controller.showCategory(slug);
      await openManager(tester);
      expect(find.text('ב'), findsOneWidget);

      await tester.tap(find.byTooltip('הזזה למקום הקודם').at(1));
      await tester.pumpAndSettle();

      expect(idsOf(), ['bet', 'alef', 'gimel']);
    });
  });

  /// דף הניהול: שורה לכל תוכנה עם כלי העריכה — בלי הפעולות של החנות.
  group('מסך הניהול', () {
    testWidgets('שורה לכל תוכנה, בלי התקנה, הורדה או בדיקה ברשת',
        (tester) async {
      await addApp(
        tester,
        id: 'gh',
        name: 'מגיטהאב',
        source: AppSourceKind.github,
      );
      await addApp(
        tester,
        id: 'local',
        name: 'מקומית',
        exeName: 'demo.exe',
        withInstaller: true,
      );
      await openManager(tester);

      expect(find.byType(CustomAppStoreCard), findsNothing);
      expect(find.text('מגיטהאב'), findsOneWidget);
      expect(find.text('מקומית'), findsOneWidget);
      expect(find.byTooltip('עריכה'), findsNWidgets(2));
      expect(find.byTooltip(stringsOf().customApps.removeTooltip),
          findsNWidgets(2));
      expect(find.text('התקנה'), findsNothing);
      expect(find.text('הורדה לכונן'), findsNothing);
      expect(find.text('בדיקה ברשת לכל התוכנות'), findsNothing);
    });

    testWidgets('"עריכה" בשורה פותחת את טופס העריכה', (tester) async {
      await addApp(tester, name: 'לעריכה בלחיצה');
      await openManager(tester);

      await tester.tap(find.byTooltip('עריכה'));
      await tester.pumpAndSettle();

      expect(find.text('עריכת התוכנה'), findsOneWidget);
    });

    testWidgets('שדות הטופס נראים: לכל שדה מסגרת ומילוי מה-theme', (
      tester,
    ) async {
      await tester.runAsync(controller.load);
      await openManager(tester);
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(fields, findsWidgets);
      for (final element in fields.evaluate()) {
        final decorator = find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(InputDecorator),
        );
        expect(decorator, findsOneWidget);
        final decoration = tester.widget<InputDecorator>(decorator).decoration;
        expect(decoration.filled, isTrue);
        expect(decoration.enabledBorder, isA<OutlineInputBorder>());
      }
    });

    testWidgets('"הקובץ הוא התוכנה עצמה" מחליף את התיקייה ושם ההרצה בהסבר', (
      tester,
    ) async {
      final t = stringsOf().customApps;
      await tester.runAsync(controller.load);
      await openManager(tester);
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();
      expect(find.text(t.exeNameLabel), findsOneWidget);
      expect(find.text(t.portableDestinationHint), findsNothing);

      await tester.ensureVisible(find.text(t.portableFileLabel));
      await tester.tap(find.text(t.portableFileLabel));
      await tester.pumpAndSettle();
      expect(find.text(t.exeNameLabel), findsNothing);
      expect(find.text(t.pickInstallDirButton), findsNothing);
      expect(find.text(t.portableDestinationHint), findsOneWidget);
    });

    testWidgets('הסרה: שאלה עם השם, ובגוף — מה נמחק ומה לא', (tester) async {
      final t = stringsOf().customApps;
      await addApp(tester, id: 'a', name: 'להסרה');
      await openManager(tester);
      await tester.tap(find.byTooltip(t.removeTooltip));
      await tester.pumpAndSettle();
      expect(find.text(t.removeDialogTitle('להסרה')), findsOneWidget);
      expect(find.text(t.removeDialogContent('להסרה')), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
    });

    testWidgets('הוספה פותחת את הטופס גם כשהמרשם ריק', (tester) async {
      await tester.runAsync(controller.load);
      await openManager(tester);

      expect(
          find.text(stringsOf().customApps.manageEmptyTitle), findsOneWidget);
      await tester.tap(find.text('הוספת תוכנה'));
      await tester.pumpAndSettle();
      expect(find.text('פרטי התוכנה'), findsOneWidget);
    });

    testWidgets('הסרה שואלת לפני, ורק אז מסירה', (tester) async {
      await addApp(tester, id: 'a', name: 'להסרה');
      await openManager(tester);

      await tester.tap(find.byTooltip(stringsOf().customApps.removeTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(controller.isBusy, isFalse);
      expect(controller.hasApps, isTrue);

      // ההסרה עצמה נבדקת ב"הסרה מוציאה מהרשימה": כתיבה לדיסק שהתחילה
      // מלחיצה אינה מסתיימת בתוך testWidgets. כאן — שהאישור מפעיל אותה.
      await tester.tap(find.byTooltip(stringsOf().customApps.removeTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('הסרה').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ביטול'), findsNothing);
      expect(controller.isBusy, isTrue);
    });

    // המסך נפתח כדי לערוך — ההודעה על מה שממתין שייכת ללשונית.
    testWidgets('אין בו הודעה על מה שממתין על הכונן', (tester) async {
      await addApp(tester, exeName: 'demo.exe', withInstaller: true);
      await openManager(tester);

      expect(controller.unannouncedApps, isNotEmpty);
      expect(find.byType(AlertDialog), findsNothing);
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
          installedVersion: '1.4.0',
        ).pending,
        CustomAppPending.newerOnDrive,
      );
    });

    test('אותה גרסה, וגם מותקנת חדשה יותר — אין מה לומר', () {
      expect(
        viewOf(
          storedVersion: '1.4.2',
          isInstalled: true,
          installedVersion: '1.4.2',
        ).pending,
        CustomAppPending.none,
      );
      expect(
        viewOf(
          storedVersion: '1.4.2',
          isInstalled: true,
          installedVersion: '1.5.0',
        ).pending,
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

    for (final version in ['', '   ', 'unknown', 'N/A']) {
      test('unknown ProductVersion "$version" is not an update', () {
        final app = viewOf(
          storedVersion: '1.4.2',
          isInstalled: true,
          installedVersion: version,
        );
        expect(app.pending, CustomAppPending.none);
        controller.apps = [app];
        expect(controller.hasHomeOffer, isFalse);
      });
    }

    test('normalized numeric ProductVersion remains comparable', () {
      for (final version in ['V1.4.2', ' v1.5.0+build.4 ']) {
        expect(
          viewOf(
            storedVersion: '1.4.2',
            isInstalled: true,
            installedVersion: version,
          ).pending,
          CustomAppPending.none,
        );
      }
      expect(
        viewOf(
          storedVersion: '1.4.2',
          isInstalled: true,
          installedVersion: 'v1.4.2-rc.1',
        ).pending,
        CustomAppPending.newerOnDrive,
      );
    });

    testWidgets('unknown ProductVersion permits an explicit reinstall',
        (tester) async {
      for (final version in ['', '   ', 'unknown', 'N/A']) {
        await pumpScreen(
          tester,
          CustomAppDetailView(
            controller: controller,
            app: viewOf(
              storedVersion: '1.4.2',
              isInstalled: true,
              installedVersion: version,
            ),
            readOnly: true,
            onInstall: () {},
            onLaunch: () {},
            onDownload: () {},
            onPickLocation: () {},
            onCategorySelected: (_) {},
          ),
        );
        expect(find.text(stringsOf().common.launch), findsOneWidget);
        expect(
            find.text(stringsOf().customApps.reinstallButton), findsOneWidget);
        expect(find.text(stringsOf().customApps.installedNoVersionValue),
            findsOneWidget);
      }
    });

    testWidgets('גרסה לא ידועה מאפשרת התקנה מחדש מדף התוכנה', (tester) async {
      var installs = 0;
      final app = viewOf(storedVersion: '1.4.2', isInstalled: true);
      await pumpScreen(
          tester,
          CustomAppDetailView(
            controller: controller,
            app: app,
            readOnly: true,
            onInstall: () => installs++,
            onLaunch: () {},
            onDownload: () {},
            onPickLocation: () {},
            onCategorySelected: (_) {},
          ));
      expect(find.text(stringsOf().common.launch), findsOneWidget);
      await tester.tap(find.text('התקנה מחדש'));
      expect(installs, 1);
      expect(app.pending, CustomAppPending.none);

      await pumpScreen(
        tester,
        CustomAppDetailView(
          controller: controller,
          app: viewOf(
              storedVersion: '1.4.2',
              isInstalled: true,
              installedVersion: '1.5.0'),
          readOnly: true,
          onInstall: () => installs++,
          onLaunch: () {},
          onDownload: () {},
          onPickLocation: () {},
          onCategorySelected: (_) {},
        ),
      );
      expect(find.text(stringsOf().common.launch), findsOneWidget);
      expect(find.text('התקנה מחדש'), findsNothing);
    });

    testWidgets('אישור הפעלה של תוכנה קיימת אינו מבקש להתקין אותה',
        (tester) async {
      await addApp(tester, withInstaller: true);
      controller.dispose();
      controller = CustomAppsController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
      );
      await tester.runAsync(controller.load);
      final app = CustomAppView(
        entry: controller.apps.single.entry,
        installed: const CustomAppInstallState(
          version: '1.4.2',
          installDir: r'C:\App',
          launchPath: r'C:\App\demo.exe',
        ),
      );
      await pumpScreen(
          tester,
          Builder(
              builder: (context) => ActionButton.neutral(
                    text: stringsOf().common.launch,
                    onPressed: () => unawaited(launchCustomApp(
                      context: context,
                      controller: controller,
                      app: app,
                    )),
                  )));
      await tester.tap(find.text(stringsOf().common.launch));
      await settleDisk(tester);
      expect(find.text('להפעיל תוכנה שלא אושרה במחשב הזה?'), findsOneWidget);
      expect(find.text(stringsOf().customApps.trustDialogTitle), findsNothing);
      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pumpAndSettle();
    });

    test('תוכנה חסרה שכבר הוצגה אינה עדכון; גרסה חדשה עדיין מוצעת', () async {
      controller.apps = [viewOf(storedVersion: '1.4.2')];
      expect(controller.hasHomeOffer, isTrue);
      await controller.markAnnounced(controller.apps);
      expect(controller.pendingApps, hasLength(1));
      expect(controller.hasHomeOffer, isFalse);
      controller.apps = [
        viewOf(
            storedVersion: '1.4.2',
            isInstalled: true,
            installedVersion: '1.4.0')
      ];
      expect(controller.hasHomeOffer, isTrue);
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

    // אין דיאלוג: הבית מציג שבב באריח, והכניסה לדף מסמנת את הממתינות כנראו.
    testWidgets('בכניסה למסך אין דיאלוג, והממתינות נרשמות כנראו', (
      tester,
    ) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      expect(controller.unannouncedApps, hasLength(1));
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(controller.pendingApps, hasLength(1));
      expect(controller.unannouncedApps, isEmpty);
    });

    // הבקשה שחזרה מהמשתמשים: להתקין בלי לחפש — הכרטיס עצמו מציע התקנה.
    testWidgets('הכרטיס של ממתינה מציע התקנה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text(stringsOf().common.install), findsOneWidget);
    });

    testWidgets('כשאין מה להתקין אין ממתינות ואין מה לסמן', (tester) async {
      await addApp(tester, exeName: 'no-such-app-anywhere.exe');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(controller.pendingApps, isEmpty);
    });

    // המסך נבנה רק בכניסה (`ShellNavigator.isBuilt`) — ולכן בלי כניסה
    // הממתינה נשארת "חדשה", והשבב באריח שבבית נשאר בולט.
    testWidgets('בלי כניסה למסך הממתינה נשארת חדשה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(tester,
          CustomAppsSettingsCard(controller: controller, onOpenManager: () {}));
      await tester.pumpAndSettle();

      expect(controller.unannouncedApps, hasLength(1));
    });

    // המסגרת משאירה מקטע בנוי אחרי היציאה ממנו (IndexedStack עם TickerMode
    // כבוי). ממתינה שמגיעה אז — למשל אחרי הורדה לכונן — לא נראתה.
    testWidgets('מסך בנוי אבל מוסתר אינו מסמן; כשהוא מוצג — מסמן', (
      tester,
    ) async {
      var shown = false;
      late StateSetter setShown;
      await pumpScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setShown = setState;
            return TickerMode(
              enabled: shown,
              child: CustomAppsScreen(controller: controller),
            );
          },
        ),
      );
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await tester.pumpAndSettle();
      expect(controller.unannouncedApps, hasLength(1));

      setShown(() => shown = true);
      await tester.pumpAndSettle();
      expect(controller.unannouncedApps, isEmpty);
    });

    testWidgets('מסך הניהול אינו מסמן — הוא נפתח כדי לערוך', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await pumpScreen(
        tester,
        CustomAppsManagePage(controller: controller),
      );
      await tester.pumpAndSettle();

      expect(controller.unannouncedApps, hasLength(1));
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

    testWidgets('תוכנה שכבר הוכרזה אינה חדשה גם אחרי כניסה', (tester) async {
      await addApp(
        tester,
        exeName: 'no-such-app-anywhere.exe',
        withInstaller: true,
      );
      await tester.runAsync(() => controller.markAnnounced(controller.apps));
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(controller.pendingApps, hasLength(1));
      expect(controller.unannouncedApps, isEmpty);
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

  group('טעינות חופפות', () {
    test('late loading preserves an announcement recorded while loading',
        () async {
      final root = p.join(tempDir.path, 'gated-announced');
      final gated = _GatedLoadManager(mirrorRootDir: root);
      final built = CustomAppsController(
        mirrorRootDir: root,
        stateDir: tempDir.path,
        manager: gated,
      );
      addTearDown(built.dispose);
      const descriptor = AppDescriptor(
        id: 'missing-app',
        name: 'Missing app',
        sourceKind: AppSourceKind.manual,
        detect: AppDetectRules(exeName: 'missing-app.exe'),
      );
      await gated.add(descriptor);
      final source = File(p.join(tempDir.path, 'setup.exe'))
        ..writeAsStringSync('installer');
      await gated.attachInstaller(
        descriptor.id,
        sourcePath: source.path,
        version: '1.4.2',
      );
      built.apps = [CustomAppView(entry: (await gated.load(descriptor.id))!)];
      expect(built.hasHomeOffer, isTrue);

      final loading = built.load();
      while (gated.gates.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await built.markAnnounced(built.apps);
      expect(built.hasHomeOffer, isFalse);
      gated.gates.single.complete();
      await loading;
      expect(built.pendingApps, hasLength(1));
      expect(built.hasHomeOffer, isFalse);
    });

    AppDescriptor manualApp(String id) =>
        AppDescriptor(id: id, name: id, sourceKind: AppSourceKind.manual);

    test(
      'בקשת טעינה בזמן טעינה פעילה מריצה טעינה חוזרת בלי תוצאה ישנה',
      () async {
        final root = p.join(tempDir.path, 'gated-mirror');
        final gated = _GatedLoadManager(mirrorRootDir: root);
        final built = CustomAppsController(mirrorRootDir: root, manager: gated);
        addTearDown(built.dispose);
        await gated.add(manualApp('first'));
        var notifications = 0;
        built.addListener(() => notifications++);

        Future<Completer<void>> gate(int index) async {
          while (gated.gates.length <= index) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          return gated.gates[index];
        }

        final firstLoad = built.load();
        final firstGate = await gate(0);
        await gated.add(manualApp('second'));
        final requestedLoad = built.load();
        firstGate.complete();
        (await gate(1)).complete();
        await requestedLoad;

        expect(built.apps.map((a) => a.descriptor.id), ['first', 'second']);
        expect(notifications, 1);
        await firstLoad;
      },
    );

    test('כשל בטעינה ישנה אינו מרוקן תוצאה מהטעינה החוזרת', () async {
      final root = p.join(tempDir.path, 'gated-mirror-error');
      final gated = _GatedLoadManager(mirrorRootDir: root);
      final built = CustomAppsController(mirrorRootDir: root, manager: gated);
      addTearDown(built.dispose);
      await gated.add(manualApp('first'));
      var notifications = 0;
      built.addListener(() => notifications++);

      Future<Completer<void>> gate(int index) async {
        while (gated.gates.length <= index) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        return gated.gates[index];
      }

      final firstLoad = built.load();
      final firstGate = await gate(0);
      final requestedLoad = built.load();
      firstGate.completeError(const FileSystemException('drive pulled'));
      (await gate(1)).complete();
      await requestedLoad;

      expect(built.apps.map((a) => a.descriptor.id), ['first']);
      expect(notifications, 1);
      await firstLoad;
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
    testWidgets('בכונן לקריאה בלבד אין כלל כרטיס פעולות מרוכזות', (
      tester,
    ) async {
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

    testWidgets('an older online version never replaces the drive copy', (
      tester,
    ) async {
      late ({int checked, int downloaded, int failed, int notChecked}) result;
      late _FakeManager fake;
      late List<CustomAppView> outdated;
      await tester.runAsync(() async {
        final built = await fakeController(
          {'a': '1.9.5'},
          ids: ['a'],
          storedVersion: '2.0.0',
        );
        fake = built.fake;
        await built.controller.load();
        await built.controller.checkAllOnline();
        outdated = built.controller.outdatedApps;
        result = await built.controller.downloadAllOutdated();
        built.controller.dispose();
      });

      expect(outdated, isEmpty);
      expect(fake.downloaded, isEmpty);
      expect(result.downloaded, 0);
    });

    test('customAppOnlineIsNewer', () {
      expect(customAppOnlineIsNewer('2.0.0', '1.9.5'), isTrue);
      expect(customAppOnlineIsNewer('1.9.5', '2.0.0'), isFalse);
      expect(customAppOnlineIsNewer('1.2', '1.2.0'), isFalse);
      expect(customAppOnlineIsNewer('1.2.0', null), isTrue);
      expect(customAppOnlineIsNewer('1.0.0', '1.0.0-beta'), isTrue);
      expect(customAppOnlineIsNewer('1.0.0-beta2', '1.0.0-beta1'), isTrue);
      expect(customAppOnlineIsNewer('nightly-2', 'nightly-1'), isTrue);
      expect(customAppOnlineIsNewer('nightly-1', 'nightly-1'), isFalse);
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

    testWidgets('ההורדה מקבלת את ה-release שהבדיקה מצאה ואינה שואלת שוב', (
      tester,
    ) async {
      late _FakeManager fake;
      await tester.runAsync(() async {
        final built = await fakeController({'old': '2.0.0'}, ids: ['old']);
        fake = built.fake;
        await built.controller.load();
        await built.controller.downloadAllOutdated();
        built.controller.dispose();
      });

      expect(fake.peeked, ['old']);
      expect(fake.passedReleases['old']?.tagName, '2.0.0');
      expect(fake.passedSources['old']?.repo, 'their-app');
    });

    testWidgets('בדיקה שחזרה אחרי שינוי המקור אינה שומרת את ה-release שלה', (
      tester,
    ) async {
      late _FakeManager fake;
      late CustomAppsController c;
      await tester.runAsync(() async {
        final built = await fakeController({'old': '2.0.0'}, ids: ['old']);
        fake = built.fake;
        c = built.controller;
        await c.load();
        final before = c.apps.single.descriptor;
        final gate = Completer<void>();
        fake.peekGate = gate;
        final check = c.checkOnline(before);
        await c.update(
          AppDescriptor(
            id: before.id,
            name: before.name,
            sourceKind: AppSourceKind.github,
            detect: before.detect,
            github: const GithubSource(
              owner: 'fork',
              repo: 'their-app',
              assetPattern: r'^App\-\d+\.exe$',
            ),
          ),
        );
        gate.complete();
        await check;
        fake.peekGate = null;
        await c.download('old');
        c.dispose();
      });

      expect(c.onlineVersions, isNot(contains('old')));
      expect(fake.passedReleases['old'], isNull);
      expect(fake.passedSources['old'], isNull);
    });

    testWidgets('בלי אינטרנט: אין בדיקה ואין הורדה ברשת — לא בראש ולא בדף', (
      tester,
    ) async {
      final t = stringsOf().customApps;
      late CustomAppsController c;
      await tester.runAsync(() async {
        c = (await fakeController({'a': '2.0.0'}, ids: ['a'])).controller;
        await c.load();
      });
      addTearDown(c.dispose);

      await pumpScreen(tester, CustomAppsScreen(controller: c, online: false));
      await tester.pump();
      expect(find.text(t.checkAllOnlineButton), findsNothing);
      expect(find.text(t.downloadAllButton), findsNothing);
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pump();
      expect(find.text(t.checkOnlineButton), findsNothing);
      expect(find.text(t.downloadButton), findsNothing);

      // מחובר: הבדיקה מוצגת; "הורדה לכונן" — רק כשידוע שבכונן ישן.
      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester, CustomAppsScreen(controller: c, online: true));
      await tester.pump();
      expect(find.text(t.checkAllOnlineButton), findsOneWidget);
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pump();
      expect(find.text(t.checkOnlineButton), findsOneWidget);
      expect(find.text(t.downloadButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"בדיקה ברשת" בדף: מצב טעינה, ובלי בקשה כפולה בלחיצה חוזרת', (
      tester,
    ) async {
      final t = stringsOf().customApps;
      late CustomAppsController c;
      late _FakeManager fake;
      await tester.runAsync(() async {
        final built = await fakeController({'a': '2.0.0'}, ids: ['a']);
        c = built.controller;
        fake = built.fake;
        await c.load();
      });
      addTearDown(c.dispose);
      final gate = Completer<void>();
      fake.peekGate = gate;

      await pumpScreen(tester, CustomAppsScreen(controller: c));
      await tester.pump();
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pump();

      ActionButton check() =>
          tester.widget(find.widgetWithText(ActionButton, t.checkOnlineButton));
      await tester.tap(find.text(t.checkOnlineButton));
      await tester.pump();
      expect(check().spinning, isTrue);
      expect(check().onPressed, isNull);
      await tester.tap(find.text(t.checkOnlineButton), warnIfMissed: false);
      await tester.pump();
      expect(fake.peeked, ['a']);

      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(check().onPressed, isNotNull);
      // ברשת יש גרסה חדשה מזו שבכונן — עכשיו "הורדה לכונן" מוצעת.
      expect(find.text(t.downloadButton), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('אחרי עריכה ההורדה אינה נשענת על release ישן', (tester) async {
      late _FakeManager fake;
      await tester.runAsync(() async {
        final built = await fakeController({'old': '2.0.0'}, ids: ['old']);
        fake = built.fake;
        await built.controller.load();
        await built.controller.checkOnline(
          built.controller.apps.single.descriptor,
        );
        await built.controller.update(
          built.controller.apps.single.descriptor.copyWith(name: 'x'),
        );
        await built.controller.download('old');
        built.controller.dispose();
      });

      expect(fake.passedReleases['old'], isNull);
    });
  });

  group('זיהוי ההתקנות', () {
    AppDescriptor detectable(String id, {String? exeName}) => AppDescriptor(
          id: id,
          name: id,
          sourceKind: AppSourceKind.manual,
          detect: AppDetectRules(
            exeName: exeName ?? '$id.exe',
            registryDisplayName: '^$id\\b',
          ),
        );

    test('צילום אחד של התהליכים ושל הרג\'יסטרי לכל טעינה', () async {
      final root = p.join(tempDir.path, 'mirror');
      final running = File(p.join(tempDir.path, 'running', 'b.exe'))
        ..createSync(recursive: true);
      final registered = Directory(p.join(tempDir.path, 'registered', 'c'))
        ..createSync(recursive: true);
      File(p.join(registered.path, 'c.exe')).createSync();
      for (final id in ['a', 'b', 'c']) {
        await controller.add(detectable(id));
      }

      var snapshots = 0;
      var processReads = 0;
      var registryReads = 0;
      final built = CustomAppsController(
        mirrorRootDir: root,
        detectionSnapshot: () {
          snapshots++;
          return CustomAppDetectionSnapshot(
            runningImagePaths: () {
              processReads++;
              return [running.path];
            },
            uninstallEntries: () {
              registryReads++;
              return [
                InstallRegistryEntry(
                  keyName: 'c_is1',
                  displayName: 'c 1.0',
                  installDir: registered.path,
                ),
              ];
            },
          );
        },
      );
      addTearDown(built.dispose);

      await built.load();

      CustomAppInstallState? installedOf(String id) =>
          built.apps.firstWhere((a) => a.descriptor.id == id).installed;
      expect(snapshots, 1);
      expect(processReads, 1);
      expect(registryReads, 1);
      expect(installedOf('a'), isNull);
      expect(installedOf('b')?.launchPath, running.path);
      expect(installedOf('c')?.installDir, registered.path);
    });

    test('שינוי שאינו נוגע בזיהוי אינו סורק מחדש', () async {
      final root = p.join(tempDir.path, 'counting-mirror');
      final manager = _CountingManager(mirrorRootDir: root);
      final built = CustomAppsController(mirrorRootDir: root, manager: manager);
      addTearDown(built.dispose);

      await built.add(detectable('a'));
      await built.add(detectable('b'));
      expect(manager.detected, ['a', 'b']);

      manager.detected.clear();
      final source = File(p.join(tempDir.path, 'Setup.exe'))
        ..writeAsStringSync('x');
      await built.attachInstaller('a', sourcePath: source.path, version: '1');
      await built.addCategory('כלים');
      await built.update(detectable('b').copyWith(name: 'שם חדש'));
      expect(manager.detected, isEmpty);

      await built.update(detectable('b', exeName: 'other.exe'));
      expect(manager.detected, ['b']);

      manager.detected.clear();
      await built.load();
      expect(manager.detected, isEmpty);

      final fresh = CustomAppsController(mirrorRootDir: root, manager: manager);
      addTearDown(fresh.dispose);
      await fresh.load();
      expect(manager.detected, ['a', 'b']);
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

      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(CustomAppDetailView), findsOneWidget);
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
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      expect(find.text('בחירת מיקום ידנית'), findsOneWidget);
      expect(find.text('בדיקה ברשת'), findsOneWidget);
      expect(find.text('הורדה לכונן'), findsOneWidget);
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
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      expect(find.text('צילומי מסך'), findsOneWidget);
    });

    testWidgets('דף התוכנה: ראש, מידע וצילום גדול שנפתח לתצוגה מוגדלת', (
      tester,
    ) async {
      final t = stringsOf().customApps;
      await addApp(tester, name: 'תוכנה לבדיקת פריסה', withInstaller: true);
      await tester.runAsync(() async {
        final first = File(p.join(tempDir.path, 'first.png'))
          ..writeAsBytesSync(_onePixelPng);
        final second = File(p.join(tempDir.path, 'second.png'))
          ..writeAsBytesSync(_onePixelPng);
        await controller.saveMedia(
          'demo',
          screenshotSources: [first.path, second.path],
        );
      });
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      final hero = find.byType(StoreDetailHero);
      expect(
        find.descendant(of: hero, matching: find.text('תוכנה לבדיקת פריסה')),
        findsOneWidget,
      );
      final info = find.byType(StoreInfoRows);
      expect(
        find.descendant(of: info, matching: find.text(t.infoStoredSize)),
        findsOneWidget,
      );

      // צילום אחד גדול בכל פעם, מפוענח ברוחב שלו, ונקודה לכל צילום.
      final shots = find.byType(StoreScreenshots);
      expect(
        find.descendant(
          of: find.byType(CustomAppDetailView),
          matching: find.text(t.screenshotsPanelTitle),
        ),
        findsOneWidget,
      );
      final images = find.descendant(of: shots, matching: find.byType(Image));
      expect(images, findsOneWidget);
      expect(tester.widget<Image>(images).image, isA<ResizeImage>());
      final p1 = stringsOf().plugins;
      expect(find.byTooltip(p1.screenshotNumber(2, 2)), findsOneWidget);

      await tester.tap(images);
      await tester.pumpAndSettle();
      expect(find.text(p1.screenshotNumber(1, 2)), findsOneWidget);
    });

    testWidgets('צילום מסך שנמחק מהכונן נעלם מהגלריה בטעינה הבאה', (
      tester,
    ) async {
      await addApp(tester, name: 'תוכנת דמו');
      late List<String> saved;
      await tester.runAsync(() async {
        final first = File(p.join(tempDir.path, 'first.png'))
          ..writeAsBytesSync(_onePixelPng);
        final second = File(p.join(tempDir.path, 'second.png'))
          ..writeAsBytesSync(_onePixelPng);
        await controller.saveMedia(
          'demo',
          screenshotSources: [first.path, second.path],
        );
        saved = controller.screenshotPathsOf(controller.apps.single.descriptor);
        File(saved.first).deleteSync();
        await controller.load();
      });

      final descriptor = controller.apps.single.descriptor;
      expect(saved, hasLength(2));
      expect(controller.shownScreenshotPathsOf(descriptor), [saved.last]);

      await tester.runAsync(() async {
        File(saved.last).deleteSync();
        await controller.load();
      });
      expect(controller.shownScreenshotPathsOf(descriptor), isEmpty);

      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();
      expect(find.text('צילומי מסך'), findsNothing);
    });

    testWidgets('בלי תמונות אין סעיף צילומי מסך', (tester) async {
      await addApp(tester, name: 'תוכנת דמו');
      await pumpScreen(tester, CustomAppsScreen(controller: controller));
      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pumpAndSettle();

      expect(find.text('צילומי מסך'), findsNothing);
    });

    testWidgets('כרטיס עמוס בכרטיס הצר ביותר אינו גולש', (tester) async {
      const longName = 'שם ארוך במיוחד לתוכנה שנועד לתפוס שתי שורות שלמות';
      var tilesChecked = 0;
      final slug = await addCategory(tester, 'כלי לימוד');
      for (var i = 0; i < 4; i++) {
        await addApp(
          tester,
          id: 'app-$i',
          name: longName,
          description:
              'תקציר ארוך שנמשך על פני כמה שורות כדי לבדוק שהכרטיס אינו '
              'גולש גם כשהטקסט מגיע למקסימום השורות המותר בו',
          categories: [slug],
          exeName: 'no-such-app-anywhere.exe',
        );
      }

      // שורות צרות ורחבות, כרטיסים בשתי עמודות, שתי השפות וכל ההגדלות —
      // ומעליהן ההגדלה של המערכת. גם דף הניהול, ששורותיו נושאות ארבעה כפתורים.
      for (final manage in [false, true]) {
        for (final width in [584.0, 760.0, 840.0, 1160.0]) {
          for (final language in AppLanguage.values) {
            for (final scale in [0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]) {
              // עץ נקי בין שילוב לשילוב: `RenderFlex` מדווח על גלישה **פעם
              // אחת** לכל render object, ובלי איפוס שילוב גולש נבלע בשקט.
              useViewSize(tester, Size(width, 1400));
              AppL10n.use(language);
              await tester.pumpWidget(const SizedBox());
              await tester.pumpWidget(
                wrap(
                  MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: manage
                        ? CustomAppsManagePage(controller: controller)
                        : CustomAppsScreen(controller: controller),
                  ),
                  language: language,
                ),
              );
              await tester.pump();

              expect(
                tester.takeException(),
                isNull,
                reason: 'הכרטיס גלש ברוחב $width, שפה $language, '
                    'הגדלה $scale, ניהול $manage',
              );
              final card = find.byType(StoreItemCard).first;
              if (!manage &&
                  tester.getSize(card).height == storeTileCardExtent(scale)) {
                final name = tester.renderObject<RenderParagraph>(
                  find.descendant(of: card, matching: find.text(longName)),
                );
                final line = name.getFullHeightForCaret(
                  const TextPosition(offset: 0),
                );
                expect(name.size.height, greaterThan(line * 1.5));
                tilesChecked++;
              }
            }
          }
        }
      }
      AppL10n.use(AppLanguage.hebrew);
      expect(tilesChecked, greaterThan(0), reason: 'אף אריח לא נבדק');
    });
  });

  // ⚠️ `BoxFit.cover` ממלא את המסגרת וחותך את מה שחורג — ואייקון ריבועי
  // במסגרת רחבה נחתך מלמעלה ומלמטה. זה היה הבאג "האייקון בורח מהמסגרת".
  group('תצוגת האייקון', () {
    Finder iconImage() => find.byType(Image);

    testWidgets('אייקון נכנס שלם בתוך מסגרת ריבועית קבועה', (tester) async {
      await addApp(tester, name: 'תוכנת דמו');
      await tester.runAsync(() async {
        final png = File(p.join(tempDir.path, 'icon.png'))
          ..writeAsBytesSync(_onePixelPng);
        await controller.saveMedia('demo', iconSource: png.path);
      });
      await pumpScreen(tester, CustomAppsScreen(controller: controller));

      final image = tester.widget<Image>(iconImage().first);
      expect(image.fit, BoxFit.contain);
      expect(image.image, isA<ResizeImage>());

      // סמל 64 בכרטיס, כמו `.picon` במוקאפ; התמונה בתוכו ריבועית ושלמה.
      final frame = tester.getSize(find.byType(StoreIcon).first);
      expect(frame, const Size(64, 64));
      final icon = tester.getSize(iconImage().first);
      expect(icon.width, lessThan(frame.width));
      expect(icon.height, closeTo(icon.width, 0.01));
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
        await built.controller.saveMedia(
          'demo',
          screenshotSources: [shot.path],
        );
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

  group('טעינות חופפות', () {
    test(
      'טעינה שמתחילה באמצע אחרת מצטרפת אליה, והרשימה האחרונה גוברת',
      () async {
        final root = p.join(tempDir.path, 'gated-mirror');
        final gated = _GatedManager(root);
        final c = CustomAppsController(mirrorRootDir: root, manager: gated);
        addTearDown(c.dispose);

        final release = gated.gate = Completer<void>();
        final stale = c.load();
        while (gated.calls == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await gated.add(
          const AppDescriptor(
            id: 'late',
            name: 'late',
            sourceKind: AppSourceKind.github,
            github: GithubSource(
              owner: 'someone',
              repo: 'their-app',
              assetPattern: r'^App\-\d+\.exe$',
            ),
            detect: AppDetectRules(),
          ),
        );
        final fresh = c.load();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        release.complete();
        await Future.wait([stale, fresh]);

        expect(gated.maxInFlight, 1);
        expect(c.apps.map((a) => a.descriptor.id), ['late']);
      },
    );
  });

  group('דף התוכנה כנתיב בנווט', () {
    testWidgets('הפתיחה והחזרה עוברות דרך המסגרת, בלי כפתור חזרה משלו', (
      tester,
    ) async {
      await addApp(tester, name: 'תוכנת פרטים');
      final requests = <String?>[];
      String? detail;
      late StateSetter rebuild;
      await pumpScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SubPageHeaderScope(
              header: const SizedBox.shrink(),
              child: CustomAppsScreen(
                controller: controller,
                detailId: detail,
                onDetailChanged: requests.add,
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(StoreItemCard).first);
      await tester.pump();
      expect(requests, ['demo']);
      // המסך אינו פותח בעצמו: רק הנתיב שהמסגרת מעבירה.
      expect(find.byType(CustomAppDetailView), findsNothing);

      rebuild(() => detail = 'demo');
      await tester.pumpAndSettle();
      expect(find.byType(CustomAppDetailView), findsOneWidget);
    });
  });
}

class _GatedManager extends CustomAppsManager {
  _GatedManager(String mirrorRootDir)
      : super(
          resolveMirrorDir: () async => mirrorRootDir,
          readVersion: _FakeManager._noVersion,
        );

  Completer<void>? gate;
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<List<CustomAppEntry>> loadAll() async {
    final snapshot = await super.loadAll();
    calls++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final pending = gate;
    gate = null;
    await pending?.future;
    inFlight--;
    return snapshot;
  }
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

  final List<String> peeked = [];

  final Map<String, GithubRelease?> passedReleases = {};

  final Map<String, GithubSource?> passedSources = {};

  Completer<void>? peekGate;

  @override
  Future<GithubRelease?> peekLatestOnline(AppDescriptor descriptor) async {
    peeked.add(descriptor.id);
    if (peekGate case final gate?) await gate.future;
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
    GithubRelease? release,
    GithubSource? releaseSource,
    void Function(int received, int total)? onProgress,
  }) async {
    downloaded.add(id);
    passedReleases[id] = release;
    passedSources[id] = releaseSource;
    return attachInstaller(
      id,
      sourcePath: sourceFile.path,
      version: online[id]!,
    );
  }
}

class _CountingManager extends CustomAppsManager {
  _CountingManager({required String mirrorRootDir})
      : super(
          resolveMirrorDir: () async => mirrorRootDir,
          readVersion: _noVersion,
        );

  final List<String> detected = [];

  static String? _noVersion(String _) => null;

  @override
  Future<CustomAppInstallState?> detectInstalled(AppDescriptor descriptor) {
    detected.add(descriptor.id);
    return super.detectInstalled(descriptor);
  }
}

/// PNG אמיתי בגודל פיקסל אחד — `Image.file` על קובץ שאינו תמונה מדווח
/// שגיאת פענוח, וזו הייתה נספרת בבדיקה כחריג.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

class _GatedLoadManager extends CustomAppsManager {
  _GatedLoadManager({required String mirrorRootDir})
      : super(
          resolveMirrorDir: () async => mirrorRootDir,
          readVersion: (_) => null,
        );

  final List<Completer<void>> gates = [];

  @override
  Future<List<CustomAppEntry>> loadAll() async {
    final entries = await super.loadAll();
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return entries;
  }
}

/// בורר הקבצים של המערכת אינו קיים בבדיקות; מחזיר את מה שהבדיקה קבעה.
/// ב-file_picker 8.3.7 אי אפשר לאפס את `platform`, ולכן בסיום הוא נכבה.
class _FakeFilePicker extends FilePicker {
  String? next;
  List<String>? lastExtensions;
  bool active = true;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (!active) throw StateError('FilePicker.platform נשאר מבדיקה קודמת');
    lastExtensions = allowedExtensions;
    final path = next;
    if (path == null) return null;
    return FilePickerResult([
      PlatformFile(path: path, name: p.basename(path), size: 0),
    ]);
  }
}
