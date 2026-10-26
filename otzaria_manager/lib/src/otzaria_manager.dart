import 'dart:io'
    show Directory, FileSystemEntity, FileSystemEntityType, Platform;

import 'package:otzaria_downloads/otzaria_downloads.dart' show WindowsElevation;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'models/otzaria_capabilities.dart';
import 'models/otzaria_deep_links.dart';
import 'models/otzaria_install_state.dart';
import 'models/otzaria_release.dart';
import 'models/otzaria_release_channel.dart';
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

/// נקודת הכניסה היחידה שמודול ה-UI (הדשבורד ב-Flutter) אמור להשתמש בה.
/// מרכיב יחד את בדיקת ה-release, ההתקנה, השמירה, הזיהוי וההפעלה, בלי
/// שהצרכן יצטרך להכיר את השירותים הפנימיים — כולל בחירת המסלול הנכון
/// לפלטפורמה (Windows/macOS).
///
/// דוגמת שימוש (התקנה טרייה או עדכון רגיל):
/// ```dart
/// final manager = OtzariaManager(dataDir: dataDir);
/// final check = await manager.checkForUpdate();
/// if (check.updateAvailable) {
///   await manager.update(check, onProgress: (r, t) => print('$r/$t'));
/// }
/// await manager.launch();
/// ```
///
/// דוגמת שימוש (למשתמש שכבר יש לו אוצריא מותקנת במיקום משלו):
/// ```dart
/// final detected = await manager.detectExistingInstall(customDir: userChosenDir);
/// if (detected != null) {
///   await manager.adoptExistingInstall(detected);
/// }
/// ```
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

    /// לאן נכתב קובץ המצב, כשהוא אינו יכול לשבת ב-[dataDir] — כונן
    /// מוגן-כתיבה שממנו אפשר רק להתקין (`AppPaths.readOnly` בלאנצ'ר).
    /// ברירת המחדל היא [dataDir] עצמה.
    String? stateDir,
    OtzariaTargetPlatform? platform,
    Map<String, String>? environment,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
    WindowsInstallRegistry installRegistry = const WindowsInstallRegistry(),
    OtzariaLauncher launcher = const OtzariaLauncher(),
    InstalledVersionReader? versionReader,
    OtzariaArch? machineArch,
    OtzariaArch? Function(String exePath)? exeArchOf,

    /// ברירת המחדל: [legacyWindowsInstallDirsFor] על הסביבה.
    List<String>? legacyInstallDirs,
    this.preferPrerelease = false,
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
    // הכול נבנה בגוף ה-constructor ולא ברשימת האתחול, כדי שכולם יקבלו את
    // [_platform] שכבר נפתר — במקום לפתור את `Platform.operatingSystem`
    // מחדש בכל אחד מהם.
    _legacyInstallDirs =
        legacyInstallDirs ?? legacyWindowsInstallDirsFor(_environment);
    _appLocator = OtzariaAppLocator(platform: _platform);
    _versionReader = versionReader ?? installedVersionReaderFor(_platform);
    _releaseClient = OtzariaReleaseClient(platform: _platform);
    _changelogClient = OtzariaChangelogClient();
    _installer = OtzariaInstaller(
      // קובצי ההתקנה יושבים **בתוך** המראה, כדי שהמטא־דאטה והקובץ ייסעו
      // יחד על הכונן הנייד.
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

  /// בחירת המשתמש כשבמראה יושבות **שתי** גרסאות: `true` = הלא-יציבה
  /// (pre-release), `false` = היציבה. ניתן לשינוי בזמן ריצה, ונכנס לתוקף
  /// בבדיקה/התקנה הבאה. אינו משפיע על ההורדה — היא תמיד מביאה את שתיהן.
  bool preferPrerelease;

  bool get elevatedAsOtherUser =>
      _platform == OtzariaTargetPlatform.windows &&
      WindowsElevation.isElevatedAsOtherUser;

  /// הזמן הקצוב לכל פעולת רשת של המודול — נכנס לתוקף בבקשה הבאה, כדי
  /// שההגדרה בלאנצ'ר לא תדרוש בנייה מחדש של הלקוחות.
  set networkTimeout(Duration value) {
    _releaseClient.timeout = value;
    _changelogClient.timeout = value;
    _installer.connectTimeout = value;
  }

  /// תיקיית המראה של תוכנת אוצריא — ראו [OtzariaAppMirror].
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
      stable: pick(arm64.stable, x64.stable),
      prerelease: pick(arm64.prerelease, x64.prerelease),
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

  /// `<data>/otzaria-app` — התיקייה שאליה הלאנצ'ר **נהג** להתקין, כשהיא עוד
  /// הייתה ברירת המחדל. אין מתקינים לשם יותר (ראו [resolveDefaultInstallDir]),
  /// אבל היא נשארת בראש [_autoDetectDirs]: התקנות שכבר יושבות שם חייבות
  /// להמשיך להיות מזוהות ולהתעדכן במקומן.
  final String _managedInstallDir;

  /// תיקיית האפליקציות הסטנדרטית של macOS. ב-macOS, בשונה מווינדוס,
  /// למשתמש שהתקין את אוצריא בעצמו היא כמעט תמיד תהיה שם — גרירת ה-`.app`
  /// ל-`/Applications` היא *הדרך* להתקין. לכן שווה להציץ שם לפני שמתקינים
  /// עותק שני בתיקייה המנוהלת של הלאנצ'ר.
  static const String _macApplicationsDir = '/Applications';

  /// `~/Applications` — המקבילה הפר-משתמשית של [_macApplicationsDir], שאינה
  /// דורשת הרשאת מנהל. Finder מציג אותה בדיוק כמו התיקייה הראשית.
  String? get _userApplicationsDir {
    final home = _environment['HOME'];
    return home == null || home.isEmpty ? null : p.join(home, 'Applications');
  }

  /// גיבוי משני בווינדוס: `C:\אוצריא` של המתקינים הישנים, שכתבו C: קבוע.
  /// `SystemDrive` משמש רק כמתג: סביבה מוזרקת בלעדיו אינה מגיעה להתקנה שבמחשב.
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

  /// לאן תלך התקנה חדשה כשאין עדיין התקנה מוכרת: **המיקום הרגיל של אוצריא
  /// על המחשב**, ולא תיקייה של הלאנצ'ר. ציבורי כדי שהממשק יוכל להראות
  /// מראש לאן מתקינים.
  ///
  /// זה הבאג שהיה כאן: ברירת המחדל הייתה [_managedInstallDir], שיושבת בתוך
  /// `OtzariaData` שליד קובץ ההרצה. לאנצ'ר שרץ מכונן נייד — התרחיש שלשמו
  /// נכתבה התוכנה — התקין בכך את אוצריא **על הכונן**: היא נעלמה מהמחשב
  /// ברגע שהכונן נשלף, ותפסה עליו מקום במקום להישאר במחשב שאליו התכוונו.
  ///
  /// ⚠️ **בווינדוס אין קוראים לזה בהתקנה** — ראו [_installDirFor]: המתקין
  /// בוחר את ברירת המחדל שלו, ולא אנחנו. נשאר ציבורי כי הממשק מציג את
  /// המיקום, וכי ב-macOS זה כן היעד בפועל.
  Future<String> resolveDefaultInstallDir() async {
    if (_platform == OtzariaTargetPlatform.windows) {
      final dirs = _windowsRealDefaultDirs;
      return dirs.isEmpty ? r'C:\אוצריא' : dirs.first.dir;
    }
    // `/Applications` קיימת תמיד, אבל בחשבון שאינו מנהל אי אפשר לכתוב בה.
    if (await _isWritableDir(_macApplicationsDir)) return _macApplicationsDir;
    // בלי HOME נשארים על `/Applications` ונכשלים שם בקול — עדיף מהתקנה
    // שקטה אל תיקיית הלאנצ'ר, כלומר אל הכונן הנייד.
    return _userApplicationsDir ?? _macApplicationsDir;
  }

  /// האם אפשר באמת **ליצור** בתוך [dir] — ולא רק "היא קיימת".
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

  /// התיקיות שבהן מחפשים התקנה קיימת כשאין עדיין state שמור, לפי סדר
  /// עדיפות. התיקייה המנוהלת הישנה של הלאנצ'ר תמיד ראשונה (אם הלאנצ'ר עצמו
  /// התקין לשם בגרסה קודמת, זה המקור הסמכותי); אחריה, בווינדוס, מה שרשום
  /// ברג'יסטרי — זה הנתיב האמיתי גם כשהמשתמש התקין במקום משלו, ולכן הוא
  /// קודם לניחוש לפי מיקומי ברירת המחדל.
  ///
  /// `sharedDir` מסמן תיקייה שיש בה גם אפליקציות אחרות — ראו
  /// [_verifyIsOtzaria].
  ///
  /// `verifyIdentity` על תיקיות הרג'יסטרי: ה-`DisplayName` שם נבחר בהכלה
  /// (`mentionsOtzaria`), ולכן גם **מוצר אחר** ששמו מזכיר את אוצריא נכנס
  /// לרשימה — "HebrewBooks לאוצריא" הביא את הלאנצ'ר לקרוא גרסה מ-exe זר
  /// (2.12.0), להכריז installedIsNewer ולסרב להתקין אוצריא בכלל. בתיקייה
  /// ייעודית (`{autopf}\Otzaria`) הניחוש בטוח, וה-fallback נשאר.
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
    OtzariaChannelReleases? online,
    void Function(int received, int total)? onProgress,
    void Function(OtzariaReleaseChannel channel)? onChannel,
    bool Function()? isCancelled,
  }) =>
      _mirror.sync(
        online: online,
        onDownloadProgress: onProgress,
        onChannelStart: onChannel,
        isCancelled: isCancelled,
      );

  /// The highest schema any channel's installer on the drive reads, `null` if
  /// none is usable; the architecture is chosen as [update] chooses it.
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

  /// **שני הערוצים** כפי שהם ברשת כרגע, ולא גרסה נבחרת אחת.
  ///
  /// ההורדה מביאה תמיד את שניהם, ולכן "יש מה להביא?" חייב להישאל על כל
  /// ערוץ מול המקביל לו במראה. כששאלנו על הנבחר בלבד, פרסום של pre-release
  /// לבדו (היציב לא זז) נראה כמו "אין חדש": מודול התוכנה דולג, הערוץ
  /// הלא-יציב לא ירד, ולכן פקד בחירת הערוץ לא הופיע — והמשתמש לא יכול היה
  /// לבקש אותו. ראו `OtzariaModuleController.hasOnlineUpdate`.
  Future<OtzariaChannelReleases> peekOnlineChannels() async {
    final online = await _releaseClient.fetchChannelReleases();
    return OtzariaChannelReleases(
      stable: await _withChangelogNotes(online.stable),
      prerelease: await _withChangelogNotes(online.prerelease),
    );
  }

  /// "מה התחדש" מיומן השינויים המרוכז, עם נפילה לתיאור ה-release הגולמי.
  Future<OtzariaRelease?> _withChangelogNotes(OtzariaRelease? release) async {
    if (release == null) return null;
    final notes = await _changelogClient.notesFor(release.tagName);
    return notes == null ? release : release.copyWithReleaseNotes(notes);
  }

  /// בודק אם יש עדכון זמין — **מהמראה המקומית בלבד, בלי רשת**. ה-state השמור
  /// מאומת קודם מול הדיסק של המחשב הזה ([_verifyStoredState]); אם הוא לא
  /// תקף שם, או שאין state בכלל (אף פעם לא הותקן/אומץ דרך הלאנצ'ר הזה),
  /// מנסים לזהות התקנה קיימת במיקומים המוכרים ([_autoDetectDirs]) — לא
  /// סורקים את כל המחשב — כדי לא "לשכוח" התקנה שכבר קיימת שם מסשן קודם.
  ///
  /// [OtzariaUpdateCheckResult.latestRelease] הוא `null` כשעדיין לא הורדה
  /// שום גרסה. זה לא כשל: זה אומר "יש להריץ הורדה במחשב עם אינטרנט".
  Future<OtzariaUpdateCheckResult> checkForUpdate() async {
    // שלושתם עצמאיים: שתי קריאות דיסק ובדיקת תהליך. בטור זה היה סכום
    // הזמנים — ובדיקת התהליך לבדה היא ~300ms.
    //
    // בדיקת תהליך **אחת** משרתת את כל הבדיקה: היא גם מזהה התקנה וגם עונה
    // על "אוצריא פתוחה?" שהממשק מציג. קודם היא רצה פעמיים — כאן ושוב
    // בלאנצ'ר.
    _registryDirs = null;
    final mirrorLoad = _mirror.load();
    final arm64MirrorLoad = _mirror.load(arch: OtzariaArch.arm64);
    final storedState = _stateStore.load();
    final probe = _runningLocator.probe();

    final stored = await storedState;
    final running = await probe;

    // ה-state נאמן רק אם ההתקנה שהוא מתאר קיימת *כאן* — ראו
    // [_verifyStoredState]. גרסה שהתחלפה על הדיסק נכתבת בחזרה.
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

    // רק כשעדיין לא ידוע כלום: בניית הרשימה עצמה סורקת את הרג'יסטרי
    // (~200ms), ואין סיבה לשלם על זה בכל בדיקה כשההתקנה כבר מוכרת.
    current ??= await _detectInKnownDirs();
    final mirrored = await _mirrorFor(
      current,
      x64Load: mirrorLoad,
      arm64Load: arm64MirrorLoad,
    );

    return OtzariaUpdateCheckResult(
      stableRelease: mirrored.stable?.release,
      prereleaseRelease: mirrored.prerelease?.release,
      preferPrerelease: preferPrerelease,
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
    final selected = mirrored.select(preferPrerelease: preferPrerelease);
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

  /// מסרב להתקין ב-macOS בזמן שאוצריא פתוחה.
  ///
  /// ההתקנה שם היא החלפת חבילת ה-`.app` כולה, ואחריה מחיקת החבילה הקודמת —
  /// ו-`unlink` ב-macOS מצליח על קבצים שתהליך מחזיק פתוחים. כלומר אוצריא
  /// שרצה הייתה ממשיכה לרוץ בלי הקבצים שלה וקורסת ברגע שתזדקק למשאב נוסף.
  /// בווינדוס אין צורך בזה: המתקין של Inno הוא שמכריע מה לעשות עם קובץ נעול.
  ///
  /// אותו שיקול בדיוק שבגללו `LibraryUpdateApplier` בודק את שומר-התהליך שוב
  /// מיד לפני החלפת המסד.
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

  /// מפעיל את אוצריא: קודם לפי מצב ההתקנה השמור, ואם אין כזה — לפי ההתקנה
  /// שמזוהה במיקומים המוכרים ([_autoDetectDirs]).
  ///
  /// הנפילה חזרה אינה מיותרת: זיהוי לפי תיקייה (רג'יסטרי ההסרה או תיקיית
  /// ברירת המחדל) **אינו נשמר** בכוונה — ראו [checkForUpdate] — ולכן בלעדיה
  /// הלאנצ'ר הציג את הגרסה שמצא ובלחיצה על "הפעל" סירב להפעיל אותה.
  ///
  /// זורק רק כשלא נמצאה שום התקנה; אז יש להתקין, או להצביע על התיקייה
  /// ([detectExistingInstall] + [adoptExistingInstall]).
  /// [withUri] מוסר לאוצריא קישור עומק בהפעלה — ראו [OtzariaDeepLinks].
  Future<void> launch({String? withUri}) async {
    final state = (await _loadVerifiedState()) ?? (await _detectInKnownDirs());
    if (state == null) {
      throw OtzariaUserError(AppL10n.strings.appDomain.noOtzariaInstallFound);
    }
    await _launcher.launch(state.launchPath, withUri: withUri);
  }

  /// מבקש מאוצריא לרענן את הספרייה מהדיסק ולעדכן את אינדקס החיפוש — הבקשה
  /// שאחרי עדכון `seforim.db` שנעשה **מבחוץ**, ע"י הלאנצ'ר.
  ///
  /// אוצריא סגורה תיפתח; מופע פתוח מקבל את הבקשה דרך ה-single-instance שלו
  /// ולא נפתח שוב. אין כאן פרמטרים — אוצריא מזהה לבד אילו ספרים השתנו.
  Future<void> requestLibraryReindex() =>
      launch(withUri: OtzariaDeepLinks.libraryReindex);

  /// ה-state השמור, אחרי אימות מול הדיסק — או null כשאין כזה או שאינו תקף
  /// כאן. ראו [_verifyStoredState].
  Future<OtzariaInstallState?> _loadVerifiedState() async {
    final stored = await _stateStore.load();
    return stored == null ? null : _verifyStoredState(stored);
  }

  /// מאמת state שמור מול הדיסק של המחשב **הזה**, ומחזיר null אם ההתקנה
  /// שהוא מתאר אינה שם.
  ///
  /// קובץ ה-state יושב ב-`OtzariaData` שעל הכונן הנייד ונוסע איתו בין
  /// מחשבים, ולכן "מותקנת גרסה X" שנרשם במחשב אחד אינו עדות לכלום במחשב
  /// הבא. בלי האימות הזה הלאנצ'ר הכריז "אוצריא מעודכנת" במחשב שאין בו
  /// אוצריא בכלל, ובדיקה מחדש רק קראה שוב את אותו קובץ.
  ///
  /// הקובץ עצמו **אינו** נמחק: הוא עשוי להיות תקף לגמרי במחשב שהכונן יחזור
  /// אליו.
  OtzariaInstallState? _verifyStoredState(OtzariaInstallState stored) {
    // `.exe` בווינדוס, חבילת `.app` (תיקייה) ב-macOS — לכן בדיקת סוג ולא
    // `File.existsSync`.
    if (FileSystemEntity.typeSync(stored.launchPath) ==
        FileSystemEntityType.notFound) {
      return null;
    }

    // הגרסה נקראת תמיד מקובץ ההרצה עצמו (ראו [OtzariaStateStore]), כדי
    // שהתקנה שעודכנה מחוץ ללאנצ'ר לא תוצג בגרסה שאנחנו "זוכרים". כשל
    // קריאה משאיר את התג השמור — הקובץ קיים, ואין סיבה להתייחס אליו כאילו
    // נעלם.
    final onDisk = _readVersionQuietly(stored.launchPath);
    if (onDisk == null) return stored;

    // אותו exe שראינו כשנכתב ה-state: התג השמור נאמן, והוא היחיד שהוא תג
    // גיטהאב מלא — כולל ה-build שלו, שהדיסק אינו יודע לדווח.
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

  /// ההתקנה הראשונה שנמצאת ב-[_autoDetectDirs], או null. אינה נשמרת.
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

  /// מחפש התקנה קיימת של אוצריא בתיקייה נתונה (למשל תיקייה שהמשתמש
  /// הצביע עליה ידנית, כי הוא כבר התקין את אוצריא במיקום משלו לפני
  /// שהתחיל להשתמש בלאנצ'ר הזה). קורא את הגרסה ישירות מההתקנה עצמה
  /// (version resource בווינדוס, `Info.plist` ב-macOS) — לא מסתמך על מה
  /// שהלאנצ'ר עצמו "זוכר".
  ///
  /// מחזיר null אם לא נמצאה התקנה בתיקייה, או שנמצאה אך לא ניתן לקרוא
  /// ממנה גרסה (למשל אם זו לא בכלל התקנה של אוצריא).
  ///
  /// [isSharedDir] = "התיקייה הזאת מכילה גם אפליקציות אחרות" (למשל
  /// `/Applications`), ואז נדרש גם אימות זהות ([_verifyIsOtzaria]) ולא
  /// מסתפקים ב"נמצאה שם אפליקציה". כשהמשתמש הצביע ידנית על תיקייה, ברירת
  /// המחדל (false) נכונה: הוא אמר לנו שאוצריא שם.
  ///
  /// [verifyIdentity] דורש את אותו אימות בתיקייה שאינה משותפת — כשהגענו
  /// אליה מהתאמת שם ולא מידיעה. ראו [_autoDetectDirs].
  Future<OtzariaInstallState?> detectExistingInstall({
    required String customDir,
    bool isSharedDir = false,
    bool verifyIdentity = false,
  }) async {
    final launchPath = await _appLocator.findIn(
      customDir,
      accept: isSharedDir || verifyIdentity ? _verifyIsOtzaria : null,
      // בתיקייה משותפת ה-.app תמיד יושבת ישירות בשורש — אין טעם לצלול.
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

  /// מזהה התקנה קיימת לפי **תהליך אוצריא שרץ כרגע** — ראו
  /// [RunningOtzariaLocator]. בשונה מ-[detectExistingInstall], לא סורקים
  /// כאן את התיקייה: ידוע לנו בדיוק איזה קובץ רץ, ולסרוק היה עלול להחזיר
  /// exe אחר שיושב לידו.
  ///
  /// מחזיר null כשאוצריא אינה רצה, כשאין הרשאה לקרוא את נתיב התהליך, או
  /// כשלא ניתן לקרוא ממנו גרסה — בכל המקרים האלה פשוט ממשיכים לזיהוי
  /// לפי תיקיות ברירת המחדל.
  Future<OtzariaInstallState?> detectRunningInstall() async =>
      _installStateAt(await _runningLocator.findLaunchPath());

  /// מצב התקנה מנתיב הפעלה שכבר ידוע, בלי לחזור לבדיקת התהליך.
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

  /// קריאת הגרסה מקובץ ההרצה, שכשל בה הוא "לא ידוע" ולא תקלה.
  ///
  /// הקוראים כאן הם מסלולי **זיהוי**, ושם `null` הוא תשובה תקינה: ממשיכים
  /// למועמד הבא. הקורא עצמו כן זורק — `plutil` שאינו שם, קובץ בלי משאב
  /// גרסה, או קורא של פלטפורמה אחרת — ובלי העטיפה כל `checkForUpdate`
  /// הייתה נופלת בגלל אפליקציה זרה אחת שנקרתה בדרך.
  ///
  /// מחזיר את מה שכתוב ב-exe **כפי שהוא**, כולל ה-build — ראו
  /// [_diskStateAt] למה הוא אינו נכנס לתג.
  String? _readVersionQuietly(String launchPath) {
    try {
      return _versionReader.readVersion(launchPath);
    } catch (_) {
      return null;
    }
  }

  /// מצב התקנה מגרסה שנקראה מהדיסק.
  ///
  /// ה-build שאחרי ה-`+` נשמר כ-[OtzariaInstallState.appVersion] ואינו
  /// נכנס לתג: המספר המוטבע ב-exe (`0.9.97+99702`) הוא ספירה אחרת מזו
  /// שבתגי הגיטהאב (`0.9.97+740`), והשוואה בין השתיים הכריזה תמיד
  /// "מותקנת גרסה חדשה יותר".
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

  /// "מאמץ" התקנה קיימת שהתגלתה על ידי [detectExistingInstall] — שומר
  /// אותה כמצב הידוע, כך שמכאן והלאה עדכונים יתבצעו לתוך אותה תיקייה
  /// (במקום לתיקייה המנוהלת של הלאנצ'ר).
  Future<void> adoptExistingInstall(OtzariaInstallState detected) async {
    await _stateStore.save(detected);
  }

  void dispose() {
    _releaseClient.dispose();
    _changelogClient.dispose();
    _installer.dispose();
  }
}
