// בדיקות רינדור למסכי הדשבורד. המסכים נבדקים ישירות (ולא דרך AppShell),
// כדי שהבדיקה לא תיגע ברשת: הבנייה של הקונטרולרים אינה פונה לרשת, רק
// checkForUpdate/update — שלא נקראים כאן.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_screen.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_card.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/screens/setup_error_screen.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/self_update/launcher_version.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/theme/theme_exports.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import 'test_harness.dart';

void main() {
  late Directory tempDir;
  late OtzariaModuleController otzaria;
  late LibraryModuleController library;
  late PluginsModuleController plugins;
  late SettingsController settings;
  late LauncherUpdateController launcherUpdate;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launcher_test');
    otzaria = OtzariaModuleController(dataDir: tempDir.path);
    library = LibraryModuleController(dataDir: tempDir.path);
    // תיקייה זמנית ריקה: אין מראה, ולכן הבדיקה המקומית עונה "אין מה להתקין"
    // בלי לגעת ברשת. הבנייה עצמה לא פונה לשום מקום.
    launcherUpdate = LauncherUpdateController(dataDir: tempDir.path);
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
    Future<bool> Function()? onProcessStateChanged,
  }) =>
      HomeScreen(
        otzaria: otzaria,
        library: library,
        plugins: plugins,
        launcherUpdate: launcherUpdate,
        settings: settings,
        otzariaIsRunning: otzariaIsRunning,
        isDownloading: isDownloading,
        isCheckingOnline: isCheckingOnline,
        onProcessStateChanged: onProcessStateChanged ?? () async => false,
        onCheckOnline: () async {},
        onDownloadAll: () async {},
        onDownloadLauncherUpdate: () async {},
        onInstallLauncherUpdate: () async {},
        onRequestReindex: () async {},
        onGoToOtzaria: () {},
        onGoToLibrary: () {},
      );

  tearDown(() {
    otzaria.dispose();
    library.dispose();
    plugins.dispose();
    launcherUpdate.dispose();
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

  // ── עדכון הלאנצ'ר עצמו ───────────────────────────────────────────────────

  testWidgets('כרטיס עדכון התוכנה נעדר כשאין מה לומר', (tester) async {
    final t = stringsOf().launcherUpdate;
    await pumpScreen(tester, home());

    // המצב הרגיל: התוכנה מעודכנת, ומספר הגרסה יושב בהגדרות.
    expect(find.text(t.cardTitle), findsNothing);
    expect(find.text(t.downloadButton), findsNothing);
    expect(find.text(t.installButton), findsNothing);
  });

  testWidgets('נמצאה גרסה חדשה ברשת — הכרטיס מציע להוריד, ולא להתקין',
      (tester) async {
    final t = stringsOf().launcherUpdate;
    // מדמה בדיקה קלה שמצאה עדכון, בלי לגעת ברשת.
    launcherUpdate.onlineRelease = const LauncherRelease(
      tagName: 'v9.9.9',
      name: 'Otzaria Updates v9.9.9',
      assetName: 'עדכוני אוצריא.exe',
      downloadUrl: 'https://example/x.exe',
      sizeBytes: 42 << 20,
    );
    launcherUpdate.onlineCheckedAt = DateTime(2026, 8, 1);

    await pumpScreen(tester, home());

    expect(find.text(t.cardTitle), findsOneWidget);
    expect(find.text(t.statusUpdateAvailable), findsOneWidget);
    expect(find.text(t.onlineVersion('9.9.9')), findsOneWidget);
    expect(find.text(t.downloadButton), findsOneWidget);
    // עוד לא הורד כלום, ולכן אין מה להתקין.
    expect(find.text(t.installButton), findsNothing);
  });

  testWidgets('גרסה שהורדה — הכרטיס מציע התקנה, וגם בלי רשת', (tester) async {
    final t = stringsOf().launcherUpdate;
    launcherUpdate.status = LauncherUpdateStatus.readyToInstall;
    launcherUpdate.downloadedVersion = '9.9.9';
    launcherUpdate.canInstall = true;

    await pumpScreen(tester, home());

    expect(find.text(t.statusReadyToInstall), findsOneWidget);
    expect(find.text(t.downloadedVersion('9.9.9')), findsOneWidget);
    expect(find.text(t.installButton), findsOneWidget);
    expect(find.text(t.downloadButton), findsNothing);
  });

  testWidgets('בלי נתיב לקובץ ההרצה אין כפתור התקנה שייכשל בלחיצה',
      (tester) async {
    final t = stringsOf().launcherUpdate;
    launcherUpdate.status = LauncherUpdateStatus.readyToInstall;
    launcherUpdate.downloadedVersion = '9.9.9';
    launcherUpdate.canInstall = false;

    await pumpScreen(tester, home());

    expect(find.text(t.statusReadyToInstall), findsOneWidget);
    expect(find.text(t.installButton), findsNothing);
  });

  /// הכפתור בדף הבית קיים רק כשיש מה לעדכן — כאן זה מוצב ידנית, בלי דיסק.
  void fakeLibraryUpdateAvailable() {
    library.status = LibraryModuleStatus.updateAvailable;
    library.localVersion = 1;
    library.targetVersion = 2;
  }

  testWidgets('עדכון הספרייה נחסם לפי בדיקה טרייה — לא לפי מה שמוצג במסך',
      (tester) async {
    fakeLibraryUpdateAvailable();
    var checks = 0;
    // המסך עלה כשאוצריא הייתה פתוחה, ומאז היא נסגרה. קודם לחיצה על "עדכון"
    // נחסמה לנצח לפי הערך שנלכד בבנייה — עד להפעלה מחדש של הלאנצ'ר.
    await pumpScreen(
      tester,
      home(
        otzariaIsRunning: true,
        onProcessStateChanged: () async {
          checks++;
          return false;
        },
      ),
    );

    await tester.tap(find.widgetWithText(ActionButton, 'עדכון'));
    await tester.pumpAndSettle();

    expect(checks, 1);
    expect(find.text('עדכון הספרייה'), findsOneWidget);
    expect(find.text('עדכן עכשיו'), findsOneWidget);
  });

  testWidgets('אוצריא שנפתחה מאז הבנייה כן חוסמת — הבדיקה הטרייה קובעת',
      (tester) async {
    fakeLibraryUpdateAvailable();
    var checks = 0;
    await pumpScreen(
      tester,
      home(
        otzariaIsRunning: false,
        onProcessStateChanged: () async {
          checks++;
          return true;
        },
      ),
    );

    await tester.tap(find.widgetWithText(ActionButton, 'עדכון'));
    await tester.pumpAndSettle();

    // `checks` מוודא שהחסימה אכן קרתה, ולא שהלחיצה פשוט לא עשתה כלום.
    expect(checks, 1);
    // אין דיאלוג אישור: העדכון נחסם (ההודעה עצמה יוצאת ב-UiSnack, שדורש
    // navigatorKey ולכן אינו נבנה בבדיקת מסך בודד).
    expect(find.text('עדכון הספרייה'), findsNothing);
    expect(find.text('עדכן עכשיו'), findsNothing);
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
        launcherVersion: launcherVersion,
      ),
    );

    expect(settings.settings.syncLibrary, isTrue);
    await tester.tap(find.text('הרכיב הכבד — המסד המלא הוא כ-1.5GB'));
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
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
      ),
    );

    expect(find.text('מצב המסד'), findsOneWidget);
    expect(find.text('התיקייה שממנה מעדכנים'), findsOneWidget);
    // אין יותר בחירת מקור — התיקייה קבועה ליד התוכנה.
    expect(find.text('עדכון מתיקייה מקומית'), findsNothing);
    expect(find.text('חזרה לעדכון מהרשת'), findsNothing);
  });

  testWidgets('מסך הספרייה חוסם לפי בדיקה טרייה — לא לפי מה שמוצג',
      (tester) async {
    fakeLibraryUpdateAvailable();
    var checks = 0;
    // אותו תיקון כמו בדף הבית, ובמסך אחר: המסך עלה כשאוצריא הייתה פתוחה,
    // ומאז נסגרה — והעדכון היה נחסם עד להפעלה מחדש של הלאנצ'ר.
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: true,
        isDownloading: false,
        onProcessStateChanged: () async {
          checks++;
          return false;
        },
        onRequestReindex: () async {},
      ),
    );

    await tester.tap(find.widgetWithText(ActionButton, 'התקנת העדכון'));
    await tester.pumpAndSettle();

    expect(checks, 1);
    expect(find.text('עדכן עכשיו'), findsOneWidget);
  });

  testWidgets('מסך הספרייה: אוצריא שנפתחה מאז הבנייה כן חוסמת', (tester) async {
    fakeLibraryUpdateAvailable();
    var checks = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: () async {
          checks++;
          return true;
        },
        onRequestReindex: () async {},
      ),
    );

    await tester.tap(find.widgetWithText(ActionButton, 'התקנת העדכון'));
    await tester.pumpAndSettle();

    expect(checks, 1);
    expect(find.text('עדכן עכשיו'), findsNothing);
  });

  // issue #19: patch שאינו מתאים למסד המקומי הותיר את המשתמש תקוע — אין
  // בממשק שום דרך להתקין במקומו את המסד המלא שממילא יושב במראה.
  testWidgets('כפתור הספרייה המלאה מופיע רק אחרי כשל, ופותח דיאלוג אישור',
      (tester) async {
    final t = stringsOf().libraryScreen;
    fakeLibraryUpdateAvailable();

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
      ),
    );
    expect(
      find.widgetWithText(ActionButton, t.fullDownloadInsteadButton),
      findsNothing,
    );

    // כמו אחרי כשל אמיתי של מסלול הדלתא. המסך הוא StatelessWidget שנבנה
    // מחדש על ידי המסגרת, ולכן הבדיקה בונה אותו שוב ולא מסתמכת על notify.
    library.status = LibraryModuleStatus.error;
    library.errorMessage = 'ה-patch אינו מתאים למסד';
    library.canRetryWithFullDownload = true;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
      ),
    );

    await tester
        .tap(find.widgetWithText(ActionButton, t.fullDownloadInsteadButton));
    await tester.pumpAndSettle();

    // הדיאלוג בלבד — ההתקנה עצמה נוגעת בדיסק ואינה חלק מבדיקת המסך.
    // הגודל לא ידוע כאן (אין בדיקה אמיתית מאחור), וזה בדיוק מה שמוצג.
    expect(
      find.text(
        t.fullDownloadInsteadPrompt(stringsOf().common.unknownValue),
      ),
      findsOneWidget,
    );
  });

  // עדכון מסד שנעשה מכאן משאיר את אינדקס החיפוש של אוצריא על התוכן הישן,
  // והבקשה לתקן זאת חייבת להיות נגישה גם אחרי שהמשתמש דחה אותה פעם אחת.
  testWidgets('אריח בקשת עדכון האינדקס מופיע רק כשיש בקשה ממתינה',
      (tester) async {
    final t = stringsOf().libraryScreen;
    var requests = 0;

    Future<void> pumpLibrary() => pumpScreen(
          tester,
          LibraryScreen(
            library: library,
            otzariaIsRunning: false,
            isDownloading: false,
            onProcessStateChanged: () async => false,
            onRequestReindex: () async => requests++,
          ),
        );

    await pumpLibrary();
    expect(find.text(t.reindexTitle), findsNothing);

    // כמו אחרי עדכון מסד מוצלח: הסימון נקרא בבדיקה ויושב בקונטרולר.
    library.pendingReindex = const ExternalUpdateNoticeData(
      route: ExternalUpdateNotice.routeDelta,
      booksTouched: {3, 9},
      dbVersion: 42,
    );
    await pumpLibrary();

    expect(find.text(t.reindexTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionButton, t.reindexButton));
    await tester.pump();

    // הדיאלוג והמסירה עצמה יושבים ב-`AppShell` — כאן נבדק שהאריח קורא לו.
    expect(requests, 1);
  });

  testWidgets('"בדוק שוב" במסך הספרייה מרענן גם את מצב התהליך', (tester) async {
    // האזהרה "אוצריא פתוחה" יושבת באותו כרטיס, ולכן הכפתור שמתחתיה חייב
    // לרענן גם אותה ולא רק את גרסת המסד.
    var checks = 0;
    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: true,
        isDownloading: false,
        onProcessStateChanged: () async {
          checks++;
          return false;
        },
        onRequestReindex: () async {},
      ),
    );

    // בלי pumpAndSettle: בדיקת הספרייה שאחריה קוראת מהדיסק ואינה מסתיימת
    // בתוך ה-fake-async. ה-pump הארוך רק מנקז את סיבוב-המינימום של הכפתור.
    await tester.tap(find.widgetWithText(ActionButton, 'בדיקה מחדש'));
    await tester.pump();

    expect(checks, 1);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('מסך החנות מציג מצב ריק אמיתי כשהמראה עוד ריקה', (tester) async {
    // הטעינה נעשית ב-runAsync: קריאות דיסק אמיתיות לא מסתיימות בתוך
    // ה-fake-async של testWidgets. באפליקציה עצמה AppShell קורא ל-load().
    await tester.runAsync(plugins.load);
    // הסריקה שב-load קוראת מההתקנה האמיתית של אוצריא במחשב הזה; הבדיקה
    // אינה נשענת עליה, ולכן המפה מאופסת מיד.
    plugins.installed = const {};
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
    // הסריקה שב-load קוראת מההתקנה האמיתית של אוצריא במחשב הזה; הבדיקה
    // אינה נשענת עליה, ולכן המפה מאופסת מיד.
    plugins.installed = const {};
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

  testWidgets('כרטיס עמוס בכרטיס הצר ביותר אינו גולש — בכל הגדלה ובשתי השפות',
      (tester) async {
    // המקרה הגרוע: שם ארוך, תקציר ארוך, ארבע תגיות עבריות ארוכות, מונה
    // הורדות בן שש ספרות ושבב "עדכון זמין" (שמופיע רק כשמותקנת גרסה
    // ישנה) — כל אלה מרחיבים את שתי שורות הגלולות שהכרטיס תוקצב עבורן.
    final store = PluginMirrorStore(tempDir.path);
    await tester.runAsync(() => store.save(PluginCatalog(
          lastSync: DateTime.utc(2026, 8, 6),
          plugins: [
            for (var i = 0; i < 5; i++)
              StorePlugin.fromApi({
                'id': 'p$i',
                'name': 'שם ארוך במיוחד לתוסף שנועד לתפוס שתי שורות שלמות',
                'shortDescription':
                    'תקציר ארוך שנמשך על פני כמה שורות כדי לבדוק שהכרטיס '
                        'אינו גולש גם כשהטקסט מגיע למקסימום השורות המותר בו',
                'version': '10.20.30',
                'status': 'experimental',
                'downloadCount': 123456,
                'isPinned': true,
                'tags': const [
                  'תגית ארוכה למדי',
                  'עוד תגית',
                  'שלישית',
                  'רביעית',
                ],
                'supportsDirectInstall': true,
              }, 'https://otzaria.org')
                  // התוסף האחרון נשאר בלי manifestId: קובץ שטרם הורד מדווח
                  // PluginInstallStatus.unknown, וזה מצב תקין ולא שגיאה.
                  .copyWith(manifestId: i == 4 ? null : 'id-$i'),
          ],
        )));

    await tester.runAsync(plugins.load);
    // סריקת ההתקנה האמיתית מגיעה מתיקיית אוצריא של המכונה; כאן מזריקים
    // גרסאות מותקנות ישנות ישירות, כדי שהשבב הארוך ביותר ייבנה.
    plugins.installed = {for (var i = 0; i < 4; i++) 'id-$i': '1.0.0'};

    // 584/620 = שתי עמודות צרות, 700 = שתיים רחבות, 1160 = שלוש. שתי
    // השפות וכל ההגדלות שהמשתמש יכול לבחור (0.9/1.0/1.15), ומעליהן 1.3
    // ו-1.5 מהגדלת המערכת. אנגלית היא המקרה הצפוף — התקציב אינו תלוי שפה.
    final cases = <({double width, AppLanguage language, double scale})>[
      for (final width in [584.0, 620.0, 700.0, 1160.0])
        for (final language in AppLanguage.values)
          for (final scale in [0.9, 1.0, 1.15, 1.3, 1.5])
            (width: width, language: language, scale: scale),
    ];

    for (final c in cases) {
      final t = stringsOf(c.language).plugins;
      useViewSize(tester, Size(c.width, 1400));
      AppL10n.use(c.language);
      addTearDown(() => AppL10n.use(AppLanguage.hebrew));

      // עץ נקי בין שילוב לשילוב: `RenderFlex` מדווח על גלישה **פעם אחת**
      // לכל render object, ובלי איפוס שילוב גולש היה נבלע בשקט.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        wrap(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(c.scale)),
            child: PluginsScreen(controller: plugins),
          ),
          language: c.language,
        ),
      );
      await tester.pumpAndSettle();

      // השבב אכן מוצג — אחרת הבדיקה לא באמת בודקת את המקרה הגרוע.
      expect(
        find.text(t.installChipUpdateAvailable),
        findsWidgets,
        reason: 'שבב "עדכון זמין" חסר ב-$c',
      );
      // גלישת RenderFlex נזרקת כחריג; אין צורך ב-expect נוסף.
      expect(tester.takeException(), isNull, reason: 'הכרטיס גלש ב-$c');
    }
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
    plugins.installed = const {};
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
    // הסריקה שב-load קוראת מההתקנה האמיתית של אוצריא במחשב הזה; הבדיקה
    // אינה נשענת עליה, ולכן המפה מאופסת מיד.
    plugins.installed = const {};
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
        launcherVersion: launcherVersion,
      ),
    );

    expect(find.text('אוטומציה'), findsOneWidget);
    expect(find.text('הורדה'), findsOneWidget);
    expect(find.text('שפה ומראה'), findsOneWidget);
    expect(find.text('תמיכה'), findsOneWidget);
    // שפה ומראה הם הכרטיס הראשון, לפני האוטומציה.
    expect(
      tester.getTopLeft(find.text('שפה ומראה')).dy,
      lessThan(tester.getTopLeft(find.text('אוטומציה')).dy),
    );
    // ההגדרה "timeout להורדה" הוסרה — הזמן הקצוב נקבע בלקוחות עצמם.
    expect(find.text('רשת'), findsNothing);
    expect(find.text('timeout להורדה'), findsNothing);
    // אין יותר הגדרות נתיבים — התיקייה צמודה לתוכנה ואינה ניתנת לשינוי.
    expect(find.text('נתיבים ואחסון'), findsNothing);
    expect(find.text('בחירת תיקייה'), findsNothing);
    // גיבוי המסד בוטל לגמרי — אין כרטיס אחסון ואין מה לכבות/להדליק.
    expect(find.text('אחסון'), findsNothing);
    expect(find.text('גיבוי בטיחות של המסד'), findsNothing);
    // ערוץ הגרסאות קבוע ואינו הגדרה, וההתקנה האוטומטית של תוספים לא קיימת.
    expect(find.text('ערוצי גרסאות'), findsNothing);
    expect(find.text('התקנת תוספים אוטומטית'), findsNothing);
  });

  testWidgets('מסך ההגדרות באנגלית — הכול מתורגם והכיוון מתהפך',
      (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
      language: AppLanguage.english,
    );

    // מול מלל ה-l10n עצמו ולא מול מחרוזות קבועות: ליטוש נוסח באנגלית הוא
    // שינוי לגיטימי, וכשהוא הפיל את הבדיקה הזאת הוא הפיל איתה את כל ה-CI.
    // מה שנבדק כאן הוא שהמסך אכן מתורגם ומתהפך, לא איך בדיוק הוא מנוסח.
    const en = EnglishStrings();
    expect(find.text(en.settings.automationCardTitle), findsOneWidget);
    expect(find.text(en.settings.downloadCardTitle), findsOneWidget);
    expect(find.text(en.settings.appearanceCardTitle), findsOneWidget);
    expect(find.text(en.settings.supportCardTitle), findsOneWidget);
    expect(find.text(en.settings.languageTitle), findsOneWidget);
    expect(find.text(const HebrewStrings().settings.automationCardTitle),
        findsNothing);

    final direction = Directionality.of(
      tester.element(find.text(en.settings.automationCardTitle)),
    );
    expect(direction, TextDirection.ltr);
  });

  testWidgets('בחירת שפה נשמרת בהגדרות ומחליפה את המלל', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    // ברירת המחדל היא "אוטומטי" — לפי שפת המחשב.
    expect(settings.settings.languagePreference, AppLanguagePreference.system);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(settings.settings.languagePreference, AppLanguagePreference.english);
    expect(settings.settings.language, AppLanguage.english);
    // ה-scope כאן קבוע לעברית (הוא נבנה פעם אחת ב-`wrap`), ולכן הבדיקה
    // היא על ההגדרה עצמה ועל המצב הגלובלי שהיא מזליגה לחבילות התשתית.
    expect(AppL10n.language, AppLanguage.english);
    addTearDown(() => AppL10n.use(AppLanguage.hebrew));

    // וחזרה לאוטומטי — הבחירה המפורשת ניתנת לביטול. המסך נבנה מחדש כדי
    // שהסגמנט הנבחר יתעדכן: `SegmentedButton` מתעלם מהקשה על הנבחר.
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );
    await tester.tap(find.text('אוטומטי'));
    await tester.pumpAndSettle();

    expect(settings.settings.languagePreference, AppLanguagePreference.system);
  });

  testWidgets('פלטת הצבעים בוחרת, מאפסת ונשמרת', (tester) async {
    final t = stringsOf().settings;

    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
      ),
    );

    // ברירת המחדל היא הגוון הבהיר של אוצריא, והשורה מציגה את שמו.
    expect(find.text(t.seedColorTitle), findsOneWidget);
    expect(find.text(t.colorDarkBrown), findsOneWidget);

    await tester.tap(find.text(t.seedColorButton));
    await tester.pumpAndSettle();

    expect(find.text(t.seedColorDialogTitle), findsOneWidget);
    // כל צבע בפלטה מוצג עם שמו — זה מה שמכריח מלל מתורגם לכולם.
    for (final option in AppSeedColors.options) {
      expect(
        find.byTooltip(seedColorName(t, option.color)),
        findsOneWidget,
        reason: '${option.label}',
      );
    }

    await tester.tap(find.byTooltip(t.colorBlue));
    await tester.pumpAndSettle();

    expect(settings.settings.seedColor, AppSeedColors.blue);
    // הערכה הכהה לא נגעה — כל בהירות והצבע שלה.
    expect(settings.settings.darkSeedColor, AppSeedColors.defaultDark);

    // "איפוס" מופיע גם בכרטיס התמיכה, ולכן דווקא זה שבתוך הפלטה.
    await tester.tap(find.descendant(
      of: find.byType(SeedColorPalette),
      matching: find.text(t.seedColorResetButton),
    ));
    await tester.pumpAndSettle();

    expect(settings.settings.seedColor, AppSeedColors.defaultLight);
  });

  testWidgets('בערכה כהה הפלטה משנה את הצבע הכהה בלבד', (tester) async {
    final t = stringsOf().settings;

    await pumpScreen(
      tester,
      Theme(
        data: AppThemeData.dark(
          AppThemeData.createColorScheme(
            AppSeedColors.defaultDark,
            Brightness.dark,
          ),
        ),
        child: SettingsScreen(
          controller: settings,
          onOpenLog: () {},
          launcherVersion: launcherVersion,
        ),
      ),
    );

    expect(find.text(t.colorPurple), findsOneWidget);

    await tester.tap(find.text(t.seedColorButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(t.colorTeal));
    await tester.pumpAndSettle();

    expect(settings.settings.darkSeedColor, AppSeedColors.teal);
    expect(settings.settings.seedColor, AppSeedColors.defaultLight);
  });

  testWidgets('הפעלת התקנה אוטומטית דורשת אישור באזהרה', (tester) async {
    await pumpScreen(
      tester,
      SettingsScreen(
        controller: settings,
        onOpenLog: () {},
        launcherVersion: launcherVersion,
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

  // ── מסך השגיאה שמחליף את האפליקציה ────────────────────────────────────────

  testWidgets('מסך "התוכנה במקום הלא נכון" מוצג ואינו מציע דרך להמשיך',
      (tester) async {
    final t = stringsOf().setupError;
    const error = AppPathsException(
      message: 'Access is denied',
      attemptedDir: r'C:\Program Files\Otzaria\OtzariaData',
    );

    // בלי ההזרקה WindowCaption פונה לערוץ פלטפורמה שאינו קיים בבדיקות.
    await pumpScreen(
      tester,
      const SetupErrorScreen(error: error, showWindowButtons: false),
    );

    expect(find.text(t.title), findsOneWidget);
    expect(find.text(t.explanation), findsOneWidget);
    expect(find.text(t.whatToDo), findsOneWidget);
    expect(find.text(error.message), findsOneWidget);
    // `SettingsActionTile.path` משתיל LRM אחרי כל מפריד, ולכן ההשוואה על חלק.
    expect(find.textContaining('OtzariaData'), findsOneWidget);

    // הפעולה היחידה היא העתקת הנתיב — אין "המשך בכל זאת" ואין ניווט פנימה.
    final buttons = tester.widgetList<ActionButton>(find.byType(ActionButton));
    expect(buttons.length, 1);
    expect(find.widgetWithText(ActionButton, t.copyPathButton), findsOneWidget);
  });

  testWidgets('מסך השגיאה מתורגם לאנגלית', (tester) async {
    final t = stringsOf(AppLanguage.english).setupError;

    await pumpScreen(
      tester,
      const SetupErrorScreen(
        error: AppPathsException(message: 'denied', attemptedDir: '/ro/data'),
        showWindowButtons: false,
      ),
      language: AppLanguage.english,
    );

    expect(find.text(t.title), findsOneWidget);
    expect(find.text(stringsOf().setupError.title), findsNothing);
  });

  // ── מסך התוכנה: ערוצים ────────────────────────────────────────────────────

  testWidgets('pre-release כגרסה היחידה מוצג בלי פקד בחירת ערוץ',
      (tester) async {
    // אין יציבה בעמוד הראשון של ה-API — רק ה-pre-release ירד למראה.
    final t = stringsOf().appScreen;
    otzaria.hasChannelChoice = false;
    otzaria.stableVersion = null;
    otzaria.prereleaseVersion = '0.9.99';
    otzaria.latestVersion = '0.9.99';

    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
      ),
    );

    expect(find.text(t.mirrorVersionTitle), findsOneWidget);
    expect(find.text('0.9.99'), findsOneWidget);
    // בלי שתי גרסאות אין מה לבחור, ולכן אין פקד ערוץ ואין זוג גרסאות.
    expect(find.text(t.channelTileTitle), findsNothing);
    expect(find.text(t.channelStable), findsNothing);
    expect(find.text(t.channelPrerelease), findsNothing);
  });

  testWidgets('מסך התוכנה מציג את שלושת הכרטיסים באנגלית', (tester) async {
    final t = stringsOf(AppLanguage.english).appScreen;

    await pumpScreen(
      tester,
      OtzariaScreen(
        otzaria: otzaria,
        settings: settings,
        otzariaIsRunning: false,
      ),
      language: AppLanguage.english,
    );

    expect(find.text(t.stateCardTitle), findsOneWidget);
    expect(find.text(t.whatsNewTitle), findsOneWidget);
    expect(find.text(t.sourceCardTitle), findsOneWidget);
    expect(find.text(stringsOf().appScreen.stateCardTitle), findsNothing);
  });

  // ── דף הבית: מצבי הבדיקה ברשת ─────────────────────────────────────────────

  testWidgets('כשל בבדיקה ברשת מוצג כ"אין חיבור" ולא כשגיאה', (tester) async {
    // בדיקת המטא-דאטה נכשלה (אין רשת) — זה מצב תקין ומטופל בשקט.
    final t = stringsOf().home;
    library.onlineCheckError = 'SocketException: failed host lookup';
    library.onlineCheckedAt = DateTime(2026, 8, 9, 10, 30);

    await pumpScreen(tester, home());

    expect(find.text(t.onlineOffline), findsOneWidget);
    expect(find.text(stringsOf().common.error), findsNothing);
    expect(find.byType(InfoErrorRow), findsNothing);
    // בלי חיבור אין מה להוריד, ולכן גם אין כפתור הורדה.
    expect(find.text(t.downloadNowButton), findsNothing);
  });

  testWidgets('בזמן בדיקה ברשת הכפתור הופך למחוון והמצב "בודק"',
      (tester) async {
    final t = stringsOf().home;

    await pumpScreen(tester, home(isCheckingOnline: true));

    expect(find.text(t.onlineChecking), findsOneWidget);
    // ActionButton במצב טעינה מחליף את התווית במחוון, ולכן נשארת רק כותרת
    // הכרטיס — שנוסחה זהה לתווית הכפתור.
    expect(find.text(t.checkForUpdatesButton), findsOneWidget);
    expect(find.text(t.onlineCardTitle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  // ── מסך הספרייה: שגיאה והתקדמות ───────────────────────────────────────────

  testWidgets('מסך הספרייה מציג שגיאה עם ניסיון חוזר', (tester) async {
    library.status = LibraryModuleStatus.error;
    library.errorMessage = 'המראה המקומית פגומה';

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: false,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
      ),
    );

    expect(find.byType(InfoErrorRow), findsOneWidget);
    expect(find.text('המראה המקומית פגומה'), findsOneWidget);
    expect(
      find.text(stringsOf().libraryScreen.mirrorUnreadable),
      findsOneWidget,
    );
  });

  testWidgets('מסך הספרייה מציג התקדמות בזמן עדכון וחוסם פעולות',
      (tester) async {
    library.status = LibraryModuleStatus.updating;
    library.stageText = 'מחיל תיקון 3 מתוך 7';
    library.applyProgress = 0.42;

    await pumpScreen(
      tester,
      LibraryScreen(
        library: library,
        otzariaIsRunning: true,
        isDownloading: false,
        onProcessStateChanged: () async => false,
        onRequestReindex: () async {},
      ),
    );

    expect(find.byType(InfoProgressRow), findsOneWidget);
    expect(find.text('מחיל תיקון 3 מתוך 7'), findsOneWidget);
    // אוצריא פתוחה — האזהרה מוצגת כאן ולא רק בדף הבית.
    expect(
      find.text(stringsOf().libraryScreen.otzariaRunningTitle),
      findsOneWidget,
    );
    final recheck = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, stringsOf().common.recheck),
    );
    expect(recheck.onPressed, isNull);
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
