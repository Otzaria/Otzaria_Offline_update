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

/// שלב נפרד לגמרי מ-[LibraryModuleStatus] — ייצוא מראה offline הוא פעולה
/// יזומה בנפרד מבדיקת/החלת עדכון רגילה, ויכולה לרוץ גם כש-status הרגיל
/// הוא upToDate (מייצאים "בשביל מישהו אחר", לא כי צריך עדכון בעצמנו).
enum MirrorExportStatus { idle, exporting, done, error }

/// עוטף את [LibraryManager] כמצב הניתן לצפייה עבור מסך הדשבורד — בדיקת
/// גרסת מסד, בקשת נתיב ידני כשלא נמצא DB, **הורדה לתיקייה מקומית בלבד**
/// (ללא patch/apply על ה-DB החי), והחלפה בין מקור ה-cloud למראה מקומית
/// (offline) לצד ייצוא מראה כזו.
class LibraryModuleController extends ChangeNotifier {
  LibraryModuleController({required String dataDir})
      : _manager = LibraryManager(dataDir: dataDir);

  final LibraryManager _manager;
  LibraryUpdateCheckResult? _lastCheck;

  LibraryModuleStatus status = LibraryModuleStatus.idle;
  int? localVersion;
  int? targetVersion;
  String? stageText;
  String? errorMessage;

  /// `true` אם checkForUpdate האחרון זיהה שאין DB בכלל עדיין (התקנה
  /// טרייה) — ה-UI יכול להציג "מוריד ספרייה בפעם הראשונה" במקום "מעדכן".
  bool isFreshInstall = false;

  /// נתיב המראה המקומית הפעילה כרגע, או null אם מצב ה-cloud פעיל.
  /// מתעדכן דרך [refreshSourceMode], שנקרא גם מ-[checkForUpdate].
  String? activeMirrorPath;

  /// מצב ייצוא מראה offline **ידני** (יעד שהמשתמש בחר בעצמו) — נפרד
  /// מ-[status] (ראו [MirrorExportStatus]).
  MirrorExportStatus mirrorExportStatus = MirrorExportStatus.idle;
  String? mirrorExportStage;
  int? mirrorExportDoneAssets;
  int? mirrorExportTotalAssets;
  String? mirrorExportError;

  /// נתיב ה-cache הקבוע (`<dataDir>/offline-mirror`) — מתעדכן אוטומטית
  /// ברקע בכל פתיחת האפליקציה (ראו [refreshOfflineMirrorCacheInBackground],
  /// שנקרא מה-dashboard) ומוכן תמיד להעברה למחשב אחר (USB / תיקייה
  /// משותפת) בלי צורך לבחור יעד או ללחוץ על כלום.
  String get offlineMirrorCacheDir => _manager.offlineMirrorCacheDir;

  /// מצב הרענון **האוטומטי** של [offlineMirrorCacheDir] — נפרד מ-
  /// [mirrorExportStatus] כדי לא להתנגש עם ייצוא ידני יזום.
  MirrorExportStatus autoCacheStatus = MirrorExportStatus.idle;
  String? autoCacheStage;
  String? autoCacheError;
  DateTime? autoCacheLastRefreshedAt;

  /// מרענן ברקע את [offlineMirrorCacheDir] מהענן. best-effort ולא זורק:
  /// כישלון (בעיקר אין אינטרנט) פשוט משאיר את ה-cache כפי שהיה מהרענון
  /// הקודם — לא אמור להפריע לשום דבר אחר. נקרא אוטומטית בכל פתיחת
  /// האפליקציה מה-dashboard, במקביל ל-[checkForUpdate] (לא לפניו/אחריו).
  Future<void> refreshOfflineMirrorCacheInBackground() async {
    autoCacheStatus = MirrorExportStatus.exporting;
    autoCacheStage = null;
    autoCacheError = null;
    notifyListeners();

    try {
      await _manager.refreshOfflineMirrorCache(
        onStage: (stage) {
          autoCacheStage = stage;
          notifyListeners();
        },
      );
      autoCacheStatus = MirrorExportStatus.done;
      autoCacheLastRefreshedAt = DateTime.now();
    } catch (e) {
      autoCacheStatus = MirrorExportStatus.error;
      autoCacheError = e.toString();
    }
    notifyListeners();
  }

  Future<void> refreshSourceMode() async {
    activeMirrorPath = await _manager.currentLocalMirrorPath();
    notifyListeners();
  }

  Future<void> checkForUpdate() async {
    status = LibraryModuleStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      activeMirrorPath = await _manager.currentLocalMirrorPath();
      final check = await _manager.checkForUpdate();
      _lastCheck = check;
      isFreshInstall = check.isFreshInstall;

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

  /// עובר לעדכון ממראה מקומית (offline) בתיקייה [mirrorDir], ומריץ בדיקת
  /// עדכון מיידית מהמקור החדש.
  Future<void> useLocalMirror(String mirrorDir) async {
    await _manager.useLocalMirror(mirrorDir);
    await checkForUpdate();
  }

  /// חוזר לעדכון מהענן (GitHub), ומריץ בדיקת עדכון מיידית מהמקור החדש.
  Future<void> useCloud() async {
    await _manager.useCloud();
    await checkForUpdate();
  }

  /// בונה מראה מקומית מלאה (מה-cloud) לתיקייה [destDir] — להעברה למחשב
  /// בלי אינטרנט (USB / תיקייה משותפת). דורש אינטרנט בעצמו, ללא קשר
  /// למקור הפעיל כרגע.
  Future<void> exportOfflineMirror(String destDir) async {
    mirrorExportStatus = MirrorExportStatus.exporting;
    mirrorExportStage = null;
    mirrorExportDoneAssets = null;
    mirrorExportTotalAssets = null;
    mirrorExportError = null;
    notifyListeners();

    try {
      await _manager.exportOfflineMirror(
        destDir: destDir,
        onStage: (stage) {
          mirrorExportStage = stage;
          notifyListeners();
        },
        onAssetProgress: (done, total) {
          mirrorExportDoneAssets = done;
          mirrorExportTotalAssets = total;
          notifyListeners();
        },
      );
      mirrorExportStatus = MirrorExportStatus.done;
    } catch (e) {
      mirrorExportStatus = MirrorExportStatus.error;
      mirrorExportError = e.toString();
    }
    notifyListeners();
  }

  /// **לא מחיל שום דבר על ה-DB החי.** מוריד רק את ה-DB המלא העדכני ביותר
  /// (לא כל ההיסטוריה — לזה יש את [exportOfflineMirror] הנפרד, היקר
  /// יותר) לתיקייה מקומית קלה ([LibraryManager.latestDbDownloadDir]).
  /// התקנת הקובץ בפועל היא צעד נפרד ומכוון-ידית של המשתמש.
  Future<void> update() async {
    if (_lastCheck == null) return;

    status = LibraryModuleStatus.updating;
    stageText = null;
    notifyListeners();

    try {
      await _manager.downloadLatestDbToFolder(
        onStage: (stage) {
          stageText = stage;
          notifyListeners();
        },
      );
      status = LibraryModuleStatus.upToDate;
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
