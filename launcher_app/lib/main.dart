import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:error_reports_manager/error_reports_manager.dart'
    show LauncherLogFormat;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart' as downloads;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_report/launcher_crash_session.dart';
import 'src/controllers/app_reports_controller.dart';
import 'src/screens/app_shell.dart';
import 'src/screens/payload_mismatch_screen.dart';
import 'src/screens/setup_error_screen.dart';
import 'src/self_update/launcher_install_layout.dart';
import 'src/self_update/launcher_version.dart';
import 'src/self_update/payload_check.dart';
import 'src/services/app_logger.dart';
import 'src/services/app_paths.dart';
import 'src/services/instance_lock.dart';
import 'src/services/native_sha256_sink.dart';
import 'src/services/netfree_certificates.dart';
import 'src/services/startup_diagnostics.dart';
import 'src/settings/app_settings.dart';
import 'src/settings/settings_controller.dart';
import 'src/theme/theme_exports.dart';
import 'src/widgets/widgets_exports.dart';

void main() {
  // מה שהעלייה הזו כותבת ליומן לפני בדיקת הקריסה אינו ראיה נגד ההפעלה הקודמת.
  LauncherCrashSession.processStartedAt = DateTime.now();

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
      downloads.startSha256 = NativeSha256Sink.new;

      // תופס שגיאות שה-widgets framework עצמו זורק (למשל בתוך build/layout).
      FlutterError.onError = (details) {
        report(
          LauncherLogFormat.uncaughtMessage(
            LauncherLogFormat.flutterError,
            details.exception,
          ),
          details.exception,
          details.stack,
        );
        FlutterError.presentError(details);
      };
      // שגיאות שאינן עוברות ב-zone (קריאות חוזרות מהפלטפורמה). הכותרת היא
      // ראיה לקריסה בזיהוי היציאה הלא נקייה — ראו `LauncherLogFormat`.
      PlatformDispatcher.instance.onError = (error, stack) {
        report(
          LauncherLogFormat.uncaughtMessage(
            LauncherLogFormat.platformError,
            error,
          ),
          error,
          stack,
        );
        return true;
      };

      await _prepareWindow();

      // תיקיית הנתונים צמודה לתוכנה ואינה ניתנת לשינוי. כשאי אפשר לכתוב בה
      // אבל יש בה מראה, ההרצה נמשכת במצב קריאה — הלוג והמצב עוברים לתיקיית
      // המשתמש שבמחשב הזה (ראו [AppPaths.resolve]). כשגם זה אינו אפשרי אין
      // לאן לשמור *כלום*, ולכן זו לא שגיאה שאפשר לרשום ולהמשיך: מציגים מסך
      // הסבר ועוצרים.
      final AppPaths paths;
      try {
        paths = await AppPaths.resolve();
      } on AppPathsException catch (e) {
        debugPrint('$e');
        // **גם מסך העצירה משאיר עקבה.** זה היה המסלול היחיד שנגמר בלי שורת
        // לוג אחת בשום מקום — ולכן משתמש שנתקע בו נראה בדיוק כמו משתמש
        // שהתוכנה שלו לא כותבת ללוג בכלל. ה-temp הוא מה שנשאר כשלתיקיית
        // הנתונים אין הרשאת כתיבה.
        try {
          await AppLogger.init(
            Directory.systemTemp.path,
            version: launcherVersion,
          );
          AppLogger.instance.error('מסך עצירה בעלייה (${e.kind.name}): $e');
        } catch (_) {}
        runApp(SetupErrorApp(error: e));
        return;
      }
      final instanceLock = await InstanceLock.acquire(paths.stateFilesDir);
      final machineLock = instanceLock == InstanceLockResult.heldElsewhere
          ? instanceLock
          : await InstanceLock.acquireMachineWide();
      if (machineLock == InstanceLockResult.heldElsewhere) {
        debugPrint(
            '${InstanceLock.fileName} held by another launcher, exiting');
        InstanceLock.focusOtherInstance();
        exit(0);
      }
      // לפני טעינת ההגדרות: במצב קריאה הן נקראות מתיקיית המחשב, ובלי
      // ההעתקה הזו הרצה ראשונה שם הייתה מתחילה מברירות המחדל.
      await paths.seedPreferences();
      await paths.migrateStateFiles();

      // שני אלה נוגעים בדיסק ואינם תלויים זה בזה. בטור, על כונן USB איטי,
      // זה היה שני סבבי I/O לפני הפריים הראשון; במקביל — סבב אחד.
      final settings = SettingsController(dataDir: paths.stateDir);
      final initialized = await Future.wait([
        AppLogger.init(
          paths.stateDir,
          version: launcherVersion,
          payloadVersion: PayloadCheck.stubPayloadVersion(),
        ),
        settings.load(),
        trustNetfreeCertificates(),
      ]);
      logger = initialized.first as AppLogger;

      // מיד אחרי שיש לוג: משם והלאה כל שלב בעלייה מותיר עקבות, כולל הפריים
      // הראשון שהוצג — בלעדיו "מסך שחור" ו"תקוע" נראים אותו דבר (issue #28).
      StartupDiagnostics.start();
      if (instanceLock == InstanceLockResult.unavailable) {
        AppLogger.instance.warn(
          '${InstanceLock.fileName} unavailable, running without the single-instance guard',
        );
      }

      if (paths.readOnly) {
        final where = 'dataDir=${paths.dataDir} stateDir=${paths.stateDir}';
        if (paths.driveFull) {
          AppLogger.instance.warn(
            'הכונן מלא — מצב והגדרות נשמרים במחשב הזה: $where',
          );
        } else {
          AppLogger.instance.warn(
            'הכונן מוגן מכתיבה — מצב והגדרות נשמרים במחשב הזה: $where',
          );
        }
      }

      // ערמת קבצים שאינה שייכת לקובץ ההרצה שלצידה קורסת בדרכים שאי אפשר
      // לרשום אחר כך — לכן נעצרים כאן, אחרי שיש לוג ולפני שנוגעים בעוד משהו.
      final mismatch = PayloadCheck.detect(
        layout: LauncherInstallLayout.resolve(),
      );
      if (mismatch != null) {
        AppLogger.instance
            .error('ערמת הקבצים אינה תואמת לקובץ ההרצה: $mismatch');
        await PayloadCheck.requestReextract(mismatch);
        runApp(PayloadMismatchApp(mismatch: mismatch));
        return;
      }

      // נעילת ההפעלה ויומן הלאנצ'ר באותה תיקייה — ראו `LauncherCrashSession`.
      final appReports = AppReportsController.forState(
        stateDir: paths.stateDir,
        logsDirectory: AppLogger.instance.logDir,
        settings: settings,
      );
      // הנעילה נפתחת כאן, לא אחרי הפריים: עלייה שנתקעת לפניו תישאר עם ראיה.
      // הזיהוי והכתיבה אסינכרוניים ואינם עוצרים את הפריים (§5.9).
      unawaited(
        LauncherCrashSession.begin(
          logsDirectory: AppLogger.instance.logDir,
          version: launcherVersion,
        ),
      );
      await LauncherCrashSession.installCloseHooks();

      runApp(
        LauncherApp(paths: paths, settings: settings, appReports: appReports),
      );
    },
    // תופס שגיאות אסינכרוניות שלא נתפסו ע"י שום try/catch — רשת חיצונית
    // (defense in depth): גם אם ניצור בעתיד בטעות עוד קריסת isolate/async
    // שבורחת מהטיפול הרגיל, היא עדיין תיכתב ללוג במקום להיעלם בשקט.
    (error, stackTrace) => report(
      LauncherLogFormat.uncaughtMessage(LauncherLogFormat.zoneError, error),
      error,
      stackTrace,
    ),
  );
}

/// מסגרת המערכת מוסתרת לפני `runApp`: שינוי המסגרת מבטל פריים שכבר צויר.
/// הגודל והמיקום ההתחלתיים נקבעים ב-runner (`main.cpp`).
Future<void> _prepareWindow() async {
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  // כשל כאן הוא קוסמטי בלבד (נשארת מסגרת המערכת), אבל בלי ה-catch הוא היה
  // בורח לפני שיש לוג ומשאיר את המשתמש בלי חלון בכלל.
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(760, 560));
    // ב-macOS המערכת מציירת את שלושת הכפתורים העגולים, ו-`AppTitleBar` אינו
    // מצייר את שלו; בווינדוס `false`, אחרת היו מופיעים כפולים.
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS,
    );
  } catch (e) {
    debugPrint('הכנת החלון נכשלה: $e');
  }
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({
    super.key,
    required this.paths,
    required this.settings,
    this.appReports,
  });

  final AppPaths paths;
  final SettingsController settings;
  final AppReportsController? appReports;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.settings;

        return _materialApp(
          language: s.language,
          textScale: s.textScale,
          home: AppShell(
            dataDir: paths.dataDir,
            stateDir: paths.stateDir,
            readOnly: paths.readOnly,
            driveFull: paths.driveFull,
            settings: settings,
            appReports: appReports,
          ),
        );
      },
    );
  }
}

/// עוטף את [SetupErrorScreen] ב-MaterialApp משלו — ההגדרות עוד לא נטענו
/// (ואי אפשר לטעון אותן), ולכן השפה היא לפי המערכת.
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

/// כמו [SetupErrorApp]: ההגדרות אולי נטענו, אבל אין טעם להפעיל את הממשק
/// הרגיל מעל ערמת קבצים שאינה תואמת. שפת המערכת, כמו שאר מסכי העצירה.
class PayloadMismatchApp extends StatelessWidget {
  const PayloadMismatchApp({super.key, required this.mismatch});

  final PayloadMismatch mismatch;

  @override
  Widget build(BuildContext context) => _materialApp(
        home: PayloadMismatchScreen(mismatch: mismatch),
        language: AppL10n.language,
      );
}

/// הקונפיגורציה של כל MaterialApp. ה-`locale` קובע גם את הכיוון (RTL/LTR)
/// דרך `GlobalWidgetsLocalizations` — בלי [Directionality] ישיר.
Widget _materialApp({
  required Widget home,
  required AppLanguage language,
  double textScale = 1.0,
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
    theme: AppThemeData.light(),
    // ב-`builder` ולא סביב `home`: כאן זה יושב **מעל** ה-Navigator, ולכן גם
    // דיאלוגים מוצאים את המלל, ושורת הכותרת מצוירת מעל השכבה שלהם.
    builder: (context, child) => AppStringsScope(
      strings: strings,
      child: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: TitleBarHost(child: child ?? const SizedBox.shrink()),
      ),
    ),
    home: home,
  );
}
