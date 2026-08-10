import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/app_logger.dart';
import 'progress_notifier.dart';

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
class LibraryModuleController extends ChangeNotifier with ProgressNotifier {
  LibraryModuleController({
    required String dataDir,
    bool allowPrerelease = false,
    Future<String?> Function()? otzariaLaunchPath,
  }) : _manager = LibraryManager(
          dataDir: dataDir,
          allowPrerelease: allowPrerelease,
          otzariaLaunchPath: otzariaLaunchPath,
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

  /// הבייטים עצמם של השלב הנוכחי ב-[update] — לתצוגת "כמה מתוך כמה".
  /// `null` בשלבים שאינם הורדה (החלת patch, אימות).
  int? applyReceivedBytes;
  int? applyTotalBytes;
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

  /// בייטים שהורדו/סה"כ **בנכס שיורד כרגע**. בלי זה המד נשען על ספירת
  /// הנכסים בלבד, והמסד המלא (~1GB בקובץ אחד) השאיר אותו תקוע על אותו
  /// אחוז לאורך כל ההורדה.
  int? downloadReceivedBytes;
  int? downloadTotalBytes;
  String? downloadError;
  DateTime? lastDownloadedAt;

  /// 0..1 להורדה כולה: הנכסים שכבר הושלמו ועוד החלק היחסי של הנוכחי.
  /// כשעוד לא ידוע מספר הנכסים — מתקדם לפי הבייטים של הנכס הנוכחי בלבד.
  double? get downloadProgress {
    final received = downloadReceivedBytes;
    final bytesTotal = downloadTotalBytes;
    final inAsset = (received != null && bytesTotal != null && bytesTotal > 0)
        ? (received / bytesTotal).clamp(0.0, 1.0)
        : null;

    final totalAssets = downloadTotalAssets;
    if (totalAssets == null || totalAssets <= 0) return inAsset;
    final done = downloadDoneAssets ?? 0;
    return ((done + (inAsset ?? 0)) / totalAssets).clamp(0.0, 1.0);
  }

  /// מצב הבדיקה הקלה ("יש עדכון ברשת?") — נפרד לגמרי מ-[downloadStatus]:
  /// היא לא מורידה כלום, רק שואלת. `null` = טרם נבדק בהרצה הזו.
  int? onlineLatestVersion;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  /// `true` אם הבדיקה הקלה מצאה ברשת גרסה גבוהה מזו שיושבת **במראה
  /// המקומית**. [targetVersion] הוא הגרסה האחרונה שבמראה (התוכנית מחזירה
  /// אותה גם כשאין מה לעדכן), ולכן הוא הבסיס להשוואה — לא גרסת המסד החי,
  /// שההתקנה מעדכנת בשלב נפרד לגמרי מההורדה.
  bool get hasOnlineUpdate {
    final online = onlineLatestVersion;
    if (online == null) return false;
    final mirrored = targetVersion ?? localVersion ?? 0;
    return online > mirrored;
  }

  /// בודק ברשת מה הגרסה העדכנית ביותר — **פעולת רשת קלה**, בלי הורדת
  /// המסד/patches. כשל (בעיקר "אין חיבור") הוא מצב תקין: נשמר ב-
  /// [onlineCheckError] ולא נזרק, כדי שבדיקה אוטומטית לא תציג שגיאה
  /// מפחידה כשפשוט אין רשת כרגע.
  Future<void> checkOnline() async {
    onlineCheckError = null;
    notifyListeners();

    try {
      onlineLatestVersion = await _manager.peekLatestOnlineVersion();
    } catch (e, st) {
      onlineLatestVersion = null;
      onlineCheckError = e.toString();
      AppLogger.instance.info('בדיקת עדכונים ברשת (ספרייה) לא הצליחה: $e\n$st');
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// מוריד עדכוני ספרייה מהרשת אל [mirrorDir]. **הפעולה היחידה כאן שדורשת
  /// אינטרנט.** לא נוגעת ב-DB. לא זורקת — כשל נשמר ב-[downloadError].
  Future<void> download() async {
    downloadStatus = MirrorDownloadStatus.downloading;
    downloadStage = null;
    downloadDoneAssets = null;
    downloadTotalAssets = null;
    downloadReceivedBytes = null;
    downloadTotalBytes = null;
    downloadError = null;
    notifyListeners();

    try {
      await _manager.downloadToMirror(
        onStage: (stage) {
          downloadStage = stage;
          // כל נכס מדווח את הבייטים שלו מאפס — בלי איפוס כאן המד היה קופץ
          // אחורה עם הערכים של הנכס הקודם.
          downloadReceivedBytes = null;
          downloadTotalBytes = null;
          notifyProgress();
        },
        onAssetProgress: (done, total) {
          downloadDoneAssets = done;
          downloadTotalAssets = total;
          notifyProgress();
        },
        onBytesProgress: (received, total) {
          downloadReceivedBytes = received;
          downloadTotalBytes = total;
          notifyProgress();
        },
        // כשל בקובץ נלווה אינו מפיל את ההורדה, אבל בלי הרישום הזה הוא היה
        // מתגלה רק במחשב הלא-מקוון, כשכבר אין רשת לתקן בה.
        onCompanionWarning: (name, error) =>
            AppLogger.instance.info('הורדת הקובץ הנלווה "$name" נכשלה: $error'),
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
          errorMessage = check.plan?.reason ??
              AppL10n.strings.libraryDomain.blockedNeedsManualActionWithPeriod;
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
    // הבדיקה עצמה כבר איתרה את הנתיב — גם כשהיא נכשלה אחר כך (למשל אין
    // מראה). קריאה נפרדת ל-`currentDbPath()` הייתה חוזרת על כל האיתור.
    dbPath = _manager.lastResolvedDbPath;
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
    // שמירה מפני כניסה חוזרת: בין הלחיצה לדיאלוג יש בדיקת תהליך אסינכרונית,
    // והכפתור פעיל בזמנה — שתי החלות במקביל על ה-DB החי הן בדיוק מה שאסור.
    if (status == LibraryModuleStatus.updating) return;

    status = LibraryModuleStatus.updating;
    stageText = null;
    applyProgress = null;
    applyReceivedBytes = null;
    applyTotalBytes = null;
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
          applyReceivedBytes = p.bytesDownloaded;
          applyTotalBytes = p.bytesTotal;
          applyProgress = (p.bytesDownloaded != null &&
                  p.bytesTotal != null &&
                  p.bytesTotal! > 0)
              ? p.bytesDownloaded! / p.bytesTotal!
              // אימות ה-hash אורך דקות בלי בייטים להציג — בלעדיו המד נראה
              // תקוע לאורך כל השלב הארוך ביותר בהחלה.
              : p.verifyProgress;
          notifyProgress();
        },
        onCompanionWarning: (name, error) =>
            AppLogger.instance.info('התקנת הקובץ הנלווה "$name" נכשלה: $error'),
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
    final t = AppL10n.strings.libraryDomain;
    final step = (p.stepIndex != null && p.stepCount != null)
        ? ' (${p.stepIndex}/${p.stepCount})'
        : '';
    switch (p.stage) {
      case LibraryApplyStage.downloadingPatch:
        return t.applyDownloadingPatch(step);
      case LibraryApplyStage.applyingPatch:
        final patchStage = p.patchStage;
        return patchStage == null
            ? t.applyApplyingPatch(step)
            : t.applyPatchStage(patchStage, step);
      case LibraryApplyStage.downloadingFullDb:
        return t.applyDownloadingFullDb;
      case LibraryApplyStage.decompressingFullDb:
        return t.applyDecompressingFullDb;
      case LibraryApplyStage.writingFullDb:
        return t.applyWritingFullDb;
      case LibraryApplyStage.verifying:
        return t.applyVerifying;
      case LibraryApplyStage.installingCompanions:
        // ההתקנה מדווחת טקסט מוכן (שם הפריט שבטיפול); ה-fallback לשלב כולו.
        return p.statusText ?? t.applyInstallingCompanions;
      case LibraryApplyStage.done:
        return t.applyDone;
    }
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
