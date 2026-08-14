import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import '../services/app_logger.dart';
import 'progress_notifier.dart';

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

  /// המותקן חדש מהגרסה שבתיקייה המקומית — אין מה להתקין, כי התקנה הייתה
  /// נסיגת גרסה. מצב תקין, לא שגיאה.
  installedIsNewer,
}

/// מצב ההורדה מהרשת אל התיקייה המקומית, נפרד מ-[OtzariaModuleStatus].
enum OtzariaDownloadStatus { idle, downloading, done, error }

/// עוטף את [OtzariaManager] כמצב הניתן לצפייה עבור הדשבורד. שתי פעולות
/// נפרדות: [download] מביא גרסה מהרשת אל התיקייה שלצד התוכנה (הפעולה
/// היחידה שדורשת אינטרנט), ו-[install] מתקין ממנה — גם בלי רשת.
class OtzariaModuleController extends ChangeNotifier with ProgressNotifier {
  OtzariaModuleController({
    required String dataDir,
    bool preferPrerelease = false,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
    Future<String?> Function()? pendingLaunchUri,
    Future<void> Function()? onLaunchUriDelivered,
    // תפר לבדיקות: בלעדיו כל בדיקה שנוגעת ב-[launch] מפעילה את אוצריא
    // האמיתית של מי שמריץ אותה.
    OtzariaLauncher launcher = const OtzariaLauncher(),
  })  : _preferPrerelease = preferPrerelease,
        _pendingLaunchUri = pendingLaunchUri,
        _onLaunchUriDelivered = onLaunchUriDelivered,
        _runningLocator = runningLocator,
        _manager = OtzariaManager(
          dataDir: dataDir,
          preferPrerelease: preferPrerelease,
          runningLocator: runningLocator,
          launcher: launcher,
        );

  final OtzariaManager _manager;

  /// קישור עומק שממתין להיכנס לאוצריא בהפעלה הבאה (עדכון אינדקס אחרי עדכון
  /// מסד), ומה שמסמן שנמסר. מוזרקים מהלאנצ'ר: המצב עצמו שייך למודול
  /// הספרייה, והמסירה לקובץ ההרצה — כאן.
  final Future<String?> Function()? _pendingLaunchUri;
  final Future<void> Function()? _onLaunchUriDelivered;

  /// אותו locator שה-manager מקבל — נשמר גם כאן כדי ש-[refreshRunningState]
  /// תוכל לבדוק "אוצריא פתוחה?" לבד, בלי בדיקת גרסאות שלמה.
  final RunningOtzariaLocator _runningLocator;
  OtzariaUpdateCheckResult? _lastCheck;
  bool _preferPrerelease;

  /// הערוץ שממנו מתקינים כשיושבות בתיקייה שתי גרסאות. ההורדה מביאה תמיד
  /// את שתיהן, ולכן החלפה כאן אינה דורשת רשת — רק בדיקה מחדש מהדיסק.
  bool get preferPrerelease => _preferPrerelease;

  set preferPrerelease(bool value) {
    if (_preferPrerelease == value) return;
    _preferPrerelease = value;
    _manager.preferPrerelease = value;
    unawaited(checkForUpdate());
  }

  OtzariaModuleStatus status = OtzariaModuleStatus.idle;
  String? currentVersion;

  /// נתיב ההפעלה של אוצריא שזוהתה (`.exe` / חבילת `.app`), או `null` אם לא
  /// זוהתה התקנה. מודול הספרייה משתמש בו כדי לזהות התקנה ניידת/ספרייה
  /// מצורפת — ראו [LibraryDbLocator.otzariaLaunchPath].
  String? launchPath;

  /// הגרסה שיושבת בתיקייה המקומית ומוכנה להתקנה **בערוץ שנבחר**, או null
  /// אם טרם הורדה.
  String? latestVersion;
  String? errorMessage;

  /// הגרסאות שבתיקייה המקומית לפי ערוץ — `null` לערוץ שאין בו גרסה.
  String? stableVersion;
  String? prereleaseVersion;

  /// שתי הגרסאות יושבות בתיקייה — רק אז מוצגת למשתמש בחירת ערוץ.
  bool hasChannelChoice = false;

  /// האם אוצריא פתוחה, לפי בדיקת התהליך ש-[checkForUpdate] מבצעת ממילא.
  /// כך הלאנצ'ר לא מריץ `tasklist` שני משלו בעלייה. [refreshRunningState]
  /// מרעננת אותה לבדה.
  bool isRunning = false;

  /// בדיקת התהליך שרצה כרגע, אם רצה — ראו [refreshRunningState].
  Future<bool>? _runningProbe;

  OtzariaDownloadStatus downloadStatus = OtzariaDownloadStatus.idle;
  int? downloadReceived;
  int? downloadTotal;

  /// מה יורד כרגע — ההורדה מביאה שתי גרסאות בזו אחר זו, ובלי זה מד
  /// ההתקדמות היה מתאפס בלי הסבר.
  String? downloadStage;
  String? downloadError;
  DateTime? lastDownloadedAt;

  /// מצב הבדיקה הקלה ("יש עדכון ברשת?") — נפרד לגמרי מ-[downloadStatus]:
  /// היא לא מורידה כלום, רק שואלת. `null`/`null` = טרם נבדק בהרצה הזו.
  OtzariaRelease? onlineLatestRelease;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  bool get canLaunch => currentVersion != null;

  /// התיקייה שלצד התוכנה שממנה מותקנת/מתעדכנת אוצריא — המקור היחיד.
  String get mirrorDir => _manager.mirrorDir;

  /// "מה התחדש" של הגרסה שיושבת במראה המקומית — מוצג אפילו בלי רשת, כי
  /// זה נשמר לצד שאר המטא-דאטה של ה-release.
  String? get latestReleaseNotes => _lastCheck?.latestRelease?.releaseNotes;

  /// `true` אם הבדיקה הקלה מצאה ברשת תג שונה מזה שכבר יושב **במראה
  /// המקומית**. ההשוואה היא מול המראה ולא מול מה שמותקן, כי השאלה שהכרטיס
  /// שואל היא "יש ברשת משהו שעוד לא הורדנו?" — התקנה היא צעד נפרד, ומדידה
  /// מול המותקן השאירה את ההודעה דולקת מיד אחרי הורדה מוצלחת.
  bool get hasOnlineUpdate {
    final online = onlineLatestRelease;
    if (online == null) return false;
    final mirrored = latestVersion;
    if (mirrored == null) return true;
    return OtzariaUpdateCheckResult.normalizeVersion(online.tagName) !=
        OtzariaUpdateCheckResult.normalizeVersion(mirrored);
  }

  /// בודק ברשת מה הגרסה העדכנית ביותר — **פעולת רשת קלה**, בלי הורדת
  /// installer. כשל (בעיקר "אין חיבור") הוא מצב תקין: נשמר ב-
  /// [onlineCheckError] ולא נזרק, כדי שבדיקה אוטומטית לא תציג שגיאה
  /// מפחידה כשפשוט אין רשת כרגע.
  Future<void> checkOnline() async {
    onlineCheckError = null;
    notifyListeners();

    try {
      onlineLatestRelease = await _manager.peekLatestOnlineRelease();
    } catch (e, st) {
      onlineLatestRelease = null;
      onlineCheckError = e.toString();
      AppLogger.instance.info('בדיקת עדכונים ברשת (אוצריא) לא הצליחה: $e\n$st');
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// מרענן **רק** את "אוצריא פתוחה?" — כדי שסגירה שלה תזוהה בזמן שהלאנצ'ר
  /// פתוח, ולא רק בהפעלה מחדש שלו. קורא שמגיע בזמן בדיקה שרצה מצטרף אליה
  /// במקום להריץ `tasklist` שני.
  ///
  /// [force] מחייב בדיקה שמתחילה **עכשיו**, וממתין לזו שבאוויר לפני כן.
  /// נחוץ לפני פעולה שאוצריא הפתוחה חוסמת: הצטרפות מחזירה תמונה מלפני עד
  /// ~300ms, ובחלון הזה אוצריא יכולה להיפתח — כלומר עדכון מסד שיירוץ תחת
  /// אוצריא פתוחה, בדיוק מה שהבדיקה אמורה למנוע.
  Future<bool> refreshRunningState({bool force = false}) {
    final inFlight = _runningProbe;
    if (inFlight == null) return _runningProbe = _probeRunning();
    if (!force) return inFlight;
    return inFlight.then((_) => _runningProbe ??= _probeRunning());
  }

  Future<bool> _probeRunning() async {
    try {
      final probe = await _runningLocator.probe();
      if (_isDisposed) return probe.isRunning;
      // מודיעים רק על שינוי אמיתי: הרענון חוזר כל 3 שניות כל עוד אוצריא
      // פתוחה, וכל הודעה בונה מחדש את כל עץ הווידג'טים.
      final changed = isRunning != probe.isRunning;
      isRunning = probe.isRunning;
      if (changed) notifyListeners();
      return isRunning;
    } finally {
      _runningProbe = null;
    }
  }

  /// מאמץ התקנה קיימת של אוצריא בתיקייה [dir] שהמשתמש הצביע עליה ידנית
  /// (למשל כשהזיהוי האוטומטי לא מצא אותה). מחזיר `false` בלי לזרוק אם
  /// לא נמצאה שם התקנה תקינה — ה-UI מציג הודעה, לא שגיאה חוסמת.
  Future<bool> adoptInstallDir(String dir) async {
    final detected = await _manager.detectExistingInstall(customDir: dir);
    if (detected == null) return false;
    await _manager.adoptExistingInstall(detected);
    await checkForUpdate();
    return true;
  }

  /// מוריד את הגרסה האחרונה מהרשת אל התיקייה המקומית. לא מתקין.
  ///
  /// ביטול דרך [isCancelled] אינו שגיאה: המצב חוזר ל-
  /// [OtzariaDownloadStatus.idle] בלי [downloadError].
  Future<void> download({bool Function()? isCancelled}) async {
    downloadStatus = OtzariaDownloadStatus.downloading;
    downloadReceived = null;
    downloadTotal = null;
    downloadStage = null;
    downloadError = null;
    notifyListeners();

    try {
      await _manager.downloadToMirror(
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyProgress();
        },
        onChannel: (channel) {
          downloadStage =
              AppL10n.strings.appDomain.downloadingChannel(channel.label);
          downloadReceived = null;
          downloadTotal = null;
          notifyListeners();
        },
        isCancelled: isCancelled,
      );
      downloadStage = null;
      downloadStatus = OtzariaDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      notifyListeners();
      await checkForUpdate();
      return;
    } catch (e, st) {
      downloadStage = null;
      // ביטול של המשתמש אינו תקלה — ראו [LibraryModuleController.download].
      if (isCancelled?.call() ?? false) {
        downloadStatus = OtzariaDownloadStatus.idle;
        AppLogger.instance.info('הורדת גרסת אוצריא בוטלה: $e');
      } else {
        downloadStatus = OtzariaDownloadStatus.error;
        downloadError = e.toString();
        AppLogger.instance.error('הורדת גרסת אוצריא נכשלה', e, st);
      }
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
      launchPath = check.currentState?.launchPath;
      latestVersion = check.latestRelease?.tagName;
      stableVersion = check.stableRelease?.tagName;
      prereleaseVersion = check.prereleaseRelease?.tagName;
      hasChannelChoice = check.hasChannelChoice;
      isRunning = check.isOtzariaRunning;
      status = switch (check) {
        _ when check.needsDownload => OtzariaModuleStatus.needsDownload,
        _ when check.installedIsNewer => OtzariaModuleStatus.installedIsNewer,
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

  /// מפעיל את אוצריא. בקשת עדכון אינדקס שממתינה נוסעת עם ההפעלה הזאת: את
  /// אוצריא המשתמש פותח ממילא, וכך האינדקס מתוקן בלי פעולה נוספת ממנו.
  Future<void> launch() async {
    final uri = await _pendingLaunchUri?.call();
    try {
      await _manager.launch(withUri: uri);
      if (uri != null) await _onLaunchUriDelivered?.call();
      // אוצריא נפתחה עכשיו. מציבים ולא דוגמים, כי התהליך עדיין לא בהכרח
      // מופיע ב-`tasklist` — ואם בכל זאת לא עלה, הרענון המחזורי (שההודעה
      // הזאת מדליקה) יתקן זאת תוך 3 שניות. בלי זה הלאנצ'ר המשיך להציג
      // "סגורה" עד לבדיקה מלאה, ולא הציג את האזהרה לפני עדכון מסד.
      if (!isRunning) {
        isRunning = true;
        notifyListeners();
      }
    } catch (e, st) {
      errorMessage = e.toString();
      AppLogger.instance.error('OtzariaModuleController.launch() נכשל', e, st);
      notifyListeners();
    }
  }

  /// מוסר לאוצריא את בקשת עדכון אינדקס החיפוש — הפעולה היזומה, כשהמשתמש
  /// אינו רוצה לחכות להפעלה הבאה. אוצריא סגורה תיפתח.
  ///
  /// `false` = לא היה למי למסור (למשל לא זוהתה התקנה); הסיבה ב-[errorMessage].
  Future<bool> requestLibraryReindex() async {
    try {
      await _manager.requestLibraryReindex();
      if (!isRunning) {
        isRunning = true;
        notifyListeners();
      }
      return true;
    } catch (e, st) {
      errorMessage = e.toString();
      AppLogger.instance.error('בקשת עדכון האינדקס לאוצריא נכשלה', e, st);
      notifyListeners();
      return false;
    }
  }

  /// רענון התהליך רץ ברקע (טיימר מחזורי בלאנצ'ר) ועלול להסתיים אחרי
  /// השחרור — `notifyListeners` אחרי `dispose` זורק.
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _manager.dispose();
    super.dispose();
  }
}
