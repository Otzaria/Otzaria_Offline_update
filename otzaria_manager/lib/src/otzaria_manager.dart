import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

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
    this.preferPrerelease = false,
  })  : _platform =
            platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem),
        _environment = environment ?? Platform.environment,
        _stateStore =
            OtzariaStateStore(p.join(dataDir, 'otzaria_install_state.json')),
        _launcher = const OtzariaLauncher(),
        _appLocator = OtzariaAppLocator(platform: platform),
        _versionReader = installedVersionReaderFor(
          platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem),
        ),
        _defaultInstallDir = p.join(dataDir, 'otzaria-app'),
        mirrorDir = p.join(dataDir, 'mirror', 'app') {
    _releaseClient = OtzariaReleaseClient(platform: platform);
    _changelogClient = OtzariaChangelogClient();
    _installer = OtzariaInstaller(
      defaultInstallDir: _defaultInstallDir,
      // קובצי ההתקנה יושבים **בתוך** המראה, כדי שהמטא־דאטה והקובץ ייסעו
      // יחד על הכונן הנייד.
      cacheDir: p.join(mirrorDir, 'installers'),
      appLocator: OtzariaAppLocator(platform: platform),
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
  final OtzariaAppLocator _appLocator;
  final InstalledVersionReader _versionReader;
  final String _defaultInstallDir;

  /// תיקיית האפליקציות הסטנדרטית של macOS. ב-macOS, בשונה מווינדוס,
  /// למשתמש שהתקין את אוצריא בעצמו היא כמעט תמיד תהיה שם — גרירת ה-`.app`
  /// ל-`/Applications` היא *הדרך* להתקין. לכן שווה להציץ שם לפני שמתקינים
  /// עותק שני בתיקייה המנוהלת של הלאנצ'ר.
  static const String _macApplicationsDir = '/Applications';

  /// גיבוי משני בווינדוס — לא ברירת המחדל האמיתית. ייתכן שזה עדיין נכון
  /// בהתקנות ישנות (אומת מול מפתחי אוצריא: "אם קיימת התקנה קודמת — המתקין
  /// נשאר בנתיב שלה, למשל C:\אוצריא או {Program Files}\אוצריא").
  static const String _legacyWindowsInstallDir = r'C:\אוצריא';

  /// ברירת המחדל האמיתית של installer-ה-Inno Setup של אוצריא בווינדוס —
  /// **אומת מול מפתחי אוצריא** (לא ניחוש): `{autopf}\Otzaria`, כלומר
  /// `%LocalAppData%\Programs\Otzaria` בהתקנה למשתמש הנוכחי (ברירת המחדל),
  /// או `%ProgramFiles%\Otzaria` בהתקנה לכל המשתמשים (כמנהל). שתיהן
  /// תיקיות ייעודיות לאוצריא בלבד — לא "משותפות" כמו `/Applications`.
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

  /// התיקיות שבהן מחפשים התקנה קיימת כשאין עדיין state שמור, לפי סדר
  /// עדיפות. התיקייה המנוהלת של הלאנצ'ר תמיד ראשונה (אם הלאנצ'ר עצמו
  /// התקין, זה המקור הסמכותי); אחריה מיקומי ברירת המחדל האמיתיים של
  /// אוצריא בפלטפורמה. ב-macOS `/Applications` בא **אחרון**, כדי שהתקנה
  /// שהלאנצ'ר עשה בעצמו תמיד תנצח.
  ///
  /// `sharedDir` מסמן תיקייה שיש בה גם אפליקציות אחרות — ראו
  /// [_verifyIsOtzaria].
  List<({String dir, bool sharedDir})> get _autoDetectDirs =>
      switch (_platform) {
        OtzariaTargetPlatform.windows => [
            (dir: _defaultInstallDir, sharedDir: false),
            ..._windowsRealDefaultDirs,
          ],
        OtzariaTargetPlatform.macos => [
            (dir: _defaultInstallDir, sharedDir: false),
            (dir: _macApplicationsDir, sharedDir: true),
          ],
      };

  /// מוריד את הגרסאות האחרונות אל המראה המקומית — **הפעולה הכבדה** שנוגעת
  /// ברשת (מוריד את קובצי ההתקנה עצמם). לא מתקין כלום.
  ///
  /// מוריד **את שתי הגרסאות**: היציבה, ובנוסף ה-pre-release כשהוא חדש
  /// ממנה. כך במחשב המנותק אפשר לבחור ביניהן בלי לחזור לרשת.
  Future<void> downloadToMirror({
    void Function(int received, int total)? onProgress,
    void Function(OtzariaReleaseChannel channel)? onChannel,
  }) =>
      _mirror.sync(
        onDownloadProgress: onProgress,
        onChannelStart: onChannel,
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
      throw StateError('לא נמצאה גרסת אוצריא שניתן להתקין בפלטפורמה הזו.');
    }
    final changelogNotes = await _changelogClient.notesFor(release.tagName);
    return changelogNotes == null
        ? release
        : release.copyWithReleaseNotes(changelogNotes);
  }

  /// בודק אם יש עדכון זמין — **מהמראה המקומית בלבד, בלי רשת**. אם עדיין אין
  /// state שמור (אף פעם לא הותקן/אומץ דרך הלאנצ'ר הזה), מנסה קודם לזהות
  /// התקנה קיימת במיקומים המוכרים ([_autoDetectDirs]) — לא סורק את כל
  /// המחשב — כדי לא "לשכוח" התקנה שכבר קיימת שם מסשן קודם.
  ///
  /// [OtzariaUpdateCheckResult.latestRelease] הוא `null` כשעדיין לא הורדה
  /// שום גרסה. זה לא כשל: זה אומר "יש להריץ הורדה במחשב עם אינטרנט".
  Future<OtzariaUpdateCheckResult> checkForUpdate() async {
    final mirrored = await _mirror.load();
    var current = await _stateStore.load();

    for (final candidate in _autoDetectDirs) {
      if (current != null) break;
      current = await detectExistingInstall(
        customDir: candidate.dir,
        isSharedDir: candidate.sharedDir,
      );
    }

    return OtzariaUpdateCheckResult(
      stableRelease: mirrored.stable?.release,
      prereleaseRelease: mirrored.prerelease?.release,
      preferPrerelease: preferPrerelease,
      currentState: current,
    );
  }

  /// מתקין את הגרסה שיושבת במראה המקומית **בערוץ שנבחר**
  /// ([preferPrerelease]). אם יש כבר מצב מוכר (מותקן/מאומץ קודם), מעדכן
  /// **באותה תיקייה** — לא יוצר התקנה שנייה בתיקייה המנוהלת. שומר את מצב
  /// ההתקנה החדש לשימוש עתידי.
  ///
  /// לא נוגע ברשת. זורק [StateError] אם אין מראה — כלומר לא בוצעה הורדה.
  Future<OtzariaInstallState> update(OtzariaUpdateCheckResult check) async {
    final mirrored = await _mirror.load();
    final selected = mirrored.select(preferPrerelease: preferPrerelease);
    if (selected == null) {
      throw StateError(
        'אין גרסת אוצריא בתיקייה המקומית — יש להריץ הורדה במחשב עם אינטרנט.',
      );
    }

    final state = await _installer.installFromFile(
      release: selected.release,
      installerPath: selected.installerPath,
      targetInstallDir: check.currentState?.installDir,
      // שתי הגרסאות נשארות בכונן: התקנת אחת מהן לא מוחקת את קובץ ההתקנה
      // של השנייה, כדי שאפשר יהיה להחליף ערוץ בלי הורדה מחדש.
      keepCachedTagNames: {
        for (final entry in mirrored.all) entry.release.tagName,
      },
    );
    await _stateStore.save(state);
    return state;
  }

  /// מפעיל את אוצריא לפי מצב ההתקנה השמור. זורק אם עדיין לא בוצעה אף
  /// התקנה/אימוץ (יש לקרוא ל-[update] או ל-[adoptExistingInstall] קודם).
  Future<void> launch() async {
    final state = await _stateStore.load();
    if (state == null) {
      throw StateError('אוצריא עדיין לא הותקנה על ידי הלאנצ׳ר הזה.');
    }
    await _launcher.launch(state.launchPath);
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

  /// האם [candidatePath] הוא בכלל אוצריא. נבדק לפי שם החבילה, ואם זה לא
  /// מכריע — לפי `CFBundleIdentifier` ב-macOS (`com.example.otzaria` בבנייה
  /// הנוכחית; ההשוואה היא על הסיומת `.otzaria` כדי שגם תיקון עתידי של
  /// המזהה, למשל ל-`org.otzaria.otzaria`, ימשיך לעבוד).
  bool _verifyIsOtzaria(String candidatePath) {
    final name = p.basenameWithoutExtension(candidatePath).toLowerCase();
    if (name.contains('otzaria') || name.contains('אוצריא')) return true;

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

  void close() {
    _releaseClient.close();
    _changelogClient.close();
    _installer.close();
  }
}
