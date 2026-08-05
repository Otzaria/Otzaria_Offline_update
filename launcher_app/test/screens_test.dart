// בדיקות רינדור לארבעת המסכים. המסכים נבדקים ישירות (ולא דרך AppShell),
// כדי שהבדיקה לא תיגע ברשת: הבנייה של הקונטרולרים אינה פונה לרשת, רק
// checkForUpdate/update — שלא נקראים כאן.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';

/// משטח בדיקה גבוה — ה-ListView של [ScreenBody] בונה רק את מה שנראה,
/// ובחלון ברירת המחדל (800x600) הכרטיסים התחתונים לא היו נבנים בכלל.
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1400, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(screen));
}

/// עוטף מסך באותו MaterialApp שהאפליקציה בונה — כולל locale he-IL, שהוא
/// מה שקובע RTL גלובלי לכל עץ ה-widgets.
Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL')],
      locale: const Locale('he', 'IL'),
      theme: AppThemeData.light(
        AppThemeData.createColorScheme(
          AppSeedColors.defaultLight,
          Brightness.light,
        ),
      ),
      home: child,
    );

void main() {
  late Directory tempDir;
  late OtzariaModuleController otzaria;
  late LibraryModuleController library;
  late SettingsController settings;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launcher_test');
    otzaria = OtzariaModuleController(dataDir: tempDir.path);
    library = LibraryModuleController(dataDir: tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
  });

  tearDown(() {
    otzaria.dispose();
    library.dispose();
    settings.dispose();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('דף הבית מציג את ארבעת הכרטיסים ואינו טוען שמצב נבדק',
      (tester) async {
    await pumpScreen(
      tester,
      HomeScreen(
        otzaria: otzaria,
        library: library,
        settings: settings,
        network: NetworkState.unknown,
        otzariaIsRunning: false,
        onRecheck: () async {},
        onGoToLibrary: () {},
        onGoToPlugins: () {},
      ),
    );

    expect(find.text('תוכנת אוצריא'), findsOneWidget);
    expect(find.text('ספריית הספרים'), findsOneWidget);
    expect(find.text('תוספים'), findsOneWidget);
    expect(find.text('העברה למחשב לא־מקוון'), findsOneWidget);
    // המצב ההתחלתי אמור להיות "טרם נבדק", לא "מעודכן".
    expect(find.text('טרם נבדק'), findsWidgets);
  });

  testWidgets('דף הבית מציג אזהרה כשאוצריא פתוחה', (tester) async {
    await pumpScreen(
      tester,
      HomeScreen(
        otzaria: otzaria,
        library: library,
        settings: settings,
        network: NetworkState.online,
        otzariaIsRunning: true,
        onRecheck: () async {},
        onGoToLibrary: () {},
        onGoToPlugins: () {},
      ),
    );

    expect(
      find.text('פתוחה כרגע — עדכון מסד חסום עד לסגירתה'),
      findsOneWidget,
    );
  });

  testWidgets('מסך הספרייה מציג מצב, מקור ותוכן להעברה', (tester) async {
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        onProcessStateChanged: () async {},
      ),
    );

    expect(find.text('מצב המסד'), findsOneWidget);
    expect(find.text('מקור העדכון'), findsOneWidget);
    expect(find.text('תוכן להעברה למחשב אחר'), findsOneWidget);
    // ברירת המחדל היא הרשת, ולכן אין כפתור "חזרה לעדכון מהרשת".
    expect(find.text('חזרה לעדכון מהרשת'), findsNothing);
  });

  testWidgets('מסך התוספים מציג מצב ריק אמיתי ולא רשימה מומצאת',
      (tester) async {
    await pumpScreen(tester, const PluginsScreen());

    expect(find.text('אין עדיין רשימת תוספים'), findsOneWidget);
    expect(find.text('חיפוש וסינון'), findsOneWidget);
  });

  testWidgets('מסך ההגדרות מציג את כל קטגוריות ההגדרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(controller: settings, onOpenLog: () {}),
    );

    expect(find.text('אוטומציה'), findsOneWidget);
    expect(find.text('ערוצי גרסאות'), findsOneWidget);
    expect(find.text('נתיבים ואחסון'), findsOneWidget);
    expect(find.text('רשת'), findsOneWidget);
    expect(find.text('ממשק ותמיכה'), findsOneWidget);
  });

  testWidgets('הפעלת התקנה אוטומטית דורשת אישור באזהרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(controller: settings, onOpenLog: () {}),
    );

    await tester.tap(find.text('התקנת עדכון תוכנת אוצריא'));
    await tester.pumpAndSettle();

    expect(find.text('התקנה אוטומטית של תוכנת אוצריא'), findsOneWidget);
    // ביטול משאיר את ההגדרה כבויה.
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(settings.settings.autoInstallApp, isFalse);

    await tester.tap(find.text('התקנת עדכון תוכנת אוצריא'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הפעל התקנה אוטומטית'));
    await tester.pumpAndSettle();

    expect(settings.settings.autoInstallApp, isTrue);
    // ההתקנה תלויה בהורדה, ולכן גם היא נדלקת.
    expect(settings.settings.autoDownloadApp, isTrue);
  });

  test('ברירות המחדל של ההגדרות נשמרות ונטענות מקובץ', () async {
    await settings.update(const AppSettings(autoDownloadLibrary: true));

    final reloaded = SettingsController(dataDir: tempDir.path);
    await reloaded.load();

    expect(reloaded.settings.autoDownloadLibrary, isTrue);
    expect(reloaded.settings.autoInstallLibrary, isFalse);
    reloaded.dispose();
  });
}
