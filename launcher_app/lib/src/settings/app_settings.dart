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
  /// 8: `sync.fullPackage` — חבילת ההתקנה המלאה של אוצריא.
  static const int schemaVersion = 8;

  /// בדיקת גרסאות בפתיחה כשיש חיבור לרשת — בדיקה קלה, בלי הורדה.
  final bool autoMetadataCheck;

  /// בדיקה חד-פעמית בפתיחה מול GitHub — "יש עדכון חדש ברשת?" — קלה
  /// (מטא-דאטה בלבד, בלי הורדת המסד/ההתקנה). כשל (אין רשת) נבלע בשקט.
  /// לא קשור ל-[autoMetadataCheck], שהוא בדיקה מקומית בלבד.
  final bool autoCheckOnlineUpdates;

  // ── מה נכלל בהורדה ──────────────────────────────────────────────────────
  /// אילו רכיבים פעולת ההורדה מביאה אל התיקייה המקומית. ההורדה עצמה תמיד
  /// יזומה בלחיצה; הבחירה כאן רק זוכרת מה סומן בפעם הקודמת.
  final bool syncApp;
  final bool syncLibrary;
  final bool syncPlugins;

  /// `true` = ההורדה מביאה גם את **חבילת ההתקנה המלאה** של אוצריא (הגרסה
  /// היציבה האחרונה, ~2GB, כוללת את הספרייה בתוכה). **כבוי כברירת מחדל**:
  /// היא נחוצה רק למחשב שאוצריא מותקנת בו בפעם הראשונה, ומי שלא סימן
  /// אותה לא רואה ממנה דבר.
  final bool syncFullPackage;

  /// `true` = "עדכון אישי": ההורדה מביאה רק קובצי עדכון מהגרסה שנרשמה ומעלה,
  /// בלי המסד המלא (~1.5GB). ברירת המחדל `false` — התוכנה היא כלי הפצה, וכונן
  /// בלי המסד המלא אינו יכול לשרת מחשב שאין בו אוצריא בכלל.
  final bool personalUpdateMode;

  // ── התקנה אוטומטית מהתיקייה המקומית ─────────────────────────────────────
  final bool autoInstallApp;
  final bool autoInstallLibrary;

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

  /// השפה שבה הממשק מוצג בפועל: [languagePreference] אחרי פתירת "אוטומטי".
  AppLanguage get language => languagePreference.resolve();

  const AppSettings({
    this.autoMetadataCheck = true,
    this.autoCheckOnlineUpdates = true,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.syncFullPackage = false,
    this.personalUpdateMode = false,
    this.autoInstallApp = false,
    this.autoInstallLibrary = false,
    this.preferAppPrerelease = false,
    this.languagePreference = AppLanguagePreference.system,
    this.themeMode = AppThemeMode.system,
    this.textScale = 1.0,
    this.seedColor = AppSeedColors.defaultLight,
    this.darkSeedColor = AppSeedColors.defaultDark,
  });

  /// `false` כשלא נבחר שום רכיב להורדה — ה-UI משתמש בזה כדי להשבית את
  /// כפתור ההורדה במקום להריץ פעולה שלא תעשה כלום.
  bool get hasSyncSelection =>
      syncApp || syncLibrary || syncPlugins || syncFullPackage;

  /// גבולות שפיות ל-[textScale] בקריאה מהדיסק — **לא** רשימת האפשרויות
  /// שבהגדרות (0.9/1.0/1.15). רחבים בכוונה: קובץ שנערך ביד או נשמר בגרסה
  /// אחרת עשוי להחזיק 1.3 או 2.0, ואין סיבה לדרוס אותו.
  static const double minTextScale = 0.5;
  static const double maxTextScale = 3.0;

  AppSettings copyWith({
    bool? autoMetadataCheck,
    bool? autoCheckOnlineUpdates,
    bool? syncApp,
    bool? syncLibrary,
    bool? syncPlugins,
    bool? syncFullPackage,
    bool? personalUpdateMode,
    bool? autoInstallApp,
    bool? autoInstallLibrary,
    bool? preferAppPrerelease,
    AppLanguagePreference? languagePreference,
    AppThemeMode? themeMode,
    double? textScale,
    Color? seedColor,
    Color? darkSeedColor,
  }) {
    return AppSettings(
      autoMetadataCheck: autoMetadataCheck ?? this.autoMetadataCheck,
      autoCheckOnlineUpdates:
          autoCheckOnlineUpdates ?? this.autoCheckOnlineUpdates,
      syncApp: syncApp ?? this.syncApp,
      syncLibrary: syncLibrary ?? this.syncLibrary,
      syncPlugins: syncPlugins ?? this.syncPlugins,
      syncFullPackage: syncFullPackage ?? this.syncFullPackage,
      personalUpdateMode: personalUpdateMode ?? this.personalUpdateMode,
      autoInstallApp: autoInstallApp ?? this.autoInstallApp,
      autoInstallLibrary: autoInstallLibrary ?? this.autoInstallLibrary,
      preferAppPrerelease: preferAppPrerelease ?? this.preferAppPrerelease,
      languagePreference: languagePreference ?? this.languagePreference,
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
      seedColor: seedColor ?? this.seedColor,
      darkSeedColor: darkSeedColor ?? this.darkSeedColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'automation': {
          'metadataCheck': autoMetadataCheck,
          'checkOnlineUpdates': autoCheckOnlineUpdates,
          'installApp': autoInstallApp,
          'installLibrary': autoInstallLibrary,
        },
        'channels': {
          'appPrerelease': preferAppPrerelease,
        },
        'sync': {
          'app': syncApp,
          'library': syncLibrary,
          'plugins': syncPlugins,
          'fullPackage': syncFullPackage,
          'personalMode': personalUpdateMode,
        },
        'ui': {
          'language': languagePreference.code,
          'themeMode': themeMode.name,
          'textScale': textScale,
          // ARGB שלם, כמו ש-`key-swatch-color` נשמר באוצריא.
          'seedColor': seedColor.toARGB32(),
          'darkSeedColor': darkSeedColor.toARGB32(),
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

    return AppSettings(
      autoMetadataCheck: flag(
        automation,
        'metadataCheck',
        defaults.autoMetadataCheck,
      ),
      autoCheckOnlineUpdates: flag(
        automation,
        'checkOnlineUpdates',
        defaults.autoCheckOnlineUpdates,
      ),
      syncApp: flag(sync, 'app', defaults.syncApp),
      syncLibrary: flag(sync, 'library', defaults.syncLibrary),
      syncPlugins: flag(sync, 'plugins', defaults.syncPlugins),
      syncFullPackage: flag(sync, 'fullPackage', defaults.syncFullPackage),
      personalUpdateMode:
          flag(sync, 'personalMode', defaults.personalUpdateMode),
      autoInstallApp: flag(automation, 'installApp', defaults.autoInstallApp),
      autoInstallLibrary:
          flag(automation, 'installLibrary', defaults.autoInstallLibrary),
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
    );
  }
}
