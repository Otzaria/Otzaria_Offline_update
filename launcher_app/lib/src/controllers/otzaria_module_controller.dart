import 'package:flutter/foundation.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import '../services/app_logger.dart';

enum OtzariaModuleStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  installing,
  error,

  /// עדיין לא הורדה שום גרסה לתיקייה המקומית — אין מה להתקין. מצב תקין
  /// בהרצה ראשונה, לא שגיאה.
  needsDownload,
}

/// מצב ההורדה מהרשת אל התיקייה המקומית, נפרד מ-[OtzariaModuleStatus].
enum OtzariaDownloadStatus { idle, downloading, done, error }

/// עוטף את [OtzariaManager] כמצב הניתן לצפייה עבור הדשבורד. שתי פעולות
/// נפרדות: [download] מביא גרסה מהרשת אל התיקייה שלצד התוכנה (הפעולה
/// היחידה שדורשת אינטרנט), ו-[install] מתקין ממנה — גם בלי רשת.
class OtzariaModuleController extends ChangeNotifier {
  OtzariaModuleController({
    required String dataDir,
    bool allowPrerelease = false,
  }) : _manager = OtzariaManager(
          dataDir: dataDir,
          allowPrerelease: allowPrerelease,
        );

  final OtzariaManager _manager;
  OtzariaUpdateCheckResult? _lastCheck;

  /// מחליף ערוץ גרסאות — נכנס לתוקף בהורדה הבאה.
  set allowPrerelease(bool value) => _manager.allowPrerelease = value;

  OtzariaModuleStatus status = OtzariaModuleStatus.idle;
  String? currentVersion;

  /// הגרסה שיושבת בתיקייה המקומית ומוכנה להתקנה, או null אם טרם הורדה.
  String? latestVersion;
  String? errorMessage;

  OtzariaDownloadStatus downloadStatus = OtzariaDownloadStatus.idle;
  int? downloadReceived;
  int? downloadTotal;
  String? downloadError;
  DateTime? lastDownloadedAt;

  bool get canLaunch => currentVersion != null;

  /// מוריד את הגרסה האחרונה מהרשת אל התיקייה המקומית. לא מתקין.
  Future<void> download() async {
    downloadStatus = OtzariaDownloadStatus.downloading;
    downloadReceived = null;
    downloadTotal = null;
    downloadError = null;
    notifyListeners();

    try {
      await _manager.downloadToMirror(
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyListeners();
        },
      );
      downloadStatus = OtzariaDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      notifyListeners();
      await checkForUpdate();
      return;
    } catch (e, st) {
      downloadStatus = OtzariaDownloadStatus.error;
      downloadError = e.toString();
      AppLogger.instance.error('הורדת גרסת אוצריא נכשלה', e, st);
    }
    notifyListeners();
  }

  /// בודק מה מותקן מול מה שיש בתיקייה המקומית. לא נוגע ברשת.
  Future<void> checkForUpdate() async {
    status = OtzariaModuleStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      final check = await _manager.checkForUpdate();
      _lastCheck = check;
      currentVersion = check.currentState?.installedTagName;
      latestVersion = check.latestRelease?.tagName;
      status = switch (check) {
        _ when check.needsDownload => OtzariaModuleStatus.needsDownload,
        _ when check.updateAvailable => OtzariaModuleStatus.updateAvailable,
        _ => OtzariaModuleStatus.upToDate,
      };
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance
          .error('OtzariaModuleController.checkForUpdate נכשל', e, st);
    }
    notifyListeners();
  }

  /// מתקין את הגרסה שבתיקייה המקומית. לא נוגע ברשת.
  Future<void> install() async {
    final check = _lastCheck;
    if (check == null) return;

    status = OtzariaModuleStatus.installing;
    errorMessage = null;
    notifyListeners();
    AppLogger.instance.info(
      'התקנת אוצריא מתחילה: ${check.currentState?.installedTagName} -> '
      '${check.latestRelease?.tagName}',
    );

    try {
      final state = await _manager.update(check);
      currentVersion = state.installedTagName;
      status = OtzariaModuleStatus.upToDate;
      AppLogger.instance.info('התקנת אוצריא הסתיימה בהצלחה');
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('התקנת אוצריא נכשלה', e, st);
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
