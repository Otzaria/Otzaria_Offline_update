import 'app_language.dart';
import 'app_strings.dart';

/// אנגלית — תרגום חופשי של הנוסח העברי, לא מילה במילה: אותה כוונה ואותו
/// אורך בערך, בניסוח שנשמע טבעי לקורא אנגלית.
class EnglishStrings extends AppStrings {
  const EnglishStrings();

  @override
  AppLanguage get language => AppLanguage.english;

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
  FaqStrings get faq => const _Faq();
  @override
  CustomAppsStrings get customApps => const _CustomApps();
  @override
  SetupErrorStrings get setupError => const _SetupError();
  @override
  PayloadMismatchStrings get payloadMismatch => const _PayloadMismatch();
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
  String get confirm => 'OK';
  @override
  String get cancel => 'Cancel';
  @override
  String get continueAction => 'Continue';
  @override
  String get close => 'Close';
  @override
  String get error => 'Error';
  @override
  String get retry => 'Try Again';
  @override
  String get errorDetailsButton => 'Details';
  @override
  String get errorDetailsTitle => 'Error Details';
  @override
  String get install => 'Install';
  @override
  String get update => 'Update';
  @override
  String get launch => 'Open';
  @override
  String get recheck => 'Check Again';
  @override
  String get notCheckedYet => 'Not checked yet';
  @override
  String get checking => 'Checking…';
  @override
  String get upToDate => 'Up To Date';
  @override
  String get updateAvailable => 'Update Available';
  @override
  String get installedIsNewer => 'A Newer Version Is Installed';
  @override
  String get installing => 'Installing…';
  @override
  String get unknownValue => 'Unknown';
  @override
  String get lastDownloaded => 'Last Downloaded';
  @override
  String get emptyValue => '—';
  @override
  String get copyPathButton => 'Copy the path';
  @override
  String get pathCopiedSnack => 'The path was copied';
}

class _Shell extends ShellStrings {
  const _Shell();

  @override
  String get appTitle => 'Otzaria Updates';
  @override
  String get otzariaLogoLabel => 'Otzaria';
  @override
  String get navHome => 'Home';
  @override
  String get navApp => 'Program';
  @override
  String get navLibrary => 'Library';
  @override
  String get navPlugins => 'Plugins';
  @override
  String get navCustomApps => 'Other Programs';
  @override
  String get navSettings => 'Settings';
  @override
  String logPathFallback(String path) => 'Activity log: $path';
}

class _Home extends HomeStrings {
  const _Home();

  @override
  String get title => 'Home';

  @override
  String get otzariaRunningTitle => 'Otzaria is open';
  @override
  String get otzariaRunningSubtitle =>
      'Library updates are blocked until you close it.';

  @override
  String get appTileTitle => 'Otzaria Program';
  @override
  String get libraryTileTitle => 'Library';

  @override
  String get appNoInstallFound => 'No installation found';
  @override
  String get appNothingDownloaded => 'Nothing downloaded yet';

  @override
  String get noActionAvailable =>
      'Nothing to do right now — see below for details and manual options.';
  @override
  String get moreDetails => 'More details';

  @override
  String get appInstallDialogTitle => 'Install the Otzaria Program';
  @override
  String get appInstallConfirm => 'Install';
  @override
  String appInstalledSnack(String version) =>
      'Otzaria was updated to version $version';

  @override
  String get otzariaOpenSnack =>
      'Otzaria is open — please close it and try again.';
  @override
  String get libraryUpdateDialogTitle => 'Update the Library';
  @override
  String libraryFreshInstallPrompt(String targetVersion) =>
      'The library (version $targetVersion) will be installed for the first '
      'time from the folder next to this program. The database is large, so '
      'this may take a while.';
  @override
  String libraryUpdatePrompt(String localVersion, String targetVersion) =>
      'The database will be updated from version $localVersion to version '
      '$targetVersion. The current database will be replaced only after the '
      'new version has been verified.';
  @override
  String get libraryUpdateConfirm => 'Update Now';
  @override
  String libraryUpdatedSnack(String version) =>
      'The database was updated to version $version';

  @override
  String get onlineCardTitle => 'Check for updates';
  @override
  String get onlineCardHint =>
      'Only on a computer with internet — not needed for the install itself.';
  @override
  String get onlineChecking => 'Checking online for updates…';
  @override
  String get onlineNeverChecked => 'Not checked in this session';
  @override
  String get onlineOffline => 'No internet connection right now';
  @override
  String get onlineHasUpdates => 'New updates are available online';
  @override
  String get onlineNoUpdates => 'No new updates online';
  @override
  String onlineNewPlugins(int count) => '$count new plugins in the store';
  @override
  String onlineUpdatedPlugins(int count) =>
      '$count plugins updated in the store';
  @override
  String onlineMissingPlugins(int count) =>
      '$count plugins are missing from the folder — their install file is gone';
  @override
  String get onlinePluginsSyncOff =>
      'Plugin downloads are turned off in Settings — they will be skipped.';
  @override
  String get checkForUpdatesButton => 'Check for updates';
  @override
  String get downloadNowButton => 'Download now';
  @override
  String get cancelDownloadButton => 'Cancel download';
  @override
  String get cancelDownloadPending => 'Cancelling…';
  @override
  String get cancelDownloadDialogTitle => 'Cancel the download?';
  @override
  String get cancelDownloadPrompt =>
      'The files this download fetched will be deleted. Whatever the folder '
      'already held from earlier downloads stays where it is.';
  @override
  String get cancelDownloadKeepGoing => 'Keep downloading';
  @override
  String get downloadCancelledSnack =>
      'The download was cancelled, and what it had fetched was deleted';
  @override
  String downloadSkippedSnack(String components) =>
      'Skipped $components — nothing new for them online';
  @override
  String downloadFailedSnack(String components) =>
      'Downloading $components failed. What already arrived is kept — try '
      'again and the download will continue where it stopped';
  @override
  String get downloadDoneSnack =>
      'Download complete — the folder next to the program is up to date';
  @override
  String lastCheckedAt(String time) => 'Last checked at $time';

  @override
  String get downloadingApp => 'Downloading the Otzaria Program…';
  @override
  String get downloadingLibrary => 'Downloading the Library…';
  @override
  String get downloadingPlugins => 'Downloading the Plugins…';
  @override
  String get downloadStarting => 'Starting the download…';

  @override
  String get libraryNotInstalledYet => 'Library not installed yet';
  @override
  String get libraryUpdating => 'Updating…';
  @override
  String get libraryNothingDownloaded => 'Nothing downloaded yet';
  @override
  String get libraryNeedsManualPath => 'Choose the database file';
}

class _AppScreen extends AppScreenStrings {
  const _AppScreen();

  @override
  String get title => 'Otzaria Program Update';

  @override
  String get stateCardTitle => 'Installation status';
  @override
  String get stateRowTitle => 'Status';
  @override
  String get readyToInstall => 'Ready to install';
  @override
  String get nothingDownloadedYet => 'No version downloaded yet';

  @override
  String get installedVersion => 'Installed version';
  @override
  String get noInstallDetected => 'No installation detected';
  @override
  String get pickInstallDirButton => 'Choose the folder manually';
  @override
  String get pickInstallDirDialogTitle =>
      'Choose the Otzaria installation folder';
  @override
  String get installAdoptedSnack =>
      'Otzaria was found there — the version has been updated';
  @override
  String get installNotFoundSnack =>
      'No Otzaria installation was found in that folder';

  @override
  String get mirrorVersionTitle => 'Version in the local folder';
  @override
  String get mirrorEmpty => 'None — run a download first';
  @override
  String channelPair(String stable, String prerelease) =>
      '$stable (stable) · $prerelease (pre-release)';

  @override
  String get channelTileTitle => 'Version to install';
  @override
  String prereleaseSubtitle(String version) =>
      'The pre-release ($version) — newer, but may still have rough edges';
  @override
  String stableSubtitle(String version) =>
      'The stable release ($version) — recommended';
  @override
  String get channelStable => 'Stable';
  @override
  String get channelPrerelease => 'Pre-release';

  @override
  String get processTitle => 'Otzaria process';
  @override
  String get processRunning =>
      'Running — database updates are blocked until you close it';
  @override
  String get processStopped => 'Not running';

  @override
  String get installingProgress => 'Installing Otzaria…';
  @override
  String get launchButton => 'Open Otzaria';
  @override
  String get installUpdateButton => 'Install the Update';

  @override
  String get whatsNewTitle => "What's new in the latest version";
  @override
  String get whatsNewButton => "What's new";
  @override
  String get whatsNewEmpty =>
      'This version has no release notes, or no version has been downloaded '
      'yet.';

  @override
  String get sourceCardTitle => 'Folder the program is installed from';
  @override
  String get sourceCardHint =>
      'Fixed, next to the executable — see "Library Update" for the full '
      'explanation.';
  @override
  String get sourceDirTitle => 'Program updates Folder';

  @override
  String get fullPackageCardTitle => 'Full installation package';
  @override
  String get fullPackageHint =>
      'The installer that carries the library inside it. Meant for a computer '
      'without Otzaria: it gets the program and the library in one install, '
      'with no internet.';
  @override
  String get fullPackageRowTitle => 'Status';
  @override
  String get fullPackageRecommended =>
      'No Otzaria here — installing from this is recommended';
  @override
  String get fullPackageNotNeeded =>
      'Otzaria is already installed — the full package is not needed';
  @override
  String get fullPackageVersionTitle => 'The package in the local folder';
  @override
  String fullPackageSize(String version, String size) =>
      'Stable version $version — $size';
  @override
  String get fullPackageInstallButton => 'Full install';
  @override
  String get fullPackageDialogTitle => 'Install the full package?';
  @override
  String fullPackagePrompt(String version, String size) =>
      'No Otzaria installation was found on this computer, and the drive '
      'holds the full installation package of Otzaria $version ($size), '
      'library included. Installing from it brings both at once, and needs '
      'no internet.';

  @override
  String installPrompt({
    required String? latestVersion,
    required String? currentVersion,
    required bool prereleaseNote,
  }) {
    final channelNote = prereleaseNote
        ? ' This is the pre-release you selected on the program screen.'
        : '';
    return 'Version $latestVersion will be installed from the local folder '
        'over ${currentVersion ?? 'the existing installation'}.$channelNote '
        'No internet is needed. Make sure Otzaria is closed.';
  }
}

class _LibraryScreen extends LibraryScreenStrings {
  const _LibraryScreen();

  @override
  String get title => 'Library update';

  @override
  String get stateCardTitle => 'Database status';
  @override
  String get stateRowTitle => 'Status';

  @override
  String get dbFileTitle => 'Active seforim.db file';
  @override
  String get dbFileMissing => 'Not found — please select a file';
  @override
  String get pickDbButton => 'Choose a database file';
  @override
  String get pickDbDialogTitle => 'Choose the seforim.db file';
  @override
  String get dbPathUpdatedSnack => 'The database location was updated';

  @override
  String get installTargetTitle => 'The library will be installed to';
  @override
  String get pickInstallDirButton => 'Choose an install location';
  @override
  String get pickInstallDirDialogTitle =>
      'Choose the folder the library will be installed to';
  @override
  String get installDirUpdatedSnack => 'The install location was updated';
  @override
  String get customLocationDialogTitle => 'A location Otzaria does not look in';
  @override
  String customLocationPrompt(String dbPath) => 'Chosen location:\n$dbPath\n\n'
      'This is not Otzaria\'s default location, so it will not find the books '
      'there on its own. After the installation, open Otzaria and point its '
      'library location setting at this folder. Continue with this location?';
  @override
  String get customLocationConfirm => 'Continue with this location';

  @override
  String get localVersionTitle => 'Local Version';
  @override
  String get targetVersionTitle => 'Target version in the local folder';
  @override
  String get targetVersionNothingDownloaded => 'Nothing downloaded yet';
  @override
  String get targetVersionUnknown => 'Unknown — run a check';

  @override
  String get otzariaRunningTitle => 'Otzaria is open';
  @override
  String get otzariaRunningSubtitle =>
      'Close Otzaria before applying an update to the database.';

  @override
  String get updatingProgress => 'Updating the database…';
  @override
  String get installUpdateButton => 'Install the update';
  @override
  String get updateDialogTitle => 'Update the book library';

  @override
  String get reindexTitle => 'Otzaria\'s search index';
  @override
  String get reindexPendingSubtitle =>
      'The database was updated from here, so searching the books that '
      'changed still returns their old content. One request to Otzaria fixes '
      'that.';
  @override
  String get reindexButton => 'Update the index';
  @override
  String get reindexDialogTitle => 'Update the search index';
  @override
  String get reindexDialogContent =>
      'Otzaria will open, reload the library and index the books whose '
      'content changed. The indexing runs inside Otzaria and may take a '
      'while; you can keep working meanwhile. Open it now?';
  @override
  String get reindexDialogConfirm => 'Open Otzaria';
  @override
  String get reindexRequestedSnack => 'Otzaria will update its search index';
  @override
  String reindexFailedSnack(String error) =>
      'The request could not be handed to Otzaria ($error)';

  @override
  String get fullDownloadInsteadButton => 'Install the full library';
  @override
  String get fullDownloadInsteadDialogTitle => 'Install the full library';
  @override
  String fullDownloadInsteadPrompt(String size) =>
      'The incremental update failed, and the database was left untouched. '
      'The full library can be installed instead, from the folder next to '
      'this program ($size) — a long operation that needs free disk space, '
      'and no internet. Install it now?';

  @override
  String get sourceCardTitle => 'Folder the update comes from';
  @override
  String get sourceCardHint =>
      'Fixed, next to the executable. When the program lives on a removable '
      'drive the folder travels with it, and the offline computer reads '
      'straight from it.';
  @override
  String get sourceDirTitle => 'Library Updates Folder';
  @override
  String get mirrorContentTitle => 'Folder contents';
  @override
  String get mirrorEmpty => 'Empty — run a download from the home screen';
  @override
  String get mirrorUnreadable => 'Cannot be read';
  @override
  String mirrorHasVersion(String version) => 'Contains version $version';
  @override
  String get mirrorPresent => 'Present';
  @override
  String get personalVersionTitle => 'My database version (personal update)';
  @override
  String personalVersionRecorded(String version) =>
      'Version $version recorded — the download will start from it';
  @override
  String get personalVersionMissing =>
      'No version recorded yet. Press here on the computer where your Otzaria '
      'is installed, before downloading';
  @override
  String get personalVersionButton => 'Detect my database version';
  @override
  String personalVersionCapturedSnack(String version) =>
      'Version $version recorded for personal update';
  @override
  String get personalVersionNotFoundSnack =>
      'No database was found on this computer to read a version from';
  @override
  String get downloadNoteTitle => 'The last download';
  @override
  String downloadNotePersonal(String version) =>
      'Personal update — update files from version $version onwards, without '
      'the full database';
  @override
  String get downloadNotePersonalUnknownVersion =>
      'Personal update is on, but no local database version was detected — the '
      'full database was downloaded. Run this program once on the computer '
      'where Otzaria is installed.';
  @override
  String downloadNotePersonalUpToDate(String version) =>
      'Personal update — version $version is the latest, nothing to download';
}

class _Settings extends SettingsScreenStrings {
  const _Settings();

  @override
  String get title => 'Settings';

  @override
  String get automationCardTitle => 'Automation';
  @override
  String get automationCardHint =>
      'Default: check locally only, never install on its own.';
  @override
  String get autoCheckTitle => 'Check versions on startup';
  @override
  String get autoCheckSubtitle =>
      'Compares what is installed with what is in the local folder — offline';
  @override
  String get autoOnlineCheckTitle => 'Check online for updates when connected';
  @override
  String get autoOnlineCheckSubtitle =>
      'A light check against GitHub on startup, with no download';
  @override
  String get autoOnlineCheckHint =>
      'Failure (no internet) is ignored silently, and the manual button on '
      'the home screen always works.';
  @override
  String get autoInstallAppTitle => 'Install the Otzaria program automatically';
  @override
  String get autoInstallAppSubtitle =>
      'Installs on startup when a newer version sits in the local folder';
  @override
  String get autoInstallLibraryTitle => 'Install library updates automatically';
  @override
  String get autoInstallLibrarySubtitle =>
      'Applies to the database on startup; skipped while Otzaria is open';

  @override
  String get autoInstallSubjectApp => 'the Otzaria program';
  @override
  String get autoInstallSubjectLibrary => 'the Library';
  @override
  String autoInstallDialogTitle(String subject) =>
      'Install $subject automatically';
  @override
  String autoInstallDialogContent(String subject) =>
      'From now on, $subject will be installed without asking whenever a '
      'newer version is found in the folder next to this program. The '
      'download itself still starts with a click.';
  @override
  String get autoInstallDialogWarning =>
      'Installing replaces files on your computer. If you are not sure, '
      'leave this off and approve each update yourself.';
  @override
  String get autoInstallDialogConfirm => 'Turn on automatic installs';

  @override
  String get downloadCardTitle => 'Download';
  @override
  String get downloadCardHint =>
      'Which parts the "Download now" button on the home screen brings into '
      'the local folder. The download itself always starts with a click.';
  @override
  String get syncAppTitle => 'Otzaria program';
  @override
  String get syncAppSubtitle => 'The installer for the latest version';
  @override
  String get syncLibraryTitle => 'Library';
  @override
  String get syncLibrarySubtitle =>
      'The full package — the full database is about 1 GB';
  @override
  String get syncPluginsTitle => 'Plugin store';
  @override
  String get syncPluginsSubtitle =>
      'The catalogue and the installation files for every plugin';
  @override
  String get syncFullPackageTitle => 'Full Otzaria installation package';
  @override
  String get syncFullPackageSubtitle =>
      'The installer that carries the library inside it — stable, about 2GB';
  @override
  String get syncFullPackageHint =>
      'That is how a computer without Otzaria gets everything in one '
      'install. Off by default — a drive that serves computers which already '
      'have Otzaria does not need it.';

  @override
  String get personalModeTitle => 'Personal update — this computer only';
  @override
  String get personalModeSubtitle =>
      'Only the update files from the version you already have onwards, '
      'without the full database';
  @override
  String get personalModeHint =>
      'The full database is about 1.5 GB. You detect your own database '
      'version with a click, on the library screen.';
  @override
  String get personalModeDialogTitle => 'Turn on personal update?';
  @override
  String get personalModeDialogContent =>
      'The download will bring only the update files from the version you '
      'already have onwards — tens of MB instead of several gigabytes.\n\n'
      'This program never reads your database version on its own: on the '
      'library screen, press "Detect my database version" — on the computer '
      'where your Otzaria is installed. The result is stored on the drive and '
      'travels with it to the online computer, so an Otzaria installed there '
      'cannot take its place.';
  @override
  String get personalModeDialogWarning =>
      'The drive will no longer serve another computer: the next download '
      'removes the full database from it, and the recovery route (a full '
      'install when an update file does not fit) will not be available.';
  @override
  String get personalModeDialogConfirm => 'Turn on personal update';

  @override
  String get appearanceCardTitle => 'Language and Appearance';
  @override
  String get languageTitle => 'Interface Language';
  @override
  String get languageSubtitle =>
      'Changes every screen and message right away. "Automatic" follows the '
      'computer.';
  @override
  String get languageSystem => 'Automatic';
  @override
  String get languageHebrew => 'עברית';
  @override
  String get languageEnglish => 'English';
  @override
  String get themeTitle => 'Theme';
  @override
  String get themeSystem => 'System';
  @override
  String get themeLight => 'Light';
  @override
  String get themeDark => 'Dark';
  @override
  String get showFaqTitle => 'Common-questions button';
  @override
  String get showFaqSubtitle =>
      'The round button in the bottom corner of the home screen that opens the '
      'guide.';

  @override
  String get seedColorTitle => 'Base color';
  @override
  String get seedColorButton => 'Change color';
  @override
  String get seedColorDialogTitle => 'Pick a base color';
  @override
  String get seedColorResetButton => 'Reset';
  @override
  String get seedColorCustom => 'Custom color';
  @override
  String get colorRed => 'Red';
  @override
  String get colorOrange => 'Orange';
  @override
  String get colorAmber => 'Amber';
  @override
  String get colorGreen => 'Green';
  @override
  String get colorTeal => 'Teal';
  @override
  String get colorBlue => 'Blue';
  @override
  String get colorBlueGrey => 'Graphite grey';
  @override
  String get colorNavy => 'Navy';
  @override
  String get colorPurple => 'Purple';
  @override
  String get colorBrown => 'Brown';
  @override
  String get colorParchment => 'Parchment / beige';
  @override
  String get colorGrey => 'Grey';
  @override
  String get colorDarkBrown => 'Golden brown';

  @override
  String get supportCardTitle => 'Support';
  @override
  String get logTitle => 'Activity Log';
  @override
  String get logSubtitle =>
      'Every check, download and install is recorded locally only';
  @override
  String get openLogFolderButton => 'Open the log folder';

  @override
  String get resetTitle => 'Reset settings';
  @override
  String get resetSubtitle =>
      'Restores every setting to its default without removing installations';
  @override
  String get resetButton => 'Reset';
  @override
  String get resetDialogTitle => 'Reset settings';
  @override
  String get resetDialogContent => 'Every setting returns to its default.';
  @override
  String get resetDialogWarning =>
      'Your installations, the database, the plugins and anything already '
      'downloaded are left untouched.';
  @override
  String get resetDialogConfirm => 'Reset settings';
  @override
  String get resetDoneSnack => 'Settings have been reset';
}

class _Plugins extends PluginsStrings {
  const _Plugins();

  @override
  String get syncDialogTitle => 'Sync the plugin store';
  @override
  String get syncDialogContent =>
      'This downloads the plugin list, the categories, the images and the '
      'install files from otzaria.org into the transfer folder. Only new and '
      'updated plugins are fetched — whatever is already there is left alone. '
      'It needs internet once; after that the store works on a computer with '
      'no connection at all.';
  @override
  String get syncDialogConfirm => 'Sync';
  @override
  String get syncFailedSnack => 'The sync failed';
  @override
  String syncDoneSnack(int fetched, int total) => fetched == 0
      ? 'Everything was already up to date — nothing downloaded '
          '($total plugins in the store)'
      : 'Sync complete — $fetched plugins downloaded, out of $total in the '
          'store';
  @override
  String get syncingOverlaySubtitle =>
      'Only new and updated plugins are downloaded — the rest is skipped.';
  @override
  String syncDoneWithWarningsSnack(int count) =>
      'Sync finished, but $count items did not download. Details in the log.';
  @override
  String get syncButton => 'Sync from the site';
  @override
  String get reloadTooltip => 'Reload from the local folder';
  @override
  String get syncingOverlayTitle => 'Syncing the plugin store';
  @override
  String get syncingOverlayStarting => 'Starting…';
  @override
  String get syncNeverRan => 'Never synced';
  @override
  String syncedAt(String time) => 'Last synced: $time';
  @override
  String get syncDirUnknownTooltip =>
      'The folder is chosen during the first sync';
  @override
  String updatesAvailableChip(int count) => '$count updates available';
  @override
  String get updatesChipTooltip => 'Show the plugins waiting for an update';

  @override
  String get saveDialogTitle => 'Save the plugin';
  @override
  String get saveDoneSnack => 'The file was saved';
  @override
  String get saveFailedSnack => 'Saving the file failed';
  @override
  String installOpenedSnack(String pluginName) =>
      'Otzaria was opened to finish installing $pluginName';
  @override
  String get installFailedSnack => 'The installation failed';

  @override
  String get loadingCatalog => 'Loading the plugin catalogue…';
  @override
  String get catalogTitleFallback => 'The Otzaria Plugin Store';
  @override
  String get catalogSubtitleFallback =>
      'Plugins that enhance your learning experience in Otzaria';
  @override
  String get heroSearchHint => 'Search by name, description or topic…';
  @override
  String get heroSearchButton => 'Search';

  @override
  String get emptyStoreTitle => 'The store is still being built — the plugins '
      'are already here';
  @override
  String get emptyStoreBody =>
      'Featured plugins and organized categories are on their way. In the '
      'meantime, search above or browse the full list of plugins.';
  @override
  String allPluginsWithCount(int count) => 'All plugins ($count)';
  @override
  String get browseAllPrompt => "Didn't find what you were looking for?";
  @override
  String browseAllButton(int count) => 'Browse all Plugins ($count)';

  @override
  String get featuredEyebrow => 'Store Picks';
  @override
  String get featuredTitle => 'Featured Plugins';
  @override
  String get showMoreFeatured => 'Show more picks';
  @override
  String categoryLinkButton(int count) => 'See the whole category ($count)';

  @override
  String get breadcrumbRoot => 'Plugin Store';
  @override
  String get allPluginsPage => 'All Plugins';
  @override
  String get listEyebrow => 'Plugin List';
  @override
  String get listTitle => 'Pick the plugin that fits your needs';
  @override
  String get summaryNoResults => 'No plugins match the filters you chose';
  @override
  String get summaryAllShown => 'Showing Every Plugin';
  @override
  String summaryPartial(int shown, int total) =>
      'Showing $shown of $total plugins';
  @override
  String get categoryOnePlugin => 'One plugin in this category';
  @override
  String categoryPluginCount(int count) => '$count plugins in this category';

  @override
  String get hideInstalledLabel => 'Not Installed Only';
  @override
  String hideInstalledOnTooltip(int installedCount) =>
      'Showing only plugins that are not installed or have an update.\n'
      '$installedCount installed plugins were detected in Otzaria.';
  @override
  String hideInstalledOffTooltip(int installedCount) =>
      'Showing every plugin, including installed and up-to-date ones.\n'
      '$installedCount installed plugins were detected in Otzaria.';

  @override
  String get neverSyncedTitle => 'No plugins have been synced yet';
  @override
  String get neverSyncedBody =>
      'Press "Sync from the site" on a computer with internet to load the '
      'current plugin list from otzaria.org.';
  @override
  String get noResultsTitle => 'No plugins match the filters you chose';
  @override
  String get noResultsBody =>
      'Try a different name, clear a tag, pick another status, or turn off '
      '"Not Installed Only".';
  @override
  String get allInstalledTitle => 'Everything is installed and up to date';
  @override
  String get allInstalledBody =>
      'The "Not Installed Only" switch hides plugins you already have at '
      'the latest version. Turn it off to see them too.';
  @override
  String get showInstalledButton => 'Show Installed Plugins Too';
  @override
  String get emptyCategoryTitle => 'Plugins are coming to this category soon';
  @override
  String get emptyCategoryBody =>
      'In the meantime you can browse the full list of plugins in the store.';
  @override
  String get allPluginsButton => 'All Plugins';

  @override
  String get filterSearchLabel => 'Search';
  @override
  String get filterSearchHint => 'Name, description or tag…';
  @override
  String get filterStatusLabel => 'Status';
  @override
  String get filterTagsLabel => 'Tags';
  @override
  String get filterAllTags => 'All tags';
  @override
  String get filterStatusAll => 'All';
  @override
  String get showMoreTags => 'Show More';
  @override
  String get showFewerTags => 'Show Fewer';

  @override
  String get badgeFeaturedShort => 'Featured';
  @override
  String get badgeFeatured => 'Featured Plugin';
  @override
  String pluginVersionBadge(String version) => 'Version $version';
  @override
  String downloadsBadge(int count) => '$count downloads';
  @override
  String get saveButton => 'Save';
  @override
  String get installButton => 'Install';
  @override
  String get directInstallButton => 'Install straight into Otzaria';
  @override
  String get sourcePageButton => 'Source Page';
  @override
  String get cardDetailsLink => 'Full Details';
  @override
  String cardUpdatedOn(String date) => 'Updated $date';
  @override
  String get backToStore => 'Back to the store';

  @override
  String get statusStable => 'Stable';
  @override
  String get statusBeta => 'Beta';
  @override
  String get statusExperimental => 'Experimental';
  @override
  String get statusUnknown => 'Unknown';

  @override
  String get installChipInstalled => 'Installed';
  @override
  String get installChipUpdateAvailable => 'Update Available';
  @override
  String installChipUpdateFrom(String installedVersion) =>
      'Update available (you have $installedVersion)';

  @override
  String get infoPanelTitle => 'General Information';
  @override
  String get tagsPanelTitle => 'Tags';
  @override
  String get screenshotsPanelTitle => 'Screenshots';
  @override
  String get infoVersion => 'Version';
  @override
  String get infoStatus => 'Status';
  @override
  String get infoAuthor => 'Developer';
  @override
  String get infoUpdated => 'Updated';
  @override
  String get infoNetwork => 'Internet needed while using';
  @override
  String get infoNetworkRequired => 'Required';
  @override
  String get infoNetworkNotRequired => 'Not Required';
  @override
  String get infoCompatibility => 'Compatibility';
  @override
  String compatibilityRange(String from, String to) => '$from — up to $to';
  @override
  String get infoLocalFile => 'Plugin file in the local folder';
  @override
  String get infoLocalFileMissing => 'Not downloaded yet — run a sync';
  @override
  String localFileDescription(String fileName, String size) =>
      '$fileName ($size)';
  @override
  String get valueUnspecifiedFeminine => 'Not specified';
  @override
  String get valueUnspecifiedMasculine => 'Not specified';
  @override
  String get sizeUnknown => 'Size unknown';

  @override
  String get categoriesTitle => 'Categories';
  @override
  String get storeHomeItem => 'Store Home';
  @override
  String get storeHomeChip => 'Home';

  @override
  String updatesDialogTitle(int count) => 'Updates are available ($count)';
  @override
  String get updatesDialogIntro =>
      'These plugins are installed in your Otzaria at an older version than '
      'the store has:';
  @override
  String updatesDialogRow(String installedVersion, String storeVersion) =>
      'Installed $installedVersion → store $storeVersion';
  @override
  String get updatesDialogUpdateButton => 'Update';
  @override
  String updatesDialogUpdateAllButton(int count) => 'Update all ($count)';
  @override
  String get updatesDialogDetailsButton => 'Details';
  @override
  String get updatesDialogSentLabel => 'Sent to Otzaria';
  @override
  String get updatesDialogDoneLabel => 'Updated';
  @override
  String get updatesDialogManualOnly => 'Install from the plugin page';
  @override
  String get updatesDialogPendingNote =>
      'The installation itself happens inside Otzaria. Once it is done there, '
      'press "Re-check" to see what has already been updated.';
  @override
  String get updatesDialogRecheckButton => 'Re-check';

  @override
  String get screenshotPrevious => 'Previous';
  @override
  String get screenshotNext => 'Next';
}

class _Faq extends FaqStrings {
  const _Faq();

  @override
  String get title => 'Common questions';
  @override
  String get intro => 'Click a question to see the answer.';

  @override
  String get groupBasics => 'How this works';
  @override
  String get groupDownload => 'Downloading and installing';
  @override
  String get groupLibrary => 'The books are not found';
  @override
  String get groupExtras => 'Plugins and extra programs';
  @override
  String get groupGeneral => 'General questions';

  @override
  String get qWhatIsThis => 'What do I actually do with this program?';
  @override
  String get aWhatIsThis =>
      'When it opens, two tiles appear in the middle of the screen: one for '
      'updating the Otzaria app, one for updating the books. If an update is '
      'waiting, the tile says so. Do the app update first, and only then the '
      'library update.';
  @override
  String get qOfflineFlow =>
      'My computer has no internet — how do I update it?';
  @override
  String get aOfflineFlow =>
      'That is exactly what this program is for. Copy the whole program folder '
      'onto a USB drive, plug the drive into a computer that does have '
      'internet, open the program there and press Download — everything is '
      'collected into that same folder on the drive. Then unplug the drive, '
      'plug it into your own computer, open the program from there and '
      'install. No internet is needed at that stage.';
  @override
  String get qNoOtzariaYet =>
      'I have no Otzaria on this computer at all — is this program for me?';
  @override
  String get aNoOtzariaYet =>
      'Yes. When you press install you will be offered the full installation '
      'package, and that is the recommended choice: it brings both the app and '
      'the books in one step. A regular install on a computer with no Otzaria '
      'may leave it half working. Note that the full package is large (about '
      '2 GB) and is therefore not downloaded on its own — tick it in settings '
      'before downloading.';

  @override
  String get qDownloadStopped =>
      'The download stopped halfway — do I have to start over?';
  @override
  String get aDownloadStopped =>
      'No. The download remembers what it already fetched, and pressing '
      'Download again continues from there. Cancelling on purpose does not '
      'erase earlier runs either — it only clears what the current download '
      'brought in.';
  @override
  String get qDownloadTooBig =>
      'The download is enormous and I only want to update the library I '
      'already have';
  @override
  String get aDownloadTooBig =>
      'Settings has a "personal update" option. With it on, only the steps '
      'from your own version upwards are fetched instead of the whole '
      'library — far less data. Before downloading, go to the Library screen '
      'and press the button that records your library version, otherwise the '
      'program does not know where to start from. One caveat: such a drive '
      'cannot install Otzaria on a computer that has none, so if you update '
      'several computers, leave the option off.';
  @override
  String get qOtzariaOpen => 'It says Otzaria is open and cannot be updated';
  @override
  String get aOtzariaOpen =>
      'An update writes into files that Otzaria itself holds open, so it has '
      'to be closed first. Close Otzaria completely and this program will '
      'notice within seconds and re-enable the buttons.';
  @override
  String get qBrokenAfterUpdate =>
      'I updated and everything came out broken, or it does not work';
  @override
  String get aBrokenAfterUpdate =>
      'Otzaria is still under active development, and moving between versions '
      'can occasionally leave mismatched files behind. In that case: uninstall '
      'Otzaria, delete every folder named Otzaria or otzaria (searching the '
      'computer for the name helps), and then install the full package again.';

  @override
  String get qAppNotDetected =>
      'Otzaria is installed here, but the program does not detect it';
  @override
  String get aAppNotDetected =>
      'If you chose a location other than the default when installing, it is '
      'not found automatically. The fix is easy: launch Otzaria while this '
      'program is open — it will detect it by itself and remember the location '
      'from then on.';
  @override
  String get qDbNotFound => 'It says no database was found, but I have books';
  @override
  String get aDbNotFound =>
      'The book database is likewise not detected when it sits somewhere other '
      'than the default. On the Library screen, pick the location manually. If '
      'you do not know where it is, Otzaria will tell you: open its settings, '
      'and under the Library tab press "copy path".';
  @override
  String get qStillNotFound =>
      'I picked the location by hand and it still finds nothing';
  @override
  String get aStillNotFound =>
      'You most likely have a very old Otzaria (0.9.74 or earlier). Otzaria '
      'has since moved to a new way of storing books, which this program '
      'cannot update. It is best to uninstall Otzaria and install the full '
      'package again.';
  @override
  String get qSearchMissesNewBooks =>
      'I updated the library, but the search in Otzaria does not find the new '
      'books';
  @override
  String get aSearchMissesNewBooks =>
      'Otzaria searches through an index built in advance, and that index does '
      'not refresh by itself once the books have been replaced. Right after a '
      'library update this program offers to ask Otzaria to rebuild it — worth '
      'accepting. If you declined, the offer returns the next time Otzaria '
      'starts.';

  @override
  String get qWhatArePlugins => 'What is the Plugins tab?';
  @override
  String get aWhatArePlugins =>
      'Plugins are helper programs for Otzaria. You can install them straight '
      'from here, or press Save and then install them on any computer that has '
      'Otzaria by double-clicking the file.';
  @override
  String get qWhatAreCustomApps => 'What are "extra programs"?';
  @override
  String get aWhatAreCustomApps =>
      'A place to add helper programs that are not Otzaria — the kind that '
      'help with learning. You fill in once where the program comes from, and '
      'the drive then carries it and installs it even on a computer with no '
      'internet.';

  @override
  String get qWrongFolder =>
      'A message appeared saying the program is in an unsuitable location';
  @override
  String get aWrongFolder =>
      'Everything this program downloads is kept in a folder right beside it, '
      'so that it all travels together on the drive. If it was moved '
      'somewhere without write permission — Program Files, for instance — '
      'there is nowhere to save, so it stops rather than leaving the files on '
      'the wrong computer. The fix: move the whole program folder to the USB '
      'drive, or to an ordinary folder on the disk, and run it from there.';
  @override
  String get qLauncherSelfUpdate => 'Does this program update itself too?';
  @override
  String get aLauncherSelfUpdate =>
      'Yes. When a new version exists it offers to download it on a computer '
      'with internet, then replaces itself and reopens. Your settings, books '
      'and plugins already on the drive stay untouched.';
  @override
  String get qFree => 'Wow, is all of this really free?';
  @override
  String get aFree =>
      'Yes. Otzaria was built by people who set out to spread Torah learning, '
      'and so they make it freely available to anyone who wants it.';
  @override
  String get qNoExpenses => 'Still, how can that be — do they have no costs?';
  @override
  String get aNoExpenses =>
      'Development costs are considerable. The developers themselves take no '
      'payment, but the work itself costs real money. Anyone who wants to take '
      'part can donate through Nedarim Plus: open "Kupot Nosafot" (further '
      'funds), then "Tzorchei Rabim - Kranot" (communal needs - funds), and '
      'pick "Otzaria" there. That site is in Hebrew only.';

  @override
  String get contactTitle => 'Still have a question?';

  @override
  String get editTooltip => 'Customise this guide';
  @override
  String get editDoneTooltip => 'Done customising';
  @override
  String get editIntro =>
      'Here you can hide questions that do not apply to you, add your own, and '
      'put your details at the bottom of the list. Customisations are saved in '
      'the folder beside the program and travel with it on the drive.';

  @override
  String get hideTooltip => 'Hide this question';
  @override
  String get restoreTooltip => 'Bring this question back';
  @override
  String get hiddenLabel => 'hidden';

  @override
  String get myQuestionsTitle => 'Questions I added';
  @override
  String get noExtrasYet => 'You have not added any questions yet.';
  @override
  String get addQuestionButton => 'Add a question';
  @override
  String get editQuestionTooltip => 'Edit this question';
  @override
  String get deleteQuestionTooltip => 'Delete this question';

  @override
  String get formAddTitle => 'New question';
  @override
  String get formEditTitle => 'Edit question';
  @override
  String get formQuestionLabel => 'Question';
  @override
  String get formAnswerLabel => 'Answer';
  @override
  String get formSave => 'Save';
  @override
  String get formIncompleteSnack => 'Fill in both the question and the answer.';

  @override
  String get deleteConfirmTitle => 'Delete this question?';
  @override
  String get deleteConfirmContent =>
      'The question and its answer will be removed from the guide. You can add '
      'them again at any time.';

  @override
  String get contactCardTitle => 'My details at the bottom of the guide';
  @override
  String get contactCardHint =>
      'If you prepare drives for other people, put here who they should '
      'contact. An empty field is simply not shown.';
  @override
  String get contactNameLabel => 'Name';
  @override
  String get contactPhoneLabel => 'Phone';
  @override
  String contactPhoneLine(String phone) => 'Phone: $phone';
}

class _SetupError extends SetupErrorStrings {
  const _SetupError();

  @override
  String get title => 'This program is in the wrong place';
  @override
  String get explanation =>
      'The launcher keeps all of its data — the library, the plugins and the '
      'Otzaria program itself — in a folder right next to it, so everything '
      'travels together on the drive. The current folder is not writable, so '
      'there is nowhere to save.';
  @override
  String get whatToDo =>
      'What to do: move the whole program folder onto the removable drive '
      '(or into any folder on disk that is not under Program Files), and run '
      'it from there.';
  @override
  String get attemptedDirTitle => 'Folder that was tried';
  @override
  String cannotWriteToDataDir(String osMessage) =>
      'Cannot write to the folder next to this program: $osMessage';
}

class _PayloadMismatch extends PayloadMismatchStrings {
  const _PayloadMismatch();

  @override
  String get title => 'The program files do not match each other';
  @override
  String get explanation =>
      'The executable is from one version, and the files in the app-files '
      'folder next to it are from another. This happens when an update did '
      'not finish, or when the folder was copied between computers without '
      'all of its files. Running like this can hang or close by itself, so '
      'it was stopped here.';
  @override
  String get whatToDo =>
      'What to do: close the program and open it again. It will restore the '
      'missing files by itself — this can take up to a minute, and a black '
      'window will appear meanwhile; do not close it. If this message comes '
      'back after reopening, copy the executable into a new empty folder on '
      'the hard drive and run it from there.';
  @override
  String get runningVersionTitle => 'Version actually running';
  @override
  String get expectedVersionTitle => 'Version of the executable';
  @override
  String get closeButton => 'Close the program';
}

class _LauncherUpdate extends LauncherUpdateStrings {
  const _LauncherUpdate();

  @override
  String get cardTitle => 'Update this program';
  @override
  String get cardHint =>
      'Otzaria Updates itself. The update replaces the program only — your '
      'data, your settings and the folder beside it stay exactly as they are.';
  @override
  String installedVersion(String version) => 'Installed version: $version';
  @override
  String downloadedVersion(String version) => 'Downloaded version: $version';
  @override
  String onlineVersion(String version) => 'Version online: $version';

  @override
  String get statusUpToDate => 'Up to date';
  @override
  String get statusUpdateAvailable => 'A new version is available';
  @override
  String get statusReadyToInstall => 'Ready to install';
  @override
  String get statusDownloading => 'Downloading the new version';
  @override
  String get statusInstalling => 'Installing the new version';

  @override
  String get downloadButton => 'Download the new version';
  @override
  String get installButton => 'Install and restart';

  @override
  String get availableDialogTitle => 'Update for Otzaria Updates';
  @override
  String availableDialogContent(String version) =>
      'Version $version of Otzaria Updates is available. Download it now?';
  @override
  String availableDialogDetail(String size) =>
      'Download size: $size. The file is kept in the folder beside the '
      'program, and the installation itself runs from the launcher — even on '
      'a computer with no internet.';
  @override
  String get availableDialogConfirm => 'Download now';
  @override
  String get availableDialogCancel => 'Not now';

  @override
  String get readyDialogTitle => 'The new version is ready';
  @override
  String readyDialogContent(String version) =>
      'Version $version has been downloaded. Install it now? The program will '
      'close and reopen in the new version, from the very same location, and '
      'your data and settings will stay as they are.';
  @override
  String get readyDialogConfirm => 'Install and restart';

  @override
  String downloadedSnack(String version) =>
      'Version $version was downloaded to the folder beside the program';
  @override
  String get installingSnack =>
      'Installing the new version — the program will reopen in a moment';
  @override
  String get manualRestartNotice =>
      'The new version is in place. Close the program and open it again to '
      'start using it.';

  @override
  String get versionTileTitle => 'Program version';

  @override
  String get executableNotFound =>
      'The executable this program runs from could not be located, so there '
      'is nothing to replace. Please download the new version and replace the '
      'file manually.';
  @override
  String get mirrorMissing =>
      'The new version has not been downloaded to the folder beside the '
      'program yet — run a download on a computer with internet.';
  @override
  String unsupportedPlatform(String operatingSystem) =>
      'Self-update is supported on Windows and macOS only '
      '(detected: $operatingSystem).';
  @override
  String downloadFailed(int statusCode) =>
      'Downloading the new version failed: status $statusCode';
  @override
  String sizeMismatch(int received, int expected) =>
      'The downloaded file is not the expected size ($received bytes '
      'received, $expected expected) — the download was probably cut short.';
  @override
  String replaceFailed(String error) =>
      'Replacing the executable failed: $error. The previous file was put '
      'back in place.';
  @override
  String restartFailed(String error) =>
      'Launching the new version failed: $error. Please close the program and '
      'start it again manually — the replacement itself already finished.';
}

class _Units extends UnitStrings {
  const _Units();

  @override
  String bytes(int count) => count == 1 ? '1 byte' : '$count bytes';
  @override
  String progressOf(String received, String total) => '$received of $total';
  @override
  String kilobytes(String amount) => '$amount KB';
  @override
  String megabytes(String amount) => '$amount MB';
  @override
  String gigabytes(String amount) => '$amount GB';
}

class _LibraryDomain extends LibraryDomainStrings {
  const _LibraryDomain();

  @override
  String unsupportedPatchCompression(String compression) =>
      'Unsupported compression in the patch: $compression';
  @override
  String get manifestMissingPatchFiles =>
      'Required manifest field is missing or empty: patchFiles';
  @override
  String manifestMissingField(String key) =>
      'Required manifest field is missing or invalid: $key';
  @override
  String releasesRequestFailed(int statusCode) =>
      'Could not fetch the release list: HTTP $statusCode';
  @override
  String get releasesResponseNotList =>
      'The releases response from GitHub is not a list';
  @override
  String manifestDownloadFailed(String url, int statusCode) =>
      'Could not download the manifest ($url): HTTP $statusCode';
  @override
  String manifestNotJsonObject(String url) =>
      'The manifest is not a valid JSON object: $url';

  @override
  String get interruptedUpdateFound =>
      'An unfinished update was flagged — please verify the database';

  @override
  String get exportLoadingReleases => 'Loading the version list from GitHub';
  @override
  String get exportNoReleases =>
      'No releases with database updates were found to download.';
  @override
  String exportPersonalFrom(int localVersion) =>
      'Personal update: downloading update files from version $localVersion '
      'onwards, without the full database';
  @override
  String exportPersonalUpToDate(int localVersion) =>
      'Nothing newer than $localVersion — nothing was downloaded';
  @override
  String get exportPersonalVersionUnknown =>
      'No local database version was detected — downloading the full database';
  @override
  String exportReusingFullDb(int version, String tag) =>
      'Keeping the full database already in the folder (version $version, '
      '$tag) — update files can carry it to the latest version, so there is '
      'no need to download it again';
  @override
  String exportDownloading(String tag, String asset) =>
      'Downloading $tag / $asset';
  @override
  String exportVerifying(String tag, String asset) => 'Verifying $tag / $asset';
  @override
  String exportWritingManifest(String fileName) => 'Writing $fileName';
  @override
  String get exportDone => 'Done';
  @override
  String get exportCancelled => 'The export was cancelled';
  @override
  String get exporterDoesNotExtract =>
      'LibraryMirrorExporter only downloads files, it does not extract them';
  @override
  String exportManifestUnreadable(String asset, String detail) =>
      'The manifest $asset could not be read, so it was skipped ($detail)';
  @override
  String exportManifestFetchFailed(String asset, String detail) =>
      'Fetching the manifest $asset failed even after retries. The download '
      'stopped rather than write an incomplete mirror — try again on a stable '
      'connection. ($detail)';
  @override
  String exportPatchAssetMissing(String tag, String file) =>
      'The file $file of $tag is not available for download right now (it may '
      'still be uploading), so the update route through it will not enter the '
      'mirror';

  @override
  String get planLocalVersionUnknown =>
      'The local database version is unknown (schema_meta.db_version is '
      'missing)';
  @override
  String planContentChangedWithoutVersionBump(String releaseTag) =>
      'The database contents changed in $releaseTag without a version bump';
  @override
  String planNoDeltaRoute(int localVersion, int latestVersion) =>
      'There is no continuous delta route from version $localVersion to '
      'version $latestVersion';
  @override
  String planNoFullDbEither(String reason) =>
      '$reason, and no full database is available to download';

  @override
  String mirrorManifestMissing(String fileName, String mirrorDir) =>
      'No $fileName file in the folder: $mirrorDir — make sure this is a '
      'valid mirror folder created by "prepare an update for transfer".';
  @override
  String mirrorManifestCorrupt(
    String fileName,
    String mirrorDir,
    String error,
  ) =>
      'The $fileName file in $mirrorDir is corrupt: $error';
  @override
  String mirrorManifestUnexpectedShape(String fileName, String mirrorDir) =>
      'The $fileName file in $mirrorDir is not in the expected format.';
  @override
  String mirrorPatchManifestMissing(String url) =>
      'A manifest file is missing from the local mirror: $url';
  @override
  String mirrorPatchManifestCorrupt(String url, String error) =>
      'The manifest file is corrupt ($url): $error';
  @override
  String mirrorPatchManifestNotJson(String url) =>
      'The manifest is not a valid JSON object: $url';

  @override
  String unsupportedSchemaForHashOrder(int schemaVersion) =>
      'Schema version $schemaVersion is not supported for choosing the hash '
      'order';
  @override
  String localVersionMismatch(int? localVersion, int expected) =>
      'The local database version ($localVersion) does not match the patch '
      '(expected $expected)';
  @override
  String localSchemaMismatch(int localSchema, int expected) =>
      'The local database schema ($localSchema) does not match the patch '
      '(expected $expected)';
  @override
  String get contentHashMismatchNeedsFullDownload =>
      'The local database differs from what was expected — its hash does not '
      'match fromContentHash. A full download is required.';
  @override
  String patchUniqueConflictNeedsFullDownload(String table, String detail) =>
      'This patch does not fit the database on this computer: a unique-value '
      'conflict in table "$table". The incremental update was cancelled and '
      'the database was left untouched. A full download of the library is '
      'required. ($detail)';
  @override
  String foreignKeyViolationsGrew(int before, int after) =>
      'Foreign-key violations increased ($before→$after) — the patch is not '
      'valid';
  @override
  String resultHashMismatch(String actual, String expected) =>
      'The hash after applying ($actual) does not match toContentHash '
      '($expected)';
  @override
  String get patchMetaSchemaVersionMissing =>
      'patch_meta.schema_version is missing from the patch';
  @override
  String patchSchemaTooNew(int schemaVersion, int supported) =>
      'The patch schema version ($schemaVersion) is newer than supported '
      '($supported) — please update this program';
  @override
  String patchVersionRangeMismatch(
    int? from,
    int? to,
    int manifestFrom,
    int manifestTo,
  ) =>
      'The patch versions ($from→$to) do not match the manifest '
      '($manifestFrom→$manifestTo)';

  @override
  String get compressedFileSizeLabel => 'The compressed file size';
  @override
  String get compressedFileHashLabel => 'The sha256 of the compressed file';
  @override
  String get extractedFileSizeLabel => 'The extracted file size';
  @override
  String get extractedFileHashLabel => 'The sha256 of the extracted file';
  @override
  String get patchExtractionFailed =>
      'Extracting the patch failed or produced nothing';
  @override
  String get deleteExistingWithoutResumeIdentityFailed =>
      'Could not delete an existing file with no resume identity — the '
      'download cannot continue';
  @override
  String get deletePartialFromPreviousVersionFailed =>
      'Could not delete a partial file from an earlier version — the '
      'download cannot continue';
  @override
  String get deletePartialWithoutValidatorFailed =>
      'Could not delete a partial file with no validator — the download '
      'cannot continue';
  @override
  String get deletePartialFromPreviousRepresentationFailed =>
      'Could not delete a partial file from an earlier representation — the '
      'download cannot continue';
  @override
  String get deletePartialBeforeRetryFailed =>
      'Could not delete a partial file before retrying — the download cannot '
      'continue';
  @override
  String fullDbSizeMismatch(int downloaded, int expected) =>
      'The downloaded database size ($downloaded) does not match the '
      'expected size ($expected)';
  @override
  String get fullDbHashMismatch =>
      'The sha256 of the full database does not match';
  @override
  String resumeRoundLimit(int maxRounds, String url) =>
      'Resuming the download passed the maximum number of rounds '
      '($maxRounds): $url';
  @override
  String contentLengthMismatch(int responseLength, int expectedSize) =>
      'The download Content-Length ($responseLength) does not match the '
      'expected size ($expectedSize)';
  @override
  String truncatedBody(int declared, int received) =>
      'The download was cut short: Content-Length declared $declared bytes, '
      'but $received arrived';
  @override
  String downloadHttpError(int statusCode, String url) =>
      'Download error (HTTP $statusCode): $url';
  @override
  String resumeMadeNoProgress(String url) =>
      'Resuming the download made no progress: $url';
  @override
  String resumeFailedAfterRetry(String url) =>
      'Resuming the download failed after a retry: $url';
  @override
  String downloadExceedsExpectedSize(int expectedSize) =>
      'The download is larger than expected ($expectedSize bytes)';
  @override
  String saveDownloadedFileFailed(String error) =>
      'Saving the downloaded file to disk failed: $error';
  @override
  String tooManyRedirects(String url) => 'Too many redirects: $url';
  @override
  String writeResumeSidecarFailed(String path, String error) =>
      'Could not write the resume identity file ($path): $error';
  @override
  String checksumMismatchDetailed(
    String label,
    String expected,
    String actual,
  ) =>
      '$label does not match: expected $expected, got $actual';
  @override
  String checksumMismatch(String label) => '$label does not match';
  @override
  String localFileNotFound(String path) => 'Local file not found: $path';
  @override
  String localFileTooLarge(int maxBytes, String path) =>
      'The local file is larger than expected ($maxBytes bytes): $path';
  @override
  String localSourceNotFound(String url) => 'Local source file not found: $url';
  @override
  String localFileSizeMismatch(int expected, int actual, String url) =>
      'The local file size does not match: expected $expected, got $actual '
      '($url)';
  @override
  String localFileHashMismatch(String url) =>
      'The sha256 of the local file does not match: $url';

  @override
  String get mirrorMissing =>
      'No library updates have been downloaded into the local folder yet — '
      'run a download on a computer with internet.';
  @override
  String interruptedUpdateNeedsManualFix(String detail) =>
      '$detail — quick_check actually failed, so this needs manual attention '
      '(restore from an external backup).';
  @override
  String get interruptedUpdateDefaultDetail => 'An interrupted database update';
  @override
  String get blockedNeedsManualAction => 'Blocked — manual action is needed';
  @override
  String get blockedNeedsManualActionWithPeriod =>
      'Blocked — manual action is needed.';
  @override
  String patchUrlMissing(String fileName) =>
      'No download URL was found for $fileName';
  @override
  String get fullDbAssetMissingFromPlan =>
      'The plan contains no full-database asset';
  @override
  String get fullDbExtractionFailed =>
      'Extracting the full database failed or produced nothing';
  @override
  String versionMismatchAfterWrite(int? actual, int? expected) =>
      'After writing the full database, the version read back ($actual) does '
      'not match the target ($expected) — it was rolled back.';
  @override
  String get updateCancelled => 'The update was cancelled';
  @override
  String notEnoughDiskSpace(String dir, String needed, String free) =>
      'Not enough free space in $dir: $needed is needed and $free is free. '
      'Free up space on that drive and try again, or choose another location '
      'for the database.';
  @override
  String installDirNotWritable(String dir, String detail) =>
      'The folder $dir could not be created ($detail). Choose another location '
      'for the database through "Choose location manually" on the library '
      'screen.';
  @override
  String mirrorNotEnoughDiskSpace(String dir, String needed, String free) =>
      'Not enough free space in $dir for the download: $needed is needed and '
      '$free is free. Free up space and try again — what already arrived is '
      'kept.';
  @override
  String get otzariaIsRunning =>
      'Otzaria is currently open — close it before updating the database so '
      'the file is not locked.';
  @override
  String get zstdContextCreationFailed =>
      'Could not create the decompression context (DCtx)';
  @override
  String zstdDecompressionFailed(String errorName) =>
      'zstd decompression failed: $errorName';
  @override
  String get zstdEmptyInput => 'The compressed file is empty';
  @override
  String get zstdTruncatedFrame =>
      'The compressed file was cut short — the frame is incomplete';

  @override
  String dbIntegrityCheckFailed(String result) =>
      'The integrity check of the downloaded database failed: $result';

  @override
  String get companionTalmudName => 'Talmud Bavli';
  @override
  String get companionCatalogName => 'Otzar HaChochma & HebrewBooks catalog';
  @override
  String get companionDictionaryName => 'Fuzzy-search dictionary';
  @override
  String companionChecking(String name) => 'Checking $name…';
  @override
  String companionDownloading(String name) => 'Downloading $name…';
  @override
  String companionInstalling(String name) => 'Installing $name…';
  @override
  String companionAssetMissingInRelease(String name) =>
      'No file for $name was found in the latest release';
  @override
  String companionExtractionFailed(String name) => 'Extracting $name failed';
  @override
  String get companionsMirrorMissing =>
      'The companion files have not been downloaded to the local folder yet';

  @override
  String applyDownloadingPatch(String step) => 'Downloading the update$step…';
  @override
  String applyApplyingPatch(String step) =>
      'Applying the update to the database$step…';
  @override
  String applyPatchStage(String stage, String step) {
    switch (stage) {
      case 'preflight':
        return 'Checking compatibility$step…';
      case 'verifyFromHash':
        return 'Verifying the existing database$step…';
      case 'attach':
        return 'Opening the update file$step…';
      case 'migrations':
        return 'Updating the database structure$step…';
      case 'upserts':
        return 'Writing the changes$step…';
      case 'deletes':
        return 'Removing deleted records$step…';
      case 'foreignKeyCheck':
        return 'Checking link integrity$step…';
      case 'verifyToHash':
        return 'Verifying the update result$step…';
      case 'commit':
        return 'Saving the changes$step…';
      default:
        return applyApplyingPatch(step);
    }
  }

  @override
  String get applyDownloadingFullDb => 'Downloading the full database…';
  @override
  String get applyDecompressingFullDb => 'Extracting the database…';
  @override
  String get applyWritingFullDb => 'Writing the database…';
  @override
  String get applyVerifying => 'Verifying…';
  @override
  String get applyInstallingCompanions => 'Installing companion files…';
  @override
  String get applyDone => 'Done.';
}

class _AppDomain extends AppDomainStrings {
  const _AppDomain();

  @override
  String get channelStable => 'stable';
  @override
  String get channelPrerelease => 'pre-release';
  @override
  String downloadingChannel(String channelLabel) =>
      'Downloading the Otzaria program ($channelLabel version)…';
  @override
  String get downloadingFullPackage => 'Downloading the full package';
  @override
  String get downloadCancelled => 'The download was cancelled.';

  @override
  String get noInstallableReleaseForPlatform =>
      'No Otzaria version that can be installed on this platform was found.';
  @override
  String get fullPackageNotOnDrive =>
      'The full installation package is not in the local folder — tick it in '
      'settings and run a download on a computer with internet.';
  @override
  String get mirrorEmptyRunDownload =>
      'There is no Otzaria version in the local folder — run a download on a '
      'computer with internet.';
  @override
  String get noOtzariaInstallFound =>
      'No Otzaria installation was found on this computer — install it, or '
      'choose the folder of an existing installation.';
  @override
  String get corruptReleaseMetadata => 'Corrupt Otzaria release metadata';
  @override
  String unsupportedPlatform(String operatingSystem) =>
      'The launcher can install Otzaria on Windows and macOS only '
      '(detected: $operatingSystem).';
  @override
  String noAssetForPlatform(
    String tagName,
    String platform,
    List<String> expectedSuffixes,
  ) {
    final suffixes = expectedSuffixes.map((s) => '"$s"').join(' or ');
    return 'Release "$tagName" has no installer for $platform (expecting a '
        'name ending in $suffixes).';
  }

  @override
  String installerDownloadFailed(int statusCode) =>
      'Downloading the installer failed: HTTP $statusCode';
  @override
  String installerSizeMismatch(int received, int expected) =>
      'The downloaded installer is not the expected size ($received bytes '
      'received, $expected expected) — the download was probably cut short.';
  @override
  String installerExitCode(int exitCode, String output) =>
      'The installer exited with code $exitCode.\n$output';
  @override
  String installerLogTail(String tail) => 'End of the installer log:\n$tail';
  @override
  String get macAppNotFoundInArchive =>
      'No .app bundle was found inside the extracted package — the layout of '
      'the Otzaria macOS asset may have changed.';
  @override
  String macReplaceFailed(String error) =>
      'Replacing the .app bundle in the install folder failed: $error';
  @override
  String dittoExtractFailed(int exitCode, String output) =>
      'Extracting the package (ditto) failed with code $exitCode.\n$output';
  @override
  String hdiutilAttachFailed(int exitCode, String output) =>
      'Mounting the disk image (hdiutil attach) failed with code '
      '$exitCode.\n$output';
  @override
  String get macAppNotFoundInDmg =>
      'No .app bundle was found inside the mounted disk image.';
  @override
  String dittoCopyFailed(int exitCode, String output) =>
      'Copying the .app from the disk image (ditto) failed with code '
      '$exitCode.\n$output';
  @override
  String installNotDetected(String installDir, int timeoutSeconds) =>
      'No Otzaria installation appeared in $installDir within '
      '$timeoutSeconds seconds of the installer finishing. It may still be '
      'running in the background, or the install path may have changed in a '
      'newer installer.';
  @override
  String launchFileMissing(String launchPath) =>
      'The executable was not found at: $launchPath';
  @override
  String launchFailed(int exitCode, String stderr) =>
      'Opening Otzaria failed (open returned $exitCode): $stderr';
  @override
  String githubStatus(int statusCode, String uri) =>
      'The GitHub API returned status $statusCode for $uri';
  @override
  String noReleasesAtAll(String repo) => 'No releases at all were found in '
      '$repo.';
  @override
  String get windowsOnlyReader =>
      'WindowsExeVersionReader only works on Windows.';
  @override
  String get macOnlyReader => 'MacAppVersionReader only works on macOS.';
}

class _PluginsDomain extends PluginsDomainStrings {
  const _PluginsDomain();

  @override
  String get fileNotAvailableSyncFirst =>
      'The file is not available locally. Run a sync first.';
  @override
  String saveFailed(String error) => 'Saving the file failed: $error';
  @override
  String get pluginFileNotAvailable =>
      'The plugin file is not available. Run a sync first.';
  @override
  String get localPluginFileMissing =>
      'The local plugin file is missing. Please sync again.';
  @override
  String get badPluginExtension =>
      'The plugin file does not have a valid otzplugin extension.';
  @override
  String get otzariaOpenFailedHint =>
      'Opening Otzaria failed. Make sure Otzaria is installed on this '
      'computer. ';
  @override
  String otzariaOpenFailed(String error) => 'Opening Otzaria failed: $error';
  @override
  String get directInstallUnsupportedPlatform =>
      'Direct installation is supported on Windows and macOS only.';

  @override
  String get syncLoadingCatalog => 'Loading the plugin list from the site…';
  @override
  String syncPlugin(String name, int done, int total) =>
      'Syncing: $name ($done/$total)';
  @override
  String get syncDone => 'Sync complete';
  @override
  String syncDoneCounts(int fetched, int skipped) =>
      'Sync complete: $fetched plugins updated, $skipped already up to date';
  @override
  String get syncCategories => 'Syncing the store categories…';
  @override
  String syncStructureFailed(String error) =>
      'Could not load the store structure from the site ($error) — keeping '
      'the previous structure';
  @override
  String get syncStructureEmpty => 'the site returned no categories';
  @override
  String get syncEmptyCatalogRejected =>
      'The site returned an empty plugin list — the store already downloaded '
      'was left untouched. Worth trying again later.';
  @override
  String syncCategoryFailed(String name, String error) =>
      'Could not load the $name category: $error';
  @override
  String syncImageFailed(String name, String error) =>
      'Could not download the image for $name: $error';
  @override
  String syncScreenshotFailed(String name, String error) =>
      'Could not download a screenshot for $name: $error';
  @override
  String syncPluginFileFailed(String name, String error) =>
      'Could not download the plugin file for $name: $error';

  @override
  String get whatPluginList => 'the plugin list';
  @override
  String get whatStoreStructure => 'the store structure';
  @override
  String whatCategory(String slug) => 'the $slug category';
  @override
  String get responseNotPluginList =>
      'The site response is not a valid plugin list';
  @override
  String get networkTimedOut => 'The site did not respond in time';
  @override
  String siteUnreachable(String error) =>
      'Could not reach the Otzaria site: $error';
  @override
  String loadFailed(String what, int statusCode) =>
      'Could not load $what (HTTP $statusCode)';
  @override
  String responseNotJson(String what) =>
      'The site response for $what is not valid JSON';
  @override
  String get responseUnexpectedShape =>
      'The site response is not in the expected shape';
  @override
  String httpStatusFor(int statusCode, String url) =>
      'HTTP $statusCode for $url';
}

class _CustomAppsDomain extends CustomAppsDomainStrings {
  const _CustomAppsDomain();

  @override
  String get descriptorNotJson => 'The plugin file is not valid JSON';
  @override
  String descriptorUnsupportedSchema(int found, int supported) =>
      'This plugin was written for format version $found, and this program '
      'reads up to $supported. Please update the program';
  @override
  String descriptorMissingField(String field) =>
      'The plugin is missing the "$field" field, or it is empty';
  @override
  String descriptorInvalidId(String id) =>
      'The id "$id" is not valid. Only lowercase letters, digits, dots, '
      'hyphens and underscores are allowed';
  @override
  String descriptorUnknownInstallerKind(String found, String allowed) =>
      'Installer type "$found" is not supported. Supported types: $allowed';
  @override
  String descriptorUnknownSourceKind(String found, String allowed) =>
      'Version source "$found" is not supported. Supported sources: $allowed';

  @override
  String appAlreadyRegistered(String name) => '$name is already on the list';
  @override
  String appNotRegistered(String id) => 'No program found with the id $id';

  @override
  String get noInstallerInMirror =>
      'No installer is stored for this program — add one on a computer that '
      'has the file';
  @override
  String installerFileMissing(String path) => 'Installer file not found: $path';
  @override
  String installerExitCode(int exitCode, String output) =>
      'The installation failed (exit code $exitCode).\n$output';
  @override
  String fileCopyFailed(String error) => 'Copying the file failed: $error';
  @override
  String launchFileMissing(String launchPath) =>
      'Executable not found: $launchPath';

  @override
  String githubStatus(int statusCode, String uri) =>
      'GitHub returned error $statusCode for $uri';
  @override
  String get githubBadResponse =>
      'The GitHub response is not in the expected shape';
  @override
  String get githubNoReleases => 'No releases were found in this repository';
  @override
  String githubNoMatchingAsset(String tagName) =>
      'Release $tagName has no file matching the one that was chosen. The '
      'file name may have changed — please choose it again';
  @override
  String downloadFailed(int statusCode) =>
      'The download failed (error $statusCode)';
  @override
  String get sourceIsNotGithub =>
      'This program has no repository set — there is nothing to check online';
}

class _CustomApps extends CustomAppsStrings {
  const _CustomApps();

  @override
  String get screenTitle => 'Other Programs';

  @override
  String get settingsCardTitle => 'Other Programs';
  @override
  String get settingsCardHint =>
      'You can add your own programs, and this app will carry them on the '
      'drive and install them on the offline computer — exactly as it does '
      'for Otzaria.';
  @override
  String get emptyHint => 'No programs added';
  @override
  String get addButton => 'Add a Program';

  @override
  String get addDialogTitle => 'Add a Program';
  @override
  String get editDialogTitle => 'Edit Program';
  @override
  String get nameLabel => 'Program name';
  @override
  String get nameHint => 'As it will appear in your list';
  @override
  String get descriptionLabel => 'Description';
  @override
  String get descriptionHint => 'A short line to remind you what this is';
  @override
  String get installDirLabel => 'Install location';
  @override
  String get installDirHint =>
      'Can be left empty — the location is found by itself after the first '
      'install.';
  @override
  String get pickInstallDirButton => 'Choose Folder';
  @override
  String get pickInstallDirDialogTitle => 'Choose the install folder';

  @override
  String get sourceLabel => 'Where the program comes from';
  @override
  String get sourceGithub => 'From GitHub';
  @override
  String get sourceFile => 'From my own file';

  @override
  String get githubUrlLabel => 'GitHub repository address';
  @override
  String get githubUrlHint => 'For example github.com/owner/repo';
  @override
  String get githubUrlInvalid => 'That is not a GitHub repository address';
  @override
  String get fetchAssetsButton => 'Show The Files';
  @override
  String get fetchingAssets => 'Fetching the file list…';
  @override
  String get assetLabel => 'Which file to download';
  @override
  String get assetHint =>
      'A release usually holds several files. Pick the one that fits your '
      'computer.';
  @override
  String get noAssetsFound => 'This release has no files to download';
  @override
  String assetsFromRelease(String tagName) => 'Files in release $tagName:';

  @override
  String get pickInstallerButton => 'Choose File';
  @override
  String get pickInstallerDialogTitle => 'Choose the installer file';
  @override
  String get installerKindLabel => 'Installer type';
  @override
  String installerKindSniffed(String kind) => 'Detected from the file: $kind';
  @override
  String get portableFileLabel => 'The file is the program itself';
  @override
  String get portableFileHint =>
      'Tick this when the file is not an installer but the program itself. '
      'On install you will be asked where to copy it, instead of running it.';
  @override
  String get pickCopyTargetDialogTitle => 'Where to copy the file';
  @override
  String copiedFileSnack(String path) => 'The file was copied to $path';
  @override
  String get exeNameLabel => 'Executable file name';
  @override
  String get exeNameHint =>
      'Can be left empty — the name is learned by itself after the first '
      'install';

  @override
  String get githubAssetKept =>
      'The file picked here earlier will be kept. To change it — show the '
      'files and pick another.';
  @override
  String installerKept(String fileName) =>
      'The stored file, $fileName, will be kept. To change it — pick another '
      'file.';

  @override
  String get saveButton => 'Add';
  @override
  String get saveEditButton => 'Save';
  @override
  String get nameRequired => 'A program name is required';
  @override
  String get sourceRequired =>
      'Choose a file, or a repository and a file in it';
  @override
  String addedSnack(String name) => '$name was added';
  @override
  String updatedSnack(String name) => '$name was updated';

  @override
  String get kindInno => 'Inno Setup';
  @override
  String get kindNsis => 'NSIS';
  @override
  String get kindMsi => 'MSI';
  @override
  String get kindZip => 'Archive';
  @override
  String get kindPortableFile => 'The file itself, no installation';
  @override
  String get kindInteractive =>
      'Unrecognised installer — a normal install window will open';

  @override
  String installedVersion(String version) => 'Installed: version $version';
  @override
  String get installedUnknownVersion =>
      'Installed, but the version cannot be read';
  @override
  String get notInstalled => 'Not installed';
  @override
  String get noDetectRules => 'Cannot detect — no executable file name was set';
  @override
  String storedInstaller(String version) => 'On the drive: version $version';
  @override
  String get noStoredInstaller => 'No installer downloaded yet';

  @override
  String get downloadButton => 'Download To Drive';
  @override
  String get downloadingLabel => 'Downloading…';
  @override
  String get checkOnlineButton => 'Check Online';
  @override
  String onlineVersionAvailable(String version) =>
      'Version $version is available online';
  @override
  String get onlineUpToDate => 'What is on the drive is the latest version';
  @override
  String get onlineUnavailable => 'No internet connection right now';
  @override
  String get replaceInstallerButton => 'Replace The File';
  @override
  String get pickLocationButton => 'Choose Location Manually';
  @override
  String locationAdoptedSnack(String dir) => 'The program was found in $dir';
  @override
  String get locationNotFoundSnack =>
      'No installation was found there. Check that you picked the right '
      'folder.';

  @override
  String installedSnack(String name) => '$name was installed';
  @override
  String get learningLabel => 'Identifying the installation...';
  @override
  String learnedDetectionSnack(String exeName) =>
      'From now on it will be recognised automatically, by $exeName';
  @override
  String archiveInDownloadsSnack(String path) =>
      'The file was copied to your Downloads folder: $path';
  @override
  String downloadedSnack(String version) =>
      'Version $version was downloaded to the drive';

  @override
  String get editTooltip => 'Edit';
  @override
  String get removeTooltip => 'Remove from list';
  @override
  String get removeDialogTitle => 'Remove From List';
  @override
  String removeDialogContent(String name) =>
      '$name will be removed from the list, and its stored file will be '
      'deleted from the drive.\n\n'
      'The program itself will not be uninstalled from this computer.';
  @override
  String get removeDialogConfirm => 'Remove';
  @override
  String removedSnack(String name) => '$name was removed';
}
