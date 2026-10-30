import 'package:flutter/foundation.dart';

import 'shell_navigator.dart';

/// מפתחות קבועים לבדיקות ולצילומי הסקירה: מוצאים בהם חלק בדף בלי לתלות
/// את הבדיקה בנוסח.
abstract final class ShellKeys {
  static const hero = ValueKey('home.hero');
  static const heroPrimary = ValueKey('home.hero.primary');
  static const heroSecondary = ValueKey('home.hero.secondary');
  static const heroLaunch = ValueKey('home.hero.launch');
  static const heroSemanticOffer = ValueKey('home.hero.semanticOffer');
  static const heroFailedDownloads = ValueKey('home.hero.failedDownloads');
  static const heroFoundNothing = ValueKey('home.hero.foundNothing');
  static const eyebrow = ValueKey('home.eyebrow');
  static const heroChecking = ValueKey('home.hero.checking');
  static const heroItems = ValueKey('home.hero.items');
  static const heroTotal = ValueKey('home.hero.total');
  static const heroWhatsNew = ValueKey('home.hero.whatsNew');
  static const heroStopWaiting = ValueKey('home.hero.stopWaiting');
  static const heroAppError = ValueKey('home.hero.appError');
  static const heroAppErrorNote = ValueKey('home.hero.appErrorNote');
  static const heroAppAdvanced = ValueKey('home.hero.appAdvanced');
  static const semanticConsentWhatIsSent =
      ValueKey('home.notice.semanticConsent.whatIsSent');

  static const readOnlyNotice = ValueKey('home.notice.readOnly');
  static const driveFullNotice = ValueKey('home.notice.driveFull');
  static const reportsIntroNotice = ValueKey('home.notice.reportsIntro');
  static const searchFeedbackCollectedNotice =
      ValueKey('home.notice.searchFeedbackCollected');
  static const legacyReportsNotice = ValueKey('home.notice.legacyReports');
  static const otzariaOpenBanner = ValueKey('home.banner.otzariaOpen');
  static const elevationBanner = ValueKey('home.banner.elevation');
  static const newPluginsBanner = ValueKey('home.banner.newPlugins');
  static const libraryMissingNotice = ValueKey('home.notice.libraryMissing');
  static const libraryAbsentNotice = ValueKey('home.notice.libraryAbsent');
  static const homeSyncOffNote = ValueKey('home.note.syncOff');
  static const libraryNotFoundNotice = ValueKey('home.notice.libraryNotFound');
  static const libraryElsewhereNotice =
      ValueKey('home.notice.libraryElsewhere');
  static const semanticConsentNotice = ValueKey('home.notice.semanticConsent');
  static const semanticAskDialog = ValueKey('dialog.semanticAsk');
  static const semanticAskApprove = ValueKey('dialog.semanticAsk.approve');
  static const semanticAskDecline = ValueKey('dialog.semanticAsk.decline');
  static const semanticAskWhatIsSent =
      ValueKey('dialog.semanticAsk.whatIsSent');
  static const settingsSemanticConsent = ValueKey('settings.semanticConsent');

  static const launcherLine = ValueKey('home.foot.launcher');
  static const launcherUpdateButton = ValueKey('home.foot.launcherUpdate');
  static const statusBar = ValueKey('home.statusBar');
  static const connectionLine = ValueKey('home.foot.connection');
  static const checkedAt = ValueKey('home.foot.checkedAt');
  static const checkNow = ValueKey('home.foot.checkNow');
  static const driveLine = ValueKey('home.foot.drive');
  static const driveLockedChip = ValueKey('home.foot.driveLocked');
  static const homeContact = ValueKey('home.contact');

  static const welcome = ValueKey('home.welcome');
  static const welcomePrimary = ValueKey('home.welcome.primary');
  static const welcomeLanguage = ValueKey('home.welcome.language');
  static const welcomeLinks = ValueKey('home.welcome.links');

  static const sectionStack = ValueKey('shell.sections');

  static const statusPrimary = ValueKey('page.status.primary');
  static const pageAdvanced = ValueKey('page.advanced');
  static const appAdvanced = ValueKey('otzaria.advanced');
  static const appChannel = ValueKey('otzaria.channel');
  static const appReinstall = ValueKey('otzaria.reinstall');
  static const appAwaitsNewer = ValueKey('otzaria.awaitsNewer');
  static const pageBusyNote = ValueKey('page.busyNote');
  static const libraryLocation = ValueKey('library.location');
  static const libraryReindex = ValueKey('library.reindex');
  static const libraryFull = ValueKey('library.full');
  static const libraryPersonal = ValueKey('library.personal');
  static const librarySource = ValueKey('library.source');
  static const libraryConsent = ValueKey('library.consent');
  static const libraryConsentWhatIsSent =
      ValueKey('library.consent.whatIsSent');
  static const libraryInstallNote = ValueKey('library.installNote');
  static const reportsSend = ValueKey('reports.send');
  static const reportsCheckConnection = ValueKey('reports.checkConnection');
  static const storeEmptyReload = ValueKey('store.empty.reload');
  static const reportsStop = ValueKey('reports.stop');
  static const reportsProblem = ValueKey('reports.problem');
  static const reportsLegacy = ValueKey('reports.legacy');
  static const reportsCollect = ValueKey('reports.collect');
  static const reportsDisclosure = ValueKey('reports.disclosure');

  static const taskLayer = ValueKey('task.layer');
  static const taskPrimary = ValueKey('task.primary');
  static const taskSecondary = ValueKey('task.secondary');
  static const taskCancel = ValueKey('task.cancel');
  static const taskHide = ValueKey('task.hide');
  static const taskSemanticRemember = ValueKey('task.semanticRemember');
  static const taskStopWaiting = ValueKey('task.stopWaiting');
  static const taskReindex = ValueKey('task.reindex');
  static const taskElevation = ValueKey('task.elevation');
  static const heroShowProgress = ValueKey('home.hero.showProgress');
  static const heroShowDownload = ValueKey('home.hero.showDownload');
  static const personalAskDialog = ValueKey('personal.ask');
  static const personalAskMultiple = ValueKey('personal.ask.multiple');
  static const personalAskMine = ValueKey('personal.ask.mine');
  static const personalAskConfirm = ValueKey('personal.ask.confirm');
  static const personalPreparedHere = ValueKey('home.personal.preparedHere');
  static const personalDownloadNote = ValueKey('home.personal.downloadNote');
  static const settingsPersonalMultiple =
      ValueKey('settings.personal.multiple');
  static const settingsPersonalMine = ValueKey('settings.personal.mine');
  static const settingsPersonalRegisterHere =
      ValueKey('settings.personal.registerHere');
  static const personalPendingNote = ValueKey('home.personal.pending');

  /// "הסרה" של מחשב שנרשם, לפי המפתח שלו בקובץ ה-state.
  static ValueKey<String> personalMachineRemove(String machineKey) =>
      ValueKey('settings.personal.remove.$machineKey');

  /// אריח הבית שמוביל אל [section].
  static ValueKey<String> tile(ShellSection section) =>
      ValueKey('home.tile.${section.name}');
}
