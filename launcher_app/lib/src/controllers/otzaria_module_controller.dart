import 'package:flutter/foundation.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import '../services/app_logger.dart';

enum OtzariaModuleStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  updating,
  error
}

/// עוטף את [OtzariaManager] כמצב הניתן לצפייה עבור מסך הדשבורד — בדיקת
/// עדכון, התקנה/עדכון עם התקדמות, והפעלת אוצריא.
class OtzariaModuleController extends ChangeNotifier {
  OtzariaModuleController({required String dataDir})
      : _manager = OtzariaManager(dataDir: dataDir);

  final OtzariaManager _manager;
  OtzariaUpdateCheckResult? _lastCheck;

  OtzariaModuleStatus status = OtzariaModuleStatus.idle;
  String? currentVersion;
  String? latestVersion;
  int? downloadReceived;
  int? downloadTotal;
  String? errorMessage;

  bool get canLaunch => currentVersion != null;

  Future<void> checkForUpdate() async {
    status = OtzariaModuleStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      final check = await _manager.checkForUpdate();
      _lastCheck = check;
      currentVersion = check.currentState?.installedTagName;
      latestVersion = check.latestRelease.tagName;
      status = check.updateAvailable
          ? OtzariaModuleStatus.updateAvailable
          : OtzariaModuleStatus.upToDate;
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance
          .error('OtzariaModuleController.checkForUpdate נכשל', e, st);
    }
    notifyListeners();
  }

  Future<void> update() async {
    final check = _lastCheck;
    if (check == null) return;

    status = OtzariaModuleStatus.updating;
    downloadReceived = null;
    downloadTotal = null;
    notifyListeners();
    AppLogger.instance.info(
      'OtzariaModuleController.update() מתחיל: ${check.currentState?.installedTagName} -> ${check.latestRelease.tagName}',
    );

    try {
      final state = await _manager.update(
        check,
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyListeners();
        },
      );
      currentVersion = state.installedTagName;
      status = OtzariaModuleStatus.upToDate;
      AppLogger.instance.info('OtzariaModuleController.update() הסתיים בהצלחה');
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('OtzariaModuleController.update() נכשל', e, st);
    }
    notifyListeners();
  }

  Future<void> launch() async {
    try {
      await _manager.launch();
    } catch (e, st) {
      errorMessage = e.toString();
      AppLogger.instance.error('OtzariaModuleController.launch() נכשל', e, st);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _manager.close();
    super.dispose();
  }
}
