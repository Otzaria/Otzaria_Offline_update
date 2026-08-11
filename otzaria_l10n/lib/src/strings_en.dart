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
  SetupErrorStrings get setupError => const _SetupError();
  @override
  UnitStrings get units => const _Units();
  @override
  LibraryDomainStrings get libraryDomain => const _LibraryDomain();
  @override
  AppDomainStrings get appDomain => const _AppDomain();
  @override
  PluginsDomainStrings get pluginsDomain => const _PluginsDomain();
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
  String get installing => 'Installing…';
  @override
  String get unknownValue => 'Unknown';
  @override
  String get lastDownloaded => 'Last Downloaded';
  @override
  String get emptyValue => '—';
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
  String get navSettings => 'Settings';
  @override
  String logPathFallback(String path) => 'Activity log: $path';
}

class _Home extends HomeStrings {
  const _Home();

  @override
  String get title => 'Home';
  @override
  String get description =>
      'Update the Program and the Library from the folder next to this '
      'program — no internet required.';

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
      '$targetVersion. The current database will be replaced only after the new'
    'version has been verified';
  @override
  String get libraryUpdateConfirm => 'Update Now';
  @override
  String libraryUpdatedSnack(String version) =>
      'The database was updated to version $version';

  @override
  String get onlineCardTitle => 'Check for updates';
  @override
  String get onlineCardSubtitle =>
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
  String get checkForUpdatesButton => 'Check for updates';
  @override
  String get downloadNowButton => 'Download now';
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
  String get description =>
      'Otzaria is installed from the folder next to this program, with no '
      'internet needed. Make sure Otzaria is closed before you install.';

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
  String get pickInstallDirDialogTitle => 'Choose the Otzaria installation folder';
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
  String get whatsNewEmpty =>
      'This version has no release notes, or no version has been downloaded '
      'yet.';

  @override
  String get sourceCardTitle => 'Folder the program is installed from';
  @override
  String get sourceCardSubtitle =>
      'Fixed, next to the executable — see "Library Update" for the full '
      'explanation.';
  @override
  String get sourceDirTitle => 'Program updates Folder';

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
  String get description =>
      'The update is applied from this program\'s folder. Nothing touches '
      'your database until you approve it, and updates are blocked while '
      'Otzaria is open.';

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
  String get sourceCardTitle => 'Folder the update comes from';
  @override
  String get sourceCardSubtitle =>
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
}

class _Settings extends SettingsScreenStrings {
  const _Settings();

  @override
  String get title => 'Settings';
  @override
  String get description =>
      'Downloads always start with a click. Installing from the local folder '
      'is the only thing that can be automated, and it takes a one-time '
      'confirmation.';

  @override
  String get automationCardTitle => 'Automation';
  @override
  String get automationCardSubtitle =>
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
      'A light check against GitHub on startup — no download. Failure (no '
      'internet) is ignored silently; the manual button on the home screen '
      'always works';
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
  String get downloadCardSubtitle =>
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
  String get appearanceCardTitle => 'Language and Appearance';
  @override
  String get appearanceCardSubtitle =>
      'How the program looks and which Language it is in. Applies right away, and '
      'is kept for next time.';
  @override
  String get languageTitle => 'System Language';
  @override
  String get languageSubtitle => 'Changes every screen and message right away';
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
  String get textSizeTitle => 'Text size';
  @override
  String get textSizeSmall => 'Small';
  @override
  String get textSizeNormal => 'Normal';
  @override
  String get textSizeLarge => 'Large';

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
      'install files from otzaria.org into the transfer folder. It needs '
      'internet once; after that the store works on a computer with no '
      'connection at all.';
  @override
  String get syncDialogConfirm => 'Sync';
  @override
  String get syncFailedSnack => 'The sync failed';
  @override
  String syncDoneSnack(int count) =>
      'Sync complete — $count plugins in the store';
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
  String get screenshotPrevious => 'Previous';
  @override
  String get screenshotNext => 'Next';
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
  String get copyPathButton => 'Copy the path';
  @override
  String get pathCopiedSnack => 'The path was copied';
  @override
  String cannotWriteToDataDir(String osMessage) =>
      'Cannot write to the folder next to this program: $osMessage';
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
  String get noInstallableReleaseForPlatform =>
      'No Otzaria version that can be installed on this platform was found.';
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
