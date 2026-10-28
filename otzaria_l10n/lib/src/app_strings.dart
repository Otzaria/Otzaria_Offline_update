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
  GuidanceStrings get guide;
  TaskStrings get task;
  PageStrings get pages;
  AppScreenStrings get appScreen;
  LibraryScreenStrings get libraryScreen;
  SettingsScreenStrings get settings;
  SaferModeStrings get saferMode;
  PluginsStrings get plugins;
  FaqStrings get faq;
  CustomAppsStrings get customApps;
  ErrorReportsStrings get errorReports;
  AppReportsStrings get appReports;
  SetupErrorStrings get setupError;
  ReadOnlyDriveStrings get readOnlyDrive;
  ElevationStrings get elevation;
  PayloadMismatchStrings get payloadMismatch;
  LauncherUpdateStrings get launcherUpdate;
  UnitStrings get units;

  // ── מלל שנוצר בחבילות התשתית ומוצג כמו שהוא ─────────────────────────────
  LibraryDomainStrings get libraryDomain;
  AppDomainStrings get appDomain;
  PluginsDomainStrings get pluginsDomain;
  CustomAppsDomainStrings get customAppsDomain;
  ErrorReportsDomainStrings get errorReportsDomain;
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

  /// האזהרה "אוצריא פתוחה" מופיעה בשלושה מסכים, והכפתור שסוגר אותה זהה
  /// בכולם — ולכן המלל שלו יושב כאן ולא בכל אחד מהם.
  String get closeOtzariaButton;
  String get closeOtzariaFailedSnack;

  /// הכונן התמלא באמצע כתיבה והמערכת לא אמרה כמה חסר, ולכן אין כאן מספרים.
  String storageFullNoDetails(String dir);
  String get storageFullUnknownDir;
}

// ── מסגרת האפליקציה ───────────────────────────────────────────────────────────

abstract class ShellStrings {
  const ShellStrings();

  String get appTitle;
  String get otzariaLogoLabel;

  /// נאמר כשלא ניתן לפתוח את תיקיית הלוגים בסייר הקבצים.
  String logPathFallback(String path);
  String folderPathFallback(String path);

  String get closeWhileBusyTitle;
  String get closeWhileDownloadingPrompt;
  String get closeWhileDownloadingConfirm;
  String get closeWhileInstallingPrompt;
  String get closeWhileInstallingConfirm;
  String get closeWhileBusyKeepGoing;

  /// כלי שורת הכותרת וכפתורי החלון — תוויות נגישות ו-tooltip.
  String get helpTooltip;
  String get settingsTooltip;
  String get windowMinimize;
  String get windowMaximize;
  String get windowRestore;
  String get windowClose;

  /// כפתור החזרה בראש דף משנה.
  String get backTooltip;

  /// "בית" בפירור הלחם של דף משנה.
  String get breadcrumbHome;
}

// ── דף הבית ───────────────────────────────────────────────────────────────────

abstract class HomeStrings {
  const HomeStrings();

  String get otzariaOpenSnack;

  /// אזהרה לפני עדכון הספרייה ולאורכו — התוכנה והעדכונים יושבים על הכונן
  /// הנשלף, ושליפתו באמצע ההחלה קוטעת את העדכון.
  String get doNotRemoveDriveWarning;

  // ── ההורדה לכונן ─────────────────────────────────────────────────────────

  /// ביטול ההורדה שרצה — מוצג רק בזמנה. הביטול **מוחק** את מה שההורדה הזו
  /// הביאה, ולכן הוא עובר דרך דיאלוג אזהרה.
  String get cancelDownloadButton;
  String get cancelDownloadDialogTitle;
  String get cancelDownloadPrompt;
  String get cancelDownloadKeepGoing;
  String get downloadingApp;
  String get downloadingLibrary;
  String get downloadingPlugins;
  String get downloadStarting;

  // ── תוויות מצב הספרייה, משותפות לדף הבית ולמסך הספרייה ──────────────────
  String get libraryApplyActive;
}

// ── מסכי המשימה ──

/// מסכי המשימה: הורדה לכונן ו"עדכון אוצריא במחשב הזה". הנוסח מהמוקאפ.
abstract class TaskStrings {
  const TaskStrings();

  String get semanticTitle;
  String get semanticBody;
  String get semanticNoTitle;
  String get semanticNoBody;
  String get semanticNoSize;
  String get semanticYesTitle;
  String get semanticYesBody;

  /// תיבת הסימון שבתחתית השאלה — מעבירה את הבחירה להגדרות.
  String get semanticRemember;
  String get semanticRememberBody;
  String get back;
  String get startDownload;
  String get preparingTitle;
  String get preparingBody;
  String get downloadingTitle;
  String get downloadingBody;
  String downloadingStep(String name, int index, int count);
  String get componentApp;
  String get componentLibrary;
  String get componentPlugins;
  String get stepApp;
  String get stepLibrary;
  String get stepPlugins;

  /// הזמן שנותר, מדקה אחת ומעלה; מתחת לדקה — [lessThanMinuteLeft].
  String minutesLeft(int minutes);
  String get lessThanMinuteLeft;

  /// לפני שיש מספיק מדידה למהירות.
  String get speedPending;

  /// לא הגיע דיווח זמן מה — לא מציגים מהירות קפואה.
  String get speedStalled;
  String bytesLine(String name, String done, String total);
  String stageDone(String? size);
  String get stageWaiting;

  /// גודל צפוי לפי הבדיקה ברשת — [size] כבר מעוצב.
  String approxSize(String size);
  String downloadTotal(String size);

  /// ליד "ממתין", בזמן שבודקים כמה הספרייה תוריד.
  String get sizeChecking;
  String get cancelling;
  String get cancelledTitle;
  String get cancelledBody;

  /// [names] — הרכיבים שירדו עד הסוף, מחוברים לרשימה.
  String cancelledKeptBody(String names);
  String get cancelledRevertFailedBody;
  String get downloadAgain;
  String get backHome;
  String get retryNothingSnack;
  String get doneTitle;
  String get doneBody;

  /// לא ירד דבר — באתר אין חדש באף רכיב.
  String get doneNothingBody;
  String doneSkipped(String names);
  String doneAppValue(String version);
  String doneLibraryValue(int version);
  String donePluginsValue(int count);
  String get donePluginsUpdated;
  String get whatNow;
  String get whatNowEject;
  String get whatNowEjectHint;
  String get whatNowConnect;

  /// [toolName] מודגש במסך.
  String whatNowOpen(String toolName);
  String get updateHereToo;
  String get installHereToo;
  String get finish;
  String get networkTitle;

  /// החיבור המאובטח נדחה (תעודה) — לרוב מסנן אינטרנט, ו"נסה שוב" לא יעזור לבד.
  String get filterTitle;
  String filterBody(String name);
  String networkBody(String name);
  String get shabbatTitle;
  String get shabbatBody;
  String get spaceTitle;
  String spaceBody(String needed, String free);
  String get snapshotTitle;
  String get snapshotBody;
  String otherTitle(String name);
  String get otherBody;
  String get techDetails;
  String get hideTechDetails;
  String get copyDetails;
  String get detailsCopied;

  /// הכלי רץ כמנהל בחשבון אחר — ההתקנה תיכנס לפרופיל של המנהל.
  String get otherUserTitle;
  String otherUserBody({required bool firstInstall, String? account});
  String get otherUserHint;
  String get continueAnyway;
  String get closeTitle;
  String get closeBody;
  String closeHint({required bool plugins});
  String get closeAfterWizardBody;
  String get closeOtzariaAndContinue;
  String stepOf(int index, int count);
  String get installingApp;
  String get updatingApp;
  String get installingLibrary;
  String get updatingLibrary;
  String get sendingPlugins;
  String get appWizardFirstBody;
  String get appWizardBody;

  /// [lowMinutes]–[highMinutes] — האומדן לתוכנית, כשידוע.
  String libraryBody(int? lowMinutes, int? highMinutes);
  String get pluginsBody;
  String get keepDrive;
  String appVersion(String version);
  String appInstalled(String version);
  String get appWizardOpen;
  String get appStoppedWaiting;
  String get appSkipped;
  String get stopWaiting;
  String get libraryFull;
  String libraryVersion(int version);
  String libraryDone(String detail);
  String get libraryWaitingClose;
  String get librarySkipped;
  String pluginsWaiting(int count);
  String get pluginsCurrent;
  String get pluginsSent;
  String pluginsSentNames(String names);
  String pluginsNotSent(String names);
  String pluginsStillSending(String names);

  /// "הפסק להמתין" לאשף — התוספים לא נשלחים לגרסה שאולי עוד לא הותקנה.
  String get pluginsAfterInstall;
  String get pluginRowSent;
  String get pluginRowWaiting;
  String get pluginRowFailed;
  String get finishWithoutWaiting;
  String get installedTitle;
  String get updatedTitle;

  /// בנוי ממה שבאמת הושלם: [app], [library], [plugins] (נשלחו).
  /// [libraryNote] — הספרייה הותקנה, אבל יש הערה בשורה שלה.
  String doneHereBody({
    required bool firstInstall,
    required bool app,
    required bool library,
    required bool plugins,
    bool libraryNote = false,
  });

  /// אחרי "הפסק להמתין": לא ידוע אם ההתקנה הסתיימה.
  String get stoppedWaitingTitle;
  String stoppedWaitingBody(
      {required bool firstInstall, required bool libraryDone});

  /// האשף עוד רץ אחרי הזמן הקצוב — ההתקנה עשויה עוד להסתיים.
  String get wizardStillOpenTitle;
  String get wizardStillOpenBody;
  String get reindexTitle;
  String get reindexBody;
  String get reindexButton;
  String get toOtzaria;
  String get wizardClosedTitle;
  String wizardClosedBody(
      {required bool firstInstall, required bool libraryDone});
  String get stoppedTitle;
  String get stoppedBody;
  String get libraryFailedTitle;
  String get libraryInstallFailedTitle;
  String get appFailedTitle;
  String get libraryFailedKeep;
  String get appFailedKeep;

  /// כשל בשלב התוספים — אוצריא כבר הותקנה או עודכנה כש-[appDone].
  String get pluginsFailedTitle;
  String pluginsFailedKeep({required bool firstInstall, required bool appDone});

  /// כשל הרשאות: גוף ידידותי; ההודעה הגולמית בפרטים הטכניים.
  String get permissionFailedTitle;
  String get permissionInstallFailedTitle;
  String get permissionAppBody;
  String get permissionAppInstallBody;
  String get permissionLibraryBody;
  String get elevateTitle;
  String get elevateBody;
  String get elevateButton;

  String get toLibraryPage;
  String get toPluginsPage;
  String get showProgress;
}

// ── דפי הרכיבים ──

/// דפי התוכנה, הספרייה, הדיווחים ועדכון הכלי. הנוסח מהמוקאפ.
abstract class PageStrings {
  const PageStrings();

  String get advancedTitle;
  String get onThisComputer;
  String get onTheDrive;
  String get nothingYet;

  /// מה ברשת ועוד לא בכונן — רק כשהבדיקה ברשת הצליחה.
  String get onlineAvailable;
  String get nothingNewOnline;
  String downloadedOn(String date);
  String get chipUpdateOnDrive;
  String get chipUpToDate;
  String get lockedChip;
  String get appChipNotInstalled;
  String appWhatsNew(String version);

  /// מתחת לכותרת "מה חדש" כשאין עדכון — ההערות של הגרסה המותקנת.
  String get appInstalledNotesCaption;

  /// דף המשנה שנפתח מהאריח "תוכנת אוצריא" ומההגדרות.
  String get appAdvancedPageTitle;

  /// מותקנת הגרסה של הערוץ השני, חדשה מזו שנבחרה — לא מורידים גרסה.
  String appAwaitsNewer({required bool stable});

  /// כפתורים שמושבתים כי משימה ארוכה רצה במקום אחר.
  String get pageBusyNote;

  String appAdvancedSummary({required bool channel});
  String get appChannelTitle;
  String get appChannelBody;
  String get appReinstallTitle;
  String appReinstallBody(String version);
  String get appReinstallUnavailable;
  String get appLocationTitle;
  String get appSourceTitle;
  String get libSemanticSection;
  String libAdvancedSummary({required bool reindex});
  String get libMissingFilesTitle;
  String libChipCompanions(String names);
  String libVersion(int version);
  String get libNotInstalled;
  String get libInstallButton;
  String get libInstallWithAppButton;
  String get libInstallWithAppNote;
  String get libInstallNeedsApp;
  String get libUpdateNeedsApp;
  String get libUpdateButton;
  String get libNotFoundTitle;
  String get libNotFoundBody;
  String get libPickFolderButton;
  String get libSemanticTitle;
  String get libSemanticBody;
  String get libSemanticGrant;
  String get libSemanticClosedNote;
  String get libSemanticActive;
  String get libSemanticActiveBody;
  String get libLocationTitle;
  String get libLocationNone;
  String get libFullTitle;
  String libFullBody(String size);
  String get libFullBodyNoSize;

  /// הגודל והאומדן של הספרייה המלאה, ליד הכפתור שמתקין אותה.
  String libFullMeta({String? size, int? lowMinutes, int? highMinutes});
  String get libFullUnavailable;
  String get libPersonalReadOnly;
  String get libSourceTitle;
  String get repDescription;
  String get repSendingTitle;
  String repWaitingTitle(int count);
  String repWaitingBody({required bool withSearch});
  String repStoredTitle(int count);
  String get repStoredBody;
  String get repUncheckedBody;
  String get repOnlyOnline;
  String get repCheckConnectionButton;
  String repAlsoStored(int count);
  String get repNothingTitle;
  String get repSendButton;

  /// בכרטיס האיסוף — שליחת מה שכבר בכונן, בלי לאסוף קודם.
  String repSendStoredButton(int count);
  String get repWhatIsSent;
  String repOwnPending(int count);
  String get repOwnTitle;
  String get repOwnEmpty;

  /// פירור הלחם של דף הדיווחים — קצר מהכותרת.
  String get repCrumb;
  String get repProblemSection;
  String get repProblemTitle;
  String get repProblemBody;
  String get selfCrumb;
  String get selfTitle;
  String get selfDescription;
  String selfChipOnline(String version);
  String selfChipOnDrive(String version);
  String get selfChipUpToDate;
  String get selfCurrentVersion;
  String get selfNewVersion;
  String get selfDownloadButton;
  String selfDownloading(int percent);
  String get selfInstalling;
  String get selfErrorTitle;
  String get selfDownloadFailed;
  String get selfCheckFailed;
  String get selfInstallFailed;
  String get selfErrorKeepsWorking;
  String get selfManualTitle;
  String get selfOpenFolder;
  String get selfAdminTitle;
  String get selfAdminBody;
  String get selfReadOnly;
  String selfWhatsNew(String version);
}

// ── דף הבית: הכוונה לפי המצב ───────────────────────────────────────────────────

/// דף הבית: הגיבור ("מה לעשות עכשיו"), האריחים, ההודעות שבמקום דיאלוגי העלייה,
/// שורת התחתית ומסך הפתיחה של כונן ריק. כל מספר מופיע בטקסט גם ב-1.
abstract class GuidanceStrings {
  const GuidanceStrings();

  // ── שורת "המחשב הזה" שמעל הכותרת ──
  String get eyebrowOnline;
  String get eyebrowOffline;

  /// כשעוד לא ידוע אם יש אינטרנט — בלי לנחש.
  String get eyebrowThisComputer;
  String eyebrowOtzaria(String version);
  String get eyebrowNotInstalled;

  // ── הגיבור ──
  String get checkingTitle;
  String get checkingBody;
  String get installHereTitle;
  String get installHereBody;
  String get installHereButton;
  String get updateHereTitle;
  String get updateHereBody;
  String get updateHereButton;
  String get whatsNewButton;
  String get downloadTitle;
  String get downloadBody;
  String get downloadButton;

  /// [version] — גרסת אוצריא שבכונן, כשהיא חלק מהעדכון.
  String updateHereTooNote(String? version);

  /// מה שכבוי בהגדרות ולכן לא יירד.
  String syncOffNote({
    required bool app,
    required bool library,
    required bool plugins,
  });
  String get noSyncSelectionNote;

  /// כמו [syncOffNote], כשאין שום הורדה לצידה: יש חדש, וההורדה שלו כבויה.
  /// [libraryFilesOnly] — בספרייה חדשים רק הקבצים הנלווים, לא גרסת המסד.
  String syncOffOnlyNote({
    required bool app,
    required bool library,
    required bool plugins,
    bool libraryFilesOnly = false,
  });

  /// "הורדה" בזמן שמשימה אחרת (או הורדת עדכון של הכלי) רצה.
  String get downloadBusySnack;
  String get changeInSettingsLink;
  String get chooseInSettingsLink;
  String get libraryRetryNote;

  /// "לשאול כל פעם" בהגדרות: חיפוש חכם לבדו הוא שורה שקטה, לא "יש חדש".
  String get semanticOfferNote;
  String get semanticOfferLink;

  /// "הורדה" שהבדיקה המחודשת שלפניה לא מצאה בה דבר — במקום מסך "לא ירד דבר".
  String get recheckNothingTitle;

  /// [upToDate] — `false` כשבכונן חסר משהו שנבחר לא להוריד (חיפוש חכם).
  String recheckNothingBody(String time, {required bool upToDate});
  String recheckNothingNote(String time);

  /// אותו מצב בלי בדיקה חדשה: לפי הבדיקה הקודמת, ובשעה שלה.
  String get nothingNewTitle;
  String nothingNewBody(String time, {required bool upToDate});
  String nothingNewNote(String time);

  /// קבצים שנכשלו בהורדה האחרונה — לא מוצעים שוב עד "נסה שוב" או בדיקה ידנית.
  String failedDownloadsNote(String names);

  /// כל רכיב שנבחר נבדק ברשת בלי חדש — במחשב מחובר בלבד.
  String get upToDateTitle;
  String upToDateBody(String? version);

  /// מה שידוע בלי בדיקה ברשת: מה שבכונן כבר מותקן. במחשב לא מחובר אין כאן
  /// שום מילה על הרשת.
  String get driveInstalledTitle;
  String driveInstalledBody(String? version);

  /// "הכול מעודכן" שליד "עדכון זמין" בשורת המצב, או תוכנות נוספות שמחכות.
  String get othersPendingTitle;
  String get otherLauncherTitle;
  String otherLauncherOnline(String version);
  String otherLauncherOnDrive(String version);

  /// כשל חלקי: המחשב מחובר, ובדיקה של רכיב שנבחר נכשלה. [appFailed] וכו' —
  /// מה לא נבדק; [appChecked] וכו' — מה נבדק ונמצא מעודכן.
  String get checkFailedTitle;
  String checkFailedBody({
    required bool appFailed,
    required bool libraryFailed,
    required bool pluginsFailed,
    required bool appChecked,
    required bool libraryChecked,
    required bool pluginsChecked,
  });
  String get launchButton;
  String get recheckButton;
  String get offlineNote;
  String get checkOnlineNowNote;
  String get newerTitle;
  String newerChannelTitle({required bool stable});
  String newerBody(String installed, String onDrive);
  String get newerNote;
  String get attentionAppTitle;
  String get attentionLibraryTitle;
  String get attentionBody;
  String get attentionLibraryButton;
  String get taskDownloadingTitle;
  String get taskDownloadingBody;
  String get taskInstallingAppTitle;
  String get taskUpdatingLibraryTitle;
  String get taskBusyTitle;
  String get taskBusyBody;
  String get taskNamedBody;
  String get taskSyncingPluginsTitle;
  String get taskUpdatingPluginsTitle;
  String get taskExportingStoreTitle;
  String get taskDownloadingCustomAppsTitle;
  String get taskCustomAppsTitle;
  String get taskInstallingLauncherTitle;
  String get taskRestartingElevatedTitle;

  // ── רשימת מה ייכלל ──
  String itemUpdateTo(String version);
  String itemLibraryUpdateTo(int version);
  String get itemLibraryUpdate;
  String get itemLibraryFull;
  String itemPluginUpdates(int count);
  String itemPlugins(int count);
  String get itemPluginsCatalog;

  /// גרסה חדשה לחנות התוספים שבאוצריא — בלי מספר: אינה רכיב שהמשתמש מכיר.
  String get itemStoreApp;
  String itemPluginsWithStore(int count);

  /// חסם עליון שידוע לפני ההורדה; [size] מ-`formatBytes`.
  String itemUpTo(String size);

  /// סכום החסמים, ו"ועוד" לכל רכיב שאין לו חסם.
  String downloadTotal(
    String size, {
    required bool plusApp,
    required bool plusLibrary,
    required bool plusPlugins,
  });
  String driveFree(String size);

  // ── הודעות ופסים ──
  String get otzariaOpenTitle;
  String get otzariaOpenBody;

  /// כשאין מה להתקין כאן — ואז יש בפס "סגירת אוצריא".
  String get otzariaOpenIdleBody;

  /// לפני [otzariaOpenBody] כשההתקנה האוטומטית דילגה בגלל אוצריא הפתוחה.
  String get autoInstallSkippedLead;
  String newPluginsTitle(int count);

  /// [names] — שמות התוספים, עד שלושה; [more] — כמה עוד יש מעבר להם.
  String newPluginsBody(List<String> names, int more);
  String get toPluginsButton;

  /// הודעות הספרייה בבית — בלי "אינטרנט", גם במחשב לא מחובר.
  String libraryMissingFilesBody(String names);
  String get libraryCompanionsAbsentBody;
  String get semanticConsentBody;

  // ── האריחים ──
  String get tilesLabel;
  String get tileApp;
  String get tileLibrary;
  String get tilePlugins;
  String get tileCustomApps;
  String get tileReports;
  String get chipReadyToInstall;
  String get chipNewerHere;
  String get chipNotOnDrive;
  String get chipChecking;
  String get chipInstalling;
  String get chipUpdating;
  String get chipAttention;
  String get chipLibraryUpToDate;
  String chipPluginUpdates(int count);
  String chipPluginsInstalled(int count);
  String chipPluginsOnDrive(int count);
  String get chipNoPlugins;
  String chipAppsPending(int count);
  String chipAppsInstalled(int count);
  String chipReportsToSend(int count);
  String chipReportsToCollect(int count);
  String get chipReportsSending;
  String get chipReportsLocked;

  /// רכיב שההורדה לכונן תביא — כמו "מה ייכלל" בגיבור.
  String get chipNewOnline;

  /// שורות העובדות שבאריחי התוכנה והספרייה.
  String tileFactHere(String value);
  String tileFactDrive(String value);
  String tileFactOnline(String value);
  String tileFactVersion(String version);

  /// הכפתור שבשורת המצב כשיש גרסה חדשה של הכלי עצמו.
  String get updateAvailableButton;

  // ── שורת התחתית ──
  String launcherOnline(String version);
  String launcherOnDrive(String version);
  String get launcherDownloading;
  String checkedAt(String time);
  String get recheckHint;
  String get checkNowLink;
  String drive(String letter);
  String get driveReadOnlySuffix;
  String get driveFullSuffix;

  // ── מסך הפתיחה ──
  String get welcomeTitle;
  String get welcomeLeadOnline;
  String get welcomeLeadOffline;
  String step(int number);
  String get youAreHere;
  String get step1Title;
  String get step1BodyOnline;
  String get step1BodyOffline;
  String get step2Title;
  String get step2Body;
  String get step3Title;
  String get step3BodyOnline;
  String get step3BodyOffline;
  String get welcomeDownloadButton;
  String get welcomeDownloadNote;
  String get welcomeHelpButton;
  String get welcomeOfflineNote;

  /// מה עוד יש בכונן ריק מאוצריא — קישורים לדפים שלהם.
  String get welcomeAlsoOnDrive;

  // ── דף הדיווחים ──
  String reportsCollectTitle(
      {required int reports, required int searchRecords});

  /// הגילוי שמעל כפתור האיסוף: מה יועתק לכונן, איך נשמר ולמי נשלח.
  String get reportsCollectBody;
  String get reportsDisclosureReports;
  String get reportsDisclosureSearch;
  String get reportsDisclosureStorage;
  String get reportsCollectButton;
  String get reportsNothing;
  String reportsLockedNote({required bool driveFull});
}

// ── מסך תוכנת אוצריא ──────────────────────────────────────────────────────────

abstract class AppScreenStrings {
  const AppScreenStrings();

  String get readyToInstall;

  String get installedVersion;
  String get noInstallDetected;
  String get pickInstallDirButton;
  String get pickInstallDirDialogTitle;
  String get installAdoptedSnack;
  String get installNotFoundSnack;

  String get mirrorEmpty;
  String channelPair(String stable, String prerelease);

  String get channelStable;
  String get channelPrerelease;

  String get launchButton;

  /// התקנה חוזרת של אותה גרסה — מוצעת דווקא כשהכול מעודכן, כדי לתקן התקנה
  /// פגומה בלי להמתין לגרסה הבאה.
  String get reinstallButton;
}

// ── מסך הספרייה ───────────────────────────────────────────────────────────────

abstract class LibraryScreenStrings {
  const LibraryScreenStrings();

  String get pickDbButton;
  String get pickDbDialogTitle;
  String get dbPathUpdatedSnack;

  /// בחירת המיקום שאליו תותקן ספרייה חדשה, וההסבר החובה כשהוא אינו מיקום
  /// שאוצריא מחפשת בו בעצמה.
  String get pickInstallDirButton;
  String get pickInstallDirDialogTitle;
  String get installDirUpdatedSnack;
  String get customLocationDialogTitle;
  String customLocationPrompt(String dbPath);
  String get customLocationConfirm;

  String get updatingProgress;

  /// "מה חדש בספרייה" — `library-changes.md` של הגרסאות שבטווח העדכון.
  String get changesTitle;
  String changesPendingSubtitle(String version);
  String changesAppliedSubtitle(String version);

  /// הטווח ארוך ממה שיש על הכונן: חלק מהגרסאות בלי רשימה, או מעבר לעשר.
  String changesPartial(int shown, int total);
  String get changesButton;
  String get changesNotFound;

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

  String get mirrorEmpty;
  String get mirrorUnreadable;

  /// המראה לא נבדקה, כי הבדיקה נעצרה כבר בקריאת המסד המקומי.
  String get mirrorNotChecked;
  String mirrorHasVersion(String version);
  String get mirrorPresent;

  String get personalVersionButton;
  String personalVersionCapturedSnack(String version);
  String get personalVersionNotFoundSnack;

  /// המראה נבנתה לעדכון אישי של מחשב אחר. לא שגיאה — המחשב הזה רק הוריד,
  /// ואין לו מה להתקין מהתיקייה הזו.
  String get personalOtherMachineTitle;
  String personalOtherMachineSubtitle(String version);
  String get personalOtherMachineSettingsButton;

  /// השאלה בהפעלה הראשונה של כונן: למי מורידים את ספריית אוצריא.
  String get personalAskTitle;
  String get personalAskMultiple;
  String get personalAskMultipleBody;
  String get personalAskMine;
  String get personalAskMineBody;
  String get personalAskLater;

  /// הערה שקטה בבית אחרי שהמחשב הזה נרשם.
  String get personalPreparedHere;
  String get personalPendingNote;
  String get personalPendingRegisterNote;
  String get personalChipElsewhere;
  String get personalChange;

  /// השורה בכרטיס של דף הספרייה, כשמורידים רק את מה שחסר.
  String personalCardThis(String version);
  String personalCardThisAndOthers(int others, String version);
  String personalCardOthers(int count, String version);
  String get personalCardNone;

  /// שורת ספריית אוצריא ברשימת ההורדה, וההערה שמתחת לכפתורים.
  String personalDownloadItem(int count, String version);
  String get personalDownloadItemNone;
  String personalDownloadNote(int count);
  String get downloadNoteTitle;

  /// הספרייה לא הורדה כי אין בכונן מתקין אוצריא שקורא אותה.
  String get downloadNeedsOtzariaInstaller;

  /// גרסת ספרייה חדשה יותר נשארה ברשת: המתקינים שבכונן אינם קוראים אותה.
  String downloadNewerNeedsOtzaria(String version);

  /// בכונן כבר יש ספרייה חדשה ממה שהמתקינים שבו קוראים, והיא נשארה.
  String get downloadKeptNewerMirror;

  /// חלק מנתוני העדכון לא נקרא — לא ידוע אם יש ספרייה חדשה שאפשר להביא.
  String get downloadMetadataUnreadable;
}

// ── מסך ההגדרות ───────────────────────────────────────────────────────────────

abstract class SettingsScreenStrings {
  const SettingsScreenStrings();

  String get title;

  // ── קבוצות ──
  String get groupGeneral;
  String get groupPrivacy;
  String get groupAbout;

  /// מה מקופל תחת "מתקדם" — שורה אחת מתחת לכותרת.
  String get advancedSummary;

  // ── שפה ──
  /// גם כותרת הדו-שיח שבוחרים בו.
  String get languageTitle;
  String get languageSystem;

  /// בדו-שיח השפה בלבד: "כמו במחשב" עם השפה שהיא מתורגמת אליה בפועל.
  String languageSystemAs(String language);
  String get languageHebrew;
  String get languageEnglish;

  // ── בדיקה והתקנה אוטומטיות ──
  String get autoCheckTitle;
  String get autoCheckSubtitle;

  /// שאלה אחת לתוכנה ולספרייה גם יחד.
  String get autoInstallTitle;
  String get autoInstallSubtitle;
  String get autoInstallDialogTitle;
  String get autoInstallDialogContent;
  String get autoInstallDialogConfirm;

  // ── מה להוריד לכונן ──
  /// שבבי סימון, אחד לכל רכיב.
  String get syncTargetsTitle;
  String get syncTargetsSubtitle;
  String get syncTargetApp;
  String get syncTargetLibrary;
  String get syncTargetPlugins;

  /// נוסף לשורה, וגם הסבר צף לשבב, כשעדכון למחשב מסוים נועל את "הספרייה".
  String get syncLibraryLockedSubtitle;

  /// חיפוש חכם בהורדה: לשאול / תמיד / לא.
  String get semanticDownloadTitle;
  String get semanticDownloadSubtitle;
  String get semanticDownloadAsk;
  String get semanticDownloadAlways;
  String get semanticDownloadNever;

  /// ההסכמה לחיפוש החכם באוצריא שבמחשב הזה. ביטול — רק בהגדרות של אוצריא.
  String get semanticConsentRowTitle;
  String get semanticConsentRowOn;
  String get semanticConsentRowOff;
  String get semanticConsentRowEnable;

  // ── בשביל איזה מחשב מורידים ──

  String get personalModeDialogTitle;
  String get personalModeDialogContent;
  String get personalModeDialogConfirm;
  String get personalGroupTitle;
  String get personalMachineThis;
  String get personalMachineUnnamed;
  String personalMachineVersion(String version);
  String personalMachineFloor(String version);
  String get personalMachineRemove;
  String get personalMachinesNone;
  String personalMachineName(String machineName);
  String personalMachineThisSubtitle(String machineName, String version);
  String get personalMachineNotHere;
  String get personalMachinesReadOnly;
  String get personalRemoveTitle;
  String get personalRemoveBody;
  String get personalRemoveThisBody;

  // ── מתקדם ──
  String get faqEditTitle;
  String get faqEditSubtitle;

  String get logTitle;
  String get logSubtitle;
  String get openLogFolderButton;

  String get resetTitle;
  String get resetSubtitle;
  String get resetButton;
  String get resetDialogTitle;
  String get resetDialogContent;
  String get resetDialogConfirm;
  String get resetDoneSnack;

  // ── אודות ──
  String aboutTitle(String version);

  /// כשאין גרסה חדשה ידועה — הדף עצמו אומר אם יש.
  String get aboutSubtitle;
  String aboutNewVersion(String version);
}

// ── מצב סייפר ─────────────────────────────────────────────────────────────────

/// נעילת ההגדרות בסיסמה. מלל משלו ולא בתוך [SettingsScreenStrings], כי הוא
/// מופיע גם מחוץ למסך ההגדרות — בכניסה אליו, ובמעבר לעריכת השאלות הנפוצות.
abstract class SaferModeStrings {
  const SaferModeStrings();

  // ── השורות שבהגדרות › מתקדם ──
  String get lockTitle;

  /// כשעוד אין סיסמה — אין מה להפעיל, ולכן במקום המתג יש כפתור.
  String get noPasswordSubtitle;
  String get setPasswordButton;
  String get lockOnSubtitle;
  String get lockOffSubtitle;
  String get passwordRowTitle;
  String get passwordRowSubtitle;

  /// אי אפשר למחוק סיסמה כשהנעילה פעילה — זו הייתה דלת אחורית מתוך הנעילה.
  String get passwordRowLockedSubtitle;
  String get changeButton;
  String get clearButton;
  String get enabledSnack;
  String get disabledSnack;

  // ── בקשת הסיסמה ──
  String get verifyTitle;

  /// למה מבקשים את הסיסמה עכשיו — משפט אחד לכל מקום שנעול.
  String get verifySettingsHint;
  String get verifyFaqHint;
  String get verifyEnableHint;
  String get verifyDisableHint;

  /// כפתור האישור כשהסיסמה פותחת דף (הגדרות, עריכת השאלות).
  String get enterButton;
  String get passwordLabel;
  String get wrongPassword;
  String get passwordRequired;
  String get showPasswordTooltip;
  String get hidePasswordTooltip;

  // ── קביעה והחלפה ──
  String get setTitle;

  /// [onThisComputer] — בכונן מוגן ההגדרות נשמרות במחשב ולא בכונן.
  String setIntro(int minLength, {bool onThisComputer = false});
  String get setConfirm;
  String get changeTitle;
  String get currentPasswordLabel;
  String get newPasswordLabel;
  String get confirmPasswordLabel;
  String passwordTooShort(int minLength);
  String get passwordsDoNotMatch;
  String get passwordSetSnack;
  String get passwordChangedSnack;

  // ── מחיקה ──
  String get clearDialogTitle;
  String get clearDialogContent;
  String get passwordRemovedSnack;
}

// ── חנות התוספים ──────────────────────────────────────────────────────────────

abstract class PluginsStrings {
  const PluginsStrings();

  String get syncFailedSnack;

  /// [fetched] הוא מה שבאמת ירד עכשיו, מתוך [total] שבחנות — הסנכרון מדלג
  /// על כל מה שכבר מעודכן במראה, וההודעה חייבת לומר את זה.
  String syncDoneSnack(int fetched, int total);

  /// סנכרון שהסתיים אך פריטים בודדים בו נכשלו — ראו `syncWarnings`.
  String syncDoneWithWarningsSnack(int count);
  String get syncingOverlayStarting;
  String get syncDirUnknownTooltip;

  String get saveDialogTitle;
  String get saveDoneSnack;
  String get saveFailedSnack;

  /// אחרי שהסריקה הוכיחה שאוצריא סיימה — ולא כשהמסירה אליה הצליחה.
  String installDoneSnack(String pluginName);
  String installCancelledSnack(String pluginName);
  String installRejectedSnack(String pluginName, String? reason);
  String get installFailedSnack;

  String get loadingCatalog;

  String get noResultsTitle;
  String get noResultsBody;

  // ── שורת הסינון ─────────────────────────────────────────────────────────
  String get filterStatusLabel;
  String get filterSortLabel;
  String get sortRecommended;
  String get sortNewest;
  String get sortUpdated;
  String get filterTagsLabel;
  String get showMoreTags;
  String get showFewerTags;

  // ── כרטיס ועמוד התוסף ───────────────────────────────────────────────────
  String pluginVersionBadge(String version);

  // ── דירוג המשתמשים ──────────────────────────────────────────────────────
  // תצוגה בלבד. הדירוג עצמו נעשה באתר (דורש חשבון), ואין כאן דרך לדרג.
  String ratingBadge(String average, int count);
  String ratingTooltip(int count);
  String get ratingPanelTitle;
  String ratingCountLabel(int count);
  String ratingVerifiedLabel(int count);
  String get ratingVerifiedTooltip;
  String get ratingEmpty;
  String ratingStarsLabel(String average);

  String get sourcePageButton;

  String get statusStable;
  String get statusExperimental;
  String get statusUnknown;

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
  String get valueUnspecifiedMasculine;

  // ── גלריית צילומי המסך ──────────────────────────────────────────────────
  String get screenshotPrevious;
  String get screenshotNext;

  // ── תוכנת החנות העצמאית ─────────────────────────────────────────────────
  // החנות כתוכנת ווינדוס עצמאית, עם התוספים שבכונן (Otzaria_Website#171).
  String get storeAppButton;
  String get storeAppDialogTitle;
  String get storeAppDialogBody;
  String get storeAppHighlightBundled;
  String get storeAppHighlightOffline;
  String get storeAppHighlightDirect;
  String get storeAppChipWindows;
  String storeAppChipSize(String size);
  String storeAppChipUpdated(String date);
  String get storeAppChooseFolder;

  /// הכפתור מושבת — אין מה להעתיק. שתי סיבות נפרדות, כי הפעולה הנדרשת
  /// שונה: להוריד תוספים, או להוריד במחשב מקוון בכלל.
  String get storeAppUnavailableTooltip;
  String get storeAppNoPluginsTooltip;

  String get storeAppPickFolderTitle;

  /// ביעד כבר יושבת חנות — מעדכנים במקום, ולא מוחקים מה שאיננו מכירים.
  String get storeAppOverwriteTitle;
  String storeAppOverwriteContent(String path);
  String get storeAppOverwriteConfirm;

  /// החנות כבר הועתקה לתיקייה ידועה והמראה חדשה ממנה — מציעים לעדכן שם.
  String get storeAppUpdateButton;
  String get storeAppUpdateHereTitle;
  String storeAppUpdateHereContent(String path);
  String get storeAppChooseOtherFolder;
  String get storeAppInUseSnack;

  String get storeAppCopyingTitle;

  String get storeAppDoneTitle;
  String storeAppDoneContent(int plugins, String size);

  /// תוספים שנכס שלהם חסר במראה ולכן הושמטו — לא כשל, אבל ראוי שייאמר.
  String storeAppDoneSkipped(int count);
  String get storeAppOpenFolder;
  String get storeAppLaunch;
  String storeAppFailedSnack(String error);

  /// הפעלת החנות שהועתקה נכשלה. קובץ חסר הוא הסיבה השכיחה, ולכן ההודעה
  /// אינה נבלעת: כפתור שלא עושה דבר נראה כתקלה בלאנצ'ר.
  String storeAppLaunchFailedSnack(String error);

  // ── החנות: עמוד, סינון, כרטיס ופרטים ──
  String get storeTitle;
  String get storeSubtitle;
  String asOfDate(String date);
  String get refreshButton;
  String get syncingTitle;
  String get syncingHint;
  String get syncStopButton;
  String get syncStoppedSnack;
  String get emptyTitle;
  String get emptyBodyOnline;
  String get emptyBodyOffline;
  String get searchHint;
  String get clearSearchTooltip;
  String get filterAll;
  String get filterInstalled;
  String get filterNotInstalled;
  String get moreFilters;
  String moreFiltersCount(int count);
  String noResultsForQuery(String query);
  String get clearFiltersButton;
  String updatesAvailable(int count);
  String updatesBarNames(String names);

  /// "א, ב ו-ג" — רשימת שמות במשפט.
  String joinNames(List<String> names);
  String get updateAllButton;
  String updatingAllLabel(int current, int total);
  String updatesSentSnack(int count);
  String updateAllNoneSentSnack(String names);
  String updateAllPartlySentSnack(int sent, String names);
  String updateAllStoppedSnack(int sent);

  /// נעצר לפני שנשלח דבר — אישור שהעצירה נקלטה.
  String get updateAllStoppedNoneSnack;

  /// לפני הודעת הכישלון, כשהריצה גם נעצרה.
  String get updateAllStoppedPrefix;
  String get updateAllStoppingLabel;
  String get actionsBlockedSyncing;
  String get actionsBlockedExporting;
  String get actionsBlockedUpdatingAll;
  String get actionsBlockedElsewhere;
  String get howItWorksButton;
  String get updatesSentTitle;
  String get updatesSentBody;
  String installSentSnack(String pluginName);
  String get newChip;
  String get networkChip;
  String get installInOtzariaButton;
  String updateToButton(String version);
  String get saveFileButton;
  String get sendingLabel;
  String get sentLabel;
  String get developmentLabel;
  String get incompatibleLabel;
  String get disabledLabel;
  String get installedLabel;
  String get noteIncompatible;
  String noteNeedsApp(String version);
  String get noteNeedsOtzaria;
  String get noteSaveOnly;
  String get noteDisabled;
  String get noteFileMissing;
  String get noteFileMissingOnline;
  String get fileNotOnDriveLabel;
  String get noteNextDriveDownload;
  String get incompatibleTitle;
  String incompatibleBodyVersions(String needs, String here);
  String get incompatibleBody;
  String get disabledTitle;
  String get disabledBody;
  String get disabledUpdateBody;
  String get developmentTitle;
  String get developmentBody;
  String get fileMissingTitle;
  String get fileMissingBody;
  String get factRating;
  String get factCompatible;
  String get factYes;
  String get factNo;
  String factOtzariaVersion(String version);
  String get factVersionLatest;
  String get factVersionInstalled;
  String factVersionInstalledAt(String version);
  String get factNetworkAny;
  String get factNetworkSome;
  String get factSize;
  String get factOnDrive;
  String get factNotOnDrive;
  String get descriptionTitle;
  String get versionsTitle;
  String get versionLatestTag;
  String get versionInstalledTag;
  String get infoDownloads;
  String get infoSource;
  String get copyAddressTooltip;
  String get addressCopiedSnack;
  String get ratingSourceNote;
  String ratingAsOfNote(String date);
  String get screenshotZoom;
  String screenshotNumber(int index, int total);
  String get advancedSummary;
  String get storeAppCopyButton;
  String get storeAppRowBody;
  String get reloadRowTitle;
  String get reloadButton;
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

  // ── איש הקשר ────────────────────────────────────────────────────────────
  /// מוצג רק כשמולאו שם או טלפון — "אפשר לפנות" בלי למי אינו עוזר.
  String get contactTitle;

  /// אותו איש קשר בשורה אחת בתחתית הבית, לפני השם והטלפון.
  String get contactLead;

  // ── עריכה ───────────────────────────────────────────────────────────────
  /// עריכת דף העזרה — למי שמכין כונן לאחרים.
  String get editButton;
  String get editDoneButton;
  String get editTitle;
  String get editIntro;

  /// בכונן מוגן ההתאמות נשמרות במחשב הזה ולא בכונן.
  String get editIntroThisComputer;

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

  /// מתחת לשדות: אין כפתור שמירה.
  String get contactAutoSaveNote;
  String get contactNameLabel;
  String get contactPhoneLabel;
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
  String get driveFull;
  String get driveFullTitle;
  String get appTranslocated;
  String get appTranslocatedTitle;
  String get runningFromTemp;
  String get runningFromTempTitle;
  String get systemDrive;
  String get systemDriveTitle;

  /// macOS (TCC) חסם כתיבה לתיקייה שליד התוכנה — EPERM, לא הרשאות קובץ.
  String get macVolumeAccessDenied;
}

// ── כונן מוגן-כתיבה: מצב קריאה ────────────────────────────────────────────────

/// הכונן מוגן מפני כתיבה אך נושא מראה שנמלאה — ההתקנות עובדות (הן כותבות
/// למחשב), וההורדות כבויות. ראו `AppPaths.readOnly`.
abstract class ReadOnlyDriveStrings {
  const ReadOnlyDriveStrings();

  String get bannerTitle;
  String get bannerSubtitle;

  /// נאמר כשמסלול שדורש כתיבה לכונן נחסם — הורדה או עדכון הלאנצ'ר עצמו.
  String get downloadsDisabledSnack;

  /// Shown on the custom-apps settings card: managing apps writes to the drive.
  String get customAppsManageDisabled;
  String get bannerTitleDriveFull;
  String get bannerSubtitleDriveFull;
  String get downloadsDisabledSnackDriveFull;
  String get customAppsManageDisabledDriveFull;
}

// ── הרשאות מנהל ───────────────────────────────────────────────────────────────

/// תיקייה שהלאנצ'ר צריך לכתוב אליה ואינו מורשה — אוצריא ב-`Program Files`
/// היא המקרה השכיח. ראו `Elevation`.
abstract class ElevationStrings {
  const ElevationStrings();

  /// נתלה בסוף הודעת השגיאה עצמה, ולכן מנוסח כהמשך שלה.
  String get hint;

  /// אותו תפקיד ב-macOS, ששם אין "הפעל כמנהל": התוכנה אינה יכולה להרים את
  /// עצמה, והפעולה שפותרת היא אחרת לגמרי — לבחור מיקום שהחשבון יכול לכתוב
  /// אליו, או לתת לתוכנה גישה מלאה לדיסק בהגדרות המערכת.
  String get macHint;

  /// הפס בדף הבית כשפעולה נכשלה על הרשאות.
  String get bannerTitle;
  String get bannerContent;
  String get bannerConfirm;
  String get bannerDismiss;

  /// ההרמה עצמה נכשלה (למשל PowerShell חסום) — נשארת הדרך הידנית.
  String restartFailedSnack(String error);

  String get busyNotice;
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

  // ── שורת העדכון בתחתית הבית, וגרסת הכלי בהגדרות ───────────────────────────
  String installedVersion(String version);

  String get installButton;

  // ── דיאלוג "ההורדה הושלמה" ──────────────────────────────────────────────
  String get readyDialogTitle;
  String readyDialogContent(String version);
  String get readyDialogConfirm;

  String downloadedSnack(String version);
  String get installingSnack;

  /// ב-macOS ההחלפה מסתיימת בלי הפעלה מחדש אוטומטית — ראו
  /// `LauncherSelfInstaller`.
  String get manualRestartNotice;

  /// ההחלפה מסתיימת ב-`exit(0)`, ולכן היא נחסמת בזמן הורדה או התקנה.
  String get busyNotice;

  /// הגרסה מוכנה אך אין לנו את קובץ ההרצה להחליף — הכרטיס אומר זאת במקום
  /// להציג את עצמו בלי אף כפתור.
  String get installUnavailableNotice;

  // ── מה התחדש ────────────────────────────────────────────────────────────
  /// הכותרת שמעל יומן השינויים בדיאלוגים של הגרסה החדשה.
  String get whatsNewHeading;

  // ── הגדרות ──────────────────────────────────────────────────────────────
  String get changelogButton;
  String get changelogDialogTitle;
  String get changelogNotFound;

  // ── שגיאות ──────────────────────────────────────────────────────────────
  /// אין לנו את הנתיב של קובץ ההרצה שהמשתמש מפעיל, ולכן אין מה להחליף.
  String get executableNotFound;
  String get mirrorMissing;
  String unsupportedPlatform(String operatingSystem);
  String downloadFailed(int statusCode);
  String sizeMismatch(int received, int expected);
  String replaceFailed(String error);
  String replaceFailedNotRestored(
    String error,
    String previousPath,
    String executableName,
  );
  String restartFailed(String error);
  String restartFailedRolledBack(String error);
  String get digestMismatch;
}

// ── יחידות ומספרים ────────────────────────────────────────────────────────────

abstract class UnitStrings {
  const UnitStrings();

  String bytes(int count);
  String progressOf(String received, String total);

  /// KB/MB/GB לטיניות בשתי השפות, כמו במוקאפ. בעברית הצירוף מבודד (LRI…PDI)
  /// עם רווח קשיח — אחרת ה-bidi מציג "MB 403".
  String kilobytes(String amount);
  String megabytes(String amount);
  String gigabytes(String amount);

  /// [size] — גודל מעוצב: "6.8 MB/s".
  String perSecond(String size);

  /// תאריך מלא בשם חודש לועזי: "18 באוקטובר 2026" / "October 18, 2026".
  String longDate(int day, int month, int year);
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
  String get exportPersonalMirrorDamaged;
  String get exportKeptNewerMirror;

  /// הבדיקה הקלה אינה קוראת מניפסטים, ובלעדיהם לא ידוע לאיזו ספרייה מתאים
  /// החיפוש החכם שאוצריא שבכונן קוראת.
  String get semanticTargetUnknown;

  /// המסד המלא שכבר במראה נשמר, כי יש ממנו מסלול patches לגרסה האחרונה.
  String exportReusingFullDb(int version, String tag);

  String exportDownloading(String tag, String asset);

  /// אימות sha256 של נכס שכבר על הכונן — דקה שלמה שבה מד הבייטים אינו זז,
  /// ולכן האחוז נמסר כאן.
  String exportVerifying(String tag, String asset, int percent);

  /// חיבור חלקי ה-DB המפוצל לקובץ אחד על הכונן — קריאה וכתיבה, לא רשת.
  String exportAssembling(String tag, String asset, int percent);

  /// מסד מלא מפוצל שהמניפסט שלו פגום או אינו תואם לחלקים — הוא נחשב כאילו
  /// אינו קיים, ומסד מלא אחר נבחר במקומו.
  String exportSplitFullDbSkipped(String tag, String detail);

  String exportSplitPartCorrupted(String asset, String parts);

  /// הקובץ המורכב לא הועבר למקומו — בדרך כלל יעד נעול.
  String exportAssembledReplaceFailed(String path, String detail);
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

  /// ה-patch בנוי על סכמה שאינה ניתנת להחלה — הוא אינו נכנס למראה.
  String exportSkippingUnappliablePatch(
    String tag,
    String file,
    int schemaVersion,
  );

  /// אותו דבר, על ציר פורמט ה-`patch.db` (ראו `kSupportedPatchFormatVersion`).
  String exportSkippingUnsupportedPatchFormat(
    String tag,
    String file,
    int patchFormatVersion,
  );

  /// סכמה חדשה בגרסה האחרונה — המראה מקבלת DB מלא במקום patches.
  String exportFullDbRequiredBySchema(int schemaVersion, int latestVersion);

  /// אותו דבר, כשהחוסם הוא פורמט ה-patch ולא סכמת ה-DB.
  String exportFullDbRequiredByPatchFormat(
    int patchFormatVersion,
    int latestVersion,
  );

  String exportFullDbSchemaUnsupported(String tag, int schemaVersion);

  /// קובצי עדכון שהושמטו מהמראה כי המסד המלא מגיע גבוה מהם ממילא.
  String exportSkippingPatchesFullDbWins(int fileCount, int fullDbVersion);

  /// קובץ עדכון שהחלתו אצל המשתמש ארוכה מהחלפת המסד המלא כולו — אינו נכנס
  /// למראה, והמסד המלא יורד במקומו.
  String exportFullDbInsteadOfSlowPatches(
    int fileCount,
    int patchMinutes,
    int fullDbMinutes,
    int toVersion,
  );

  /// "עדכון אישי" שאין לו מסלול patches — המסד המלא יורד למרות שהמצב הזה
  /// בנוי כדי לדלג עליו.
  String exportPersonalNeedsFullDb(int fromVersion, int latestVersion);

  /// אותו מצב, כשגם מסד מלא בגרסה האחרונה אינו קיים — כאן באמת אין מה
  /// להביא, ולכן זו אזהרה.
  String exportPersonalNoFullDbEither(int fromVersion, int latestVersion);

  String get planLocalVersionUnknown;
  String planContentChangedWithoutVersionBump(String releaseTag);
  String planNoDeltaRoute(int localVersion, int latestVersion);

  /// שרשרת קובצי העדכון מגיעה לאותה גרסה כמו החלפת המסד המלא, אבל ארוכה
  /// ממנה בהרבה — ולכן נבחרת ההחלפה.
  String planFullDbFasterThanPatches(
    int stepCount,
    int patchMinutes,
    int fullDbMinutes,
  );
  String planNoFullDbEither(String reason);
  String planPatchSchemaTooNew(int schemaVersion, int latestVersion);
  String planOtzariaTooOldForLibrary(int readableSchema, int latestVersion);
  String planStopsBeforeOtzariaSchema(int reachedVersion, int latestVersion);
  String libraryNeedsOtzariaUpdateFromDrive(String otzariaVersion);

  /// אותו מצב על ציר פורמט ה-patch: הסכמה מוכרת, הפורמט לא.
  String planPatchFormatTooNew(int patchFormatVersion, int latestVersion);
  String planFullDbWouldNotProgress(
    int reachableVersion,
    int localVersion,
    int latestVersion,
  );
  String planNewSchemaNeedsFullDb(int latestVersion, int schemaVersion);

  /// שרשרת קובצי עדכון שנעצרת מתחת ל-latest כי הגרסאות שמעליה עברו סכמה.
  String planPartialDeltaSchemaStop(
    int reachedVersion,
    int latestVersion,
    int schemaVersion,
  );

  /// אותה עצירה, כשהחוסם הוא פורמט ה-patch.
  String planPartialDeltaFormatStop(
    int reachedVersion,
    int latestVersion,
    int patchFormatVersion,
  );

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

  /// `patch_meta.schema_version` — גרסת פורמט ה-`patch.db` — מחוץ לטווח הנתמך.
  String patchFormatTooNew(int patchFormatVersion, int supported);

  /// הפורמט שבקובץ ה-patch אינו זה שהמניפסט הצהיר עליו.
  String patchFormatMismatch(int inPatch, int inManifest);
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
  String get manifestMissingPatchFormatVersion;
  String manifestInvalidOptionalField(String key);
  String manifestInvalidHashMap(String key);
  String splitManifestDownloadFailed(String name, int statusCode);
  String get interruptedUpdateWithoutBackup;
  String get interruptedUpdateRestored;
  String planSchemaNeedsAppUpdate(int schemaVersion, int supportedSchema);
  String planSchemaBarrierNeedsFullDownload(int schemaVersion);
  String planDeltaNeedsAppUpdate(
    int latestVersion,
    int supportedSchema,
    int supportedPatchFormat,
  );
  String planHeavyDelta(String deltaSize, String localDbSize);
  String tableHashMismatch(String tables);
  String patchOpenFailed(String path, String detail);
  String get networkInterrupted;
  String get deletePreviousArchiveFailed;
  String joinedArchiveSizeMismatch(int written, int expected);
  String get joinedArchiveHashMismatch;

  // library_manager
  String get mirrorMissing;
  String get mirrorDamaged;
  String interruptedUpdateCorruptDb(String detail);
  String get interruptedUpdateDefaultDetail;
  String get blockedNeedsManualAction;
  String get blockedNeedsManualActionWithPeriod;
  String patchUrlMissing(String fileName);
  String get fullDbAssetMissingFromPlan;
  String get fullDbExtractionFailed;
  String get fullDbNeedsNativeZstd;
  String get patchNeedsNativeZstd;
  String versionMismatchAfterWrite(int? actual, int? expected);
  String get updateCancelled;

  /// אין מקום בדיסק. אומרת **כמה** לפנות ו**איפה** — קודם לכן זו הייתה שגיאת
  /// OS באנגלית על נתיב `.new` שהמשתמש אינו מכיר.
  String notEnoughDiskSpace(String dir, String needed, String free);
  String fileTooLargeForVolume(String dir);

  /// תיקיית ההתקנה אינה ניתנת לכתיבה (issue #23) — מפנה לבורר הידני.
  String installDirNotWritable(String dir, String detail);

  /// מקום פנוי חסר להורדת המראה, עם הגודל שנדרש בפועל לפי התוכנית.
  String mirrorNotEnoughDiskSpace(String dir, String needed, String free);
  String get otzariaIsRunning;

  /// גרסת המסד המקומי לא נקראה כרגע: הוא נעול, נשאר באמצע כתיבה, או יושב
  /// בתיקייה שאי אפשר לכתוב אליה. ראו `LocalDbUnreadableReason`.
  String get localDbLocked;
  String get localDbInterruptedWrite;
  String get localDbReadOnlyLocation;
  String get zstdContextCreationFailed;
  String zstdDecompressionFailed(String errorName);
  String get zstdEmptyInput;
  String get zstdTruncatedFrame;

  String dbIntegrityCheckFailed(String result);

  // ── הקבצים הנלווים לספרייה (תלמוד, קטלוג, מילון) ────────────────────────
  String get companionTalmudName;
  String get companionCatalogName;
  String get companionDictionaryName;
  String get companionSemanticName;

  /// קובצי החיפוש החכם שבמראה אינם ניתנים להתקנה; ההסבר תלוי במי שצריך לזוז.
  String get semanticIncompatibleUpdateTool;
  String get semanticIncompatibleUpdateOtzaria;
  String get semanticIncompatibleRepublish;
  String get semanticIncompatibleOtzariaUnproven;
  String get libraryChangesNotesName;
  String get semanticDownloading;
  String get semanticInstalling;
  String get semanticConsentRequired;
  String get semanticFullDownloadNeeded;
  String get semanticConsentTitle;

  /// נוסח ההסכמה של אוצריא עצמה, בלי המשפט על הכלי הזה.
  String get semanticConsentTerms;
  String get semanticConsentText;
  String get semanticConsentConfirm;

  /// החלון שלפני "עדכון המחשב הזה", פעם אחת במחשב. בלי "אינטרנט": הוא מוצג
  /// גם במחשב הלא מחובר.
  String get semanticAskTitle;
  String get semanticAskIntro;
  String get semanticAskLater;
  String get semanticAskApprove;
  String get semanticAskDecline;

  /// השרת חסם את המפתח של המחשב הזה — הסכמה חדשה לא תעזור.
  String get semanticConsentBlocked;

  /// ההסכמה לא נשמרה בהגדרות אוצריא (כשל כתיבה או חריג).
  String get semanticConsentNotSaved;
  String get semanticFeedbackFailed;
  String companionChecking(String name);
  String companionDownloading(String name);
  String companionInstalling(String name);
  String companionAssetMissingInRelease(String name);
  String companionAssetHttpFailure(String name, int status);
  String companionExtractionFailed(String name);
  String get companionsMirrorMissing;
  String companionStillPendingAfterInstall(String name);
  String companionsInstallFailed(String names);

  /// אחרי התקנה טרייה שלא הצלחנו לכוון אליה את ההגדרה של אוצריא. אוצריא
  /// אינה סורקת את ברירת המחדל שלה, ולכן בלי ההוראה הזו היא נפתחת על
  /// ספרייה ריקה בלי שום רמז למה.
  String libraryLocationNeedsManualSetting(String dbPath);

  /// רשומה שהקובץ שלה חסר או קטוע במראה — המראה שעל הכונן חלקית.
  String companionsMissingFromMirror(String names);

  /// המראה אינה נושאת אף קובץ נלווה — עדכון מכאן לא יביא תלמוד, קטלוג ומילון.
  String get companionsAbsentFromMirror;

  // שלבי ההחלה, כפי שמוצגים במד ההתקדמות
  String applyDownloadingPatch(String step);
  String applyApplyingPatch(String step);

  /// תת-שלב בתוך החלת ה-patch — [stage] הוא שם השלב הגולמי כפי ש-
  /// `PatchApplier.onStage` מדווח אותו.
  String applyPatchStage(String stage, String step);
  String get applyDownloadingFullDb;
  String get applyDecompressingFullDb;

  /// חילוץ שגם מאמת את ה-sha256 של הנכס תוך כדי — כך זה כשמחלצים ישירות
  /// מהמראה במקום להעתיק אותה קודם לצד המסד.
  String get applyDecompressingAndVerifyingFullDb;
  String get applyWritingFullDb;
  String get applyVerifying;

  /// **מה** מאומת כרגע — [stage] הוא `dbIntegrity`/`dbVersion` כפי
  /// ש-`LibraryApplyProgress.verifyStage` מדווח. "מוודא תקינות..." לבדו
  /// חוזר כמה פעמים בהחלה אחת ואינו אומר על מה מחכים.
  String applyVerifyStage(String stage);

  /// שם השלב ולצידו הזמן שחלף בו, לשלבים שאינם מדווחים התקדמות כלל
  /// (`quick_check` על מסד מלא חוסם דקות). [elapsed] הוא `mm:ss`.
  String applyStageElapsed(String stage, String elapsed);
  String get applyInstallingCompanions;
  String get applyDone;
}

// ── הודעות מ-otzaria_manager ──────────────────────────────────────────────────

abstract class AppDomainStrings {
  const AppDomainStrings();

  String get channelStable;
  String get channelPrerelease;
  String downloadingChannel(String channelLabel);

  /// הודעת החריג שנזרק כשהמשתמש ביטל את ההורדה — לא שגיאה, בחירה.
  String get downloadCancelled;

  /// אותו דבר, כשהביטול היה באשף ההתקנה עצמו.
  String get installCancelledByUser;

  /// האשף רץ, סיים, וההתקנה עדיין לא נראית על הדיסק — כמעט תמיד משמע
  /// שהמשתמש עוד באמצע. לא שגיאה: הודעה שאומרת מה לעשות.
  String get wizardStillOpen;
  String get wizardEndedWithoutInstall;
  String get setupContinuesElsewhere;

  String get noInstallableReleaseForPlatform;
  String get mirrorEmptyRunDownload;
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
  String get installerDigestMismatch;
  String installerExitCode(int exitCode, String output);
  String installerLogTail(String tail);
  String get macAppNotFoundInArchive;
  String macReplaceFailed(String error);

  /// ההתקנה ב-macOS מחליפה את חבילת ה-`.app` כולה, ומחיקת קבצים שתהליך
  /// מחזיק פתוחים מצליחה שם בשקט — כלומר אוצריא שרצה הייתה נשארת בלי
  /// הקבצים שלה. לכן מסרבים, ומבקשים לסגור אותה.
  String get macCloseOtzariaBeforeInstall;
  String dittoExtractFailed(int exitCode, String output);
  String hdiutilAttachFailed(int exitCode, String output);
  String get macAppNotFoundInDmg;
  String dittoCopyFailed(int exitCode, String output);
  String installNotDetected(String installDir, int timeoutSeconds);

  /// כשלא נמסר `/DIR=` — ההתקנה הלכה לברירת המחדל של המתקין, ואחריה
  /// הזיהוי (רג'יסטרי + מיקומים מוכרים) לא מצא אותה.
  String installNotDetectedAnywhere(int timeoutSeconds);
  String launchFileMissing(String launchPath);
  String launchFailed(int exitCode, String stderr);
  String githubStatus(int statusCode, String uri);
  String githubRateLimited(int? retryAfterMinutes);
  String networkBlockedByFilter(int statusCode, String host);
  String networkCertificateRejected(String host);
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

  /// אין לתוסף אף בילד שירוץ על גרסת אוצריא שבמחשב הזה.
  String get noCompatibleBuild;
  String get localPluginFileMissing;
  String get localPluginFileCorrupt;
  String get badPluginExtension;
  String get otzariaOpenFailedHint;
  String otzariaOpenFailed(String error);
  String get directInstallUnsupportedPlatform;

  String get syncLoadingCatalog;

  /// [total] הוא מספר התוספים שיש בהם מה להוריד, לא גודל החנות — הסנכרון
  /// מדלג לגמרי על מה שכבר מעודכן.
  String syncPlugin(String name, int done, int total);

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
  String get downloadedFileNotPlugin;
  String get downloadedFileNotImage;
  String get downloadedFileHashMismatch;
  String get downloadedFileWrongBuild;
  String get siteClosedForShabbat;

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

  // ── ייצוא תוכנת החנות ───────────────────────────────────────────────────
  String get exportPreparing;

  /// אין קובץ הרצה במראה — במחשב המקוון לא נלחץ "הורד", או שההורדה נכשלה.
  String get exportAppMissing;
  String get exportCopyingApp;
  String exportAppCopyFailed(String error);

  /// קובץ ההרצה הועתק ואינו שם יותר — כמעט תמיד אנטי-וירוס שמחק קובץ
  /// לא-חתום. **חייב להיאמר**: בלעדיו הדיאלוג הכריז "הועתק" על תיקייה
  /// שיש בה `Data\` בלבד.
  String exportAppVanished(String path);

  /// ההורדה הצליחה והקובץ אינו בכונן יותר. **הודעה נפרדת מ-[exportAppMissing]
  /// בכוונה**: שם הפעולה הנכונה היא להוריד, וכאן הורדה חוזרת רק תימחק שוב.
  String get exportAppRemovedFromMirror;
  String get exportAppDamaged;
  String exportPlugin(String name, int done, int total);
  String get exportWritingCatalog;
  String exportDone(int plugins);
}
// ── תוכנות מותאמות (ממשק) ────────────────────────────────────────────────────

/// המסגרת סביב תוכנות שהמשתמש הוסיף. **שם התוכנה והתיאור שלה אינם
/// מתורגמים** — הם תוכן שהמשתמש כתב, כמו שמות התוספים מ-otzaria.org.
abstract class CustomAppsStrings {
  const CustomAppsStrings();

  // ── המסך ──
  String get screenTitle;

  // ── רשת הכרטיסים, סרגל הקטגוריות ודף התוכנה ──

  /// כותרת סרגל הצד, וגם כותרת חלון ניהול הקטגוריות.
  String get categoriesTitle;
  String get allAppsItem;

  /// הפריט שמרכז את מה שלא שויך לשום קטגוריה. מוצג רק כשיש קטגוריות.
  String get uncategorizedItem;

  /// כותרות הסעיפים בדף התוכנה.
  String get aboutPanelTitle;
  String get infoPanelTitle;
  String get screenshotsPanelTitle;

  // ── שדות "מידע כללי" בדף התוכנה ──
  String get infoSource;
  String get infoSourceFile;
  String get infoInstalled;
  String get infoStored;
  String get infoOnline;
  String get infoStoredSize;
  String get infoStoredAdded;
  String get valueUnknown;
  String get valueNo;
  String get installedNoVersionValue;
  String get notStoredValue;

  // ── מצבים ריקים ──
  String get emptyCategoryTitle;
  String get emptyCategoryBody;
  String get emptyUncategorizedTitle;
  String get emptyUncategorizedBody;
  String categoryAppCount(int count);

  // ── ניהול הקטגוריות (בהגדרות) ──
  String get categoriesDialogHint;
  String get categoryNameLabel;
  String get categoryNameHint;
  String get categoryDescriptionLabel;
  String get addCategoryButton;
  String get editCategoryTitle;
  String get noCategoriesHint;
  String get removeCategoryTooltip;
  String removeCategoryDialogTitle(String name);

  /// המחיקה אינה נוגעת בתוכנות עצמן — חובה לומר זאת, אחרת "מחיקה" נשמעת
  /// כמו מחיקת מה שבתוכה.
  String removeCategoryDialogContent(String name, int count);
  String categoryRemovedSnack(String name);

  // ── מדיה בטופס ──
  String get appCategoriesLabel;
  String get appCategoriesHint;
  String get longDescriptionLabel;
  String get longDescriptionHint;
  String get iconLabel;
  String get pickIconButton;
  String get pickIconDialogTitle;
  String get removeIconTooltip;

  /// חילוץ האייקון מקובץ הרצה — ווינדוס בלבד, ורק כשיש מאיזה קובץ.
  /// מתקין של Inno נושא כמעט תמיד את האייקון של התוכנה עצמה.
  String get extractIconButton;
  String extractedIconSnack(String fileName);
  String get extractIconFailedSnack;

  String get moveScreenshotBackTooltip;
  String get moveScreenshotForwardTooltip;
  String get screenshotsLabel;
  String get addScreenshotsButton;
  String get pickScreenshotsDialogTitle;
  String get removeScreenshotTooltip;
  String screenshotsChosen(int count);

  /// שורת ההגדרות — שורה אחת, שכל תפקידה לפתוח את מסך הניהול.
  String get settingsCardTitle;
  String get manageRowTitle;
  String manageRowSubtitle(int count);
  String get emptyHint;
  String get addButton;

  /// כמה תוכנות רשומות. זה מה שמבדיל את השורה הריקה מהמלאה בהגדרות.
  String get openManagerButton;

  // ── מסך הניהול: **כל** ניהול המרשם — הוספה, עריכה, הסרה, קטגוריות וסדר ──
  String get manageDialogTitle;
  String get manageDialogHint;

  /// הסדר נקבע כאן והוא הסדר שבו התוכנות מוצגות במסך — חייב להיאמר,
  /// אחרת החיצים נראים כמו שינוי שאינו משפיע על דבר.
  String get orderHint;

  /// "קודם" ו"הבא" בסדר הרשת — בכיוון הקריאה, ולכן החיצים מתהפכים ב-RTL.
  String get moveAppEarlierTooltip;
  String get moveAppLaterTooltip;
  String get dragToReorderTooltip;

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

  String get githubUrlLabel;
  String get githubUrlHint;
  String get githubUrlInvalid;
  String get fetchAssetsButton;
  String get assetHint;
  String get noAssetsFound;
  String assetsFromRelease(String tagName);

  String get pickInstallerButton;
  String get pickInstallerDialogTitle;
  String installerKindSniffed(String kind);

  /// "הקובץ הוא התוכנה עצמה". נשאל במפורש כי
  /// **אי אפשר להסיק אותו מהבייטים**: exe נייד ומתקין שלא זוהה נראים זהים.
  String get portableFileLabel;
  String get portableFileHint;
  String get interactiveInstallLabel;
  String get interactiveInstallHint;
  String get portableDestinationHint;
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
  String get noStoredInstaller;

  String get downloadButton;
  String get downloadingLabel;
  String get checkOnlineButton;

  // ── בדיקה ברשת לכל התוכנות בבת אחת, במקום כרטיס-כרטיס ──
  String get checkAllOnlineButton;
  String checkingAllOnlineLabel(int done, int total);
  String checkAllOnlineSummary(int updates, int checked);
  String checkAllOnlineNoUpdates(int checked);

  /// כולן נכשלו — כלומר אין רשת, וזו התשובה השלמה.
  String get checkAllOnlineAllFailed;

  /// חלקן נכשלו. חייב להיאמר: "אין עדכונים" על תוכנות שלא נבדקו הוא מטעה.
  String checkAllOnlineSomeFailed(int failed);

  // ── הורדה לכל התוכנות בבת אחת — רק למה שיש בו חדש ──
  String get downloadAllButton;
  String downloadingAllLabel(int done, int total);
  String downloadAllDoneSnack(int downloaded);

  /// נבדק, ואין מה להוריד. אומר כמה נבדקו, כי זה ההבדל בין "הכול מעודכן"
  /// לבין "לא נבדק כלום".
  String downloadAllNothingNew(int checked);

  /// הורדות שנכשלו. אסור לבלוע — "הורדו 2" על שלוש שנוסו הוא מטעה.
  String downloadAllSomeFailed(int failed);

  String onlineVersionAvailable(String version);
  String get onlineUpToDate;
  String get onlineUnavailable;

  /// "בחירת מיקום ידנית" — הנפילה חזרה כשהזיהוי האוטומטי לא מצא.
  String get pickLocationButton;
  String locationAdoptedSnack(String dir);
  String get locationNotFoundSnack;

  String installedSnack(String name);

  String get trustDialogTitle;
  String trustDialogContent(String name, String source);
  String get trustDialogConfirm;
  String get unverifiedDialogTitle;
  String unverifiedDialogContent(String fileName);
  String get unverifiedDialogConfirm;

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
  String removeDialogTitle(String name);

  /// חייב לומר במפורש שהתוכנה עצמה **אינה** מוסרת מהמחשב.
  String removeDialogContent(String name);
  String get removeDialogConfirm;
  String removedSnack(String name);

  // ── החנות: עמוד, סינון, כרטיס ופרטים ──
  String get screenSubtitle;
  String get showAllAppsButton;
  String get sourceGithubShort;
  String get sourceFileShort;
  String versionLabel(String version);
  String updateToButton(String version);
  String get onlineNotChecked;
  String get manageEmptyTitle;
  String get manageEmptyBody;
  String get emptyReadOnlyBody;
  String get noCategoriesTitle;
  String get orderSectionTitle;
  String get formStepSource;
  String get formStepGithubFile;
  String get formStepLocalFile;
  String get formStepDetails;
  String get sourceGithubOption;
  String get sourceGithubOptionHint;
  String get sourceFileOption;
  String get sourceFileOptionHint;
  String get fileLabel;
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
  String descriptorUnknownSourceKind(String found, String allowed);

  // ── המרשם ──
  String appAlreadyRegistered(String name);
  String appNotRegistered(String id);

  // ── התקנה ──
  String get noInstallerInMirror;
  String installerFileMissing(String path);
  String installerUnsupportedFile(String fileName);
  String installerExitCode(int exitCode, String output);
  String installerElevatedRetryFailed(
    int firstExitCode,
    int elevatedExitCode,
    String output,
  );
  String installerElevatedRetryDeclined(int firstExitCode);
  String get installerElevationDeclined;
  String get installerCancelled;
  String get installerDigestMismatch;

  /// קובץ התקנה בלי sha256 שמור אינו מורץ עד שמישהו מאשר אותו כאן.
  String get installerUnverified;

  /// רשומה שהגיעה ממחשב אחר אינה מותקנת לפני אישור במחשב הזה.
  String get appNotTrustedHere;
  String get appNotTrustedForLaunch;
  String fileCopyFailed(String error);
  String portableFileInUse(String fileName, String error);
  String launchFileMissing(String launchPath);
  String get launchElevationDeclined;

  // ── מדיה: אייקון וצילומי מסך ──
  String mediaFileMissing(String path);

  /// נבחר קובץ שאינו תמונה. נאמר בשם הקובץ, כי הבחירה הייתה מרשימה.
  String mediaNotAnImage(String fileName);

  // ── GitHub ──
  String githubStatus(int statusCode, String uri);
  String get githubBadResponse;
  String get githubNoReleases;
  String githubNoMatchingAsset(String tagName);
  String downloadFailed(int statusCode);

  /// הקובץ שהורד אינו תואם ל-digest שגיטהאב מפרסם לו.
  String downloadDigestMismatch(String fileName);
  String get sourceIsNotGithub;
}

// ── דיווחי טעויות: מהמחשב הלא-מקוון אל אוצריא ──────────────────────────────

/// איסוף דיווחי הטעויות שאוצריא לא הצליחה לשלוח, ושליחתם מהמחשב המקוון.
/// אין לזה מסך משלו: דיאלוג בעלייה, וכפתור בכרטיס ההורדות.
abstract class ErrorReportsStrings {
  const ErrorReportsStrings();

  // ── איסוף, במחשב הלא-מקוון ──
  String get collectDialogTitle;
  String collectDialogContent(int count);
  String get collectConfirm;
  String get collectLater;
  String collectedSnack(int count);

  String collectPartialSnack(int count, String error);
  String collectFailedSnack(String error);

  String get collectOtzariaOpenSnack;

  /// הגילוי שמעל הכפתור רוענן בלחיצה — יש בו מידע שלא הוצג קודם.
  String get collectDisclosureRefreshedSnack;

  String get legacyReportsDialogTitle;
  String get legacyReportsDialogContent;
  String get introDialogTitle;
  String get introDialogContent;
  String get introDialogContentReadOnly;
  String get introDialogContentReadOnlyDriveFull;
  String get introDialogConfirm;

  // ── העלאה, במחשב המקוון ──
  String get uploadLongDialogTitle;
  String uploadLongDialogContent(int count, int perMinute, int minutes);
  String get uploadLongDialogConfirm;
  String uploadingStage(int done, int total);
  String uploadWaitingStage(int seconds);
  String get uploadStopButton;
  String uploadPendingOffline(int count);
  String uploadPendingUnchecked(int count);
  String get uploadingFeedbackStage;
  String get uploadCollectingBusy;
  String get uploadUnexpectedFailure;

  String uploadSummary(int sent, int rejected, int remaining);
  String uploadFailedSnack(String error);
}

/// שגיאות של התור של אוצריא ושל שרת הדיווחים.
abstract class ErrorReportsDomainStrings {
  const ErrorReportsDomainStrings();

  /// התור של אוצריא (`user_state.db`) לא נקרא או לא נכתב. הפרטים — ביומן.
  String get queueUnreadable;

  /// חלק מהדיווחים לא הועברו; הם נשארו בתור של אוצריא.
  String get someNotCollected;

  String uploadHttpStatus(int statusCode);
  String get uploadShabbat;
  String get uploadTimedOut;
  String uploadNetworkError(String error);
  String outboxUnreadable(String error);
}

// ── דיווחים של הלאנצ'ר על עצמו ──────────────────────────────────────────────

/// דיווח על תקלה בלאנצ'ר עצמו — פורט של "דיווח על התוכנה" של אוצריא: כרטיס
/// בהגדרות, טופס, ניהול התור וההיסטוריה, וההצעה לדווח אחרי סגירה לא צפויה.
abstract class AppReportsStrings {
  const AppReportsStrings();

  // ── הכרטיס בהגדרות ──
  String get crashModeTitle;
  String get crashModeSubtitle;
  String get crashModeAsk;
  String get crashModeAlways;
  String get crashModeNever;
  String get manageTileTitle;
  String manageTileSubtitle(int pending, int sent);

  // ── חלון הניהול ──
  String get manageDialogIntro;
  String get sendNowButton;
  String get clearPendingButton;
  String get sendOneButton;
  String get deleteButton;
  String get detailsButton;
  String get sentSectionTitle;
  String sentSummary(int shown, int total);
  String get clearSentButton;

  /// מספר ה-issue, או `null` כשהשרת עוד לא פתח אותו.
  String openIssueButton(int? number);
  String get mergedLabel;
  String get detailsPendingTitle;
  String get detailsSentTitle;
  String get stepsHeading;
  String get clearPendingDialogTitle;
  String get clearPendingDialogContent;
  String get clearSentDialogTitle;
  String get clearSentDialogContent;
  String flushSentSnack(int count);
  String flushFailedSnack(int pending);

  /// שגיאה מקומית (דיסק, תור לא קריא) — לא רשת — ולא נשלח דבר.
  String flushErrorSnack(int failed);

  /// חלק נשלחו, ואחרים נכשלו בשגיאה מקומית ונשארו בתור.
  String flushPartialSnack(int sent, int failed);

  /// חלק נשלחו, וחלק נדחו על ידי השרת והוסרו.
  String flushDroppedSnack(int sent, int dropped);

  /// הסבב הגיע לתקרה ויש עוד בתור.
  String flushRemainingSnack(int sent, int remaining);

  /// הדיווח כבר אינו בתור (נשלח ברקע או הוסר), ולכן לא נשלח שוב.
  String get notPendingSnack;
  String get removedFromQueueSnack;
  String get deletedFromHistorySnack;
  String get pendingClearedSnack;
  String get historyClearedSnack;

  // ── סוגי דיווח ──
  String get typeBug;
  String get typeCrash;
  String get typePerformance;
  String get typeSuggestion;

  // ── הטופס ──
  String get dialogTitle;
  String get dialogSubtitle;
  String get typeLabel;
  String get titleLabel;
  String get titleHint;
  String get titleRequired;
  String get descriptionLabel;
  String get descriptionHint;
  String get descriptionRequired;
  String get stepsLabel;
  String get stepsHint;
  String get optionalHint;
  String get emailLabel;
  String get emailInvalid;
  String get sendButton;

  // ── תמונות ──
  String get imagesPrompt;
  String get imagesPickDialogTitle;
  String get removeImageTooltip;
  String imageTooLarge(int megabytes);
  String tooManyImages(int count);
  String imagesTotalTooLarge(int megabytes);
  String get imageReadFailed;

  // ── מה נשלח ──
  String get attachmentsHeading;
  String get includeDiagnostics;
  String get diagnosticsUnavailable;
  String get includeLog;
  String get logEmpty;
  String get showPreviewButton;
  String get hidePreviewButton;
  String get privacyNote;

  // ── תוצאה ──
  String sentSnack(int? issueNumber);
  String mergedSnack(int? issueNumber);
  String get queuedSnack;

  /// השדה שהשרת דחה, או `null` כשלא אמר.
  String rejectedSnack(String? field);
  String get titleRequiredSnack;
  String get descriptionRequiredSnack;
  String get emailRequiredSnack;
  String get invalidEmailSnack;
  String get cannotOpenIssueSnack;
  String get sendFailedSnack;

  // ── אחרי סגירה לא צפויה ──
  String get crashTitle;
  String get crashBody;
  String get crashDescriptionLabel;
  String get crashEmailLabel;
  String get crashNextTimeLabel;
  String get crashNextAsk;
  String get crashNextAlways;
  String get crashNextNever;
  String get crashDismissButton;
  String get crashSendButton;
  String get crashDismissedSnack;

  /// כותרת הדיווח על קריסה שאין לה חתימה.
  String get crashFallbackTitle;

  /// הודעה שקטה בעלייה, אחרי שדיווח על הסגירה נשלח מעצמו ("לשלוח תמיד").
  String get crashAutoSentSnack;
}
