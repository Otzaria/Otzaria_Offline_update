import 'app_language.dart';
import 'app_strings.dart';
import 'plural.dart';

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
  GuidanceStrings get guide => const _Guide();
  @override
  TaskStrings get task => const _Task();
  @override
  PageStrings get pages => const _Pages();
  @override
  AppScreenStrings get appScreen => const _AppScreen();
  @override
  LibraryScreenStrings get libraryScreen => const _LibraryScreen();
  @override
  SettingsScreenStrings get settings => const _Settings();
  @override
  SaferModeStrings get saferMode => const _SaferMode();
  @override
  PluginsStrings get plugins => const _Plugins();
  @override
  FaqStrings get faq => const _Faq();
  @override
  CustomAppsStrings get customApps => const _CustomApps();
  @override
  ErrorReportsStrings get errorReports => const _ErrorReports();
  @override
  AppReportsStrings get appReports => const _AppReports();
  @override
  SetupErrorStrings get setupError => const _SetupError();
  @override
  ReadOnlyDriveStrings get readOnlyDrive => const _ReadOnlyDrive();
  @override
  ElevationStrings get elevation => const _Elevation();
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
  @override
  ErrorReportsDomainStrings get errorReportsDomain =>
      const _ErrorReportsDomain();
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
  String get retry => 'Try again';
  @override
  String get errorDetailsButton => 'Details';
  @override
  String get errorDetailsTitle => 'Error details';
  @override
  String get install => 'Install';
  @override
  String get update => 'Update';
  @override
  String get launch => 'Open';
  @override
  String get notCheckedYet => 'Not checked yet';
  @override
  String get checking => 'Checking…';
  @override
  String get upToDate => 'Up To Date';
  @override
  String get updateAvailable => 'Update available';
  @override
  String get installedIsNewer => 'A Newer Version Is Installed';
  @override
  String get installing => 'Installing…';
  @override
  String get unknownValue => 'Unknown';
  @override
  String get lastDownloaded => 'Last downloaded';
  @override
  String get emptyValue => '—';
  @override
  String get copyPathButton => 'Copy the path';
  @override
  String get pathCopiedSnack => 'The path was copied';
  @override
  String get closeOtzariaButton => 'Close Otzaria';
  @override
  String get closeOtzariaFailedSnack =>
      'Otzaria did not close — it may be waiting to save. Please close it '
      'manually.';
}

class _Shell extends ShellStrings {
  const _Shell();

  @override
  String get appTitle => 'Otzaria Updates';
  @override
  String get otzariaLogoLabel => 'Otzaria';
  @override
  String logPathFallback(String path) => 'Activity log: $path';
  @override
  String folderPathFallback(String path) =>
      'Could not open the folder. It is here: $path';
  @override
  String get closeWhileBusyTitle => 'Close in the middle of this?';
  @override
  String get closeWhileDownloadingPrompt =>
      'A download is running. Closing now cancels it: whatever has finished '
      'downloading stays on the drive, and the part in progress is deleted '
      'before the program closes.';
  @override
  String get closeWhileDownloadingConfirm => 'Cancel and close';
  @override
  String get closeWhileInstallingPrompt =>
      'An install is running. Closing in the middle may leave it unfinished, '
      'and it will need to run again.';
  @override
  String get closeWhileInstallingConfirm => 'Close anyway';
  @override
  String get closeWhileBusyKeepGoing => 'Keep going';
  @override
  String get helpTooltip => 'Help and FAQ';
  @override
  String get settingsTooltip => 'Settings';
  @override
  String get windowMinimize => 'Minimize';
  @override
  String get windowMaximize => 'Maximize';
  @override
  String get windowRestore => 'Restore';
  @override
  String get windowClose => 'Close';
  @override
  String get backTooltip => 'Back (Esc)';
  @override
  String get breadcrumbHome => 'Home';
}

class _Home extends HomeStrings {
  const _Home();

  @override
  String get otzariaOpenSnack =>
      'Otzaria is open — please close it and try again.';

  @override
  String get doNotRemoveDriveWarning =>
      'Do not disconnect the drive until the update finishes.';

  @override
  String get cancelDownloadButton => 'Cancel download';
  @override
  String get cancelDownloadDialogTitle => 'Cancel the download?';
  @override
  String get cancelDownloadPrompt =>
      'Whatever has finished downloading stays on the drive. The part in '
      'progress is deleted, and whatever the drive held before stays where it is.';
  @override
  String get cancelDownloadKeepGoing => 'Keep downloading';
  @override
  String get downloadingApp => 'Downloading the Otzaria Program…';
  @override
  String get downloadingLibrary => 'Downloading the Otzaria library…';
  @override
  String get downloadingPlugins => 'Downloading the Plugins…';
  @override
  String get downloadStarting => 'Starting the download…';

  @override
  String get libraryApplyActive => 'Otzaria library update in progress';
}

class _Task extends TaskStrings {
  const _Task();

  @override
  String get semanticTitle => 'Download smart search too?';
  @override
  String get semanticBody =>
      'Smart search finds sources by meaning, even when the words differ from what you searched for.';
  @override
  String get semanticNoTitle => 'No, regular search only (recommended)';
  @override
  String get semanticNoBody => 'You can add smart search in the next download.';
  @override
  String get semanticNoSize => 'Nothing extra';
  @override
  String get semanticYesTitle => 'Yes, smart search too';
  @override
  String get semanticYesBody =>
      'The files take a few gigabytes, and the download will take longer. Using smart search in Otzaria requires consent to training-data collection; downloading does not change that consent.';
  @override
  String get semanticRemember => "Don't show again";
  @override
  String get semanticRememberBody =>
      'Your choice is saved in Settings, under "Smart search". You can change it there.';
  @override
  String get back => 'Back';
  @override
  String get startDownload => 'Start download';
  @override
  String get preparingTitle => 'Getting ready to download';
  @override
  String get preparingBody => 'Checking the Otzaria website for what is new.';
  @override
  String get downloadingTitle => 'Downloading the updates to the drive';
  @override
  String get downloadingBody => 'You can keep using the computer meanwhile.';
  @override
  String downloadingStep(String name, int index, int count) =>
      'Downloading $name · $index of $count';
  @override
  String get componentApp => 'Otzaria app';
  @override
  String get componentLibrary => 'The Otzaria library';
  @override
  String get componentPlugins => 'Plugins';
  @override
  String get stepApp => 'the Otzaria app';
  @override
  String get stepLibrary => 'the Otzaria library';
  @override
  String get stepPlugins => 'the plugins';
  @override
  String minutesLeft(int minutes) => plural(
        minutes,
        one: 'One minute left',
        many: '$minutes minutes left',
      );
  @override
  String get lessThanMinuteLeft => 'Less than a minute left';
  @override
  String get speedPending => 'Measuring speed…';
  @override
  String get speedStalled => 'Waiting for data…';
  @override
  String bytesLine(String name, String done, String total) =>
      '$name: $done of $total downloaded';
  @override
  String stageDone(String? size) => size == null ? 'Done' : 'Done · $size';
  @override
  String get stageWaiting => 'Waiting';
  @override
  String approxSize(String size) => 'about $size';
  @override
  String downloadTotal(String size) => 'About $size in total';
  @override
  String get sizeChecking => 'checking how much will download…';
  @override
  String get cancelling => 'Cancelling…';
  @override
  String get cancelledTitle => 'The download was cancelled';
  @override
  String get cancelledBody =>
      'The drive is as it was before you started, and you can keep using it as usual.';
  @override
  String cancelledKeptBody(String names) =>
      'What finished downloading stays on the drive: $names. You can continue '
      'the download from the same point.';
  @override
  String get cancelledRevertFailedBody =>
      'Not everything that was downloaded could be removed from the drive. Downloading again will continue from it.';
  @override
  String get downloadAgain => 'Download again';
  @override
  String get backHome => 'Back to home';
  @override
  String get retryNothingSnack =>
      'There is nothing left to install from the drive — home shows the current state.';
  @override
  String get doneTitle => 'The drive is ready';
  @override
  String get doneBody =>
      'All the updates were downloaded and saved on the drive.';
  @override
  String get doneNothingBody =>
      'The Otzaria website has nothing new, so nothing was downloaded. The drive is already up to date.';
  @override
  String doneSkipped(String names) =>
      '$names were not downloaded — nothing new on the website.';
  @override
  String doneAppValue(String version) => 'Otzaria $version';
  @override
  String doneLibraryValue(int version) => 'Version $version';
  @override
  String donePluginsValue(int count) => plural(
        count,
        one: 'One plugin on the drive',
        many: '$count plugins on the drive',
      );
  @override
  String get donePluginsUpdated => 'The plugin store was updated';
  @override
  String get whatNow => 'What now?';
  @override
  String get whatNowEject => 'Safely eject the drive';
  @override
  String get whatNowEjectHint => '(the drive icon next to the clock → Eject)';
  @override
  String get whatNowConnect =>
      'Connect it to the computer where you study with Otzaria.';
  @override
  String whatNowOpen(String toolName) =>
      'Open $toolName from the drive there, and click "Update this computer".';
  @override
  String get updateHereToo => 'Update this computer too';
  @override
  String get installHereToo => 'Install Otzaria here too';
  @override
  String get finish => 'Done';
  @override
  String get networkTitle => 'No internet connection';
  @override
  String get filterTitle => 'The connection to the Otzaria website was blocked';
  @override
  String filterBody(String name) =>
      'An internet filter may be blocking the download of $name. What was already downloaded is saved on the drive. If it happens again, ask your filtering provider to allow the Otzaria website, then click "Try again".';
  @override
  String networkBody(String name) =>
      'The connection dropped while downloading $name. What was already downloaded is saved on the drive. Check the connection and click "Try again".';
  @override
  String get shabbatTitle =>
      'The Otzaria website is closed on Shabbat and holidays';
  @override
  String get shabbatBody =>
      'You can download after Shabbat. What was already downloaded is saved on the drive.';
  @override
  String get spaceTitle => 'Not enough space on the drive';
  @override
  String spaceBody(String needed, String free) =>
      '$needed are needed and $free are free. Free up space on the drive and click "Try again" — what was already downloaded is saved.';
  @override
  String get snapshotTitle => 'The download did not start';
  @override
  String get snapshotBody =>
      'The drive state could not be saved before downloading, and without it the download cannot be cancelled safely. Nothing was downloaded. Check that the drive is connected and click "Try again".';
  @override
  String otherTitle(String name) => 'The download of $name did not finish';
  @override
  String get otherBody =>
      'What was already downloaded is saved on the drive, and "Try again" continues from it. If it happens again, the technical details will help whoever assists you.';
  @override
  String get techDetails => 'Technical details';
  @override
  String get hideTechDetails => 'Hide technical details';
  @override
  String get copyDetails => 'Copy';
  @override
  String get detailsCopied => 'Details copied';
  @override
  String get otherUserTitle =>
      'This tool runs as an administrator of another account';
  @override
  String otherUserBody({required bool firstInstall, String? account}) {
    final who = account == null
        ? 'This tool was started as an administrator under another account'
        : 'This tool was started as the administrator account $account';
    return firstInstall
        ? '$who, so Otzaria would be installed for that administrator and not for you.'
        : '$who, so the update would go to that administrator and not to the Otzaria in your account.';
  }

  @override
  String get otherUserHint =>
      'It is best to close this tool and open it again without "Run as administrator".';
  @override
  String get continueAnyway => 'Continue anyway';
  @override
  String get closeTitle => 'Otzaria needs to be closed';
  @override
  String get closeBody =>
      'The update replaces files that Otzaria is using right now.';
  @override
  String closeHint({required bool plugins}) => plugins
      ? 'Nothing is lost: open books, bookmarks and notes will wait for you exactly where you left them. At the end of the update Otzaria will open again so you can approve the plugins.'
      : 'Nothing is lost: open books, bookmarks and notes will wait for you exactly where you left them.';
  @override
  String get closeAfterWizardBody =>
      'The setup wizard opened Otzaria. Close Otzaria to install the Otzaria library.';
  @override
  String get closeOtzariaAndContinue => 'Close Otzaria and continue';
  @override
  String stepOf(int index, int count) => 'Step $index of $count';
  @override
  String get installingApp => 'Installing Otzaria';
  @override
  String get updatingApp => 'Updating the Otzaria app';
  @override
  String get installingLibrary => 'Installing the Otzaria library';
  @override
  String get updatingLibrary => 'Updating the Otzaria library';
  @override
  String get sendingPlugins => 'Sending the plugins to Otzaria';
  @override
  String get appWizardFirstBody =>
      'The Otzaria setup wizard opened in a separate window. Follow it to the end, and this tool will continue by itself.';
  @override
  String get appWizardBody =>
      'The Otzaria setup wizard opened in a separate window. At its end Otzaria opens by itself, and this tool continues by itself.';
  @override
  String libraryBody(int? lowMinutes, int? highMinutes) => lowMinutes == null ||
          highMinutes == null
      ? 'This may take a while, depending on the update and the computer.'
      : 'Expected to take ${_minutesRange(lowMinutes, highMinutes)}, depending on the computer.';
  @override
  String get pluginsBody =>
      'This tool sends the plugins to Otzaria one by one. You approve the installation in the Otzaria window.';
  @override
  String get keepDrive => 'Do not disconnect the drive until the end';
  @override
  String appVersion(String version) => 'Version $version';
  @override
  String appInstalled(String version) => 'Installed · version $version';
  @override
  String get appWizardOpen => 'The setup wizard is open — continue in it';
  @override
  String get appStoppedWaiting =>
      'Stopped waiting · check on the home page whether the installation finished';
  @override
  String get appSkipped => 'No installation was needed';
  @override
  String get stopWaiting => 'Stop waiting';
  @override
  String get libraryFull => 'The full Otzaria library';
  @override
  String libraryVersion(int version) => 'Version $version';
  @override
  String libraryDone(String detail) => 'Done · $detail';
  @override
  String get libraryWaitingClose => 'Waiting for Otzaria to close';
  @override
  String get librarySkipped =>
      'Not installed now — you can install it later from the home page';
  @override
  String pluginsWaiting(int count) => plural(
        count,
        one: 'One plugin · will be sent to Otzaria',
        many: '$count plugins · will be sent to Otzaria',
      );
  @override
  String get pluginsCurrent => 'Approve each plugin in the Otzaria window';
  @override
  String get pluginsSent => 'Sent to Otzaria — approve each plugin there';
  @override
  String pluginsSentNames(String names) => 'Sent: $names';
  @override
  String pluginsNotSent(String names) =>
      'Not sent: $names — you can retry from the plugins page';
  @override
  String pluginsStillSending(String names) => 'Still being sent: $names';
  @override
  String get pluginsAfterInstall =>
      'Not sent — send them from the plugins page after the installation finishes';
  @override
  String get pluginRowSent => 'Sent to Otzaria';
  @override
  String get pluginRowWaiting => 'Waiting to be sent';
  @override
  String get pluginRowFailed =>
      'Not sent — you can retry from the plugins page';
  @override
  String get finishWithoutWaiting => 'Finish without waiting';
  @override
  String get installedTitle => 'Otzaria is installed';
  @override
  String get updatedTitle => 'Otzaria is up to date';
  @override
  String doneHereBody({
    required bool firstInstall,
    required bool app,
    required bool library,
    required bool plugins,
    bool libraryNote = false,
  }) {
    if (firstInstall) {
      if (library && libraryNote) {
        return 'Otzaria and its library were installed on this computer, but one thing is left to do — see the library row. You can disconnect the drive.';
      }
      return library
          ? 'Otzaria and its library are installed on this computer and ready for study. You can disconnect the drive.'
          : 'Otzaria is installed on this computer. You can disconnect the drive.';
    }
    final done = app && library
        ? 'The app and the Otzaria library were updated.'
        : app
            ? 'The Otzaria app was updated.'
            : library
                ? 'The Otzaria library was updated.'
                : null;
    return [
      if (done != null) done,
      if (library && libraryNote)
        'One thing is left to do — see the Otzaria library row.',
      if (plugins) 'The plugins are waiting for your approval in Otzaria.',
      'You can disconnect the drive.',
    ].join(' ');
  }

  @override
  String get stoppedWaitingTitle => 'Stopped waiting for the setup wizard';
  @override
  String stoppedWaitingBody(
          {required bool firstInstall, required bool libraryDone}) =>
      firstInstall
          ? 'If the wizard is still open, finish it. Then check on the home page that Otzaria was installed; you can install the Otzaria library from there too.'
          : libraryDone
              ? 'The Otzaria library was updated. Finish the installation in the wizard window, and check on the home page that Otzaria was updated. Do not disconnect the drive until the wizard finishes.'
              : 'Finish the installation in the wizard window, and check on the home page that Otzaria was updated. Do not disconnect the drive until the wizard finishes.';
  @override
  String get wizardStillOpenTitle => 'The setup wizard is still open';
  @override
  String get wizardStillOpenBody =>
      'Finish the installation in the wizard window, then check again on the home page. Do not disconnect the drive until the wizard finishes.';
  @override
  String get reindexTitle => 'Rebuilding search is recommended';
  @override
  String get reindexBody =>
      'That way the new books show up in search. Otzaria will open and rebuild it.';
  @override
  String get reindexButton => 'Rebuild';
  @override
  String get toOtzaria => 'Go to Otzaria';
  @override
  String get wizardClosedTitle => 'The Otzaria installation did not finish';
  @override
  String wizardClosedBody(
          {required bool firstInstall, required bool libraryDone}) =>
      firstInstall
          ? 'The setup wizard was closed before the end, and Otzaria was not installed. You can try again any time.'
          : libraryDone
              ? 'The setup wizard was closed before the end. Otzaria stayed on the previous version and works as usual. The Otzaria library that was already updated stays updated.'
              : 'The setup wizard was closed before the end. Otzaria stayed on the previous version and works as usual.';
  @override
  String get stoppedTitle => 'The update stopped';
  @override
  String get stoppedBody =>
      'Otzaria stayed open, so the rest of the update was not installed. What was already installed stays.';
  @override
  String get libraryFailedTitle => 'The Otzaria library update failed';
  @override
  String get libraryInstallFailedTitle =>
      'Installing the Otzaria library failed';
  @override
  String get appFailedTitle => 'Installing Otzaria failed';
  @override
  String get libraryFailedKeep =>
      'Otzaria keeps working with the previous library.';
  @override
  String get appFailedKeep => 'Otzaria stayed on the previous version.';
  @override
  String get pluginsFailedTitle => 'Sending the plugins failed';
  @override
  String pluginsFailedKeep(
          {required bool firstInstall, required bool appDone}) =>
      !appDone
          ? 'The plugins were not sent to Otzaria.'
          : firstInstall
              ? 'Otzaria was installed, but the plugins were not sent to it.'
              : 'Otzaria was updated, but the plugins were not sent to it.';
  @override
  String get permissionFailedTitle => 'The update failed';
  @override
  String get permissionInstallFailedTitle => 'The installation failed';
  @override
  String get permissionAppBody =>
      'This tool is not allowed to update Otzaria, because it is installed for all users of the computer.';
  @override
  String get permissionAppInstallBody =>
      'This tool is not allowed to install Otzaria on this computer.';
  @override
  String get permissionLibraryBody =>
      'This tool is not allowed to change the folder that holds the Otzaria library.';
  @override
  String get elevateTitle => 'Restart as administrator';
  @override
  String get elevateBody =>
      'This tool will reopen with administrator rights, and then you can try again.';
  @override
  String get elevateButton => 'Restart as administrator';
  @override
  String get toLibraryPage => 'To the Otzaria library page';
  @override
  String get toPluginsPage => 'To the plugins page';
  @override
  String get showProgress => 'Show progress';
}

class _Pages extends PageStrings {
  const _Pages();

  @override
  String get advancedTitle => 'Advanced';
  @override
  String get onThisComputer => 'On this computer';
  @override
  String get onTheDrive => 'On the drive';
  @override
  String get nothingYet => 'Nothing yet';
  @override
  String get onlineAvailable => 'Available to download';
  @override
  String get nothingNewOnline => 'Nothing new';
  @override
  String downloadedOn(String date) => 'downloaded $date';
  @override
  String get chipUpdateOnDrive => 'Update on the drive';
  @override
  String get chipUpToDate => 'Up to date';
  @override
  String get lockedChip => 'Locked by password';
  @override
  String get appChipNotInstalled => 'Not installed on this computer';
  @override
  String appWhatsNew(String version) => "What's new in Otzaria $version";
  @override
  String get appInstalledNotesCaption =>
      'The version installed on this computer';
  @override
  String get appAdvancedPageTitle => 'Otzaria — advanced';
  @override
  String appAwaitsNewer({required bool stable}) => stable
      ? 'A beta version newer than the stable one on the drive is installed here. You will move to the stable version when a stable version newer than the installed one comes out.'
      : 'A stable version newer than the beta on the drive is installed here. You will move to the beta version when a beta newer than the installed one comes out.';
  @override
  String get pageBusyNote =>
      'Another task is running now, so the actions here wait for it to finish.';
  @override
  String appAdvancedSummary({required bool channel}) => channel
      ? 'Beta version, reinstall, install location and the drive folder'
      : 'Reinstall, install location and the drive folder';
  @override
  String get appChannelTitle => 'Which version to install';
  @override
  String get appChannelBody =>
      'A beta version gets new features first, but it may have problems.';
  @override
  String get appReinstallTitle => 'Reinstall the same version';
  @override
  String appReinstallBody(String version) =>
      'Installs Otzaria $version again. Helps when something in the app does not work as it should.';
  @override
  String get appReinstallUnavailable =>
      'The drive does not have the version installed here.';
  @override
  String get appLocationTitle => 'Install location';
  @override
  String get appSourceTitle => 'The drive folder it installs from';
  @override
  String get libSemanticSection => 'Smart search';
  @override
  String libAdvancedSummary({required bool reindex}) => reindex
      ? 'Otzaria library location, rebuilding search, the full library and '
          'the drive folder'
      : 'Otzaria library location, the full library and the drive folder';
  @override
  String get libMissingFilesTitle =>
      'Some Otzaria library files did not reach the drive';
  @override
  String libChipCompanions(String names) => 'On the drive: $names';
  @override
  String libVersion(int version) => 'Version $version';
  @override
  String get libNotInstalled => 'Not installed';
  @override
  String get libInstallButton => 'Install the Otzaria library';
  @override
  String get libInstallWithAppButton => 'Install Otzaria and its library';
  @override
  String get libInstallWithAppNote =>
      'Otzaria is not installed on this computer yet. The program installs first, then the Otzaria library.';
  @override
  String get libInstallNeedsApp =>
      'Otzaria is not installed on this computer, and the program is not on the drive. To install the Otzaria library, first download the program on a computer with internet.';
  @override
  String get libUpdateNeedsApp =>
      'Otzaria is not installed on this computer. Install it first from the home page, and then the Otzaria library can be installed here.';
  @override
  String get libUpdateButton => 'Update the Otzaria library';
  @override
  String get libNotFoundTitle =>
      'We could not find the Otzaria library on this computer';
  @override
  String get libNotFoundBody =>
      'Otzaria is installed, but the Otzaria library is not in the usual place. If you moved it, choose where it is now.';
  @override
  String get libPickFolderButton => 'Choose the Otzaria library location';
  @override
  String get libSemanticTitle => 'Search by meaning';
  @override
  String get libSemanticBody =>
      'Smart search finds sources even when the words differ from what you '
      'searched for. To turn it on, you need to agree that Otzaria keeps your '
      'search words and which results helped you. This tool passes them to '
      'the developers through the drive, together with the reports.';
  @override
  String get libSemanticGrant => 'I agree, turn it on';
  @override
  String get libSemanticClosedNote =>
      'Otzaria needs to be closed to turn this on.';
  @override
  String get libSemanticActive => 'On';
  @override
  String get libSemanticActiveBody =>
      'Consent is on. You can withdraw it in the Otzaria settings.';
  @override
  String get libLocationTitle => 'Otzaria library location on this computer';
  @override
  String get libLocationNone => 'No location chosen yet';
  @override
  String get libFullTitle => 'The full Otzaria library instead of an update';
  @override
  String libFullBody(String size) =>
      'The regular update failed. You can install the full Otzaria library from the drive instead ($size). It takes longer, and needs no internet.';
  @override
  String get libFullBodyNoSize =>
      'The regular update failed. You can install the full Otzaria library from the drive instead. It takes longer, and needs no internet.';
  @override
  String libFullMeta({String? size, int? lowMinutes, int? highMinutes}) => [
        size == null
            ? 'The full Otzaria library on the drive'
            : 'The full Otzaria library on the drive: $size',
        if (lowMinutes != null && highMinutes != null)
          _minutesRange(lowMinutes, highMinutes),
      ].join(' · ');
  @override
  String get libFullUnavailable =>
      'Possible only after a regular update failed, when the drive has a full library.';
  @override
  String get libPersonalReadOnly =>
      'The drive is write-protected, so this computer cannot be registered on it.';
  @override
  String get libSourceTitle => 'The drive folder it updates from';
  @override
  String get repDescription =>
      'When something does not work in Otzaria or its plugins, a short report is saved. This tool passes the reports to the developers — even from computers without internet.';
  @override
  String get repSendingTitle => 'Sending the reports';
  @override
  String repWaitingTitle(int count) => count == 1
      ? '1 report waiting to be sent'
      : '$count reports waiting to be sent';
  @override
  String repWaitingBody({required bool withSearch}) => withSearch
      ? 'They are saved on the drive, together with the smart search improvement data. This computer is online, so you can send them now.'
      : 'They are saved on the drive. This computer is online, so you can send them now.';
  @override
  String repStoredTitle(int count) => count == 1
      ? '1 report saved on the drive'
      : '$count reports saved on the drive';
  @override
  String get repStoredBody =>
      'They will be sent when you connect the drive to a computer with internet and open this tool there.';
  @override
  String get repUncheckedBody =>
      'It has not been checked yet whether this computer is online. If it is, you can send from here.';
  @override
  String get repOnlyOnline =>
      'Sending works only from a computer with internet';
  @override
  String get repCheckConnectionButton => 'Check connection';
  @override
  String repAlsoStored(int count) => count == 1
      ? '1 report is already saved on the drive.'
      : '$count are already saved on the drive.';
  @override
  String get repNothingTitle => 'No reports from Otzaria waiting';
  @override
  String get repSendButton => 'Send now';
  @override
  String repSendStoredButton(int count) => plural(count,
      one: 'Send the report on the drive',
      many: 'Send the $count reports on the drive');
  @override
  String get repWhatIsSent => 'What is sent?';
  @override
  String repOwnPending(int count) => 'Reports from this tool waiting ($count)';
  @override
  String get repOwnTitle => 'Reports about this tool';
  @override
  String get repOwnEmpty => 'There are no reports about this tool yet.';
  @override
  String get repCrumb => 'Reports';
  @override
  String get repProblemSection => 'Something not working in this tool?';
  @override
  String get repProblemTitle => 'Report a problem with this tool';
  @override
  String get repProblemBody =>
      'Tell us what happened. You can attach screenshots.';
  @override
  String get selfCrumb => 'This tool';
  @override
  String get selfTitle => 'Updating this tool';
  @override
  String get selfDescription =>
      'Otzaria Updates updates itself too. It takes less than a minute, and the tool reopens by itself.';
  @override
  String selfChipOnline(String version) => 'Version $version is on the website';
  @override
  String selfChipOnDrive(String version) => 'Version $version is on the drive';
  @override
  String get selfChipUpToDate => 'Up to date';
  @override
  String get selfCurrentVersion => 'The version open now';
  @override
  String get selfNewVersion => 'New version';
  @override
  String get selfDownloadButton => 'Download and restart';
  @override
  String selfDownloading(int percent) =>
      'Downloading the new version · $percent%';
  @override
  String get selfInstalling => 'Installing and restarting…';
  @override
  String get selfErrorTitle => 'Updating the tool did not succeed';
  @override
  String get selfDownloadFailed => 'The new version was not fully downloaded.';
  @override
  String get selfCheckFailed =>
      'We could not read the new version on the drive.';
  @override
  String get selfInstallFailed => 'Installing the new version did not succeed.';
  @override
  String get selfErrorKeepsWorking =>
      'The current version keeps working as usual.';
  @override
  String get selfManualTitle => 'The tool needs to be replaced by hand';
  @override
  String get selfOpenFolder => 'Open the folder';
  @override
  String get selfAdminTitle => 'Administrator rights are needed';
  @override
  String get selfAdminBody =>
      'The tool is in a folder only an administrator can change. Restart it as administrator, and click "Install and restart" again.';
  @override
  String get selfReadOnly =>
      'The drive is write-protected, so the new version cannot be downloaded to it.';
  @override
  String selfWhatsNew(String version) => "What's new in $version";
}

class _Guide extends GuidanceStrings {
  const _Guide();

  @override
  String get eyebrowOnline => 'This computer: online';
  @override
  String get eyebrowOffline => 'This computer: not connected';
  @override
  String get eyebrowThisComputer => 'This computer';
  @override
  String eyebrowOtzaria(String version) => 'Otzaria $version';
  @override
  String get eyebrowNotInstalled => 'Otzaria is not installed yet';

  @override
  String get checkingTitle => 'Checking the drive and this computer';
  @override
  String get checkingBody =>
      'This takes a moment. Then you will see here what to do next.';
  @override
  String get installHereTitle => 'Otzaria is ready to install on this computer';
  @override
  String get installHereBody =>
      'The program and the Otzaria library are already on the drive. Plugins are '
      'installed later, from the plugins page.';
  @override
  String get installHereButton => 'Install Otzaria on this computer';
  @override
  String get updateHereTitle => 'The drive has updates for this computer';
  @override
  String get updateHereBody =>
      'Your books, bookmarks and notes stay exactly as they are.';
  @override
  String get updateHereButton => 'Update this computer';
  @override
  String get whatsNewButton => 'What is new?';
  @override
  String get downloadTitle => 'There are new updates on the Otzaria site';
  @override
  String get downloadBody =>
      'Download them to this drive, and update any computer from it — even '
      'one without internet.';
  @override
  String get downloadButton => 'Download everything to the drive';
  @override
  String updateHereTooNote(String? version) => version == null
      ? 'The drive already holds an update not installed on this computer. '
          'You can install it now, or after the download.'
      : 'The drive already holds an update not installed on this computer '
          '(Otzaria $version). You can install it now, or after the download.';
  @override
  String syncOffNote({
    required bool app,
    required bool library,
    required bool plugins,
  }) {
    final off = [
      if (app) 'the program',
      if (library) 'the Otzaria library',
      if (plugins) 'the plugins',
    ];
    if (off.isEmpty) return noSyncSelectionNote;
    final names = off.length == 1
        ? off.single
        : '${off.sublist(0, off.length - 1).join(', ')} and ${off.last}';
    final subject = '${names[0].toUpperCase()}${names.substring(1)}';
    return '$subject will not be downloaded — turned off in the settings.';
  }

  @override
  String get noSyncSelectionNote =>
      'Nothing is selected for download in the settings.';
  @override
  String syncOffOnlyNote({
    required bool app,
    required bool library,
    required bool plugins,
    bool libraryFilesOnly = false,
  }) {
    final off = [
      if (app) 'the program',
      if (library) 'the Otzaria library',
      if (plugins) 'the plugins',
    ];
    if (off.length > 1) {
      final names =
          '${off.sublist(0, off.length - 1).join(', ')} and ${off.last}';
      return 'There is something new online for $names, but their download '
          'is turned off in the settings.';
    }
    if (plugins) {
      return 'There are plugin updates online, but their download is turned '
          'off in the settings.';
    }
    if (off.isEmpty) return noSyncSelectionNote;
    if (library && libraryFilesOnly) {
      return 'There are new Otzaria library files online, but their download is '
          'turned off in the settings.';
    }
    return 'There is a new version of ${off.single} online, but its download '
        'is turned off in the settings.';
  }

  @override
  String get downloadBusySnack =>
      'Another task is running. You can download once it finishes.';
  @override
  String get changeInSettingsLink => 'Change';
  @override
  String get chooseInSettingsLink => 'Choose in settings';
  @override
  String get libraryRetryNote =>
      'The last library download did not finish. Downloading again continues '
      'from what already arrived.';
  @override
  String get semanticOfferNote => 'Smart search is available to download';
  @override
  String get semanticOfferLink => 'Download';
  @override
  String get recheckNothingTitle =>
      'Checked again — nothing new on the Otzaria site';
  @override
  String recheckNothingBody(String time, {required bool upToDate}) => [
        'There are no new updates on the Otzaria site (checked at $time), so '
            'nothing was downloaded.',
        if (upToDate) 'The drive and this computer are up to date.',
      ].join(' ');
  @override
  String recheckNothingNote(String time) =>
      'Checked again — nothing new on the Otzaria site · checked at $time';
  @override
  String get nothingNewTitle => 'Nothing new on the Otzaria site';
  @override
  String nothingNewBody(String time, {required bool upToDate}) => [
        'The check at $time found no new updates, so nothing was downloaded.',
        if (upToDate) 'The drive and this computer are up to date.',
      ].join(' ');
  @override
  String nothingNewNote(String time) =>
      'Nothing new on the Otzaria site · checked at $time';
  @override
  String failedDownloadsNote(String names) =>
      'Did not reach the drive: $names.';
  @override
  String get upToDateTitle => 'Everything is up to date on this computer';
  @override
  String upToDateBody(String? version) => version == null
      ? 'Otzaria, its library and the plugins are up to date.'
      : 'Otzaria $version, its library and the plugins are up to date.';
  @override
  String get driveInstalledTitle =>
      'Everything on the drive is already installed here';
  @override
  String driveInstalledBody(String? version) => version == null
      ? 'Otzaria, its library and the plugins are installed.'
      : 'Otzaria $version, its library and the plugins are installed.';
  @override
  String get othersPendingTitle => 'There are more updates';
  @override
  String get otherLauncherTitle => 'This tool';
  @override
  String otherLauncherOnline(String version) =>
      'Version $version on the Otzaria site';
  @override
  String otherLauncherOnDrive(String version) =>
      'Version $version on the drive';
  @override
  String get checkFailedTitle => 'Could not check online';
  @override
  String checkFailedBody({
    required bool appFailed,
    required bool libraryFailed,
    required bool pluginsFailed,
    required bool appChecked,
    required bool libraryChecked,
    required bool pluginsChecked,
  }) {
    List<String> names(bool app, bool library, bool plugins) => [
          if (app) 'the Otzaria program',
          if (library) 'the Otzaria library',
          if (plugins) 'the plugins',
        ];
    String join(List<String> all) => all.length < 2
        ? all.join()
        : '${all.sublist(0, all.length - 1).join(', ')} and ${all.last}';

    final failed = join(names(appFailed, libraryFailed, pluginsFailed));
    final lead = failed.isEmpty
        ? 'The check on the Otzaria site failed.'
        : 'The check of $failed on the Otzaria site failed.';
    final checkedNames = names(appChecked, libraryChecked, pluginsChecked);
    if (checkedNames.isEmpty) return lead;
    final checked = join(checkedNames);
    final plural = checkedNames.length > 1 || pluginsChecked;
    final verb = plural
        ? 'were checked and are up to date'
        : 'was checked and is up to date';
    return '$lead ${checked[0].toUpperCase()}${checked.substring(1)} $verb.';
  }

  @override
  String get launchButton => 'Open Otzaria';
  @override
  String get recheckButton => 'Check again';
  @override
  String get offlineNote =>
      'New updates are downloaded to the drive on the connected computer, '
      'and then the drive is plugged in here.';
  @override
  String get checkOnlineNowNote =>
      'The Otzaria site has not been checked yet. "Check again" checks now.';
  @override
  String get newerTitle => 'This computer is newer than the drive';
  @override
  String newerChannelTitle({required bool stable}) => stable
      ? 'This computer is newer than the stable version on the drive'
      : 'This computer is newer than the beta version on the drive';
  @override
  String newerBody(String installed, String onDrive) =>
      'This computer has Otzaria $installed, and the drive has $onDrive. '
      'There is nothing to install from the drive.';
  @override
  String get newerNote =>
      'Newer updates are downloaded to the drive on the connected computer, '
      'and then the drive is plugged in here.';
  @override
  String get attentionAppTitle =>
      'Something in the Otzaria program needs a look';
  @override
  String get attentionLibraryTitle =>
      'Something in the Otzaria library needs a look';
  @override
  String get attentionBody => 'Its page explains what happened and what to do.';
  @override
  String get attentionLibraryButton => 'To the Otzaria library page';
  @override
  String get taskDownloadingTitle => 'Downloading updates to the drive';
  @override
  String get taskDownloadingBody =>
      'You can keep working. Do not unplug the drive until the download ends.';
  @override
  String get taskInstallingAppTitle => 'Installing Otzaria';
  @override
  String get taskUpdatingLibraryTitle => 'Updating the Otzaria library';
  @override
  String get taskBusyTitle => 'A task is running';
  @override
  String get taskBusyBody =>
      'When it ends, you will see here what else this computer needs.';
  @override
  String get taskNamedBody =>
      'When this ends, you will see here what else this computer needs.';
  @override
  String get taskSyncingPluginsTitle =>
      'Downloading the plugin store to the drive';
  @override
  String get taskUpdatingPluginsTitle => 'Updating the plugins';
  @override
  String get taskExportingStoreTitle => 'Copying the plugin store';
  @override
  String get taskDownloadingCustomAppsTitle =>
      'Downloading additional programs to the drive';
  @override
  String get taskCustomAppsTitle => 'Working on an additional program';
  @override
  String get taskInstallingLauncherTitle =>
      'Installing the new version of this tool';
  @override
  String get taskRestartingElevatedTitle =>
      'Restarting this tool as administrator';

  @override
  String itemUpdateTo(String version) => 'Update to $version';
  @override
  String itemLibraryUpdateTo(int version) => 'Update to version $version';
  @override
  String get itemLibraryUpdate => 'Update';
  @override
  String get itemLibraryFull => 'The full Otzaria library';
  @override
  String itemPluginUpdates(int count) =>
      count == 1 ? '1 plugin update' : '$count plugin updates';
  @override
  String itemPlugins(int count) => count == 1 ? '1 plugin' : '$count plugins';
  @override
  String get itemPluginsCatalog => 'Plugin list';
  @override
  String get itemStoreApp => 'Plugin store update';
  @override
  String itemPluginsWithStore(int count) =>
      '${itemPlugins(count)} · store update';
  @override
  String itemUpTo(String size) => 'Up to $size';
  @override
  String downloadTotal(
    String size, {
    required bool plusApp,
    required bool plusLibrary,
    required bool plusPlugins,
  }) {
    final plus = [
      if (plusApp) 'the program',
      if (plusLibrary) 'the Otzaria library',
      if (plusPlugins) 'the plugins',
    ];
    if (plus.isEmpty) return 'Total up to $size';
    final names = plus.length == 1
        ? plus.single
        : '${plus.sublist(0, plus.length - 1).join(', ')} and ${plus.last}';
    return 'Total up to $size plus $names';
  }

  @override
  String driveFree(String size) => 'Free on the drive: $size';

  @override
  String get otzariaOpenTitle => 'Otzaria is open right now';
  @override
  String get otzariaOpenBody =>
      'When you press "Update", the tool will ask to close it. Your open books '
      'will wait for you.';
  @override
  String get otzariaOpenIdleBody =>
      'There is nothing to install right now, so you can keep working in it. '
      'When there is an update, the tool will ask to close it.';
  @override
  String get autoInstallSkippedLead =>
      'That is why the automatic update was not installed. ';
  @override
  String newPluginsTitle(int count) => count == 1
      ? '1 new plugin on the drive'
      : '$count new plugins on the drive';
  @override
  String newPluginsBody(List<String> names, int more) {
    final listed = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    final suffix = more > 0 ? ' and $more more' : '';
    return '$listed$suffix — you can install them in Otzaria.';
  }

  @override
  String get toPluginsButton => 'To plugins';
  @override
  String libraryMissingFilesBody(String names) =>
      'Missing on the drive: $names. Downloading to the drive again fills in '
      'what is missing, and the rest of the update will install as usual.';
  @override
  String get libraryCompanionsAbsentBody =>
      'The drive does not have the Talmud Bavli, the catalog and the '
      'dictionary, so they will not be installed. Downloading to the drive '
      'again brings them.';
  @override
  String get semanticConsentBody =>
      'Smart search is on the drive. To turn it on, agree that Otzaria keeps '
      'your search words and which results helped you.';

  @override
  String get tilesLabel => 'On the drive and on this computer';
  @override
  String get tileApp => 'Otzaria program';
  @override
  String get tileLibrary => 'Otzaria library';
  @override
  String get tilePlugins => 'Plugins';
  @override
  String get tileCustomApps => 'Other programs';
  @override
  String get tileReports => 'Error reports';
  @override
  String get chipReadyToInstall => 'Ready to install';
  @override
  String get chipNewerHere => 'Newer than the drive';
  @override
  String get chipNotOnDrive => 'Not on the drive yet';
  @override
  String get chipChecking => 'Checking…';
  @override
  String get chipInstalling => 'Installing…';
  @override
  String get chipUpdating => 'Updating…';
  @override
  String get chipAttention => 'Something went wrong';
  @override
  String get chipLibraryUpToDate => 'Up to date';
  @override
  String chipPluginUpdates(int count) =>
      count == 1 ? '1 update available' : '$count updates available';
  @override
  String chipPluginsInstalled(int count) => '$count installed';
  @override
  String chipPluginsOnDrive(int count) => '$count on the drive';
  @override
  String get chipNoPlugins => 'No plugins on the drive';
  @override
  String chipAppsPending(int count) => '$count waiting to install';
  @override
  String chipAppsInstalled(int count) => '$count on the drive';
  @override
  String chipReportsToSend(int count) => '$count waiting to send';
  @override
  String chipReportsToCollect(int count) =>
      '$count new to collect from Otzaria';
  @override
  String get chipReportsSending => 'Sending…';
  @override
  String get chipReportsLocked => 'Not available on this drive';
  @override
  String get chipNewOnline => 'New online';
  @override
  String tileFactHere(String value) => 'On this computer: $value';
  @override
  String tileFactDrive(String value) => 'On the drive: $value';
  @override
  String tileFactOnline(String value) => 'Online: $value';
  @override
  String tileFactVersion(String version) => 'version $version';
  @override
  String get updateAvailableButton => 'Update available';

  @override
  String launcherOnline(String version) =>
      'A new version of this tool is available ($version)';
  @override
  String launcherOnDrive(String version) =>
      'The drive has a new version of this tool ($version)';
  @override
  String get launcherDownloading => 'Downloading the new version of the tool';
  @override
  String checkedAt(String time) => 'Checked at $time';
  @override
  String get recheckHint => 'Check again: Ctrl+R or F5';
  @override
  String get checkNowLink => 'Check now';
  @override
  String drive(String letter) => 'Drive $letter';
  @override
  String get driveReadOnlySuffix => 'write-protected';
  @override
  String get driveFullSuffix => 'full';

  @override
  String get welcomeTitle => 'Welcome to Otzaria Updates';
  @override
  String get welcomeLeadOnline =>
      'This is how Otzaria reaches any computer, even without internet:';
  @override
  String get welcomeLeadOffline =>
      'This drive is still empty, and this computer is not connected. Here is '
      'how to start:';
  @override
  String step(int number) => 'Step $number';
  @override
  String get youAreHere => 'You are here';
  @override
  String get step1Title => 'On a connected computer';
  @override
  String get step1BodyOnline => 'Download Otzaria to this drive.';
  @override
  String get step1BodyOffline =>
      'Open the tool there from the drive and download.';
  @override
  String get step2Title => 'The drive changes hands';
  @override
  String get step2Body => 'Eject it safely and take it with you.';
  @override
  String get step3Title => 'On the study computer';
  @override
  String get step3BodyOnline => 'Open the tool there and install in one click.';
  @override
  String get step3BodyOffline => 'Come back here and install in one click.';
  @override
  String get welcomeDownloadButton => 'Download Otzaria to the drive';
  @override
  String get welcomeDownloadNote =>
      'The tool only downloads to the drive. It installs nothing on this '
      'computer unless you ask.';
  @override
  String get welcomeHelpButton => 'How do I start?';
  @override
  String get welcomeOfflineNote =>
      'Nothing can be downloaded from this computer. Plug the drive into a '
      'connected computer and open the tool there.';
  @override
  String get welcomeAlsoOnDrive => 'Also on this drive:';

  @override
  String reportsCollectTitle({
    required int reports,
    required int searchRecords,
  }) =>
      'Otzaria has ${[
        if (reports > 0 || searchRecords <= 0)
          plural(reports, one: '1 new report', many: '$reports new reports'),
        if (searchRecords > 0)
          plural(searchRecords,
              one: '1 search record', many: '$searchRecords search records'),
      ].join(' and ')} waiting';
  @override
  String get reportsCollectBody =>
      'Collecting copies them to the drive, so they can be sent from here or '
      'from a computer with internet. What will be copied:';
  @override
  String get reportsDisclosureReports =>
      'Reports: what you wrote, your email address if you gave it, excerpts '
      'from the app log, technical details about the computer and Otzaria '
      '(such as versions and the operating system), screenshots and images '
      'you attached, and for a crash report you approved — also a copy of '
      'the app memory at the moment of the crash.';
  @override
  String get reportsDisclosureSearch =>
      'Smart search records, collected with your consent: search usage data, '
      'including the search terms, together with the anonymous key that signs '
      'them. They are removed from Otzaria only after being saved to the '
      'drive, and the key is deleted from the drive once all records are sent.';
  @override
  String get reportsDisclosureStorage =>
      'Everything is stored on the drive as it is, unencrypted, until it is '
      'sent — anyone holding the drive can read it. When sent, the data goes '
      'to Otzaria only, and is deleted from the drive.';
  @override
  String get reportsCollectButton => 'Collect from Otzaria';
  @override
  String get reportsNothing =>
      'When something does not work in Otzaria, the report will show up here.';
  @override
  String reportsLockedNote({required bool driveFull}) => driveFull
      ? 'The drive is full, so reports cannot be collected to it, and the ones '
          'on it cannot be sent. Free up space and open the tool again.'
      : 'The drive is write-protected, so reports cannot be collected to it, '
          'and the ones on it cannot be sent. Move the lock switch and open '
          'the tool again.';
}

class _AppScreen extends AppScreenStrings {
  const _AppScreen();

  @override
  String get readyToInstall => 'Ready to install';

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
  String get mirrorEmpty =>
      'None — Download updates to the drive on a computer with internet, from the home page';
  @override
  String channelPair(String stable, String prerelease) =>
      '$stable (stable) · $prerelease (beta)';

  @override
  String get channelStable => 'Stable';
  @override
  String get channelPrerelease => 'Beta';

  @override
  String get launchButton => 'Open Otzaria';

  @override
  String get reinstallButton => 'Reinstall';
}

class _LibraryScreen extends LibraryScreenStrings {
  const _LibraryScreen();

  @override
  String get pickDbButton => 'Choose the Otzaria library file';
  @override
  String get pickDbDialogTitle => 'Choose the seforim.db file';
  @override
  String get dbPathUpdatedSnack => 'The Otzaria library location was updated';

  @override
  String get pickInstallDirButton => 'Choose folder';
  @override
  String get pickInstallDirDialogTitle =>
      'Choose the folder the Otzaria library will be installed to';
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
  String get updatingProgress => 'Updating the Otzaria library…';
  @override
  String get changesTitle => "What's new in the Otzaria library";
  @override
  String changesPendingSubtitle(String version) =>
      'The update adds and fixes books up to version $version.';
  @override
  String changesAppliedSubtitle(String version) =>
      'Books added and changed up to version $version, which is now '
      'installed. Otzaria versions that support it will also show this list '
      'the next time they open.';
  @override
  String changesPartial(int shown, int total) =>
      'This list is partial: it covers $shown of the $total versions in the '
      'range.';
  @override
  String get changesButton => 'Full list';
  @override
  String get changesNotFound =>
      'The list of changes was not found on the drive.';

  @override
  String get reindexTitle => 'Rebuilding search';
  @override
  String get reindexPendingSubtitle =>
      'The database was updated from here, so searching the books that '
      'changed still returns their old content. One request to Otzaria fixes '
      'that.';
  @override
  String get reindexButton => 'Rebuild';
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
  String get fullDownloadInsteadButton => 'Install the full Otzaria library';

  @override
  String get mirrorEmpty =>
      'Empty — Download updates to the drive on a computer with internet, from the home page';
  @override
  String get mirrorUnreadable => 'Cannot be read';
  @override
  String get mirrorNotChecked =>
      'Not checked: the Otzaria library on this computer could not be read';
  @override
  String mirrorHasVersion(String version) => 'Contains version $version';
  @override
  String get mirrorPresent => 'Present';
  @override
  String get personalVersionButton => 'Register this computer';
  @override
  String personalVersionCapturedSnack(String version) =>
      'This computer was registered, at version $version';
  @override
  String get personalVersionNotFoundSnack =>
      'No Otzaria library was found on this computer to read the version from';
  @override
  String get personalOtherMachineTitle =>
      'The drive was prepared for another computer';
  @override
  String personalOtherMachineSubtitle(String version) =>
      'The Otzaria library on the drive fits only the registered computer, '
      'from version $version. This computer is not registered, so there is no '
      'library update for it here.';
  @override
  String get personalOtherMachineSettingsButton => 'To settings';
  @override
  String get personalAskTitle =>
      'Do you want to update several computers, or only your own?';
  @override
  String get personalAskMultiple => 'Several computers';
  @override
  String get personalAskMultipleBody =>
      'The drive keeps everything any computer may need, including the full '
      'Otzaria library.';
  @override
  String get personalAskMine => 'Only my computer';
  @override
  String get personalAskMineBody =>
      'Only what your computer is missing is downloaded, so the download is '
      'much smaller. Other computers will not update from the drive.';
  @override
  String get personalAskLater =>
      'You can change this at any time in the settings.';
  @override
  String get personalPreparedHere => 'The drive is prepared for this computer';
  @override
  String get personalPendingNote =>
      'The computer with Otzaria installed is chosen when you run the tool on it.';
  @override
  String get personalPendingRegisterNote =>
      'The drive is not prepared for any computer yet. If this is the '
      'computer to update from the drive:';
  @override
  String get personalChipElsewhere => 'Prepared for another computer';
  @override
  String get personalChange => 'Change';
  @override
  String personalCardThis(String version) =>
      'The drive is prepared for this computer, from version $version.';
  @override
  String personalCardThisAndOthers(int others, String version) =>
      'The drive is prepared for this computer and '
      '${plural(others, one: 'one more', two: '$others more', many: '$others more')}, '
      'from version $version.';
  @override
  String personalCardOthers(int count, String version) =>
      'The drive is prepared for '
      '${plural(count, one: 'one registered computer', two: '$count registered computers', many: '$count registered computers')}, '
      'from version $version.';
  @override
  String get personalCardNone =>
      'No computer is registered yet, so the full Otzaria library is '
      'downloaded.';
  @override
  String personalDownloadItem(int count, String version) => 'only what '
      '${plural(count, one: 'the registered computer is', two: 'the $count registered computers are', many: 'the $count registered computers are')} '
      'missing, from version $version';
  @override
  String get personalDownloadItemNone =>
      'the full Otzaria library, no computer registered yet';
  @override
  String personalDownloadNote(int count) => 'The drive is prepared for '
      '${plural(count, one: 'one registered computer', two: '$count registered computers', many: '$count registered computers')}.';
  @override
  String get downloadNoteTitle => 'Otzaria library download';
  @override
  String get downloadNeedsOtzariaInstaller =>
      'The library was not downloaded: the drive carries no Otzaria installer '
      'that can read it. Download Otzaria to the drive first (select Otzaria '
      'in the download components), then the library.';
  @override
  String downloadNewerNeedsOtzaria(String version) =>
      'Library release $version was not downloaded: the Otzaria on the drive '
      'cannot read it. To bring it, download a suitable Otzaria to the drive '
      'and download again.';
  @override
  String get downloadKeptNewerMirror =>
      'The drive already holds a newer library than its Otzaria reads, and it '
      'was left as it is. To install it, download a suitable Otzaria to the '
      'drive.';
  @override
  String get downloadMetadataUnreadable =>
      'Some of the library\'s update data online could not be read, so '
      'whether a newer release can be brought is unknown. What is on the '
      'drive was kept — try downloading again later.';
}

class _Settings extends SettingsScreenStrings {
  const _Settings();

  @override
  String get title => 'Settings';

  @override
  String get groupGeneral => 'General';
  @override
  String get groupPrivacy => 'Privacy and reports';
  @override
  String get groupAbout => 'About';
  @override
  String get advancedSummary =>
      'Password lock, common questions, log and reset';

  @override
  String get languageTitle => 'Language';
  @override
  String get languageSystem => 'Same as the computer';
  @override
  String languageSystemAs(String language) =>
      'Same as the computer ($language)';
  @override
  String get languageHebrew => 'עברית';
  @override
  String get languageEnglish => 'English';

  @override
  String get autoCheckTitle => 'Check for updates every time it opens';
  @override
  String get autoCheckSubtitle =>
      'Checks what is on the drive, and on a connected computer also what is new on the site.';
  @override
  String get autoInstallTitle => 'Update on its own without asking';
  @override
  String get autoInstallSubtitle =>
      'When the drive has an update for this computer, it is installed right on opening. '
      'Never applies to a first installation.';
  @override
  String get autoInstallDialogTitle => 'Update on its own without asking?';
  @override
  String get autoInstallDialogContent =>
      'Whenever the tool opens on a computer the drive has an update for, the update '
      'is installed right away. If Otzaria is open, the update waits for next time.';
  @override
  String get autoInstallDialogConfirm => 'Turn on';

  @override
  String get syncTargetsTitle => 'What to download to the drive';
  @override
  String get syncTargetsSubtitle =>
      'Anything not selected is not downloaded, even if it has an update.';
  @override
  String get syncTargetApp => 'Otzaria';
  @override
  String get syncTargetLibrary => 'Otzaria library';
  @override
  String get syncTargetPlugins => 'Plugins';
  @override
  String get syncLibraryLockedSubtitle =>
      'The Otzaria library follows the registered computer.';
  @override
  String get semanticDownloadTitle => 'Smart search';
  @override
  String get semanticDownloadSubtitle =>
      'The files take a few gigabytes. When there is a download:';
  @override
  String get semanticDownloadAsk => 'Ask every time';
  @override
  String get semanticDownloadAlways => 'Always download';
  @override
  String get semanticDownloadNever => "Don't download";
  @override
  String get semanticConsentRowTitle => 'Smart search on this computer';
  @override
  String get semanticConsentRowOn =>
      'On: consent to send training data is active in Otzaria. It can be '
      'revoked only in Otzaria settings: System → Smart search (experimental) '
      '→ Improve the engine.';
  @override
  String get semanticConsentRowOff =>
      'Off: the smart search on the drive is installed with the next update '
      'only after consent to send training data. Otzaria must be closed.';
  @override
  String get semanticConsentRowEnable => 'Enable smart search';

  @override
  String get personalModeDialogTitle =>
      'Download only what your computer is missing?';
  @override
  String get personalModeDialogContent =>
      'From now on the drive gets only what the registered computers are '
      'missing. A computer that is not registered will not update from the '
      'drive, and the full Otzaria library on the drive is deleted on the next '
      'download.';
  @override
  String get personalModeDialogConfirm => 'Turn on';
  @override
  String get personalGroupTitle => 'Which computer the Otzaria library is for';
  @override
  String get personalMachineThis => 'This computer';
  @override
  String get personalMachineUnnamed => 'A registered computer';
  @override
  String personalMachineVersion(String version) => 'Version $version';
  @override
  String personalMachineFloor(String version) =>
      'Version $version · the download starts from it, as it is the lowest';
  @override
  String get personalMachineRemove => 'Remove';
  @override
  String get personalMachinesNone =>
      'No computer is registered yet. The computer with Otzaria installed is '
      'chosen when you run the tool on it.';
  @override
  String personalMachineName(String machineName) => machineName;
  @override
  String personalMachineThisSubtitle(String machineName, String version) =>
      '$machineName · version $version';
  @override
  String get personalMachineNotHere => 'This computer is not registered';
  @override
  String get personalMachinesReadOnly =>
      'The drive is write-protected, so its list of computers cannot change.';
  @override
  String get personalRemoveTitle => 'Remove this computer from the list?';
  @override
  String get personalRemoveBody =>
      'The next download will no longer bring what it is missing. You can '
      'register it again at any time.';
  @override
  String get personalRemoveThisBody =>
      'This computer will no longer update from the drive until it is '
      'registered again.';

  @override
  String get faqEditTitle => 'Edit the common questions';
  @override
  String get faqEditSubtitle =>
      'Hide questions, add your own, and a contact for help on site';

  @override
  String get logTitle => 'Activity log';
  @override
  String get logSubtitle => 'To send to support when something does not work.';
  @override
  String get openLogFolderButton => 'Open the folder';

  @override
  String get resetTitle => 'Reset settings';
  @override
  String get resetSubtitle =>
      'Returns every setting to its default. The password stays.';
  @override
  String get resetButton => 'Reset';
  @override
  String get resetDialogTitle => 'Reset all settings?';
  @override
  String get resetDialogContent =>
      'Every setting returns to its default. Nothing on the drive is deleted, and the password stays.';
  @override
  String get resetDialogConfirm => 'Reset settings';
  @override
  String get resetDoneSnack => 'Settings were reset';

  @override
  String aboutTitle(String version) => 'Otzaria Updates $version';
  @override
  String get aboutSubtitle => 'Check whether a new version exists';
  @override
  String aboutNewVersion(String version) =>
      'New version: $version · what is new and update';
}

class _SaferMode extends SaferModeStrings {
  const _SaferMode();

  @override
  String get lockTitle => 'Password lock';
  @override
  String get noPasswordSubtitle =>
      'Prevents changing settings, choosing a pre-release version and editing the common questions without a password.';
  @override
  String get setPasswordButton => 'Set a password';
  @override
  String get lockOnSubtitle => 'On: opening Settings asks for the password.';
  @override
  String get lockOffSubtitle => 'There is a password, but the lock is off.';
  @override
  String get passwordRowTitle => 'The password';
  @override
  String get passwordRowSubtitle => 'You can change or delete it.';
  @override
  String get passwordRowLockedSubtitle =>
      'To delete it, turn the lock off first.';
  @override
  String get changeButton => 'Change';
  @override
  String get clearButton => 'Delete';
  @override
  String get enabledSnack => 'The lock is on';
  @override
  String get disabledSnack => 'The lock is off';

  @override
  String get verifyTitle => 'Password required';
  @override
  String get verifySettingsHint => 'Settings are locked with a password.';
  @override
  String get verifyFaqHint =>
      'Editing the common questions is locked with a password.';
  @override
  String get verifyEnableHint => 'To turn the lock on, type the password.';
  @override
  String get verifyDisableHint => 'To turn the lock off, type the password.';
  @override
  String get enterButton => 'Unlock';
  @override
  String get passwordLabel => 'Password';
  @override
  String get wrongPassword => 'The password is wrong. Try again.';
  @override
  String get passwordRequired => 'Type a password.';
  @override
  String get showPasswordTooltip => 'Show the password';
  @override
  String get hidePasswordTooltip => 'Hide the password';

  @override
  String get setTitle => 'Set a password';
  @override
  String setIntro(int minLength, {bool onThisComputer = false}) =>
      'The password will be needed to open Settings, choose a pre-release version and '
      'edit the common questions. At least $minLength characters. A forgotten password '
      'cannot be recovered — only the settings file '
      '${onThisComputer ? 'on this computer' : 'on the drive'} can be deleted.';
  @override
  String get setConfirm => 'Save and turn the lock on';
  @override
  String get changeTitle => 'Change the password';
  @override
  String get currentPasswordLabel => 'Current password';
  @override
  String get newPasswordLabel => 'New password';
  @override
  String get confirmPasswordLabel => 'Again, to confirm';
  @override
  String passwordTooShort(int minLength) =>
      'The password is too short: at least $minLength characters.';
  @override
  String get passwordsDoNotMatch => 'The two passwords are not the same.';
  @override
  String get passwordSetSnack => 'The password is set and the lock is on';
  @override
  String get passwordChangedSnack => 'The password was changed';

  @override
  String get clearDialogTitle => 'Delete the password?';
  @override
  String get clearDialogContent =>
      'Without a password, anyone who opens the tool can change settings.';
  @override
  String get passwordRemovedSnack => 'The password was deleted';
}

class _Plugins extends PluginsStrings {
  const _Plugins();

  @override
  String get syncFailedSnack => 'Updating from the website failed';
  @override
  String syncDoneSnack(int fetched, int total) => fetched == 0
      ? 'The plugin list is up to date — nothing new ($total plugins)'
      : 'The plugin list was updated — $fetched of $total downloaded';
  @override
  String syncDoneWithWarningsSnack(int count) =>
      'The list was updated, but $count items did not download. Details are in the log.';
  @override
  String get syncingOverlayStarting => 'Starting…';
  @override
  String get syncDirUnknownTooltip =>
      'The folder is set on the first update from the website';

  @override
  String get saveDialogTitle => 'Save the plugin';
  @override
  String get saveDoneSnack => 'The file was saved';
  @override
  String get saveFailedSnack => 'Saving the file failed';
  @override
  String installDoneSnack(String pluginName) =>
      '$pluginName was installed successfully';
  @override
  String installCancelledSnack(String pluginName) =>
      'Installing $pluginName was cancelled in Otzaria';
  @override
  String installRejectedSnack(String pluginName, String? reason) =>
      'Otzaria did not install $pluginName${reason == null ? '' : ': $reason'}';
  @override
  String get installFailedSnack => 'The installation failed';

  @override
  String get loadingCatalog => 'Loading the plugin list…';

  @override
  String get noResultsTitle => 'No plugins match your filters';
  @override
  String get noResultsBody => 'Try another word, or search all categories.';

  @override
  String get filterStatusLabel => 'Stability';
  @override
  String get filterSortLabel => 'Sort';
  @override
  String get sortRecommended => 'Recommended';
  @override
  String get sortNewest => 'Newest';
  @override
  String get sortUpdated => 'Recently updated';
  @override
  String get filterTagsLabel => 'Tags';
  @override
  String get showMoreTags => 'Show more';
  @override
  String get showFewerTags => 'Show fewer';

  @override
  String pluginVersionBadge(String version) => 'Version $version';

  @override
  String ratingBadge(String average, int count) => '$average ($count)';
  @override
  String ratingTooltip(int count) => 'Average rating from $count raters';
  @override
  String get ratingPanelTitle => 'User rating';
  @override
  String ratingCountLabel(int count) =>
      count == 1 ? '$count rater' : '$count raters';
  @override
  String ratingVerifiedLabel(int count) => '$count actually installed it';
  @override
  String get ratingVerifiedTooltip =>
      'Raters whose install of the plugin was actually recorded';
  @override
  String get ratingEmpty => 'This plugin has not been rated yet';
  @override
  String ratingStarsLabel(String average) => 'Rated $average out of 5';
  @override
  String get sourcePageButton => 'Source page';

  @override
  String get statusStable => 'Stable';
  @override
  String get statusExperimental => 'Experimental';
  @override
  String get statusUnknown => 'Unknown';

  @override
  String get infoPanelTitle => 'General information';
  @override
  String get tagsPanelTitle => 'Categories and tags';
  @override
  String get screenshotsPanelTitle => 'Screenshots';
  @override
  String get infoVersion => 'Version';
  @override
  String get infoStatus => 'Stability';
  @override
  String get infoAuthor => 'Developer';
  @override
  String get infoUpdated => 'Updated';
  @override
  String get infoNetwork => 'Internet connection';
  @override
  String get infoNetworkRequired => 'Required';
  @override
  String get infoNetworkNotRequired => 'Not required';
  @override
  String get valueUnspecifiedMasculine => 'Not specified';

  @override
  String get screenshotPrevious => 'Previous';
  @override
  String get screenshotNext => 'Next';

  @override
  String get storeAppButton => 'Copy the store to a computer';
  @override
  String get storeAppDialogTitle => 'The plugin store as a desktop program';
  @override
  String get storeAppDialogBody =>
      'A separate Windows program, with every plugin on this drive packed '
      'inside it. Copy it to a flash drive, browse the plugins and install '
      'them straight into Otzaria — even on a machine with no internet.';
  @override
  String get storeAppHighlightBundled =>
      'Every plugin on this drive is packed in';
  @override
  String get storeAppHighlightOffline => 'Works with no internet connection';
  @override
  String get storeAppHighlightDirect => 'Installs straight into Otzaria';
  @override
  String get storeAppChipWindows => 'For Windows';
  @override
  String storeAppChipSize(String size) => 'Size $size';
  @override
  String storeAppChipUpdated(String date) => 'Updated $date';
  @override
  String get storeAppChooseFolder => 'Choose a folder…';
  @override
  String get storeAppUnavailableTooltip =>
      'The store program is not on the drive yet. Download updates to the drive on a computer with internet, from the home page.';
  @override
  String get storeAppNoPluginsTooltip =>
      'There are no plugins on this drive. Sync the store on a computer with '
      'internet.';
  @override
  String get storeAppPickFolderTitle => 'Where should the plugin store go?';
  @override
  String get storeAppOverwriteTitle => 'A store is already here';
  @override
  String storeAppOverwriteContent(String path) =>
      'A plugin store already sits in $path. Updating will overwrite the '
      'program and the plugins, and will leave everything else alone.';
  @override
  String get storeAppOverwriteConfirm => 'Update';
  @override
  String get storeAppUpdateButton => 'Update the store';
  @override
  String get storeAppUpdateHereTitle => 'Update the plugin store';
  @override
  String storeAppUpdateHereContent(String path) =>
      'The store copied to $path is out of date. Update it there?';
  @override
  String get storeAppChooseOtherFolder => 'Choose another folder';
  @override
  String get storeAppInUseSnack =>
      'The store is open right now. Close it and try again.';
  @override
  String get storeAppCopyingTitle => 'Copying the plugin store';
  @override
  String get storeAppDoneTitle => 'The store was copied';
  @override
  String storeAppDoneContent(int plugins, String size) =>
      'The store was copied with $plugins plugins ($size).';
  @override
  String storeAppDoneSkipped(int count) =>
      '$count plugins have no file on this drive and were left out.';
  @override
  String get storeAppOpenFolder => 'Open the folder';
  @override
  String get storeAppLaunch => 'Launch the store';
  @override
  String storeAppFailedSnack(String error) => 'The copy failed: $error';
  @override
  String storeAppLaunchFailedSnack(String error) =>
      'Launching the store failed: $error';

  @override
  String get storeTitle => 'Plugins';
  @override
  String get storeSubtitle =>
      'Plugins that extend Otzaria. Everything here is already on the drive and installs without internet.';
  @override
  String asOfDate(String date) => 'As of $date.';
  @override
  String get refreshButton => 'Refresh';
  @override
  String get syncingTitle => 'Updating the plugin list from the website';
  @override
  String get syncingHint =>
      'Only new and updated plugins are downloaded. You can keep browsing meanwhile.';
  @override
  String get syncStopButton => 'Stop';
  @override
  String get syncStoppedSnack =>
      'The update stopped. What was already downloaded is kept on the drive.';
  @override
  String get emptyTitle => 'No plugins on the drive yet';
  @override
  String get emptyBodyOnline =>
      'Plugins come to the drive with the Otzaria updates. "Refresh" downloads them now.';
  @override
  String get emptyBodyOffline =>
      'Plugins come to the drive with the Otzaria updates. On a computer with internet, click "Download everything to the drive" on the home page, and they will appear here.';
  @override
  String get searchHint => 'Search plugins by name or topic';
  @override
  String get clearSearchTooltip => 'Clear';
  @override
  String get filterAll => 'All';
  @override
  String get filterInstalled => 'Installed';
  @override
  String get filterNotInstalled => 'Not installed';
  @override
  String get moreFilters => 'More filters';
  @override
  String moreFiltersCount(int count) => 'More filters ($count)';
  @override
  String noResultsForQuery(String query) => 'No plugins found for "$query"';
  @override
  String get clearFiltersButton => 'Clear search and filters';
  @override
  String updatesAvailable(int count) => plural(count,
      one: 'One update available', many: '$count updates available');
  @override
  String updatesBarNames(String names) =>
      '$names · sent to Otzaria, where you approve each one';
  @override
  String joinNames(List<String> names) => names.length < 2
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  @override
  String get updateAllButton => 'Update all';
  @override
  String updatingAllLabel(int current, int total) =>
      'Sending to Otzaria, $current of $total…';
  @override
  String updatesSentSnack(int count) => plural(count,
      one: 'The update was sent to Otzaria — approve it there',
      many: '$count updates were sent to Otzaria — approve them there');
  @override
  String updateAllNoneSentSnack(String names) => 'Not sent to Otzaria: $names';
  @override
  String updateAllPartlySentSnack(int sent, String names) => plural(sent,
      one: 'One update was sent to Otzaria — approve it there. '
          'Not sent: $names',
      many: '$sent updates were sent to Otzaria — approve them there. '
          'Not sent: $names');
  @override
  String updateAllStoppedSnack(int sent) => plural(sent,
      one: 'Updating stopped. One update was sent to Otzaria — approve it '
          'there',
      many: 'Updating stopped. $sent updates were sent to Otzaria — approve '
          'them there');
  @override
  String get updateAllStoppedNoneSnack =>
      'Updating stopped. Nothing was sent to Otzaria.';
  @override
  String get updateAllStoppedPrefix => 'Updating stopped.';
  @override
  String get updateAllStoppingLabel => 'Stopping after the current plugin…';
  @override
  String get actionsBlockedSyncing =>
      'Plugins cannot be installed or saved while the list updates from the website.';
  @override
  String get actionsBlockedExporting =>
      'Plugins cannot be installed or saved while the store is being copied.';
  @override
  String get actionsBlockedUpdatingAll =>
      'Other plugins cannot be installed or saved during "Update All".';
  @override
  String get actionsBlockedElsewhere =>
      'Another task is running. Plugins cannot be installed or saved meanwhile.';
  @override
  String get howItWorksButton => 'How does this work?';
  @override
  String get updatesSentTitle =>
      'The updates were sent to Otzaria — approve them there';
  @override
  String get updatesSentBody =>
      'This list updates by itself as soon as Otzaria finishes installing.';
  @override
  String installSentSnack(String pluginName) =>
      '$pluginName was sent to Otzaria — approve it there';
  @override
  String get newChip => 'New';
  @override
  String get networkChip => 'Needs internet';
  @override
  String get installInOtzariaButton => 'Install in Otzaria';
  @override
  String updateToButton(String version) => 'Update to $version';
  @override
  String get saveFileButton => 'Save plugin file…';
  @override
  String get sendingLabel => 'Sending to Otzaria…';
  @override
  String get sentLabel => 'Sent to Otzaria — approve there';
  @override
  String get developmentLabel => 'In development here';
  @override
  String get incompatibleLabel => 'Not compatible with your Otzaria';
  @override
  String get disabledLabel => 'Disabled in Otzaria';
  @override
  String get installedLabel => 'Installed';
  @override
  String get noteIncompatible => 'No version fits the Otzaria on this computer';
  @override
  String noteNeedsApp(String version) => 'Needs Otzaria $version or later';
  @override
  String get noteNeedsOtzaria => 'Install Otzaria first';
  @override
  String get noteSaveOnly => 'No direct install — save the file';
  @override
  String get noteDisabled => 'Disabled in Otzaria';
  @override
  String get noteFileMissing =>
      'Not on the drive yet — downloaded on install (needs internet)';
  @override
  String get noteFileMissingOnline =>
      'Not on the drive yet — it downloads from the website now';
  @override
  String get fileNotOnDriveLabel => 'The file is not on the drive';
  @override
  String get noteNextDriveDownload =>
      'It comes with the next download to the drive';
  @override
  String get incompatibleTitle =>
      'This plugin does not fit the Otzaria on this computer';
  @override
  String incompatibleBodyVersions(String needs, String here) =>
      'It needs Otzaria $needs or later, and this computer has $here. After you update Otzaria you can install it.';
  @override
  String get incompatibleBody =>
      'It has no version that runs on the Otzaria here. After you update Otzaria you can install it.';
  @override
  String get disabledTitle => 'The plugin is disabled in Otzaria';
  @override
  String get disabledBody =>
      'It is installed but not active. You can turn it back on in the Otzaria plugin settings.';
  @override
  String get disabledUpdateBody =>
      'The update installs even while it is disabled.';
  @override
  String get developmentTitle => 'Plugin in development';
  @override
  String get developmentBody =>
      'Otzaria loads it from its own folder on this computer, so this tool does not update it.';
  @override
  String get fileMissingTitle => 'The plugin file is not on the drive yet';
  @override
  String get fileMissingBody =>
      'It downloads the next time you download updates to the drive on a computer with internet. On a connected computer, installing downloads it now.';
  @override
  String get factRating => 'Rating';
  @override
  String get factCompatible => 'Fits your Otzaria';
  @override
  String get factYes => 'Yes';
  @override
  String get factNo => 'No';
  @override
  String factOtzariaVersion(String version) => 'Otzaria $version';
  @override
  String get factVersionLatest => 'Latest';
  @override
  String get factVersionInstalled => 'Installed here';
  @override
  String factVersionInstalledAt(String version) => 'You have $version';
  @override
  String get factNetworkAny => 'Works on any computer';
  @override
  String get factNetworkSome => 'For some features';
  @override
  String get factSize => 'Size';
  @override
  String get factOnDrive => 'On the drive';
  @override
  String get factNotOnDrive => 'Not on the drive';
  @override
  String get descriptionTitle => 'Description';
  @override
  String get versionsTitle => 'Versions';
  @override
  String get versionLatestTag => 'latest';
  @override
  String get versionInstalledTag => 'installed here';
  @override
  String get infoDownloads => 'Downloads';
  @override
  String get infoSource => 'Source';
  @override
  String get copyAddressTooltip => 'Copy address';
  @override
  String get addressCopiedSnack => 'Address copied';
  @override
  String get ratingSourceNote => 'Ratings are given on the Otzaria website.';
  @override
  String ratingAsOfNote(String date) =>
      'As of $date, when you downloaded to the drive. Ratings are given on the Otzaria website.';
  @override
  String get screenshotZoom => 'Enlarge screenshot';
  @override
  String screenshotNumber(int index, int total) =>
      'Screenshot $index of $total';
  @override
  String get advancedSummary => 'Copy the plugin store to this computer';
  @override
  String get storeAppCopyButton => 'Copy…';
  @override
  String get storeAppRowBody =>
      'A small app that shows the plugins on the drive and installs them even without the drive (Windows).';
  @override
  String get reloadRowTitle => 'Reload from the drive';
  @override
  String get reloadButton => 'Reload';
}

class _Faq extends FaqStrings {
  const _Faq();

  @override
  String get title => 'Common questions';
  @override
  String get intro => 'Short answers to questions that keep coming up.';

  @override
  String get groupBasics => 'How this works';
  @override
  String get groupDownload => 'Downloading and installing';
  @override
  String get groupLibrary => 'The books are not found';
  @override
  String get groupExtras => 'Plugins and other programs';
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
      'internet, open the program there and press "Download everything to the drive" — everything is '
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
      '"Download everything to the drive" again continues from there. Cancelling on purpose does not '
      'erase what has finished downloading or earlier runs — it only clears the '
      'part that was in progress.';
  @override
  String get qDownloadTooBig =>
      'The download is enormous and I only want to update the Otzaria library I '
      'already have';
  @override
  String get aDownloadTooBig =>
      'In the settings, under "Which computer the Otzaria library is for", '
      'choose "Only my computer". From then on only the steps from your own '
      'version upwards are fetched instead of the whole Otzaria library — far '
      'less data. Your computer registers itself the first time the tool opens '
      'on it. One caveat: such a drive '
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
      'The Otzaria library is likewise not detected when it sits somewhere other than '
      'the default. On the Otzaria library page, under Advanced, pick the location manually. If '
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
      'I updated the Otzaria library, but the search in Otzaria does not find the new '
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
  String get qWhatAreCustomApps => 'What are "Other programs"?';
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
      'the wrong computer. The fix: move the whole program folder to a USB '
      'stick or an external drive, and run it from there.';
  @override
  String get qLauncherSelfUpdate => 'Does this program update itself too?';
  @override
  String get aLauncherSelfUpdate =>
      'Yes. When a new version exists it offers to download it on a computer '
      'with internet, then replaces itself and reopens. Your settings, books '
      'and plugins already on the drive stay untouched. If the replacement '
      'was interrupted (say, by a power cut) and the program file is gone, '
      'run .launcher-previous.exe next to it — it restores the previous '
      'version under its usual name.';
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
  String get contactTitle => 'Help on site';

  @override
  String get contactLead => 'Help on site:';

  @override
  String get editButton => 'Edit';
  @override
  String get editDoneButton => 'Done';
  @override
  String get editTitle => 'Edit the common questions';
  @override
  String get editIntro =>
      'Hidden questions are not shown. Changes are saved on the drive.';
  @override
  String get editIntroThisComputer =>
      'Hidden questions are not shown. Changes are saved on this computer.';

  @override
  String get hideTooltip => 'Hide';
  @override
  String get restoreTooltip => 'Show';
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
  String get contactAutoSaveNote => 'Saved automatically.';
  @override
  String get contactNameLabel => 'Contact name';
  @override
  String get contactPhoneLabel => 'Phone';
}

class _SetupError extends SetupErrorStrings {
  const _SetupError();

  @override
  String get title => 'This program is in the wrong place';
  @override
  String get explanation =>
      'The launcher keeps all of its data — the Otzaria library, the plugins and the '
      'Otzaria program itself — in a folder right next to it, so everything '
      'travels together on the drive. The current folder is blocked for '
      'writing — permissions, or a write-protected drive — and carries no '
      'mirror to install from, so there is nowhere to save.';
  @override
  String get whatToDo =>
      'What to do: if the drive itself is write-protected (a lock switch on '
      'the drive, a burned disc, or read-only permissions) — remove the '
      'protection, download the updates, and then you can lock it again and '
      'install from it on any computer. Otherwise — move the whole program '
      'folder onto a USB stick or an external drive, and run it from '
      'there.';
  @override
  String get attemptedDirTitle => 'Folder that was tried';
  @override
  String cannotWriteToDataDir(String osMessage) =>
      'Cannot write to the folder next to this program: $osMessage';
  @override
  String get driveFull =>
      'The drive is full — there is no room even for a tiny test file. Free '
      'up space on the drive and start the program again.';
  @override
  String get driveFullTitle => 'The drive has no free space';
  @override
  String get appTranslocated =>
      'macOS is running this program from a temporary read-only copy because '
      'it is marked as downloaded from the internet, so it cannot see the '
      'folder next to it. Move the program to another folder and back in '
      'Finder, or run in Terminal: xattr -dr com.apple.quarantine followed by '
      'the program dragged in — then open it again.';
  @override
  String get appTranslocatedTitle =>
      'macOS is running this program from a temporary copy';
  @override
  String get runningFromTemp =>
      'This program was started from inside a ZIP file or a temporary folder, '
      'and everything it downloads there would be deleted along with that '
      'folder. Extract the file to a USB stick or an external drive and run '
      'it from there.';
  @override
  String get runningFromTempTitle =>
      'Extract the file to a drive before running it';
  @override
  String get systemDrive =>
      'This program carries the updates from one computer to another, so it '
      'has to be on a USB stick or an external drive — not on the '
      "computer's main drive. Copy the whole program folder (including the "
      'app-files folder) to the portable drive and run it from there.';
  @override
  String get systemDriveTitle => 'Run the program from a portable drive';
  @override
  String get macVolumeAccessDenied =>
      'macOS did not allow this program to write to the folder next to it. '
      'Open System Settings → Privacy & Security → Files and Folders (or Full '
      'Disk Access), allow Otzaria Updates to access that location — a '
      'removable drive, Documents, Desktop or Downloads — and open the program '
      'again.';
}

class _ReadOnlyDrive extends ReadOnlyDriveStrings {
  const _ReadOnlyDrive();

  @override
  String get bannerTitle => 'The drive is write-protected';
  @override
  String get bannerSubtitle =>
      'You can update this computer from it, but new updates and reports '
      'cannot be saved on it. To change that, slide the lock switch on the '
      'side of the drive and open the tool again.';
  @override
  String get downloadsDisabledSnack =>
      'The drive is write-protected — there is nowhere to download to. You '
      'can still install what it already carries.';
  @override
  String get customAppsManageDisabled =>
      'The drive is write-protected, so programs cannot be added, edited or '
      'removed here. Programs already on the drive install as usual.';
  @override
  String get bannerTitleDriveFull => 'The drive is full';
  @override
  String get bannerSubtitleDriveFull =>
      'Very little space is left on it, so updates cannot be downloaded to it '
      'and reports cannot be saved. Free some space, or move the folder to a '
      'larger drive, and open the tool again.';
  @override
  String get downloadsDisabledSnackDriveFull =>
      'The drive is full — there is nowhere to download to. Free up space on '
      'it and restart the program; you can still install what it already '
      'carries.';
  @override
  String get customAppsManageDisabledDriveFull =>
      'The drive is full, so programs cannot be added, edited or removed here '
      'until space is freed on it. Programs already on the drive install as '
      'usual.';
}

class _Elevation extends ElevationStrings {
  const _Elevation();

  @override
  String get hint =>
      'The folder appears to be protected and to need administrator rights — '
      'that is what happens when Otzaria is installed under Program Files. '
      'You can close this program, start it again with a right-click on the '
      'executable → "Run as administrator", and try again.';
  @override
  String get macHint =>
      'The folder does not appear to be writable. On macOS there are three '
      'things to try: install Otzaria into the "Applications" folder inside '
      'your home directory (~/Applications) rather than the machine-wide '
      '/Applications; pick a library location inside your home directory; or '
      'grant this program Full Disk Access in System Settings → Privacy & '
      'Security → Full Disk Access, and then reopen it.';
  @override
  String get bannerTitle => 'Administrator rights are needed';
  @override
  String get bannerContent =>
      'The folder is protected from changes. The tool will reopen as '
      'administrator, and then you can try again.';
  @override
  String get bannerConfirm => 'Restart as administrator';
  @override
  String get bannerDismiss => 'Not now';
  @override
  String restartFailedSnack(String error) =>
      'Restarting as administrator failed: $error. You can close this program '
      'and start it again with a right-click on the executable → "Run as '
      'administrator".';
  @override
  String get busyNotice =>
      'Restarting as administrator closes this program, so it will be offered '
      'again once the download or install that is running right now finishes.';
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
  String installedVersion(String version) => 'Installed version: $version';

  @override
  String get installButton => 'Install and restart';

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
  String get busyNotice =>
      'Installing the new version closes and reopens this program, so it '
      'waits for the download or install that is running right now.';
  @override
  String get installUnavailableNotice =>
      'Close the tool, copy the new file from the folder below, and put it in '
      "place of the tool's old file.";

  @override
  String get whatsNewHeading => "What's new:";

  @override
  String get changelogButton => 'Changelog';

  @override
  String get changelogDialogTitle => 'Program changelog';

  @override
  String get changelogNotFound => 'No changelog file was found.';

  @override
  String get executableNotFound =>
      'The executable this program runs from could not be located, so there '
      'is nothing to replace. Please download the new version and replace the '
      'file manually.';
  @override
  String get mirrorMissing =>
      'The new version has not been downloaded to the folder beside the '
      'program yet. Download updates to the drive on a computer with internet, from the home page.';
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
  String replaceFailedNotRestored(
    String error,
    String previousPath,
    String executableName,
  ) =>
      'Replacing the executable failed: $error, and putting the previous '
      'file back failed too. It is kept as $previousPath — rename it back to '
      '$executableName.';
  @override
  String restartFailed(String error) =>
      'Launching the new version failed: $error. Please close the program and '
      'start it again manually — the replacement itself already finished.';
  @override
  String restartFailedRolledBack(String error) =>
      'Launching the new version failed: $error. The previous version was '
      'restored.';
  @override
  String get digestMismatch =>
      'The new version in the folder is damaged — it does not match the '
      'checksum GitHub publishes for it. Download it again on a computer with '
      'internet.';
}

const _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

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
  @override
  String perSecond(String size) => '$size/s';
  @override
  String longDate(int day, int month, int year) =>
      '${_englishMonths[(month - 1) % 12]} $day, $year';
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
      'Only my computer: downloading update files from version '
      '$localVersion onwards, without the full Otzaria library';
  @override
  String exportPersonalUpToDate(int localVersion) =>
      'Nothing newer than $localVersion — nothing was downloaded';
  @override
  String get exportPersonalVersionUnknown =>
      'The Otzaria library version on this computer was not detected — downloading the full library';
  @override
  String get semanticTargetUnknown =>
      'Which smart-search files match the library the drive\'s Otzaria reads '
      'is unknown without a download';
  @override
  String get exportKeptNewerMirror =>
      'The drive already holds a newer library than its Otzaria reads — '
      'leaving it as it is';
  @override
  String get exportPersonalMirrorDamaged =>
      'The library updates in the folder are damaged — downloading the full '
      'database';
  @override
  String exportReusingFullDb(int version, String tag) =>
      'Keeping the full database already in the folder (version $version, '
      '$tag) — update files can carry it to the latest version, so there is '
      'no need to download it again';
  @override
  String exportDownloading(String tag, String asset) =>
      'Downloading $tag / $asset';
  @override
  String exportVerifying(String tag, String asset, int percent) =>
      'Verifying $tag / $asset — $percent%';
  @override
  String exportAssembling(String tag, String asset, int percent) =>
      'Assembling $tag / $asset from its parts — $percent%';
  @override
  String exportSplitFullDbSkipped(String tag, String detail) =>
      'The full database of $tag was published in parts, but the manifest of '
      'the parts is damaged or does not match them, so it was not downloaded '
      '($detail)';
  @override
  String exportSplitPartCorrupted(String asset, String parts) =>
      'Parts of $asset read back from the drive differ from what was '
      'downloaded ($parts) — the drive may be faulty. Those parts were '
      'deleted and nothing was written to the mirror; try again and they '
      'will be downloaded again.';
  @override
  String exportAssembledReplaceFailed(String path, String detail) =>
      'Could not save $path after assembling it from its parts — another '
      'program (an antivirus, for example) may be holding it. Try again. '
      '($detail)';
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
  String exportSkippingUnappliablePatch(
    String tag,
    String file,
    int schemaVersion,
  ) =>
      'The update file $file in release $tag is built on schema '
      '$schemaVersion, which cannot be applied, so it is not being copied '
      'into the mirror';
  @override
  String exportSkippingUnsupportedPatchFormat(
    String tag,
    String file,
    int patchFormatVersion,
  ) =>
      'The update file $file in release $tag is built in format '
      '$patchFormatVersion, which cannot be applied, so it is not being '
      'copied into the mirror';
  @override
  String exportFullDbRequiredBySchema(int schemaVersion, int latestVersion) =>
      'Version $latestVersion uses a new database format (schema '
      '$schemaVersion): downloading the full database instead of the update '
      'files';
  @override
  String exportFullDbRequiredByPatchFormat(
    int patchFormatVersion,
    int latestVersion,
  ) =>
      'The update files of version $latestVersion are built in a new format '
      '($patchFormatVersion): downloading the full database instead';
  @override
  String exportFullDbSchemaUnsupported(String tag, int schemaVersion) =>
      'The full database of $tag was published only in schema $schemaVersion, '
      'which this version of the software cannot install — it was not '
      'downloaded, and the offline computer will show that a software update '
      'is needed';
  @override
  String exportSkippingPatchesFullDbWins(int fileCount, int fullDbVersion) =>
      'Skipping $fileCount update files: the full database (version '
      '$fullDbVersion) reaches higher than any appliable chain, so they are '
      'not needed';
  @override
  String exportFullDbInsteadOfSlowPatches(
    int fileCount,
    int patchMinutes,
    int fullDbMinutes,
    int toVersion,
  ) =>
      'The update to version $toVersion rewrote the database end to end: '
      'applying its update files would take about $patchMinutes minutes on '
      'the computer being updated, against about $fullDbMinutes minutes to '
      'swap in the full database. Skipping those $fileCount files and '
      'downloading the full database instead';
  @override
  String exportPersonalNeedsFullDb(int fromVersion, int latestVersion) =>
      'There is no chain of update files that can carry version $fromVersion '
      'to version $latestVersion, so the full database is being downloaded — '
      'even though downloading only for your computer normally skips it';

  @override
  String exportPersonalNoFullDbEither(int fromVersion, int latestVersion) =>
      'There is no chain of update files from version $fromVersion to '
      'version $latestVersion, and no full database for the latest version '
      'either. Choose "Several computers" in the settings and download '
      'again.';

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
  String planFullDbFasterThanPatches(
    int stepCount,
    int patchMinutes,
    int fullDbMinutes,
  ) =>
      'Applying the $stepCount update files would take about $patchMinutes '
      'minutes, against about $fullDbMinutes minutes to swap in the full '
      'database — replacing the full database instead';
  @override
  String planNoFullDbEither(String reason) =>
      '$reason, and no full database is available to download';
  @override
  String planPatchSchemaTooNew(int schemaVersion, int latestVersion) =>
      'The newest library release ($latestVersion) is built on database '
      'schema $schemaVersion, which this version of the software does not '
      'know how to apply through update files';
  @override
  String planOtzariaTooOldForLibrary(int readableSchema, int latestVersion) =>
      'Otzaria library release $latestVersion needs a newer Otzaria: the installed '
      'version reads databases up to schema $readableSchema only. Update '
      'Otzaria first, then the library.';
  @override
  String planStopsBeforeOtzariaSchema(int reachedVersion, int latestVersion) =>
      'The Otzaria library will be updated to release $reachedVersion. Release '
      '$latestVersion needs a newer Otzaria — update Otzaria to continue.';
  @override
  String libraryNeedsOtzariaUpdateFromDrive(String otzariaVersion) =>
      'The drive carries Otzaria $otzariaVersion, which reads the new Otzaria library: '
      'update Otzaria first, then the library.';
  @override
  String planPatchFormatTooNew(int patchFormatVersion, int latestVersion) =>
      'The update files of the newest release ($latestVersion) are built in '
      'format $patchFormatVersion, which this version of the software does '
      'not know how to apply';
  @override
  String planFullDbWouldNotProgress(
    int reachableVersion,
    int localVersion,
    int latestVersion,
  ) =>
      'The full database available for download only reaches version '
      '$reachableVersion, which is not newer than the version already '
      'installed ($localVersion) — installing it would replace the Otzaria library '
      'with an older version instead of updating it to version '
      '$latestVersion. The update was therefore not performed: a newer full '
      'database, or a newer version of the software, is needed.';
  @override
  String planNewSchemaNeedsFullDb(int latestVersion, int schemaVersion) =>
      'Version $latestVersion moved to a new database format (schema '
      '$schemaVersion), so the whole database is downloaded anew instead of '
      'update files';
  @override
  String planPartialDeltaSchemaStop(
    int reachedVersion,
    int latestVersion,
    int schemaVersion,
  ) =>
      'This update reaches version $reachedVersion. Version $latestVersion '
      'moved to a new database format (schema $schemaVersion) that has no '
      'update files — reaching it requires a new full database.';
  @override
  String planPartialDeltaFormatStop(
    int reachedVersion,
    int latestVersion,
    int patchFormatVersion,
  ) =>
      'This update reaches version $reachedVersion. The update files of '
      'version $latestVersion are built in format $patchFormatVersion, which '
      'the software cannot apply — reaching it requires a new full database.';

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
      'Schema version $schemaVersion is not supported for applying update '
      'files — a full database download is required';
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
      'the database was left untouched. A full download of the Otzaria library is '
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
  String patchFormatTooNew(int patchFormatVersion, int supported) =>
      'The patch file format ($patchFormatVersion) is outside the supported '
      'range (1–$supported) — please update this program';
  @override
  String patchFormatMismatch(int inPatch, int inManifest) =>
      'The patch file format ($inPatch) does not match what the manifest '
      'declared ($inManifest)';
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
      'The downloaded file is damaged (sha256 mismatch) and was deleted — '
      'download again. If it keeps happening, the drive may be faulty: check '
      'it for errors or replace it.';
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
      'The file on the drive is damaged and cannot be used: $url — download '
      'again on a computer with internet. If it keeps happening, the drive '
      'may be faulty.';
  @override
  String get manifestMissingPatchFormatVersion =>
      'Required manifest field is missing for schema 4+: patchFormatVersion';
  @override
  String manifestInvalidOptionalField(String key) =>
      'Invalid optional manifest field: $key';
  @override
  String manifestInvalidHashMap(String key) =>
      'Invalid value in the manifest hash map: $key';
  @override
  String splitManifestDownloadFailed(String name, int statusCode) =>
      'Failed to download the split manifest ($name): $statusCode';
  @override
  String get interruptedUpdateWithoutBackup =>
      'An unfinished update marker was found without a backup — the DB must '
      'be checked';
  @override
  String get interruptedUpdateRestored =>
      'An interrupted update was detected — the DB was restored from the '
      'backup';
  @override
  String planSchemaNeedsAppUpdate(int schemaVersion, int supportedSchema) =>
      'The Otzaria library moved to DB schema $schemaVersion, newer than supported '
      '(DB $supportedSchema) — an app update is required';
  @override
  String planSchemaBarrierNeedsFullDownload(int schemaVersion) =>
      'The Otzaria library moved to DB schema $schemaVersion; the change requires a '
      'full download';
  @override
  String planDeltaNeedsAppUpdate(
    int latestVersion,
    int supportedSchema,
    int supportedPatchFormat,
  ) =>
      'The delta route to version $latestVersion needs a DB schema or patch '
      'format newer than supported (DB $supportedSchema, patch '
      '$supportedPatchFormat) — an app update is required';
  @override
  String planHeavyDelta(String deltaSize, String localDbSize) =>
      'The delta route unpacks $deltaSize against a local DB of '
      '$localDbSize, and applying it may take a long time';
  @override
  String tableHashMismatch(String tables) =>
      'The hash after applying does not match toTableContentHashes in tables: '
      '$tables';
  @override
  String patchOpenFailed(String path, String detail) =>
      'Cannot open the patch file ($path): $detail';
  @override
  String get networkInterrupted =>
      'The network connection was interrupted during the download';
  @override
  String get deletePreviousArchiveFailed =>
      'Deleting the previous archive failed — the downloaded parts cannot be '
      'joined';
  @override
  String joinedArchiveSizeMismatch(int written, int expected) =>
      'The joined archive size ($written) does not match the expected '
      '($expected)';
  @override
  String get joinedArchiveHashMismatch =>
      'The sha256 of the joined archive does not match';

  @override
  String get mirrorMissing =>
      'No Otzaria library updates have been downloaded to the drive yet. Download updates to the drive on a computer with internet, from the home page.';
  @override
  String get mirrorDamaged =>
      'The library updates in the local folder are damaged and cannot be '
      'read — usually a drive that was unplugged without "Safely Remove" or '
      'a faulty drive. Run the download again on a computer with internet; '
      'if it keeps happening, check the drive for errors or replace it.';
  @override
  String interruptedUpdateCorruptDb(String detail) =>
      '$detail — the database failed quick_check, so it must be replaced by '
      'a full database download.';
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
  String get fullDbNeedsNativeZstd =>
      'Extracting the full database requires the zstd library, which is not available on this computer';
  @override
  String get patchNeedsNativeZstd =>
      'Extracting the update file requires the zstd library, which is not available on this computer';
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
  String fileTooLargeForVolume(String dir) =>
      'The drive holding $dir is formatted as FAT32, which cannot store files '
      'larger than 4 GB, and the Otzaria library database is larger than that. Choose '
      'a location for the database on an NTFS or exFAT drive.';
  @override
  String installDirNotWritable(String dir, String detail) =>
      'The folder $dir could not be created ($detail). Choose another location '
      'for the database through "Choose location manually" on the Otzaria library '
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
  String get localDbLocked =>
      'Could not read the local Otzaria library version because the database is '
      'locked, probably because Otzaria is open. Close Otzaria and check '
      'again.';
  @override
  String get localDbInterruptedWrite =>
      'Could not read the local Otzaria library version: the database was left in '
      'the middle of an interrupted write. Open and close Otzaria, then '
      'check again.';
  @override
  String get localDbReadOnlyLocation =>
      'Could not read the local Otzaria library version because its folder is '
      'write-protected. Allow writing to the folder and check again.';
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
  String get companionSemanticName => 'Smart search';
  @override
  String get libraryChangesNotesName => "The Otzaria library's what's-new list";
  @override
  String get semanticDownloading => 'Downloading smart search files';
  @override
  String get semanticInstalling => 'Installing smart search';
  @override
  String get semanticConsentTitle => 'Help improve the engine';
  @override
  String get semanticConsentTerms =>
      'This is experimental search, and your searches help improve it. Using it requires consent to send usage data: search terms, displayed results and their rankings, passages opened or rated (like / dislike) and time spent reading them, plus the app and operating system versions. Content from personal books is not sent. Recognized email addresses and file paths are masked in search text, but other personal details may still be sent. Do not include personal details in search text. You can revoke consent at any time in Otzaria settings; revoking it disables this search mode.';
  @override
  String get semanticConsentText =>
      'This is experimental search, and your searches help improve it. Using it requires consent to send usage data: search terms, displayed results and their rankings, passages opened or rated (like / dislike) and time spent reading them, plus the app and operating system versions. Content from personal books is not sent. Recognized email addresses and file paths are masked in search text, but other personal details may still be sent. Do not include personal details in search text. You can revoke consent at any time in settings; revoking it disables this search mode.\n\nConfirming enables consent in Otzaria settings. From then on, the app collects the data onto the drive and sends it to Otzaria whenever there is an internet connection, automatically and without notifications. The data, including search terms, is stored on the drive unencrypted until it is sent, together with the anonymous key that signs it.';
  @override
  String get semanticAskTitle => 'Smart search on this computer';
  @override
  String get semanticAskIntro =>
      'The drive also carries smart search: search by meaning, which finds '
      'sources even when the words differ from what you searched for. You can '
      'install it now, together with the update.';
  @override
  String get semanticAskLater =>
      'You will not be asked again on this computer. You can enable it later '
      'in the settings of this tool; revoking is done in Otzaria settings.';
  @override
  String get semanticConsentNotSaved =>
      "Couldn't save the consent in Otzaria settings, so smart search was not "
      'installed. You can try again.';
  @override
  String get semanticConsentBlocked =>
      "Otzaria's server has blocked training data from this computer, so smart "
      'search cannot be enabled here.';
  @override
  String get semanticAskApprove => 'Agree and install smart search';
  @override
  String get semanticAskDecline => 'Continue without smart search';
  @override
  String get semanticConsentConfirm => 'I agree';
  @override
  String get semanticFeedbackFailed =>
      'Training data transfer did not finish. You can try again; details were saved to the log.';
  @override
  String get semanticConsentRequired =>
      'Smart search files are on the drive. Installing them requires consent to collect training data. You can agree here while Otzaria is closed, or enable consent in Otzaria settings and check again.';
  @override
  String get semanticFullDownloadNeeded =>
      'Smart search on this computer is not at the version the partial update on the drive continues from, so it was not installed. The next download on the online computer will bring the full smart search package.';
  @override
  String get semanticBuiltForOlderOtzaria =>
      'The smart search published for this library version was built for an older Otzaria, and this tool cannot install it. It will be downloaded with a newer library, once the drive has an Otzaria version that reads it.';
  @override
  String get semanticNeedsNewerLauncher =>
      'The smart search published for this library version needs a newer version of this tool. Update Otzaria Updates and try again.';
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
  String companionAssetHttpFailure(String name, int status) =>
      'No file for $name was found in the latest release (HTTP $status)';
  @override
  String companionExtractionFailed(String name) => 'Extracting $name failed';
  @override
  String get companionsMirrorMissing =>
      'The companion files have not been downloaded to the local folder yet';
  @override
  String companionStillPendingAfterInstall(String name) =>
      'Installing $name finished, but the item is still marked as out of date';
  @override
  String companionsInstallFailed(String names) =>
      'The database was updated, but installing the companion files ($names) '
      'failed — so the Otzaria library update will keep being offered.';
  @override
  String libraryLocationNeedsManualSetting(String dbPath) =>
      'The Otzaria library was installed in $dbPath, but Otzaria\'s settings could '
      'not be updated. Open Otzaria and point it at this folder in the '
      'library location screen.';
  @override
  String companionsMissingFromMirror(String names) =>
      'Missing on the drive: $names. The download was probably interrupted. '
      'To get it, download again on a computer with internet. The rest of '
      'the update will install as usual.';
  @override
  String get companionsAbsentFromMirror =>
      'The drive does not have the Talmud Bavli, the catalog and the '
      'dictionary, so they will not be installed. To get them, download '
      'again on a computer with internet.';

  @override
  String applyDownloadingPatch(String step) => 'Downloading the update$step…';
  @override
  String applyApplyingPatch(String step) =>
      'Updating the Otzaria library$step…';
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
  String get applyDownloadingFullDb => 'Downloading the full Otzaria library…';
  @override
  String get applyDecompressingFullDb => 'Extracting the Otzaria library…';
  @override
  String get applyDecompressingAndVerifyingFullDb =>
      'Extracting the database and verifying its checksum…';
  @override
  String get applyWritingFullDb => 'Writing the Otzaria library…';
  @override
  String get applyVerifying => 'Verifying…';
  @override
  String applyVerifyStage(String stage) {
    switch (stage) {
      case 'sourceHash':
        return 'Verifying the database file checksum…';
      case 'dbIntegrity':
        return 'Checking the extracted database (full scan, may take minutes)…';
      case 'dbVersion':
        return 'Verifying the extracted database version…';
      default:
        return applyVerifying;
    }
  }

  @override
  String applyStageElapsed(String stage, String elapsed) => '$stage — $elapsed';
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
  String get downloadCancelled => 'The download was cancelled.';
  @override
  String get installCancelledByUser =>
      'The installation was cancelled in the installer.';
  @override
  String get wizardStillOpen =>
      'The Otzaria installer was opened. When you finish it, press "Check '
      'again" so the program detects the installation.';
  @override
  String get wizardEndedWithoutInstall =>
      'The installer closed, but the new version was not found on this '
      'computer. If you installed it into another folder, choose it with '
      '"Choose location manually"; otherwise install again.';
  @override
  String get setupContinuesElsewhere =>
      'The installer is updating Otzaria in its own window — waiting for it '
      'to finish…';

  @override
  String get noInstallableReleaseForPlatform =>
      'No Otzaria version that can be installed on this platform was found.';
  @override
  String get mirrorEmptyRunDownload =>
      'There is no Otzaria version on the drive. Download updates to the drive on a computer with internet, from the home page.';
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
  String get installerDigestMismatch =>
      'The Otzaria installer in the folder is damaged — it does not match '
      'the checksum GitHub publishes for it. Download it again on a computer '
      'with internet.';
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
  String get macCloseOtzariaBeforeInstall =>
      'Otzaria is currently open. On macOS the install replaces the whole '
      'application bundle, so a running Otzaria would be left without its own '
      'files and crash — please close it and try again.';
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
  String installNotDetectedAnywhere(int timeoutSeconds) =>
      'The installation finished, but Otzaria was not found on this computer '
      'within $timeoutSeconds seconds — neither in the list of installed '
      'programs nor in the known locations. If it was installed after all, '
      'choose its folder manually on the "Otzaria — advanced" page.';
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
  String githubRateLimited(int? retryAfterMinutes) {
    final retry = switch (retryAfterMinutes) {
      null => 'Try again later.',
      1 => 'Try again in about 1 minute.',
      final minutes => 'Try again in about $minutes minutes.',
    };
    return 'GitHub has temporarily limited requests from this network. $retry';
  }

  @override
  String networkBlockedByFilter(int statusCode, String host) =>
      'Access to $host was blocked (status $statusCode). An internet filter '
      '(such as NetFree) is probably blocking the address — ask for it to be '
      'opened, or download from another computer.';
  @override
  String networkCertificateRejected(String host) =>
      'The secure connection to $host failed: the security certificate it '
      'presented is not trusted. If this computer goes through a filter such '
      'as NetFree, install the filter\'s certificate, or download from '
      'another computer.';

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
  String get noCompatibleBuild =>
      'This plugin has no build that runs on the Otzaria version on this machine.';
  @override
  String get localPluginFileMissing =>
      'The local plugin file is missing. Please sync again.';
  @override
  String get localPluginFileCorrupt =>
      'The plugin file on the drive is damaged or is not the selected version. Download the store again on the online computer.';
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
      'Updating: $name ($done/$total)';
  @override
  String syncDoneCounts(int fetched, int skipped) =>
      'Sync complete: $fetched plugins updated, $skipped already up to date';
  @override
  String get syncCategories => 'Updating the store categories…';
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
  String get downloadedFileNotPlugin =>
      'the downloaded file is not a valid plugin';
  @override
  String get downloadedFileNotImage =>
      'the downloaded file is not an image (it may be a filter block page)';
  @override
  String get downloadedFileHashMismatch =>
      'the downloaded file does not match the checksum the site published';
  @override
  String get downloadedFileWrongBuild =>
      'the downloaded file is not the selected version of the plugin';
  @override
  String get siteClosedForShabbat =>
      'The Otzaria site is closed on Shabbat and Yom Tov. The store already on the drive keeps working; updates can be downloaded after Shabbat ends.';

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

  @override
  String get exportPreparing => 'Preparing the copy…';
  @override
  String get exportAppMissing =>
      'The store program is not on this drive. Download updates to the drive on a computer with internet, from the home page.';
  @override
  String get exportCopyingApp => 'Copying the store program…';
  @override
  String exportAppCopyFailed(String error) =>
      'The program file could not be written to the destination: $error. '
      'Antivirus software may be blocking it, or the chosen folder may not '
      'be writable.';
  @override
  String exportAppVanished(String path) =>
      'The store program file has disappeared from $path. This is almost '
      'always antivirus software deleting an unsigned executable (in Windows '
      'Defender: Windows Security → Virus protection → Protection history, '
      'then "Allow on device").';
  @override
  String get exportAppRemovedFromMirror =>
      'The store program was downloaded to the drive and is no longer there. '
      'Downloading again will not help — antivirus software is most likely '
      'deleting it; allow it there first, then download again.';
  @override
  String get exportAppDamaged =>
      'The store program on the drive is damaged — it does not match the '
      'checksum GitHub publishes for it. Download it again on a computer with '
      'internet.';
  @override
  String exportPlugin(String name, int done, int total) =>
      'Copying $name ($done/$total)';
  @override
  String get exportWritingCatalog => 'Writing the catalog…';
  @override
  String exportDone(int plugins) => '$plugins plugins copied';
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
  String installerUnsupportedFile(String fileName) =>
      'The file "$fileName" is not a supported installation package. Choose a Windows EXE or MSI installer, or a ZIP archive to copy. A source archive does not install the program. You can replace the file by editing the program.';
  @override
  String installerExitCode(int exitCode, String output) =>
      'The installation failed (exit code $exitCode).\n$output';
  @override
  String installerElevatedRetryFailed(
    int firstExitCode,
    int elevatedExitCode,
    String output,
  ) =>
      'The installation failed (exit code $firstExitCode), and the retry '
      'with administrator rights failed too (exit code $elevatedExitCode).'
      '\n$output';
  @override
  String installerElevatedRetryDeclined(int firstExitCode) =>
      'The installation failed (exit code $firstExitCode). It was not '
      'retried with administrator rights: the Windows permission prompt was '
      'declined, or access was denied.';
  @override
  String get installerCancelled =>
      'The installation was cancelled in the installer. The program was not '
      'installed.';
  @override
  String get installerElevationDeclined =>
      'The installer requires administrator rights, and the request was '
      'declined or access was denied. To install, approve the Windows '
      'permission prompt.';
  @override
  String get installerDigestMismatch =>
      'The installer on the drive is damaged — it does not match the file '
      'that was stored. Download or add it again on a computer with internet';
  @override
  String get installerUnverified =>
      'The installer has no stored fingerprint, so there is no way to tell '
      'whether it was changed. Approve it before installing';
  @override
  String get appNotTrustedHere =>
      'This program was added on another computer. Approve it on this '
      'computer before installing';
  @override
  String get appNotTrustedForLaunch =>
      'This program\'s record was added or changed on another computer. '
      'Approve it on this computer before running it';
  @override
  String fileCopyFailed(String error) => 'Copying the file failed: $error';
  @override
  String portableFileInUse(String fileName, String error) =>
      'Could not replace $fileName, probably because the program is open. '
      'Close it and try again.${error.isEmpty ? '' : '\n$error'}';
  @override
  String launchFileMissing(String launchPath) =>
      'Executable not found: $launchPath';
  @override
  String get launchElevationDeclined =>
      'The program requires administrator rights, and the request was '
      'declined or access was denied.';

  @override
  String mediaFileMissing(String path) => 'Image file not found: $path';
  @override
  String mediaNotAnImage(String fileName) =>
      '$fileName is not an image file. Pick a PNG, JPG, GIF, WEBP or BMP.';

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
  String downloadDigestMismatch(String fileName) =>
      'The downloaded $fileName does not match the checksum GitHub publishes '
      'for it — the download was corrupted. Please try again';
  @override
  String get sourceIsNotGithub =>
      'This program has no repository set — there is nothing to check online';
}

class _CustomApps extends CustomAppsStrings {
  const _CustomApps();

  @override
  String get screenTitle => 'Other programs';

  // ── The card grid and the category rail ──
  @override
  String get categoriesTitle => 'Categories';
  @override
  String get allAppsItem => 'All programs';
  @override
  String get uncategorizedItem => 'Uncategorized';

  // ── The program page ──
  @override
  String get aboutPanelTitle => 'About';
  @override
  String get infoPanelTitle => 'General information';
  @override
  String get screenshotsPanelTitle => 'Screenshots';
  @override
  String get infoSource => 'Source';
  @override
  String get infoSourceFile => 'Manually picked file';
  @override
  String get infoInstalled => 'Installed on this computer';
  @override
  String get infoStored => 'On the drive';
  @override
  String get infoOnline => 'Online';
  @override
  String get infoStoredSize => 'Stored file size';
  @override
  String get infoStoredAdded => 'Added to the drive';
  @override
  String get valueUnknown => 'Unknown';
  @override
  String get valueNo => 'No';
  @override
  String get installedNoVersionValue => 'Yes, version unknown';
  @override
  String get notStoredValue => 'Not downloaded yet';

  // ── Empty states ──
  @override
  String get emptyCategoryTitle => 'No programs here yet';
  @override
  String get emptyCategoryBody =>
      'You can assign programs to this category when editing them, in program management under Settings.';
  @override
  String get emptyUncategorizedTitle => 'Every program is assigned';
  @override
  String get emptyUncategorizedBody => 'No program is left outside a category.';
  @override
  String categoryAppCount(int count) =>
      count == 1 ? '$count program' : '$count programs';

  // ── Managing categories ──
  @override
  String get categoriesDialogHint =>
      'Categories travel on the drive with the programs and appear as chips above the list.';
  @override
  String get categoryNameLabel => 'Category name';
  @override
  String get categoryNameHint => 'For example: study tools';
  @override
  String get categoryDescriptionLabel => 'Description (optional)';
  @override
  String get addCategoryButton => 'Add category';
  @override
  String get editCategoryTitle => 'Edit category';
  @override
  String get noCategoriesHint =>
      'No categories yet. Without them the screen shows every program '
      'together.';
  @override
  String get removeCategoryTooltip => 'Delete category';
  @override
  String removeCategoryDialogTitle(String name) => 'Delete "$name"?';
  @override
  String removeCategoryDialogContent(String name, int count) =>
      'The category "$name" will be deleted. $count programs will go back to '
      '"Uncategorized" — no program is removed and no file is deleted from '
      'the drive.';
  @override
  String categoryRemovedSnack(String name) =>
      'The category "$name" was deleted';

  // ── Media and categories in the form ──
  @override
  String get appCategoriesLabel => 'Categories';
  @override
  String get appCategoriesHint =>
      'A program can belong to several categories, or to none.';
  @override
  String get longDescriptionLabel => 'Full description (optional)';
  @override
  String get longDescriptionHint =>
      'What the program does, who it is for, and anything worth knowing. '
      'Shown on the program page.';
  @override
  String get iconLabel => 'Icon';
  @override
  String get pickIconButton => 'Choose image';
  @override
  String get pickIconDialogTitle => 'Pick an icon image';
  @override
  String get removeIconTooltip => 'Remove the icon';
  @override
  String get extractIconButton => 'Extract from file';
  @override
  String extractedIconSnack(String fileName) =>
      'The icon was extracted from $fileName';
  @override
  String get extractIconFailedSnack =>
      'No icon was found in the file. You can pick an image manually.';
  @override
  String get moveScreenshotBackTooltip => 'Move back';
  @override
  String get moveScreenshotForwardTooltip => 'Move forward';
  @override
  String get screenshotsLabel => 'Screenshots';
  @override
  String get addScreenshotsButton => 'Add screenshots';
  @override
  String get pickScreenshotsDialogTitle => 'Pick screenshots';
  @override
  String get removeScreenshotTooltip => 'Remove the image';
  @override
  String screenshotsChosen(int count) =>
      count == 1 ? '$count image' : '$count images';

  @override
  String get settingsCardTitle => 'Other programs';
  @override
  String get manageRowTitle => 'Manage';
  @override
  String manageRowSubtitle(int count) =>
      '${count == 1 ? '$count program' : '$count programs'} on the drive · add, edit, order and categories';
  @override
  String get emptyHint => 'No programs yet · add, edit, order and categories';
  @override
  String get addButton => 'Add a program';
  @override
  String get openManagerButton => 'Manage programs';

  // ── The management window ──
  @override
  String get manageDialogTitle => 'Manage other programs';
  @override
  String get manageDialogHint =>
      'The programs kept on the drive, their order and categories.';
  @override
  String get orderHint =>
      'Drag a row by its handle onto another, or use the arrows. This is the order the programs are shown in, and it travels on the drive.';
  @override
  String get moveAppEarlierTooltip => 'Move earlier';
  @override
  String get moveAppLaterTooltip => 'Move later';
  @override
  String get dragToReorderTooltip => 'Drag to reorder';

  @override
  String get addDialogTitle => 'Add a program';
  @override
  String get editDialogTitle => 'Edit program';
  @override
  String get nameLabel => 'Program name';
  @override
  String get nameHint => 'As it will appear in your list';
  @override
  String get descriptionLabel => 'Short description';
  @override
  String get descriptionHint => 'A short line to remind you what this is';
  @override
  String get installDirLabel => 'Installation folder';
  @override
  String get installDirHint =>
      'Can be left empty — the location is found by itself after the first '
      'install.';
  @override
  String get pickInstallDirButton => 'Choose…';
  @override
  String get pickInstallDirDialogTitle => 'Choose the install folder';

  @override
  String get githubUrlLabel => 'Program address on the developer site';
  @override
  String get githubUrlHint => 'For example github.com/owner/repo';
  @override
  String get githubUrlInvalid =>
      'That is not the address of a program on the developers\' site (GitHub)';
  @override
  String get fetchAssetsButton => 'Show the files';
  @override
  String get assetHint =>
      'A release usually holds several files. Pick the one that fits your '
      'computer.';
  @override
  String get noAssetsFound => 'This release has no files to download';
  @override
  String assetsFromRelease(String tagName) => 'Files in release $tagName:';

  @override
  String get pickInstallerButton => 'Choose…';
  @override
  String get pickInstallerDialogTitle => 'Choose the installer file';
  @override
  String installerKindSniffed(String kind) => 'Detected: $kind';
  @override
  String get portableFileLabel => 'The file is the program itself';
  @override
  String get interactiveInstallLabel => 'Use the installation wizard';
  @override
  String get interactiveInstallHint =>
      'For programs that do not support silent installation. Choose the installation folder and complete the steps in the installer window.';
  @override
  String get portableFileHint =>
      'Tick this when the file is not an installer but the program itself. '
      'On install you will be asked where to copy it, instead of running it.';
  @override
  String get portableDestinationHint =>
      'Where to keep the program on each computer — you will be asked to choose a folder during installation.';
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
  String get saveButton => 'Add to the drive';
  @override
  String get saveEditButton => 'Save';
  @override
  String get nameRequired => 'A program name is required';
  @override
  String get sourceRequired =>
      'Choose a file, or an address and a file from it';
  @override
  String addedSnack(String name) => '$name was added';
  @override
  String updatedSnack(String name) => '$name was updated';

  @override
  String get kindInno => 'A regular installer';
  @override
  String get kindNsis => 'A regular installer';
  @override
  String get kindMsi => 'A regular installer';
  @override
  String get kindZip => 'Archive';
  @override
  String get kindPortableFile => 'The file itself, no installation';
  @override
  String get kindInteractive =>
      'Unrecognised installer — a normal install window will open';

  @override
  String get noStoredInstaller => 'No installer downloaded yet';

  @override
  String get downloadButton => 'Download to drive';
  @override
  String get downloadingLabel => 'Downloading…';
  @override
  String get checkOnlineButton => 'Check online';
  @override
  String get checkAllOnlineButton => 'Check all programs online';
  @override
  String checkingAllOnlineLabel(int done, int total) =>
      'Checking online… ($done/$total)';
  @override
  String checkAllOnlineSummary(int updates, int checked) =>
      '$checked programs checked — $updates have a newer version online';
  @override
  String checkAllOnlineNoUpdates(int checked) =>
      '$checked programs checked — what is on the drive is up to date';
  @override
  String get checkAllOnlineAllFailed =>
      'No program could be checked — there is probably no internet connection';
  @override
  String checkAllOnlineSomeFailed(int failed) =>
      '$failed programs could not be checked.';
  @override
  String get downloadAllButton => 'Download all updates';
  @override
  String downloadingAllLabel(int done, int total) =>
      'Downloading updates… ($done/$total)';
  @override
  String downloadAllDoneSnack(int downloaded) =>
      'Updates for $downloaded programs were downloaded to the drive';
  @override
  String downloadAllNothingNew(int checked) =>
      '$checked programs checked — nothing to download, what is on the drive '
      'is up to date';
  @override
  String downloadAllSomeFailed(int failed) =>
      '$failed programs could not be downloaded.';
  @override
  String onlineVersionAvailable(String version) =>
      'Version $version is available online';
  @override
  String get onlineUpToDate => 'What is on the drive is the latest version';
  @override
  String get onlineUnavailable => 'No internet connection right now';
  @override
  String get pickLocationButton => 'Choose location manually';
  @override
  String locationAdoptedSnack(String dir) => 'The program was found in $dir';
  @override
  String get locationNotFoundSnack =>
      'No installation was found there. Check that you picked the right '
      'folder.';

  @override
  String installedSnack(String name) => '$name was installed';
  @override
  String get trustDialogTitle => 'Install a program that was not checked?';
  @override
  String trustDialogContent(String name, String source) =>
      '"$name" was added to the drive on another computer and has not been approved on this one. '
      'Install it only if you trust whoever added it${source == name ? '' : ' ($source)'}.';
  @override
  String get trustDialogConfirm => 'Install anyway';
  @override
  String get unverifiedDialogTitle => 'Install a file that was not checked?';
  @override
  String unverifiedDialogContent(String fileName) =>
      'No identifying mark was saved for $fileName, so there is no way to make sure it was not changed. '
      'If you continue, the mark is computed and saved, and any later change to the file is blocked.';
  @override
  String get unverifiedDialogConfirm => 'Install anyway';
  @override
  String get learningLabel => 'Identifying the installation…';
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
  String get removeTooltip => 'Remove from the drive';
  @override
  String removeDialogTitle(String name) => 'Remove "$name" from the drive?';
  @override
  String removeDialogContent(String name) =>
      '"$name" will be removed from the list and its file deleted from the drive. '
      'It will not be uninstalled from computers that already installed it.';
  @override
  String get removeDialogConfirm => 'Remove';
  @override
  String removedSnack(String name) => '$name was removed';

  @override
  String get screenSubtitle =>
      'Programs saved on the drive so you can install them on computers without internet.';
  @override
  String get showAllAppsButton => 'Show all programs';
  @override
  String get sourceGithubShort => 'From the developer site (GitHub)';
  @override
  String get sourceFileShort => 'From a file';
  @override
  String versionLabel(String version) => 'Version $version';
  @override
  String updateToButton(String version) => 'Update to $version';
  @override
  String get onlineNotChecked => 'Not checked yet';
  @override
  String get emptyReadOnlyBody =>
      'This drive is write-protected, so programs cannot be added to it.';
  @override
  String get manageEmptyTitle => 'No programs added yet';
  @override
  String get manageEmptyBody =>
      'You can keep a program on the drive to install on computers without internet — from a file on this computer, or from the developer site (GitHub) so it updates by itself.';
  @override
  String get noCategoriesTitle => 'No categories';
  @override
  String get orderSectionTitle => 'Programs in the order they are shown';
  @override
  String get formStepSource => 'Where is the program from?';
  @override
  String get formStepGithubFile => 'Which file?';
  @override
  String get formStepLocalFile => 'Choose the file';
  @override
  String get formStepDetails => 'Program details';
  @override
  String get sourceGithubOption =>
      'From the developer site — GitHub (recommended)';
  @override
  String get sourceGithubOptionHint =>
      'The program updates by itself with every download to the drive.';
  @override
  String get sourceFileOption => 'A file on this computer';
  @override
  String get sourceFileOptionHint =>
      'An installer, or a program that needs no installation.';
  @override
  String get fileLabel => 'The file';
}

String _reports(int count) => count == 1 ? 'report' : 'reports';

class _ErrorReports extends ErrorReportsStrings {
  const _ErrorReports();

  @override
  String get collectDialogTitle => 'Unsent reports';
  @override
  String collectDialogContent(int count) =>
      'Otzaria has $count ${_reports(count)} about books, the app and plugins '
      'that have not been '
      'sent yet.\n\nCollect them to the drive, so they can be sent to Otzaria '
      'from the computer that is online?\n\n'
      'Note: the reports are stored on the drive as they are, unencrypted, '
      'until they are sent — your email address, the text you wrote, log '
      'excerpts, screenshots and, for a crash report you approved, a memory '
      'dump. Anyone holding the drive can read them.';
  @override
  String get collectConfirm => 'Collect';
  @override
  String get collectLater => 'Not now';
  @override
  String collectedSnack(int count) =>
      '$count ${_reports(count)} collected to the drive. They will be sent '
      'from the computer that is online';
  @override
  String collectPartialSnack(int count, String error) =>
      '$count ${_reports(count)} collected, but not all of them: $error';
  @override
  String collectFailedSnack(String error) =>
      'Collecting the reports failed: $error';
  @override
  String get collectDisclosureRefreshedSnack =>
      'More data to collect was found — review the details above the button and click again.';
  @override
  String get collectOtzariaOpenSnack =>
      'Otzaria is open, so the reports were not collected. You will be asked '
      'again once Otzaria is closed';
  @override
  String get legacyReportsDialogTitle =>
      'Old reports found that cannot be sent';
  @override
  String get legacyReportsDialogContent =>
      'An old version of Otzaria saved them in a form that is no longer sent. '
      'All other reports are sent as usual.';

  @override
  String get introDialogTitle => 'Reports to Otzaria and plugin developers';
  @override
  String get introDialogContent =>
      'Otzaria keeps reports about books, app problems and plugins while there '
      'was no network.\n\nThe program can collect them to the drive, and '
      'send them to Otzaria from the computer that is online.';
  @override
  String get introDialogContentReadOnly =>
      'Otzaria keeps reports about books, app problems and plugins while there '
      'was no network.\n\nThis drive is locked for writing, so reports '
      'cannot be collected through it.';
  @override
  String get introDialogContentReadOnlyDriveFull =>
      'Otzaria keeps reports about books, app problems and plugins while there '
      'was no network.\n\nThis drive is full, so reports cannot be collected '
      'to it until space is freed on it.';
  @override
  String get introDialogConfirm => 'Got it';

  @override
  String get uploadLongDialogTitle => 'Uploading reports';
  @override
  String uploadLongDialogContent(int count, int perMinute, int minutes) =>
      'The drive holds $count ${_reports(count)}. The Otzaria server accepts '
      'up to $perMinute reports a minute, so the upload will take about '
      '$minutes minutes.\n\nYou can stop in the middle; next time the upload '
      'continues from where it stopped.';
  @override
  String get uploadLongDialogConfirm => 'Start';
  @override
  String uploadingStage(int done, int total) =>
      'Sending reports · $done of $total';
  @override
  String uploadWaitingStage(int seconds) =>
      'Waiting for the server — continuing in $seconds seconds';
  @override
  String get uploadStopButton => 'Stop';
  @override
  String uploadPendingOffline(int count) =>
      '$count ${_reports(count)} waiting to be uploaded. There is no network connection, so there is no upload button';
  @override
  String uploadPendingUnchecked(int count) =>
      '$count ${_reports(count)} waiting to be uploaded. The network connection has not been checked yet — check the connection to upload';
  @override
  String get uploadingFeedbackStage =>
      'Sending the smart search improvement data…';
  @override
  String get uploadCollectingBusy =>
      'Reports are being collected right now. Try again in a moment';
  @override
  String get uploadUnexpectedFailure =>
      'The upload failed. Details are in the activity log';
  @override
  String uploadSummary(int sent, int rejected, int remaining) => [
        '$sent ${_reports(sent)} sent',
        if (rejected > 0) '$rejected rejected by the server and deleted',
        if (remaining > 0) '$remaining left for next time',
      ].join(', ');
  @override
  String uploadFailedSnack(String error) => 'The upload stopped: $error';
}

class _ErrorReportsDomain extends ErrorReportsDomainStrings {
  const _ErrorReportsDomain();

  @override
  String get queueUnreadable => 'Could not read the Otzaria report queue';
  @override
  String get someNotCollected =>
      'The reports that were not collected stayed in Otzaria';

  @override
  String uploadHttpStatus(int statusCode) =>
      'The server answered with code $statusCode';
  @override
  String get uploadShabbat =>
      'The Otzaria site is closed on Shabbat and Yom Tov. The reports stay on the drive and will be sent next time, after Shabbat ends.';
  @override
  String get uploadTimedOut => 'The server did not respond in time';
  @override
  String uploadNetworkError(String error) => 'Cannot reach the server: $error';
  @override
  String outboxUnreadable(String error) =>
      'Cannot read the reports on the drive: $error';
}

class _AppReports extends AppReportsStrings {
  const _AppReports();

  @override
  String get crashModeTitle => 'After the tool closes unexpectedly';
  @override
  String get crashModeSubtitle =>
      'A short report to the developers: version and system details, an '
      'excerpt of the activity log and the email you saved in the report '
      'form, if any. Paths and the user name are hidden.';
  @override
  String get crashModeAsk => 'Ask';
  @override
  String get crashModeAlways => 'Always send';
  @override
  String get crashModeNever => 'Do not send';
  @override
  String get manageTileTitle => 'Problem reports';
  @override
  String manageTileSubtitle(int pending, int sent) => pending == 0
      ? 'No reports waiting · $sent sent'
      : '$pending waiting · $sent sent';

  @override
  String get manageDialogIntro =>
      'Reports about this tool itself. The description is published on the '
      "developers' site where anyone can read it; diagnostic files are "
      'visible to the developers only.';
  @override
  String get sendNowButton => 'Send now';
  @override
  String get clearPendingButton => 'Delete all';
  @override
  String get sendOneButton => 'Send';
  @override
  String get deleteButton => 'Delete';
  @override
  String get detailsButton => 'Details';
  @override
  String get sentSectionTitle => 'Sent reports';
  @override
  String sentSummary(int shown, int total) =>
      shown == total ? '$total sent' : '$total sent; showing the latest $shown';
  @override
  String get clearSentButton => 'Clear history';
  @override
  String openIssueButton(int? number) =>
      number == null ? 'Open the report' : 'Open report #$number';
  @override
  String get mergedLabel => 'Added to an existing report';
  @override
  String get detailsPendingTitle => 'Waiting report';
  @override
  String get detailsSentTitle => 'Sent report';
  @override
  String get stepsHeading => 'Steps to reproduce:';
  @override
  String get clearPendingDialogTitle => 'Delete the waiting reports?';
  @override
  String get clearPendingDialogContent =>
      'The waiting reports will not be sent. This cannot be undone.';
  @override
  String get clearSentDialogTitle => 'Clear the report history?';
  @override
  String get clearSentDialogContent =>
      'This does not delete reports that were already sent to the developers.';
  @override
  String flushSentSnack(int count) =>
      count == 1 ? '1 report sent' : '$count reports sent';
  @override
  String flushFailedSnack(int pending) => pending == 1
      ? 'Cannot send right now. 1 report is still waiting and will be '
          'sent automatically once there is a connection.'
      : 'Cannot send right now. $pending reports are still waiting and '
          'will be sent automatically once there is a connection.';
  @override
  String flushErrorSnack(int failed) =>
      'Sending failed because of an error on this computer ($failed). The '
      'reports stay queued; details are in the log.';
  @override
  String flushPartialSnack(int sent, int failed) =>
      '${sent == 1 ? '1 report was' : '$sent reports were'} sent. '
      '${failed == 1 ? '1 report was' : '$failed reports were'} not sent '
      'because of an error on this computer and stayed queued; see the log.';
  @override
  String flushDroppedSnack(int sent, int dropped) =>
      '${sent == 1 ? '1 report was' : '$sent reports were'} sent, and '
      '${dropped == 1 ? '1 was' : '$dropped were'} rejected by the server '
      'and removed from the queue.';
  @override
  String flushRemainingSnack(int sent, int remaining) =>
      '${sent == 1 ? '1 report was' : '$sent reports were'} sent. '
      '${remaining == 1 ? '1 more is' : '$remaining more are'} still queued — '
      'they will be sent automatically, or press again.';
  @override
  String get notPendingSnack =>
      'The report is no longer queued (it was sent or removed), so it was '
      'not sent again.';
  @override
  String get removedFromQueueSnack => 'The report was removed from the queue';
  @override
  String get deletedFromHistorySnack => 'The report was deleted from history';
  @override
  String get pendingClearedSnack => 'The waiting reports were deleted';
  @override
  String get historyClearedSnack => 'History cleared';

  @override
  String get typeBug => 'Bug';
  @override
  String get typeCrash => 'Crash';
  @override
  String get typePerformance => 'Performance';
  @override
  String get typeSuggestion => 'Suggestion';

  @override
  String get dialogTitle => 'Report a problem';
  @override
  String get dialogSubtitle =>
      'The more precise the description, the easier it is to find and fix';
  @override
  String get typeLabel => 'Report type';
  @override
  String get titleLabel => 'Title';
  @override
  String get titleHint => 'One sentence describing the problem';
  @override
  String get titleRequired => 'A title is required';
  @override
  String get descriptionLabel => 'What happened?';
  @override
  String get descriptionHint => 'What you expected, and what happened instead';
  @override
  String get descriptionRequired => 'Please describe the problem';
  @override
  String get stepsLabel => 'Steps to reproduce';
  @override
  String get stepsHint => 'What you did before the problem appeared';
  @override
  String get optionalHint => '(optional)';
  @override
  String get emailLabel => 'Email, so we can get back to you';
  @override
  String get emailInvalid => 'A valid address is required';
  @override
  String get sendButton => 'Send';

  @override
  String get imagesPrompt => 'Click to choose a screenshot';
  @override
  String get imagesPickDialogTitle => 'Choose screenshots for the report';
  @override
  String get removeImageTooltip => 'Remove image';
  @override
  String imageTooLarge(int megabytes) =>
      'An image larger than $megabytes MB was not attached.';
  @override
  String tooManyImages(int count) =>
      'Up to $count images can be attached to a report.';
  @override
  String imagesTotalTooLarge(int megabytes) =>
      'The images are limited to $megabytes MB in total.';
  @override
  String get imageReadFailed => 'The image could not be read.';

  @override
  String get attachmentsHeading => 'What is sent with the report';
  @override
  String get includeDiagnostics =>
      'Attach diagnostic information about the app and the system';
  @override
  String get diagnosticsUnavailable =>
      'Diagnostic information could not be collected';
  @override
  String get includeLog => 'Attach an excerpt of the activity log';
  @override
  String get logEmpty => 'The activity log has no entries';
  @override
  String get showPreviewButton => 'Show what will be sent';
  @override
  String get hidePreviewButton => 'Hide what will be sent';
  @override
  String get privacyNote =>
      'The title, description, version details and screenshots go into the '
      "app's issue tracker on GitHub. Diagnostics, the activity log and your "
      'email stay with the Otzaria team only. Paths, the user name and email '
      'addresses are masked before sending.';

  @override
  String sentSnack(int? issueNumber) => issueNumber == null
      ? 'The report was received. Thank you!'
      : 'The report was received as issue $issueNumber. Thank you!';
  @override
  String mergedSnack(int? issueNumber) => issueNumber == null
      ? 'The report was added to an existing report of the same problem. '
          'Thank you!'
      : 'The report was added to existing issue $issueNumber about the same '
          'problem. Thank you!';
  @override
  String get queuedSnack =>
      'Cannot send right now. The report was saved and will be sent '
      'automatically once there is a connection. Manage saved reports in '
      'Settings.';
  @override
  String rejectedSnack(String? field) => field == null
      ? 'The server rejected the report, so it was not kept for another try.'
      : 'The server rejected the report because of the field "$field", so it '
          'was not kept for another try.';
  @override
  String get titleRequiredSnack => 'Please fill in a title for the report.';
  @override
  String get descriptionRequiredSnack =>
      'Please describe the problem so we can handle it.';
  @override
  String get emailRequiredSnack =>
      'Please enter a valid email address — without it we cannot get back '
      'to you.';
  @override
  String get invalidEmailSnack => 'The email address is not valid.';
  @override
  String get cannotOpenIssueSnack => 'Cannot open the issue in the browser.';
  @override
  String get sendFailedSnack => 'Sending the report failed.';

  @override
  String get crashTitle => 'The app closed unexpectedly';
  @override
  String get crashBody =>
      'Last time the app did not close properly. Sending a report helps us '
      'find the cause and fix it.';
  @override
  String get crashDescriptionLabel =>
      'What were you doing before it closed? (optional)';
  @override
  String get crashEmailLabel => 'Email (optional)';
  @override
  String get crashNextTimeLabel => 'Next time this happens:';
  @override
  String get crashNextAsk => 'Ask me';
  @override
  String get crashNextAlways => 'Always send automatically';
  @override
  String get crashNextNever => "Don't ask again";
  @override
  String get crashDismissButton => "Don't send";
  @override
  String get crashSendButton => 'Send report';
  @override
  String get crashDismissedSnack =>
      'The crash report was not sent. You can report at any time from '
      'Settings.';
  @override
  String get crashFallbackTitle => 'Unexpected exit';
  @override
  String get crashAutoSentSnack =>
      'The tool closed unexpectedly last time. A short report was sent to the '
      'developers, or will be once there is a connection. You can change this '
      'in the settings.';
}

/// "about 3 to 5 minutes"; a collapsed range — "about 2 minutes".
String _minutesRange(int low, int high) => low == high
    ? plural(low, one: 'about a minute', many: 'about $low minutes')
    : 'about $low to $high minutes';
