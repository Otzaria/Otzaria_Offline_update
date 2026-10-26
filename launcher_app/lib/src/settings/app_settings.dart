import 'dart:ui' show PlatformDispatcher;

import 'package:error_reports_manager/error_reports_manager.dart'
    show AppCrashReportMode;
import 'package:otzaria_l10n/otzaria_l10n.dart';

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

/// האם ההורדה לכונן מביאה גם את החיפוש החכם (כמה ג׳יגה־בייט). [ask] — השאלה
/// שלפני ההורדה; [always]/[never] נבחרים בהגדרות או ב"אל תציג שוב" שבשאלה.
enum SemanticDownloadPreference {
  ask('ask'),
  always('always'),
  never('never');

  const SemanticDownloadPreference(this.code);

  /// הערך שנשמר תחת `sync.semantic`.
  final String code;

  /// ערך לא מוכר — וגם קובץ מלפני השדה — חוזר לשאלה.
  static SemanticDownloadPreference fromCode(Object? code) {
    for (final preference in values) {
      if (preference.code == code) return preference;
    }
    return SemanticDownloadPreference.ask;
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
  /// מפתח חסר מקבל ברירת מחדל, ומפתח לא מוכר נמחק בשמירה הבאה. הגרסה
  /// נבדקת רק להסבת `reports.crashMode` (ראו [AppSettings.fromJson]).
  static const int schemaVersion = 15;

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

  /// השאלה "מחשבים מרובים או רק המחשב שלי" כבר נענתה בכונן הזה. נוסע עם
  /// הכונן, ולכן היא נשאלת פעם אחת לכונן ולא לכל מחשב.
  final bool personalModeAsked;

  /// "רק המחשב שלי" נבחר במחשב שלא נרשם: המחשב הלא מחובר הראשון שבו אוצריא
  /// מותקנת יירשם. חד-פעמי — נמחק ברישום הזה או בהסרה ידנית.
  final bool personalAutoRegisterPending;

  final SemanticDownloadPreference semanticDownload;

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
  final double textScale;

  // ── מצב סייפר ───────────────────────────────────────────────────────────
  /// `true` = ההגדרות ועריכת ההדרכה נעולות בסיסמה. אין לזה משמעות בלי
  /// [saferModePassword], ולכן שאלו תמיד את [saferModeActive].
  final bool saferModeEnabled;

  /// הסיסמה, מעורבלת — `"<מלח>:<sha256(מלח+סיסמה)>"`, וריק כשאין. **הסיסמה
  /// עצמה לעולם אינה נשמרת**; המלח נוצר מחדש בכל בחירת סיסמה, כך שאותה
  /// סיסמה על שני כוננים אינה נראית אותו דבר בקובץ.
  final String saferModePassword;

  // ── דיווח על תקלות ──────────────────────────────────────────────────────
  /// מה לעשות אחרי סגירה לא צפויה — כמו `keyAppCrashReportMode` באוצריא.
  final AppCrashReportMode crashReportMode;

  /// הכתובת האחרונה שנשלחה בטופס (כמו `savedSenderEmail` באוצריא), לפי שם
  /// המחשב: ההגדרות נוסעות על הכונן, וכתובת אישית לא אמורה לצוץ במחשב אחר.
  final Map<String, String> reportSenderEmails;

  /// השפה שבה הממשק מוצג בפועל: [languagePreference] אחרי פתירת "אוטומטי".
  AppLanguage get language => languagePreference.resolve();

  const AppSettings({
    this.autoCheckUpdates = true,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.personalUpdateMode = false,
    this.personalModeAsked = false,
    this.personalAutoRegisterPending = false,
    this.semanticDownload = SemanticDownloadPreference.ask,
    this.autoInstall = false,
    this.preferAppPrerelease = false,
    this.languagePreference = AppLanguagePreference.system,
    this.textScale = 1.0,
    this.saferModeEnabled = false,
    this.saferModePassword = '',
    this.crashReportMode = AppCrashReportMode.always,
    this.reportSenderEmails = const {},
  });

  /// האם ההורדה מביאה את הספרייה בפועל. "עדכון אישי" כופה אותה, בלי לדרוס
  /// את [syncLibrary] — כך שכיבוי המצב מחזיר את הבחירה הקודמת.
  bool get downloadsLibrary => syncLibrary || personalUpdateMode;

  /// `false` כשלא נבחר שום רכיב להורדה — ה-UI משתמש בזה כדי להשבית את
  /// כפתור ההורדה במקום להריץ פעולה שלא תעשה כלום.
  bool get hasSyncSelection => syncApp || downloadsLibrary || syncPlugins;

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
    bool? personalModeAsked,
    bool? personalAutoRegisterPending,
    SemanticDownloadPreference? semanticDownload,
    bool? autoInstall,
    bool? preferAppPrerelease,
    AppLanguagePreference? languagePreference,
    double? textScale,
    bool? saferModeEnabled,
    String? saferModePassword,
    AppCrashReportMode? crashReportMode,
    Map<String, String>? reportSenderEmails,
  }) {
    return AppSettings(
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      syncApp: syncApp ?? this.syncApp,
      syncLibrary: syncLibrary ?? this.syncLibrary,
      syncPlugins: syncPlugins ?? this.syncPlugins,
      personalUpdateMode: personalUpdateMode ?? this.personalUpdateMode,
      personalModeAsked: personalModeAsked ?? this.personalModeAsked,
      personalAutoRegisterPending:
          personalAutoRegisterPending ?? this.personalAutoRegisterPending,
      semanticDownload: semanticDownload ?? this.semanticDownload,
      autoInstall: autoInstall ?? this.autoInstall,
      preferAppPrerelease: preferAppPrerelease ?? this.preferAppPrerelease,
      languagePreference: languagePreference ?? this.languagePreference,
      textScale: textScale ?? this.textScale,
      saferModeEnabled: saferModeEnabled ?? this.saferModeEnabled,
      saferModePassword: saferModePassword ?? this.saferModePassword,
      crashReportMode: crashReportMode ?? this.crashReportMode,
      reportSenderEmails: reportSenderEmails ?? this.reportSenderEmails,
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
          'personalAsked': personalModeAsked,
          'personalAutoRegister': personalAutoRegisterPending,
          'semantic': semanticDownload.code,
        },
        'ui': {
          'language': languagePreference.code,
          'textScale': textScale,
        },
        'protection': {
          'enabled': saferModeEnabled,
          'password': saferModePassword,
        },
        'reports': {
          'crashMode': crashReportMode.wireName,
          'senderEmails': reportSenderEmails,
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
    final reports = section('reports');
    const defaults = AppSettings();

    bool flag(Map<String, dynamic> from, String key, bool fallback) {
      final value = from[key];
      return value is bool ? value : fallback;
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

    // עד סכימה 14 "לשאול" היה ברירת המחדל ונכתב לכל קובץ, כך שאין לדעת אם
    // נבחר; ברירת המחדל החדשה (לבקשת המתחזק) חלה גם עליו. "לא לשלוח" נשמר.
    AppCrashReportMode crashMode() {
      final mode = AppCrashReportMode.parse(reports['crashMode']);
      final version = json['schemaVersion'];
      final legacy = version is! int || version < 15;
      return legacy && mode == AppCrashReportMode.ask
          ? AppCrashReportMode.always
          : mode;
    }

    final personalMode =
        flag(sync, 'personalMode', defaults.personalUpdateMode);

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
      personalUpdateMode: personalMode,
      // כונן שכבר הפעיל עדכון אישי ענה על השאלה, גם לפני שהיא הייתה.
      personalModeAsked: flag(sync, 'personalAsked', personalMode),
      personalAutoRegisterPending: flag(sync, 'personalAutoRegister', false),
      semanticDownload: SemanticDownloadPreference.fromCode(sync['semantic']),
      autoInstall: merged(
        'install',
        'installApp',
        'installLibrary',
        defaults.autoInstall,
      ),
      preferAppPrerelease:
          flag(channels, 'appPrerelease', defaults.preferAppPrerelease),
      languagePreference: AppLanguagePreference.fromCode(ui['language']),
      textScale: textScale(defaults.textScale),
      saferModeEnabled: flag(
        protection,
        'enabled',
        defaults.saferModeEnabled,
      ),
      saferModePassword: protection['password'] is String
          ? protection['password'] as String
          : defaults.saferModePassword,
      crashReportMode: crashMode(),
      reportSenderEmails: {
        if (reports['senderEmails'] case final Map<dynamic, dynamic> emails)
          for (final entry in emails.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
    );
  }
}
