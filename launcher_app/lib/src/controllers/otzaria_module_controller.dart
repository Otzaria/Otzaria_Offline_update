import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import '../services/app_logger.dart';
import '../services/elevation.dart';
import 'dispose_guard.dart';
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

  /// המותקן חדש מהגרסה שבתיקייה המקומית — אין מה להתקין: הכלי אינו מתקין
  /// גרסה ישנה מהמותקנת. מצב תקין, לא שגיאה.
  installedIsNewer,
}

/// מצב ההורדה מהרשת אל התיקייה המקומית, נפרד מ-[OtzariaModuleStatus].
enum OtzariaDownloadStatus { idle, downloading, done, error }

class OtzariaModuleController extends ChangeNotifier
    with DisposeGuard, ProgressNotifier {
  OtzariaModuleController({
    required String dataDir,
    String? stateDir,
    bool preferPrerelease = false,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
    Future<String?> Function()? pendingLaunchUri,
    Future<void> Function()? onLaunchUriDelivered,
    bool Function()? isLibraryApplying,
    OtzariaLauncher launcher = const OtzariaLauncher(),
    OtzariaProcessCloser? processCloser,
    OtzariaTargetPlatform? platform,
    @visibleForTesting OtzariaManager? manager,
  })  : _preferPrerelease = preferPrerelease,
        _pendingLaunchUri = pendingLaunchUri,
        _onLaunchUriDelivered = onLaunchUriDelivered,
        _isLibraryApplying = isLibraryApplying,
        _runningLocator = runningLocator,
        _processCloser =
            processCloser ?? OtzariaProcessCloser(locator: runningLocator),
        _manager = manager ??
            OtzariaManager(
              dataDir: dataDir,
              stateDir: stateDir,
              platform: platform,
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
  final bool Function()? _isLibraryApplying;

  bool get libraryApplyActive => _isLibraryApplying?.call() ?? false;

  /// אותו locator שה-manager מקבל — נשמר גם כאן כדי ש-[refreshRunningState]
  /// תוכל לבדוק "אוצריא פתוחה?" לבד, בלי בדיקת גרסאות שלמה.
  final RunningOtzariaLocator _runningLocator;

  /// סוגר את אוצריא לבקשת המשתמש — ראו [closeRunning].
  final OtzariaProcessCloser _processCloser;
  OtzariaUpdateCheckResult? _lastCheck;

  Future<void>? _checkInFlight;
  int _checkInputs = 0;
  bool _installing = false;
  bool _recheckAfterInstall = false;
  bool _preferPrerelease;

  bool get preferPrerelease => _preferPrerelease;

  set preferPrerelease(bool value) {
    if (_preferPrerelease == value) return;
    _preferPrerelease = value;
    _checkInputs++;
    if (!_installing) _manager.preferPrerelease = value;
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

  String? installStage;

  bool _stopSetupWait = false;

  void stopWaitingForSetup() => _stopSetupWait = true;

  /// הודעה שאינה שגיאה — "ביטלת באשף", "האשף עוד פתוח". נפרדת מ-
  /// [errorMessage] כדי שהממשק לא יצבע בחירה של המשתמש כתקלה אדומה.
  String? noticeMessage;

  /// איך נגמרה ההתקנה האחרונה — בלי לפענח את [noticeMessage].
  OtzariaInstallResult? lastInstallResult;

  /// מה נאמר כשההתקנה בוטלה או שהאשף עוד פתוח. נפרד מ-[noticeMessage], שגם
  /// סירוב להפעיל בזמן עדכון ספרייה כותב אליו.
  String? lastInstallNotice;

  /// ההתקנה הסתיימה ואוצריא לא נמצאה — התיקון: "בחירת מיקום ידנית".
  bool installNotDetected = false;

  /// הכשל האחרון היה "אין הרשאה" — ראו [Elevation] ואת התאום שלו
  /// ב-`LibraryModuleController`.
  bool needsElevation = false;

  /// הגרסאות שבתיקייה המקומית לפי ערוץ — `null` לערוץ שאין בו גרסה.
  String? stableVersion;
  String? prereleaseVersion;

  /// שתי הגרסאות יושבות בתיקייה — רק אז מוצגת למשתמש בחירת ערוץ.
  bool hasChannelChoice = false;

  /// המותקנת היא הגרסה של הערוץ השני, חדשה מזו שנבחרה — ממתינים לגרסה
  /// חדשה יותר בערוץ שנבחר, ולא מתקינים ישנה.
  bool awaitsNewerInSelectedChannel = false;

  /// על הכונן יושבת חבילת FULL (~2GB) מגרסה ישנה של הלאנצ'ר. ההורדה הבאה
  /// מוחקת אותה, ולכן זה גם מה שמחייב את מודול התוכנה לרוץ אפילו כשאין
  /// גרסה חדשה — אחרת "אין מה להוריד" היה משאיר אותה שם לנצח.
  bool hasStaleFullPackage = false;

  /// האם אוצריא פתוחה, לפי בדיקת התהליך ש-[checkForUpdate] מבצעת ממילא.
  /// כך הלאנצ'ר לא בודק פעם שנייה בעלייה. [refreshRunningState]
  /// מרעננת אותה לבדה.
  bool isRunning = false;

  /// בדיקת התהליך שרצה כרגע, אם רצה — ראו [refreshRunningState].
  Future<bool>? _runningProbe;

  /// בקשת סגירה שנשלחה ועדיין ממתינה — ראו [closeRunning]. הממשק מסמן בה
  /// את הכפתור כטוען, כי הסגירה נמשכת שנייה־שתיים ובלעדיה הלחיצה נראית
  /// כאילו לא קרתה.
  bool isClosing = false;

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
  /// **שני הערוצים** שההצצה מצאה ברשת. הפער מול המראה נמדד ערוץ מול ערוץ —
  /// ראו [hasOnlineUpdate].
  OtzariaChannelReleases? onlineChannels;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  /// הגרסה שברשת בערוץ שהמשתמש בחר — לתצוגה בלבד.
  OtzariaRelease? get onlineLatestRelease =>
      onlineChannels?.select(preferPrerelease: preferPrerelease);

  bool get canLaunch => currentVersion != null && !libraryApplyActive;

  bool get elevatedAsOtherUser => _manager.elevatedAsOtherUser;

  /// התיקייה שלצד התוכנה שממנה מותקנת/מתעדכנת אוצריא — המקור היחיד.
  String get mirrorDir => _manager.mirrorDir;

  /// "מה התחדש" של הגרסה שיושבת במראה המקומית — מוצג אפילו בלי רשת, כי
  /// זה נשמר לצד שאר המטא-דאטה של ה-release.
  String? get latestReleaseNotes => _lastCheck?.latestRelease?.releaseNotes;

  /// "מה חדש" של הגרסה שמותקנת כאן, כשהיא אחת משתי הגרסאות שבכונן.
  String? get installedReleaseNotes {
    final installed = currentVersion;
    final check = _lastCheck;
    if (installed == null || check == null) return null;
    for (final release in [check.stableRelease, check.prereleaseRelease]) {
      if (release == null) continue;
      final tag = release.tagName;
      if (OtzariaUpdateCheckResult.normalizeVersion(tag) ==
              OtzariaUpdateCheckResult.normalizeVersion(installed) &&
          OtzariaUpdateCheckResult.sameBuild(tag, installed)) {
        return release.releaseNotes;
      }
    }
    return null;
  }

  /// `true` אם הבדיקה הקלה מצאה ברשת תג שונה מזה שכבר יושב **במראה
  /// המקומית**. ההשוואה היא מול המראה ולא מול מה שמותקן, כי השאלה שהכרטיס
  /// שואל היא "יש ברשת משהו שעוד לא הורדנו?" — התקנה היא צעד נפרד, ומדידה
  /// מול המותקן השאירה את ההודעה דולקת מיד אחרי הורדה מוצלחת.
  bool get hasOnlineUpdate {
    final online = onlineChannels;
    if (online == null) return false;
    // **כל ערוץ מול המקביל לו**, ולא הנבחר מול הנבחר: ההורדה מביאה את
    // שניהם, ולכן pre-release חדש שהיציב לא זז לצדו הוא "יש מה להביא".
    // בהשוואה על הנבחר בלבד הוא נראה כ"אין חדש", ההורדה דילגה על מודול
    // התוכנה, ובלי שהערוץ ירד לא הופיע גם הפקד שמאפשר לבחור בו.
    return _channelHasMore(online.stable?.tagName, stableVersion) ||
        _channelHasMore(online.prerelease?.tagName, prereleaseVersion);
  }

  /// כמה הורדה למראה תביא לפי הבדיקה ברשת: מתקין שהתג שלו אינו בכונן.
  /// `null` כשלא נבדק או שאין מה למדוד.
  int? get onlineDownloadBytes {
    final online = onlineChannels;
    if (online == null) return null;
    final mirrored = {stableVersion, prereleaseVersion};
    final lacksArm64 = _lastCheck?.mirrorLacksArchitectures ?? false;
    final seen = <String>{};
    var bytes = 0;
    for (final release in [online.stable, online.prerelease]) {
      if (release == null || !seen.add(release.tagName)) continue;
      final arm64 = release.arm64Variant?.installerSizeBytes ?? 0;
      if (!mirrored.contains(release.tagName)) {
        bytes += release.installerSizeBytes + arm64;
      } else if (lacksArm64) {
        bytes += arm64;
      }
    }
    return bytes > 0 ? bytes : null;
  }

  /// יש ברשת תג שאינו זה שיושב במראה באותו ערוץ. ערוץ שאינו ברשת אינו
  /// "עדכון": הניקוי שלו קורה בהורדה הבאה, ולא כדאי שידליק את ההודעה על
  /// משהו שאין מה להוריד עבורו.
  ///
  /// גם מספר ה-build שאחרי ה-`+` נספר: שני התגים כאן הגיעו מגיטהאב, ותיקון
  /// באג שאוצריא מפרסמת באותו מספר גרסה ובמספר build חדש בלבד הוא בהחלט
  /// "יש מה להביא" — ראו [OtzariaUpdateCheckResult.sameBuild].
  static bool _channelHasMore(String? online, String? mirrored) {
    if (online == null) return false;
    if (mirrored == null) return true;
    if (OtzariaUpdateCheckResult.normalizeVersion(online) !=
        OtzariaUpdateCheckResult.normalizeVersion(mirrored)) {
      return true;
    }
    return !OtzariaUpdateCheckResult.sameBuild(online, mirrored);
  }

  /// גרסת התוכנה שנמצאה ברשת וטרם ירדה למראה — לתצוגה בלבד. `null` כשאין
  /// הפרש גרסאות, למשל כשההבדל היחיד הוא החבילה המלאה שחסרה.
  ///
  /// הערוץ הנבחר קודם, ואחריו השני: גם pre-release שירד עבור מי שעוד לא
  /// ביקש אותו הוא גרסה שההורדה תביא, ולכן ראוי שתיאמר בשמה.
  String? get onlineUpdateVersion {
    final online = onlineChannels;
    if (online == null) return null;
    final selectedFirst = preferPrerelease
        ? [
            (online.prerelease?.tagName, prereleaseVersion),
            (online.stable?.tagName, stableVersion),
          ]
        : [
            (online.stable?.tagName, stableVersion),
            (online.prerelease?.tagName, prereleaseVersion),
          ];
    for (final (onlineTag, mirroredTag) in selectedFirst) {
      if (_channelHasMore(onlineTag, mirroredTag)) return onlineTag;
    }
    return null;
  }

  /// בודק ברשת מה הגרסה העדכנית ביותר — **פעולת רשת קלה**, בלי הורדת
  /// installer. כשל (בעיקר "אין חיבור") הוא מצב תקין: נשמר ב-
  /// [onlineCheckError] ולא נזרק, כדי שבדיקה אוטומטית לא תציג שגיאה
  /// מפחידה כשפשוט אין רשת כרגע.
  Future<void> checkOnline() async {
    // הכשל הקודם נשאר עד התשובה החדשה — ראו `LibraryModuleController.checkOnline`.
    notifyListeners();

    try {
      onlineChannels = await _manager.peekOnlineChannels();
      onlineCheckError = null;
    } catch (e) {
      onlineChannels = null;
      onlineCheckError = e.toString();
      // ראו `LibraryModuleController.checkOnline` — בלי stack trace בכוונה.
      AppLogger.instance.info('בדיקת עדכונים ברשת (אוצריא) לא הצליחה: $e');
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  /// מרענן **רק** את "אוצריא פתוחה?" — כדי שסגירה שלה תזוהה בזמן שהלאנצ'ר
  /// פתוח, ולא רק בהפעלה מחדש שלו. קורא שמגיע בזמן בדיקה שרצה מצטרף אליה
  /// במקום להריץ בדיקה שנייה.
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

  Object? _loggedProbeFailure;

  void _noteProbeFailure() {
    final failure = RunningOtzariaLocator.lastProbeFailure;
    if (failure != null && failure != _loggedProbeFailure) {
      AppLogger.maybeInstance?.warn(
        'בדיקת "אוצריא פתוחה?" נכשלה ונחשבת "סגורה": $failure',
      );
    }
    _loggedProbeFailure = failure;
  }

  Future<bool> _probeRunning() async {
    try {
      final probe = await _runningLocator.probe();
      _noteProbeFailure();
      if (isDisposed) return probe.isRunning;
      final changed = isRunning != probe.isRunning;
      isRunning = probe.isRunning;
      if (changed) notifyListeners();
      return isRunning;
    } finally {
      _runningProbe = null;
    }
  }

  Future<bool> closeRunning() async {
    if (isClosing) return !isRunning;
    isClosing = true;
    notifyListeners();
    try {
      final closed = await _processCloser.close();
      if (isDisposed) return closed;
      await refreshRunningState(force: true);
      return closed;
    } catch (e, st) {
      AppLogger.instance.error('סגירת אוצריא מהלאנצ׳ר נכשלה', e, st);
      return false;
    } finally {
      isClosing = false;
      if (!isDisposed) notifyListeners();
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

  static const Duration _onlineReuseWindow = Duration(minutes: 10);

  OtzariaChannelReleases? get _freshOnlineChannels {
    final checkedAt = onlineCheckedAt;
    if (checkedAt == null ||
        DateTime.now().difference(checkedAt) >= _onlineReuseWindow) {
      return null;
    }
    return onlineChannels;
  }

  Future<void> download({bool Function()? isCancelled}) async {
    downloadStatus = OtzariaDownloadStatus.downloading;
    downloadReceived = null;
    downloadTotal = null;
    downloadStage = null;
    downloadError = null;
    notifyListeners();

    try {
      await _manager.downloadToMirror(
        online: _freshOnlineChannels,
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

  /// מבטיח שהבדיקה המקומית כבר רצה — בלי להריץ שנייה כשאחת בדרך.
  ///
  /// הבדיקה הקלה ברשת יוצאת בעלייה **במקביל** למקומית, ומי שתלוי בגרסאות
  /// שהמקומית מגלה (הבילד של כל תוסף נבחר לפיהן) חייב להמתין לה: בלעדיה
  /// רשימת הגרסאות יוצאת ריקה, ההצצה נופלת לבילד החי של כל תוסף, ומדווחת
  /// "חסר" על מה שההורדה לעולם לא תביא.
  Future<void> ensureChecked() async {
    if (_lastCheck != null) return;
    await (_checkInFlight ?? checkForUpdate());
  }

  Future<void> checkForUpdate() {
    if (_installing) {
      _recheckAfterInstall = true;
      return Future.value();
    }
    final inFlight = _checkInFlight;
    if (inFlight != null) return inFlight;
    final started = _checkForUpdate();
    _checkInFlight = started;
    return started.whenComplete(() {
      if (identical(_checkInFlight, started)) _checkInFlight = null;
    });
  }

  Future<void> _checkForUpdate() async {
    status = OtzariaModuleStatus.checking;
    needsElevation = false;
    installNotDetected = false;
    notifyListeners();

    try {
      OtzariaUpdateCheckResult check;
      int inputs;
      do {
        inputs = _checkInputs;
        check = await _manager.checkForUpdate();
      } while (inputs != _checkInputs);
      _lastCheck = check;
      currentVersion = check.currentState?.installedTagName;
      launchPath = check.currentState?.launchPath;
      latestVersion = check.latestRelease?.tagName;
      stableVersion = check.stableRelease?.tagName;
      prereleaseVersion = check.prereleaseRelease?.tagName;
      hasChannelChoice = check.hasChannelChoice;
      awaitsNewerInSelectedChannel = check.awaitsNewerInSelectedChannel;
      hasStaleFullPackage =
          check.hasStaleFullPackage || check.mirrorLacksArchitectures;
      isRunning = check.isOtzariaRunning;
      _noteProbeFailure();
      status = switch (check) {
        _ when check.needsDownload => OtzariaModuleStatus.needsDownload,
        _ when check.installedIsNewer => OtzariaModuleStatus.installedIsNewer,
        _ when check.updateAvailable => OtzariaModuleStatus.updateAvailable,
        _ => OtzariaModuleStatus.upToDate,
      };
      errorMessage = null;
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      errorMessage = e.toString();
      AppLogger.instance
          .error('OtzariaModuleController.checkForUpdate נכשל', e, st);
    }
    notifyListeners();
  }

  Future<void> install({bool useWizard = true}) async {
    if (_lastCheck == null || _installing) return;
    if (_refuseWhileLibraryApplies()) return;
    for (var pending = _checkInFlight;
        pending != null;
        pending = _checkInFlight) {
      await pending;
      if (_installing) return;
    }
    final check = _lastCheck;
    if (check == null) return;

    _installing = true;
    _stopSetupWait = false;
    lastInstallResult = null;
    lastInstallNotice = null;
    installNotDetected = false;
    _recheckAfterInstall = false;
    status = OtzariaModuleStatus.installing;
    needsElevation = false;
    noticeMessage = null;
    errorMessage = null;
    notifyListeners();
    AppLogger.instance.info(
      'התקנת אוצריא מתחילה: ${check.currentState?.installedTagName} -> '
      '${check.latestRelease?.tagName}',
    );

    var recheck = false;
    try {
      final state = await _manager.update(
        check,
        useWizard: useWizard,
        onSetupContinuesElsewhere: () {
          installStage = AppL10n.strings.appDomain.setupContinuesElsewhere;
          if (!isDisposed) notifyListeners();
        },
        isWaitCancelled: () => _stopSetupWait || isDisposed,
      );
      currentVersion = state.installedTagName;
      status = OtzariaModuleStatus.upToDate;
      lastInstallResult = OtzariaInstallResult.installed;
      AppLogger.instance.info('התקנת אוצריא הסתיימה בהצלחה');
      recheck = useWizard;
    } on OtzariaInstallCancelled catch (e) {
      noticeMessage = lastInstallNotice = e.toString();
      lastInstallResult = OtzariaInstallResult.cancelled;
      AppLogger.instance.info('התקנת אוצריא בוטלה באשף');
      recheck = true;
    } on OtzariaWizardStillOpen catch (e) {
      noticeMessage = lastInstallNotice = e.toString();
      lastInstallResult = OtzariaInstallResult.wizardStillOpen;
      AppLogger.instance.info('אשף ההתקנה עדיין פתוח — ההתקנה לא זוהתה עדיין');
      recheck = true;
    } catch (e, st) {
      status = OtzariaModuleStatus.error;
      lastInstallResult = OtzariaInstallResult.failed;
      errorMessage = Elevation.describe(e);
      needsElevation = Elevation.isAccessDenied(e);
      installNotDetected = e is OtzariaInstallNotDetected;
      _recheckAfterInstall = false;
      AppLogger.instance.error('התקנת אוצריא נכשלה', e, st);
    } finally {
      _installing = false;
      installStage = null;
      _manager.preferPrerelease = _preferPrerelease;
    }
    if (recheck || _recheckAfterInstall) {
      _recheckAfterInstall = false;
      await checkForUpdate();
      return;
    }
    notifyListeners();
  }

  /// מחזירה את סיבת הכשל — `null` כשנפתחה, או כשסורבה בזמן עדכון ספרייה
  /// (ואז הסיבה ב-[noticeMessage]).
  Future<String?> launch() async {
    if (_refuseWhileLibraryApplies()) return null;
    if (errorMessage != null && status != OtzariaModuleStatus.error) {
      errorMessage = null;
      notifyListeners();
    }
    final uri = await _pendingLaunchUri?.call();
    try {
      await _manager.launch(withUri: uri);
      if (uri != null) await _onLaunchUriDelivered?.call();
      if (!isRunning) {
        isRunning = true;
        notifyListeners();
      }
      return null;
    } catch (e, st) {
      final message = e.toString();
      // שגיאת בדיקה או התקנה שבגיבור נשארת; כשל ההפעלה נאמר בהודעה בלבד.
      if (status != OtzariaModuleStatus.error) errorMessage = message;
      AppLogger.instance.error('OtzariaModuleController.launch() נכשל', e, st);
      notifyListeners();
      return message;
    }
  }

  /// מוסר לאוצריא את בקשת עדכון אינדקס החיפוש — הפעולה היזומה, כשהמשתמש
  /// אינו רוצה לחכות להפעלה הבאה. אוצריא סגורה תיפתח.
  ///
  /// `false` = לא היה למי למסור (למשל לא זוהתה התקנה); הסיבה ב-[errorMessage].
  Future<bool> requestLibraryReindex() async {
    if (_refuseWhileLibraryApplies()) return false;
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

  bool _refuseWhileLibraryApplies() {
    if (!libraryApplyActive) return false;
    noticeMessage = AppL10n.strings.home.libraryApplyActive;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}

enum OtzariaInstallResult { installed, cancelled, wizardStillOpen, failed }
