import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../services/app_logger.dart';
import '../services/elevation.dart';
import '../services/storage_failure.dart';
import '../settings/app_settings.dart' show SemanticDownloadPreference;
import 'dispose_guard.dart';
import 'download_plan.dart' show LibrarySizeProbe;
import 'online_check.dart';
import 'progress_notifier.dart';
import 'stage_clock.dart';

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

  /// "עדכון אישי" דלוק, והמראה נבנתה לגרסה של מחשב אחר שנרשם — המחשב הזה
  /// לא נרשם כיעד, ולכן אין לו כאן מה להתקין. מצב תקין, לא שגיאה.
  personalTargetElsewhere,
}

/// מצב ההורדה מהרשת אל התיקייה המקומית. נפרד לגמרי מ-[LibraryModuleStatus]:
/// הורדה יכולה לרוץ גם כשהמסד המקומי מעודכן (מורידים בשביל המחשב האחר).
enum MirrorDownloadStatus { idle, downloading, done, error }

typedef LibraryOnlineAnswers = ({
  int? latestVersion,
  String? checkError,
  DateTime? checkedAt,
  Set<CompanionAsset> pendingCompanions,
  String? companionsCheckError,
  bool semanticPending,
  String? semanticCheckError,
  bool semanticChecked,
  int? downloadBytesBound,
  int? semanticBytes,
  bool readableMirrorCurrent,
});

/// מה ההורדה האחרונה עשתה במצב "עדכון אישי".
enum LibraryPersonalDownloadNote {
  /// ירדו קובצי עדכון מהגרסה שנרשמה ומעלה.
  fromRecordedVersion,

  /// המצב מופעל אך לא נרשמה גרסה — ירד המסד המלא.
  versionUnknown,

  /// אין גרסה חדשה מזו שנרשמה — לא ירד דבר.
  upToDate,

  /// `releases.json` שבמראה היה פגום — ירד המסד המלא כדי לתקן אותה.
  mirrorRepaired,
}

class LibraryModuleController extends ChangeNotifier
    with DisposeGuard, ProgressNotifier {
  LibraryModuleController({
    required String dataDir,
    String? stateDir,
    bool allowPrerelease = false,
    Future<String?> Function()? otzariaLaunchPath,
    Future<String?> Function()? otzariaAppVersion,
    Future<String?> Function()? mirroredOtzariaUpdate,
    Future<int?> Function()? mirroredReadableDbSchema,
    OtzariaInstanceLock? instanceLock,
    LibraryManager? manager,
  })  : _mirroredOtzariaUpdate = mirroredOtzariaUpdate,
        _mirroredReadableDbSchema = mirroredReadableDbSchema,
        _manager = manager ??
            LibraryManager(
              dataDir: dataDir,
              stateDir: stateDir,
              allowPrerelease: allowPrerelease,
              otzariaLaunchPath: otzariaLaunchPath,
              otzariaAppVersion: otzariaAppVersion,
              mirroredReadableDbSchema: mirroredReadableDbSchema,
              instanceLock: instanceLock,
            );

  final Future<String?> Function()? _mirroredOtzariaUpdate;

  /// The schema the Otzaria installers on the drive read, asked fresh at each
  /// download (after the app's); `null` from it = no usable installer.
  final Future<int?> Function()? _mirroredReadableDbSchema;

  set personalUpdateMode(bool value) {
    if (_manager.personalUpdateMode == value) return;
    _manager.personalUpdateMode = value;
    _readableMirrorCurrent = false;
    _refreshDownloadSize();
    if (!value) registeredMachines = const [];
    if (status == LibraryModuleStatus.idle || _applying) return;
    unawaited(checkForUpdate());
  }

  bool get personalUpdateMode => _manager.personalUpdateMode;

  SemanticDownloadPreference get semanticPreference => _semanticPreference;
  SemanticDownloadPreference _semanticPreference =
      SemanticDownloadPreference.ask;

  set semanticPreference(SemanticDownloadPreference value) {
    if (_semanticPreference == value) return;
    _semanticPreference = value;
    if (value == SemanticDownloadPreference.never) {
      semanticDownloadFailed = false;
    }
    notifyListeners();
  }

  bool get _semanticCountsAsUpdate =>
      _semanticPreference == SemanticDownloadPreference.always &&
      onlineSemanticPending &&
      !semanticDownloadFailed;

  final LibraryManager _manager;
  LibraryUpdateCheckResult? _lastCheck;

  Future<void>? _checkInFlight;
  bool _applying = false;
  bool get isApplying => _applying;

  LibraryModuleStatus status = LibraryModuleStatus.idle;
  int? localVersion;
  int? targetVersion;
  String? stageText;

  /// שעון לשלבים שאינם מדווחים דבר — ראו [StageClock]. הטיימר יושב כאן
  /// והמדידה שם, כדי שהחישוב יהיה בר-בדיקה בלי להריץ החלה שלמה.
  final StageClock _stageClock = StageClock();
  Timer? _stageTicker;

  /// 0..1 כשיש יעד ידוע (בייטים שהורדו/סה"כ), אחרת null (מד לא-קבוע).
  /// מתעדכן במהלך [update] בלבד.
  double? applyProgress;

  /// הבייטים עצמם של השלב הנוכחי ב-[update] — לתצוגת "כמה מתוך כמה": מה שירד
  /// בשלבי ההורדה, ומה שנקרא מהקובץ הדחוס בשלב החילוץ. `null` בשלבים שאין בהם
  /// בייטים למנות (החלת patch, אימות).
  int? applyReceivedBytes;
  int? applyTotalBytes;
  String? errorMessage;

  /// כשל בקריאת המסד המקומי מובחן מכשל במראה כדי להציג את המקור הנכון.
  bool localDbUnreadable = false;

  /// `true` אם checkForUpdate האחרון זיהה שאין DB בכלל עדיין (התקנה
  /// טרייה) — ה-UI יכול להציג "מוריד ספרייה בפעם הראשונה" במקום "מעדכן".
  bool isFreshInstall = false;

  /// `true` כשאין מראה מקומית בכלל (טרם הורד דבר). נשמר בנפרד מ-[status], כי
  /// [hasOnlineUpdate] חייב לדעת זאת גם אחרי שה-status התקדם.
  bool mirrorMissing = false;

  /// `releases.json` שבמראה אינו קריא — כמו [mirrorMissing], יש מה להוריד.
  bool mirrorDamaged = false;

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
    if (pendingReindex == null || _applying) return;
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

  /// ההחלה האחרונה הגיעה לסופה — המסד הוחלף.
  bool lastApplyCompleted = false;

  /// הערה מוכרת אחרי החלה שהצליחה (מיקום שצריך לכוון, קובץ נלווה שנכשל).
  /// חריג גולמי שנזרק אחרי ההחלה לא נכנס לכאן.
  String? applyNote;

  /// הכשל האחרון היה "אין הרשאה" — ראו [Elevation]. `AppSession` מציע על סמך
  /// זה להפעיל מחדש כמנהל, ולכן זה נדלק בכשל ונכבה בכל ניסיון חדש.
  bool needsElevation = false;

  /// "צפוי כ-X עד Y דקות" לתוכנית שתוחל — בשלב הספרייה של מסך המשימה,
  /// וליד הכפתור של הספרייה המלאה.
  ({int low, int high})? applyEstimateFor({bool fullDownload = false}) =>
      libraryApplyMinutes(
        fullDownload
            ? _lastCheck?.plan?.fullDownloadFallback
            : _lastCheck?.plan,
      );

  /// גודל ההורדה של אותה ספרייה מלאה, בבייטים — לתצוגה לפני שמאשרים.
  int? get fullDownloadFallbackSize =>
      _lastCheck?.plan?.fullDownloadFallback?.totalDownloadSize;

  /// ההסבר של התוכנית כשמסלול העדכון אינו המובן מאליו — מסד שלם במקום
  /// קובצי עדכון, או שרשרת שנעצרת מתחת ל-latest. בלי זה המשתמש רואה הורדה
  /// של ~1.5GB, או יעד נמוך מהגרסה הקיימת, בלי סיבה.
  String? get updateRouteNote {
    final plan = _lastCheck?.plan;
    return switch (plan?.kind) {
      LibraryUpdatePlanKind.fullDownload ||
      LibraryUpdatePlanKind.delta =>
        plan?.reason,
      _ => null,
    };
  }

  /// התיקייה שלצד התוכנה שממנה נקראים העדכונים — המקור היחיד.
  String get mirrorDir => _manager.mirrorDir;

  /// תיקיית הקבצים הנלווים (תלמוד/קטלוג/מילון), שגם היא נמלאת ב-[download].
  String get companionsMirrorDir => _manager.companionsMirrorDir;

  String get semanticMirrorDir => _manager.semanticMirrorDir;

  bool semanticPending = false;
  bool semanticConsentGranted = false;

  /// "מה חדש בספרייה": לפני ההחלה — של העדכון המוצע; אחריה — של מה שהותקן
  /// בהרצה הזו ([changesNotesApplied]). [changesNotesVersion] היא גרסת היעד.
  List<LibraryChangesNote> changesNotes = const [];
  bool changesNotesApplied = false;
  int? changesNotesVersion;

  /// כמה גרסאות בטווח; יותר מ-[changesNotes] = הרשימה חלקית.
  int changesNotesRange = 0;
  bool get changesNotesPartial => changesNotes.length < changesNotesRange;
  ({
    int version,
    int range,
    List<LibraryChangesNote> notes
  })? _appliedChangesNotes;
  bool get semanticConsentRequired =>
      semanticPending && !semanticConsentGranted;

  /// מצב ההורדה מהרשת אל [mirrorDir].
  MirrorDownloadStatus downloadStatus = MirrorDownloadStatus.idle;
  String? downloadStage;

  /// שלב הקבצים הנלווים, שרץ **במקביל** לשלב שב-[downloadStage]. שורה משלו
  /// כי שניהם כתבו לאחת וזו קפצה ביניהם בזמן שהמד מתאר את שניהם יחד.
  String? downloadCompanionStage;
  int? downloadDoneAssets;
  int? downloadTotalAssets;

  /// בייטים שהורדו/סה"כ **לכל ההורדה יחד**, ורק מה שבאמת עובר ברשת: נכס
  /// שכבר יושב שלם על הכונן אינו נספר בשני האגפים. בלי המונה הזה המד נשען
  /// על ספירת הנכסים בלבד, והמסד המלא (~1GB בקובץ אחד) השאיר אותו תקוע.
  int? downloadReceivedBytes;
  int? downloadTotalBytes;
  String? downloadError;

  /// החריג שהפיל את ההורדה — המסך מסווג לפיו ולא לפי הטקסט.
  Object? downloadCause;
  bool get downloadStorageFull => findStorageFull(downloadCause) != null;
  bool _incompleteMirrorDownload = false;
  bool get downloadNeedsRetry =>
      downloadError != null || _incompleteMirrorDownload;

  /// The last download did not start: no Otzaria installer on the drive reads
  /// the library. [downloadError] carries the message.
  bool downloadNeedsOtzariaInstaller = false;

  /// A newer library the drive's Otzaria installers cannot read, left online
  /// by the last download.
  int? newerLibraryNeedsOtzaria;

  /// The last download left a newer mirror in place rather than replace it
  /// with what the drive's Otzaria installers read.
  bool keptNewerMirror = false;

  /// Some update manifests could not be read, so "nothing newer" is unproven.
  bool libraryMetadataUnreadable = false;

  /// What the last download could not do, or could not tell — each its own
  /// sentence, so a block, a kept mirror and unknown data never read alike.
  List<String> get downloadNotes {
    final t = AppL10n.strings.libraryScreen;
    return [
      if (downloadNeedsOtzariaInstaller) t.downloadNeedsOtzariaInstaller,
      if (keptNewerMirror) t.downloadKeptNewerMirror,
      if (newerLibraryNeedsOtzaria case final newer?)
        t.downloadNewerNeedsOtzaria('$newer'),
      if (libraryMetadataUnreadable) t.downloadMetadataUnreadable,
      if (semanticIncompatibility case final incompatible?) '$incompatible',
    ];
  }

  DateTime? lastDownloadedAt;

  /// הגרסה שנרשמה כנקודת מוצא להורדה אישית, או `null` אם טרם נרשמה. נקראת
  /// מקובץ ה-state בלבד — **לא** ממסד. ראו [capturePersonalVersion].
  int? personalFromVersion;

  /// מה ההורדה האחרונה הביאה במצב אישי, `null` כשלא רלוונטי. קיים כדי
  /// שהמצב לא יהיה שקוף: מי שהפעיל אותו בלי לרשום גרסה קיבל מסד מלא.
  LibraryPersonalDownloadNote? personalDownloadNote;

  /// גודל ההורדה הבאה לפני שהספרייה מתחילה לרדת; null כשלא נבדק.
  LibrarySizeProbe? downloadSizeProbe;

  void clearDownloadSizeProbe() => downloadSizeProbe = null;

  /// מריץ רק את התכנון של ההורדה (בלי התוכן). כשל משאיר את השורה בלי מספר.
  Future<void> probeDownloadSize() async {
    if (_mirroredReadableDbSchema != null) return;
    downloadSizeProbe = const LibrarySizeProbe.checking();
    notifyProgress();
    int? bytes;
    try {
      bytes = await _manager.probeMirrorDownloadBytes();
    } catch (e) {
      AppLogger.instance.info('בדיקת גודל הספרייה לפני ההורדה לא הצליחה: $e');
    }
    downloadSizeProbe = bytes == null
        ? const LibrarySizeProbe.failed()
        : LibrarySizeProbe.known(bytes);
    notifyProgress();
  }

  /// המחשבים שנרשמו לעדכון אישי, מהגרסה הנמוכה. נקרא בכל בדיקה.
  List<RegisteredMachine> registeredMachines = const [];

  /// גם בלי בדיקה: ההגדרות מציגות את הרשימה כשהבדיקה בעלייה כבויה. רק במצב
  /// אישי — זיהוי המחשב מריץ תהליך ב-macOS, וכבוי אין למי להציג את הרשימה.
  Future<void> refreshRegisteredMachines() async {
    registeredMachines = await _loadRegisteredMachines();
    if (!isDisposed) notifyListeners();
  }

  Future<List<RegisteredMachine>> _loadRegisteredMachines() async {
    if (!personalUpdateMode) return const [];
    try {
      return await _manager.registeredMachines();
    } catch (e) {
      if (!isDisposed) {
        AppLogger.maybeInstance?.info('קריאת המחשבים שנרשמו נכשלה: $e');
      }
      return const [];
    }
  }

  /// בכונן ספרייה מלאה שתימחק בהורדה הבאה במצב אישי — לאזהרה שלפני הבחירה.
  Future<bool> mirrorHoldsFullDb() => _manager.mirrorHoldsFullDb();

  /// אף מחשב לא נרשם — נקרא מקובץ ה-state, לא מהבדיקה האחרונה.
  Future<bool> hasNoRegisteredMachine() async =>
      await _manager.recordedPersonalDbVersion() == null;

  /// "הסרה" בהגדרות: המחשב כבר אינו קובע מאיזו גרסה מורידים.
  Future<void> forgetMachine(String machineKey) async {
    try {
      await _manager.forgetRegisteredMachine(machineKey);
    } catch (e, st) {
      AppLogger.instance.error('הסרת מחשב שנרשם נכשלה', e, st);
    }
    _refreshDownloadSize();
    await checkForUpdate(fresh: true);
  }

  int _sizeRun = 0;

  /// מחשב את החסם מחדש אחרי שינוי מצב או רישום — מההצצה האחרונה בלבד, בלי
  /// רשת ובלי כתיבה לכונן (`peekedDownloadBytesBound`).
  void _refreshDownloadSize() {
    final run = ++_sizeRun;
    onlineDownloadBytesBound = null;
    if (onlineCheckedAt == null || onlineLibraryProofError != null) return;
    unawaited(() async {
      int? bytes;
      try {
        bytes = await _manager.peekedDownloadBytesBound();
      } catch (e) {
        if (isDisposed) return;
        AppLogger.maybeInstance
            ?.info('חישוב גודל ההורדה של הספרייה לא הצליח: $e');
      }
      if (run != _sizeRun || isDisposed) return;
      onlineDownloadBytesBound = bytes;
      notifyListeners();
    }());
  }

  /// האם המחשב הזה נרשם כיעד לעדכון אישי. `true` גם כשהמצב כבוי, כי אז
  /// כל מחשב הוא יעד לגיטימי. ראו [LibraryModuleStatus.personalTargetElsewhere].
  bool personalTargetIsThisMachine = true;

  /// 0..1 להורדה כולה. **הבייטים קודמים לספירת הנכסים**: המונה מתאר ממילא
  /// את כל ההורדה יחד (`ByteProgressAggregator`), ולחלק אותו במספר הנכסים
  /// היה משאיר את המד על שליש בזמן שההורדה כמעט הסתיימה. ספירת הנכסים היא
  /// הנפילה־לאחור, לפני שידוע סכום בייטים — ובהורדה שכולה כבר על הכונן.
  double? get downloadProgress {
    final received = downloadReceivedBytes;
    final bytesTotal = downloadTotalBytes;
    if (received != null && bytesTotal != null && bytesTotal > 0) {
      return (received / bytesTotal).clamp(0.0, 1.0);
    }
    // **אין החלפת סרגל באמצע.** בייטים שכבר עברו בלי שיש להם יעד הם המצב
    // היחיד שבו ספירת הנכסים הייתה מציגה אחוז מסרגל אחר לגמרי — ואז הכניסה
    // של הבייטים קפצה. מד בלתי-מוגדר אומר את האמת, ונמשך שניות בודדות.
    if (received != null && received > 0 && bytesTotal == null) return null;

    final totalAssets = downloadTotalAssets;
    if (totalAssets == null || totalAssets <= 0) return null;
    return ((downloadDoneAssets ?? 0) / totalAssets).clamp(0.0, 1.0);
  }

  /// מצב הבדיקה הקלה ("יש עדכון ברשת?") — נפרד לגמרי מ-[downloadStatus]:
  /// היא לא מורידה כלום, רק שואלת. `null` = טרם נבדק בהרצה הזו.
  int? onlineLatestVersion;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  /// הנלווים שהורדה הייתה מביאה עכשיו, לפי הבדיקה הקלה שלהם.
  Set<CompanionAsset> onlinePendingCompanions = const {};
  bool onlineSemanticPending = false;
  String? onlineSemanticCheckError;

  /// חיפוש חכם שהמנוע שבכלי או באוצריא אינו קורא: לא ירד מחדש, וההסבר לפי
  /// הסיבה. הבדיקה המקוונת והמראה שעל הכונן נבדקות בנפרד.
  SemanticEngineIncompatibleException? onlineSemanticIncompatibility;
  SemanticEngineIncompatibleException? mirrorSemanticIncompatibility;
  SemanticEngineIncompatibleException? get semanticIncompatibility =>
      mirrorSemanticIncompatibility ?? onlineSemanticIncompatibility;

  /// הבדיקה של החיפוש החכם רצה בפועל. בלעדיה — "לא נבדק", לעולם לא "מעודכן".
  bool semanticChecked = false;

  /// חסמים עליונים מהבדיקה הקלה — `LibraryManager.peekedDownloadBytesBound`
  /// ו-`peekedSemanticBytes`; `null` כשאין חסם מוגדר.
  int? onlineDownloadBytesBound;
  int? onlineSemanticBytes;

  /// "עד X" של הספרייה בבית: עם החיפוש החכם רק ב"תמיד", כי ב"לשאול" הוא
  /// יורד רק אחרי השאלה. `null` — אין חסם, ולכן אין מספר.
  int? get onlineDownloadUpperBound {
    final bound = onlineDownloadBytesBound;
    if (bound == null) return null;
    // אותו תנאי שבו ההורדה מוסיפה אותו — גם כשבדיקתו נכשלה.
    if (_semanticPreference != SemanticDownloadPreference.always ||
        !shouldOfferSemanticDownload) {
      return bound;
    }
    final semantic = onlineSemanticBytes;
    return semantic == null ? null : bound + semantic;
  }

  /// נלווים שנשארו חסרים אחרי הורדה של הספרייה שהסתיימה — לא מוצעים שוב עד
  /// [forgetDownloadFailures]; אחרת הבית מציע אותם בכל פתיחה ונכשל שוב.
  Set<CompanionAsset> failedCompanions = const {};
  bool semanticDownloadFailed = false;

  /// רק מה שעדיין חסר — בדיקה מאוחרת יותר יכולה לגלות שכבר ירד.
  Set<CompanionAsset> get _stillFailed =>
      failedCompanions.intersection(onlinePendingCompanions);

  bool get hasDownloadFailures =>
      _stillFailed.isNotEmpty ||
      (semanticDownloadFailed && onlineSemanticPending);

  String get failedDownloadNames => [
        if (_stillFailed.isNotEmpty) _companionNames(_stillFailed),
        if (semanticDownloadFailed && onlineSemanticPending)
          AppL10n.strings.libraryDomain.companionSemanticName,
      ].join(', ');

  void forgetDownloadFailures() {
    if (failedCompanions.isEmpty && !semanticDownloadFailed) return;
    failedCompanions = const {};
    semanticDownloadFailed = false;
    notifyListeners();
  }

  Set<CompanionAsset> get _offeredCompanions =>
      onlinePendingCompanions.difference(failedCompanions);

  /// "לשאול כל פעם": חיפוש חכם שאפשר להוריד, כשורה משנית — לא כעדכון.
  bool get onlineSemanticOffer =>
      _semanticPreference == SemanticDownloadPreference.ask &&
      onlineSemanticPending &&
      semanticChecked &&
      !semanticDownloadFailed;

  /// כשל בבדיקת הנלווים בלבד. אינו "אין רשת" למודול, אך שולל את ההוכחה שאין
  /// מה להוריד — ראו [onlineProofError].
  String? onlineCompanionsCheckError;

  String? get onlineProofError =>
      onlineLibraryProofError ?? onlineSemanticCheckError;

  String? get onlineLibraryProofError =>
      onlineCheckError ?? onlineCompanionsCheckError;

  /// הבדיקה כפי שהבית רואה אותה: כשל של החיפוש החכם נחשב רק ב"תמיד" — בשאר
  /// הוא אינו חלק מהעדכון.
  String? get onlineAnswerError =>
      onlineLibraryProofError ??
      (_semanticPreference == SemanticDownloadPreference.always
          ? onlineSemanticCheckError
          : null);

  /// לשאול על הורדת החיפוש החכם רק כשהבדיקה לא הוכיחה שהכונן כבר מחזיק אותו —
  /// אחרת "כן" מריץ את כל הורדת הספרייה בלי שום דבר חדש להביא.
  bool get shouldOfferSemanticDownload =>
      !semanticChecked ||
      !provenUpToDateOnline(
        checkedAt: onlineCheckedAt,
        error: onlineCheckError ?? onlineSemanticCheckError,
        hasUpdate: onlineSemanticPending,
      );

  String get onlinePendingCompanionNames => [
        if (_offeredCompanions.isNotEmpty) _companionNames(_offeredCompanions),
        if (_semanticCountsAsUpdate)
          AppL10n.strings.libraryDomain.companionSemanticName,
      ].join(', ');

  LibraryOnlineAnswers get onlineAnswers => (
        latestVersion: onlineLatestVersion,
        checkError: onlineCheckError,
        checkedAt: onlineCheckedAt,
        pendingCompanions: onlinePendingCompanions,
        companionsCheckError: onlineCompanionsCheckError,
        semanticPending: onlineSemanticPending,
        semanticCheckError: onlineSemanticCheckError,
        semanticChecked: semanticChecked,
        downloadBytesBound: onlineDownloadBytesBound,
        semanticBytes: onlineSemanticBytes,
        readableMirrorCurrent: _readableMirrorCurrent,
      );

  void restoreOnlineAnswers(LibraryOnlineAnswers answers) {
    onlineLatestVersion = answers.latestVersion;
    onlineCheckError = answers.checkError;
    onlineCheckedAt = answers.checkedAt;
    onlinePendingCompanions = answers.pendingCompanions;
    onlineCompanionsCheckError = answers.companionsCheckError;
    onlineSemanticPending = answers.semanticPending;
    onlineSemanticCheckError = answers.semanticCheckError;
    semanticChecked = answers.semanticChecked;
    _sizeRun++;
    onlineDownloadBytesBound = answers.downloadBytesBound;
    onlineSemanticBytes = answers.semanticBytes;
    _readableMirrorCurrent = answers.readableMirrorCurrent;
    notifyListeners();
  }

  bool get hasOnlineUpdate => hasOnlineLibraryUpdate || _semanticCountsAsUpdate;

  bool _readableMirrorCurrent = false;

  bool get hasOnlineLibraryUpdate =>
      downloadNeedsRetry || _hasOnlineDbUpdate || _offeredCompanions.isNotEmpty;

  /// להוכחה שלפני ההורדה: נלווה שנכשל אינו מוצע בבית, אבל גם אינו "מעודכן".
  bool get libraryDownloadPending =>
      hasOnlineLibraryUpdate || onlinePendingCompanions.isNotEmpty;

  bool get _hasOnlineDbUpdate {
    final online = onlineLatestVersion;
    if (online == null) return false;
    if (_readableMirrorCurrent) return false;
    // מראה ריקה = יש מה להוריד, נקודה. הנפילה לגרסת המסד החי השוותה את הרשת
    // למחשב הזה במקום לכונן, ולכן כונן ריק במחשב שיש עליו אוצריא מעודכנת
    // קיבל "אין עדכונים", בלי כפתור הורדה ועם דילוג ב-downloadAll.
    if (mirrorMissing || mirrorDamaged) return true;
    final mirrored = targetVersion ?? localVersion ?? 0;
    return online > mirrored;
  }

  /// גרסת הספרייה שנמצאה ברשת כשיש מה להוריד — לתצוגה בלבד.
  int? get onlineUpdateVersion =>
      _hasOnlineDbUpdate ? onlineLatestVersion : null;

  /// התשובה הקודמת — גם כשל — נשארת עד שהחדשה מוכנה: ניקוי בתחילה הפך כשל
  /// ל"הוכח" באמצע בדיקה חוזרת (`onlineProofOf`).
  Future<void> checkOnline() async {
    notifyListeners();

    int? latest;
    String? checkError;
    var companions = const <CompanionAsset>{};
    String? companionsError;
    await Future.wait<void>([
      () async {
        try {
          latest = await _manager.peekLatestOnlineVersion();
        } catch (e) {
          checkError = e.toString();
          AppLogger.instance.info('בדיקת עדכונים ברשת (ספרייה) לא הצליחה: $e');
        }
      }(),
      () async {
        try {
          companions = await _manager.peekPendingCompanions();
        } catch (e) {
          companionsError = e.toString();
          AppLogger.instance.info('בדיקת הקבצים הנלווים ברשת לא הצליחה: $e');
        }
      }(),
    ]);
    AppLogger.instance.info(
      'checkOnline (ספרייה): latest=$latest '
      'companions=[${_companionNames(companions)}]',
    );
    String? semanticError;
    SemanticEngineIncompatibleException? semanticIncompatible;
    var semanticPending = false;
    var checkedSemantic = false;
    int? semanticBytes;
    if (checkError == null &&
        _semanticPreference != SemanticDownloadPreference.never) {
      try {
        semanticPending = await _manager.peekPendingSemanticSearch();
        semanticBytes = _manager.peekedSemanticBytes;
        semanticIncompatible = _manager.peekedSemanticIncompatibility;
        if (semanticIncompatible != null) {
          AppLogger.instance.info('$semanticIncompatible');
        }
      } catch (e) {
        semanticError = e.toString();
        AppLogger.instance.info('בדיקת החיפוש החכם ברשת לא הצליחה: $e');
      }
      checkedSemantic = true;
    }
    int? bound;
    _readableMirrorCurrent = false;
    if (checkError == null) {
      try {
        _readableMirrorCurrent = await _manager.isReadableMirrorCurrent();
      } catch (e) {
        AppLogger.instance.info('בדיקת תאימות ההורדה השמורה לא הצליחה: $e');
      }
    }
    if (checkError == null && companionsError == null) {
      try {
        bound = await _manager.peekedDownloadBytesBound();
      } catch (e) {
        AppLogger.instance.info('חישוב גודל ההורדה של הספרייה לא הצליח: $e');
      }
    }
    onlineLatestVersion = latest;
    final checkedLatest = latest;
    if (_readableMirrorCurrent &&
        checkedLatest != null &&
        checkedLatest > (targetVersion ?? 0)) {
      newerLibraryNeedsOtzaria = checkedLatest;
    }
    onlineCheckError = checkError;
    onlinePendingCompanions = companions;
    onlineCompanionsCheckError = companionsError;
    onlineSemanticPending = semanticPending;
    onlineSemanticIncompatibility = semanticIncompatible;
    onlineSemanticCheckError = semanticError;
    semanticChecked = checkedSemantic;
    onlineSemanticBytes = semanticBytes;
    onlineCheckedAt = DateTime.now();
    _sizeRun++;
    onlineDownloadBytesBound = bound;
    notifyListeners();
  }

  /// מוריד עדכוני ספרייה מהרשת אל [mirrorDir]. **הפעולה היחידה כאן שדורשת
  /// אינטרנט.** לא נוגעת ב-DB. לא זורקת — כשל נשמר ב-[downloadError].
  ///
  /// [isCancelled] נבדק לאורך כל ההורדה, כולל באמצע נכס. ביטול אינו שגיאה:
  /// המצב חוזר ל-[MirrorDownloadStatus.idle] בלי [downloadError].
  Future<void> download({
    bool includeSemanticSearch = false,
    bool Function()? isCancelled,
  }) async {
    downloadStatus = MirrorDownloadStatus.downloading;
    downloadStage = null;
    downloadCompanionStage = null;
    downloadDoneAssets = null;
    downloadTotalAssets = null;
    downloadReceivedBytes = null;
    downloadTotalBytes = null;
    downloadError = null;
    downloadCause = null;
    // הדיווח מתייחס להורדה הזו בלבד — הישן היה מתאר מצב שכבר הוחלף.
    personalDownloadNote = null;
    downloadNeedsOtzariaInstaller = false;
    newerLibraryNeedsOtzaria = null;
    keptNewerMirror = false;
    libraryMetadataUnreadable = false;
    notifyListeners();

    StorageFullException? warnedStorageFull;
    try {
      int? readableDbSchema;
      if (_mirroredReadableDbSchema case final readSchema?) {
        readableDbSchema = await readSchema();
        if (readableDbSchema == null) {
          downloadStatus = MirrorDownloadStatus.error;
          downloadNeedsOtzariaInstaller = true;
          downloadError =
              AppL10n.strings.libraryScreen.downloadNeedsOtzariaInstaller;
          AppLogger.instance.info(
            'הורדת הספרייה לא התחילה: אין בכונן מתקין אוצריא מתאים',
          );
          notifyListeners();
          return;
        }
      }
      final outcome = await _manager.downloadToMirror(
        includeSemanticSearch: includeSemanticSearch,
        readableDbSchema: readableDbSchema,
        onStage: (stage) {
          downloadStage = stage;
          // **בלי איפוס הבייטים.** הנכסים יורדים במקביל ומדווחים מונה אחד
          // מצטבר לכל ההורדה (ראו `ByteProgressAggregator`), ולכן איפוס בכל
          // הכרזת שלב היה מרוקן מד שדווקא כן מתקדם.
          notifyProgress();
        },
        onCompanionStage: (stage) {
          downloadCompanionStage = stage;
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
        onCompanionWarning: (name, error) {
          AppLogger.instance.info('הורדת הקובץ הנלווה "$name" נכשלה: $error');
          // כונן מלא אינו כשל נקודתי: הוא משתק את כל הכתיבות שאחריו.
          warnedStorageFull ??= findStorageFull(error);
        },
        isCancelled: isCancelled,
      );
      if (warnedStorageFull case final full?) throw full;
      downloadStatus = MirrorDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      newerLibraryNeedsOtzaria = outcome.newerNeedsOtzaria;
      keptNewerMirror = outcome.keptNewerMirror;
      libraryMetadataUnreadable = outcome.unreadableManifests.isNotEmpty;
      personalFromVersion = outcome.personalFromVersion ?? personalFromVersion;
      // "Nothing newer" beside a newer release left online contradicts itself.
      personalDownloadNote = !personalUpdateMode ||
              outcome.libraryLeftAsIs ||
              (outcome.upToDate && outcome.newerNeedsOtzaria != null)
          ? null
          : outcome.upToDate
              ? LibraryPersonalDownloadNote.upToDate
              : outcome.repairedDamagedMirror
                  ? LibraryPersonalDownloadNote.mirrorRepaired
                  : outcome.personalFromVersion == null
                      ? LibraryPersonalDownloadNote.versionUnknown
                      : LibraryPersonalDownloadNote.fromRecordedVersion;
      notifyListeners();
      // עכשיו יש מול מה להשוות — מרעננים את מצב העדכון מהתיקייה החדשה.
      await checkForUpdate();
      // הנלווים יכולים להיכשל בנפרד; בודקים מה עדיין חסר אחרי ההורדה.
      if (!(isCancelled?.call() ?? false)) {
        await checkOnline();
        failedCompanions = {...onlinePendingCompanions};
        if (includeSemanticSearch) {
          semanticDownloadFailed = onlineSemanticPending;
        }
        notifyListeners();
      }
      return;
    } catch (e, st) {
      // ביטול של המשתמש אינו תקלה, ולכן אינו נשאר על המסך כשגיאה. השלב
      // מתאפס גם הוא — אחרת הכרטיס ממשיך לתאר נכס שהורדתו נפסקה.
      if (isCancelled?.call() ?? false) {
        downloadStatus = MirrorDownloadStatus.idle;
        downloadStage = null;
        downloadCompanionStage = null;
        AppLogger.instance.info('הורדת עדכוני ספרייה בוטלה: $e');
      } else {
        downloadStatus = MirrorDownloadStatus.error;
        downloadError = e.toString();
        downloadCause = e;
        AppLogger.instance.error('הורדת עדכוני ספרייה נכשלה', e, st);
      }
    }
    notifyListeners();
  }

  /// קורא את גרסת המסד של המחשב הזה ורושם אותה כנקודת המוצא להורדה אישית —
  /// **רק מכאן**, כלומר מלחיצה מפורשת. מחזיר `false` אם לא נמצא מסד לקרוא
  /// ממנו, כדי שהמסך יאמר זאת במקום להציג הצלחה שקטה.
  Future<bool> capturePersonalVersion() async {
    personalCaptureError = null;
    try {
      final version = await _manager.captureLocalDbVersion();
      if (version == null) return false;
      personalFromVersion = version;
      _readableMirrorCurrent = false;
      _refreshDownloadSize();
      // בדיקה מחדש ולא רק notify: המחשב הזה הפך זה עתה ליעד, ו-
      // [LibraryModuleStatus.personalTargetElsewhere] שהוצג לו כבר אינו נכון.
      await checkForUpdate();
      return true;
    } catch (e, st) {
      AppLogger.instance
          .error('רישום גרסת המסד לעדכון אישי נכשל${_errorDetail(e)}', e, st);
      if (e is LocalDbUnreadableException) personalCaptureError = e.toString();
      return false;
    }
  }

  /// סיבת כשל בקריאת הגרסה לרישום אישי; `null` כשלא נמצא מסד עם גרסה.
  String? personalCaptureError;

  @visibleForTesting
  static bool unreadableDbNeedsElevation(Object e) =>
      e is LocalDbUnreadableException &&
      e.reason == LocalDbUnreadableReason.readOnlyLocation;

  static String _errorDetail(Object e) => switch (e) {
        LocalDbUnreadableException() =>
          ' (${e.reason.name}, SQLite ${e.extendedResultCode}: ${e.detail})',
        LibraryMirrorDamagedException() => ' (${e.detail})',
        _ => '',
      };

  /// הקבצים הנלווים שממתינים, בשמם — זה מה שהמסך אומר במקום "יש עדכון"
  /// סתמי ליד "גרסה 27 → 27". ריק כשההצעה היא על המסד עצמו.
  Set<CompanionAsset> pendingCompanions = const {};

  /// פריטים שרשומים במראה אבל הקובץ שלהם חסר או קטוע שם. לא הצעה — אבל כן
  /// נאמר, כי המראה שעל הכונן חלקית.
  Set<CompanionAsset> unavailableCompanions = const {};

  /// מה שרשום במניפסט הנלווים שבמראה — ריק כשהכונן לא נשא אף אחד מהם.
  Set<CompanionAsset> mirroredCompanions = const {};

  /// יש מראה, והיא אינה נושאת אף קובץ נלווה: עדכון מכאן יביא מסד בלי תלמוד,
  /// קטלוג ומילון. בלי ההודעה הזו זה נראה כ"הכול מעודכן" (issue #33).
  bool get mirrorLacksCompanions =>
      !mirrorMissing &&
      mirroredCompanions.isEmpty &&
      (status == LibraryModuleStatus.upToDate ||
          status == LibraryModuleStatus.updateAvailable);

  /// ההצעה הנוכחית היא **רק** על קבצים נלווים: המסד עצמו מעודכן.
  bool get companionsOnly =>
      status == LibraryModuleStatus.updateAvailable &&
      !(_lastCheck?.dbUpdateAvailable ?? false) &&
      (pendingCompanions.isNotEmpty ||
          (semanticPending && semanticConsentGranted));

  /// שמות הפריטים, מופרדים בפסיק — לתצוגה ולדיאלוג.
  String get pendingCompanionNames => [
        if (pendingCompanions.isNotEmpty) _companionNames(pendingCompanions),
        if (semanticPending && semanticConsentGranted)
          AppL10n.strings.libraryDomain.companionSemanticName,
      ].join(', ');
  String get unavailableCompanionNames =>
      _companionNames(unavailableCompanions);

  String _companionNames(Set<CompanionAsset> assets) {
    final t = AppL10n.strings.libraryDomain;
    return assets
        .map((a) => switch (a) {
              CompanionAsset.talmud => t.companionTalmudName,
              CompanionAsset.catalog => t.companionCatalogName,
              CompanionAsset.dictionary => t.companionDictionaryName,
            })
        .join(', ');
  }

  /// [fresh] — לא מצטרף לבדיקה שכבר רצה (לא ראתה כתיבה של עכשיו). בזמן החלה
  /// אין בדיקה, כמו תמיד: ההחלה בודקת בסופה.
  Future<void> checkForUpdate({bool fresh = false}) async {
    if (fresh) {
      try {
        await _checkInFlight;
      } catch (_) {}
    }
    return _joinOrStartCheck();
  }

  Future<void> _joinOrStartCheck() {
    if (_applying) return Future.value();
    final inFlight = _checkInFlight;
    if (inFlight != null) return inFlight;
    final started = _runCheckForUpdate();
    _checkInFlight = started;
    return started.whenComplete(() {
      if (identical(_checkInFlight, started)) _checkInFlight = null;
    });
  }

  Future<void> _runCheckForUpdate() async {
    status = LibraryModuleStatus.checking;
    needsElevation = false;
    errorMessage = null;
    canRetryWithFullDownload = false;
    notifyListeners();

    // מה שנרשם בלחיצה — כולל במחשב אחר, דרך קובץ ה-state שנוסע על הכונן.
    personalFromVersion = await _manager.recordedPersonalDbVersion();
    // ומי נרשם: המראה של עדכון אישי נבנית לגרסה של המחשבים שנרשמו, ולכן
    // "אין מסלול" במחשב שאינו אחד מהם אינו תקלה אלא מראה של מישהו אחר.
    personalTargetIsThisMachine =
        !personalUpdateMode || await _manager.isRegisteredForPersonalUpdate();
    registeredMachines = await _loadRegisteredMachines();

    // **לא `_lastCheck`.** הוא נכתב רק בנתיב ההצלחה, ובמסלולי החריגה הוא
    // מחזיק את התוצאה של הריצה הקודמת — שורת אבחון שקוראת ממנו משקרת.
    LibraryUpdateCheckResult? check;
    localDbUnreadable = false;
    try {
      check = await _manager.checkForUpdate();
      _incompleteMirrorDownload = check.mirrorDownloadIncomplete;
      _lastCheck = check;
      isFreshInstall = check.isFreshInstall;
      mirrorMissing = false;
      mirrorDamaged = false;
      // שגיאה מבדיקה קודמת אינה מתארת את זו: `LibraryScreen` הציג אותה כל עוד
      // השדה מלא, בלי קשר ל-status, ולכן היא שרדה בדיקה שהצליחה.
      errorMessage = null;
      canRetryWithFullDownload = false;
      pendingCompanions = check.pendingCompanions;
      unavailableCompanions = check.unavailableCompanions;
      mirroredCompanions = check.mirroredCompanions;
      semanticPending = check.semanticPending;
      semanticConsentGranted = check.semanticConsentGranted;
      mirrorSemanticIncompatibility = check.semanticIncompatibility;

      if (check.needsManualDbPath) {
        status = LibraryModuleStatus.needsManualPath;
      } else {
        localVersion = check.localVersion?.dbVersion;
        // הגרסה שבסוף התהליך, ולא זו של המסד המלא: התקנה טרייה שנוחתת על מסד
        // מלא ישן ומושלמת ב-patches הבטיחה למשתמש את הגרסה הישנה.
        targetVersion = check.plan?.finalTargetVersion;

        if (check.plan?.kind == LibraryUpdatePlanKind.blocked) {
          // ההודעה האדומה נשמרת למי שבאמת תקוע. במחשב המקוון, שרק הוריד
          // בשביל מחשב אחר, "אין מסלול דלתא" הוא מצב תקין — ראו
          // [LibraryModuleStatus.personalTargetElsewhere].
          if (personalTargetIsThisMachine) {
            status = LibraryModuleStatus.error;
            errorMessage = await _otzariaFirstMessage(check) ??
                check.plan?.reason ??
                AppL10n
                    .strings.libraryDomain.blockedNeedsManualActionWithPeriod;
          } else {
            status = LibraryModuleStatus.personalTargetElsewhere;
          }
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
      mirrorDamaged = false;
      _lastCheck = null;
      mirrorSemanticIncompatibility = null;
      pendingCompanions = const {};
      unavailableCompanions = const {};
      mirroredCompanions = const {};
      // הגרסה המקומית ידועה גם בלי מראה: הבדיקה כבר קראה אותה מהמסד לפני
      // שנכשלה. בלי זה המסך מציג "לא ידוע" למסד שנמצא ונקרא בהצלחה — מה
      // שמשתמש שבחר את הקובץ ידנית רואה כ"לא מזהה את המסד".
      final local = await _manager.readLocalVersion();
      localVersion = (local?.hasVersionMeta ?? false) ? local!.dbVersion : null;
      targetVersion = null;
    } catch (e, st) {
      status = LibraryModuleStatus.error;
      errorMessage = e.toString();
      _lastCheck = null;
      mirrorSemanticIncompatibility = null;
      localDbUnreadable = e is LocalDbUnreadableException;
      mirrorDamaged = e is LibraryMirrorDamagedException;
      needsElevation = unreadableDbNeedsElevation(e);
      pendingCompanions = const {};
      unavailableCompanions = const {};
      mirroredCompanions = const {};
      AppLogger.instance.error('checkForUpdate נכשל${_errorDetail(e)}', e, st);
      if (mirrorDamaged) {
        // כמו במראה חסרה: המסד נקרא לפני שהמראה נכשלה.
        final local = await _manager.readLocalVersion();
        localVersion =
            (local?.hasVersionMeta ?? false) ? local!.dbVersion : null;
        targetVersion = null;
      }
    }
    await _refreshChangesNotes(check);
    // הבדיקה עצמה כבר איתרה את הנתיב — גם כשהיא נכשלה אחר כך (למשל אין
    // מראה). קריאה נפרדת ל-`currentDbPath()` הייתה חוזרת על כל האיתור.
    dbPath = _manager.lastResolvedDbPath;
    installTargetPath = _manager.lastInstallDbPath;
    // בקשה שנכתבה בהרצה קודמת ולא נמסרה עדיין — הסימון יושב לצד המסד, ולכן
    // הוא נקרא כאן ולא רק אחרי עדכון שנעשה בהרצה הזאת.
    await _refreshPendingReindex();
    if (isDisposed) return;
    // **שורה אחת בכל בדיקה, וזו ששווה הכול.** בלעדיה בדיקה שהצליחה והכריזה
    // "יש עדכון" לא השאירה שום עקבה, ו"מציע לעדכן בכל פתיחה" לא היה ניתן
    // לאבחון מהלוג בכלל. `companions` מפריד בין הצעה על המסד לבין קובץ נלווה
    // שאינו נרשם כמותקן — שני באגים שונים לגמרי שנראים אותו דבר על המסך.
    AppLogger.instance.info(
      'checkForUpdate: status=$status kind=${check?.plan?.kind} '
      'local=$localVersion target=$targetVersion '
      'planTarget=${check?.plan?.targetVersion} latest=${check?.latestVersion} '
      'companions=[${_companionNames(pendingCompanions)}] '
      'companionsMissingInMirror=[${_companionNames(unavailableCompanions)}] '
      'companionsInMirror=[${_companionNames(mirroredCompanions)}] '
      'fresh=$isFreshInstall '
      'mirrorMissing=$mirrorMissing mirrorDamaged=$mirrorDamaged '
      'reindex=$hasPendingReindex db=$dbPath',
    );
    notifyListeners();
  }

  /// קוסמטי: כשל בקריאת ההערות מהכונן נרשם ללוג ואינו מכשיל את הבדיקה.
  Future<void> _refreshChangesNotes(LibraryUpdateCheckResult? check) async {
    try {
      final pending =
          check != null && status == LibraryModuleStatus.updateAvailable
              ? await _manager.pendingChangesNotes(check)
              : const <LibraryChangesNote>[];
      final applied = _appliedChangesNotes;
      if (pending.isNotEmpty || applied == null) {
        changesNotes = pending;
        changesNotesApplied = false;
        changesNotesVersion = targetVersion;
        changesNotesRange =
            pending.isEmpty ? 0 : (targetVersion ?? 0) - (localVersion ?? 0);
      } else {
        changesNotes = applied.notes;
        changesNotesApplied = true;
        changesNotesVersion = applied.version;
        changesNotesRange = applied.range;
      }
    } catch (e) {
      changesNotes = const [];
      AppLogger.instance.info('קריאת "מה חדש בספרייה" מהכונן נכשלה: $e');
    }
  }

  Future<void> _rememberAppliedChangesNotes(LocalDbVersion? before) async {
    final reached = localVersion;
    if (before == null ||
        !before.hasVersionMeta ||
        reached == null ||
        reached <= before.dbVersion) {
      return;
    }
    try {
      _appliedChangesNotes = (
        version: reached,
        range: reached - before.dbVersion,
        notes: await _manager.changesNotesBetween(before.dbVersion, reached),
      );
    } catch (e) {
      AppLogger.instance.info('קריאת "מה חדש בספרייה" מהכונן נכשלה: $e');
    }
    await _refreshChangesNotes(_lastCheck);
  }

  Future<String?> _otzariaFirstMessage(LibraryUpdateCheckResult check) async {
    if (!check.needsNewerOtzaria) return null;
    final version = await _mirroredOtzariaUpdate?.call();
    if (version == null) return null;
    final readable = OtzariaCapabilities.readableDbSchemaForAppVersion(version);
    final current = check.readableDbSchemaVersion;
    if (readable == null || current == null || readable <= current) {
      return null;
    }
    return AppL10n.strings.libraryDomain
        .libraryNeedsOtzariaUpdateFromDrive(version);
  }

  Future<void> setCustomDbPath(String dbPath) async {
    await _manager.setCustomDbPath(dbPath, explicit: true);
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
    lastApplyCompleted = false;
    applyNote = null;
    if (_applying) return;
    _applying = true;
    final inFlight = _checkInFlight;
    if (inFlight != null) {
      notifyListeners();
      try {
        await inFlight;
      } catch (_) {}
    }
    final check = _lastCheck;
    if (check == null) {
      _applying = false;
      if (inFlight != null) notifyListeners();
      return;
    }

    // רק החלה שהעלתה את הגרסה מציגה "מה חדש" — לא ניסיון חוזר של נלווים.
    _appliedChangesNotes = null;
    if (changesNotesApplied) {
      changesNotes = const [];
      changesNotesApplied = false;
    }
    status = LibraryModuleStatus.updating;
    stageText = null;
    applyProgress = null;
    applyReceivedBytes = null;
    applyTotalBytes = null;
    errorMessage = null;
    canRetryWithFullDownload = false;
    needsElevation = false;
    notifyListeners();

    final plan =
        useFullDownloadFallback ? check.plan?.fullDownloadFallback : check.plan;
    AppLogger.instance.info(
      'update() מתחיל: kind=${plan?.kind} local=${plan?.localVersion} target=${plan?.targetVersion}',
    );

    // מה נכשל מבין הקבצים הנלווים. נאסף כאן כי `applyUpdate` הוא best-effort
    // לגביהם ואינו זורק — וכשל שלהם הוא בדיוק מה שמשאיר את הבדיקה על
    // "יש עדכון" אחרי החלה שהצליחה.
    final companionFailures = <String, Object>{};

    // התקנה טרייה שההגדרה של אוצריא לא כוונה אליה — היא לא תראה שם ספרים,
    // ורק הודעה מפורשת אומרת למשתמש מה נשאר לו לעשות.
    String? locationNotSetFor;

    try {
      try {
        await _manager.applyUpdate(
          check,
          useFullDownloadFallback: useFullDownloadFallback,
          onProgress: (p) {
            stageText = _describeApplyStage(p);
            if (_isSilentLongStage(p)) {
              _startStageClock(stageText!);
              stageText = _stageTextWithElapsed();
            } else {
              _stopStageClock();
            }
            final done = p.bytesDone;
            final total = p.bytesTotal;
            applyReceivedBytes = done;
            applyTotalBytes = total;
            applyProgress = (done != null && total != null && total > 0)
                ? done / total
                : p.verifyProgress;
            notifyProgress();
          },
          onCompanionWarning: (name, error) {
            companionFailures[name] = error;
            AppLogger.instance.warn('התקנת הקובץ הנלווה "$name" נכשלה: $error');
          },
          onStateWarning: (error) => AppLogger.instance
              .warn('רישום שאחרי ההחלה נכשל (מצב או "מה חדש"): $error'),
          onLibraryLocationFailure: (reason) => AppLogger.instance
              .warn('סיבת הכשל בכתיבת מיקום הספרייה: $reason'),
          onLibraryLocationNotSet: (dbPath) {
            locationNotSetFor = dbPath;
            AppLogger.instance
                .warn('מיקום הספרייה לא נכתב להגדרות של אוצריא: $dbPath');
          },
        );
      } finally {
        _applying = false;
      }
      lastApplyCompleted = true;
      AppLogger.instance.info(
        'החלת העדכון הסתיימה, נלווים שנכשלו=${companionFailures.length}',
      );
      // מרעננים את מצב הבדיקה עצמו (localVersion/targetVersion/status) —
      // עדיף על קביעה ידנית של upToDate, כי זה קורא בפועל את הגרסה
      // שנכתבה ל-DB במקום להניח שהיא תואמת ליעד.
      await checkForUpdate();
      await _rememberAppliedChangesNotes(check.localVersion);
      // המסד עודכן, אבל קובץ נלווה שלא נרשם כמותקן משאיר את הבדיקה על
      // "יש עדכון" — והמשתמש קיבל את אותה הצעה בכל פתיחה בלי הודעה ובלי
      // שגיאה. עכשיו נאמר לו מה נכשל, ונדלקת הצעת ההרשאות כשזו הסיבה.
      if (companionFailures.isNotEmpty &&
          (status == LibraryModuleStatus.updateAvailable ||
              companionFailures.containsKey(
                  AppL10n.strings.libraryDomain.companionSemanticName))) {
        errorMessage = applyNote = AppL10n.strings.libraryDomain
            .companionsInstallFailed(companionFailures.keys.join(', '));
        needsElevation = companionFailures.values.any(Elevation.isAccessDenied);
        if (companionFailures
            .containsKey(AppL10n.strings.libraryDomain.companionSemanticName)) {
          status = LibraryModuleStatus.error;
          canRetryWithFullDownload = false;
        }
      }
      // גובר על אזהרת הנלווים: ספרייה שאוצריא לא תמצא בכלל היא התקלה
      // הגדולה מבין השתיים.
      final notSet = locationNotSetFor;
      if (notSet != null) {
        errorMessage = applyNote = AppL10n.strings.libraryDomain
            .libraryLocationNeedsManualSetting(notSet);
      }
    } catch (e, st) {
      status = LibraryModuleStatus.error;
      // מסד שיושב בתיקייה מוגנת (Program Files) נכשל כאן, וההודעה של מערכת
      // ההפעלה לבדה אינה אומרת למשתמש מה לעשות.
      errorMessage = Elevation.describe(e);
      needsElevation = Elevation.isAccessDenied(e);
      canRetryWithFullDownload =
          !useFullDownloadFallback && check.canFallBackToFullDownload;
      // שרשרת דלתא שנקטעה באמצע כן שינתה ספרים, והסימון נכתב — ולכן גם
      // המסלול הזה מציע את עדכון האינדקס.
      await _refreshPendingReindex();
      AppLogger.instance.error('update() נכשל', e, st);
    }
    _stopStageClock();
    notifyListeners();
  }

  /// שלב שיכול להימשך דקות בלי לדווח בייטים ובלי אחוזים. אימות ה-hash
  /// שבמסלול הדלתא **אינו** כזה — הוא מדווח `verifyProgress`.
  static bool _isSilentLongStage(LibraryApplyProgress p) =>
      p.stage == LibraryApplyStage.verifying ||
      p.stage == LibraryApplyStage.writingFullDb;

  /// מתחיל שעון לשלב ששמו [base], ומפעיל טיימר רק כשזו התחלה חדשה.
  void _startStageClock(String base) {
    if (!_stageClock.start(base)) return;
    _stageTicker?.cancel();
    _stageTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      stageText = _stageTextWithElapsed();
      notifyProgress();
    });
  }

  void _stopStageClock() {
    _stageTicker?.cancel();
    _stageTicker = null;
    _stageClock.stop();
  }

  String _stageTextWithElapsed() =>
      _stageClock.text(AppL10n.strings.libraryDomain.applyStageElapsed);

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
        // חילוץ ישירות מהמראה מאמת את החתימה תוך כדי — ואז מד הבייטים הזה
        // הוא גם מד ההתקדמות של האימות.
        return p.verifyStage == 'sourceHash'
            ? t.applyDecompressingAndVerifyingFullDb
            : t.applyDecompressingFullDb;
      case LibraryApplyStage.writingFullDb:
        return t.applyWritingFullDb;
      case LibraryApplyStage.verifying:
        // "מוודא תקינות..." לבדו חזר כמה פעמים בלי לומר על מה מחכים.
        final verifyStage = p.verifyStage;
        return verifyStage == null
            ? t.applyVerifying
            : t.applyVerifyStage(verifyStage);
      case LibraryApplyStage.installingCompanions:
        // ההתקנה מדווחת טקסט מוכן (שם הפריט שבטיפול); ה-fallback לשלב כולו.
        return p.statusText ?? t.applyInstallingCompanions;
      case LibraryApplyStage.done:
        return t.applyDone;
    }
  }

  @override
  void dispose() {
    _stopStageClock();
    _manager.dispose();
    super.dispose();
  }
}

/// הריצות שנמדדו מתפזרות פי 3–5 סביב האומדן של [ApplyTimeEstimate]
/// (129–581 שניות מול 262), ולכן מוצג טווח ולא מספר אחד.
({int low, int high})? libraryApplyMinutes(
  LibraryUpdatePlan? plan, {
  ApplyTimeEstimate estimate = const ApplyTimeEstimate(),
}) {
  if (plan == null) return null;
  final double seconds;
  switch (plan.kind) {
    case LibraryUpdatePlanKind.delta:
      seconds = estimate
          .deltaRouteSeconds(plan.deltaSteps.map((s) => s.compressedSize));
    case LibraryUpdatePlanKind.fullDownload:
      final size = plan.fullDbAsset?.size ?? 0;
      if (size <= 0) return null;
      final followUp = plan.followUpDelta?.deltaSteps ?? const [];
      seconds = estimate.fullRouteSeconds(size) +
          estimate.deltaRouteSeconds(followUp.map((s) => s.compressedSize));
    default:
      return null;
  }
  if (seconds <= 0) return null;
  return (
    low: ApplyTimeEstimate.minutesOf(seconds * 0.5),
    high: ApplyTimeEstimate.minutesOf(seconds * 2.5),
  );
}
