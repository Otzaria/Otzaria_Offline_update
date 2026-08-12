import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:window_manager/window_manager.dart';

import 'src/screens/app_shell.dart';
import 'src/screens/setup_error_screen.dart';
import 'src/services/app_logger.dart';
import 'src/services/app_paths.dart';
import 'src/settings/app_settings.dart';
import 'src/settings/settings_controller.dart';
import 'src/theme/theme_exports.dart';
import 'src/widgets/widgets_exports.dart';

void main() {
  // ה-logger נוצר בתוך ה-zone אבל נדרש גם למטפל השגיאות שלו — ולכן מוחזק
  // כאן, מחוץ. nullable כי שגיאה יכולה לקרות עוד לפני שהוא נבנה.
  AppLogger? logger;

  void report(String context, Object error, StackTrace? stackTrace) {
    // העתקה מקומית: `logger` הוא משתנה שנתפס ומשתנה, ולכן promotion ל-non-null
    // לא חל עליו ישירות.
    final log = logger;
    if (log != null) {
      log.error(context, error, stackTrace);
    } else {
      // עוד אין לאן לכתוב — לפחות שזה יגיע ל-stderr ולקונסולת הדיבאגר.
      debugPrint('$context (לפני אתחול הלוג): $error\n$stackTrace');
    }
  }

  // **כל** האתחול חייב לרוץ בתוך אותו zone שממנו נקרא `runApp`. קודם
  // `ensureInitialized()` נקרא מחוץ ל-`runZonedGuarded`, וזה הפיל assertion
  // של "Zone mismatch" בכל הרצת debug (ב-release ה-assertion לא קיים, ולכן
  // זה לא נראה שם) — Flutter דורש שאתחול ה-bindings ו-`runApp` יהיו באותו
  // zone, אחרת קונפיגורציה zone-specific מתנהגת באופן לא צפוי.
  //
  // בונוס: עכשיו גם כשלים באתחול עצמו (למשל `getApplicationSupportDirectory`
  // שנכשל) נתפסים ונרשמים, במקום להפיל את האפליקציה בשקט לפני שיש לוג.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // שפת המחשב, עוד לפני שההגדרות נטענו: כשל באתחול (למשל [AppPaths])
      // מנסח את הודעתו מ-`AppL10n` ברגע הזריקה. `SettingsController` יחליף
      // אם המשתמש בחר שפה מפורשת.
      AppL10n.use(systemLanguage());

      // תופס שגיאות שה-widgets framework עצמו זורק (למשל בתוך build/layout).
      FlutterError.onError = (details) {
        report(
          'FlutterError: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };

      await _prepareWindow();

      // תיקיית הנתונים צמודה לתוכנה ואינה ניתנת לשינוי. אם אי אפשר לכתוב
      // בה — אין לאן לשמור *כלום*, כולל הלוג עצמו, ולכן זו לא שגיאה שאפשר
      // לרשום ולהמשיך: מציגים מסך הסבר ועוצרים.
      final AppPaths paths;
      try {
        paths = await AppPaths.resolve();
      } on AppPathsException catch (e) {
        debugPrint('$e');
        runApp(SetupErrorApp(error: e));
        return;
      }

      // שני אלה נוגעים בדיסק ואינם תלויים זה בזה. בטור, על כונן USB איטי,
      // זה היה שני סבבי I/O לפני הפריים הראשון; במקביל — סבב אחד.
      final settings = SettingsController(dataDir: paths.dataDir);
      final initialized = await Future.wait([
        AppLogger.init(paths.dataDir),
        settings.load(),
      ]);
      logger = initialized.first as AppLogger;

      runApp(LauncherApp(dataDir: paths.dataDir, settings: settings));
    },
    // תופס שגיאות אסינכרוניות שלא נתפסו ע"י שום try/catch — רשת חיצונית
    // (defense in depth): גם אם ניצור בעתיד בטעות עוד קריסת isolate/async
    // שבורחת מהטיפול הרגיל, היא עדיין תיכתב ללוג במקום להיעלם בשקט.
    (error, stackTrace) => report('Uncaught zone error', error, stackTrace),
  );
}

/// מסתיר את מסגרת החלון של המערכת — מכאן והלאה שורת הכותרת היא [AppTitleBar]
/// שבתוך האפליקציה, בצבע הרקע. רץ לפני `runApp` כדי שהחלון ייצבע פעם אחת
/// בגודלו הסופי: שינוי המסגרת מאתחל את אזור-הלקוח ומבטל פריים שכבר צויר.
/// ההגדלה עצמה נעשית ב-runner (`Win32Window::Show`) ולא כאן — ראו שם.
Future<void> _prepareWindow() async {
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  // כשל כאן הוא קוסמטי בלבד (נשארת מסגרת המערכת), אבל בלי ה-catch הוא היה
  // בורח לפני שיש לוג ומשאיר את המשתמש בלי חלון בכלל.
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(900, 620));
    // ברירת המחדל של windowButtonVisibility היא true — בלי false מפורש כפתורי
    // המערכת של macOS יופיעו כפול לצד הכפתורים שלנו.
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  } catch (e) {
    debugPrint('הכנת החלון נכשלה: $e');
  }
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({
    super.key,
    required this.dataDir,
    required this.settings,
  });

  final String dataDir;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.settings;

        return _materialApp(
          language: s.language,
          themeMode: switch (s.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          textScale: s.textScale,
          seedColor: s.seedColor,
          darkSeedColor: s.darkSeedColor,
          home: AppShell(dataDir: dataDir, settings: settings),
        );
      },
    );
  }
}

/// עוטף את [SetupErrorScreen] ב-MaterialApp משלו — ההגדרות עוד לא נטענו
/// (ואי אפשר לטעון אותן), ולכן ערכת הנושא והשפה הן לפי המערכת.
class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key, required this.error});

  final AppPathsException error;

  @override
  Widget build(BuildContext context) => _materialApp(
        home: SetupErrorScreen(error: error),
        // אותה שפה שבה נוסחה הודעת השגיאה עצמה, שנבנתה לפני `runApp`.
        language: AppL10n.language,
      );
}

/// הקונפיגורציה המשותפת לשני ה-MaterialApp — שפה, כיווניות וערכת הנושא.
///
/// ה-`locale` הוא שקובע גם את כיוון הכתיבה: עברית → RTL, אנגלית → LTR, דרך
/// `GlobalWidgetsLocalizations`. אין כאן נגיעה ישירה ב-[Directionality].
Widget _materialApp({
  required Widget home,
  required AppLanguage language,
  ThemeMode themeMode = ThemeMode.system,
  double textScale = 1.0,
  Color seedColor = AppSeedColors.defaultLight,
  Color darkSeedColor = AppSeedColors.defaultDark,
}) {
  final strings = AppL10n.stringsFor(language);

  return MaterialApp(
    navigatorKey: navigatorKey,
    title: strings.shell.appTitle,
    debugShowCheckedModeBanner: false,
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('he', 'IL'), Locale('en')],
    locale: switch (language) {
      AppLanguage.hebrew => const Locale('he', 'IL'),
      AppLanguage.english => const Locale('en'),
    },
    theme: AppThemeData.light(
      AppThemeData.createColorScheme(seedColor, Brightness.light),
    ),
    darkTheme: AppThemeData.dark(
      AppThemeData.createColorScheme(darkSeedColor, Brightness.dark),
    ),
    themeMode: themeMode,
    // ב-`builder` ולא סביב `home`: כאן זה יושב **מעל** ה-Navigator, ולכן גם
    // דיאלוגים ומסלולים שנפתחים מעליו מוצאים את המלל.
    builder: (context, child) => AppStringsScope(
      strings: strings,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: home,
  );
}
