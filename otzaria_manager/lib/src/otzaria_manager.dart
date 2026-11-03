import 'dart:io'
    show Directory, FileSystemEntity, FileSystemEntityType, Platform;

import 'package:otzaria_downloads/otzaria_downloads.dart' show WindowsElevation;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'models/otzaria_capabilities.dart';
import 'models/otzaria_deep_links.dart';
import 'models/otzaria_install_state.dart';
import 'models/otzaria_release.dart';
import 'models/otzaria_update_check_result.dart';
import 'otzaria_user_error.dart';
import 'services/installed_version_reader.dart';
import 'services/mac_app_version_reader.dart';
import 'services/otzaria_app_locator.dart';
import 'services/otzaria_app_mirror.dart';
import 'services/otzaria_changelog_client.dart';
import 'services/otzaria_installer.dart';
import 'services/otzaria_launcher.dart';
import 'services/otzaria_process_closer.dart';
import 'services/otzaria_release_client.dart';
import 'services/otzaria_state_store.dart';
import 'services/running_otzaria_locator.dart';
import 'services/windows_arch.dart';
import 'services/windows_install_registry.dart';

class OtzariaManager {
  static Map<String, String> Function() defaultEnvironment =
      _platformEnvironment;

  static Map<String, String> _platformEnvironment() => Platform.environment;

  static void sandboxForTests(String sandboxRoot) {
    final real = Platform.environment;
    final forbidden = [
      for (final key in const ['APPDATA', 'LOCALAPPDATA', 'ProgramData'])
        if ((real[key] ?? '').isNotEmpty) p.join(real[key]!, 'otzaria'),
      if ((real['HOME'] ?? '').isNotEmpty)
        p.join(real['HOME']!, 'Library', 'Application Support', 'otzaria'),
    ];
    final sandbox = {
      'APPDATA': p.join(sandboxRoot, 'Roaming'),
      'LOCALAPPDATA': p.join(sandboxRoot, 'Local'),
      'HOME': p.join(sandboxRoot, 'home'),
      for (final key in const ['ProgramFiles', 'ProgramFiles(x86)'])
        if (real[key] != null) key: real[key]!,
    };
    defaultEnvironment = () => sandbox;
    OtzariaCapabilities.debugPathGuard = (path) {
      for (final root in forbidden) {
        if (p.equals(root, path) || p.isWithin(root, path)) {
          throw AssertionError('A test reached a real Otzaria path: $path');
        }
      }
    };
    final temp = Directory.systemTemp.path;
    OtzariaLauncher.debugLaunchGuard = (path) {
      if (!p.isWithin(temp, path)) {
        throw AssertionError('A test tried to launch a real program: $path');
      }
    };
    OtzariaProcessCloser.debugCloseGuard =
        () => throw AssertionError('A test tried to close the running Otzaria');
  }

  OtzariaManager({
    required String dataDir,
    String? stateDir,
    OtzariaTargetPlatform? platform,
    Map<String, String>? environment,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
    WindowsInstallRegistry installRegistry = const WindowsInstallRegistry(),
    OtzariaLauncher launcher = const OtzariaLauncher(),
    InstalledVersionReader? versionReader,
    OtzariaArch? machineArch,
    OtzariaArch? Function(String exePath)? exeArchOf,
    List<String>? legacyInstallDirs,
  })  : _platform =
            platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem),
        _environment = environment ?? defaultEnvironment(),
        _machineArchOverride = machineArch,
        _exeArchOf = exeArchOf ?? WindowsArch.ofExecutable,
        _runningLocator = runningLocator,
        _installRegistry = installRegistry,
        _stateStore = OtzariaStateStore(
          p.join(stateDir ?? dataDir, 'otzaria_install_state.json'),
        ),
        _launcher = launcher,
        _managedInstallDir = p.join(dataDir, 'otzaria-app'),
        mirrorDir = p.join(dataDir, 'mirror', 'app') {
    _legacyInstallDirs =
        legacyInstallDirs ?? legacyWindowsInstallDirsFor(_environment);
    _appLocator = OtzariaAppLocator(platform: _platform);
    _versionReader = versionReader ?? installedVersionReaderFor(_platform);
    _releaseClient = OtzariaReleaseClient(platform: _platform);
    _changelogClient = OtzariaChangelogClient();
    _installer = OtzariaInstaller(
      cacheDir: p.join(mirrorDir, 'installers'),
      appLocator: _appLocator,
      versionReader: _versionReader,
    );
    _mirror = OtzariaAppMirror(
      mirrorDir: mirrorDir,
      releaseClient: _releaseClient,
      installer: _installer,
      changelogClient: _changelogClient,
      platform: _platform,
    );
  }

  bool get elevatedAsOtherUser =>
      _platform == OtzariaTargetPlatform.windows &&
      WindowsElevation.isElevatedAsOtherUser;

  set networkTimeout(Duration value) {
    _releaseClient.timeout = value;
    _changelogClient.timeout = value;
    _installer.connectTimeout = value;
  }

  final String mirrorDir;

  final OtzariaTargetPlatform _platform;
  final Map<String, String> _environment;
  final OtzariaArch? _machineArchOverride;
  final OtzariaArch? Function(String exePath) _exeArchOf;

  OtzariaArch get _machineArch =>
      _machineArchOverride ??
      (_platform == OtzariaTargetPlatform.windows
          ? WindowsArch.machine(environment: _environment)
          : OtzariaArch.x64);

  Future<MirroredOtzariaReleases> _mirrorFor(
    OtzariaInstallState? current, {
    Future<MirroredOtzariaReleases>? x64Load,
    Future<MirroredOtzariaReleases>? arm64Load,
  }) async {
    final x64 = await (x64Load ?? _mirror.load());
    if (_platform != OtzariaTargetPlatform.windows ||
        _machineArch != OtzariaArch.arm64) {
      return x64;
    }
    final arm64 = await (arm64Load ?? _mirror.load(arch: OtzariaArch.arm64));
    final keepArm64 =
        current != null && _exeArchOf(current.launchPath) == OtzariaArch.arm64;
    MirroredOtzariaRelease? pick(
      MirroredOtzariaRelease? arm,
      MirroredOtzariaRelease? x,
    ) {
      if (arm == null || keepArm64) return arm ?? (keepArm64 ? null : x);
      if (x == null) return arm;
      return OtzariaUpdateCheckResult.compareVersions(
                arm.release.tagName,
                x.release.tagName,
              ) >=
              0
          ? arm
          : x;
    }

    return MirroredOtzariaReleases(
      latest: pick(arm64.latest, x64.latest),
    );
  }

  final OtzariaStateStore _stateStore;
  late final OtzariaReleaseClient _releaseClient;
  late final OtzariaChangelogClient _changelogClient;
  late final OtzariaInstaller _installer;
  late final OtzariaAppMirror _mirror;
  final OtzariaLauncher _launcher;
  late final OtzariaAppLocator _appLocator;
  final RunningOtzariaLocator _runningLocator;
  final WindowsInstallRegistry _installRegistry;
  late final InstalledVersionReader _versionReader;

  final String _managedInstallDir;

  static const String _macApplicationsDir = '/Applications';

  String? get _userApplicationsDir {
    final home = _environment['HOME'];
    return home == null || home.isEmpty ? null : p.join(home, 'Applications');
  }

  static List<String> legacyWindowsInstallDirsFor(
    Map<String, String> environment,
  ) {
    final drive = environment['SystemDrive'];
    return drive == null || drive.isEmpty ? const [] : const [r'C:\אוצריא'];
  }

  late final List<String> _legacyInstallDirs;

  List<({String dir, bool sharedDir})> get _windowsRealDefaultDirs {
    final dirs = <({String dir, bool sharedDir})>[];

    final localAppData = _environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      dirs.add((
        dir: p.join(localAppData, 'Programs', 'Otzaria'),
        sharedDir: false,
      ));
      dirs.add((
        dir: p.join(localAppData, 'Programs', 'אוצריא'),
        sharedDir: false,
      ));
    }
    final programFiles = _environment['ProgramFiles'];
    if (programFiles != null && programFiles.isNotEmpty) {
      dirs.add((dir: p.join(programFiles, 'Otzaria'), sharedDir: false));
      dirs.add((dir: p.join(programFiles, 'אוצריא'), sharedDir: false));
    }
    for (final dir in _legacyInstallDirs) {
      dirs.add((dir: dir, sharedDir: false));
    }

    return dirs;
  }

  Future<String> resolveDefaultInstallDir() async {
    if (_platform == OtzariaTargetPlatform.windows) {
      final dirs = _windowsRealDefaultDirs;
      return dirs.isEmpty ? r'C:\אוצריא' : dirs.first.dir;
    }

    if (await _isWritableDir(_macApplicationsDir)) return _macApplicationsDir;

    return _userApplicationsDir ?? _macApplicationsDir;
  }

  static Future<bool> _isWritableDir(String dir) async {
    try {
      final probe = await Directory(dir).createTemp('.otzaria-write-test-');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isDurableInstallDir(String dir) async {
    if (_platform != OtzariaTargetPlatform.macos) return true;
    final segments = p.split(dir);
    if (segments.contains('AppTranslocation')) return false;
    if (segments.contains('Volumes')) return _isWritableDir(dir);
    return true;
  }

  Future<List<String>>? _registryDirs;

  Future<List<String>> _registryInstallDirs({bool fresh = false}) {
    if (fresh) _registryDirs = null;
    return _registryDirs ??= _installRegistry.otzariaInstallDirs();
  }

  Future<List<({String dir, bool sharedDir, bool verifyIdentity})>>
      _autoDetectDirs({bool fresh = false}) async => switch (_platform) {
            OtzariaTargetPlatform.windows => [
                (
                  dir: _managedInstallDir,
                  sharedDir: false,
                  verifyIdentity: false
                ),
                for (final dir in await _registryInstallDirs(fresh: fresh))
                  (dir: dir, sharedDir: false, verifyIdentity: true),
                for (final candidate in _windowsRealDefaultDirs)
                  (
                    dir: candidate.dir,
                    sharedDir: candidate.sharedDir,
                    verifyIdentity: false,
                  ),
              ],
            OtzariaTargetPlatform.macos => [
                (
                  dir: _managedInstallDir,
                  sharedDir: false,
                  verifyIdentity: false
                ),
                (
                  dir: _macApplicationsDir,
                  sharedDir: true,
                  verifyIdentity: false
                ),
                if (_userApplicationsDir case final dir?)
                  (dir: dir, sharedDir: true, verifyIdentity: false),
              ],
          };

  Future<void> downloadToMirror({
    OtzariaLatestRelease? online,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) =>
      _mirror.sync(
        online: online,
        onDownloadProgress: onProgress,
        isCancelled: isCancelled,
      );

  Future<int?> mirroredReadableDbSchema() async {
    final stored = await _stateStore.load();
    final current = stored == null ? null : _verifyStoredState(stored);
    int? best;
    for (final entry in (await _mirrorFor(current)).all) {
      final schema = OtzariaCapabilities.readableDbSchemaForAppVersion(
        entry.release.tagName,
      );
      if (schema != null && (best == null || schema > best)) best = schema;
    }
    return best;
  }

  /// The app versions of the installers the drive carries; their model
  /// generations are what a new install there will read.
  Future<List<String>> mirroredInstallerVersions() async {
    final stored = await _stateStore.load();
    final current = stored == null ? null : _verifyStoredState(stored);
    return [
      for (final entry in (await _mirrorFor(current)).all)
        entry.release.tagName,
    ];
  }

  Future<OtzariaLatestRelease> peekOnlineRelease() async {
    final online = await _releaseClient.fetchLatestRelease();
    return OtzariaLatestRelease(
      latest: await _withChangelogNotes(online.latest),
    );
  }

  Future<OtzariaRelease?> _withChangelogNotes(OtzariaRelease? release) async {
    if (release == null) return null;
    final notes = await _changelogClient.notesFor(release.tagName);
    return notes == null ? release : release.copyWithReleaseNotes(notes);
  }

  Future<OtzariaUpdateCheckResult> checkForUpdate() async {
    _registryDirs = null;
    final mirrorLoad = _mirror.load();
    final arm64MirrorLoad = _mirror.load(arch: OtzariaArch.arm64);
    final storedState = _stateStore.load();
    final probe = _runningLocator.probe();

    final stored = await storedState;
    final running = await probe;

    var current = stored == null ? null : _verifyStoredState(stored);
    if (current != null && current != stored) await _stateStore.save(current);

    if (current == null) {
      final runningState = _installStateAt(running.launchPath);
      if (runningState != null &&
          await _isDurableInstallDir(runningState.installDir)) {
        current = runningState;
        await _stateStore.save(runningState);
      }
    }

    current ??= await _detectInKnownDirs();
    final mirrored = await _mirrorFor(
      current,
      x64Load: mirrorLoad,
      arm64Load: arm64MirrorLoad,
    );

    return OtzariaUpdateCheckResult(
      latestRelease: mirrored.latest?.release,
      currentState: current,
      isOtzariaRunning: running.isRunning,
      hasStaleFullPackage: (await _mirror.staleFullPackages()).isNotEmpty,
      mirrorLacksArchitectures: await _mirror.lacksArm64Installers(),
    );
  }

  Future<OtzariaInstallState> update(
    OtzariaUpdateCheckResult check, {
    bool useWizard = false,
    void Function()? onSetupContinuesElsewhere,
    bool Function()? isWaitCancelled,
  }) async {
    final mirrored = await _mirrorFor(check.currentState);
    final selected = mirrored.latest;
    if (selected == null) {
      throw OtzariaUserError(AppL10n.strings.appDomain.mirrorEmptyRunDownload);
    }

    await _refuseIfRunningOnMac();

    final installDir = await _installDirFor(check.currentState);
    final state = useWizard &&
            selected.release.installerKind ==
                OtzariaInstallerKind.windowsSetupExe &&
            OtzariaInstaller.windowsInstallScopeOf(installDir) !=
                OtzariaWindowsInstallScope.portable
        ? await _installer.installWithWizard(
            release: selected.release,
            installerPath: selected.installerPath,
            locateInstalled: (accept) =>
                _detectInKnownDirs(accept: accept, fresh: true),
            installDir: installDir,
            onSetupContinuesElsewhere: onSetupContinuesElsewhere,
            isWaitCancelled: isWaitCancelled,
          )
        : await _installer.installFromFile(
            release: selected.release,
            installerPath: selected.installerPath,
            installDir: installDir,
            locateInstalled: () => _detectInKnownDirs(fresh: true),
          );
    await _stateStore.save(state);
    return state;
  }

  Future<void> _refuseIfRunningOnMac() async {
    if (_platform != OtzariaTargetPlatform.macos) return;
    if (!(await _runningLocator.probe()).isRunning) return;
    throw OtzariaUserError(
        AppL10n.strings.appDomain.macCloseOtzariaBeforeInstall);
  }

  Future<String?> _installDirFor(OtzariaInstallState? existing) async {
    if (existing != null) return existing.installDir;
    return _platform == OtzariaTargetPlatform.macos
        ? await resolveDefaultInstallDir()
        : null;
  }

  Future<void> launch({String? withUri}) async {
    final state = (await _loadVerifiedState()) ?? (await _detectInKnownDirs());
    if (state == null) {
      throw OtzariaUserError(AppL10n.strings.appDomain.noOtzariaInstallFound);
    }
    await _launcher.launch(state.launchPath, withUri: withUri);
  }

  Future<void> requestLibraryReindex() =>
      launch(withUri: OtzariaDeepLinks.libraryReindex);

  Future<OtzariaInstallState?> _loadVerifiedState() async {
    final stored = await _stateStore.load();
    return stored == null ? null : _verifyStoredState(stored);
  }

  OtzariaInstallState? _verifyStoredState(OtzariaInstallState stored) {
    if (FileSystemEntity.typeSync(stored.launchPath) ==
        FileSystemEntityType.notFound) {
      return null;
    }

    final onDisk = _readVersionQuietly(stored.launchPath);
    if (onDisk == null) return stored;

    if (onDisk == stored.appVersion) return stored;

    final version = _installedVersionOf(stored.launchPath, onDisk);
    if (stored.appVersion == null &&
        OtzariaUpdateCheckResult.sameVersion(
          version,
          stored.installedTagName,
        )) {
      return OtzariaInstallState(
        installedTagName: stored.installedTagName,
        installDir: stored.installDir,
        launchPath: stored.launchPath,
        appVersion: onDisk,
      );
    }
    if (stored.appVersion == null &&
        _sameMajorMinorPatch(version, stored.installedTagName)) {
      return stored;
    }

    return _diskStateAt(
      launchPath: stored.launchPath,
      installDir: stored.installDir,
      version: onDisk,
    );
  }

  static bool _sameMajorMinorPatch(String diskVersion, String tagName) =>
      OtzariaUpdateCheckResult.compareBases(
        diskVersion,
        tagName,
        leftCarriesHotfix: false,
      ) ==
      0;

  Future<OtzariaInstallState?> _detectInKnownDirs({
    bool Function(OtzariaInstallState detected)? accept,
    bool fresh = false,
  }) async {
    for (final candidate in await _autoDetectDirs(fresh: fresh)) {
      final detected = await detectExistingInstall(
        customDir: candidate.dir,
        isSharedDir: candidate.sharedDir,
        verifyIdentity: candidate.verifyIdentity,
      );
      if (detected != null && (accept == null || accept(detected))) {
        return detected;
      }
    }
    return null;
  }

  Future<OtzariaInstallState?> detectExistingInstall({
    required String customDir,
    bool isSharedDir = false,
    bool verifyIdentity = false,
  }) async {
    final launchPath = await _appLocator.findIn(
      customDir,
      accept: isSharedDir || verifyIdentity ? _verifyIsOtzaria : null,
      macMaxDepth: isSharedDir ? 1 : OtzariaAppLocator.defaultMacMaxDepth,
    );
    if (launchPath == null) return null;

    final version = _readVersionQuietly(launchPath);
    if (version == null) return null;

    return _diskStateAt(
      launchPath: launchPath,
      installDir: customDir,
      version: version,
    );
  }

  Future<OtzariaInstallState?> detectRunningInstall() async =>
      _installStateAt(await _runningLocator.findLaunchPath());

  OtzariaInstallState? _installStateAt(String? launchPath) {
    if (launchPath == null) return null;

    final version = _readVersionQuietly(launchPath);
    if (version == null) return null;

    return _diskStateAt(
      launchPath: launchPath,
      installDir: p.dirname(launchPath),
      version: version,
    );
  }

  String? _readVersionQuietly(String launchPath) {
    try {
      return _versionReader.readVersion(launchPath);
    } catch (_) {
      return null;
    }
  }

  OtzariaInstallState _diskStateAt({
    required String launchPath,
    required String installDir,
    required String version,
  }) =>
      OtzariaInstallState(
        installedTagName: _installedVersionOf(launchPath, version),
        installDir: installDir,
        launchPath: launchPath,
        appVersion: version,
      );

  String _installedVersionOf(String launchPath, String diskVersion) {
    final capabilities = OtzariaCapabilities.readForInstall(
      launchPath,
      platform: _platform,
      environment: _environment,
    );
    final appVersion = capabilities?.appVersion;
    final build = OtzariaUpdateCheckResult.buildNumberOf(diskVersion);
    if (appVersion != null &&
        build != null &&
        capabilities!.buildNumber == build &&
        capabilities.describesExe(launchPath)) {
      return OtzariaUpdateCheckResult.normalizeVersion(appVersion);
    }
    return OtzariaUpdateCheckResult.versionFromDisk(diskVersion);
  }

  bool _verifyIsOtzaria(String candidatePath) {
    if (OtzariaAppLocator.nameLooksLikeOtzaria(candidatePath)) return true;

    if (_platform == OtzariaTargetPlatform.macos) {
      if (!_isFlutterMacBundle(candidatePath)) return false;
      try {
        final id = const MacAppVersionReader().readBundleIdentifier(
          candidatePath,
        );
        return id != null && id.toLowerCase().endsWith('.otzaria');
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  static bool _isFlutterMacBundle(String candidatePath) {
    final bundle = MacAppVersionReader.bundleRootOf(candidatePath);
    if (bundle == null) return false;
    return FileSystemEntity.typeSync(
          p.join(bundle, 'Contents', 'Frameworks', 'FlutterMacOS.framework'),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;
  }

  Future<void> adoptExistingInstall(OtzariaInstallState detected) async {
    await _stateStore.save(detected);
  }

  void dispose() {
    _releaseClient.dispose();
    _changelogClient.dispose();
    _installer.dispose();
  }
}
