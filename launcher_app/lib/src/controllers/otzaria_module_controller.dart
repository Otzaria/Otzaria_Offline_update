import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import '../services/app_logger.dart';
import '../services/elevation.dart';
import '../services/storage_failure.dart';
import 'dispose_guard.dart';
import 'progress_notifier.dart';

enum OtzariaModuleStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  installing,
  error,

  needsDownload,

  installedIsNewer,
}

enum OtzariaDownloadStatus { idle, downloading, done, error }

class OtzariaModuleController extends ChangeNotifier
    with DisposeGuard, ProgressNotifier {
  OtzariaModuleController({
    required String dataDir,
    String? stateDir,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
    Future<String?> Function()? pendingLaunchUri,
    Future<void> Function()? onLaunchUriDelivered,
    bool Function()? isLibraryApplying,
    OtzariaLauncher launcher = const OtzariaLauncher(),
    OtzariaProcessCloser? processCloser,
    OtzariaTargetPlatform? platform,
    OtzariaManager? manager,
  })  : _pendingLaunchUri = pendingLaunchUri,
        _onLaunchUriDelivered = onLaunchUriDelivered,
        _isLibraryApplying = isLibraryApplying,
        _runningLocator = runningLocator,
        _processCloser =
            processCloser ?? OtzariaProcessCloser(locator: runningLocator),
        _manager = manager ??
            OtzariaManager(
              dataDir: dataDir,
              stateDir: stateDir,
              platform: platform,
              runningLocator: runningLocator,
              launcher: launcher,
            );

  final OtzariaManager _manager;

  final Future<String?> Function()? _pendingLaunchUri;
  final Future<void> Function()? _onLaunchUriDelivered;
  final bool Function()? _isLibraryApplying;

  bool get libraryApplyActive => _isLibraryApplying?.call() ?? false;

  final RunningOtzariaLocator _runningLocator;

  final OtzariaProcessCloser _processCloser;
  OtzariaUpdateCheckResult? _lastCheck;

  Future<void>? _checkInFlight;
  final int _checkInputs = 0;
  bool _installing = false;
  bool _recheckAfterInstall = false;
  OtzariaModuleStatus status = OtzariaModuleStatus.idle;
  String? currentVersion;

  String? launchPath;

  String? latestVersion;
  String? errorMessage;

  String? installStage;

  bool _stopSetupWait = false;

  void stopWaitingForSetup() => _stopSetupWait = true;

  String? noticeMessage;

  OtzariaInstallResult? lastInstallResult;

  String? lastInstallNotice;

  bool installNotDetected = false;

  bool needsElevation = false;

  bool hasStaleFullPackage = false;

  bool isRunning = false;

  Future<bool>? _runningProbe;

  bool isClosing = false;

  OtzariaDownloadStatus downloadStatus = OtzariaDownloadStatus.idle;
  int? downloadReceived;
  int? downloadTotal;

  String? downloadStage;
  String? downloadError;

  Object? downloadCause;
  bool get downloadStorageFull => findStorageFull(downloadCause) != null;
  DateTime? lastDownloadedAt;

  OtzariaLatestRelease? onlineRelease;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  OtzariaRelease? get onlineLatestRelease => onlineRelease?.latest;

  bool get canLaunch => currentVersion != null && !libraryApplyActive;

  bool get elevatedAsOtherUser => _manager.elevatedAsOtherUser;

  String get mirrorDir => _manager.mirrorDir;

  String? get latestReleaseNotes => _lastCheck?.latestRelease?.releaseNotes;

  String? get installedReleaseNotes {
    final installed = currentVersion;
    final check = _lastCheck;
    if (installed == null || check == null) return null;
    for (final release in [check.latestRelease]) {
      if (release == null) continue;
      final tag = release.tagName;
      if (OtzariaUpdateCheckResult.normalizeVersion(tag) ==
              OtzariaUpdateCheckResult.normalizeVersion(installed) &&
          OtzariaUpdateCheckResult.sameBuild(tag, installed)) {
        return release.releaseNotes;
      }
    }
    return null;
  }

  bool get hasOnlineUpdate {
    final online = onlineRelease;
    if (online == null) return false;

    return _hasDifferentRelease(online.latest?.tagName, latestVersion);
  }

  int? get onlineDownloadBytes {
    final online = onlineRelease;
    if (online == null) return null;
    final mirrored = {latestVersion};
    final lacksArm64 = _lastCheck?.mirrorLacksArchitectures ?? false;
    final seen = <String>{};
    var bytes = 0;
    for (final release in [online.latest]) {
      if (release == null || !seen.add(release.tagName)) continue;
      final arm64 = release.arm64Variant?.installerSizeBytes ?? 0;
      if (!mirrored.contains(release.tagName)) {
        bytes += release.installerSizeBytes + arm64;
      } else if (lacksArm64) {
        bytes += arm64;
      }
    }
    return bytes > 0 ? bytes : null;
  }

  static bool _hasDifferentRelease(String? online, String? mirrored) {
    if (online == null) return false;
    if (mirrored == null) return true;
    if (OtzariaUpdateCheckResult.normalizeVersion(online) !=
        OtzariaUpdateCheckResult.normalizeVersion(mirrored)) {
      return true;
    }
    return !OtzariaUpdateCheckResult.sameBuild(online, mirrored);
  }

  String? get onlineUpdateVersion {
    final online = onlineRelease;
    if (online == null) return null;
    return _hasDifferentRelease(online.latest?.tagName, latestVersion)
        ? online.latest?.tagName
        : null;
  }

  Future<void> checkOnline() async {
    notifyListeners();

    try {
      onlineRelease = await _manager.peekOnlineRelease();
      onlineCheckError = null;
    } catch (e) {
      onlineRelease = null;
      onlineCheckError = e.toString();

      AppLogger.instance.info('בדיקת עדכונים ברשת (אוצריא) לא הצליחה: $e');
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  Future<bool> refreshRunningState({bool force = false}) {
    final inFlight = _runningProbe;
    if (inFlight == null) return _runningProbe = _probeRunning();
    if (!force) return inFlight;
    return inFlight.then((_) => _runningProbe ??= _probeRunning());
  }

  Object? _loggedProbeFailure;

  void _noteProbeFailure() {
    final failure = RunningOtzariaLocator.lastProbeFailure;
    if (failure != null && failure != _loggedProbeFailure) {
      AppLogger.maybeInstance?.warn(
        'בדיקת "אוצריא פתוחה?" נכשלה ונחשבת "סגורה": $failure',
      );
    }
    _loggedProbeFailure = failure;
  }

  Future<bool> _probeRunning() async {
    try {
      final probe = await _runningLocator.probe();
      _noteProbeFailure();
      if (isDisposed) return probe.isRunning;
      final changed = isRunning != probe.isRunning;
      isRunning = probe.isRunning;
      if (changed) notifyListeners();
      return isRunning;
    } finally {
      _runningProbe = null;
    }
  }

  Future<bool> closeRunning() async {
    if (isClosing) return !isRunning;
    isClosing = true;
    notifyListeners();
    try {
      final closed = await _processCloser.close();
      if (isDisposed) return closed;
      await refreshRunningState(force: true);
      return closed;
    } catch (e, st) {
      AppLogger.instance.error('סגירת אוצריא מהלאנצ׳ר נכשלה', e, st);
      return false;
    } finally {
      isClosing = false;
      if (!isDisposed) notifyListeners();
    }
  }

  Future<bool> adoptInstallDir(String dir) async {
    final detected = await _manager.detectExistingInstall(customDir: dir);
    if (detected == null) return false;
    await _manager.adoptExistingInstall(detected);
    await checkForUpdate();
    return true;
  }

  static const Duration _onlineReuseWindow = Duration(minutes: 10);

  OtzariaLatestRelease? get _freshOnlineRelease {
    final checkedAt = onlineCheckedAt;
    if (checkedAt == null ||
        DateTime.now().difference(checkedAt) >= _onlineReuseWindow) {
      return null;
    }
    return onlineRelease;
  }

  Future<int?> mirroredReadableDbSchema() =>
      _manager.mirroredReadableDbSchema();

  Future<void> download({bool Function()? isCancelled}) async {
    downloadStatus = OtzariaDownloadStatus.downloading;
    downloadReceived = null;
    downloadTotal = null;
    downloadStage = null;
    downloadError = null;
    downloadCause = null;
    notifyListeners();

    try {
      await _manager.downloadToMirror(
        online: _freshOnlineRelease,
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyProgress();
        },
        isCancelled: isCancelled,
      );
      downloadStage = null;
      downloadStatus = OtzariaDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      notifyListeners();
      await checkForUpdate();
      return;
    } catch (e, st) {
      downloadStage = null;

      if (isCancelled?.call() ?? false) {
        downloadStatus = OtzariaDownloadStatus.idle;
        AppLogger.instance.info('הורדת גרסת אוצריא בוטלה: $e');
      } else {
        downloadStatus = OtzariaDownloadStatus.error;
        downloadError = e.toString();
        downloadCause = e;
        AppLogger.instance.error('הורדת גרסת אוצריא נכשלה', e, st);
      }
    }
    notifyListeners();
  }

  Future<void> ensureChecked() async {
    if (_lastCheck != null) return;
    await (_checkInFlight ?? checkForUpdate());
  }

  Future<void> checkForUpdate() {
    if (_installing) {
      _recheckAfterInstall = true;
      return Future.value();
    }
    final inFlight = _checkInFlight;
    if (inFlight != null) return inFlight;
    final started = _checkForUpdate();
    _checkInFlight = started;
    return started.whenComplete(() {
      if (identical(_checkInFlight, started)) _checkInFlight = null;
    });
  }

  Future<void> _checkForUpdate() async {
    status = OtzariaModuleStatus.checking;
    needsElevation = false;
    installNotDetected = false;
    notifyListeners();

    try {
      OtzariaUpdateCheckResult check;
      int inputs;
      do {
        inputs = _checkInputs;
        check = await _manager.checkForUpdate();
      } while (inputs != _checkInputs);
      _lastCheck = check;
      currentVersion = check.currentState?.installedTagName;
      launchPath = check.currentState?.launchPath;
      latestVersion = check.latestRelease?.tagName;
      hasStaleFullPackage =
          check.hasStaleFullPackage || check.mirrorLacksArchitectures;
      isRunning = check.isOtzariaRunning;
      _noteProbeFailure();
      status = switch (check) {
        _ when check.needsDownload => OtzariaModuleStatus.needsDownload,
        _ when check.installedIsNewer => OtzariaModuleStatus.installedIsNewer,
        _ when check.updateAvailable => OtzariaModuleStatus.updateAvailable,
        _ => OtzariaModuleStatus.upToDate,
      };
      errorMessage = null;
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance
          .error('OtzariaModuleController.checkForUpdate נכשל', e, st);
    }
    notifyListeners();
  }

  Future<void> install({bool useWizard = true}) async {
    if (_lastCheck == null || _installing) return;
    if (_refuseWhileLibraryApplies()) return;
    for (var pending = _checkInFlight;
        pending != null;
        pending = _checkInFlight) {
      await pending;
      if (_installing) return;
    }
    final check = _lastCheck;
    if (check == null) return;

    _installing = true;
    _stopSetupWait = false;
    lastInstallResult = null;
    lastInstallNotice = null;
    installNotDetected = false;
    _recheckAfterInstall = false;
    status = OtzariaModuleStatus.installing;
    needsElevation = false;
    noticeMessage = null;
    errorMessage = null;
    notifyListeners();
    AppLogger.instance.info(
      'התקנת אוצריא מתחילה: ${check.currentState?.installedTagName} -> '
      '${check.latestRelease?.tagName}',
    );

    var recheck = false;
    try {
      final state = await _manager.update(
        check,
        useWizard: useWizard,
        onSetupContinuesElsewhere: () {
          installStage = AppL10n.strings.appDomain.setupContinuesElsewhere;
          if (!isDisposed) notifyListeners();
        },
        isWaitCancelled: () => _stopSetupWait || isDisposed,
      );
      currentVersion = state.installedTagName;
      status = OtzariaModuleStatus.upToDate;
      lastInstallResult = OtzariaInstallResult.installed;
      AppLogger.instance.info('התקנת אוצריא הסתיימה בהצלחה');
      recheck = useWizard;
    } on OtzariaInstallCancelled catch (e) {
      noticeMessage = lastInstallNotice = e.toString();
      lastInstallResult = OtzariaInstallResult.cancelled;
      AppLogger.instance.info('התקנת אוצריא בוטלה באשף');
      recheck = true;
    } on OtzariaWizardStillOpen catch (e) {
      noticeMessage = lastInstallNotice = e.toString();
      lastInstallResult = OtzariaInstallResult.wizardStillOpen;
      AppLogger.instance.info('אשף ההתקנה עדיין פתוח — ההתקנה לא זוהתה עדיין');
      recheck = true;
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      lastInstallResult = OtzariaInstallResult.failed;
      errorMessage = Elevation.describe(e);
      needsElevation = Elevation.isAccessDenied(e);
      installNotDetected = e is OtzariaInstallNotDetected;
      _recheckAfterInstall = false;
      AppLogger.instance.error('התקנת אוצריא נכשלה', e, st);
    } finally {
      _installing = false;
      installStage = null;
    }
    if (recheck || _recheckAfterInstall) {
      _recheckAfterInstall = false;
      await checkForUpdate();
      return;
    }
    notifyListeners();
  }

  Future<String?> launch() async {
    if (_refuseWhileLibraryApplies()) return null;
    if (errorMessage != null && status != OtzariaModuleStatus.error) {
      errorMessage = null;
      notifyListeners();
    }
    final uri = await _pendingLaunchUri?.call();
    try {
      await _manager.launch(withUri: uri);
      if (uri != null) await _onLaunchUriDelivered?.call();
      if (!isRunning) {
        isRunning = true;
        notifyListeners();
      }
      return null;
    } catch (e, st) {
      final message = e.toString();

      if (status != OtzariaModuleStatus.error) errorMessage = message;
      AppLogger.instance.error('OtzariaModuleController.launch() נכשל', e, st);
      notifyListeners();
      return message;
    }
  }

  Future<bool> requestLibraryReindex() async {
    if (_refuseWhileLibraryApplies()) return false;
    try {
      await _manager.requestLibraryReindex();
      if (!isRunning) {
        isRunning = true;
        notifyListeners();
      }
      return true;
    } catch (e, st) {
      errorMessage = e.toString();
      AppLogger.instance.error('בקשת עדכון האינדקס לאוצריא נכשלה', e, st);
      notifyListeners();
      return false;
    }
  }

  bool _refuseWhileLibraryApplies() {
    if (!libraryApplyActive) return false;
    noticeMessage = AppL10n.strings.home.libraryApplyActive;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}

enum OtzariaInstallResult { installed, cancelled, wizardStillOpen, failed }
