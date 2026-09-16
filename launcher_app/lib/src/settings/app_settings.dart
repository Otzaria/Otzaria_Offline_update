import 'dart:ui' show Color, PlatformDispatcher;

import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../theme/app_seed_colors.dart';

enum AppThemeMode { system, light, dark }

/// בחירת שפת הממשק. [system] — לפי שפת מערכת ההפעלה, וזו ברירת המחדל:
/// התקנה חדשה מדברת בשפה שהמחשב כבר מדבר, בלי שאיש יגדיר דבר.
enum AppLanguagePreference {
  system('system'),
  hebrew('he'),
  english('en');

  const AppLanguagePreference(this.code);

  /// גם הערך שנשמר תחת `ui.language` בקובץ ההגדרות.
  final String code;

  /// השפה בפועל. [system] נפתר בכל קריאה, ולכן שינוי שפה במערכת ההפעלה
  /// נתפס מעצמו בהרצה הבאה בלי לגעת בקובץ ההגדרות.
  AppLanguage resolve() => switch (this) {
        AppLanguagePreference.system => systemLanguage(),
        AppLanguagePreference.hebrew => AppLanguage.hebrew,
        AppLanguagePreference.english => AppLanguage.english,
      };

  /// ערך לא מוכר — וגם קובץ הגדרות מלפני השדה הזה — נופל לזיהוי אוטומטי.
  static AppLanguagePreference fromCode(Object? code) {
    for (final preference in values) {
      if (preference.code == code) return preference;
    }
    return AppLanguagePreference.system;
  }
}

/// שפת מערכת ההפעלה, מצומצמת לשפות שהלאנצ'ר מדבר.
///
/// `PlatformDispatcher` ולא `Platform.localeName` — הראשון הוא שפת *הממשק*
/// של המערכת, השני רק תבנית האזור (מחשב באנגלית עם אזור "ישראל" מדווח שם
/// עברית). `instance` ישירות ולא דרך `WidgetsBinding`, כדי שגם קריאה לפני
/// אתחול ה-binding תעבוד — `main` קורא לזה לפני שההגדרות נטענו.
AppLanguage systemLanguage() {
  final locales = PlatformDispatcher.instance.locales;
  // מערכת שלא דיווחה שום locale — עברית, שפת הבית של התוכנה. זה שונה
  // ממחשב שדיווח שפה אחרת, שאותו [AppLanguage.forLanguageCode] שולח לאנגלית.
  if (locales.isEmpty) return AppLanguage.hebrew;
  return AppLanguage.forLanguageCode(locales.first.languageCode);
}

/// כל ההגדרות של הלאנצ'ר, immutable ובעלות [schemaVersion] — נשמרות
/// לקובץ JSON יחיד (ראו `SettingsController`).
///
/// **אין כאן נתיבים.** תיקיית הנתונים תמיד צמודה לקובץ ההרצה (ראו
/// `AppPaths`), והמיקום של אוצריא עצמה מתגלה ואינו מוגדר.
class AppSettings {
  /// 4: מקטע `storage` (גיבוי המסד) הוסר — ראו `LibraryDbRecoveryService`.
  /// 5: `ui.language` מקבל גם `system` — לפי שפת המחשב, וזו ברירת המחדל.
  /// 6: `ui.seedColor` / `ui.darkSeedColor` — פלטת הצבעים של אוצריא.
  /// 7: `sync.personalMode` — הורדה למחשב שלי בלבד, בלי המסד המלא.
  /// 8: `sync.fullPackage` — חבילת ההתקנה המלאה של אוצריא (הוסר).
  /// 9: `ui.showFaq` — הכפתור הצף של השאלות הנפוצות.
  /// 10: `protection` — מצב סייפר: נעילת ההגדרות בסיסמה.
  /// 11: `automation` — שני דגלים במקום ארבעה: בדיקה והתקנה, כל אחד
  ///     לתוכנה ולספרייה גם יחד.
  static const int schemaVersion = 11;

  /// בדיקת עדכונים בפתיחה — גם מקומית (התיקייה שלצד התוכנה) וגם קלה מול
  /// GitHub כשיש רשת: מטא-דאטה בלבד, בלי הורדה, וכשל (אין רשת) נבלע בשקט.
  final bool autoCheckUpdates;

  // ── מה נכלל בהורדה ──────────────────────────────────────────────────────
  /// אילו רכיבים פעולת ההורדה מביאה אל התיקייה המקומית. ההורדה עצמה תמיד
  /// יזומה בלחיצה; הבחירה כאן רק זוכרת מה סומן בפעם הקודמת.
  final bool syncApp;
  final bool syncLibrary;
  final bool syncPlugins;

  /// `true` = "עדכון אישי": ההורדה מביאה רק קובצי עדכון מהגרסה שנרשמה ומעלה,
  /// בלי המסד המלא (~1.5GB). ברירת המחדל `false` — התוכנה היא כלי הפצה, וכונן
  /// בלי המסד המלא אינו יכול לשרת מחשב שאין בו אוצריא בכלל.
  final bool personalUpdateMode;

  // ── התקנה אוטומטית מהתיקייה המקומית ─────────────────────────────────────
  /// התוכנה והספרייה יחד — התקנה ראשונה לעולם אינה אוטומטית.
  final bool autoInstall;

  // ── ערוץ הגרסה של תוכנת אוצריא ──────────────────────────────────────────
  /// `true` = להתקין את הגרסה הלא-יציבה (pre-release). ההורדה מביאה תמיד
  /// את שתי הגרסאות; זו רק הבחירה איזו מהן מותקנת, והיא רלוונטית רק כשיש
  /// pre-release חדש מהיציבה.
  final bool preferAppPrerelease;

  // ── ממשק ────────────────────────────────────────────────────────────────
  /// *הבחירה* בהגדרות — כולל "אוטומטי", שהיא ברירת המחדל. השפה שמוצגת
  /// בפועל היא [language].
  final AppLanguagePreference languagePreference;
  final AppThemeMode themeMode;
  final double textScale;

  /// צבעי ה-seed שמהם נבנית ערכת הצבעים — אחד לכל בהירות, כמו באוצריא:
  /// הבחירה בהגדרות חלה על הערכה המוצגת באותו רגע.
  final Color seedColor;
  final Color darkSeedColor;

  /// הכפתור הצף של השאלות הנפוצות בדף הבית. דלוק כברירת מחדל — הוא ההדרכה
  /// היחידה בתוכנה — וכיבוי מסתיר אותו לגמרי, כולל ההבהוב שבעלייה.
  final bool showFaqButton;

  // ── מצב סייפר ───────────────────────────────────────────────────────────
  /// `true` = ההגדרות ועריכת ההדרכה נעולות בסיסמה. אין לזה משמעות בלי
  /// [saferModePassword], ולכן שאלו תמיד את [saferModeActive].
  final bool saferModeEnabled;

  /// הסיסמה, מעורבלת — `"<מלח>:<sha256(מלח+סיסמה)>"`, וריק כשאין. **הסיסמה
  /// עצמה לעולם אינה נשמרת**; המלח נוצר מחדש בכל בחירת סיסמה, כך שאותה
  /// סיסמה על שני כוננים אינה נראית אותו דבר בקובץ.
  final String saferModePassword;

  /// השפה שבה הממשק מוצג בפועל: [languagePreference] אחרי פתירת "אוטומטי".
  AppLanguage get language => languagePreference.resolve();

  const AppSettings({
    this.autoCheckUpdates = true,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.personalUpdateMode = false,
    this.autoInstall = false,
    this.preferAppPrerelease = false,
    this.languagePreference = AppLanguagePreference.system,
    this.themeMode = AppThemeMode.system,
    this.textScale = 1.0,
    this.seedColor = AppSeedColors.defaultLight,
    this.darkSeedColor = AppSeedColors.defaultDark,
    this.showFaqButton = true,
    this.saferModeEnabled = false,
    this.saferModePassword = '',
  });

  /// `false` כשלא נבחר שום רכיב להורדה — ה-UI משתמש בזה כדי להשבית את
  /// כפתור ההורדה במקום להריץ פעולה שלא תעשה כלום.
  bool get hasSyncSelection => syncApp || syncLibrary || syncPlugins;

  /// יש סיסמה שמורה — התנאי להפעלת מצב הסייפר.
  bool get hasSaferModePassword => saferModePassword.isNotEmpty;

  /// מצב הסייפר נועל בפועל. מתג דלוק בלי סיסמה אינו נועל דבר — כך קובץ
  /// שנערך ביד אינו יכול לנעול את ההגדרות בסיסמה שאינה קיימת.
  bool get saferModeActive => saferModeEnabled && hasSaferModePassword;

  /// גבולות שפיות ל-[textScale] בקריאה מהדיסק — **לא** רשימת האפשרויות
  /// שבהגדרות (0.9/1.0/1.15). רחבים בכוונה: קובץ שנערך ביד או נשמר בגרסה
  /// אחרת עשוי להחזיק 1.3 או 2.0, ואין סיבה לדרוס אותו.
  static const double minTextScale = 0.5;
  static const double maxTextScale = 3.0;

  AppSettings copyWith({
    bool? autoCheckUpdates,
    bool? syncApp,
    bool? syncLibrary,
    bool? syncPlugins,
    bool? personalUpdateMode,
    bool? autoInstall,
    bool? preferAppPrerelease,
    AppLanguagePreference? languagePreference,
    AppThemeMode? themeMode,
    double? textScale,
    Color? seedColor,
    Color? darkSeedColor,
    bool? showFaqButton,
    bool? saferModeEnabled,
    String? saferModePassword,
  }) {
    return AppSettings(
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      syncApp: syncApp ?? this.syncApp,
      syncLibrary: syncLibrary ?? this.syncLibrary,
      syncPlugins: syncPlugins ?? this.syncPlugins,
      personalUpdateMode: personalUpdateMode ?? this.personalUpdateMode,
      autoInstall: autoInstall ?? this.autoInstall,
      preferAppPrerelease: preferAppPrerelease ?? this.preferAppPrerelease,
      languagePreference: languagePreference ?? this.languagePreference,
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
      seedColor: seedColor ?? this.seedColor,
      darkSeedColor: darkSeedColor ?? this.darkSeedColor,
      showFaqButton: showFaqButton ?? this.showFaqButton,
      saferModeEnabled: saferModeEnabled ?? this.saferModeEnabled,
      saferModePassword: saferModePassword ?? this.saferModePassword,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'automation': {
          'checkUpdates': autoCheckUpdates,
          'install': autoInstall,
        },
        'channels': {
          'appPrerelease': preferAppPrerelease,
        },
        'sync': {
          'app': syncApp,
          'library': syncLibrary,
          'plugins': syncPlugins,
          'personalMode': personalUpdateMode,
        },
        'ui': {
          'language': languagePreference.code,
          'themeMode': themeMode.name,
          'textScale': textScale,
          // ARGB שלם, כמו ש-`key-swatch-color` נשמר באוצריא.
          'seedColor': seedColor.toARGB32(),
          'darkSeedColor': darkSeedColor.toARGB32(),
          'showFaq': showFaqButton,
        },
        'protection': {
          'enabled': saferModeEnabled,
          'password': saferModePassword,
        },
      };

  /// קורא הגדרות מ-JSON. שדה חסר או פגום נופל לברירת המחדל שלו — קובץ
  /// מקולקל חלקית, או קובץ מגרסת schema ישנה (שבה היו נתיבים, זמן קצוב
  /// לרשת, גיבוי המסד ומתגים שהוסרו), לא מאבד את שאר ההגדרות.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? value : const {};
    }

    final automation = section('automation');
    final channels = section('channels');
    final sync = section('sync');
    final ui = section('ui');
    final protection = section('protection');
    const defaults = AppSettings();

    bool flag(Map<String, dynamic> from, String key, bool fallback) {
      final value = from[key];
      return value is bool ? value : fallback;
    }

    Color color(String key, Color fallback) {
      final value = ui[key];
      return value is int ? Color(value) : fallback;
    }

    // ערך פגום היה מגיע ישר ל-`MediaQuery.withClampedTextScaling` (ראו
    // `main.dart`): שלילי מפיל שם assert, ו-40 משאיר ממשק שאי אפשר לתקן בו
    // כלום — כולל את מסך ההגדרות שבו משנים אותו בחזרה.
    double textScale(double fallback) {
      final value = ui['textScale'];
      if (value is! num || !value.toDouble().isFinite) return fallback;
      return value.toDouble().clamp(minTextScale, maxTextScale);
    }

    // קובץ מגרסה 10 ומטה החזיק ארבעה דגלים, ושניים מהם מתמזגים לאחד.
    // המיזוג שמרני — **וגם** ולא **או**: הפעלה שהמשתמש מעולם לא אישר
    // (פנייה לרשת, או התקנה שדורסת קבצים) לא תידלק כאן מאליה.
    bool merged(String key, String legacyA, String legacyB, bool fallback) {
      final value = automation[key];
      if (value is bool) return value;
      final a = automation[legacyA];
      final b = automation[legacyB];
      if (a is! bool && b is! bool) return fallback;
      // מפתח חסר בקובץ הישן שווה לברירת המחדל שלו — זהה לחדשה.
      return (a is bool ? a : fallback) && (b is bool ? b : fallback);
    }

    return AppSettings(
      autoCheckUpdates: merged(
        'checkUpdates',
        'metadataCheck',
        'checkOnlineUpdates',
        defaults.autoCheckUpdates,
      ),
      syncApp: flag(sync, 'app', defaults.syncApp),
      syncLibrary: flag(sync, 'library', defaults.syncLibrary),
      syncPlugins: flag(sync, 'plugins', defaults.syncPlugins),
      personalUpdateMode:
          flag(sync, 'personalMode', defaults.personalUpdateMode),
      autoInstall: merged(
        'install',
        'installApp',
        'installLibrary',
        defaults.autoInstall,
      ),
      preferAppPrerelease:
          flag(channels, 'appPrerelease', defaults.preferAppPrerelease),
      languagePreference: AppLanguagePreference.fromCode(ui['language']),
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == ui['themeMode'],
        orElse: () => defaults.themeMode,
      ),
      textScale: textScale(defaults.textScale),
      seedColor: color('seedColor', defaults.seedColor),
      darkSeedColor: color('darkSeedColor', defaults.darkSeedColor),
      showFaqButton: flag(ui, 'showFaq', defaults.showFaqButton),
      saferModeEnabled: flag(
        protection,
        'enabled',
        defaults.saferModeEnabled,
      ),
      saferModePassword: protection['password'] is String
          ? protection['password'] as String
          : defaults.saferModePassword,
    );
  }
}
