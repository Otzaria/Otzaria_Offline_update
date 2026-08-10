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
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/library_screen.dart';
import 'package:launcher_app/src/screens/otzaria_screen.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/screens/settings_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
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

  Future<void> pumpShell(WidgetTester tester) async {
    useViewSize(tester, const Size(1400, 1000));
    await tester.pumpWidget(
      wrap(AppShell(
        dataDir: tempDir.path,
        settings: settings,
        runningLocator: const _NeverRunningLocator(),
        // כפתורי החלון מדברים עם ערוץ פלטפורמה שאינו קיים בבדיקות widget.
        showWindowButtons: false,
      )),
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
}

/// "אוצריא סגורה", בלי להריץ `tasklist` — ראו ה-setUp.
class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}
