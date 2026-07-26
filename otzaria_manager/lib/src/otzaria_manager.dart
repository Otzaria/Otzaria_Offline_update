import 'package:path/path.dart' as p;

import 'models/otzaria_install_state.dart';
import 'models/otzaria_update_check_result.dart';
import 'services/otzaria_exe_locator.dart';
import 'services/otzaria_installer.dart';
import 'services/otzaria_launcher.dart';
import 'services/otzaria_release_client.dart';
import 'services/otzaria_state_store.dart';
import 'services/windows_exe_version_reader.dart';

/// נקודת הכניסה היחידה שמודול ה-UI (הדשבורד ב-Flutter) אמור להשתמש בה.
/// מרכיב יחד את בדיקת ה-release, ההתקנה, השמירה, הזיהוי וההפעלה, בלי
/// שהצרכן יצטרך להכיר את השירותים הפנימיים.
///
/// דוגמת שימוש (התקנה טרייה או עדכון רגיל):
/// ```dart
/// final manager = OtzariaManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');
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
  OtzariaManager({required String dataDir})
      : _stateStore = OtzariaStateStore(p.join(dataDir, 'otzaria_install_state.json')),
        _releaseClient = OtzariaReleaseClient(),
        _installer = OtzariaInstaller(
          defaultInstallDir: p.join(dataDir, 'otzaria-app'),
          cacheDir: p.join(dataDir, 'cache', 'otzaria'),
        ),
        _launcher = const OtzariaLauncher(),
        _exeLocator = const OtzariaExeLocator(),
        _versionReader = const WindowsExeVersionReader(),
        _defaultInstallDir = p.join(dataDir, 'otzaria-app');

  final OtzariaStateStore _stateStore;
  final OtzariaReleaseClient _releaseClient;
  final OtzariaInstaller _installer;
  final OtzariaLauncher _launcher;
  final OtzariaExeLocator _exeLocator;
  final WindowsExeVersionReader _versionReader;
  final String _defaultInstallDir;

  /// בודק אם יש עדכון זמין. אם עדיין אין state שמור (אף פעם לא הותקן/
  /// אומץ דרך הלאנצ'ר הזה), מנסה קודם לזהות התקנה קיימת במיקום ברירת
  /// המחדל של הלאנצ'ר עצמו (לא סורק את כל המחשב) — כדי לא "לשכוח"
  /// התקנה שכבר קיימת שם מסשן קודם.
  Future<OtzariaUpdateCheckResult> checkForUpdate() async {
    final latest = await _releaseClient.fetchLatestRelease();
    var current = await _stateStore.load();
    current ??= await detectExistingInstall(customDir: _defaultInstallDir);

    return OtzariaUpdateCheckResult(latestRelease: latest, currentState: current);
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
    await _launcher.launch(state.exePath);
  }

  /// מחפש התקנה קיימת של אוצריא בתיקייה נתונה (למשל תיקייה שהמשתמש
  /// הצביע עליה ידנית, כי הוא כבר התקין את אוצריא במיקום משלו לפני
  /// שהתחיל להשתמש בלאנצ'ר הזה). קורא את הגרסה ישירות מתוך ה-exe
  /// (Windows version resource) — לא מסתמך על מה שהלאנצ'ר עצמו "זוכר".
  ///
  /// מחזיר null אם לא נמצא exe בתיקייה, או שנמצא אך לא ניתן לקרוא ממנו
  /// גרסה (למשל אם זו לא בכלל התקנה של אוצריא).
  Future<OtzariaInstallState?> detectExistingInstall({required String customDir}) async {
    final exePath = await _exeLocator.findExeIn(customDir);
    if (exePath == null) return null;

    final version = _versionReader.readProductVersion(exePath);
    if (version == null) return null;

    return OtzariaInstallState(
      installedTagName: version,
      installDir: customDir,
      exePath: exePath,
    );
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
