import 'package:path/path.dart' as p;

import 'models/otzaria_install_state.dart';
import 'models/otzaria_update_check_result.dart';
import 'services/otzaria_installer.dart';
import 'services/otzaria_launcher.dart';
import 'services/otzaria_release_client.dart';
import 'services/otzaria_state_store.dart';

/// נקודת הכניסה היחידה שמודול ה-UI (הדשבורד ב-Flutter) אמור להשתמש בה.
/// מרכיב יחד את בדיקת ה-release, ההתקנה, השמירה וההפעלה, בלי שהצרכן
/// יצטרך להכיר את השירותים הפנימיים.
///
/// דוגמת שימוש:
/// ```dart
/// final manager = OtzariaManager(dataDir: r'C:\Users\me\AppData\Roaming\OurLauncher');
/// final check = await manager.checkForUpdate();
/// if (check.updateAvailable) {
///   await manager.update(check.latestRelease, onProgress: (r, t) => print('$r/$t'));
/// }
/// await manager.launch();
/// ```
class OtzariaManager {
  OtzariaManager({required String dataDir})
      : _stateStore = OtzariaStateStore(p.join(dataDir, 'otzaria_install_state.json')),
        _releaseClient = OtzariaReleaseClient(),
        _installer = OtzariaInstaller(managedInstallDir: p.join(dataDir, 'otzaria-app')),
        _launcher = const OtzariaLauncher();

  final OtzariaStateStore _stateStore;
  final OtzariaReleaseClient _releaseClient;
  final OtzariaInstaller _installer;
  final OtzariaLauncher _launcher;

  Future<OtzariaUpdateCheckResult> checkForUpdate() async {
    final latest = await _releaseClient.fetchLatestRelease();
    final current = await _stateStore.load();
    return OtzariaUpdateCheckResult(latestRelease: latest, currentState: current);
  }

  /// מוריד ומתקין את ה-release שהתקבל מ-[checkForUpdate], ושומר את מצב
  /// ההתקנה החדש לשימוש עתידי (כולל אחרי סגירה/פתיחה מחדש של הלאנצ'ר).
  Future<OtzariaInstallState> update(
    OtzariaUpdateCheckResult check, {
    void Function(int received, int total)? onProgress,
  }) async {
    final state = await _installer.downloadAndInstall(
      release: check.latestRelease,
      onDownloadProgress: onProgress,
    );
    await _stateStore.save(state);
    return state;
  }

  /// מפעיל את אוצריא לפי מצב ההתקנה השמור. זורק אם עדיין לא בוצעה אף
  /// התקנה (יש לקרוא ל-[update] קודם).
  Future<void> launch() async {
    final state = await _stateStore.load();
    if (state == null) {
      throw StateError('אוצריא עדיין לא הותקנה על ידי הלאנצ׳ר הזה.');
    }
    await _launcher.launch(state.exePath);
  }

  void close() {
    _releaseClient.close();
    _installer.close();
  }
}
