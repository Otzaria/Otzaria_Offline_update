// בדיקות רינדור למסכי הדשבורד. המסכים נבדקים ישירות (ולא דרך AppShell),
// כדי שהבדיקה לא תיגע ברשת: הבנייה של הקונטרולרים אינה פונה לרשת, רק
// checkForUpdate/update — שלא נקראים כאן.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_screen.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:plugins_manager/plugins_manager.dart';

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
  late PluginsModuleController plugins;
  late SettingsController settings;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launcher_test');
    otzaria = OtzariaModuleController(dataDir: tempDir.path);
    library = LibraryModuleController(dataDir: tempDir.path);
    // מראה בתיקייה זמנית ריקה: הקטלוג לא קיים ולכן [load] מחזיר קטלוג ריק
    // בלי לגעת ברשת — בדיוק המצב שלפני הסנכרון הראשון.
    plugins = PluginsModuleController(mirrorRootDir: tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
  });

  /// דף הבית עם כל התלויות — נבנה כאן כדי שהוספת פרמטר לא תדרוש לגעת
  /// בכל בדיקה בנפרד.
  HomeScreen home({
    bool otzariaIsRunning = false,
    bool isDownloading = false,
    bool isCheckingOnline = false,
  }) =>
      HomeScreen(
        otzaria: otzaria,
        library: library,
        settings: settings,
        otzariaIsRunning: otzariaIsRunning,
        isDownloading: isDownloading,
        isCheckingOnline: isCheckingOnline,
        onCheckOnline: () async {},
        onDownloadAll: () async {},
        onGoToOtzaria: () {},
        onGoToLibrary: () {},
      );

  tearDown(() {
    otzaria.dispose();
    library.dispose();
    plugins.dispose();
    settings.dispose();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('דף הבית מציג שני אריחים ובדיקת עדכונים, ואינו טוען שמצב נבדק',
      (tester) async {
    await pumpScreen(tester, home());

    expect(find.text('תוכנת אוצריא'), findsWidgets);
    expect(find.text('ספריית הספרים'), findsWidgets);
    // מופיע פעמיים: כותרת הכרטיס וטקסט הכפתור הידני.
    expect(find.text('בדיקת עדכונים'), findsNWidgets(2));
    // המצב ההתחלתי אמור להיות "טרם נבדק", לא "מעודכן".
    expect(find.text('טרם נבדק'), findsWidgets);
    // אין יותר כרטיס תוספים או מתגי סנכרון בדף הבית — עברו להגדרות.
    expect(find.text('חנות התוספים'), findsNothing);
  });

  testWidgets('כפתור "הורד עכשיו" מופיע רק כשנמצא עדכון ברשת ומושבת בלי בחירה',
      (tester) async {
    await tester.runAsync(() => settings.update(const AppSettings(
          syncApp: false,
          syncLibrary: false,
          syncPlugins: false,
        )));
    await pumpScreen(tester, home());
    expect(find.text('הורד עכשיו'), findsNothing);

    // מדמה בדיקה קלה שמצאה עדכון — בלי לגעת ברשת בפועל.
    library.onlineLatestVersion = 99;
    library.onlineCheckedAt = DateTime(2026, 1, 1);
    await pumpScreen(tester, home());

    final button = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, 'הורד עכשיו'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('דף הבית מציג אזהרה כשאוצריא פתוחה', (tester) async {
    await pumpScreen(tester, home(otzariaIsRunning: true));

    expect(find.text('אוצריא פתוחה'), findsOneWidget);
    expect(find.text('עדכון הספרייה חסום עד לסגירתה.'), findsOneWidget);
  });

  testWidgets('מסך תוכנה מציג מצב ו"מה התחדש"', (tester) async {
    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        otzariaIsRunning: false,
        isDownloading: false,
      ),
    );

    expect(find.text('מצב ההתקנה'), findsOneWidget);
    expect(find.text('מה התחדש בגרסה האחרונה'), findsOneWidget);
    expect(
      find.text('אין תיאור לגרסה הזו, או שעדיין לא הורדה גרסה.'),
      findsOneWidget,
    );
  });

  testWidgets('מתגי הסנכרון עברו להגדרות ונשמרים', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        dataDir: tempDir.path,
        onOpenLog: () {},
      ),
    );

    expect(settings.settings.syncLibrary, isTrue);
    await tester.tap(find.text('הרכיב הכבד — המסד המלא הוא כ-1GB'));
    await tester.pumpAndSettle();

    expect(settings.settings.syncLibrary, isFalse);
  });

  testWidgets('מסך הספרייה מציג מצב ואת התיקייה שממנה מעדכנים', (tester) async {
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: () async {},
      ),
    );

    expect(find.text('מצב המסד'), findsOneWidget);
    expect(find.text('התיקייה שממנה מעדכנים'), findsOneWidget);
    // אין יותר בחירת מקור — התיקייה קבועה ליד התוכנה.
    expect(find.text('עדכון מתיקייה מקומית'), findsNothing);
    expect(find.text('חזרה לעדכון מהרשת'), findsNothing);
  });

  testWidgets('מסך החנות מציג מצב ריק אמיתי כשהמראה עוד ריקה', (tester) async {
    // הטעינה נעשית ב-runAsync: קריאות דיסק אמיתיות לא מסתיימות בתוך
    // ה-fake-async של testWidgets. באפליקציה עצמה AppShell קורא ל-load().
    await tester.runAsync(plugins.load);
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text('סנכרון מהאתר'), findsOneWidget);
    expect(find.text('טרם בוצע סנכרון'), findsOneWidget);
    expect(find.text('חיפוש'), findsOneWidget);
    expect(find.text('עדיין לא סונכרנו תוספים'), findsOneWidget);
  });

  testWidgets('מסך החנות מציג כרטיס תוסף מהקטלוג המקומי', (tester) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            StorePlugin.fromApi(const {
              'id': 'abc',
              'name': 'תוסף לבדיקה',
              'shortDescription': 'תקציר קצר',
              'description': 'תיאור מלא',
              'version': '1.2.3',
              'status': 'stable',
              'author': 'מחבר',
              'originalDate': '2026-04-02',
              'tags': ['לימוד'],
              'supportsDirectInstall': true,
              'downloadUrl': '/api/plugins/abc/download',
            }, 'https://otzaria.org'),
          ],
        )));

    await tester.runAsync(plugins.load);
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    expect(find.text('תוסף לבדיקה'), findsOneWidget);
    expect(find.text('גרסה 1.2.3'), findsOneWidget);
    expect(find.text('יציב'), findsWidgets);
    expect(find.text('בחרו את התוסף שמתאים לכם'), findsOneWidget);
    expect(find.text('כל התוספים מוצגים'), findsOneWidget);
    // תאריך עברי, כמו בחנות המקורית.
    expect(find.textContaining('ט"ו בניסן'), findsOneWidget);
  });

  testWidgets('מסך ההגדרות מציג את כל קטגוריות ההגדרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        dataDir: tempDir.path,
        onOpenLog: () {},
      ),
    );

    expect(find.text('אוטומציה'), findsOneWidget);
    expect(find.text('ערוצי גרסאות'), findsOneWidget);
    expect(find.text('אחסון'), findsOneWidget);
    expect(find.text('רשת'), findsOneWidget);
    expect(find.text('ממשק ותמיכה'), findsOneWidget);
    // אין יותר הגדרות נתיבים — התיקייה צמודה לתוכנה ואינה ניתנת לשינוי.
    expect(find.text('נתיבים ואחסון'), findsNothing);
    expect(find.text('בחירת תיקייה'), findsNothing);
  });

  testWidgets('הפעלת התקנה אוטומטית דורשת אישור באזהרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        dataDir: tempDir.path,
        onOpenLog: () {},
      ),
    );

    await tester.tap(find.text('התקנת תוכנת אוצריא אוטומטית'));
    await tester.pumpAndSettle();

    expect(find.text('התקנה אוטומטית של תוכנת אוצריא'), findsOneWidget);
    // ביטול משאיר את ההגדרה כבויה.
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(settings.settings.autoInstallApp, isFalse);

    await tester.tap(find.text('התקנת תוכנת אוצריא אוטומטית'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הפעל התקנה אוטומטית'));
    await tester.pumpAndSettle();

    expect(settings.settings.autoInstallApp, isTrue);
  });

  test('ערוץ התוספים נגזר לסינון ברירת המחדל של החנות', () {
    // לתוספים אין prerelease — "יציב בלבד" פירושו סינון ל-stable.
    expect(
      pluginStatusFilterFor(UpdateChannel.stable),
      PluginStatusFilter.stable,
    );
    expect(
      pluginStatusFilterFor(UpdateChannel.stableAndPreview),
      PluginStatusFilter.all,
    );
  });

  test('סינון ההתחלה של החנות נקבע מהערוץ', () {
    final controller = PluginsModuleController(
      mirrorRootDir: tempDir.path,
      initialStatusFilter: PluginStatusFilter.stable,
    );
    expect(controller.statusFilter, PluginStatusFilter.stable);
    controller.dispose();
  });

  test('ברירות המחדל של ההגדרות נשמרות ונטענות מקובץ', () async {
    await settings.update(const AppSettings(syncLibrary: false));

    final reloaded = SettingsController(dataDir: tempDir.path);
    await reloaded.load();

    expect(reloaded.settings.syncLibrary, isFalse);
    expect(reloaded.settings.autoInstallLibrary, isFalse);
    reloaded.dispose();
  });
}
