// בדיקות ל-[AppShell] — המסגרת שמחזיקה את חמשת המסכים.
//
// הבדיקה הקלה ברשת (`autoCheckOnlineUpdates`) כבויה בכולן חוץ מאחת, ושם
// הרשת חסומה ב-[NoNetworkHttpOverrides] — אף בדיקה כאן לא נוגעת ברשת אמיתית.
// מה שכן נפתח ב-`initState` (טעינת הקטלוג, בדיקה מהתיקייה המקומית) הוא
// `dart:io` ולכן אינו מסתיים בתוך ה-fake-async; מכאן שכל ה-pump כאן הוא
// [WidgetTester.pump] ולא `pumpAndSettle`, שהיה נתקע על מד ההתקדמות.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/faq/faq_floating_button.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_screen.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import 'test_harness.dart';
import 'test_support.dart';

void main() {
  late Directory tempDir;
  late SettingsController settings;
  final shell = stringsOf().shell;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('app_shell_test');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    // הבדיקה המקומית נשארת דלוקה דווקא: היא ממתינה לקריאות `dart:io` שלא
    // מסתיימות ב-fake-async. בדיקת התהליך היא היחידה שהייתה מריצה כאן
    // `tasklist` אמיתי (ואיתו טיימר תלוי שמפיל את הבדיקה), ולכן היא מוזרקת.
    await settings.update(const AppSettings(autoCheckOnlineUpdates: false));
  });

  tearDown(() async {
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    RunningOtzariaLocator locator = const _NeverRunningLocator(),
    AppLanguage language = AppLanguage.hebrew,
  }) async {
    useViewSize(tester, const Size(1400, 1000));
    await tester.pumpWidget(
      wrap(
        AppShell(
          dataDir: tempDir.path,
          settings: settings,
          runningLocator: locator,
          // כפתורי החלון מדברים עם ערוץ פלטפורמה שאינו קיים בבדיקות widget.
          showWindowButtons: false,
        ),
        language: language,
      ),
    );
    await tester.pump();
  }

  /// [IndexedStack] מסתיר את מי שאינו נבחר, ולכן החיפוש חייב לכלול offstage —
  /// אחרת "לא נמצא" היה יכול להיות "נבנה אבל מוסתר".
  Finder screen(Type type) => find.byType(type, skipOffstage: false);

  /// ב-[NavRailItem] רק הסמל לחיץ; התווית יושבת מתחתיו כאחות שלו.
  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.widgetWithText(NavRailItem, label),
      matching: find.byType(IconButton),
    ));
    await tester.pump();
  }

  testWidgets('בעלייה נבנה דף הבית בלבד — שאר המסכים כלל לא בעץ',
      (tester) async {
    await pumpShell(tester);

    expect(screen(HomeScreen), findsOneWidget);
    // חנות התוספים היא היקרה מכולן (רשת כרטיסים עם תמונה לכל תוסף), וזו
    // בדיוק הסיבה שה-IndexedStack אינו בונה את כל ילדיו.
    expect(screen(PluginsScreen), findsNothing);
    expect(screen(OtzariaScreen), findsNothing);
    expect(screen(LibraryScreen), findsNothing);
    expect(screen(SettingsScreen), findsNothing);
  });

  testWidgets('כפתור השאלות הנפוצות צף בפינה השמאלית התחתונה של דף הבית',
      (tester) async {
    await pumpShell(tester);

    Rect buttonRect() => tester.getRect(find.byType(FaqFloatingButton));
    final windowSize = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(find.byType(FaqFloatingButton), findsOneWidget);
    // בעברית סרגל הניווט מימין, ולכן הכפתור פיזית שמאל-למטה.
    expect(buttonRect().left, lessThan(windowSize.width / 2));
    expect(buttonRect().bottom, greaterThan(windowSize.height / 2));

    // במסך אחר הוא מוסתר — אבל נשאר בעץ, אחרת ההבהוב והבועה החד-פעמיים היו
    // חוזרים בכל חזרה לדף הבית.
    await tapNav(tester, shell.navSettings);
    expect(find.byType(FaqFloatingButton), findsNothing);
    expect(find.byType(FaqFloatingButton, skipOffstage: false), findsOneWidget);

    await tapNav(tester, shell.navHome);
    expect(find.byType(FaqFloatingButton), findsOneWidget);
  });

  testWidgets('באנגלית הכפתור עובר לימין — הוא כיסה את סרגל הניווט שמשמאל',
      (tester) async {
    await pumpShell(tester, language: AppLanguage.english);

    final rect = tester.getRect(find.byType(FaqFloatingButton));
    final windowSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.right, greaterThan(windowSize.width / 2));
    expect(rect.bottom, greaterThan(windowSize.height / 2));
  });

  testWidgets('כיבוי בהגדרות מוציא את הכפתור מהעץ לגמרי', (tester) async {
    // `runAsync` ולא `await` ישר: השמירה כותבת לדיסק, וקריאת `dart:io` אינה
    // מסתיימת בתוך ה-fake-async של `testWidgets` — ראו AGENTS §3.
    await tester.runAsync(() => settings.update(const AppSettings(
          autoCheckOnlineUpdates: false,
          showFaqButton: false,
        )));
    await pumpShell(tester);

    expect(find.byType(FaqFloatingButton, skipOffstage: false), findsNothing);
  });

  testWidgets('מסך שנכנסים אליו נבנה, ונשאר בעץ גם אחרי מעבר משם',
      (tester) async {
    await pumpShell(tester);

    await tapNav(tester, shell.navPlugins);
    expect(screen(PluginsScreen), findsOneWidget);
    // שאר המסכים עדיין לא נבנו — הבנייה היא לפי ביקור, לא מראש.
    expect(screen(LibraryScreen), findsNothing);

    await tapNav(tester, shell.navHome);
    // נשאר בעץ עם המצב שלו — זו כל הנקודה של IndexedStack מדורג.
    expect(screen(PluginsScreen), findsOneWidget);
    expect(screen(HomeScreen), findsOneWidget);
  });

  testWidgets('כל חמשת המסכים נבנים אחרי ביקור בכולם', (tester) async {
    await pumpShell(tester);

    for (final label in [
      shell.navApp,
      shell.navLibrary,
      shell.navPlugins,
      shell.navSettings,
    ]) {
      await tapNav(tester, label);
    }

    expect(screen(HomeScreen), findsOneWidget);
    expect(screen(OtzariaScreen), findsOneWidget);
    expect(screen(LibraryScreen), findsOneWidget);
    expect(screen(PluginsScreen), findsOneWidget);
    expect(screen(SettingsScreen), findsOneWidget);
  });

  testWidgets('אין דיאלוג בעלייה — גם לא זה של עדכוני התוספים', (tester) async {
    await pumpShell(tester);
    await tester.pump();

    // הדיאלוג של "יש עדכונים לתוספים" יושב ב-PluginsScreen, שלא נבנה עדיין;
    // זו התוצאה הנלווית המכוונת של הבנייה המדורגת.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(screen(PluginsScreen), findsNothing);
  });

  testWidgets('בקשת מיקוד מחנות התוספים מעבירה את התצוגה אליה', (tester) async {
    await pumpShell(tester);

    // כניסה ויציאה — המסך נשאר בעץ, ולכן הודעת העדכונים שלו יכולה לצוץ
    // כשהמשתמש כבר בדף הבית. בחירת תוסף מתוכה מבקשת מיקוד, וזו הבקשה כאן.
    await tapNav(tester, shell.navPlugins);
    await tapNav(tester, shell.navHome);

    int? shownScreen() => tester
        .widget<IndexedStack>(find.byType(IndexedStack, skipOffstage: false))
        .index;
    expect(shownScreen(), LauncherScreen.home.index);

    tester.widget<PluginsScreen>(screen(PluginsScreen)).onRequestFocus!();
    await tester.pump();

    expect(shownScreen(), LauncherScreen.plugins.index);
  });

  testWidgets('סרגל הזהות מציג את שם התוכנה ואת הסמל', (tester) async {
    await pumpShell(tester);

    expect(find.text(shell.appTitle), findsOneWidget);
    final logo = tester.widget<Image>(find.byType(Image).first);
    expect(logo.semanticLabel, shell.otzariaLogoLabel);
    // מחווני המצב שהיו בסרגל העליון הוסרו — הם יושבים בדף הבית.
    expect(find.byType(StatusChip), findsWidgets);
  });

  testWidgets('בעלייה אין שום חיווי שגיאה, והבדיקה ברשת כבויה', (tester) async {
    await pumpShell(tester);
    await tester.pump();

    expect(find.byType(InfoErrorRow), findsNothing);
    expect(find.text(stringsOf().common.error), findsNothing);
    expect(find.text(stringsOf().home.onlineNeverChecked), findsOneWidget);
  });

  testWidgets('checkOnline שנכשל (אין רשת) אינו מציג שגיאה אלא "אין חיבור"',
      (tester) async {
    // הבדיקה הקלה היא מטא-דאטה בלבד, וכשל בה הוא תוצאה **תקינה** —
    // המחשב המנותק הוא מקרה השימוש המרכזי של התוכנה.
    HttpOverrides.global = NoNetworkHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);
    // שמירת ההגדרות כותבת לדיסק — חייבת לרוץ מחוץ ל-fake-async.
    await tester.runAsync(
      () => settings.update(const AppSettings(autoCheckOnlineUpdates: true)),
    );

    await pumpShell(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(stringsOf().home.onlineOffline), findsOneWidget);
    expect(find.byType(InfoErrorRow), findsNothing);
    expect(find.text(stringsOf().common.error), findsNothing);
    // לא נמצא עדכון ברשת, ולכן גם אין הצעה להוריד.
    expect(find.text(stringsOf().home.downloadNowButton), findsNothing);
  });

  testWidgets('אוצריא שנסגרה מזוהה בזמן שהלאנצ\'ר פתוח — בלי הפעלה מחדש שלו',
      (tester) async {
    // הבדיקה המקומית כבויה כאן בכוונה: היא קוראת מהדיסק ולא מסתיימת בתוך
    // ה-fake-async, ואז מצב התהליך היה נקבע רק אחרי סיום הבדיקה.
    await tester.runAsync(() => settings.update(const AppSettings(
          autoMetadataCheck: false,
          autoCheckOnlineUpdates: false,
        )));
    final locator = _MutableLocator(isRunning: true);

    await pumpShell(tester, locator: locator);
    await tester.pump();
    expect(find.text(stringsOf().home.otzariaRunningTitle), findsOneWidget);

    // המשתמש סוגר את אוצריא. הרענון המחזורי אמור להבחין בזה מעצמו.
    locator.isRunning = false;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.text(stringsOf().home.otzariaRunningTitle), findsNothing);

    // ומכאן הטיימר צריך להיכבות: אחרת `tasklist` (~300ms) היה רץ כל 3
    // שניות לנצח, על אוצריא שכבר סגורה.
    final probesWhenClosed = locator.probes;
    await tester.pump(const Duration(seconds: 12));
    expect(locator.probes, probesWhenClosed);
  });

  testWidgets('הניווט מסמן את הפריט הנבחר ומחליף את המסך המוצג',
      (tester) async {
    await pumpShell(tester);

    NavRailItem item(String label) =>
        tester.widget<NavRailItem>(find.widgetWithText(NavRailItem, label));

    expect(item(shell.navHome).isSelected, isTrue);
    expect(item(shell.navSettings).isSelected, isFalse);

    await tapNav(tester, shell.navSettings);

    expect(item(shell.navHome).isSelected, isFalse);
    expect(item(shell.navSettings).isSelected, isTrue);
    expect(screen(SettingsScreen), findsOneWidget);
  });

  // ההתקנה האוטומטית עצמה אינה נהיגה מבדיקת widget — היא מריצה מתקין אמיתי
  // ו-`dart:io` שאינו מסתיים ב-fake-async. הסדר, לעומת זאת, הוא כל התיקון,
  // ולכן הוא מוצמד מהמקור — כמו ב-`faq_test.dart`.
  group('_autoInstallIfEnabled', () {
    final source = File('lib/src/screens/app_shell.dart').readAsStringSync();
    final start = source.indexOf('_autoInstallIfEnabled() async {');
    final body =
        source.substring(start, source.indexOf('_downloadMirrorDirs', start));

    test('גוף המתודה נמצא — אחרת כל השאר כאן בודק מחרוזת ריקה', () {
      expect(start, greaterThan(-1));
      expect(body, contains('_library.update()'));
    });

    // המתקין של אוצריא משיק אותה בסוף התקנה שקטה, ואוצריא פתוחה נועלת את
    // המסד — בסדר ההפוך הלאנצ'ר חסם את עדכון המסד שהוא עצמו הריץ.
    test('עדכון המסד מוקדם להתקנת התוכנה', () {
      expect(body.indexOf('_library.update()'),
          lessThan(body.indexOf('_otzaria.install(')));
    });

    test('שני המסלולים נשענים על בדיקת תהליך טרייה', () {
      expect(
        'refreshProcessState()'.allMatches(body).length,
        2,
        reason: 'עדכון המסד וההתקנה',
      );
      // הערך שנלכד בבנייה הוא בדיוק מה שהיה מיושן כאן.
      expect(body, isNot(contains('_otzariaIsRunning')));
    });

    // התקנה ראשונה מנחשת את היעד (`resolveInstallDbPath`), והניחוש נרשם
    // אחר כך כבחירת המשתמש — מסד שלם במקום הלא נכון, ולנצח.
    test('עדכון המסד מותנה בכך שיש כבר מסד', () {
      expect(body, contains('!_library.isFreshInstall'));
    });

    test('התקנת התוכנה מותנית בכך שאוצריא כבר מותקנת', () {
      expect(body, contains('_otzaria.currentVersion != null'));
    });

    // `fullPackageRecommended` הוא בהגדרתו "אין אוצריא במחשב" — בדיוק
    // המקרה שאינו אוטומטי.
    test('החבילה המלאה אינה מותקנת אוטומטית', () {
      expect(body, isNot(contains('installFullPackage(')));
    });

    // דילוג שקט נראה בדיוק כמו הגדרה שאינה עובדת.
    test('דילוג בגלל אוצריא פתוחה מדווח בדיאלוג', () {
      expect(body, contains('skippedWhileRunning'));
      expect(body, contains('showSingleActionDialog'));
      expect(body, contains('autoInstallSkippedTitle'));
    });
  });

  // ההחלפה מסתיימת ב-`exit(0)`, ולכן היא נחסמת בזמן פעולה ארוכה — גם
  // כשהכפתור מנוטרל: [downloadLauncherUpdate] מגיע לכאן בלי כפתור בכלל.
  group('installLauncherUpdate', () {
    final source = File('lib/src/screens/app_shell.dart').readAsStringSync();
    final start = source.indexOf('Future<void> installLauncherUpdate()');
    final body =
        source.substring(start, source.indexOf('_autoInstallIfEnabled', start));

    test('גוף המתודה נמצא', () => expect(start, greaterThan(-1)));

    test('נחסמת בזמן הורדה או התקנה, עם הודעה', () {
      expect(body, contains('_longTaskRunning'));
      expect(body, contains('busyNotice'));
    });
  });
  group('מצב סייפר — הכניסה להגדרות', () {
    /// מפעיל את הנעילה על ההגדרות שהמסגרת כבר מחזיקה. `runAsync` כי הכתיבה
    /// לדיסק אינה מסתיימת בתוך ה-fake-async.
    Future<void> lockSettings(WidgetTester tester) => tester.runAsync(
          () => settings.update(
            AppSettings(
              autoCheckOnlineUpdates: false,
              saferModeEnabled: true,
              saferModePassword: SaferModePassword.encode('1234'),
            ),
          ),
        );

    testWidgets('לחיצה על ההגדרות פותחת דיאלוג סיסמה ואינה בונה את המסך',
        (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await tapNav(tester, shell.navSettings);
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
      // המסך עצמו כלל לא נבנה — גם לא מוסתר מאחורי הדיאלוג.
      expect(screen(SettingsScreen), findsNothing);
    });

    testWidgets('ביטול הדיאלוג משאיר את המשתמש בדף הבית', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await tapNav(tester, shell.navSettings);
      await tester.pump();
      await tester.tap(find.text(stringsOf().common.cancel));
      await tester.pump();

      expect(screen(SettingsScreen), findsNothing);
      expect(screen(HomeScreen), findsOneWidget);
    });

    testWidgets('סיסמה שגויה אינה פותחת את המסך', (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await tapNav(tester, shell.navSettings);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text(stringsOf().common.confirm));
      await tester.pump();

      expect(screen(SettingsScreen), findsNothing);
      // הדיאלוג נשאר פתוח — מי שטעה מנסה שוב.
      expect(find.text(stringsOf().saferMode.verifyTitle), findsOneWidget);
    });

    testWidgets('הסיסמה הנכונה פותחת, וכניסה חוזרת אינה נשאלת שוב',
        (tester) async {
      await lockSettings(tester);
      await pumpShell(tester);

      await tapNav(tester, shell.navSettings);
      await tester.pump();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text(stringsOf().common.confirm));
      await tester.pump();

      expect(screen(SettingsScreen), findsOneWidget);

      // אימות אחד מחזיק להרצה — יציאה וחזרה אינן מבקשות סיסמה שוב.
      await tapNav(tester, shell.navHome);
      await tapNav(tester, shell.navSettings);
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(screen(SettingsScreen), findsOneWidget);
    });

    testWidgets('בלי סיסמה שמורה המתג אינו נועל כלום', (tester) async {
      // קובץ שנערך ביד יכול להדליק את המתג בלי סיסמה — וזה אינו נועל.
      await tester.runAsync(
        () => settings.update(
          const AppSettings(
            autoCheckOnlineUpdates: false,
            saferModeEnabled: true,
          ),
        ),
      );
      await pumpShell(tester);

      await tapNav(tester, shell.navSettings);
      await tester.pump();

      expect(find.text(stringsOf().saferMode.verifyTitle), findsNothing);
      expect(screen(SettingsScreen), findsOneWidget);
    });
  });
}

/// "אוצריא סגורה", בלי להריץ `tasklist` — ראו ה-setUp.
class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

/// אוצריא שנסגרת באמצע הבדיקה: [isRunning] מוחלף בין בדיקה לבדיקה.
/// [probes] סופר דגימות, כדי לאמת גם שהרענון המחזורי **נכבה**.
class _MutableLocator extends RunningOtzariaLocator {
  _MutableLocator({required this.isRunning});

  bool isRunning;
  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    probes++;
    return (isRunning: isRunning, launchPath: null);
  }
}
