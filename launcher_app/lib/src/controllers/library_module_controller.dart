import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/app_logger.dart';

enum LibraryModuleStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  updating,
  error,
  needsManualPath,

  /// עדיין לא הורדו עדכונים לתיקייה המקומית — אין מול מה להשוות. מצב תקין
  /// בהרצה ראשונה, לא שגיאה.
  needsDownload,
}

/// מצב ההורדה מהרשת אל התיקייה המקומית. נפרד לגמרי מ-[LibraryModuleStatus]:
/// הורדה יכולה לרוץ גם כשהמסד המקומי מעודכן (מורידים בשביל המחשב האחר).
enum MirrorDownloadStatus { idle, downloading, done, error }

/// עוטף את [LibraryManager] כמצב הניתן לצפייה עבור הדשבורד. שתי פעולות
/// נפרדות לגמרי:
///  - [download] — מביא עדכונים מהרשת אל התיקייה שלצד התוכנה. **הפעולה
///    היחידה שדורשת אינטרנט.**
///  - [checkForUpdate] / [update] — קוראות מהתיקייה המקומית בלבד ומחילות
///    על ה-DB החי. עובדות במחשב בלי רשת בכלל.
class LibraryModuleController extends ChangeNotifier {
  LibraryModuleController({
    required String dataDir,
    bool allowPrerelease = false,
  }) : _manager = LibraryManager(
          dataDir: dataDir,
          allowPrerelease: allowPrerelease,
        );

  /// מחליף ערוץ גרסאות — נכנס לתוקף בבדיקה/הורדה הבאה.
  set allowPrerelease(bool value) => _manager.allowPrerelease = value;

  final LibraryManager _manager;
  LibraryUpdateCheckResult? _lastCheck;

  LibraryModuleStatus status = LibraryModuleStatus.idle;
  int? localVersion;
  int? targetVersion;
  String? stageText;

  /// 0..1 כשיש יעד ידוע (בייטים שהורדו/סה"כ), אחרת null (מד לא-קבוע).
  /// מתעדכן במהלך [update] בלבד.
  double? applyProgress;
  String? errorMessage;

  /// `true` אם checkForUpdate האחרון זיהה שאין DB בכלל עדיין (התקנה
  /// טרייה) — ה-UI יכול להציג "מוריד ספרייה בפעם הראשונה" במקום "מעדכן".
  bool isFreshInstall = false;

  /// נתיב ה-`seforim.db` שזוהה בפועל — מתעדכן בכל [checkForUpdate].
  String? dbPath;

  /// התיקייה שלצד התוכנה שממנה נקראים העדכונים — המקור היחיד.
  String get mirrorDir => _manager.mirrorDir;

  /// מצב ההורדה מהרשת אל [mirrorDir].
  MirrorDownloadStatus downloadStatus = MirrorDownloadStatus.idle;
  String? downloadStage;
  int? downloadDoneAssets;
  int? downloadTotalAssets;
  String? downloadError;
  DateTime? lastDownloadedAt;

  /// מוריד עדכוני ספרייה מהרשת אל [mirrorDir]. **הפעולה היחידה כאן שדורשת
  /// אינטרנט.** לא נוגעת ב-DB. לא זורקת — כשל נשמר ב-[downloadError].
  Future<void> download() async {
    downloadStatus = MirrorDownloadStatus.downloading;
    downloadStage = null;
    downloadDoneAssets = null;
    downloadTotalAssets = null;
    downloadError = null;
    notifyListeners();

    try {
      await _manager.downloadToMirror(
        onStage: (stage) {
          downloadStage = stage;
          notifyListeners();
        },
        onAssetProgress: (done, total) {
          downloadDoneAssets = done;
          downloadTotalAssets = total;
          notifyListeners();
        },
      );
      downloadStatus = MirrorDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      notifyListeners();
      // עכשיו יש מול מה להשוות — מרעננים את מצב העדכון מהתיקייה החדשה.
      await checkForUpdate();
      return;
    } catch (e, st) {
      downloadStatus = MirrorDownloadStatus.error;
      downloadError = e.toString();
      AppLogger.instance.error('הורדת עדכוני ספרייה נכשלה', e, st);
    }
    notifyListeners();
  }

  Future<void> checkForUpdate() async {
    status = LibraryModuleStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      dbPath = await _manager.currentDbPath();
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
    } on LibraryMirrorMissingException {
      // אין מראה = טרם הורד דבר. מצב תקין, לא שגיאה — ולכן לא נרשם ללוג
      // ולא מוצג כתקלה.
      status = LibraryModuleStatus.needsDownload;
      localVersion = null;
      targetVersion = null;
    } catch (e, st) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('checkForUpdate נכשל', e, st);
    }
    notifyListeners();
  }

  Future<void> setCustomDbPath(String dbPath) async {
    await _manager.setCustomDbPath(dbPath);
    await checkForUpdate();
  }

  /// מחיל בפועל את העדכון על ה-DB **החי** — delta patch-אחר-patch, או
  /// הורדת DB מלא, דרך [LibraryManager.applyUpdate]. בהצלחה, ה-DB של
  /// אוצריא כבר מעודכן בפועל ואין שום פעולה נוספת שהמשתמש צריך לעשות.
  ///
  /// זורק (ונתפס כאן כ-[LibraryModuleStatus.error]) בעיקר: `OtzariaIsRunningException`
  /// אם אוצריא פתוחה כרגע (בווינדוס), או `LibraryApplyException`
  /// על כשל הורדה/אימות/כתיבה — בשני המקרים ה-`toString()` של החריג
  /// כבר מנוסח כהודעה קריאה למשתמש, ומוצג ישירות ב-[errorMessage].
  Future<void> update() async {
    if (_lastCheck == null) return;

    status = LibraryModuleStatus.updating;
    stageText = null;
    applyProgress = null;
    errorMessage = null;
    notifyListeners();

    final plan = _lastCheck!.plan;
    AppLogger.instance.info(
      'update() מתחיל: kind=${plan?.kind} local=${plan?.localVersion} target=${plan?.targetVersion}',
    );

    try {
      await _manager.applyUpdate(
        _lastCheck!,
        onProgress: (p) {
          stageText = _describeApplyStage(p);
          applyProgress = (p.bytesDownloaded != null &&
                  p.bytesTotal != null &&
                  p.bytesTotal! > 0)
              ? p.bytesDownloaded! / p.bytesTotal!
              : null;
          notifyListeners();
        },
      );
      AppLogger.instance.info('update() הסתיים בהצלחה');
      // מרעננים את מצב הבדיקה עצמו (localVersion/targetVersion/status) —
      // עדיף על קביעה ידנית של upToDate, כי זה קורא בפועל את הגרסה
      // שנכתבה ל-DB במקום להניח שהיא תואמת ליעד.
      await checkForUpdate();
    } catch (e, st) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('update() נכשל', e, st);
    }
    notifyListeners();
  }

  String _describeApplyStage(LibraryApplyProgress p) {
    final step = (p.stepIndex != null && p.stepCount != null)
        ? ' (${p.stepIndex}/${p.stepCount})'
        : '';
    switch (p.stage) {
      case LibraryApplyStage.downloadingPatch:
        return 'מוריד עדכון$step...';
      case LibraryApplyStage.applyingPatch:
        return 'מחיל עדכון על המסד$step...';
      case LibraryApplyStage.downloadingFullDb:
        return 'מוריד מסד מלא...';
      case LibraryApplyStage.decompressingFullDb:
        return 'מחלץ את המסד...';
      case LibraryApplyStage.writingFullDb:
        return 'כותב את המסד...';
      case LibraryApplyStage.verifying:
        return 'מוודא תקינות...';
      case LibraryApplyStage.done:
        return 'הושלם.';
    }
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
