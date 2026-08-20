import 'dart:io'
    show Directory, FileSystemEntity, FileSystemEntityType, Platform;

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'models/otzaria_deep_links.dart';
import 'models/otzaria_install_state.dart';
import 'models/otzaria_release.dart';
import 'models/otzaria_release_channel.dart';
import 'models/otzaria_update_check_result.dart';
import 'services/installed_version_reader.dart';
import 'services/mac_app_version_reader.dart';
import 'services/otzaria_app_locator.dart';
import 'services/otzaria_app_mirror.dart';
import 'services/otzaria_changelog_client.dart';
import 'services/otzaria_installer.dart';
import 'services/otzaria_launcher.dart';
import 'services/otzaria_release_client.dart';
import 'services/otzaria_state_store.dart';
import 'services/running_otzaria_locator.dart';
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
  OtzariaManager({
    required String dataDir,
    OtzariaTargetPlatform? platform,
    Map<String, String>? environment,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
    WindowsInstallRegistry installRegistry = const WindowsInstallRegistry(),
    OtzariaLauncher launcher = const OtzariaLauncher(),
    this.preferPrerelease = false,
    this.downloadFullPackage = false,
  })  : _platform =
            platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem),
        _environment = environment ?? Platform.environment,
        _runningLocator = runningLocator,
        _installRegistry = installRegistry,
        _stateStore =
            OtzariaStateStore(p.join(dataDir, 'otzaria_install_state.json')),
        _launcher = launcher,
        _managedInstallDir = p.join(dataDir, 'otzaria-app'),
        mirrorDir = p.join(dataDir, 'mirror', 'app') {
    // הכול נבנה בגוף ה-constructor ולא ברשימת האתחול, כדי שכולם יקבלו את
    // [_platform] שכבר נפתר — במקום לפתור את `Platform.operatingSystem`
    // מחדש בכל אחד מהם.
    _appLocator = OtzariaAppLocator(platform: _platform);
    _versionReader = installedVersionReaderFor(_platform);
    _releaseClient = OtzariaReleaseClient(platform: _platform);
    _changelogClient = OtzariaChangelogClient();
    _installer = OtzariaInstaller(
      // קובצי ההתקנה יושבים **בתוך** המראה, כדי שהמטא־דאטה והקובץ ייסעו
      // יחד על הכונן הנייד.
      cacheDir: p.join(mirrorDir, 'installers'),
      appLocator: _appLocator,
    );
    _mirror = OtzariaAppMirror(
      mirrorDir: mirrorDir,
      releaseClient: _releaseClient,
      installer: _installer,
      changelogClient: _changelogClient,
    );
  }

  /// בחירת המשתמש כשבמראה יושבות **שתי** גרסאות: `true` = הלא-יציבה
  /// (pre-release), `false` = היציבה. ניתן לשינוי בזמן ריצה, ונכנס לתוקף
  /// בבדיקה/התקנה הבאה. אינו משפיע על ההורדה — היא תמיד מביאה את שתיהן.
  bool preferPrerelease;

  /// `true` = ההורדה מביאה גם את **חבילת ה-FULL** של הגרסה היציבה
  /// (~2GB, כוללת את הספרייה בתוכה). **כבוי כברירת מחדל** — היא נחוצה רק
  /// למחשב שאוצריא מותקנת בו בפעם הראשונה, ולרוב הכוננים היא סתם נפח.
  /// ניתן לשינוי בזמן ריצה, ונכנס לתוקף בהורדה הבאה.
  bool downloadFullPackage;

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

  /// גיבוי משני בווינדוס — לא ברירת המחדל האמיתית. ייתכן שזה עדיין נכון
  /// בהתקנות ישנות (אומת מול מפתחי אוצריא: "אם קיימת התקנה קודמת — המתקין
  /// נשאר בנתיב שלה, למשל C:\אוצריא או {Program Files}\אוצריא").
  static const String _legacyWindowsInstallDir = r'C:\אוצריא';

  /// המיקומים שאוצריא **עשויה** לשבת בהם בווינדוס, לצורכי זיהוי:
  /// `{autopf}\Otzaria` (כלומר `%LocalAppData%\Programs\Otzaria` למשתמש
  /// הנוכחי, או `%ProgramFiles%\Otzaria` לכל המשתמשים), ואחריו
  /// [_legacyWindowsInstallDir]. כולן תיקיות ייעודיות לאוצריא בלבד — לא
  /// "משותפות" כמו `/Applications`.
  ///
  /// ⚠️ **אין להסיק מכאן לאן להתקין.** הרשימה נבנתה כשחשבנו ש-`{autopf}`
  /// הוא ברירת המחדל של המתקין (כך נמסר מהמפתחים ב-2026-08-07), אבל ה-iss
  /// אומר `DefaultDirName=C:\אוצריא`. התקנה חדשה בווינדוס לא מוסרת `/DIR=`
  /// בכלל — ראו [_installDirFor].
  List<({String dir, bool sharedDir})> get _windowsRealDefaultDirs {
    final dirs = <({String dir, bool sharedDir})>[];

    final localAppData = _environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      dirs.add((
        dir: p.join(localAppData, 'Programs', 'Otzaria'),
        sharedDir: false,
      ));
    }
    final programFiles = _environment['ProgramFiles'];
    if (programFiles != null && programFiles.isNotEmpty) {
      dirs.add((dir: p.join(programFiles, 'Otzaria'), sharedDir: false));
      dirs.add((dir: p.join(programFiles, 'אוצריא'), sharedDir: false));
    }
    dirs.add((dir: _legacyWindowsInstallDir, sharedDir: false));

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
      return _windowsRealDefaultDirs.first.dir;
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

  /// התיקיות שבהן מחפשים התקנה קיימת כשאין עדיין state שמור, לפי סדר
  /// עדיפות. התיקייה המנוהלת הישנה של הלאנצ'ר תמיד ראשונה (אם הלאנצ'ר עצמו
  /// התקין לשם בגרסה קודמת, זה המקור הסמכותי); אחריה, בווינדוס, מה שרשום
  /// ברג'יסטרי — זה הנתיב האמיתי גם כשהמשתמש התקין במקום משלו, ולכן הוא
  /// קודם לניחוש לפי מיקומי ברירת המחדל.
  ///
  /// `sharedDir` מסמן תיקייה שיש בה גם אפליקציות אחרות — ראו
  /// [_verifyIsOtzaria].
  List<({String dir, bool sharedDir})> get _autoDetectDirs =>
      switch (_platform) {
        OtzariaTargetPlatform.windows => [
            (dir: _managedInstallDir, sharedDir: false),
            for (final dir in _installRegistry.installDirs())
              (dir: dir, sharedDir: false),
            ..._windowsRealDefaultDirs,
          ],
        OtzariaTargetPlatform.macos => [
            (dir: _managedInstallDir, sharedDir: false),
            (dir: _macApplicationsDir, sharedDir: true),
            // שתי היעדים שאליהם אנחנו מתקינים, בסדר שבו נבחרים ביניהם.
            if (_userApplicationsDir case final dir?)
              (dir: dir, sharedDir: true),
          ],
      };

  /// מוריד את הגרסאות האחרונות אל המראה המקומית — **הפעולה הכבדה** שנוגעת
  /// ברשת (מוריד את קובצי ההתקנה עצמם). לא מתקין כלום.
  ///
  /// מוריד **את שתי הגרסאות**: היציבה, ובנוסף ה-pre-release כשהוא חדש
  /// ממנה. כך במחשב המנותק אפשר לבחור ביניהן בלי לחזור לרשת.
  ///
  /// [isCancelled] נבדק גם באמצע נכס: הביטול הוא של המשתמש, וקובץ ההתקנה
  /// (~70MB) אינו משהו שכדאי לחכות לסופו. קובץ חלקי נמחק, ונזרק
  /// [OtzariaDownloadCancelled].
  Future<void> downloadToMirror({
    void Function(int received, int total)? onProgress,
    void Function(OtzariaReleaseChannel channel)? onChannel,
    void Function()? onFullPackage,
    bool Function()? isCancelled,
  }) =>
      _mirror.sync(
        onDownloadProgress: onProgress,
        onChannelStart: onChannel,
        onFullPackageStart: onFullPackage,
        isCancelled: isCancelled,
        includeFullPackage: downloadFullPackage,
      );

  /// בודק מה הגרסה העדכנית ביותר ב-GitHub **בערוץ שהמשתמש בחר** —
  /// **פעולת רשת קלה**: קריאת API יחידה, בלי הורדת קובץ ההתקנה. מיועדת
  /// לבדיקה צדדית ("יש עדכון?") בלי לחייב הורדה מלאה. זורקת חריג רשת/HTTP
  /// רגיל בכשל — הקורא אמור להתייחס לכשל כ"אין חיבור כרגע", לא כשגיאה
  /// חוסמת.
  ///
  /// המידע "מה התחדש" בתוצאה מגיע מיומן השינויים המרוכז של אוצריא
  /// (`OtzariaChangelogClient`) כשהגרסה מופיעה בו, ונופל חזרה לתיאור
  /// ה-release הגולמי מ-GitHub אם לא.
  Future<OtzariaRelease> peekLatestOnlineRelease() async {
    final online = await _releaseClient.fetchChannelReleases();
    final release = online.select(preferPrerelease: preferPrerelease);
    if (release == null) {
      throw StateError(
        AppL10n.strings.appDomain.noInstallableReleaseForPlatform,
      );
    }
    final changelogNotes = await _changelogClient.notesFor(release.tagName);
    return changelogNotes == null
        ? release
        : release.copyWithReleaseNotes(changelogNotes);
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
    final mirrorLoad = _mirror.load();
    final storedState = _stateStore.load();
    final probe = _runningLocator.probe();

    final mirrored = await mirrorLoad;
    final stored = await storedState;
    final running = await probe;

    // ה-state נאמן רק אם ההתקנה שהוא מתאר קיימת *כאן* — ראו
    // [_verifyStoredState]. גרסה שהתחלפה על הדיסק נכתבת בחזרה.
    var current = stored == null ? null : _verifyStoredState(stored);
    if (current != null && current != stored) await _stateStore.save(current);

    // התהליך הרץ קודם לרשימת התיקיות: הוא אינו ניחוש אלא העותק שהמשתמש
    // מפעיל בפועל — כולל התקנה במיקום שאינו ברשימה. זו גם תצפית **חולפת**,
    // ולכן נשמרת: אחרת המידע היה נעלם בדיוק כשמבקשים מהמשתמש לסגור את
    // אוצריא. זיהוי לפי תיקייה, לעומת זאת, חוזר על עצמו בכל בדיקה.
    if (current == null) {
      current = _installStateAt(running.launchPath);
      if (current != null) await _stateStore.save(current);
    }

    // רק כשעדיין לא ידוע כלום: בניית הרשימה עצמה סורקת את הרג'יסטרי
    // (~200ms), ואין סיבה לשלם על זה בכל בדיקה כשההתקנה כבר מוכרת.
    current ??= await _detectInKnownDirs();

    return OtzariaUpdateCheckResult(
      stableRelease: mirrored.stable?.release,
      prereleaseRelease: mirrored.prerelease?.release,
      preferPrerelease: preferPrerelease,
      currentState: current,
      isOtzariaRunning: running.isRunning,
      // רק כשקובץ ההתקנה של ה-FULL באמת על הכונן — ראו
      // [OtzariaAppMirror.load], שפוסלת רשומה שהקובץ שלה חסר.
      mirroredFullPackage: mirrored.stable?.hasFullPackage ?? false
          ? mirrored.stable?.release.fullPackage
          : null,
      fullPackageKnown: mirrored.stable?.fullPackageKnown ?? false,
    );
  }

  /// מתקין את הגרסה שיושבת במראה המקומית **בערוץ שנבחר**
  /// ([preferPrerelease]). אם יש כבר מצב מוכר (מותקן/מאומץ קודם), מעדכן
  /// **באותה תיקייה** — לא יוצר התקנה שנייה; ואם אין, נותן למתקין להתקין
  /// לברירת המחדל שלו (ראו [_installDirFor]) ומזהה אחר כך לאן זה הלך.
  /// שומר את מצב ההתקנה החדש לשימוש עתידי.
  ///
  /// לא נוגע ברשת. זורק [StateError] אם אין מראה — כלומר לא בוצעה הורדה.
  ///
  /// [useWizard] — כמו ב-[installFullPackage]: לחיצה של המשתמש פותחת את
  /// האשף של המתקין, וההתקנה האוטומטית נשארת שקטה. גם בעדכון יש מה לבחור
  /// שם (קיצור דרך, ובמחשב נקי גם התיקייה), ובעדכון של התקנה קיימת Inno
  /// ממילא ממלא מראש את התיקייה שלה (`UsePreviousAppDir`) ומדלג על העמוד.
  Future<OtzariaInstallState> update(
    OtzariaUpdateCheckResult check, {
    bool useWizard = false,
  }) async {
    final mirrored = await _mirror.load();
    final selected = mirrored.select(preferPrerelease: preferPrerelease);
    if (selected == null) {
      throw StateError(AppL10n.strings.appDomain.mirrorEmptyRunDownload);
    }

    // שתי הגרסאות נשארות בכונן: התקנת אחת מהן לא מוחקת את קובץ ההתקנה
    // של השנייה, כדי שאפשר יהיה להחליף ערוץ בלי הורדה מחדש.
    final keepCachedTagNames = {
      for (final entry in mirrored.all) entry.release.tagName,
    };

    // אשף רק במתקין של ווינדוס — ב-macOS ההתקנה היא חילוץ bundle, ואין שם
    // אשף בכלל.
    final state = useWizard &&
            selected.release.installerKind ==
                OtzariaInstallerKind.windowsSetupExe
        ? await _installer.installWithWizard(
            release: selected.release,
            installerPath: selected.installerPath,
            locateInstalled: _detectInKnownDirs,
            // אותה תיקייה שההתקנה הקיימת יושבת בה — עדכון במקום, לא התקנה
            // שנייה לצדה. `null` בהתקנה חדשה.
            installDir: check.currentState?.installDir,
            keepCachedTagNames: keepCachedTagNames,
          )
        : await _installer.installFromFile(
            release: selected.release,
            installerPath: selected.installerPath,
            installDir: await _installDirFor(check.currentState),
            locateInstalled: _detectInKnownDirs,
            keepCachedTagNames: keepCachedTagNames,
          );
    await _stateStore.save(state);
    return state;
  }

  /// לאן להתקין: התיקייה של התקנה קיימת — ובהיעדרה `null` בווינדוס, כלומר
  /// "בלי `/DIR=`, שהמתקין יבחר".
  ///
  /// **למה לא ברירת מחדל משלנו:** [resolveDefaultInstallDir] נבנתה כדי
  /// *לחזור* על ברירת המחדל של המתקין, והערך שבה (`{autopf}\Otzaria`) לא
  /// תואם את ה-iss בפועל (`DefaultDirName=C:\אוצריא`). ניחוש שמתיישן הוא
  /// גרוע מלא לנחש: המתקין יודע לאן הוא מתקין, והרג'יסטרי אומר לנו איפה
  /// זה נגמר. ב-macOS אין מתקין שבוחר — ההתקנה היא העתקת bundle — ולכן שם
  /// התיקייה נחוצה תמיד.
  Future<String?> _installDirFor(OtzariaInstallState? existing) async {
    if (existing != null) return existing.installDir;
    return _platform == OtzariaTargetPlatform.macos
        ? await resolveDefaultInstallDir()
        : null;
  }

  /// מתקין את **חבילת ה-FULL** שיושבת במראה — תוכנה וספרייה בצעד אחד.
  ///
  /// מיועדת למחשב שאין בו אוצריא בכלל (ראו
  /// [OtzariaUpdateCheckResult.fullPackageRecommended]), אבל אינה מסרבת
  /// להתקין על גבי התקנה קיימת: אם המשתמש ביקש זאת במפורש, המתקין של
  /// אוצריא יודע לשדרג במקום. לא נוגע ברשת.
  ///
  /// [useWizard] = **להריץ את המתקין עם האשף שלו** ולא בשקט. זו ההתנהגות
  /// כשהמשתמש לחץ "התקן" בעצמו: החבילה המלאה מגיעה למחשב שאין בו אוצריא,
  /// ושם האשף מציג את הבחירות שרק המשתמש יכול לעשות — לאן להתקין (כונן
  /// נייד? תיקייה של משתמש אחד?), האם ליצור קיצור דרך, והאזהרה של ה-`[Code]`
  /// שבמתקין על נתונים שיימחקו. שקט נשאר ברירת המחדל למסלול ההתקנה
  /// האוטומטית, שבו אין מי שיענה לאשף.
  ///
  /// זורק [OtzariaInstallCancelled] כשהמשתמש ביטל באשף, ו-
  /// [OtzariaWizardStillOpen] כשהאשף עוד פתוח כשההמתנה נגמרה — שניהם אינם
  /// שגיאות.
  Future<OtzariaInstallState> installFullPackage({
    bool useWizard = false,
  }) async {
    final mirrored = await _mirror.load();
    final stable = mirrored.stable;
    final full = stable?.release.fullPackage;
    final path = stable?.fullInstallerPath;
    if (stable == null || full == null || path == null) {
      throw StateError(AppL10n.strings.appDomain.fullPackageNotOnDrive);
    }

    final keepCachedTagNames = {
      for (final entry in mirrored.all) entry.release.tagName,
    };

    final existing = await _loadVerifiedState() ?? await _detectInKnownDirs();

    // אשף רק במתקין של ווינדוס: ב-macOS אין מתקין בכלל — ההתקנה היא חילוץ
    // bundle, ואין שם שום עמוד בחירה להציג.
    if (useWizard &&
        full.installerKind == OtzariaInstallerKind.windowsSetupExe) {
      final state = await _installer.installWithWizard(
        release: stable.release,
        installerPath: path,
        locateInstalled: _detectInKnownDirs,
        // גם החבילה המלאה מתקינה על גבי התקנה קיימת, כשיש כזו.
        installDir: existing?.installDir,
        keepCachedTagNames: keepCachedTagNames,
      );
      await _stateStore.save(state);
      return state;
    }

    final state = await _installer.installFromFile(
      release: stable.release,
      installerPath: path,
      installerKind: full.installerKind,
      installDir: await _installDirFor(existing),
      locateInstalled: _detectInKnownDirs,
      appAppearTimeout: OtzariaInstaller.fullPackageAppAppearTimeout,
      keepCachedTagNames: keepCachedTagNames,
    );
    await _stateStore.save(state);
    return state;
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
      throw StateError(AppL10n.strings.appDomain.noOtzariaInstallFound);
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
    String? onDisk;
    try {
      onDisk = _versionReader.readVersion(stored.launchPath);
    } catch (_) {
      onDisk = null;
    }
    if (onDisk == null || onDisk == stored.installedTagName) return stored;

    return OtzariaInstallState(
      installedTagName: onDisk,
      installDir: stored.installDir,
      launchPath: stored.launchPath,
    );
  }

  /// ההתקנה הראשונה שנמצאת ב-[_autoDetectDirs], או null. אינה נשמרת.
  Future<OtzariaInstallState?> _detectInKnownDirs() async {
    for (final candidate in _autoDetectDirs) {
      final detected = await detectExistingInstall(
        customDir: candidate.dir,
        isSharedDir: candidate.sharedDir,
      );
      if (detected != null) return detected;
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
  Future<OtzariaInstallState?> detectExistingInstall({
    required String customDir,
    bool isSharedDir = false,
  }) async {
    final launchPath = await _appLocator.findIn(
      customDir,
      accept: isSharedDir ? _verifyIsOtzaria : null,
      // בתיקייה משותפת ה-.app תמיד יושבת ישירות בשורש — אין טעם לצלול.
      macMaxDepth: isSharedDir ? 1 : OtzariaAppLocator.defaultMacMaxDepth,
    );
    if (launchPath == null) return null;

    final version = _versionReader.readVersion(launchPath);
    if (version == null) return null;

    return OtzariaInstallState(
      installedTagName: version,
      installDir: customDir,
      launchPath: launchPath,
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

    final version = _versionReader.readVersion(launchPath);
    if (version == null) return null;

    return OtzariaInstallState(
      installedTagName: version,
      installDir: p.dirname(launchPath),
      launchPath: launchPath,
    );
  }

  /// האם [candidatePath] הוא בכלל אוצריא. נבדק לפי שם החבילה, ואם זה לא
  /// מכריע — לפי `CFBundleIdentifier` ב-macOS (`com.example.otzaria` בבנייה
  /// הנוכחית; ההשוואה היא על הסיומת `.otzaria` כדי שגם תיקון עתידי של
  /// המזהה, למשל ל-`org.otzaria.otzaria`, ימשיך לעבוד).
  bool _verifyIsOtzaria(String candidatePath) {
    if (OtzariaAppLocator.nameLooksLikeOtzaria(candidatePath)) return true;

    if (_platform == OtzariaTargetPlatform.macos) {
      final id =
          const MacAppVersionReader().readBundleIdentifier(candidatePath);
      return id != null && id.toLowerCase().endsWith('.otzaria');
    }
    return false;
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
