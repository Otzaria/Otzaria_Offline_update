import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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

      // תופס שגיאות שה-widgets framework עצמו זורק (למשל בתוך build/layout).
      FlutterError.onError = (details) {
        report(
          'FlutterError: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };

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

      logger = await AppLogger.init(paths.dataDir);

      final settings = SettingsController(dataDir: paths.dataDir);
      await settings.load();

      runApp(LauncherApp(dataDir: paths.dataDir, settings: settings));
    },
    // תופס שגיאות אסינכרוניות שלא נתפסו ע"י שום try/catch — רשת חיצונית
    // (defense in depth): גם אם ניצור בעתיד בטעות עוד קריסת isolate/async
    // שבורחת מהטיפול הרגיל, היא עדיין תיכתב ללוג במקום להיעלם בשקט.
    (error, stackTrace) => report('Uncaught zone error', error, stackTrace),
  );
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
          themeMode: switch (s.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          textScale: s.textScale,
          home: AppShell(dataDir: dataDir, settings: settings),
        );
      },
    );
  }
}

/// עוטף את [SetupErrorScreen] ב-MaterialApp משלו — ההגדרות עוד לא נטענו
/// (ואי אפשר לטעון אותן), ולכן ערכת הנושא היא לפי המערכת.
class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key, required this.error});

  final AppPathsException error;

  @override
  Widget build(BuildContext context) =>
      _materialApp(home: SetupErrorScreen(error: error));
}

/// הקונפיגורציה המשותפת לשני ה-MaterialApp — עברית, RTL וערכת הנושא.
Widget _materialApp({
  required Widget home,
  ThemeMode themeMode = ThemeMode.system,
  double textScale = 1.0,
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    title: 'אוצריא — מנהל עדכונים',
    debugShowCheckedModeBanner: false,
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
    darkTheme: AppThemeData.dark(
      AppThemeData.createColorScheme(
        AppSeedColors.defaultDark,
        Brightness.dark,
      ),
    ),
    themeMode: themeMode,
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}
