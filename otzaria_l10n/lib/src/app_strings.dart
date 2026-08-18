import 'app_language.dart';

/// שורש כל המלל. מחולק לסעיפים לפי המסך/החבילה שבהם הוא מופיע, כדי
/// שהוספת מחרוזת תיגע בקובץ אחד קצר ולא ברשימה שטוחה של מאות שדות.
///
/// המימושים: `HebrewStrings` ו-`EnglishStrings`. הגישה בזמן ריצה דרך
/// [AppL10n] (בחבילות התשתית) או דרך `AppStringsScope` (בלאנצ'ר).
abstract class AppStrings {
  const AppStrings();

  AppLanguage get language;

  CommonStrings get common;
  ShellStrings get shell;
  HomeStrings get home;
  AppScreenStrings get appScreen;
  LibraryScreenStrings get libraryScreen;
  SettingsScreenStrings get settings;
  PluginsStrings get plugins;
  FaqStrings get faq;
  CustomAppsStrings get customApps;
  SetupErrorStrings get setupError;
  PayloadMismatchStrings get payloadMismatch;
  LauncherUpdateStrings get launcherUpdate;
  UnitStrings get units;

  // ── מלל שנוצר בחבילות התשתית ומוצג כמו שהוא ─────────────────────────────
  LibraryDomainStrings get libraryDomain;
  AppDomainStrings get appDomain;
  PluginsDomainStrings get pluginsDomain;
  CustomAppsDomainStrings get customAppsDomain;
}

// ── משותף ─────────────────────────────────────────────────────────────────────

abstract class CommonStrings {
  const CommonStrings();

  String get confirm;
  String get cancel;
  String get continueAction;
  String get close;
  String get error;
  String get retry;

  /// הודעת שגיאה ארוכה (למשל לוג התקנה) מוצגת בשורתה הראשונה בלבד, והשאר
  /// נפתח בדיאלוג — ארבעים שורות בתוך שורת כרטיס אינן נקראות.
  String get errorDetailsButton;
  String get errorDetailsTitle;
  String get install;
  String get update;
  String get launch;
  String get recheck;
  String get notCheckedYet;
  String get checking;
  String get upToDate;
  String get updateAvailable;

  /// המותקן חדש ממה שיושב בתיקייה המקומית — ולכן אין מה להתקין.
  String get installedIsNewer;
  String get installing;
  String get unknownValue;
  String get lastDownloaded;
  String get emptyValue;

  /// שורות שמחזיקות נתיב אינן מציגות אותו — הוא ארוך ואינו קריא בעברית —
  /// אלא מעתיקות אותו בלחיצה.
  String get copyPathButton;
  String get pathCopiedSnack;
}

// ── מסגרת האפליקציה ───────────────────────────────────────────────────────────

abstract class ShellStrings {
  const ShellStrings();

  String get appTitle;
  String get otzariaLogoLabel;
  String get navHome;
  String get navApp;
  String get navLibrary;
  String get navPlugins;
  String get navCustomApps;
  String get navSettings;

  /// נאמר כשלא ניתן לפתוח את תיקיית הלוגים בסייר הקבצים.
  String logPathFallback(String path);
}

// ── דף הבית ───────────────────────────────────────────────────────────────────

abstract class HomeStrings {
  const HomeStrings();

  String get title;

  String get otzariaRunningTitle;
  String get otzariaRunningSubtitle;

  String get appTileTitle;
  String get libraryTileTitle;

  String get appNoInstallFound;
  String get appNothingDownloaded;

  String get noActionAvailable;
  String get moreDetails;

  String get appInstallDialogTitle;
  String get appInstallConfirm;
  String appInstalledSnack(String version);

  String get otzariaOpenSnack;
  String get libraryUpdateDialogTitle;
  String libraryFreshInstallPrompt(String targetVersion);
  String libraryUpdatePrompt(String localVersion, String targetVersion);
  String get libraryUpdateConfirm;
  String libraryUpdatedSnack(String version);

  // ── כרטיס בדיקת העדכונים ברשת ───────────────────────────────────────────
  String get onlineCardTitle;
  String get onlineCardHint;
  String get onlineChecking;
  String get onlineNeverChecked;
  String get onlineOffline;
  String get onlineHasUpdates;
  String get onlineNoUpdates;

  /// פירוט מה נמצא בחנות התוספים — לתוספים אין מספר גרסה אחד להשוות אליו,
  /// ולכן הם נספרים.
  String onlineNewPlugins(int count);
  String onlineUpdatedPlugins(int count);

  /// תוספים שהקטלוג מכיר אבל קובץ ההתקנה שלהם חסר בתיקייה.
  String onlineMissingPlugins(int count);

  /// נאמר כשנמצאו תוספים ברשת אך "הורדת תוספים" כבויה בהגדרות — אחרת
  /// "הורד עכשיו" מדלג עליהם בשקט.
  String get onlinePluginsSyncOff;
  String get checkForUpdatesButton;
  String get downloadNowButton;

  /// ביטול ההורדה שרצה — מוצג רק בזמנה. הביטול **מוחק** את מה שההורדה הזו
  /// הביאה, ולכן הוא עובר דרך דיאלוג אזהרה.
  String get cancelDownloadButton;
  String get cancelDownloadPending;
  String get cancelDownloadDialogTitle;
  String get cancelDownloadPrompt;
  String get cancelDownloadKeepGoing;
  String get downloadCancelledSnack;

  /// אילו רכיבים ההורדה דילגה עליהם, כי הבדיקה הוכיחה שאין בהם חדש.
  String downloadSkippedSnack(String components);

  /// אילו רכיבים ההורדה שלהם נכשלה. בלי זה מד ההתקדמות פשוט נעלם, והמשתמש
  /// נשאר עם כונן חסר וללא סימן שמשהו קרה.
  String downloadFailedSnack(String components);

  /// סוף הורדה שהצליחה. בלעדיה ההורדה — שאורכת עשרות דקות — נגמרה בכך שמד
  /// ההתקדמות פשוט נעלם מהמסך.
  String get downloadDoneSnack;
  String lastCheckedAt(String time);

  String get downloadingApp;
  String get downloadingLibrary;
  String get downloadingPlugins;
  String get downloadStarting;

  // ── תוויות מצב הספרייה, משותפות לדף הבית ולמסך הספרייה ──────────────────
  String get libraryNotInstalledYet;
  String get libraryUpdating;
  String get libraryNothingDownloaded;
  String get libraryNeedsManualPath;
}

// ── מסך תוכנת אוצריא ──────────────────────────────────────────────────────────

abstract class AppScreenStrings {
  const AppScreenStrings();

  String get title;

  String get stateCardTitle;
  String get stateRowTitle;
  String get readyToInstall;
  String get nothingDownloadedYet;

  String get installedVersion;
  String get noInstallDetected;
  String get pickInstallDirButton;
  String get pickInstallDirDialogTitle;
  String get installAdoptedSnack;
  String get installNotFoundSnack;

  String get mirrorVersionTitle;
  String get mirrorEmpty;
  String channelPair(String stable, String prerelease);

  String get channelTileTitle;
  String prereleaseSubtitle(String version);
  String stableSubtitle(String version);
  String get channelStable;
  String get channelPrerelease;

  String get processTitle;
  String get processRunning;
  String get processStopped;

  String get installingProgress;
  String get launchButton;
  String get installUpdateButton;

  /// "מה התחדש" הוא דיאלוג מאחורי כפתור, ולא כרטיס על המסך — הערות הגרסה
  /// ארוכות, והן מעניינות רגע אחד בלבד.
  String get whatsNewTitle;
  String get whatsNewButton;
  String get whatsNewEmpty;

  String get sourceCardTitle;
  String get sourceCardHint;
  String get sourceDirTitle;

  // ── חבילת ההתקנה המלאה (תוכנה + ספרייה) ─────────────────────────────────
  String get fullPackageCardTitle;

  /// ההסבר מה החבילה הזו — מוצג בריחוף על סימן השאלה שליד כותרת הכרטיס.
  String get fullPackageHint;
  String get fullPackageRowTitle;
  String get fullPackageRecommended;
  String get fullPackageNotNeeded;
  String get fullPackageVersionTitle;
  String fullPackageSize(String version, String size);
  String get fullPackageInstallButton;

  /// הדיאלוג שמוצע בלחיצה על "התקנה" במחשב שאין בו אוצריא — לא בעלייה.
  String get fullPackageDialogTitle;
  String fullPackagePrompt(String version, String size);

  /// נוסח דיאלוג ההתקנה — משותף למסך הזה ולאריח שבדף הבית.
  String installPrompt({
    required String? latestVersion,
    required String? currentVersion,
    required bool prereleaseNote,
  });
}

// ── מסך הספרייה ───────────────────────────────────────────────────────────────

abstract class LibraryScreenStrings {
  const LibraryScreenStrings();

  String get title;

  String get stateCardTitle;
  String get stateRowTitle;

  String get dbFileTitle;
  String get dbFileMissing;
  String get pickDbButton;
  String get pickDbDialogTitle;
  String get dbPathUpdatedSnack;

  /// בחירת המיקום שאליו תותקן ספרייה חדשה, וההסבר החובה כשהוא אינו מיקום
  /// שאוצריא מחפשת בו בעצמה.
  String get installTargetTitle;
  String get pickInstallDirButton;
  String get pickInstallDirDialogTitle;
  String get installDirUpdatedSnack;
  String get customLocationDialogTitle;
  String customLocationPrompt(String dbPath);
  String get customLocationConfirm;

  String get localVersionTitle;
  String get targetVersionTitle;
  String get targetVersionNothingDownloaded;
  String get targetVersionUnknown;

  String get otzariaRunningTitle;
  String get otzariaRunningSubtitle;

  String get updatingProgress;
  String get installUpdateButton;
  String get updateDialogTitle;

  /// בקשת עדכון אינדקס החיפוש באוצריא, אחרי שהמסד הוחלף מבחוץ.
  String get reindexTitle;
  String get reindexPendingSubtitle;
  String get reindexButton;
  String get reindexDialogTitle;
  String get reindexDialogContent;
  String get reindexDialogConfirm;
  String get reindexRequestedSnack;
  String reindexFailedSnack(String error);

  String get fullDownloadInsteadButton;
  String get fullDownloadInsteadDialogTitle;
  String fullDownloadInsteadPrompt(String size);

  String get sourceCardTitle;
  String get sourceCardHint;
  String get sourceDirTitle;

  String get mirrorContentTitle;
  String get mirrorEmpty;
  String get mirrorUnreadable;
  String mirrorHasVersion(String version);
  String get mirrorPresent;

  /// מצב "עדכון אישי": נקודת המוצא להורדה נרשמת רק בלחיצה כאן, ובמחשב שבו
  /// אוצריא של המשתמש מותקנת.
  String get personalVersionTitle;
  String personalVersionRecorded(String version);
  String get personalVersionMissing;
  String get personalVersionButton;
  String personalVersionCapturedSnack(String version);
  String get personalVersionNotFoundSnack;

  /// מה ההורדה האחרונה הביאה בפועל — קיים כדי שמצב "עדכון אישי" לא יהיה
  /// שקוף: משתמש שהפעיל אותו ולא זוהתה לו גרסה קיבל בכל זאת מסד מלא.
  String get downloadNoteTitle;
  String downloadNotePersonal(String version);
  String get downloadNotePersonalUnknownVersion;
  String downloadNotePersonalUpToDate(String version);
}

// ── מסך ההגדרות ───────────────────────────────────────────────────────────────

abstract class SettingsScreenStrings {
  const SettingsScreenStrings();

  String get title;

  String get automationCardTitle;
  String get automationCardHint;
  String get autoCheckTitle;
  String get autoCheckSubtitle;
  String get autoOnlineCheckTitle;
  String get autoOnlineCheckSubtitle;

  /// ההסתייגויות — מוצגות בסימן השאלה שליד השורה, לא כשלוש שורות טקסט.
  String get autoOnlineCheckHint;
  String get autoInstallAppTitle;
  String get autoInstallAppSubtitle;
  String get autoInstallLibraryTitle;
  String get autoInstallLibrarySubtitle;

  String get autoInstallSubjectApp;
  String get autoInstallSubjectLibrary;
  String autoInstallDialogTitle(String subject);
  String autoInstallDialogContent(String subject);
  String get autoInstallDialogWarning;
  String get autoInstallDialogConfirm;

  String get downloadCardTitle;
  String get downloadCardHint;
  String get syncAppTitle;
  String get syncAppSubtitle;
  String get syncLibraryTitle;
  String get syncLibrarySubtitle;
  String get syncPluginsTitle;
  String get syncPluginsSubtitle;
  String get syncFullPackageTitle;
  String get syncFullPackageSubtitle;
  String get syncFullPackageHint;

  // ── עדכון אישי ──
  /// מוריד רק את קובצי העדכון מהגרסה שכבר מותקנת ומעלה, בלי המסד המלא —
  /// ולכן הכונן אינו משמש עוד להפצה למחשבים אחרים.
  String get personalModeTitle;
  String get personalModeSubtitle;
  String get personalModeHint;
  String get personalModeDialogTitle;
  String get personalModeDialogContent;
  String get personalModeDialogWarning;
  String get personalModeDialogConfirm;

  String get appearanceCardTitle;
  String get languageTitle;
  String get languageSubtitle;
  String get languageSystem;
  String get languageHebrew;
  String get languageEnglish;
  String get themeTitle;
  String get themeSystem;
  String get themeLight;
  String get themeDark;

  /// הכפתור הצף של השאלות הנפוצות בדף הבית.
  String get showFaqTitle;
  String get showFaqSubtitle;

  // ── פלטת צבע הבסיס ──
  // הבחירה חלה על הערכה המוצגת כרגע — בהירה או כהה — כמו באוצריא.
  String get seedColorTitle;
  String get seedColorButton;
  String get seedColorDialogTitle;
  String get seedColorResetButton;

  /// כשהצבע השמור אינו אחד מצבעי הפלטה (קובץ הגדרות שנערך ביד).
  String get seedColorCustom;

  /// שמות הצבעים, בסדר שבו הם מוצגים בבורר.
  String get colorRed;
  String get colorOrange;
  String get colorAmber;
  String get colorGreen;
  String get colorTeal;
  String get colorBlue;
  String get colorBlueGrey;
  String get colorNavy;
  String get colorPurple;
  String get colorBrown;
  String get colorParchment;
  String get colorGrey;
  String get colorDarkBrown;

  String get supportCardTitle;
  String get logTitle;
  String get logSubtitle;
  String get openLogFolderButton;

  String get resetTitle;
  String get resetSubtitle;
  String get resetButton;
  String get resetDialogTitle;
  String get resetDialogContent;
  String get resetDialogWarning;
  String get resetDialogConfirm;
  String get resetDoneSnack;
}

// ── חנות התוספים ──────────────────────────────────────────────────────────────

abstract class PluginsStrings {
  const PluginsStrings();

  String get syncDialogTitle;
  String get syncDialogContent;
  String get syncDialogConfirm;
  String get syncFailedSnack;

  /// [fetched] הוא מה שבאמת ירד עכשיו, מתוך [total] שבחנות — הסנכרון מדלג
  /// על כל מה שכבר מעודכן במראה, וההודעה חייבת לומר את זה.
  String syncDoneSnack(int fetched, int total);

  /// נאמר בזמן הסנכרון עצמו, מתחת לכותרת: לא מורידים את החנות מחדש.
  String get syncingOverlaySubtitle;

  /// סנכרון שהסתיים אך פריטים בודדים בו נכשלו — ראו `syncWarnings`.
  String syncDoneWithWarningsSnack(int count);
  String get syncButton;
  String get reloadTooltip;
  String get syncingOverlayTitle;
  String get syncingOverlayStarting;
  String get syncNeverRan;
  String syncedAt(String time);
  String get syncDirUnknownTooltip;
  String updatesAvailableChip(int count);
  String get updatesChipTooltip;

  String get saveDialogTitle;
  String get saveDoneSnack;
  String get saveFailedSnack;
  String installOpenedSnack(String pluginName);
  String get installFailedSnack;

  String get loadingCatalog;
  String get catalogTitleFallback;
  String get catalogSubtitleFallback;
  String get heroSearchHint;
  String get heroSearchButton;

  String get emptyStoreTitle;
  String get emptyStoreBody;
  String allPluginsWithCount(int count);
  String get browseAllPrompt;
  String browseAllButton(int count);

  String get featuredEyebrow;
  String get featuredTitle;
  String get showMoreFeatured;
  String categoryLinkButton(int count);

  String get breadcrumbRoot;
  String get allPluginsPage;
  String get listEyebrow;
  String get listTitle;
  String get summaryNoResults;
  String get summaryAllShown;
  String summaryPartial(int shown, int total);
  String get categoryOnePlugin;
  String categoryPluginCount(int count);

  String get hideInstalledLabel;
  String hideInstalledOnTooltip(int installedCount);
  String hideInstalledOffTooltip(int installedCount);

  String get neverSyncedTitle;
  String get neverSyncedBody;
  String get noResultsTitle;
  String get noResultsBody;
  String get allInstalledTitle;
  String get allInstalledBody;
  String get showInstalledButton;
  String get emptyCategoryTitle;
  String get emptyCategoryBody;
  String get allPluginsButton;

  // ── שורת הסינון ─────────────────────────────────────────────────────────
  String get filterSearchLabel;
  String get filterSearchHint;
  String get filterStatusLabel;
  String get filterTagsLabel;
  String get filterAllTags;
  String get filterStatusAll;
  String get showMoreTags;
  String get showFewerTags;

  // ── כרטיס ועמוד התוסף ───────────────────────────────────────────────────
  String get badgeFeaturedShort;
  String get badgeFeatured;
  String pluginVersionBadge(String version);
  String downloadsBadge(int count);
  String get saveButton;
  String get installButton;
  String get directInstallButton;
  String get sourcePageButton;
  String get cardDetailsLink;
  String cardUpdatedOn(String date);
  String get backToStore;

  String get statusStable;
  String get statusBeta;
  String get statusExperimental;
  String get statusUnknown;

  String get installChipInstalled;
  String get installChipUpdateAvailable;
  String installChipUpdateFrom(String installedVersion);

  String get infoPanelTitle;
  String get tagsPanelTitle;
  String get screenshotsPanelTitle;
  String get infoVersion;
  String get infoStatus;
  String get infoAuthor;
  String get infoUpdated;
  String get infoNetwork;
  String get infoNetworkRequired;
  String get infoNetworkNotRequired;
  String get infoCompatibility;
  String compatibilityRange(String from, String to);
  String get infoLocalFile;
  String get infoLocalFileMissing;
  String localFileDescription(String fileName, String size);
  String get valueUnspecifiedFeminine;
  String get valueUnspecifiedMasculine;
  String get sizeUnknown;

  // ── קטגוריות וניווט ─────────────────────────────────────────────────────
  String get categoriesTitle;
  String get storeHomeItem;
  String get storeHomeChip;

  // ── דיאלוג העדכונים ─────────────────────────────────────────────────────
  String updatesDialogTitle(int count);
  String get updatesDialogIntro;
  String updatesDialogRow(String installedVersion, String storeVersion);
  String get updatesDialogUpdateButton;
  String updatesDialogUpdateAllButton(int count);
  String get updatesDialogDetailsButton;

  /// שורה שהמסירה שלה לאוצריא הצליחה — ההתקנה עצמה נעשית שם.
  String get updatesDialogSentLabel;
  String get updatesDialogDoneLabel;

  /// תוסף שאין לו התקנה ישירה — יש להתקינו מדף התוסף.
  String get updatesDialogManualOnly;
  String get updatesDialogPendingNote;
  String get updatesDialogRecheckButton;

  // ── גלריית צילומי המסך ──────────────────────────────────────────────────
  String get screenshotPrevious;
  String get screenshotNext;
}

// ── שאלות נפוצות ──────────────────────────────────────────────────────────────

/// ההדרכה שנפתחת מהכפתור הצף. הנוסח כאן מכוון למי שאינו מבין במחשבים, ולכן
/// כל תשובה אומרת מה **לעשות** ולא איך זה בנוי מבפנים.
///
/// הזוגות שאלה/תשובה נאספים לרשימה ב-`launcher_app` (`faq_content.dart`);
/// שדה שנוסף כאן חייב להיכנס גם שם, אחרת הוא לא יוצג.
abstract class FaqStrings {
  const FaqStrings();

  /// שם ההדרכה — משמש גם לכותרת הדיאלוג, גם ל-tooltip וגם לבועה שנפתחת
  /// בעלייה.
  String get title;
  String get intro;

  // ── שמות הקבוצות ────────────────────────────────────────────────────────
  String get groupBasics;
  String get groupDownload;
  String get groupLibrary;
  String get groupExtras;
  String get groupGeneral;

  // ── איך זה עובד ─────────────────────────────────────────────────────────
  String get qWhatIsThis;
  String get aWhatIsThis;
  String get qOfflineFlow;
  String get aOfflineFlow;
  String get qNoOtzariaYet;
  String get aNoOtzariaYet;

  // ── הורדה והתקנה ────────────────────────────────────────────────────────
  String get qDownloadStopped;
  String get aDownloadStopped;
  String get qDownloadTooBig;
  String get aDownloadTooBig;
  String get qOtzariaOpen;
  String get aOtzariaOpen;
  String get qBrokenAfterUpdate;
  String get aBrokenAfterUpdate;

  // ── הספרים לא נמצאים ────────────────────────────────────────────────────
  String get qAppNotDetected;
  String get aAppNotDetected;
  String get qDbNotFound;
  String get aDbNotFound;
  String get qStillNotFound;
  String get aStillNotFound;
  String get qSearchMissesNewBooks;
  String get aSearchMissesNewBooks;

  // ── תוספים ותוכנות נוספות ───────────────────────────────────────────────
  String get qWhatArePlugins;
  String get aWhatArePlugins;
  String get qWhatAreCustomApps;
  String get aWhatAreCustomApps;

  // ── כללי ────────────────────────────────────────────────────────────────
  String get qWrongFolder;
  String get aWrongFolder;
  String get qLauncherSelfUpdate;
  String get aLauncherSelfUpdate;
  String get qFree;
  String get aFree;
  String get qNoExpenses;
  String get aNoExpenses;

  // ── סיום ────────────────────────────────────────────────────────────────
  /// כותרת כרטיס הסיום. הכרטיס כולו מוצג **רק** למי שמילא שם או טלפון
  /// בהתאמה האישית — "אפשר לפנות אלינו" בלי לומר למי אינו עוזר לאיש.
  String get contactTitle;

  // ── התאמה אישית ─────────────────────────────────────────────────────────
  /// מצב העריכה שנפתח בגלגל השיניים: הסתרת שאלות, הוספת שאלות משלי, והפרטים
  /// שיופיעו בתחתית הרשימה. מיועד למי שמכין כונן לאחרים.
  String get editTooltip;
  String get editDoneTooltip;
  String get editIntro;

  String get hideTooltip;
  String get restoreTooltip;
  String get hiddenLabel;

  String get myQuestionsTitle;
  String get noExtrasYet;
  String get addQuestionButton;
  String get editQuestionTooltip;
  String get deleteQuestionTooltip;

  String get formAddTitle;
  String get formEditTitle;
  String get formQuestionLabel;
  String get formAnswerLabel;
  String get formSave;

  /// נאמר כשמנסים לשמור שאלה בלי שאלה או בלי תשובה.
  String get formIncompleteSnack;

  String get deleteConfirmTitle;
  String get deleteConfirmContent;

  String get contactCardTitle;
  String get contactCardHint;
  String get contactNameLabel;
  String get contactPhoneLabel;

  /// שורת הטלפון כפי שהיא מוצגת בתחתית ההדרכה.
  String contactPhoneLine(String phone);
}

// ── מסך "התוכנה במקום הלא נכון" ───────────────────────────────────────────────

abstract class SetupErrorStrings {
  const SetupErrorStrings();

  String get title;
  String get explanation;
  String get whatToDo;
  String get attemptedDirTitle;

  /// בפועל תמיד בעברית: השגיאה נזרקת לפני שקובץ ההגדרות בכלל נקרא, כי הוא
  /// יושב בתיקייה שנכשלה. מתורגם בכל זאת כדי שלא תישאר מחרוזת בקוד.
  String cannotWriteToDataDir(String osMessage);
}

// ── ערמת קבצים שאינה תואמת ל-exe ──────────────────────────────────────────────

/// המסך שעוצר הרצה של `app-files` שאינה שייכת ל-exe שלצידה — ראו
/// `PayloadCheck`. הפעולה שמתקנת היא סגירה ופתיחה מחדש, ולכן זה כל מה שיש כאן.
abstract class PayloadMismatchStrings {
  const PayloadMismatchStrings();

  String get title;
  String get explanation;
  String get whatToDo;
  String get runningVersionTitle;
  String get expectedVersionTitle;
  String get closeButton;
}

// ── עדכון עצמי של הלאנצ'ר ─────────────────────────────────────────────────────

/// המלל של עדכון **הלאנצ'ר עצמו** — לא אוצריא, לא הספרייה. הסעיף מחזיק גם
/// את הודעות השגיאה של השירותים שמחליפים את קובץ ההרצה, כי הם חיים בתוך
/// `launcher_app` ולא בחבילת תשתית משלהם.
abstract class LauncherUpdateStrings {
  const LauncherUpdateStrings();

  // ── הכרטיס בדף הבית ─────────────────────────────────────────────────────
  String get cardTitle;
  String get cardHint;
  String installedVersion(String version);

  /// הגרסה שכבר יושבת בתיקייה שלצד התוכנה ומחכה להתקנה.
  String downloadedVersion(String version);

  /// הגרסה שהבדיקה הקלה מצאה ברשת ועדיין לא הורדה.
  String onlineVersion(String version);

  String get statusUpToDate;
  String get statusUpdateAvailable;
  String get statusReadyToInstall;
  String get statusDownloading;
  String get statusInstalling;

  String get downloadButton;
  String get installButton;

  // ── דיאלוג ההצעה, בפתיחת התוכנה ─────────────────────────────────────────
  String get availableDialogTitle;
  String availableDialogContent(String version);
  String availableDialogDetail(String size);
  String get availableDialogConfirm;
  String get availableDialogCancel;

  // ── דיאלוג "ההורדה הושלמה" ──────────────────────────────────────────────
  String get readyDialogTitle;
  String readyDialogContent(String version);
  String get readyDialogConfirm;

  String downloadedSnack(String version);
  String get installingSnack;

  /// ב-macOS ההחלפה מסתיימת בלי הפעלה מחדש אוטומטית — ראו
  /// `LauncherSelfInstaller`.
  String get manualRestartNotice;

  // ── הגדרות ──────────────────────────────────────────────────────────────
  String get versionTileTitle;

  // ── שגיאות ──────────────────────────────────────────────────────────────
  /// אין לנו את הנתיב של קובץ ההרצה שהמשתמש מפעיל, ולכן אין מה להחליף.
  String get executableNotFound;
  String get mirrorMissing;
  String unsupportedPlatform(String operatingSystem);
  String downloadFailed(int statusCode);
  String sizeMismatch(int received, int expected);
  String replaceFailed(String error);
  String restartFailed(String error);
}

// ── יחידות ומספרים ────────────────────────────────────────────────────────────

abstract class UnitStrings {
  const UnitStrings();

  String bytes(int count);
  String progressOf(String received, String total);

  /// יחידות הגודל הגדולות. הן מופיעות בשורת ההתקדמות של הורדה של ~1GB —
  /// הטקסט הנקרא ביותר בתוכנה — ולכן אינן יכולות להישאר קבועות באנגלית.
  String kilobytes(String amount);
  String megabytes(String amount);
  String gigabytes(String amount);
}

// ── הודעות מחבילות הספרייה (השורש + library_manager) ─────────────────────────

abstract class LibraryDomainStrings {
  const LibraryDomainStrings();

  // seforim_library_updater
  String unsupportedPatchCompression(String compression);
  String get manifestMissingPatchFiles;
  String manifestMissingField(String key);
  String releasesRequestFailed(int statusCode);
  String get releasesResponseNotList;
  String manifestDownloadFailed(String url, int statusCode);
  String manifestNotJsonObject(String url);

  String get interruptedUpdateFound;

  String get exportLoadingReleases;
  String get exportNoReleases;

  /// מצב "עדכון אישי" — ההורדה מדלגת על המסד המלא.
  String exportPersonalFrom(int localVersion);
  String exportPersonalUpToDate(int localVersion);
  String get exportPersonalVersionUnknown;

  /// המסד המלא שכבר במראה נשמר, כי יש ממנו מסלול patches לגרסה האחרונה.
  String exportReusingFullDb(int version, String tag);

  String exportDownloading(String tag, String asset);
  String exportVerifying(String tag, String asset);
  String exportWritingManifest(String fileName);
  String get exportDone;
  String get exportCancelled;
  String get exporterDoesNotExtract;

  /// manifest שתוכנו אינו קריא — מדלגים על ה-edge שלו, כמו באופליין.
  String exportManifestUnreadable(String asset, String detail);

  /// כשל **רשת** בשליפת manifest, אחרי ניסיונות חוזרים. לא מדלגים עליו:
  /// מראה בלי קובצי ה-patch נראית שלמה וחסר בה edge.
  String exportManifestFetchFailed(String asset, String detail);

  /// ה-manifest מצביע על קובץ patch שאינו ברשימת הנכסים (עוד עולה, או הוסר).
  String exportPatchAssetMissing(String tag, String file);

  String get planLocalVersionUnknown;
  String planContentChangedWithoutVersionBump(String releaseTag);
  String planNoDeltaRoute(int localVersion, int latestVersion);
  String planNoFullDbEither(String reason);

  String mirrorManifestMissing(String fileName, String mirrorDir);
  String mirrorManifestCorrupt(String fileName, String mirrorDir, String error);
  String mirrorManifestUnexpectedShape(String fileName, String mirrorDir);
  String mirrorPatchManifestMissing(String url);
  String mirrorPatchManifestCorrupt(String url, String error);
  String mirrorPatchManifestNotJson(String url);

  String unsupportedSchemaForHashOrder(int schemaVersion);
  String localVersionMismatch(int? localVersion, int expected);
  String localSchemaMismatch(int localSchema, int expected);
  String get contentHashMismatchNeedsFullDownload;
  String patchUniqueConflictNeedsFullDownload(String table, String detail);
  String foreignKeyViolationsGrew(int before, int after);
  String resultHashMismatch(String actual, String expected);
  String get patchMetaSchemaVersionMissing;
  String patchSchemaTooNew(int schemaVersion, int supported);
  String patchVersionRangeMismatch(
    int? from,
    int? to,
    int manifestFrom,
    int manifestTo,
  );

  String get compressedFileSizeLabel;
  String get compressedFileHashLabel;
  String get extractedFileSizeLabel;
  String get extractedFileHashLabel;
  String get patchExtractionFailed;
  String get deleteExistingWithoutResumeIdentityFailed;
  String get deletePartialFromPreviousVersionFailed;
  String get deletePartialWithoutValidatorFailed;
  String get deletePartialFromPreviousRepresentationFailed;
  String get deletePartialBeforeRetryFailed;
  String fullDbSizeMismatch(int downloaded, int expected);
  String get fullDbHashMismatch;
  String resumeRoundLimit(int maxRounds, String url);
  String contentLengthMismatch(int responseLength, int expectedSize);
  String truncatedBody(int declared, int received);
  String downloadHttpError(int statusCode, String url);
  String resumeMadeNoProgress(String url);
  String resumeFailedAfterRetry(String url);
  String downloadExceedsExpectedSize(int expectedSize);
  String saveDownloadedFileFailed(String error);
  String tooManyRedirects(String url);
  String writeResumeSidecarFailed(String path, String error);
  String checksumMismatchDetailed(String label, String expected, String actual);
  String checksumMismatch(String label);
  String localFileNotFound(String path);
  String localFileTooLarge(int maxBytes, String path);
  String localSourceNotFound(String url);
  String localFileSizeMismatch(int expected, int actual, String url);
  String localFileHashMismatch(String url);

  // library_manager
  String get mirrorMissing;
  String interruptedUpdateNeedsManualFix(String detail);
  String get interruptedUpdateDefaultDetail;
  String get blockedNeedsManualAction;
  String get blockedNeedsManualActionWithPeriod;
  String patchUrlMissing(String fileName);
  String get fullDbAssetMissingFromPlan;
  String get fullDbExtractionFailed;
  String versionMismatchAfterWrite(int? actual, int? expected);
  String get updateCancelled;

  /// אין מקום בדיסק. אומרת **כמה** לפנות ו**איפה** — קודם לכן זו הייתה שגיאת
  /// OS באנגלית על נתיב `.new` שהמשתמש אינו מכיר.
  String notEnoughDiskSpace(String dir, String needed, String free);

  /// תיקיית ההתקנה אינה ניתנת לכתיבה (issue #23) — מפנה לבורר הידני.
  String installDirNotWritable(String dir, String detail);

  /// מקום פנוי חסר להורדת המראה, עם הגודל שנדרש בפועל לפי התוכנית.
  String mirrorNotEnoughDiskSpace(String dir, String needed, String free);
  String get otzariaIsRunning;
  String get zstdContextCreationFailed;
  String zstdDecompressionFailed(String errorName);
  String get zstdEmptyInput;
  String get zstdTruncatedFrame;

  String dbIntegrityCheckFailed(String result);

  // ── הקבצים הנלווים לספרייה (תלמוד, קטלוג, מילון) ────────────────────────
  String get companionTalmudName;
  String get companionCatalogName;
  String get companionDictionaryName;
  String companionChecking(String name);
  String companionDownloading(String name);
  String companionInstalling(String name);
  String companionAssetMissingInRelease(String name);
  String companionExtractionFailed(String name);
  String get companionsMirrorMissing;

  // שלבי ההחלה, כפי שמוצגים במד ההתקדמות
  String applyDownloadingPatch(String step);
  String applyApplyingPatch(String step);

  /// תת-שלב בתוך החלת ה-patch — [stage] הוא שם השלב הגולמי כפי ש-
  /// `PatchApplier.onStage` מדווח אותו.
  String applyPatchStage(String stage, String step);
  String get applyDownloadingFullDb;
  String get applyDecompressingFullDb;
  String get applyWritingFullDb;
  String get applyVerifying;
  String get applyInstallingCompanions;
  String get applyDone;
}

// ── הודעות מ-otzaria_manager ──────────────────────────────────────────────────

abstract class AppDomainStrings {
  const AppDomainStrings();

  String get channelStable;
  String get channelPrerelease;
  String downloadingChannel(String channelLabel);
  String get downloadingFullPackage;

  /// הודעת החריג שנזרק כשהמשתמש ביטל את ההורדה — לא שגיאה, בחירה.
  String get downloadCancelled;

  String get noInstallableReleaseForPlatform;
  String get mirrorEmptyRunDownload;
  String get fullPackageNotOnDrive;
  String get noOtzariaInstallFound;
  String get corruptReleaseMetadata;
  String unsupportedPlatform(String operatingSystem);
  String noAssetForPlatform(
    String tagName,
    String platform,
    List<String> expectedSuffixes,
  );

  String installerDownloadFailed(int statusCode);
  String installerSizeMismatch(int received, int expected);
  String installerExitCode(int exitCode, String output);
  String installerLogTail(String tail);
  String get macAppNotFoundInArchive;
  String macReplaceFailed(String error);
  String dittoExtractFailed(int exitCode, String output);
  String hdiutilAttachFailed(int exitCode, String output);
  String get macAppNotFoundInDmg;
  String dittoCopyFailed(int exitCode, String output);
  String installNotDetected(String installDir, int timeoutSeconds);
  String launchFileMissing(String launchPath);
  String launchFailed(int exitCode, String stderr);
  String githubStatus(int statusCode, String uri);
  String noReleasesAtAll(String repo);
  String get windowsOnlyReader;
  String get macOnlyReader;
}

// ── הודעות מ-plugins_manager ──────────────────────────────────────────────────

abstract class PluginsDomainStrings {
  const PluginsDomainStrings();

  String get fileNotAvailableSyncFirst;
  String saveFailed(String error);
  String get pluginFileNotAvailable;
  String get localPluginFileMissing;
  String get badPluginExtension;
  String get otzariaOpenFailedHint;
  String otzariaOpenFailed(String error);
  String get directInstallUnsupportedPlatform;

  String get syncLoadingCatalog;

  /// [total] הוא מספר התוספים שיש בהם מה להוריד, לא גודל החנות — הסנכרון
  /// מדלג לגמרי על מה שכבר מעודכן.
  String syncPlugin(String name, int done, int total);
  String get syncDone;

  /// סיום מפורט: כמה ירדו וכמה דולגו. בלעדיו "הסתיים" נראה זהה בין
  /// "הכול כבר היה מעודכן" לבין סנכרון שבאמת הביא משהו.
  String syncDoneCounts(int fetched, int skipped);
  String get syncCategories;
  String syncStructureFailed(String error);

  /// הסיבה שנמסרת ל-[syncStructureFailed] כשהתשובה תקינה אך ריקה ממבנה.
  String get syncStructureEmpty;

  /// סנכרון שהחזיר קטלוג ריק מול מראה שיש בה תוספים — נדחה במקום לרוקן.
  String get syncEmptyCatalogRejected;
  String syncCategoryFailed(String name, String error);
  String syncImageFailed(String name, String error);
  String syncScreenshotFailed(String name, String error);
  String syncPluginFileFailed(String name, String error);

  String get whatPluginList;
  String get whatStoreStructure;
  String whatCategory(String slug);
  String get responseNotPluginList;

  /// מחליפה את הטקסט הגולמי של `TimeoutException` בכל דיווח כשל רשת —
  /// "Future not completed" אינו אומר למשתמש דבר.
  String get networkTimedOut;
  String siteUnreachable(String error);
  String loadFailed(String what, int statusCode);
  String responseNotJson(String what);
  String get responseUnexpectedShape;
  String httpStatusFor(int statusCode, String url);
}
// ── תוכנות מותאמות (ממשק) ────────────────────────────────────────────────────

/// המסגרת סביב תוכנות שהמשתמש הוסיף. **שם התוכנה והתיאור שלה אינם
/// מתורגמים** — הם תוכן שהמשתמש כתב, כמו שמות התוספים מ-otzaria.org.
abstract class CustomAppsStrings {
  const CustomAppsStrings();

  // ── המסך ──
  String get screenTitle;

  /// הכניסה מההגדרות. היא קיימת כי פריט הניווט מופיע רק אחרי שנוספה
  /// תוכנה — בלעדיה אי אפשר להוסיף את הראשונה.
  String get settingsCardTitle;
  String get settingsCardHint;
  String get emptyHint;
  String get addButton;

  // ── טופס ההוספה, והוא גם טופס העריכה ──
  String get addDialogTitle;
  String get editDialogTitle;
  String get nameLabel;
  String get nameHint;
  String get descriptionLabel;
  String get descriptionHint;
  String get installDirLabel;
  String get installDirHint;
  String get pickInstallDirButton;
  String get pickInstallDirDialogTitle;

  String get sourceLabel;
  String get sourceGithub;
  String get sourceFile;

  String get githubUrlLabel;
  String get githubUrlHint;
  String get githubUrlInvalid;
  String get fetchAssetsButton;
  String get fetchingAssets;
  String get assetLabel;
  String get assetHint;
  String get noAssetsFound;
  String assetsFromRelease(String tagName);

  String get pickInstallerButton;
  String get pickInstallerDialogTitle;
  String get installerKindLabel;
  String installerKindSniffed(String kind);

  /// "הקובץ הוא התוכנה עצמה". השאלה היחידה על הקובץ שכן נשאלת, כי
  /// **אי אפשר להסיק אותה מהבייטים**: exe נייד ומתקין שלא זוהה נראים זהים.
  String get portableFileLabel;
  String get portableFileHint;
  String get pickCopyTargetDialogTitle;
  String copiedFileSnack(String path);

  String get exeNameLabel;
  String get exeNameHint;

  /// בעריכה המקור כבר נבחר פעם. שתי השורות האלה אומרות מה יישאר אם לא
  /// נוגעים בו — בלעדיהן טופס עריכה נראה כאילו אין בו מקור.
  String get githubAssetKept;
  String installerKept(String fileName);

  String get saveButton;
  String get saveEditButton;
  String get nameRequired;
  String get sourceRequired;
  String addedSnack(String name);
  String updatedSnack(String name);

  // ── שמות סוגי ההתקנה. שלושת הראשונים שמות מוצר — זהים בשתי השפות. ──
  String get kindInno;
  String get kindNsis;
  String get kindMsi;
  String get kindZip;
  String get kindPortableFile;
  String get kindInteractive;

  // ── כרטיס תוכנה ──
  String installedVersion(String version);
  String get installedUnknownVersion;
  String get notInstalled;

  /// "לא חיפשנו" אינו "חיפשנו ולא מצאנו" — ראו `CustomAppView.canDetect`.
  String get noDetectRules;
  String storedInstaller(String version);
  String get noStoredInstaller;

  String get downloadButton;
  String get downloadingLabel;
  String get checkOnlineButton;
  String onlineVersionAvailable(String version);
  String get onlineUpToDate;
  String get onlineUnavailable;
  String get replaceInstallerButton;

  /// "בחירת מיקום ידנית" — הנפילה חזרה כשהזיהוי האוטומטי לא מצא.
  String get pickLocationButton;
  String locationAdoptedSnack(String dir);
  String get locationNotFoundSnack;

  String installedSnack(String name);

  /// מוצג כל זמן שממתינים לרישום ההסרה אחרי ההתקנה. חייב להיות שם: הסקירה
  /// החוזרת יכולה להימשך עד דקה, ובלי הודעה זה נראה כתקיעה.
  String get learningLabel;

  /// מה שנלמד. נאמר במפורש כי מכאן והלאה הכרטיס יפסיק לומר "לא ניתן לזהות".
  String learnedDetectionSnack(String exeName);

  /// תוכנה מסוג ארכיון אינה מותקנת — היא מונחת בתיקיית ההורדות.
  String archiveInDownloadsSnack(String path);
  String downloadedSnack(String version);

  String get editTooltip;
  String get removeTooltip;
  String get removeDialogTitle;

  /// חייב לומר במפורש שהתוכנה עצמה **אינה** מוסרת מהמחשב.
  String removeDialogContent(String name);
  String get removeDialogConfirm;
  String removedSnack(String name);
}

// ── הודעות מ-custom_apps_manager ──────────────────────────────────────────────

/// שגיאות של תוכנות מותאמות. שמות התוכנות עצמם הם **תוכן** ואינם מתורגמים
/// — רק המסגרת סביבם, בדיוק כמו בשמות התוספים מ-otzaria.org.
abstract class CustomAppsDomainStrings {
  const CustomAppsDomainStrings();

  // ── קובץ התוסף ──
  String get descriptorNotJson;
  String descriptorUnsupportedSchema(int found, int supported);
  String descriptorMissingField(String field);
  String descriptorInvalidId(String id);
  String descriptorUnknownInstallerKind(String found, String allowed);
  String descriptorUnknownSourceKind(String found, String allowed);

  // ── המרשם ──
  String appAlreadyRegistered(String name);
  String appNotRegistered(String id);

  // ── התקנה ──
  String get noInstallerInMirror;
  String installerFileMissing(String path);
  String installerExitCode(int exitCode, String output);

  /// כשל בהעתקת קובץ שאין מה להתקין ממנו — ארכיון או קובץ נייד. שום דבר
  /// כאן אינו מחולץ, ולכן זה "העתקה" ולא "חילוץ".
  String fileCopyFailed(String error);
  String launchFileMissing(String launchPath);

  // ── GitHub ──
  String githubStatus(int statusCode, String uri);
  String get githubBadResponse;
  String get githubNoReleases;
  String githubNoMatchingAsset(String tagName);
  String downloadFailed(int statusCode);
  String get sourceIsNotGithub;
}
