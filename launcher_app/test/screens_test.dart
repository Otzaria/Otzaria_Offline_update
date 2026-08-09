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
import 'package:launcher_app/src/screens/plugins/plugin_store_card.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

/// משטח בדיקה גבוה — ה-ListView של [ScreenBody] בונה רק את מה שנראה,
/// ובחלון ברירת המחדל (800x600) הכרטיסים התחתונים לא היו נבנים בכלל.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  AppLanguage language = AppLanguage.hebrew,
}) async {
  tester.view.physicalSize = const Size(1400, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(screen, language: language));
}

/// עוטף מסך באותו MaterialApp שהאפליקציה בונה — כולל locale he-IL, שהוא
/// מה שקובע RTL גלובלי לכל עץ ה-widgets, ו-[AppStringsScope] שממנו המסכים
/// שואבים את המלל. שניהם חייבים להיות כאן כמו ב-`main.dart`, אחרת
/// `context.strings` נופל.
Widget wrap(Widget child, {AppLanguage language = AppLanguage.hebrew}) =>
    MaterialApp(
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL'), Locale('en')],
      locale: language == AppLanguage.hebrew
          ? const Locale('he', 'IL')
          : const Locale('en'),
      theme: AppThemeData.light(
        AppThemeData.createColorScheme(
          AppSeedColors.defaultLight,
          Brightness.light,
        ),
      ),
      builder: (context, navigator) => AppStringsScope(
        strings: AppL10n.stringsFor(language),
        child: navigator ?? const SizedBox.shrink(),
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
        plugins: plugins,
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
    expect(find.text('הספרייה'), findsWidgets);
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
        settings: settings,
        otzariaIsRunning: false,
      ),
    );

    expect(find.text('מצב ההתקנה'), findsOneWidget);
    expect(find.text('מה התחדש בגרסה האחרונה'), findsOneWidget);
    expect(
      find.text('אין תיאור לגרסה הזו, או שעדיין לא הורדה גרסה.'),
      findsOneWidget,
    );
    // בלי שתי גרסאות בתיקייה אין מה לבחור, ולכן אין פקד ערוץ.
    expect(find.text('הגרסה שתותקן'), findsNothing);
  });

  testWidgets('בחירת ערוץ מוצגת רק כשיש שתי גרסאות, ונשמרת בהגדרות',
      (tester) async {
    // מדמה מראה עם שתי גרסאות — בלי לגעת בדיסק או ברשת.
    otzaria.hasChannelChoice = true;
    otzaria.stableVersion = '0.9.90';
    otzaria.prereleaseVersion = '0.9.97';
    otzaria.latestVersion = '0.9.90';

    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
      ),
    );

    expect(find.text('הגרסה שתותקן'), findsOneWidget);
    expect(find.textContaining('הגרסה היציבה (0.9.90)'), findsOneWidget);

    await tester.tap(find.text('לא יציבה'));
    await tester.pumpAndSettle();

    expect(settings.settings.preferAppPrerelease, isTrue);
  });

  testWidgets('בחירת מיקום ידנית לאוצריא לא מושבתת בגלל הורדה של רכיב אחר',
      (tester) async {
    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
      ),
    );

    final button = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, 'בחירת מיקום ידנית'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('מתגי הסנכרון עברו להגדרות ונשמרים', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
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
    expect(find.text('עדיין לא סונכרנו תוספים'), findsOneWidget);
    // מראה ריקה — לא מציגים סינון על כלום.
    expect(find.text('חיפוש'), findsNothing);
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
    // מראה בלי אצירה (לא נבחרים ולא קטגוריות בית) נופלת ל"כל התוספים",
    // כמו דף הבית הריק באתר ששולח לרשימה המלאה.
    expect(find.text('בחרו את התוסף שמתאים לכם'), findsOneWidget);
    expect(find.text('כל התוספים מוצגים'), findsOneWidget);
    expect(find.text('חיפוש'), findsOneWidget);
    // תאריך עברי, כמו בחנות המקורית.
    expect(find.textContaining('ט"ו בניסן'), findsOneWidget);
  });

  testWidgets('כרטיס עמוס בכרטיס הצר ביותר אינו גולש', (tester) async {
    // המקרה הגרוע: שם ארוך, תקציר ארוך, ארבע תגיות, ושבב "עדכון זמין"
    // (שמופיע רק כשמותקנת גרסה ישנה) — כל אלה מרחיבים את שורות הגלולות.
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            for (var i = 0; i < 4; i++)
              StorePlugin.fromApi({
                'id': 'p$i',
                'name': 'שם ארוך במיוחד לתוסף שנועד לתפוס שתי שורות שלמות',
                'shortDescription':
                    'תקציר ארוך שנמשך על פני כמה שורות כדי לבדוק שהכרטיס '
                        'אינו גולש גם כשהטקסט מגיע למקסימום השורות המותר בו',
                'version': '10.20.30',
                'status': 'experimental',
                'downloadCount': 123456,
                'tags': const ['תגית ארוכה', 'עוד אחת', 'שלישית', 'רביעית'],
                'supportsDirectInstall': true,
              }, 'https://otzaria.org')
                  .copyWith(manifestId: 'id-$i'),
          ],
        )));

    // חלון צר → הכרטיס הצר ביותר שהרשת מייצרת.
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(plugins.load);
    // סריקת ההתקנה האמיתית מגיעה מתיקיית אוצריא של המכונה; כאן מזריקים
    // גרסאות מותקנות ישנות ישירות, כדי שהשבב הארוך ביותר ייבנה.
    plugins.installed = {for (var i = 0; i < 4; i++) 'id-$i': '1.0.0'};

    await tester.pumpWidget(wrap(PluginsScreen(controller: plugins)));
    await tester.pumpAndSettle();

    // שבב "עדכון זמין" אכן מוצג — אחרת הבדיקה לא באמת בודקת את המקרה הגרוע.
    expect(find.textContaining('עדכון זמין'), findsWidgets);
    // גלישת RenderFlex נזרקת כחריג בבדיקות; אין צורך ב-expect נוסף.
    expect(tester.takeException(), isNull);

    // גם בהגדלת טקסט — גובה הכרטיס מוכפל ב-textScaler, וזו הנקודה שבה
    // ההכפלה הזו נבדקת בפועל.
    await tester.pumpWidget(wrap(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: PluginsScreen(controller: plugins),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('מתג "רק מה שלא מותקן" בשורה העליונה חל גם על דף הבית',
      (tester) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            StorePlugin.fromApi(const {
              'id': 'a',
              'name': 'תוסף שכבר מותקן',
              'version': '1.0.0',
              'status': 'stable',
              'isPinned': true,
            }, 'https://otzaria.org')
                .copyWith(manifestId: 'id-a'),
            StorePlugin.fromApi(const {
              'id': 'b',
              'name': 'תוסף שאינו מותקן',
              'version': '1.0.0',
              'status': 'stable',
              'isPinned': true,
            }, 'https://otzaria.org'),
          ],
        )));

    await tester.runAsync(plugins.load);
    plugins.installed = {'id-a': '1.0.0'};

    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    // המתג דלוק כברירת מחדל — המותקן והמעודכן מוסתר גם בסעיף הנבחרים.
    expect(find.text('רק מה שלא מותקן'), findsOneWidget);
    expect(find.text('תוסף שאינו מותקן'), findsOneWidget);
    expect(find.text('תוסף שכבר מותקן'), findsNothing);

    await tester.tap(find.text('רק מה שלא מותקן'));
    await tester.pumpAndSettle();

    expect(find.text('תוסף שכבר מותקן'), findsOneWidget);
  });

  testWidgets('הרשת מציגה שלושה כרטיסים בשורה בחלון בינוני', (tester) async {
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            for (var i = 0; i < 6; i++)
              StorePlugin.fromApi({
                'id': 'p$i',
                'name': 'תוסף מספר $i',
                'shortDescription': 'תקציר',
                'status': 'stable',
                'tags': const ['לימוד', 'עיצוב'],
                'supportsDirectInstall': true,
              }, 'https://otzaria.org'),
          ],
        )));

    // חלון בינוני — בדיוק המקרה שבו האתר כבר מציג שלוש עמודות.
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(plugins.load);
    await tester.pumpWidget(wrap(PluginsScreen(controller: plugins)));
    await tester.pumpAndSettle();

    // שלושה כרטיסים חולקים את אותה קואורדינטת y — כלומר שורה אחת.
    final cards = tester
        .widgetList<PluginStoreCard>(find.byType(PluginStoreCard))
        .toList();
    expect(cards.length, greaterThanOrEqualTo(3));
    final firstRowTop =
        tester.getTopLeft(find.byType(PluginStoreCard).first).dy;
    final inFirstRow = [
      for (var i = 0; i < cards.length; i++)
        if (tester.getTopLeft(find.byType(PluginStoreCard).at(i)).dy ==
            firstRowTop)
          i,
    ];
    expect(inFirstRow.length, 3);
  });

  testWidgets('החנות נפתחת בדף הבית האצור, ומשם לדף קטגוריה ולכל התוספים',
      (tester) async {
    StorePlugin plugin(String id, String name,
            {bool featured = false, List<String> categories = const []}) =>
        StorePlugin.fromApi({
          'id': id,
          'name': name,
          'status': 'stable',
          'isPinned': featured,
        }, 'https://otzaria.org')
            .copyWith(categorySlugs: categories);

    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            plugin('a', 'תוסף נבחר', featured: true, categories: ['study']),
            plugin('b', 'תוסף אחר'),
          ],
          categories: const [
            PluginStoreCategory(
              slug: 'study',
              name: 'כלי לימוד',
              description: 'תוספים שמסייעים בלימוד',
              showOnHome: true,
              pluginIds: ['a'],
            ),
          ],
          home: const PluginStoreHome(
            title: 'החנות של אוצריא',
            subtitle: 'תוספים שמרחיבים את הלימוד',
          ),
        )));

    await tester.runAsync(plugins.load);
    await pumpScreen(tester, PluginsScreen(controller: plugins));
    await tester.pumpAndSettle();

    // דף הבית: hero עם הטקסטים מהאתר, וסעיף "תוספים נבחרים".
    expect(find.text('החנות של אוצריא'), findsOneWidget);
    expect(find.text('תוספים שמרחיבים את הלימוד'), findsOneWidget);
    expect(find.text('מומלצי החנות'), findsOneWidget);
    expect(find.text('תוספים נבחרים'), findsOneWidget);
    // דף הבית מציג אצירה בלבד — אין בו סינון (רק חיפוש ב-hero).
    expect(find.text('סטטוס'), findsNothing);

    // שורת הקטגוריה של דף הבית, ו"לכל הקטגוריה" שפותח את דף הקטגוריה.
    expect(find.text('תוספים שמסייעים בלימוד'), findsWidgets);
    await tester.tap(find.text('לכל הקטגוריה (1)'));
    await tester.pumpAndSettle();

    expect(find.text('תוסף אחד בקטגוריה'), findsOneWidget);
    expect(find.text('תוסף נבחר'), findsWidgets);
    expect(find.text('תוסף אחר'), findsNothing);

    // פירורי הלחם מחזירים לדף הבית, ומשם אל "כל התוספים".
    await tester.tap(find.text('חנות התוספים'));
    await tester.pumpAndSettle();
    expect(find.text('תוספים נבחרים'), findsOneWidget);

    await tester.tap(find.text('עיינו בכל התוספים (2)'));
    await tester.pumpAndSettle();

    expect(find.text('בחרו את התוסף שמתאים לכם'), findsOneWidget);
    expect(find.text('חיפוש'), findsOneWidget);
    expect(find.text('תוסף אחר'), findsWidgets);
  });

  testWidgets('מסך ההגדרות מציג את כל קטגוריות ההגדרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
      ),
    );

    expect(find.text('אוטומציה'), findsOneWidget);
    expect(find.text('אחסון'), findsOneWidget);
    expect(find.text('רשת'), findsOneWidget);
    expect(find.text('ממשק ותמיכה'), findsOneWidget);
    // אין יותר הגדרות נתיבים — התיקייה צמודה לתוכנה ואינה ניתנת לשינוי.
    expect(find.text('נתיבים ואחסון'), findsNothing);
    expect(find.text('בחירת תיקייה'), findsNothing);
    // ערוץ הגרסאות קבוע ואינו הגדרה, וההתקנה האוטומטית של תוספים לא קיימת.
    expect(find.text('ערוצי גרסאות'), findsNothing);
    expect(find.text('התקנת תוספים אוטומטית'), findsNothing);
  });

  testWidgets('מסך ההגדרות באנגלית — הכול מתורגם והכיוון מתהפך',
      (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(controller: settings, onOpenLog: () {}),
      language: AppLanguage.english,
    );

    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Interface and support'), findsOneWidget);
    expect(find.text('Interface language'), findsOneWidget);
    expect(find.text('אוטומציה'), findsNothing);

    final direction = Directionality.of(
      tester.element(find.text('Automation')),
    );
    expect(direction, TextDirection.ltr);
  });

  testWidgets('בחירת שפה נשמרת בהגדרות ומחליפה את המלל', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(controller: settings, onOpenLog: () {}),
    );

    expect(settings.settings.language, AppLanguage.hebrew);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(settings.settings.language, AppLanguage.english);
    // ה-scope כאן קבוע לעברית (הוא נבנה פעם אחת ב-`wrap`), ולכן הבדיקה
    // היא על ההגדרה עצמה ועל המצב הגלובלי שהיא מזליגה לחבילות התשתית.
    expect(AppL10n.language, AppLanguage.english);
    addTearDown(() => AppL10n.use(AppLanguage.hebrew));
  });

  testWidgets('הפעלת התקנה אוטומטית דורשת אישור באזהרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
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

  test('החנות נפתחת מציגה את הכול, לא רק יציב', () {
    final controller = PluginsModuleController(mirrorRootDir: tempDir.path);
    expect(controller.statusFilter, PluginStatusFilter.all);
    controller.dispose();
  });

  test('ברירות המחדל של ההגדרות נשמרות ונטענות מקובץ', () async {
    await settings.update(
      const AppSettings(syncLibrary: false, preferAppPrerelease: true),
    );

    final reloaded = SettingsController(dataDir: tempDir.path);
    await reloaded.load();

    expect(reloaded.settings.syncLibrary, isFalse);
    expect(reloaded.settings.autoInstallLibrary, isFalse);
    // ברירת המחדל היא הגרסה היציבה, והבחירה שורדת הפעלה מחדש.
    expect(const AppSettings().preferAppPrerelease, isFalse);
    expect(reloaded.settings.preferAppPrerelease, isTrue);
    reloaded.dispose();
  });
}
