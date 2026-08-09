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
  SetupErrorStrings get setupError;
  UnitStrings get units;

  // ── מלל שנוצר בחבילות התשתית ומוצג כמו שהוא ─────────────────────────────
  LibraryDomainStrings get libraryDomain;
  AppDomainStrings get appDomain;
  PluginsDomainStrings get pluginsDomain;
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
  String get install;
  String get update;
  String get launch;
  String get recheck;
  String get notCheckedYet;
  String get checking;
  String get upToDate;
  String get updateAvailable;
  String get installing;
  String get unknownValue;
  String get lastDownloaded;
  String get emptyValue;
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
  String get navSettings;

  /// נאמר כשלא ניתן לפתוח את תיקיית הלוגים בסייר הקבצים.
  String logPathFallback(String path);
}

// ── דף הבית ───────────────────────────────────────────────────────────────────

abstract class HomeStrings {
  const HomeStrings();

  String get title;
  String get description;

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
  String get onlineCardSubtitle;
  String get onlineChecking;
  String get onlineNeverChecked;
  String get onlineOffline;
  String get onlineHasUpdates;
  String get onlineNoUpdates;
  String get checkForUpdatesButton;
  String get downloadNowButton;
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
  String get description;

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

  String get whatsNewTitle;
  String get whatsNewEmpty;

  String get sourceCardTitle;
  String get sourceCardSubtitle;
  String get sourceDirTitle;

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
  String get description;

  String get stateCardTitle;
  String get stateRowTitle;

  String get dbFileTitle;
  String get dbFileMissing;
  String get pickDbButton;
  String get pickDbDialogTitle;
  String get dbPathUpdatedSnack;

  String get localVersionTitle;
  String get targetVersionTitle;
  String get targetVersionNothingDownloaded;
  String get targetVersionUnknown;

  String get otzariaRunningTitle;
  String get otzariaRunningSubtitle;

  String get updatingProgress;
  String get installUpdateButton;
  String get updateDialogTitle;

  String get sourceCardTitle;
  String get sourceCardSubtitle;
  String get sourceDirTitle;
  String get mirrorContentTitle;
  String get mirrorEmpty;
  String get mirrorUnreadable;
  String mirrorHasVersion(String version);
  String get mirrorPresent;
}

// ── מסך ההגדרות ───────────────────────────────────────────────────────────────

abstract class SettingsScreenStrings {
  const SettingsScreenStrings();

  String get title;
  String get description;

  String get automationCardTitle;
  String get automationCardSubtitle;
  String get autoCheckTitle;
  String get autoCheckSubtitle;
  String get autoOnlineCheckTitle;
  String get autoOnlineCheckSubtitle;
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
  String get downloadCardSubtitle;
  String get syncAppTitle;
  String get syncAppSubtitle;
  String get syncLibraryTitle;
  String get syncLibrarySubtitle;
  String get syncPluginsTitle;
  String get syncPluginsSubtitle;

  String get storageCardTitle;
  String get storageCardSubtitle;
  String get backupTitle;
  String get backupSubtitle;
  String get backupOff;
  String get backupOn;

  String get networkCardTitle;
  String get networkCardSubtitle;
  String get timeoutTitle;
  String get timeoutSubtitle;

  String get uiCardTitle;
  String get languageTitle;
  String get languageSubtitle;
  String get languageHebrew;
  String get languageEnglish;
  String get themeTitle;
  String get themeSystem;
  String get themeLight;
  String get themeDark;
  String get textSizeTitle;
  String get textSizeSmall;
  String get textSizeNormal;
  String get textSizeLarge;

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
  String syncDoneSnack(int count);
  String get syncButton;
  String get reloadTooltip;
  String get syncingOverlayTitle;
  String get syncingOverlayStarting;
  String get syncNeverRan;
  String syncedAt(String time);
  String get syncDirUnknownTooltip;
  String updatesAvailableChip(int count);

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

  // ── גלריית צילומי המסך ──────────────────────────────────────────────────
  String get screenshotPrevious;
  String get screenshotNext;
}

// ── מסך "התוכנה במקום הלא נכון" ───────────────────────────────────────────────

abstract class SetupErrorStrings {
  const SetupErrorStrings();

  String get title;
  String get explanation;
  String get whatToDo;
  String get attemptedDirTitle;
  String get copyPathButton;
  String get pathCopiedSnack;

  /// בפועל תמיד בעברית: השגיאה נזרקת לפני שקובץ ההגדרות בכלל נקרא, כי הוא
  /// יושב בתיקייה שנכשלה. מתורגם בכל זאת כדי שלא תישאר מחרוזת בקוד.
  String cannotWriteToDataDir(String osMessage);
}

// ── יחידות ומספרים ────────────────────────────────────────────────────────────

abstract class UnitStrings {
  const UnitStrings();

  String bytes(int count);
  String progressOf(String received, String total);
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

  String get interruptedUpdateNoBackup;
  String get interruptedUpdateRestored;
  String get backupLabel;
  String get restoreLabel;
  String partialCopy(String label, int actual, int expected);

  String get exportLoadingReleases;
  String get exportNoReleases;
  String exportDownloading(String tag, String asset);
  String exportVerifying(String tag, String asset);
  String exportWritingManifest(String fileName);
  String get exportDone;
  String get exportCancelled;
  String get exporterDoesNotExtract;

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
  String get otzariaIsRunning;
  String get zstdContextCreationFailed;
  String zstdDecompressionFailed(String errorName);
  String get zstdEmptyInput;
  String get zstdTruncatedFrame;

  // שלבי ההחלה, כפי שמוצגים במד ההתקדמות
  String applyDownloadingPatch(String step);
  String applyApplyingPatch(String step);
  String get applyDownloadingFullDb;
  String get applyDecompressingFullDb;
  String get applyWritingFullDb;
  String get applyVerifying;
  String get applyDone;
}

// ── הודעות מ-otzaria_manager ──────────────────────────────────────────────────

abstract class AppDomainStrings {
  const AppDomainStrings();

  String get channelStable;
  String get channelPrerelease;
  String downloadingChannel(String channelLabel);

  String get noInstallableReleaseForPlatform;
  String get mirrorEmptyRunDownload;
  String get notInstalledByThisLauncher;
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
  String syncPlugin(String name, int done, int total);
  String get syncDone;
  String get syncCategories;
  String syncStructureFailed(String error);
  String syncCategoryFailed(String name, String error);
  String syncImageFailed(String name, String error);
  String syncScreenshotFailed(String name, String error);
  String syncPluginFileFailed(String name, String error);

  String get whatPluginList;
  String get whatStoreStructure;
  String whatCategory(String slug);
  String get responseNotPluginList;
  String siteUnreachable(String error);
  String loadFailed(String what, int statusCode);
  String responseNotJson(String what);
  String get responseUnexpectedShape;
  String httpStatusFor(int statusCode, String url);
}
