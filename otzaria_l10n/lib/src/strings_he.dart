import 'app_language.dart';
import 'app_strings.dart';

/// עברית — ברירת המחדל. הנוסח כאן הוא המקור; האנגלית היא תרגום חופשי שלו.
class HebrewStrings extends AppStrings {
  const HebrewStrings();

  @override
  AppLanguage get language => AppLanguage.hebrew;

  @override
  CommonStrings get common => const _Common();
  @override
  ShellStrings get shell => const _Shell();
  @override
  HomeStrings get home => const _Home();
  @override
  AppScreenStrings get appScreen => const _AppScreen();
  @override
  LibraryScreenStrings get libraryScreen => const _LibraryScreen();
  @override
  SettingsScreenStrings get settings => const _Settings();
  @override
  PluginsStrings get plugins => const _Plugins();
  @override
  CustomAppsStrings get customApps => const _CustomApps();
  @override
  SetupErrorStrings get setupError => const _SetupError();
  @override
  LauncherUpdateStrings get launcherUpdate => const _LauncherUpdate();
  @override
  UnitStrings get units => const _Units();
  @override
  LibraryDomainStrings get libraryDomain => const _LibraryDomain();
  @override
  AppDomainStrings get appDomain => const _AppDomain();
  @override
  PluginsDomainStrings get pluginsDomain => const _PluginsDomain();
  @override
  CustomAppsDomainStrings get customAppsDomain => const _CustomAppsDomain();
}

class _Common extends CommonStrings {
  const _Common();

  @override
  String get confirm => 'אישור';
  @override
  String get cancel => 'ביטול';
  @override
  String get continueAction => 'המשך';
  @override
  String get close => 'סגירה';
  @override
  String get error => 'שגיאה';
  @override
  String get retry => 'נסה שוב';
  @override
  String get install => 'התקנה';
  @override
  String get update => 'עדכון';
  @override
  String get launch => 'הפעלה';
  @override
  String get recheck => 'בדיקה מחדש';
  @override
  String get notCheckedYet => 'טרם נבדק';
  @override
  String get checking => 'בודק...';
  @override
  String get upToDate => 'מעודכן';
  @override
  String get updateAvailable => 'יש עדכון חדש';
  @override
  String get installing => 'מתקין...';
  @override
  String get unknownValue => 'לא ידועה';
  @override
  String get lastDownloaded => 'הורד לאחרונה';
  @override
  String get emptyValue => '—';
}

class _Shell extends ShellStrings {
  const _Shell();

  @override
  String get appTitle => 'עדכוני אוצריא';
  @override
  String get otzariaLogoLabel => 'אוצריא';
  @override
  String get navHome => 'דף הבית';
  @override
  String get navApp => 'תוכנה';
  @override
  String get navLibrary => 'ספרייה';
  @override
  String get navPlugins => 'תוספים';
  @override
  String get navCustomApps => 'תוכנות נוספות';
  @override
  String get navSettings => 'הגדרות';
  @override
  String logPathFallback(String path) => 'נתיב יומן הפעילות: $path';
}

class _Home extends HomeStrings {
  const _Home();

  @override
  String get title => 'דף הבית';
  @override
  String get description =>
      'עדכון התוכנה והספרייה מהתיקייה שלצד התוכנה — בלי צורך באינטרנט.';

  @override
  String get otzariaRunningTitle => 'אוצריא פתוחה';
  @override
  String get otzariaRunningSubtitle => 'עדכון הספרייה חסום עד לסגירתה.';

  @override
  String get appTileTitle => 'תוכנת אוצריא';
  @override
  String get libraryTileTitle => 'הספרייה';

  @override
  String get appNoInstallFound => 'לא נמצאה התקנה';
  @override
  String get appNothingDownloaded => 'טרם הורד עדכון';

  @override
  String get noActionAvailable =>
      'אין פעולה זמינה כרגע — לפרטים ולבחירה ידנית ראו למטה.';
  @override
  String get moreDetails => 'פרטים נוספים';

  @override
  String get appInstallDialogTitle => 'התקנת תוכנת אוצריא';
  @override
  String get appInstallConfirm => 'התקן';
  @override
  String appInstalledSnack(String version) => 'אוצריא עודכנה לגרסה $version';

  @override
  String get otzariaOpenSnack => 'אוצריא פתוחה — יש לסגור אותה ואז לנסות שוב.';
  @override
  String get libraryUpdateDialogTitle => 'עדכון הספרייה';
  @override
  String libraryFreshInstallPrompt(String targetVersion) =>
      'הספרייה תותקן בפעם הראשונה (גרסה $targetVersion) מהתיקייה שלצד '
      'התוכנה. המסד גדול, וההתקנה עשויה להימשך זמן רב.';
  @override
  String libraryUpdatePrompt(String localVersion, String targetVersion) =>
      'המסד יעודכן מגרסה $localVersion לגרסה $targetVersion. המסד הקיים יוחלף '
      'רק אחרי שהגרסה החדשה תיבדק בהצלחה.';
  @override
  String get libraryUpdateConfirm => 'עדכן עכשיו';
  @override
  String libraryUpdatedSnack(String version) => 'המסד עודכן לגרסה $version';

  @override
  String get onlineCardTitle => 'בדיקת עדכונים';
  @override
  String get onlineCardSubtitle =>
      'רק במחשב שיש בו אינטרנט — לא נדרש בשביל ההתקנה עצמה.';
  @override
  String get onlineChecking => 'בודק אם יש עדכונים ברשת...';
  @override
  String get onlineNeverChecked => 'טרם נבדק בהרצה הזו';
  @override
  String get onlineOffline => 'אין חיבור לרשת כרגע';
  @override
  String get onlineHasUpdates => 'נמצאו עדכונים חדשים ברשת';
  @override
  String get onlineNoUpdates => 'אין עדכונים חדשים ברשת';
  @override
  String get checkForUpdatesButton => 'בדיקת עדכונים';
  @override
  String get downloadNowButton => 'הורד עכשיו';
  @override
  String lastCheckedAt(String time) => 'נבדק לאחרונה: $time';

  @override
  String get downloadingApp => 'מוריד את תוכנת אוצריא...';
  @override
  String get downloadingLibrary => 'מוריד את הספרייה...';
  @override
  String get downloadingPlugins => 'מוריד את התוספים...';
  @override
  String get downloadStarting => 'מתחיל הורדה...';

  @override
  String get libraryNotInstalledYet => 'טרם הותקנה ספרייה';
  @override
  String get libraryUpdating => 'מעדכן...';
  @override
  String get libraryNothingDownloaded => 'טרם הורדו עדכונים';
  @override
  String get libraryNeedsManualPath => 'נדרשת בחירת מיקום';
}

class _AppScreen extends AppScreenStrings {
  const _AppScreen();

  @override
  String get title => 'עדכון תוכנת אוצריא';
  @override
  String get description =>
      'ההתקנה מוחלת מהתיקייה שלצד התוכנה, בלי צורך באינטרנט. יש לוודא '
      'שאוצריא סגורה לפני התקנה.';

  @override
  String get stateCardTitle => 'מצב ההתקנה';
  @override
  String get stateRowTitle => 'מצב';
  @override
  String get readyToInstall => 'מוכן להתקנה';
  @override
  String get nothingDownloadedYet => 'טרם הורדה גרסה';

  @override
  String get installedVersion => 'גרסה מותקנת';
  @override
  String get noInstallDetected => 'לא זוהתה התקנה';
  @override
  String get pickInstallDirButton => 'בחירת מיקום ידנית';
  @override
  String get pickInstallDirDialogTitle => 'בחירת תיקיית ההתקנה של אוצריא';
  @override
  String get installAdoptedSnack => 'נמצאה התקנת אוצריא — הגרסה עודכנה';
  @override
  String get installNotFoundSnack => 'לא נמצאה התקנת אוצריא בתיקייה שנבחרה';

  @override
  String get mirrorVersionTitle => 'גרסה בתיקייה המקומית';
  @override
  String get mirrorEmpty => 'אין — יש להריץ הורדה';
  @override
  String channelPair(String stable, String prerelease) =>
      '$stable (יציבה) · $prerelease (לא יציבה)';

  @override
  String get channelTileTitle => 'הגרסה שתותקן';
  @override
  String prereleaseSubtitle(String version) =>
      'הגרסה הלא-יציבה ($version) — חדשה יותר, אך עלולה להכיל תקלות';
  @override
  String stableSubtitle(String version) => 'הגרסה היציבה ($version) — מומלץ';
  @override
  String get channelStable => 'יציבה';
  @override
  String get channelPrerelease => 'לא יציבה';

  @override
  String get processTitle => 'תהליך אוצריא';
  @override
  String get processRunning => 'פתוחה כרגע — עדכון מסד חסום עד לסגירתה';
  @override
  String get processStopped => 'סגורה';

  @override
  String get installingProgress => 'מתקין את אוצריא...';
  @override
  String get launchButton => 'הפעלת אוצריא';
  @override
  String get installUpdateButton => 'התקנת העדכון';

  @override
  String get whatsNewTitle => 'מה התחדש בגרסה האחרונה';
  @override
  String get whatsNewEmpty => 'אין תיאור לגרסה הזו, או שעדיין לא הורדה גרסה.';

  @override
  String get sourceCardTitle => 'התיקייה שממנה מתקינים';
  @override
  String get sourceCardSubtitle =>
      'קבועה, לצד קובץ ההרצה — ראו "עדכון ספרייה" להסבר המלא.';
  @override
  String get sourceDirTitle => 'תיקיית עדכוני התוכנה';

  @override
  String installPrompt({
    required String? latestVersion,
    required String? currentVersion,
    required bool prereleaseNote,
  }) {
    final channelNote = prereleaseNote
        ? ' זו הגרסה הלא-יציבה (pre-release) שנבחרה בהגדרות מסך התוכנה.'
        : '';
    return 'הגרסה $latestVersion תותקן מהתיקייה המקומית על גבי '
        '${currentVersion ?? 'ההתקנה הקיימת'}.$channelNote '
        'ההתקנה אינה דורשת אינטרנט. יש לוודא שאוצריא סגורה.';
  }
}

class _LibraryScreen extends LibraryScreenStrings {
  const _LibraryScreen();

  @override
  String get title => 'עדכון ספרייה';
  @override
  String get description =>
      'העדכון מוחל מתיקיית התוכנה. המסד לא ייגע בו עד שתאשר, ובזמן שאוצריא '
      'פתוחה העדכון חסום.';

  @override
  String get stateCardTitle => 'מצב המסד';
  @override
  String get stateRowTitle => 'מצב';

  @override
  String get dbFileTitle => 'קובץ seforim.db הפעיל';
  @override
  String get dbFileMissing => 'לא נמצא — יש להצביע על הקובץ';
  @override
  String get pickDbButton => 'בחירת קובץ מסד';
  @override
  String get pickDbDialogTitle => 'בחירת קובץ seforim.db';
  @override
  String get dbPathUpdatedSnack => 'מיקום המסד עודכן';

  @override
  String get installTargetTitle => 'הספרייה תותקן אל';
  @override
  String get pickInstallDirButton => 'בחירת מיקום להתקנה';
  @override
  String get pickInstallDirDialogTitle => 'בחירת התיקייה שאליה תותקן הספרייה';
  @override
  String get installDirUpdatedSnack => 'מיקום ההתקנה עודכן';
  @override
  String get customLocationDialogTitle => 'מיקום שאוצריא אינה מחפשת בו';
  @override
  String customLocationPrompt(String dbPath) => 'המיקום שנבחר:\n$dbPath\n\n'
      'זה אינו מיקום ברירת המחדל של אוצריא, ולכן היא לא תמצא שם את הספרים '
      'בעצמה. אחרי ההתקנה יש לפתוח את אוצריא, ובהגדרות שלה לבחור את מיקום '
      'הספרייה — התיקייה הזו. להמשיך עם המיקום הזה?';
  @override
  String get customLocationConfirm => 'המשך עם המיקום שנבחר';

  @override
  String get localVersionTitle => 'גרסה מקומית';
  @override
  String get targetVersionTitle => 'גרסת היעד בתיקייה המקומית';
  @override
  String get targetVersionNothingDownloaded => 'טרם הורדו עדכונים';
  @override
  String get targetVersionUnknown => 'לא ידועה — יש לבצע בדיקה';

  @override
  String get otzariaRunningTitle => 'אוצריא פתוחה';
  @override
  String get otzariaRunningSubtitle =>
      'יש לסגור את אוצריא לפני החלת עדכון על המסד.';

  @override
  String get updatingProgress => 'מעדכן את המסד...';
  @override
  String get installUpdateButton => 'התקנת העדכון';
  @override
  String get updateDialogTitle => 'עדכון ספריית הספרים';

  @override
  String get reindexTitle => 'אינדקס החיפוש של אוצריא';
  @override
  String get reindexPendingSubtitle =>
      'המסד עודכן מכאן, ולכן החיפוש בספרים שהשתנו עדיין מחזיר את התוכן הישן. '
      'אוצריא תתקן את זה בבקשה אחת.';
  @override
  String get reindexButton => 'עדכון האינדקס';
  @override
  String get reindexDialogTitle => 'עדכון אינדקס החיפוש';
  @override
  String get reindexDialogContent =>
      'אוצריא תיפתח, תטען את הספרייה מחדש ותאנדקס את הספרים שתוכנם השתנה. '
      'האינדוקס רץ בתוך אוצריא ועשוי להימשך, ואפשר להמשיך לעבוד בזמנו. '
      'לפתוח עכשיו?';
  @override
  String get reindexDialogConfirm => 'פתיחת אוצריא';
  @override
  String get reindexRequestedSnack => 'אוצריא תעדכן את אינדקס החיפוש';
  @override
  String reindexFailedSnack(String error) =>
      'לא הצלחנו למסור את הבקשה לאוצריא ($error)';

  @override
  String get fullDownloadInsteadButton => 'התקנת הספרייה המלאה';
  @override
  String get fullDownloadInsteadDialogTitle => 'התקנת הספרייה המלאה';
  @override
  String fullDownloadInsteadPrompt(String size) =>
      'העדכון המצטבר נכשל, והמסד לא נגע. אפשר להתקין במקומו את הספרייה '
      'המלאה מהתיקייה שלצד התוכנה ($size) — פעולה ארוכה שדורשת מקום פנוי, '
      'ואינה דורשת אינטרנט. להתקין עכשיו?';

  @override
  String get sourceCardTitle => 'התיקייה שממנה מעדכנים';
  @override
  String get sourceCardSubtitle =>
      'קבועה, לצד קובץ ההרצה. כשהתוכנה על כונן נייד היא נוסעת איתו, וההחלה '
      'במחשב הלא־מקוון קוראת ממנה ישירות.';
  @override
  String get sourceDirTitle => 'תיקיית עדכוני הספרייה';
  @override
  String get mirrorContentTitle => 'תוכן התיקייה';
  @override
  String get mirrorEmpty => 'ריקה — יש להריץ הורדה בדף הבית';
  @override
  String get mirrorUnreadable => 'לא ניתן לקרוא';
  @override
  String mirrorHasVersion(String version) => 'מכילה גרסה $version';
  @override
  String get mirrorPresent => 'קיימת';
  @override
  String get personalVersionTitle => 'גרסת המסד שלי (עדכון אישי)';
  @override
  String personalVersionRecorded(String version) =>
      'נרשמה גרסה $version — ההורדה תצא ממנה';
  @override
  String get personalVersionMissing =>
      'טרם נרשמה גרסה. יש ללחוץ כאן במחשב שאוצריא שלכם מותקנת בו, לפני ההורדה';
  @override
  String get personalVersionButton => 'זהה את גרסת המסד שלי';
  @override
  String personalVersionCapturedSnack(String version) =>
      'נרשמה גרסה $version לעדכון אישי';
  @override
  String get personalVersionNotFoundSnack =>
      'לא נמצא מסד לקרוא ממנו גרסה במחשב הזה';
  @override
  String get downloadNoteTitle => 'ההורדה האחרונה';
  @override
  String downloadNotePersonal(String version) =>
      'עדכון אישי — קובצי עדכון מגרסה $version ומעלה, בלי המסד המלא';
  @override
  String get downloadNotePersonalUnknownVersion =>
      'עדכון אישי מופעל, אך לא זוהתה גרסת מסד מקומית — הורד המסד המלא. '
      'הפעילו את התוכנה פעם אחת במחשב שבו אוצריא מותקנת.';
  @override
  String downloadNotePersonalUpToDate(String version) =>
      'עדכון אישי — גרסה $version היא האחרונה, אין מה להוריד';
}

class _Settings extends SettingsScreenStrings {
  const _Settings();

  @override
  String get title => 'הגדרות';
  @override
  String get description =>
      'ההורדה תמיד יזומה בלחיצה. ההתקנה מהתיקייה המקומית היא הדבר היחיד '
      'שניתן להפוך לאוטומטי, והיא דורשת אישור חד־פעמי.';

  @override
  String get automationCardTitle => 'אוטומציה';
  @override
  String get automationCardSubtitle =>
      'ברירת המחדל: בדיקה מקומית בלבד, בלי להתקין.';
  @override
  String get autoCheckTitle => 'בדיקת גרסאות בפתיחה';
  @override
  String get autoCheckSubtitle =>
      'משווה את המותקן למה שיש בתיקייה המקומית — בלי רשת';
  @override
  String get autoOnlineCheckTitle => 'בדיקת עדכונים אוטומטית כשיש רשת';
  @override
  String get autoOnlineCheckSubtitle =>
      'בדיקה קלה בפתיחה מול GitHub — בלי הורדה. כשל (אין רשת) נבלע בשקט; '
      'הכפתור הידני בדף הבית עובד בכל מקרה';
  @override
  String get autoInstallAppTitle => 'התקנת תוכנת אוצריא אוטומטית';
  @override
  String get autoInstallAppSubtitle =>
      'מתקין בפתיחה כשיש גרסה חדשה בתיקייה המקומית';
  @override
  String get autoInstallLibraryTitle => 'התקנת עדכון ספרייה אוטומטית';
  @override
  String get autoInstallLibrarySubtitle =>
      'מחיל על המסד בפתיחה; מדולג כשאוצריא פתוחה';

  @override
  String get autoInstallSubjectApp => 'תוכנת אוצריא';
  @override
  String get autoInstallSubjectLibrary => 'הספרייה';
  @override
  String autoInstallDialogTitle(String subject) => 'התקנה אוטומטית של $subject';
  @override
  String autoInstallDialogContent(String subject) =>
      'מעתה $subject תותקן ללא אישור נוסף בכל פעם שתימצא גרסה חדשה בתיקייה '
      'שלצד התוכנה. ההורדה עצמה תישאר יזומה.';
  @override
  String get autoInstallDialogWarning =>
      'התקנה מחליפה קבצים במחשב שלך. אם אינך בטוח/ה — עדיף להשאיר את '
      'האפשרות כבויה ולאשר כל עדכון בנפרד.';
  @override
  String get autoInstallDialogConfirm => 'הפעל התקנה אוטומטית';

  @override
  String get downloadCardTitle => 'הורדה';
  @override
  String get downloadCardSubtitle =>
      'אילו רכיבים כפתור "הורד עכשיו" בדף הבית מביא לתיקייה המקומית. '
      'ההורדה עצמה תמיד יזומה בלחיצה.';
  @override
  String get syncAppTitle => 'תוכנת אוצריא';
  @override
  String get syncAppSubtitle => 'קובץ ההתקנה של הגרסה האחרונה';
  @override
  String get syncLibraryTitle => 'הספרייה';
  @override
  String get syncLibrarySubtitle => 'הרכיב הכבד — המסד המלא הוא כ-1.5GB';
  @override
  String get syncPluginsTitle => 'חנות התוספים';
  @override
  String get syncPluginsSubtitle => 'הקטלוג וקובצי ההתקנה של כל התוספים';

  @override
  String get personalModeTitle => 'עדכון אישי — למחשב שלי בלבד';
  @override
  String get personalModeSubtitle =>
      'מוריד רק את קובצי העדכון מהגרסה שמותקנת אצלך ומעלה, בלי המסד המלא '
      '(~1.5GB). את הגרסה מזהים בלחיצה, במסך הספרייה.';
  @override
  String get personalModeDialogTitle => 'להפעיל עדכון אישי?';
  @override
  String get personalModeDialogContent =>
      'ההורדה תביא רק את קובצי העדכון מהגרסה שמותקנת אצלך ומעלה — עשרות MB '
      'במקום כמה ג\'יגה-בייט.\n\n'
      'התוכנה אינה קוראת את גרסת המסד מעצמה: במסך הספרייה יש ללחוץ על '
      '"זהה את גרסת המסד שלי", וזאת דווקא במחשב שאוצריא שלכם מותקנת בו. '
      'הלחיצה נשמרת על הכונן ונוסעת איתו למחשב המקוון, כך שאוצריא שמותקנת '
      'שם לא תיקבע במקומה.';
  @override
  String get personalModeDialogWarning =>
      'הכונן לא ישמש עוד להתקנה במחשב אחר: המסד המלא יימחק ממנו בהורדה הבאה, '
      'וגם מסלול ההתאוששות (התקנה מלאה כשקובץ עדכון אינו מתאים) לא יהיה זמין.';
  @override
  String get personalModeDialogConfirm => 'הפעל עדכון אישי';

  @override
  String get appearanceCardTitle => 'שפה ומראה';
  @override
  String get appearanceCardSubtitle =>
      'איך התוכנה נראית ובאיזו שפה. משתנה מיד, ונשמר לפעם הבאה.';
  @override
  String get languageTitle => 'שפת הממשק';
  @override
  String get languageSubtitle =>
      'משנה את שפת כל המסכים וההודעות מיד. "אוטומטי" — לפי שפת המחשב.';
  @override
  String get languageSystem => 'אוטומטי';
  @override
  String get languageHebrew => 'עברית';
  @override
  String get languageEnglish => 'English';
  @override
  String get themeTitle => 'ערכת נושא';
  @override
  String get themeSystem => 'מערכת';
  @override
  String get themeLight => 'בהיר';
  @override
  String get themeDark => 'כהה';
  @override
  String get textSizeTitle => 'גודל טקסט';
  @override
  String get textSizeSmall => 'קטן';
  @override
  String get textSizeNormal => 'רגיל';
  @override
  String get textSizeLarge => 'גדול';

  @override
  String get seedColorTitle => 'צבע בסיס';
  @override
  String get seedColorButton => 'שינוי צבע';
  @override
  String get seedColorDialogTitle => 'בחר צבע בסיס';
  @override
  String get seedColorResetButton => 'איפוס';
  @override
  String get seedColorCustom => 'צבע מותאם אישית';
  @override
  String get colorRed => 'אדום';
  @override
  String get colorOrange => 'כתום';
  @override
  String get colorAmber => 'ענבר';
  @override
  String get colorGreen => 'ירוק';
  @override
  String get colorTeal => 'טורקיז';
  @override
  String get colorBlue => 'כחול';
  @override
  String get colorBlueGrey => 'אפור גרפיט';
  @override
  String get colorNavy => 'כחול כהה';
  @override
  String get colorPurple => 'סגול';
  @override
  String get colorBrown => 'חום';
  @override
  String get colorParchment => 'פרגמנט / בז\'';
  @override
  String get colorGrey => 'אפור';
  @override
  String get colorDarkBrown => 'חום זהבהב';

  @override
  String get supportCardTitle => 'תמיכה';
  @override
  String get logTitle => 'יומן הפעילות';
  @override
  String get logSubtitle => 'כל הבדיקות, ההורדות וההתקנות נרשמות מקומית בלבד';
  @override
  String get openLogFolderButton => 'פתיחת תיקיית הלוגים';

  @override
  String get resetTitle => 'איפוס ההגדרות';
  @override
  String get resetSubtitle =>
      'מחזיר את כל ההגדרות לברירת המחדל, בלי למחוק התקנות';
  @override
  String get resetButton => 'איפוס';
  @override
  String get resetDialogTitle => 'איפוס ההגדרות';
  @override
  String get resetDialogContent => 'כל ההגדרות יחזרו לברירת המחדל.';
  @override
  String get resetDialogWarning =>
      'ההתקנות עצמן, המסד, התוספים והעדכונים שהורדו לא יימחקו.';
  @override
  String get resetDialogConfirm => 'אפס הגדרות';
  @override
  String get resetDoneSnack => 'ההגדרות אופסו';
}

class _Plugins extends PluginsStrings {
  const _Plugins();

  @override
  String get syncDialogTitle => 'סנכרון חנות התוספים';
  @override
  String get syncDialogContent =>
      'הפעולה תוריד מ-otzaria.org את רשימת התוספים, הקטגוריות, התמונות '
      'וקובצי ההתקנה אל תיקיית ההעברה. דורשת אינטרנט, ומרגע שהסתיימה החנות '
      'עובדת גם במחשב שאין בו אינטרנט.';
  @override
  String get syncDialogConfirm => 'סנכרן';
  @override
  String get syncFailedSnack => 'הסנכרון נכשל';
  @override
  String syncDoneSnack(int count) => 'הסנכרון הושלם — $count תוספים בחנות';
  @override
  String syncDoneWithWarningsSnack(int count) =>
      'הסנכרון הסתיים, אך $count פריטים לא ירדו. הפרטים ביומן.';
  @override
  String get syncButton => 'סנכרון מהאתר';
  @override
  String get reloadTooltip => 'טעינה מחדש מהתיקייה המקומית';
  @override
  String get syncingOverlayTitle => 'מסנכרן את חנות התוספים';
  @override
  String get syncingOverlayStarting => 'מתחיל...';
  @override
  String get syncNeverRan => 'טרם בוצע סנכרון';
  @override
  String syncedAt(String time) => 'סונכרן לאחרונה: $time';
  @override
  String get syncDirUnknownTooltip => 'התיקייה תיקבע בסנכרון הראשון';
  @override
  String updatesAvailableChip(int count) => '$count עדכונים זמינים';
  @override
  String get updatesChipTooltip => 'הצגת התוספים שממתינים לעדכון';

  @override
  String get saveDialogTitle => 'שמירת התוסף';
  @override
  String get saveDoneSnack => 'הקובץ נשמר';
  @override
  String get saveFailedSnack => 'שמירת הקובץ נכשלה';
  @override
  String installOpenedSnack(String pluginName) =>
      'אוצריא נפתחה כדי להשלים את התקנת $pluginName';
  @override
  String get installFailedSnack => 'ההתקנה נכשלה';

  @override
  String get loadingCatalog => 'טוען את קטלוג התוספים...';
  @override
  String get catalogTitleFallback => 'חנות התוספים של אוצריא';
  @override
  String get catalogSubtitleFallback =>
      'תוספים שמרחיבים את חוויית הלימוד באוצריא';
  @override
  String get heroSearchHint => 'חפשו תוסף לפי שם, תיאור או נושא...';
  @override
  String get heroSearchButton => 'חיפוש';

  @override
  String get emptyStoreTitle => 'החנות בבנייה — אבל התוספים כבר כאן';
  @override
  String get emptyStoreBody =>
      'בקרוב יופיעו כאן תוספים נבחרים וקטגוריות מסודרות. בינתיים אפשר לחפש '
      'למעלה או לעיין ברשימה המלאה של כל התוספים.';
  @override
  String allPluginsWithCount(int count) => 'לכל התוספים ($count)';
  @override
  String get browseAllPrompt => 'לא מצאתם את מה שחיפשתם?';
  @override
  String browseAllButton(int count) => 'עיינו בכל התוספים ($count)';

  @override
  String get featuredEyebrow => 'מומלצי החנות';
  @override
  String get featuredTitle => 'תוספים נבחרים';
  @override
  String get showMoreFeatured => 'הצג עוד נבחרים';
  @override
  String categoryLinkButton(int count) => 'לכל הקטגוריה ($count)';

  @override
  String get breadcrumbRoot => 'חנות התוספים';
  @override
  String get allPluginsPage => 'כל התוספים';
  @override
  String get listEyebrow => 'רשימת תוספים';
  @override
  String get listTitle => 'בחרו את התוסף שמתאים לכם';
  @override
  String get summaryNoResults => 'לא נמצאו תוספים לפי הסינון שבחרתם';
  @override
  String get summaryAllShown => 'כל התוספים מוצגים';
  @override
  String summaryPartial(int shown, int total) =>
      'מוצגים $shown מתוך $total תוספים';
  @override
  String get categoryOnePlugin => 'תוסף אחד בקטגוריה';
  @override
  String categoryPluginCount(int count) => '$count תוספים בקטגוריה';

  @override
  String get hideInstalledLabel => 'רק מה שלא מותקן';
  @override
  String hideInstalledOnTooltip(int installedCount) =>
      'מוצגים רק תוספים שאינם מותקנים או שיש להם עדכון.\n'
      'זוהו $installedCount תוספים מותקנים באוצריא.';
  @override
  String hideInstalledOffTooltip(int installedCount) =>
      'מוצגים כל התוספים, כולל המותקנים והמעודכנים.\n'
      'זוהו $installedCount תוספים מותקנים באוצריא.';

  @override
  String get neverSyncedTitle => 'עדיין לא סונכרנו תוספים';
  @override
  String get neverSyncedBody =>
      'לחצו על "סנכרון מהאתר" במחשב שיש בו אינטרנט כדי לטעון את רשימת '
      'התוספים העדכנית מ-otzaria.org.';
  @override
  String get noResultsTitle => 'לא נמצאו תוספים לפי הסינון שבחרתם';
  @override
  String get noResultsBody =>
      'נסו לחפש בשם אחר, להסיר תגית, לבחור סטטוס שונה, או לכבות את '
      '"הצג רק מה שלא מותקן".';
  @override
  String get allInstalledTitle => 'הכול מותקן ומעודכן';
  @override
  String get allInstalledBody =>
      'המתג "רק מה שלא מותקן" מסתיר תוספים שכבר מותקנים אצלכם בגרסה '
      'העדכנית. כבו אותו כדי לראות גם אותם.';
  @override
  String get showInstalledButton => 'הצג גם את המותקנים';
  @override
  String get emptyCategoryTitle => 'בקרוב יתווספו תוספים לקטגוריה זו';
  @override
  String get emptyCategoryBody =>
      'בינתיים אפשר לעיין ברשימה המלאה של כל התוספים בחנות.';
  @override
  String get allPluginsButton => 'לכל התוספים';

  @override
  String get filterSearchLabel => 'חיפוש';
  @override
  String get filterSearchHint => 'שם, תיאור או תגית...';
  @override
  String get filterStatusLabel => 'סטטוס';
  @override
  String get filterTagsLabel => 'תגיות';
  @override
  String get filterAllTags => 'כל התגיות';
  @override
  String get filterStatusAll => 'הכול';
  @override
  String get showMoreTags => 'הצג עוד';
  @override
  String get showFewerTags => 'הצג פחות';

  @override
  String get badgeFeaturedShort => 'נבחר';
  @override
  String get badgeFeatured => 'תוסף נבחר';
  @override
  String pluginVersionBadge(String version) => 'גרסה $version';
  @override
  String downloadsBadge(int count) => '$count הורדות';
  @override
  String get saveButton => 'שמירה';
  @override
  String get installButton => 'התקנה';
  @override
  String get directInstallButton => 'התקנה ישירה לאוצריא';
  @override
  String get sourcePageButton => 'עמוד המקור';
  @override
  String get cardDetailsLink => 'לפרטים מלאים';
  @override
  String cardUpdatedOn(String date) => 'עודכן ב־$date';
  @override
  String get backToStore => 'חזרה לחנות';

  @override
  String get statusStable => 'יציב';
  @override
  String get statusBeta => 'בטא';
  @override
  String get statusExperimental => 'ניסיוני';
  @override
  String get statusUnknown => 'לא ידוע';

  @override
  String get installChipInstalled => 'מותקן';
  @override
  String get installChipUpdateAvailable => 'עדכון זמין';
  @override
  String installChipUpdateFrom(String installedVersion) =>
      'עדכון זמין (מותקן $installedVersion)';

  @override
  String get infoPanelTitle => 'מידע כללי';
  @override
  String get tagsPanelTitle => 'תגיות';
  @override
  String get screenshotsPanelTitle => 'צילומי מסך';
  @override
  String get infoVersion => 'גרסה';
  @override
  String get infoStatus => 'סטטוס';
  @override
  String get infoAuthor => 'מפתח';
  @override
  String get infoUpdated => 'עודכן';
  @override
  String get infoNetwork => 'חיבור אינטרנט בזמן שימוש';
  @override
  String get infoNetworkRequired => 'נדרש';
  @override
  String get infoNetworkNotRequired => 'לא נדרש';
  @override
  String get infoCompatibility => 'תאימות';
  @override
  String compatibilityRange(String from, String to) => '$from — עד $to';
  @override
  String get infoLocalFile => 'קובץ התוסף במראה';
  @override
  String get infoLocalFileMissing => 'טרם ירד — יש לבצע סנכרון';
  @override
  String localFileDescription(String fileName, String size) =>
      '$fileName ($size)';
  @override
  String get valueUnspecifiedFeminine => 'לא צוינה';
  @override
  String get valueUnspecifiedMasculine => 'לא צוין';
  @override
  String get sizeUnknown => 'גודל לא ידוע';

  @override
  String get categoriesTitle => 'קטגוריות';
  @override
  String get storeHomeItem => 'דף הבית של החנות';
  @override
  String get storeHomeChip => 'דף הבית';

  @override
  String updatesDialogTitle(int count) => 'יש עדכונים זמינים ($count)';
  @override
  String get updatesDialogIntro =>
      'התוספים הבאים מותקנים אצלך באוצריא בגרסה ישנה מזו שבחנות:';
  @override
  String updatesDialogRow(String installedVersion, String storeVersion) =>
      'מותקן $installedVersion ← בחנות $storeVersion';
  @override
  String get updatesDialogUpdateButton => 'עדכון';
  @override
  String updatesDialogUpdateAllButton(int count) => 'עדכון הכל ($count)';
  @override
  String get updatesDialogDetailsButton => 'לפרטים';
  @override
  String get updatesDialogSentLabel => 'נשלח לאוצריא';
  @override
  String get updatesDialogDoneLabel => 'עודכן';
  @override
  String get updatesDialogManualOnly => 'התקנה מדף התוסף';
  @override
  String get updatesDialogPendingNote =>
      'ההתקנה עצמה מתבצעת בחלון של אוצריא. לאחר שתסתיים שם, לחצו '
      '"בדיקה מחדש" כדי לראות מה כבר עודכן.';
  @override
  String get updatesDialogRecheckButton => 'בדיקה מחדש';

  @override
  String get screenshotPrevious => 'הקודם';
  @override
  String get screenshotNext => 'הבא';
}

class _SetupError extends SetupErrorStrings {
  const _SetupError();

  @override
  String get title => 'התוכנה נמצאת במקום שאינו מתאים';
  @override
  String get explanation =>
      'הלאנצ׳ר שומר את כל הנתונים — הספרייה, התוספים וגרסת אוצריא — בתיקייה '
      'שצמודה לו, כדי שהכול ייסע יחד על הכונן. בתיקייה הנוכחית אין הרשאת '
      'כתיבה, ולכן אין לאן לשמור.';
  @override
  String get whatToDo =>
      'מה לעשות: להעביר את תיקיית התוכנה כולה לכונן הנייד (או לכל תיקייה '
      'בדיסק שאינה תחת Program Files), ולהפעיל אותה משם.';
  @override
  String get attemptedDirTitle => 'התיקייה שנוסתה';
  @override
  String get copyPathButton => 'העתקת הנתיב';
  @override
  String get pathCopiedSnack => 'הנתיב הועתק';
  @override
  String cannotWriteToDataDir(String osMessage) =>
      'לא ניתן לכתוב לתיקייה שלצד התוכנה: $osMessage';
}

class _LauncherUpdate extends LauncherUpdateStrings {
  const _LauncherUpdate();

  @override
  String get cardTitle => 'עדכון התוכנה הזאת';
  @override
  String get cardSubtitle =>
      'עדכוני אוצריא עצמה. העדכון מחליף אך ורק את התוכנה — הנתונים, ההגדרות '
      'והתיקייה שלצידה נשארים כמו שהם.';
  @override
  String installedVersion(String version) => 'הגרסה המותקנת: $version';
  @override
  String downloadedVersion(String version) => 'הגרסה שהורדה: $version';
  @override
  String onlineVersion(String version) => 'הגרסה שברשת: $version';

  @override
  String get statusUpToDate => 'התוכנה מעודכנת';
  @override
  String get statusUpdateAvailable => 'יש גרסה חדשה להורדה';
  @override
  String get statusReadyToInstall => 'מוכן להתקנה';
  @override
  String get statusDownloading => 'מוריד את הגרסה החדשה';
  @override
  String get statusInstalling => 'מתקין את הגרסה החדשה';

  @override
  String get downloadButton => 'הורדת הגרסה החדשה';
  @override
  String get installButton => 'התקנה והפעלה מחדש';

  @override
  String get availableDialogTitle => 'עדכון לעדכוני אוצריא';
  @override
  String availableDialogContent(String version) =>
      'גרסה $version של עדכוני אוצריא זמינה, להוריד עכשיו?';
  @override
  String availableDialogDetail(String size) =>
      'גודל ההורדה: $size. הקובץ נשמר בתיקייה שלצד התוכנה, וההתקנה עצמה '
      "נעשית מתוך הלאנצ'ר — גם במחשב בלי אינטרנט.";
  @override
  String get availableDialogConfirm => 'להוריד עכשיו';
  @override
  String get availableDialogCancel => 'לא עכשיו';

  @override
  String get readyDialogTitle => 'הגרסה החדשה מוכנה';
  @override
  String readyDialogContent(String version) =>
      'גרסה $version הורדה. להתקין אותה עכשיו? התוכנה תיסגר ותיפתח מחדש '
      'בגרסה החדשה, באותו מיקום בדיוק, והנתונים וההגדרות יישארו כמו שהם.';
  @override
  String get readyDialogConfirm => 'התקנה והפעלה מחדש';

  @override
  String downloadedSnack(String version) =>
      'גרסה $version ירדה לתיקייה שלצד התוכנה';
  @override
  String get installingSnack => 'הגרסה החדשה מותקנת — התוכנה תיפתח מחדש מיד';
  @override
  String get manualRestartNotice =>
      'הגרסה החדשה הוחלפה. יש לסגור את התוכנה ולפתוח אותה מחדש כדי לעבוד '
      'איתה.';

  @override
  String get versionTileTitle => 'גרסת התוכנה';

  @override
  String get executableNotFound =>
      'לא ניתן לאתר את קובץ ההרצה שממנו התוכנה פועלת, ולכן אין מה להחליף. '
      'יש להוריד את הגרסה החדשה ולהחליף את הקובץ ידנית.';
  @override
  String get mirrorMissing =>
      'הגרסה החדשה עדיין לא הורדה לתיקייה שלצד התוכנה — יש להריץ הורדה '
      'במחשב עם אינטרנט.';
  @override
  String unsupportedPlatform(String operatingSystem) =>
      'עדכון עצמי של התוכנה נתמך ב-Windows וב-macOS בלבד '
      '(זוהה: $operatingSystem).';
  @override
  String downloadFailed(int statusCode) =>
      'הורדת הגרסה החדשה נכשלה: סטטוס $statusCode';
  @override
  String sizeMismatch(int received, int expected) =>
      'הקובץ שהורד לא בגודל הצפוי (התקבלו $received בתים, צפוי $expected) — '
      'כנראה שההורדה נקטעה.';
  @override
  String replaceFailed(String error) =>
      'החלפת קובץ ההרצה נכשלה: $error. הקובץ הקודם הוחזר למקומו.';
  @override
  String restartFailed(String error) =>
      'הפעלת הגרסה החדשה נכשלה: $error. יש לסגור את התוכנה ולהפעיל אותה '
      'מחדש ידנית — ההחלפה עצמה כבר הושלמה.';
}

class _Units extends UnitStrings {
  const _Units();

  @override
  String bytes(int count) => '$count בייט';
  @override
  String progressOf(String received, String total) => '$received מתוך $total';
  @override
  String kilobytes(String amount) => '$amount ק״ב';
  @override
  String megabytes(String amount) => '$amount מ״ב';
  @override
  String gigabytes(String amount) => '$amount ג״ב';
}

class _LibraryDomain extends LibraryDomainStrings {
  const _LibraryDomain();

  @override
  String unsupportedPatchCompression(String compression) =>
      'דחיסה לא נתמכת ב-patch: $compression';
  @override
  String get manifestMissingPatchFiles =>
      'שדה חובה חסר או ריק ב-manifest: patchFiles';
  @override
  String manifestMissingField(String key) =>
      'שדה חובה חסר או לא תקין ב-manifest: $key';
  @override
  String releasesRequestFailed(int statusCode) =>
      'שגיאה בקבלת רשימת ה-releases: $statusCode';
  @override
  String get releasesResponseNotList => 'תשובת ה-releases מ-GitHub אינה רשימה';
  @override
  String manifestDownloadFailed(String url, int statusCode) =>
      'שגיאה בהורדת manifest ($url): $statusCode';
  @override
  String manifestNotJsonObject(String url) =>
      'manifest אינו אובייקט JSON תקין: $url';

  @override
  String get interruptedUpdateFound =>
      'נמצא סימון עדכון שלא הושלם — יש לוודא תקינות ה-DB';

  @override
  String get exportLoadingReleases => 'טוען רשימת גרסאות מ-GitHub';
  @override
  String get exportNoReleases => 'לא נמצאו releases עם עדכוני DB להורדה.';
  @override
  String exportPersonalFrom(int localVersion) =>
      'עדכון אישי: מוריד קובצי עדכון מגרסה $localVersion ומעלה, בלי המסד המלא';
  @override
  String exportPersonalUpToDate(int localVersion) =>
      'אין גרסה חדשה מ-$localVersion — לא הורד דבר';
  @override
  String get exportPersonalVersionUnknown =>
      'לא זוהתה גרסת מסד מקומית — מוריד את המסד המלא';
  @override
  String exportDownloading(String tag, String asset) => 'מוריד $tag / $asset';
  @override
  String exportVerifying(String tag, String asset) => 'מאמת $tag / $asset';
  @override
  String exportWritingManifest(String fileName) => 'כותב $fileName';
  @override
  String get exportDone => 'הושלם';
  @override
  String get exportCancelled => 'הייצוא בוטל';
  @override
  String get exporterDoesNotExtract =>
      'LibraryMirrorExporter מוריד קבצים בלבד ואינו מחלץ אותם';

  @override
  String get planLocalVersionUnknown =>
      'גרסת ה-DB המקומי אינה ידועה (חסר schema_meta.db_version)';
  @override
  String planContentChangedWithoutVersionBump(String releaseTag) =>
      'תוכן המסד עודכן ב-$releaseTag ללא שינוי מספר הגרסה';
  @override
  String planNoDeltaRoute(int localVersion, int latestVersion) =>
      'אין מסלול דלתא רציף מגרסה $localVersion לגרסה $latestVersion';
  @override
  String planNoFullDbEither(String reason) =>
      '$reason, ואין DB מלא זמין להורדה';

  @override
  String mirrorManifestMissing(String fileName, String mirrorDir) =>
      'לא נמצא קובץ $fileName בתיקייה: $mirrorDir — ודא/י שזו תיקיית מראה '
      'תקינה שנוצרה דרך "הכנת עדכון להעברה".';
  @override
  String mirrorManifestCorrupt(
    String fileName,
    String mirrorDir,
    String error,
  ) =>
      'קובץ $fileName בתיקייה $mirrorDir פגום: $error';
  @override
  String mirrorManifestUnexpectedShape(String fileName, String mirrorDir) =>
      'קובץ $fileName בתיקייה $mirrorDir אינו בפורמט הצפוי.';
  @override
  String mirrorPatchManifestMissing(String url) =>
      'קובץ manifest חסר במראה המקומית: $url';
  @override
  String mirrorPatchManifestCorrupt(String url, String error) =>
      'קובץ manifest פגום ($url): $error';
  @override
  String mirrorPatchManifestNotJson(String url) =>
      'manifest אינו אובייקט JSON תקין: $url';

  @override
  String unsupportedSchemaForHashOrder(int schemaVersion) =>
      'גרסת סכמה $schemaVersion אינה נתמכת לבחירת סדר hash';
  @override
  String localVersionMismatch(int? localVersion, int expected) =>
      'גרסת ה-DB המקומי ($localVersion) אינה תואמת ל-patch (מצפה ל-$expected)';
  @override
  String localSchemaMismatch(int localSchema, int expected) =>
      'סכמת ה-DB המקומי ($localSchema) אינה תואמת ל-patch (מצפה ל-$expected)';
  @override
  String get contentHashMismatchNeedsFullDownload =>
      'ה-DB המקומי שונה מהצפוי — hash לא תואם ל-fromContentHash. '
      'נדרשת הורדה מלאה.';
  @override
  String patchUniqueConflictNeedsFullDownload(String table, String detail) =>
      'ה-patch אינו מתאים למסד שעל המחשב: התנגשות ערך ייחודי בטבלה "$table". '
      'העדכון המצטבר בוטל והמסד לא נגע. נדרשת הורדה מלאה של הספרייה. '
      '($detail)';
  @override
  String foreignKeyViolationsGrew(int before, int after) =>
      'מספר הפרות מפתח זר גדל ($before→$after) — ה-patch אינו תקין';
  @override
  String resultHashMismatch(String actual, String expected) =>
      'ה-hash אחרי apply ($actual) אינו תואם ל-toContentHash ($expected)';
  @override
  String get patchMetaSchemaVersionMissing =>
      'patch_meta.schema_version חסר ב-patch';
  @override
  String patchSchemaTooNew(int schemaVersion, int supported) =>
      'גרסת סכמת ה-patch ($schemaVersion) חדשה מהנתמך ($supported) — '
      'נדרש עדכון תוכנה';
  @override
  String patchVersionRangeMismatch(
    int? from,
    int? to,
    int manifestFrom,
    int manifestTo,
  ) =>
      'גרסאות ה-patch ($from→$to) אינן תואמות ל-manifest '
      '($manifestFrom→$manifestTo)';

  @override
  String get compressedFileSizeLabel => 'גודל הקובץ הדחוס';
  @override
  String get compressedFileHashLabel => 'sha256 של הקובץ הדחוס';
  @override
  String get extractedFileSizeLabel => 'גודל הקובץ המחולץ';
  @override
  String get extractedFileHashLabel => 'sha256 של הקובץ המחולץ';
  @override
  String get patchExtractionFailed => 'חילוץ ה-patch נכשל או החזיר ריק';
  @override
  String get deleteExistingWithoutResumeIdentityFailed =>
      'מחיקת קובץ קיים ללא זהות resume נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialFromPreviousVersionFailed =>
      'מחיקת קובץ חלקי מגרסה קודמת נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialWithoutValidatorFailed =>
      'מחיקת קובץ חלקי ללא validator נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialFromPreviousRepresentationFailed =>
      'מחיקת קובץ חלקי מייצוג קודם נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String get deletePartialBeforeRetryFailed =>
      'מחיקת קובץ חלקי לפני ניסיון חוזר נכשלה — לא ניתן להמשיך בהורדה';
  @override
  String fullDbSizeMismatch(int downloaded, int expected) =>
      'גודל ה-DB שהורד ($downloaded) אינו תואם לצפוי ($expected)';
  @override
  String get fullDbHashMismatch => 'sha256 של ה-DB המלא אינו תואם';
  @override
  String resumeRoundLimit(int maxRounds, String url) =>
      'חידוש ההורדה חרג ממספר הסבבים המרבי ($maxRounds): $url';
  @override
  String contentLengthMismatch(int responseLength, int expectedSize) =>
      'Content-Length של ההורדה ($responseLength) אינו תואם לגודל הצפוי '
      '($expectedSize)';
  @override
  String truncatedBody(int declared, int received) =>
      'גוף ההורדה נקטע: Content-Length הצהיר $declared בייטים, '
      'אך התקבלו $received';
  @override
  String downloadHttpError(int statusCode, String url) =>
      'שגיאה בהורדה ($statusCode): $url';
  @override
  String resumeMadeNoProgress(String url) => 'חידוש ההורדה לא התקדם: $url';
  @override
  String resumeFailedAfterRetry(String url) =>
      'חידוש ההורדה נכשל לאחר ניסיון חוזר: $url';
  @override
  String downloadExceedsExpectedSize(int expectedSize) =>
      'ההורדה חורגת מהגודל הצפוי ($expectedSize בייטים)';
  @override
  String saveDownloadedFileFailed(String error) =>
      'שמירת הקובץ שהורד לדיסק נכשלה: $error';
  @override
  String tooManyRedirects(String url) => 'יותר מדי הפניות (redirects): $url';
  @override
  String writeResumeSidecarFailed(String path, String error) =>
      'כתיבת קובץ הזהות להמשך ההורדה נכשלה ($path): $error';
  @override
  String checksumMismatchDetailed(
    String label,
    String expected,
    String actual,
  ) =>
      '$label אינו תואם: צפוי $expected, התקבל $actual';
  @override
  String checksumMismatch(String label) => '$label אינו תואם';
  @override
  String localFileNotFound(String path) => 'קובץ מקומי לא נמצא: $path';
  @override
  String localFileTooLarge(int maxBytes, String path) =>
      'הקובץ המקומי חורג מהגודל הצפוי ($maxBytes בייטים): $path';
  @override
  String localSourceNotFound(String url) => 'קובץ מקור מקומי לא נמצא: $url';
  @override
  String localFileSizeMismatch(int expected, int actual, String url) =>
      'גודל הקובץ המקומי אינו תואם: צפוי $expected, בפועל $actual ($url)';
  @override
  String localFileHashMismatch(String url) =>
      'sha256 של הקובץ המקומי אינו תואם: $url';

  @override
  String get mirrorMissing =>
      'עדיין לא הורדו עדכוני ספרייה לתיקייה המקומית — יש להריץ הורדה במחשב '
      'עם חיבור לאינטרנט.';
  @override
  String interruptedUpdateNeedsManualFix(String detail) =>
      '$detail — quick_check נכשל בפועל, נדרשת התערבות ידנית '
      '(שחזור מגיבוי חיצוני).';
  @override
  String get interruptedUpdateDefaultDetail => 'עדכון DB שנקטע';
  @override
  String get blockedNeedsManualAction => 'מצב חסום — נדרשת פעולה ידנית';
  @override
  String get blockedNeedsManualActionWithPeriod =>
      'מצב חסום — נדרשת פעולה ידנית.';
  @override
  String patchUrlMissing(String fileName) => 'לא נמצא URL להורדת $fileName';
  @override
  String get fullDbAssetMissingFromPlan => 'לא נמצא נכס DB מלא בתוכנית';
  @override
  String get fullDbExtractionFailed => 'חילוץ ה-DB המלא נכשל או החזיר ריק';
  @override
  String versionMismatchAfterWrite(int? actual, int? expected) =>
      'אחרי כתיבת ה-DB המלא, הגרסה שנקראה ($actual) לא תואמת ליעד '
      '($expected) — בוצע שחזור.';
  @override
  String get updateCancelled => 'העדכון בוטל';
  @override
  String get otzariaIsRunning =>
      'אוצריא פתוחה כרגע — יש לסגור אותה לפני עדכון המסד, כדי למנוע נעילת '
      'קובץ.';
  @override
  String get zstdContextCreationFailed => 'יצירת הקשר החילוץ (DCtx) נכשלה';
  @override
  String zstdDecompressionFailed(String errorName) =>
      'חילוץ ה-zstd נכשל: $errorName';
  @override
  String get zstdEmptyInput => 'הקובץ הדחוס ריק';
  @override
  String get zstdTruncatedFrame => 'הקובץ הדחוס נקטע — ה-frame לא הושלם';

  @override
  String dbIntegrityCheckFailed(String result) =>
      'בדיקת התקינות של המסד שהורד נכשלה: $result';

  @override
  String get companionTalmudName => 'תלמוד בבלי';
  @override
  String get companionCatalogName => 'קטלוג אוצר החכמה והיברובוקס';
  @override
  String get companionDictionaryName => 'מילון החיפוש המקורב';
  @override
  String companionChecking(String name) => 'בודק $name...';
  @override
  String companionDownloading(String name) => 'מוריד $name...';
  @override
  String companionInstalling(String name) => 'מתקין $name...';
  @override
  String companionAssetMissingInRelease(String name) =>
      'לא נמצא קובץ של $name ב-release האחרון';
  @override
  String companionExtractionFailed(String name) => 'חילוץ $name נכשל';
  @override
  String get companionsMirrorMissing =>
      'הקבצים הנלווים טרם הורדו לתיקייה המקומית';

  @override
  String applyDownloadingPatch(String step) => 'מוריד עדכון$step...';
  @override
  String applyApplyingPatch(String step) => 'מחיל עדכון על המסד$step...';
  @override
  String applyPatchStage(String stage, String step) {
    switch (stage) {
      case 'preflight':
        return 'בודק תאימות$step...';
      case 'verifyFromHash':
        return 'מאמת את המסד הקיים$step...';
      case 'attach':
        return 'פותח את קובץ העדכון$step...';
      case 'migrations':
        return 'מעדכן את מבנה המסד$step...';
      case 'upserts':
        return 'כותב את השינויים$step...';
      case 'deletes':
        return 'מסיר רשומות שנמחקו$step...';
      case 'foreignKeyCheck':
        return 'בודק תקינות קישורים$step...';
      case 'verifyToHash':
        return 'מאמת את תוצאת העדכון$step...';
      case 'commit':
        return 'שומר את השינויים$step...';
      default:
        return applyApplyingPatch(step);
    }
  }

  @override
  String get applyDownloadingFullDb => 'מוריד מסד מלא...';
  @override
  String get applyDecompressingFullDb => 'מחלץ את המסד...';
  @override
  String get applyWritingFullDb => 'כותב את המסד...';
  @override
  String get applyVerifying => 'מוודא תקינות...';
  @override
  String get applyInstallingCompanions => 'מתקין קבצים נלווים...';
  @override
  String get applyDone => 'הושלם.';
}

class _AppDomain extends AppDomainStrings {
  const _AppDomain();

  @override
  String get channelStable => 'יציבה';
  @override
  String get channelPrerelease => 'לא יציבה';
  @override
  String downloadingChannel(String channelLabel) =>
      'מוריד את תוכנת אוצריא (גרסה $channelLabel)...';

  @override
  String get noInstallableReleaseForPlatform =>
      'לא נמצאה גרסת אוצריא שניתן להתקין בפלטפורמה הזו.';
  @override
  String get mirrorEmptyRunDownload =>
      'אין גרסת אוצריא בתיקייה המקומית — יש להריץ הורדה במחשב עם אינטרנט.';
  @override
  String get noOtzariaInstallFound =>
      'לא נמצאה התקנה של אוצריא במחשב — יש להתקין אותה, או לבחור את תיקיית '
      'ההתקנה הקיימת.';
  @override
  String get corruptReleaseMetadata => 'מטא־דאטה פגומה של גרסת אוצריא';
  @override
  String unsupportedPlatform(String operatingSystem) =>
      "הלאנצ'ר תומך בהתקנת אוצריא ב-Windows וב-macOS בלבד "
      '(זוהה: $operatingSystem).';
  @override
  String noAssetForPlatform(
    String tagName,
    String platform,
    List<String> expectedSuffixes,
  ) {
    final suffixes = expectedSuffixes.map((s) => '"$s"').join(' או ');
    return 'ל-release "$tagName" אין קובץ התקנה מתאים ל-$platform '
        '(מצפים לשם שמסתיים ב-$suffixes).';
  }

  @override
  String installerDownloadFailed(int statusCode) =>
      'הורדת קובץ ההתקנה נכשלה: סטטוס $statusCode';
  @override
  String installerSizeMismatch(int received, int expected) =>
      'קובץ ההתקנה שהורד לא בגודל הצפוי (התקבלו $received בתים, '
      'צפוי $expected) — כנראה שהורדה נקטעה.';
  @override
  String installerExitCode(int exitCode, String output) =>
      'ריצת ה-installer החזירה קוד יציאה $exitCode.\n$output';
  @override
  String get macAppNotFoundInArchive =>
      'לא נמצאה חבילת .app בתוך חבילת ההתקנה שחולצה — ייתכן שמבנה האסט של '
      'אוצריא ל-macOS השתנה.';
  @override
  String macReplaceFailed(String error) =>
      'החלפת חבילת ה-.app בתיקיית ההתקנה נכשלה: $error';
  @override
  String dittoExtractFailed(int exitCode, String output) =>
      'חילוץ חבילת ההתקנה (ditto) נכשל בקוד $exitCode.\n$output';
  @override
  String hdiutilAttachFailed(int exitCode, String output) =>
      'הרכבת דמות הדיסק (hdiutil attach) נכשלה בקוד $exitCode.\n$output';
  @override
  String get macAppNotFoundInDmg =>
      'לא נמצאה חבילת .app בתוך דמות הדיסק שהורכבה.';
  @override
  String dittoCopyFailed(int exitCode, String output) =>
      'העתקת ה-.app מדמות הדיסק (ditto) נכשלה בקוד $exitCode.\n$output';
  @override
  String installNotDetected(String installDir, int timeoutSeconds) =>
      'לא נמצאה התקנה של אוצריא בתוך $installDir תוך $timeoutSeconds שניות '
      'מסיום ה-installer. ייתכן שההתקנה עדיין רצה ברקע, או שנתיב ההתקנה '
      'השתנה בגרסה חדשה של ה-installer.';
  @override
  String launchFileMissing(String launchPath) =>
      'קובץ ההפעלה לא נמצא בנתיב: $launchPath';
  @override
  String launchFailed(int exitCode, String stderr) =>
      'הפעלת אוצריא נכשלה (open החזיר $exitCode): $stderr';
  @override
  String githubStatus(int statusCode, String uri) =>
      'GitHub API החזיר סטטוס $statusCode עבור $uri';
  @override
  String noReleasesAtAll(String repo) => 'לא נמצאו releases בכלל ב-$repo.';
  @override
  String get windowsOnlyReader => 'WindowsExeVersionReader עובד רק בווינדוס.';
  @override
  String get macOnlyReader => 'MacAppVersionReader עובד רק ב-macOS.';
}

class _PluginsDomain extends PluginsDomainStrings {
  const _PluginsDomain();

  @override
  String get fileNotAvailableSyncFirst =>
      'הקובץ אינו זמין באופן מקומי. יש לבצע סנכרון קודם.';
  @override
  String saveFailed(String error) => 'שמירת הקובץ נכשלה: $error';
  @override
  String get pluginFileNotAvailable =>
      'קובץ התוסף אינו זמין. יש לבצע סנכרון קודם.';
  @override
  String get localPluginFileMissing =>
      'קובץ התוסף המקומי חסר. יש לבצע סנכרון מחדש.';
  @override
  String get badPluginExtension => 'קובץ התוסף אינו בסיומת otzplugin תקינה.';
  @override
  String get otzariaOpenFailedHint =>
      'פתיחת אוצריא נכשלה. ודא שאוצריא מותקנת במחשב זה. ';
  @override
  String otzariaOpenFailed(String error) => 'פתיחת אוצריא נכשלה: $error';
  @override
  String get directInstallUnsupportedPlatform =>
      'התקנה ישירה נתמכת ב-Windows וב-macOS בלבד.';

  @override
  String get syncLoadingCatalog => 'טוען את רשימת התוספים מהאתר...';
  @override
  String syncPlugin(String name, int done, int total) =>
      'מסנכרן: $name ($done/$total)';
  @override
  String get syncDone => 'הסנכרון הושלם';
  @override
  String get syncCategories => 'מסנכרן את קטגוריות החנות...';
  @override
  String syncStructureFailed(String error) =>
      'לא ניתן לטעון את מבנה החנות מהאתר ($error) — נשמר המבנה הקודם';
  @override
  String get syncStructureEmpty => 'האתר לא החזיר קטגוריות';
  @override
  String get syncEmptyCatalogRejected =>
      'האתר החזיר רשימת תוספים ריקה — החנות שכבר ירדה נשמרה כמות שהיא. '
      'כדאי לנסות שוב מאוחר יותר.';
  @override
  String syncCategoryFailed(String name, String error) =>
      'לא ניתן לטעון את הקטגוריה $name: $error';
  @override
  String syncImageFailed(String name, String error) =>
      'לא ניתן להוריד תמונה עבור $name: $error';
  @override
  String syncScreenshotFailed(String name, String error) =>
      'לא ניתן להוריד צילום מסך עבור $name: $error';
  @override
  String syncPluginFileFailed(String name, String error) =>
      'לא ניתן להוריד את קובץ התוסף $name: $error';

  @override
  String get whatPluginList => 'רשימת התוספים';
  @override
  String get whatStoreStructure => 'מבנה החנות';
  @override
  String whatCategory(String slug) => 'הקטגוריה $slug';
  @override
  String get responseNotPluginList => 'תשובת האתר אינה רשימת תוספים תקינה';
  @override
  String siteUnreachable(String error) => 'לא ניתן להתחבר לאתר אוצריא: $error';
  @override
  String loadFailed(String what, int statusCode) =>
      'לא ניתן לטעון את $what (HTTP $statusCode)';
  @override
  String responseNotJson(String what) => 'תשובת האתר עבור $what אינה JSON תקין';
  @override
  String get responseUnexpectedShape => 'תשובת האתר אינה במבנה הצפוי';
  @override
  String httpStatusFor(int statusCode, String url) =>
      'HTTP $statusCode עבור $url';
}

class _CustomAppsDomain extends CustomAppsDomainStrings {
  const _CustomAppsDomain();

  @override
  String get descriptorNotJson => 'קובץ התוסף אינו קובץ JSON תקין';
  @override
  String descriptorUnsupportedSchema(int found, int supported) =>
      'התוסף נכתב עבור גרסת פורמט $found, והתוכנה יודעת לקרוא עד $supported. '
      'יש לעדכן את התוכנה';
  @override
  String descriptorMissingField(String field) =>
      'חסר בתוסף השדה "$field", או שהוא ריק';
  @override
  String descriptorInvalidId(String id) =>
      'המזהה "$id" אינו תקין. מותרים אותיות לועזיות קטנות, ספרות, נקודה, '
      'מקף וקו תחתון בלבד';
  @override
  String descriptorUnknownInstallerKind(String found, String allowed) =>
      'סוג ההתקנה "$found" אינו נתמך. הסוגים הנתמכים: $allowed';
  @override
  String descriptorUnknownSourceKind(String found, String allowed) =>
      'מקור הגרסאות "$found" אינו נתמך. המקורות הנתמכים: $allowed';

  @override
  String appAlreadyRegistered(String name) => 'התוכנה $name כבר קיימת ברשימה';
  @override
  String appNotRegistered(String id) => 'לא נמצאה תוכנה עם המזהה $id';

  @override
  String get noInstallerInMirror =>
      'אין קובץ התקנה שמור לתוכנה הזו — יש להוסיף אותו במחשב שיש בו הקובץ';
  @override
  String installerFileMissing(String path) => 'קובץ ההתקנה אינו נמצא: $path';
  @override
  String installerExitCode(int exitCode, String output) =>
      'ההתקנה הסתיימה בשגיאה (קוד $exitCode).\n$output';
  @override
  String archiveExtractFailed(String error) => 'חילוץ הארכיון נכשל: $error';
  @override
  String launchFileMissing(String launchPath) =>
      'קובץ ההרצה אינו נמצא: $launchPath';

  @override
  String githubStatus(int statusCode, String uri) =>
      'גיטהאב החזיר שגיאה $statusCode עבור $uri';
  @override
  String get githubBadResponse => 'התשובה מגיטהאב אינה במבנה הצפוי';
  @override
  String get githubNoReleases => 'לא נמצאו גרסאות בריפו הזה';
  @override
  String githubNoMatchingAsset(String tagName) =>
      'בגרסה $tagName אין קובץ שתואם למה שנבחר. ייתכן ששם הקובץ השתנה — '
      'יש לבחור אותו מחדש';
  @override
  String downloadFailed(int statusCode) => 'ההורדה נכשלה (שגיאה $statusCode)';
  @override
  String get sourceIsNotGithub =>
      'התוכנה הזו אינה מוגדרת עם ריפו — אין מה לבדוק ברשת';
}

class _CustomApps extends CustomAppsStrings {
  const _CustomApps();

  @override
  String get screenTitle => 'תוכנות נוספות';
  @override
  String get screenDescription =>
      'תוכנות שהוספתם בעצמכם. מורידים אותן במחשב שיש בו אינטרנט, ומתקינים '
      'מהכונן במחשב שאין בו.';

  @override
  String get settingsCardTitle => 'תוכנות נוספות';
  @override
  String get settingsCardSubtitle =>
      'אפשר להוסיף תוכנות משלכם, שהתוכנה תדע לשאת על הכונן ולהתקין במחשב '
      'המנותק — בדיוק כמו שהיא עושה עם אוצריא.';
  @override
  String get emptyHint => 'לא נוספו תוכנות';
  @override
  String get addButton => 'הוספת תוכנה';

  @override
  String get addDialogTitle => 'הוספת תוכנה';
  @override
  String get nameLabel => 'שם התוכנה';
  @override
  String get nameHint => 'כפי שיוצג לכם ברשימה';
  @override
  String get descriptionLabel => 'תיאור';
  @override
  String get descriptionHint => 'שורה קצרה שתזכיר לכם מה זה';
  @override
  String get installDirLabel => 'מיקום ההתקנה';
  @override
  String get installDirHint =>
      'לפי זה נדע לחפש את התוכנה במחשב. אפשר להשאיר ריק.';
  @override
  String get pickInstallDirButton => 'בחירת תיקייה';
  @override
  String get pickInstallDirDialogTitle => 'בחירת תיקיית ההתקנה';

  @override
  String get sourceLabel => 'מאיפה מגיעה התוכנה';
  @override
  String get sourceGithub => 'מגיטהאב';
  @override
  String get sourceFile => 'מקובץ שלי';

  @override
  String get githubUrlLabel => 'כתובת הריפו בגיטהאב';
  @override
  String get githubUrlHint => 'למשל github.com/owner/repo';
  @override
  String get githubUrlInvalid => 'זו אינה כתובת של ריפו בגיטהאב';
  @override
  String get fetchAssetsButton => 'הצגת הקבצים';
  @override
  String get fetchingAssets => 'מביא את רשימת הקבצים...';
  @override
  String get assetLabel => 'איזה קובץ להוריד';
  @override
  String get assetHint =>
      'בגרסה אחת יש בדרך כלל כמה קבצים. בחרו את זה שמתאים למחשב שלכם.';
  @override
  String get noAssetsFound => 'אין קבצים להורדה בגרסה הזו';
  @override
  String assetsFromRelease(String tagName) => 'הקבצים בגרסה $tagName:';

  @override
  String get pickInstallerButton => 'בחירת קובץ';
  @override
  String get pickInstallerDialogTitle => 'בחירת קובץ ההתקנה';
  @override
  String get installerKindLabel => 'סוג ההתקנה';
  @override
  String get installerKindSniffed => 'זוהה מהקובץ';
  @override
  String get exeNameLabel => 'שם קובץ ההרצה';
  @override
  String get exeNameHint =>
      'למשל myapp.exe — כך נדע אם התוכנה מותקנת ובאיזו גרסה';

  @override
  String get saveButton => 'הוספה';
  @override
  String get nameRequired => 'יש להזין שם לתוכנה';
  @override
  String get sourceRequired => 'יש לבחור קובץ, או ריפו וקובץ מתוכו';
  @override
  String addedSnack(String name) => '$name נוספה';

  @override
  String get kindInno => 'Inno Setup';
  @override
  String get kindNsis => 'NSIS';
  @override
  String get kindMsi => 'MSI';
  @override
  String get kindZip => 'ארכיון';

  @override
  String installedVersion(String version) => 'מותקנת: גרסה $version';
  @override
  String get installedUnknownVersion => 'מותקנת, אך לא ניתן לקרוא את הגרסה';
  @override
  String get notInstalled => 'אינה מותקנת';
  @override
  String get noDetectRules => 'לא ניתן לזהות — לא הוגדר שם קובץ הרצה';
  @override
  String storedInstaller(String version) => 'על הכונן: גרסה $version';
  @override
  String get noStoredInstaller => 'עוד לא הורד קובץ התקנה';

  @override
  String get downloadButton => 'הורדה לכונן';
  @override
  String get downloadingLabel => 'מוריד...';
  @override
  String get checkOnlineButton => 'בדיקה ברשת';
  @override
  String onlineVersionAvailable(String version) => 'ברשת יש גרסה $version';
  @override
  String get onlineUpToDate => 'מה שעל הכונן הוא הגרסה האחרונה';
  @override
  String get onlineUnavailable => 'אין חיבור לרשת כרגע';
  @override
  String get replaceInstallerButton => 'החלפת הקובץ';
  @override
  String get pickLocationButton => 'בחירת מיקום ידנית';
  @override
  String locationAdoptedSnack(String dir) => 'התוכנה נמצאה ב-$dir';
  @override
  String get locationNotFoundSnack =>
      'לא נמצאה שם התקנה של התוכנה. בדקו שבחרתם את התיקייה הנכונה.';

  @override
  String installedSnack(String name) => '$name הותקנה';
  @override
  String archiveInDownloadsSnack(String path) =>
      'הקובץ הועתק לתיקיית ההורדות: $path';
  @override
  String downloadedSnack(String version) => 'גרסה $version ירדה לכונן';

  @override
  String get removeTooltip => 'הסרה מהרשימה';
  @override
  String get removeDialogTitle => 'הסרה מהרשימה';
  @override
  String removeDialogContent(String name) =>
      '$name תוסר מהרשימה, והקובץ השמור שלה יימחק מהכונן.\n\n'
      'התוכנה עצמה לא תוסר מהמחשב.';
  @override
  String get removeDialogConfirm => 'הסרה';
  @override
  String removedSnack(String name) => '$name הוסרה';
}
