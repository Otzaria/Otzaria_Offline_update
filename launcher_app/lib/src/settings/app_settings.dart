enum AppThemeMode { system, light, dark }

/// כל ההגדרות של הלאנצ'ר, immutable ובעלות [schemaVersion] — נשמרות
/// לקובץ JSON יחיד (ראו `SettingsController`).
///
/// **אין כאן נתיבים.** תיקיית הנתונים תמיד צמודה לקובץ ההרצה (ראו
/// `AppPaths`), והמיקום של אוצריא עצמה מתגלה ואינו מוגדר.
class AppSettings {
  static const int schemaVersion = 2;

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

  // ── התקנה אוטומטית מהתיקייה המקומית ─────────────────────────────────────
  final bool autoInstallApp;
  final bool autoInstallLibrary;

  // ── ערוץ הגרסה של תוכנת אוצריא ──────────────────────────────────────────
  /// `true` = להתקין את הגרסה הלא-יציבה (pre-release). ההורדה מביאה תמיד
  /// את שתי הגרסאות; זו רק הבחירה איזו מהן מותקנת, והיא רלוונטית רק כשיש
  /// pre-release חדש מהיציבה.
  final bool preferAppPrerelease;

  // ── אחסון ───────────────────────────────────────────────────────────────
  /// `0` = בלי גיבוי בטיחות לפני כתיבת מסד מלא (ראו `LibraryUpdateApplier`),
  /// `1` = עם גיבוי. אין כאן שמירת היסטוריה של גרסאות — המראה המקומית
  /// שומרת רק את הגרסה האחרונה שהורדה בכל מקרה.
  final int backupsToKeep;

  // ── רשת ─────────────────────────────────────────────────────────────────
  final int networkTimeoutSeconds;

  // ── ממשק ────────────────────────────────────────────────────────────────
  final AppThemeMode themeMode;
  final double textScale;

  const AppSettings({
    this.autoMetadataCheck = true,
    this.autoCheckOnlineUpdates = true,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.autoInstallApp = false,
    this.autoInstallLibrary = false,
    this.preferAppPrerelease = false,
    this.backupsToKeep = 1,
    this.networkTimeoutSeconds = 20,
    this.themeMode = AppThemeMode.system,
    this.textScale = 1.0,
  });

  /// `false` כשלא נבחר שום רכיב להורדה — ה-UI משתמש בזה כדי להשבית את
  /// כפתור ההורדה במקום להריץ פעולה שלא תעשה כלום.
  bool get hasSyncSelection => syncApp || syncLibrary || syncPlugins;

  AppSettings copyWith({
    bool? autoMetadataCheck,
    bool? autoCheckOnlineUpdates,
    bool? syncApp,
    bool? syncLibrary,
    bool? syncPlugins,
    bool? autoInstallApp,
    bool? autoInstallLibrary,
    bool? preferAppPrerelease,
    int? backupsToKeep,
    int? networkTimeoutSeconds,
    AppThemeMode? themeMode,
    double? textScale,
  }) {
    return AppSettings(
      autoMetadataCheck: autoMetadataCheck ?? this.autoMetadataCheck,
      autoCheckOnlineUpdates:
          autoCheckOnlineUpdates ?? this.autoCheckOnlineUpdates,
      syncApp: syncApp ?? this.syncApp,
      syncLibrary: syncLibrary ?? this.syncLibrary,
      syncPlugins: syncPlugins ?? this.syncPlugins,
      autoInstallApp: autoInstallApp ?? this.autoInstallApp,
      autoInstallLibrary: autoInstallLibrary ?? this.autoInstallLibrary,
      preferAppPrerelease: preferAppPrerelease ?? this.preferAppPrerelease,
      backupsToKeep: backupsToKeep ?? this.backupsToKeep,
      networkTimeoutSeconds:
          networkTimeoutSeconds ?? this.networkTimeoutSeconds,
      themeMode: themeMode ?? this.themeMode,
      textScale: textScale ?? this.textScale,
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
        },
        'storage': {
          'backupsToKeep': backupsToKeep,
        },
        'network': {
          'timeoutSeconds': networkTimeoutSeconds,
        },
        'ui': {
          'themeMode': themeMode.name,
          'textScale': textScale,
        },
      };

  /// קורא הגדרות מ-JSON. שדה חסר או פגום נופל לברירת המחדל שלו — קובץ
  /// מקולקל חלקית, או קובץ מ-schemaVersion 1 (שבו היו נתיבים ומתגים
  /// שהוסרו), לא מאבד את שאר ההגדרות.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) {
      final value = json[key];
      return value is Map<String, dynamic> ? value : const {};
    }

    final automation = section('automation');
    final channels = section('channels');
    final sync = section('sync');
    final storage = section('storage');
    final network = section('network');
    final ui = section('ui');
    const defaults = AppSettings();

    bool flag(Map<String, dynamic> from, String key, bool fallback) {
      final value = from[key];
      return value is bool ? value : fallback;
    }

    int number(Map<String, dynamic> from, String key, int fallback) {
      final value = from[key];
      return value is int ? value : fallback;
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
      autoInstallApp: flag(automation, 'installApp', false),
      autoInstallLibrary: flag(automation, 'installLibrary', false),
      preferAppPrerelease: flag(channels, 'appPrerelease', false),
      backupsToKeep: number(storage, 'backupsToKeep', defaults.backupsToKeep),
      networkTimeoutSeconds: number(
        network,
        'timeoutSeconds',
        defaults.networkTimeoutSeconds,
      ),
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == ui['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      textScale:
          ui['textScale'] is num ? (ui['textScale'] as num).toDouble() : 1.0,
    );
  }
}
