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

/// מה ההורדה האחרונה עשתה במצב "עדכון אישי".
enum LibraryPersonalDownloadNote {
  /// ירדו קובצי עדכון מהגרסה שנרשמה ומעלה.
  fromRecordedVersion,

  /// המצב מופעל אך לא נרשמה גרסה — ירד המסד המלא.
  versionUnknown,

  /// אין גרסה חדשה מזו שנרשמה — לא ירד דבר.
  upToDate,
}

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

  /// מצב "עדכון אישי" — משפיע על [download] בלבד.
  set personalUpdateMode(bool value) => _manager.personalUpdateMode = value;
  bool get personalUpdateMode => _manager.personalUpdateMode;

  final LibraryManager _manager;
  LibraryUpdateCheckResult? _lastCheck;

  LibraryModuleStatus status = LibraryModuleStatus.idle;
  int? localVersion;
  int? targetVersion;
  String? stageText;

  /// 0..1 כשיש יעד ידוע (בייטים שהורדו/סה"כ), אחרת null (מד לא-קבוע).
  /// מתעדכן במהלך [update] בלבד.
  double? applyProgress;

  /// הבייטים עצמם של השלב הנוכחי ב-[update] — לתצוגת "כמה מתוך כמה": מה שירד
  /// בשלבי ההורדה, ומה שנקרא מהקובץ הדחוס בשלב החילוץ. `null` בשלבים שאין בהם
  /// בייטים למנות (החלת patch, אימות).
  int? applyReceivedBytes;
  int? applyTotalBytes;
  String? errorMessage;

  /// `true` אם checkForUpdate האחרון זיהה שאין DB בכלל עדיין (התקנה
  /// טרייה) — ה-UI יכול להציג "מוריד ספרייה בפעם הראשונה" במקום "מעדכן".
  bool isFreshInstall = false;

  /// `true` כשאין מראה מקומית בכלל (טרם הורד דבר). נשמר בנפרד מ-[status], כי
  /// [hasOnlineUpdate] חייב לדעת זאת גם אחרי שה-status התקדם.
  bool mirrorMissing = false;

  /// נתיב ה-`seforim.db` שזוהה בפועל — מתעדכן בכל [checkForUpdate].
  String? dbPath;

  /// לאן תותקן הספרייה כשעדיין אין מסד — המיקום שאוצריא מחפשת בו, או בחירת
  /// המשתמש. מוצג מראש כדי שההתקנה לא תנחת במקום מפתיע.
  String? installTargetPath;

  /// בקשת עדכון אינדקס שממתינה לאוצריא, או `null` כשאין. הסימון יושב לצד
  /// המסד ולכן שורד הפעלות מחדש של הלאנצ'ר — [checkForUpdate] קורא אותו.
  ExternalUpdateNoticeData? pendingReindex;

  bool get hasPendingReindex => pendingReindex != null;

  /// מסמן שהבקשה נמסרה לאוצריא בפועל. **רק אחרי מסירה מוצלחת** — מחיקה
  /// מוקדמת הייתה משאירה את אינדקס החיפוש על התוכן הישן בלי שאיש יידע.
  Future<void> markReindexRequestDelivered() async {
    if (pendingReindex == null) return;
    await _manager.clearReindexRequest(dbPath: dbPath);
    pendingReindex = null;
    notifyListeners();
  }

  Future<void> _refreshPendingReindex() async {
    // בלי נתיב מסד אין לצד מה לחפש סימון, ובקשה מ-`LibraryManager` הייתה
    // מריצה את כל האיתור מחדש (כולל קריאת קופסת ההגדרות של אוצריא מעותק).
    final path = dbPath;
    pendingReindex = path == null
        ? null
        : await _manager.pendingReindexRequest(dbPath: path);
  }

  /// `true` אחרי ניסיון עדכון שנכשל, כשיש במראה מסד מלא שאפשר להתקין
  /// במקומו — ראו [updateWithFullDownload]. בלי זה משתמש שנתקל ב-patch
  /// שאינו מתאים למסד שלו נשאר תקוע לנצח (issue #19).
  bool canRetryWithFullDownload = false;

  /// גודל ההורדה של אותה ספרייה מלאה, בבייטים — לתצוגה לפני שמאשרים.
  int? get fullDownloadFallbackSize =>
      _lastCheck?.plan?.fullDownloadFallback?.totalDownloadSize;

  /// התיקייה שלצד התוכנה שממנה נקראים העדכונים — המקור היחיד.
  String get mirrorDir => _manager.mirrorDir;

  /// תיקיית הקבצים הנלווים (תלמוד/קטלוג/מילון), שגם היא נמלאת ב-[download].
  String get companionsMirrorDir => _manager.companionsMirrorDir;

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

  /// הגרסה שנרשמה כנקודת מוצא להורדה אישית, או `null` אם טרם נרשמה. נקראת
  /// מקובץ ה-state בלבד — **לא** ממסד. ראו [capturePersonalVersion].
  int? personalFromVersion;

  /// מה ההורדה האחרונה הביאה במצב אישי, `null` כשלא רלוונטי. קיים כדי
  /// שהמצב לא יהיה שקוף: מי שהפעיל אותו בלי לרשום גרסה קיבל מסד מלא.
  LibraryPersonalDownloadNote? personalDownloadNote;

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
    // מראה ריקה = יש מה להוריד, נקודה. הנפילה לגרסת המסד החי השוותה את הרשת
    // למחשב הזה במקום לכונן, ולכן כונן ריק במחשב שיש עליו אוצריא מעודכנת
    // קיבל "אין עדכונים", בלי כפתור הורדה ועם דילוג ב-downloadAll.
    if (mirrorMissing) return true;
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
    } catch (e) {
      onlineLatestVersion = null;
      onlineCheckError = e.toString();
      // בלי stack trace: "אין רשת" הוא המצב הרגיל במחשב שהתוכנה נועדה לו,
      // וארבעה traces בכל הפעלה הטביעו את הלוג במקום להסביר משהו.
      AppLogger.instance.info('בדיקת עדכונים ברשת (ספרייה) לא הצליחה: $e');
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// מוריד עדכוני ספרייה מהרשת אל [mirrorDir]. **הפעולה היחידה כאן שדורשת
  /// אינטרנט.** לא נוגעת ב-DB. לא זורקת — כשל נשמר ב-[downloadError].
  ///
  /// [isCancelled] נבדק לאורך כל ההורדה, כולל באמצע נכס. ביטול אינו שגיאה:
  /// המצב חוזר ל-[MirrorDownloadStatus.idle] בלי [downloadError].
  Future<void> download({bool Function()? isCancelled}) async {
    downloadStatus = MirrorDownloadStatus.downloading;
    downloadStage = null;
    downloadDoneAssets = null;
    downloadTotalAssets = null;
    downloadReceivedBytes = null;
    downloadTotalBytes = null;
    downloadError = null;
    // הדיווח מתייחס להורדה הזו בלבד — הישן היה מתאר מצב שכבר הוחלף.
    personalDownloadNote = null;
    notifyListeners();

    try {
      final outcome = await _manager.downloadToMirror(
        onStage: (stage) {
          downloadStage = stage;
          // **בלי איפוס הבייטים.** הנכסים יורדים במקביל ומדווחים מונה אחד
          // מצטבר לכל ההורדה (ראו `ByteProgressAggregator`), ולכן איפוס בכל
          // הכרזת שלב היה מרוקן מד שדווקא כן מתקדם.
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
        isCancelled: isCancelled,
      );
      downloadStatus = MirrorDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      personalFromVersion = outcome.personalFromVersion ?? personalFromVersion;
      personalDownloadNote = !personalUpdateMode
          ? null
          : outcome.upToDate
              ? LibraryPersonalDownloadNote.upToDate
              : outcome.personalFromVersion == null
                  ? LibraryPersonalDownloadNote.versionUnknown
                  : LibraryPersonalDownloadNote.fromRecordedVersion;
      notifyListeners();
      // עכשיו יש מול מה להשוות — מרעננים את מצב העדכון מהתיקייה החדשה.
      await checkForUpdate();
      return;
    } catch (e, st) {
      // ביטול של המשתמש אינו תקלה, ולכן אינו נשאר על המסך כשגיאה. השלב
      // מתאפס גם הוא — אחרת הכרטיס ממשיך לתאר נכס שהורדתו נפסקה.
      if (isCancelled?.call() ?? false) {
        downloadStatus = MirrorDownloadStatus.idle;
        downloadStage = null;
        AppLogger.instance.info('הורדת עדכוני ספרייה בוטלה: $e');
      } else {
        downloadStatus = MirrorDownloadStatus.error;
        downloadError = e.toString();
        AppLogger.instance.error('הורדת עדכוני ספרייה נכשלה', e, st);
      }
    }
    notifyListeners();
  }

  /// קורא את גרסת המסד של המחשב הזה ורושם אותה כנקודת המוצא להורדה אישית —
  /// **רק מכאן**, כלומר מלחיצה מפורשת. מחזיר `false` אם לא נמצא מסד לקרוא
  /// ממנו, כדי שהמסך יאמר זאת במקום להציג הצלחה שקטה.
  Future<bool> capturePersonalVersion() async {
    try {
      final version = await _manager.captureLocalDbVersion();
      if (version == null) return false;
      personalFromVersion = version;
      notifyListeners();
      return true;
    } catch (e, st) {
      AppLogger.instance.error('רישום גרסת המסד לעדכון אישי נכשל', e, st);
      return false;
    }
  }

  Future<void> checkForUpdate() async {
    status = LibraryModuleStatus.checking;
    errorMessage = null;
    canRetryWithFullDownload = false;
    notifyListeners();

    // מה שנרשם בלחיצה — כולל במחשב אחר, דרך קובץ ה-state שנוסע על הכונן.
    personalFromVersion = await _manager.recordedPersonalDbVersion();

    try {
      final check = await _manager.checkForUpdate();
      _lastCheck = check;
      isFreshInstall = check.isFreshInstall;
      mirrorMissing = false;

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
      mirrorMissing = true;
      // הגרסה המקומית ידועה גם בלי מראה: הבדיקה כבר קראה אותה מהמסד לפני
      // שנכשלה. בלי זה המסך מציג "לא ידוע" למסד שנמצא ונקרא בהצלחה — מה
      // שמשתמש שבחר את הקובץ ידנית רואה כ"לא מזהה את המסד".
      final local = await _manager.readLocalVersion();
      localVersion = (local?.hasVersionMeta ?? false) ? local!.dbVersion : null;
      targetVersion = null;
    } catch (e, st) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error('checkForUpdate נכשל', e, st);
    }
    // הבדיקה עצמה כבר איתרה את הנתיב — גם כשהיא נכשלה אחר כך (למשל אין
    // מראה). קריאה נפרדת ל-`currentDbPath()` הייתה חוזרת על כל האיתור.
    dbPath = _manager.lastResolvedDbPath;
    installTargetPath = _manager.lastInstallDbPath;
    // בקשה שנכתבה בהרצה קודמת ולא נמסרה עדיין — הסימון יושב לצד המסד, ולכן
    // הוא נקרא כאן ולא רק אחרי עדכון שנעשה בהרצה הזאת.
    await _refreshPendingReindex();
    notifyListeners();
  }

  Future<void> setCustomDbPath(String dbPath) async {
    await _manager.setCustomDbPath(dbPath);
    await checkForUpdate();
  }

  /// קובע לאן תותקן הספרייה. התיקייה עוד יכולה להיות ריקה — הקובץ ייווצר בה
  /// בהתקנה עצמה.
  Future<void> setInstallDir(String dir) => setCustomDbPath(dbPathIn(dir));

  /// נתיב המסד שייווצר בתיקייה הזו — לתצוגה בדיאלוג האזהרה, בלי לשמור כלום.
  String dbPathIn(String dir) => _manager.dbPathIn(dir);

  /// האם אוצריא תמצא את המסד הזה בעצמה — ראו את דיאלוג האזהרה במסך הספרייה.
  Future<bool> isDbPathKnownToOtzaria(String dbPath) =>
      _manager.isDbPathKnownToOtzaria(dbPath);

  /// מחיל בפועל את העדכון על ה-DB **החי** — delta patch-אחר-patch, או
  /// הורדת DB מלא, דרך [LibraryManager.applyUpdate]. בהצלחה, ה-DB של
  /// אוצריא כבר מעודכן בפועל ואין שום פעולה נוספת שהמשתמש צריך לעשות.
  ///
  /// זורק (ונתפס כאן כ-[LibraryModuleStatus.error]) בעיקר: `OtzariaIsRunningException`
  /// אם אוצריא פתוחה כרגע (בווינדוס), או `LibraryApplyException`
  /// על כשל הורדה/אימות/כתיבה — בשני המקרים ה-`toString()` של החריג
  /// כבר מנוסח כהודעה קריאה למשתמש, ומוצג ישירות ב-[errorMessage].
  Future<void> update() => _apply(useFullDownloadFallback: false);

  /// מתקין את הספרייה המלאה שבמראה במקום ה-patches — ההתאוששות מכשל של
  /// מסלול הדלתא. פעולה ארוכה, ולכן נקראת רק מאישור מפורש של המשתמש.
  Future<void> updateWithFullDownload() =>
      _apply(useFullDownloadFallback: true);

  Future<void> _apply({required bool useFullDownloadFallback}) async {
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
    canRetryWithFullDownload = false;
    notifyListeners();

    final plan = useFullDownloadFallback
        ? _lastCheck!.plan?.fullDownloadFallback
        : _lastCheck!.plan;
    AppLogger.instance.info(
      'update() מתחיל: kind=${plan?.kind} local=${plan?.localVersion} target=${plan?.targetVersion}',
    );

    try {
      await _manager.applyUpdate(
        _lastCheck!,
        useFullDownloadFallback: useFullDownloadFallback,
        onProgress: (p) {
          stageText = _describeApplyStage(p);
          final done = p.bytesDone;
          final total = p.bytesTotal;
          applyReceivedBytes = done;
          applyTotalBytes = total;
          applyProgress = (done != null && total != null && total > 0)
              ? done / total
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
      // רק אחרי כשל של מסלול הדלתא, ורק אם יש מסד מלא במראה: הצעה שנייה
      // אחרי כשל של ההורדה המלאה עצמה הייתה לולאה.
      canRetryWithFullDownload =
          !useFullDownloadFallback && _lastCheck!.canFallBackToFullDownload;
      // שרשרת דלתא שנקטעה באמצע כן שינתה ספרים, והסימון נכתב — ולכן גם
      // המסלול הזה מציע את עדכון האינדקס.
      await _refreshPendingReindex();
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
