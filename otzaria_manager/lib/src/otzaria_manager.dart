import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

import 'models/otzaria_install_state.dart';
import 'models/otzaria_release.dart';
import 'models/otzaria_update_check_result.dart';
import 'services/installed_version_reader.dart';
import 'services/mac_app_version_reader.dart';
import 'services/otzaria_app_locator.dart';
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
  OtzariaManager({required String dataDir, OtzariaTargetPlatform? platform})
      : _platform =
            platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem),
        _stateStore =
            OtzariaStateStore(p.join(dataDir, 'otzaria_install_state.json')),
        _releaseClient = OtzariaReleaseClient(platform: platform),
        _installer = OtzariaInstaller(
          defaultInstallDir: p.join(dataDir, 'otzaria-app'),
          cacheDir: p.join(dataDir, 'cache', 'otzaria'),
          appLocator: OtzariaAppLocator(platform: platform),
        ),
        _launcher = const OtzariaLauncher(),
        _appLocator = OtzariaAppLocator(platform: platform),
        _versionReader = installedVersionReaderFor(
          platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem),
        ),
        _defaultInstallDir = p.join(dataDir, 'otzaria-app');

  final OtzariaTargetPlatform _platform;
  final OtzariaStateStore _stateStore;
  final OtzariaReleaseClient _releaseClient;
  final OtzariaInstaller _installer;
  final OtzariaLauncher _launcher;
  final OtzariaAppLocator _appLocator;
  final InstalledVersionReader _versionReader;
  final String _defaultInstallDir;

  /// תיקיית האפליקציות הסטנדרטית של macOS. ב-macOS, בשונה מווינדוס,
  /// למשתמש שהתקין את אוצריא בעצמו היא כמעט תמיד תהיה שם — גרירת ה-`.app`
  /// ל-`/Applications` היא *הדרך* להתקין. לכן שווה להציץ שם לפני שמתקינים
  /// עותק שני בתיקייה המנוהלת של הלאנצ'ר.
  static const String _macApplicationsDir = '/Applications';

  /// התיקיות שבהן מחפשים התקנה קיימת כשאין עדיין state שמור, לפי סדר
  /// עדיפות. ב-macOS `/Applications` בא **אחרי** התיקייה המנוהלת, כדי
  /// שהתקנה שהלאנצ'ר עשה בעצמו תמיד תנצח.
  ///
  /// `sharedDir` מסמן תיקייה שיש בה גם אפליקציות אחרות — ראו
  /// [_verifyIsOtzaria].
  List<({String dir, bool sharedDir})> get _autoDetectDirs =>
      switch (_platform) {
        OtzariaTargetPlatform.windows => [
            (dir: _defaultInstallDir, sharedDir: false),
          ],
        OtzariaTargetPlatform.macos => [
            (dir: _defaultInstallDir, sharedDir: false),
            (dir: _macApplicationsDir, sharedDir: true),
          ],
      };

  /// בודק אם יש עדכון זמין. אם עדיין אין state שמור (אף פעם לא הותקן/
  /// אומץ דרך הלאנצ'ר הזה), מנסה קודם לזהות התקנה קיימת במיקומים
  /// המוכרים ([_autoDetectDirs]) — לא סורק את כל המחשב — כדי לא "לשכוח"
  /// התקנה שכבר קיימת שם מסשן קודם.
  Future<OtzariaUpdateCheckResult> checkForUpdate() async {
    final latest = await _releaseClient.fetchLatestRelease();
    var current = await _stateStore.load();

    for (final candidate in _autoDetectDirs) {
      if (current != null) break;
      current = await detectExistingInstall(
        customDir: candidate.dir,
        isSharedDir: candidate.sharedDir,
      );
    }

    return OtzariaUpdateCheckResult(
        latestRelease: latest, currentState: current);
  }

  /// מוריד ומתקין את ה-release שהתקבל מ-[checkForUpdate]. אם יש כבר מצב
  /// מוכר (מותקן/מאומץ קודם), מעדכן **באותה תיקייה** — לא יוצר התקנה
  /// שנייה בתיקייה המנוהלת. שומר את מצב ההתקנה החדש לשימוש עתידי.
  Future<OtzariaInstallState> update(
    OtzariaUpdateCheckResult check, {
    void Function(int received, int total)? onProgress,
  }) async {
    final state = await _installer.downloadAndInstall(
      release: check.latestRelease,
      targetInstallDir: check.currentState?.installDir,
      onDownloadProgress: onProgress,
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
    _installer.close();
  }
}
