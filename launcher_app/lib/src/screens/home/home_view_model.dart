import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart'
    show OtzariaUpdateCheckResult;
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart' show PluginsOnlineStatus;

import '../../controllers/launcher_update_controller.dart';
import '../../controllers/library_module_controller.dart';
import '../../controllers/otzaria_module_controller.dart';
import '../../shell/app_session.dart';
import '../../shell/home_guidance.dart';
import '../../shell/home_guidance_session.dart';
import '../../shell/shell_navigator.dart';

/// מה רץ כשהגיבור במצב `taskInProgress`. [section] — הדף שמציג את ההתקדמות.
enum HomeTask {
  downloading,
  installingApp,
  updatingLibrary,
  syncingPlugins(ShellSection.plugins),
  updatingPlugins(ShellSection.plugins),
  exportingStore(ShellSection.plugins),
  downloadingCustomApps(ShellSection.customApps),
  customApps(ShellSection.customApps),
  installingLauncher(ShellSection.launcher),
  restartingElevated,
  other;

  const HomeTask([this.section]);

  final ShellSection? section;
}

enum LauncherLineKind { online, ready, readyManual, downloading, error }

/// שורת העדכון של הכלי עצמו בתחתית הבית.
class LauncherLine {
  const LauncherLine(this.kind, {this.version, this.error});

  final LauncherLineKind kind;
  final String? version;
  final String? error;
}

/// כל מה שדף הבית מציג, בלי קונטרולרים — כך כל מצב נבנה בבדיקה ובצילום.
class HomeViewModel {
  const HomeViewModel({
    required this.guidance,
    this.online,
    this.installedVersion,
    this.driveAppVersion,
    this.appAwaitsNewerStable,
    this.appError,
    this.appErrorPicksFolder = false,
    this.appSetupNotice,
    this.whatsNew = false,
    this.onlineAppVersion,
    this.onlineAppLatest,
    this.libraryHereVersion,
    this.libraryFreshInstall = false,
    this.driveLibraryVersion,
    this.driveCompanionNames,
    this.onlineLibraryVersion,
    this.onlineLibraryLatest,
    this.onlineCompanionNames,
    this.pluginUpdatesOnDrive = 0,
    this.onlinePluginChanges = 0,
    this.onlinePluginCatalogChanged = false,
    this.onlineStoreApp = false,
    this.appDownloadBytes,
    this.libraryDownloadBytes,
    this.driveFreeBytes,
    this.syncApp = true,
    this.syncLibrary = true,
    this.syncPlugins = true,
    this.libraryDownloadFailed = false,
    this.semanticOffer = false,
    this.failedDownloads,
    this.foundNothing,
    this.onlineCheckedAt,
    this.libraryMissingNames,
    this.libraryCompanionsAbsent = false,
    this.libraryNotFound = false,
    this.libraryElsewhereFrom,
    this.personalMode = false,
    this.personalMachines = 0,
    this.personalFloor,
    this.personalPreparedHere = false,
    this.personalPending = false,
    this.personalPendingNeedsClick = false,
    this.semanticConsent = false,
    this.appTile = TileStatus.upToDate,
    this.libraryTile = TileStatus.upToDate,
    this.pluginsTile = TileStatus.upToDate,
    this.pluginsOnDrive = 0,
    this.pluginsInstalled = 0,
    this.customApps = 0,
    this.customAppsPending = 0,
    this.customAppsUnannounced = false,
    this.reportsToSend = 0,
    this.reportsToCollect = 0,
    this.toolReportsPending = 0,
    this.reportsSending = false,
    this.reportsIntro = false,
    this.autoInstallSkipped = false,
    this.offersElevation = false,
    this.legacyReportsNotice = false,
    this.newPlugins = const [],
    this.canLaunch = false,
    this.task = HomeTask.other,
    this.isCheckingOnline = false,
    this.checkingNow = false,
    this.checkBlocked = false,
    this.launcher,
    this.driveName,
    this.contactName = '',
    this.contactPhone = '',
  });

  final HomeGuidance guidance;

  /// `null` = עוד לא נבדק אם יש אינטרנט.
  final bool? online;
  final String? installedVersion;
  final String? driveAppVersion;

  /// מותקנת גרסה חדשה מהערוץ שנבחר, וממתינים לגרסה חדשה יותר בו: `true`
  /// לערוץ היציב. `null` כשזה לא המצב.
  final bool? appAwaitsNewerStable;

  /// הבדיקה או ההתקנה של התוכנה נכשלו — בגיבור, עם "בדוק שוב".
  final String? appError;

  /// ההתקנה הסתיימה ואוצריא לא נמצאה — הקישור הוא ל"אוצריא — מתקדם".
  final bool appErrorPicksFolder;

  /// ההתקנה בוטלה באשף או שהאשף עוד פתוח, והגרסה החדשה עוד לא כאן.
  final String? appSetupNotice;

  /// יש מה להראות ב"מה חדש?" — של התוכנה או של הספרייה.
  final bool whatsNew;
  final String? onlineAppVersion;

  /// הגרסה שברשת לפי בדיקה שהצליחה, גם כשאין בה חדש — "ברשת:" באריח.
  final String? onlineAppLatest;

  /// `null` — לא מותקנת ([libraryFreshInstall]) או לא ידועה.
  final int? libraryHereVersion;
  final bool libraryFreshInstall;
  final int? driveLibraryVersion;

  /// בכונן יש רק קבצים נלווים לספרייה, בלי גרסת מסד חדשה.
  final String? driveCompanionNames;
  final int? onlineLibraryVersion;

  /// כמו [onlineAppLatest], לספרייה.
  final int? onlineLibraryLatest;
  final String? onlineCompanionNames;
  final int pluginUpdatesOnDrive;

  /// תוספים חדשים, מעודכנים או חסרים בכונן לפי האתר.
  final int onlinePluginChanges;

  /// באתר השתנתה רק רשימת התוספים (למשל תוסף שהוסר).
  final bool onlinePluginCatalogChanged;

  /// באתר יש גרסה חדשה של חנות התוספים שבאוצריא.
  final bool onlineStoreApp;

  /// "עד X" ברשימת ההורדה — חסם עליון שידוע לפני לחיצה, `null` כשאין. לתוספים
  /// אין חסם: גודל הקטלוג אינו כולל את התמונות.
  final int? appDownloadBytes;
  final int? libraryDownloadBytes;

  /// `AppSession.driveFreeBytes`.
  final int? driveFreeBytes;
  final bool syncApp;
  final bool syncLibrary;
  final bool syncPlugins;
  final bool libraryDownloadFailed;

  /// `AppSession.onlineSemanticOffer` — שורה משנית, לא חלק מ"יש חדש".
  final bool semanticOffer;

  /// שמות הקבצים שלא ירדו בהורדה האחרונה; `null` כשאין.
  final String? failedDownloads;

  /// `AppSession.foundNothing`.
  final FoundNothing? foundNothing;

  /// הבדיקה האחרונה ברשת שהצליחה — לשעה ב-[FoundNothing.earlierCheck]
  /// ובשורת המצב (במחשב מחובר בלבד).
  final DateTime? onlineCheckedAt;

  /// הודעות הספרייה שדורשות פעולה (ראו דף הספרייה): קבצים נלווים שחסרים
  /// בכונן, ספרייה שלא נמצאה, כונן שהוכן למחשב אחר, הסכמה לחיפוש חכם.
  final String? libraryMissingNames;
  final bool libraryCompanionsAbsent;
  final bool libraryNotFound;

  /// הכונן הוכן למחשב אחר — הגרסה שממנה הוכן, או "לא ידוע".
  final String? libraryElsewhereFrom;

  /// "רק המחשב שלי": כמה מחשבים נרשמו, והגרסה שממנה מורידים (`null` — אף
  /// מחשב, ואז יורדת הספרייה המלאה).
  final bool personalMode;
  final int personalMachines;
  final int? personalFloor;

  /// `AppSession.preparedForThisMachine`.
  final bool personalPreparedHere;

  /// `AppSession.personalRegistrationPending`.
  final bool personalPending;

  /// `AppSession.personalPendingNeedsClick` — הכפתור במקום ההבטחה.
  final bool personalPendingNeedsClick;
  final bool semanticConsent;
  final TileStatus appTile;
  final TileStatus libraryTile;
  final TileStatus pluginsTile;
  final int pluginsOnDrive;
  final int pluginsInstalled;

  /// כמה תוכנות נוספות בכונן; 0 — אין אריח.
  final int customApps;
  final int customAppsPending;

  /// יש ממתינה שהמחשב הזה עוד לא ראה בדף שלה.
  final bool customAppsUnannounced;
  final int reportsToSend;
  final int reportsToCollect;

  /// דיווחים של הכלי עצמו שממתינים בתור — נשלחים מדף הדיווחים.
  final int toolReportsPending;
  final bool reportsSending;
  final bool reportsIntro;
  final bool autoInstallSkipped;
  final bool offersElevation;

  /// בכונן תורי דיווחים ישנים (Hive) שלא הועברו — הסבר עד "הבנתי".
  final bool legacyReportsNotice;
  final List<String> newPlugins;
  final bool canLaunch;
  final HomeTask task;
  final bool isCheckingOnline;

  /// "בדוק עכשיו" רץ (מקומית ואז ברשת) — מחוון במקום הקישור.
  final bool checkingNow;

  /// משימה ארוכה חוסמת את "בדוק עכשיו" — `AppSession.checkNowBlocked`.
  final bool checkBlocked;

  /// `null` — אין מה לומר על הכלי עצמו.
  final LauncherLine? launcher;

  /// "E:" — שם הכונן שהכלי רץ ממנו, כשיש כזה.
  final String? driveName;

  /// "לעזרה במקום" מהשאלות הנפוצות, כבר בלי רווחים בקצוות.
  final String contactName;
  final String contactPhone;

  bool get hasContact => contactName.isNotEmpty || contactPhone.isNotEmpty;

  bool get readOnly => guidance.readOnly;
  bool get driveFull => guidance.driveFull;

  /// גם בכונן מוגן: הדיווחים שבו נאמרים, אף שאי אפשר לשלוח אותם מכאן.
  bool get showsReportsTile =>
      reportsToSend > 0 ||
      reportsToCollect > 0 ||
      toolReportsPending > 0 ||
      reportsSending;

  bool get showsNewPlugins =>
      newPlugins.isNotEmpty &&
      installedVersion != null &&
      guidance.primary != GuidancePrimary.welcome;
}

/// בונה את המודל מהסשן. נקרא בכל בנייה של הבית — הכול כאן קריאת שדות.
HomeViewModel homeViewModelOf(AppSession s) {
  final launcher = s.readOnly ? null : launcherLineOf(s.launcherUpdate);
  final facts = guidanceFactsFromSession(
    s,
    launcherUpdate: launcherOffersUpdate(launcher),
  );
  final otzaria = s.otzaria;
  final library = s.library;
  final plugins = s.plugins;
  final settings = s.settings.settings;
  final pluginChanges = onlinePluginChangesOf(plugins.onlineStatus);
  final customApps = s.customApps;

  final guidance = deriveHomeGuidance(facts);
  TileStatus tile(GuidanceItem item) => deriveTileStatus(
        item,
        facts,
        download: guidance.downloadItems,
        unchecked: guidance.uncheckedItems,
      );

  return HomeViewModel(
    guidance: guidance,
    online: facts.online,
    installedVersion: otzaria.currentVersion,
    driveAppVersion: otzaria.latestVersion,
    appAwaitsNewerStable:
        otzaria.awaitsNewerInSelectedChannel ? !otzaria.preferPrerelease : null,
    appError: otzaria.status == OtzariaModuleStatus.error
        ? otzaria.errorMessage
        : null,
    appErrorPicksFolder: otzaria.status == OtzariaModuleStatus.error &&
        otzaria.installNotDetected,
    appSetupNotice: switch (otzaria.lastInstallResult) {
      OtzariaInstallResult.cancelled ||
      OtzariaInstallResult.wizardStillOpen
          when otzaria.status == OtzariaModuleStatus.updateAvailable =>
        otzaria.lastInstallNotice,
      _ => null,
    },
    whatsNew:
        whatsNewAppNotes(otzaria) != null || library.changesNotes.isNotEmpty,
    onlineAppVersion:
        otzaria.hasOnlineUpdate ? otzaria.onlineUpdateVersion : null,
    onlineAppLatest: otzaria.onlineCheckError != null
        ? null
        : (otzaria.hasOnlineUpdate ? otzaria.onlineUpdateVersion : null) ??
            otzaria.onlineLatestRelease?.tagName,
    libraryHereVersion: library.localVersion,
    libraryFreshInstall: library.isFreshInstall,
    driveLibraryVersion: library.targetVersion,
    driveCompanionNames: library.companionsOnly
        ? library.pendingCompanionNames
        : semanticOnlyHere(facts)
            ? AppL10n.strings.libraryDomain.companionSemanticName
            : null,
    onlineLibraryVersion:
        library.hasOnlineLibraryUpdate ? library.onlineUpdateVersion : null,
    onlineLibraryLatest:
        library.onlineCheckError != null ? null : library.onlineLatestVersion,
    onlineCompanionNames: library.onlinePendingCompanionNames.isEmpty
        ? null
        : library.onlinePendingCompanionNames,
    pluginUpdatesOnDrive: facts.pluginUpdatesOnDrive,
    onlinePluginChanges: plugins.hasCatalogOnlineUpdate ? pluginChanges : 0,
    onlinePluginCatalogChanged:
        plugins.hasCatalogOnlineUpdate && pluginChanges == 0,
    onlineStoreApp: plugins.storeAppOnline != null,
    appDownloadBytes: otzaria.onlineDownloadBytes,
    libraryDownloadBytes: library.onlineDownloadUpperBound,
    driveFreeBytes: s.driveFreeBytes,
    syncApp: settings.syncApp,
    syncLibrary: settings.downloadsLibrary,
    syncPlugins: settings.syncPlugins,
    libraryDownloadFailed: library.downloadNeedsRetry && !s.isDownloading,
    semanticOffer: s.onlineSemanticOffer,
    failedDownloads:
        library.hasDownloadFailures && settings.downloadsLibrary && !s.readOnly
            ? library.failedDownloadNames
            : null,
    foundNothing: s.foundNothing,
    libraryMissingNames: library.unavailableCompanions.isEmpty
        ? null
        : library.unavailableCompanionNames,
    libraryCompanionsAbsent: library.mirrorLacksCompanions,
    libraryNotFound: library.status == LibraryModuleStatus.needsManualPath,
    libraryElsewhereFrom:
        library.status == LibraryModuleStatus.personalTargetElsewhere
            ? '${library.personalFromVersion ?? ''}'
            : null,
    personalMode: settings.personalUpdateMode,
    personalMachines: library.registeredMachines.length,
    personalFloor: library.registeredMachines.firstOrNull?.version,
    personalPreparedHere: s.preparedForThisMachine,
    personalPending: s.personalRegistrationPending,
    personalPendingNeedsClick: s.personalPendingNeedsClick,
    // כשהגיבור כבר מציע את החיפוש החכם, ההודעה הייתה כפולה; בלי אוצריא אין
    // לאן לכתוב את ההסכמה.
    semanticConsent: s.semanticConsentUnanswered &&
        otzaria.currentVersion != null &&
        !semanticOnlyHere(facts),
    onlineCheckedAt: latestOnlineCheck([
      if (settings.syncApp) (otzaria.onlineCheckedAt, otzaria.onlineCheckError),
      if (settings.downloadsLibrary)
        (library.onlineCheckedAt, library.onlineAnswerError),
      if (settings.syncPlugins) ...[
        (plugins.onlineCheckedAt, plugins.onlineCheckError),
        (plugins.storeAppCheckedAt, plugins.storeAppCheckError),
      ],
    ]),
    appTile: tile(GuidanceItem.app),
    libraryTile: tile(GuidanceItem.library),
    pluginsTile: tile(GuidanceItem.plugins),
    pluginsOnDrive: plugins.plugins.length,
    pluginsInstalled: plugins.installedCount,
    customApps: customApps.apps.length,
    customAppsPending: customApps.pendingApps.length,
    customAppsUnannounced: customApps.unannouncedApps.isNotEmpty,
    reportsToSend: s.errorReports.outboxCount,
    reportsToCollect: s.reportsToCollect,
    toolReportsPending: s.appReports?.pendingCount ?? 0,
    reportsSending: s.uploadingReports || s.errorReports.isUploading,
    reportsIntro: s.showsReportsIntro,
    autoInstallSkipped: s.autoInstallSkipped,
    offersElevation: s.offersElevation,
    legacyReportsNotice: s.showsLegacyReportsNotice,
    newPlugins: [for (final plugin in s.newPluginsForHome) plugin.name],
    canLaunch: otzaria.canLaunch,
    task: switch (s) {
      _ when s.isDownloading => HomeTask.downloading,
      _ when otzaria.status == OtzariaModuleStatus.installing =>
        HomeTask.installingApp,
      _
          when library.isApplying ||
              library.status == LibraryModuleStatus.updating =>
        HomeTask.updatingLibrary,
      _ when plugins.isUpdatingAll => HomeTask.updatingPlugins,
      _ when plugins.isSyncing => HomeTask.syncingPlugins,
      _ when plugins.isExporting => HomeTask.exportingStore,
      _ when customApps.isDownloadingAll => HomeTask.downloadingCustomApps,
      _ when customApps.isBusy || customApps.isLearning => HomeTask.customApps,
      _ when s.launcherUpdate.isInstalling => HomeTask.installingLauncher,
      _ when s.exitPending => HomeTask.restartingElevated,
      _ => HomeTask.other,
    },
    isCheckingOnline: s.isCheckingOnline,
    checkingNow: s.isCheckingNow,
    checkBlocked: s.checkNowBlocked,
    launcher: launcher,
    driveName: driveNameOf(s.dataDir),
    contactName: s.faq.value.contactName.trim(),
    contactPhone: s.faq.value.contactPhone.trim(),
  );
}

/// "מה חדש" של התוכנה: של הגרסה שבכונן כשהיא ממתינה להתקנה, ואחרת של הגרסה
/// המותקנת ([installed]). `null` — אין הערות להראות.
({String version, String notes, bool installed})? whatsNewAppNotes(
  OtzariaModuleController c,
) {
  bool has(String? notes) => notes?.trim().isNotEmpty == true;
  final drive = c.latestVersion;
  if (c.status == OtzariaModuleStatus.updateAvailable) {
    return drive != null && has(c.latestReleaseNotes)
        ? (version: drive, notes: c.latestReleaseNotes!, installed: false)
        : null;
  }
  final installed = c.currentVersion;
  if (installed != null && has(c.installedReleaseNotes)) {
    return (
      version: installed,
      notes: c.installedReleaseNotes!,
      installed: true,
    );
  }
  return null;
}

/// שורת הכלי מציעה גרסה. כשל בלי גרסה ידועה אינו עדכון שמחכה.
bool launcherOffersUpdate(LauncherLine? line) =>
    line != null &&
    !(line.kind == LauncherLineKind.error && line.version == null);

/// המאוחרת מבין הבדיקות ברשת שהצליחו (של הרכיבים שנבחרו); `null` כשאין כזו.
DateTime? latestOnlineCheck(List<(DateTime?, Object?)> checks) {
  DateTime? latest;
  for (final (at, error) in checks) {
    if (at == null || error != null) continue;
    if (latest == null || at.isAfter(latest)) latest = at;
  }
  return latest;
}

/// תוספים שההורדה תביא: חדשים, מעודכנים, וכאלה שהקובץ שלהם חסר בכונן. תוסף
/// שהוסר מהאתר אינו נספר — הוא רק משנה את הרשימה (`onlinePluginCatalogChanged`).
int onlinePluginChangesOf(PluginsOnlineStatus? s) =>
    s == null ? 0 : s.newCount + s.updatedCount + s.missingCount;

LauncherLine? launcherLineOf(LauncherUpdateController c) {
  if (c.isDownloading) return const LauncherLine(LauncherLineKind.downloading);
  if (c.hasUpdateReady) {
    return LauncherLine(
      c.canInstall ? LauncherLineKind.ready : LauncherLineKind.readyManual,
      version: c.downloadedVersion,
    );
  }
  if (c.status == LauncherUpdateStatus.error && c.errorMessage != null) {
    return LauncherLine(
      LauncherLineKind.error,
      version: c.onlineUpdateVersion,
      error: c.errorMessage,
    );
  }
  if (c.hasOnlineUpdate) {
    return LauncherLine(LauncherLineKind.online,
        version: c.onlineUpdateVersion);
  }
  return null;
}

/// גרסה כפי שהמשתמש רואה אותה: בלי "v" ובלי "+build". ה-build נשאר רק כש-[other]
/// (גרסה שמוצגת לצידה) זהה בלעדיו, ושתיהן נושאות build שונה (`sameBuild`).
String displayVersion(String version, {String? other}) {
  final core = OtzariaUpdateCheckResult.normalizeVersion(version);
  if (other == null ||
      OtzariaUpdateCheckResult.normalizeVersion(other) != core ||
      OtzariaUpdateCheckResult.sameBuild(version, other)) {
    return core;
  }
  return _withoutV(version);
}

String _withoutV(String version) {
  final v = version.trim();
  return v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;
}

/// "E:" מתוך נתיב בווינדוס; בשאר המערכות ובנתיב רשת — `null`.
String? driveNameOf(String dataDir) {
  if (!Platform.isWindows) return null;
  final root = p.windows.rootPrefix(dataDir);
  final match = RegExp(r'^([A-Za-z]:)').firstMatch(root);
  return match?.group(1)?.toUpperCase();
}
