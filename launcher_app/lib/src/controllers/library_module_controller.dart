import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

enum LibraryModuleStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  updating,
  error,
  needsManualPath,
}

/// עוטף את [LibraryManager] כמצב הניתן לצפייה עבור מסך הדשבורד — בדיקת
/// עדכון למסד, בקשת נתיב ידני כשלא נמצא DB, והחלת העדכון עם התקדמות.
class LibraryModuleController extends ChangeNotifier {
  LibraryModuleController({required String dataDir})
      : _manager = LibraryManager(dataDir: dataDir);

  final LibraryManager _manager;
  LibraryUpdateCheckResult? _lastCheck;

  LibraryModuleStatus status = LibraryModuleStatus.idle;
  int? localVersion;
  int? targetVersion;
  String? stageText;
  int? downloadReceived;
  int? downloadTotal;
  String? errorMessage;

  Future<void> checkForUpdate() async {
    status = LibraryModuleStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      final check = await _manager.checkForUpdate();
      _lastCheck = check;

      if (check.needsManualDbPath) {
        status = LibraryModuleStatus.needsManualPath;
      } else {
        localVersion = check.localVersion?.dbVersion;
        targetVersion = check.plan?.targetVersion;

        if (check.plan?.kind == LibraryUpdatePlanKind.blocked) {
          status = LibraryModuleStatus.error;
          errorMessage = check.plan?.reason ?? 'מצב חסום — נדרשת פעולה ידנית.';
        } else {
          status = check.updateAvailable
              ? LibraryModuleStatus.updateAvailable
              : LibraryModuleStatus.upToDate;
        }
      }
    } catch (e) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> setCustomDbPath(String dbPath) async {
    await _manager.setCustomDbPath(dbPath);
    await checkForUpdate();
  }

  Future<void> update() async {
    final check = _lastCheck;
    if (check == null) return;

    status = LibraryModuleStatus.updating;
    downloadReceived = null;
    downloadTotal = null;
    stageText = null;
    notifyListeners();

    try {
      await _manager.applyUpdate(
        check,
        onStage: (stage) {
          stageText = stage;
          notifyListeners();
        },
        onDownloadProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyListeners();
        },
      );
      status = LibraryModuleStatus.upToDate;
    } on OtzariaIsRunningException catch (e) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
    } catch (e) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
