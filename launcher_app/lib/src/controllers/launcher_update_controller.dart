import 'package:flutter/foundation.dart';

import '../self_update/launcher_changelog.dart';
import '../self_update/launcher_release.dart';
import '../self_update/launcher_release_client.dart'
    show LauncherDownloadCancelled;
import '../self_update/launcher_self_updater.dart';
import '../self_update/launcher_version.dart';
import '../services/app_logger.dart';
import '../services/elevation.dart';
import 'dispose_guard.dart';
import 'progress_notifier.dart';

enum LauncherUpdateStatus {
  /// טרם נבדק בהרצה הזו.
  idle,

  /// אין בתיקייה גרסה חדשה מזו שרצה.
  upToDate,

  /// גרסה חדשה יושבת בתיקייה ומחכה להתקנה.
  readyToInstall,
  downloading,
  installing,
  error,
}

/// השלב שבו נכשל העדכון — כדי שההודעה תתאר אותו ולא תנחש.
enum LauncherUpdateFailure { check, download, install }

class LauncherUpdateController extends ChangeNotifier
    with DisposeGuard, ProgressNotifier {
  LauncherUpdateController(
      {required String dataDir, LauncherSelfUpdater? updater})
      : _updater = updater ?? LauncherSelfUpdater(dataDir: dataDir);

  final LauncherSelfUpdater _updater;

  LauncherUpdateStatus status = LauncherUpdateStatus.idle;

  /// הגרסה שרצה כרגע — מוצגת גם כשאין שום עדכון.
  String get currentVersion => _updater.currentVersion;

  /// התיקייה בכונן שבה יושבת הגרסה שהורדה — להחלפה ידנית.
  String get mirrorDir => _updater.mirrorDir;

  /// הגרסה שמוכנה בתיקייה, אם יש.
  String? downloadedVersion;

  /// יומן השינויים שנשמר במראה יחד עם [downloadedVersion].
  String? _downloadedChangelog;

  /// מה שהבדיקה הקלה מצאה ברשת — `null` כשלא נבדק או שאין רשת.
  LauncherRelease? onlineRelease;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  String? errorMessage;
  LauncherUpdateFailure? failure;

  /// ההחלפה נכשלה על הרשאות — הלאנצ'ר מותקן בתיקייה מוגנת (`Program Files`).
  bool needsElevation = false;

  /// `false` כשאין לנו את קובץ ההרצה להחלפה (למשל הרצה מ-`flutter run`) —
  /// אז הכפתור "התקנה" אינו מוצג בכלל.
  bool canInstall = false;

  int? downloadReceived;
  int? downloadTotal;

  bool get isDownloading => status == LauncherUpdateStatus.downloading;
  bool get isInstalling => status == LauncherUpdateStatus.installing;

  /// יש בתיקייה גרסה חדשה, מוכנה להתקנה בלי רשת.
  bool get hasUpdateReady => status == LauncherUpdateStatus.readyToInstall;

  bool get hasOnlineUpdate {
    final online = onlineRelease;
    if (online == null) return false;
    final mirrored = downloadedVersion;
    final best =
        mirrored != null && LauncherVersion.isNewer(mirrored, currentVersion)
            ? mirrored
            : currentVersion;
    return LauncherVersion.isNewer(online.tagName, best);
  }

  /// הגרסה שנמצאה ברשת ועדיין לא הורדה. `null` כשאין ברשת חדש ממה שכבר יש —
  /// לא הגרסה שבתיקייה, שאחרי עדכון עצמי היא בדיוק זו שרצה כרגע.
  String? get onlineUpdateVersion =>
      hasOnlineUpdate ? onlineRelease?.version : null;

  /// "מה התחדש" מהגרסה שרצה ועד זו שברשת — `null` כשאין מה להציג.
  String? get onlineWhatsNew {
    final online = onlineRelease;
    final changelog = online?.changelog;
    if (online == null || changelog == null) return null;
    return changelogBetweenVersions(
      changelog: changelog,
      currentVersion: currentVersion,
      latestVersion: online.tagName,
    );
  }

  /// "מה התחדש" מהגרסה שרצה ועד זו שמוכנה בתיקייה — בלי רשת.
  String? get downloadedWhatsNew {
    final version = downloadedVersion;
    final changelog = _downloadedChangelog;
    if (version == null || changelog == null) return null;
    return changelogBetweenVersions(
      changelog: changelog,
      currentVersion: currentVersion,
      latestVersion: version,
    );
  }

  /// בדיקה קלה ברשת. כשל (בעיקר "אין חיבור") הוא מצב תקין ונשמר בשקט, בדיוק
  /// כמו במודולים האחרים — בדיקה אוטומטית לא מציגה שגיאה כשאין רשת.
  Future<void> checkOnline() async {
    // הכשל הקודם נשאר עד התשובה החדשה, כדי ששורת המצב לא תאמר "מחובר" באמצע.
    notifyListeners();

    try {
      onlineRelease = await _updater.peekLatestOnline();
      // בקשה נוספת רק כשיש מה להציע — היומן מוצג בדיאלוג ההצעה.
      final online = onlineRelease;
      if (online != null && hasOnlineUpdate) {
        onlineRelease = await _updater.withChangelog(online);
      }
      onlineCheckError = null;
    } catch (e) {
      onlineRelease = null;
      onlineCheckError = e.toString();
      // ראו `LibraryModuleController.checkOnline` — בלי stack trace בכוונה.
      AppLogger.instance
          .info("בדיקת עדכונים ברשת (הלאנצ'ר עצמו) לא הצליחה: $e");
    }
    onlineCheckedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> checkForUpdate() async {
    await _loadLocal();
    notifyListeners();
  }

  Future<void> _loadLocal({bool cleanupLeftovers = true}) async {
    try {
      final check =
          await _updater.checkForUpdate(cleanupLeftovers: cleanupLeftovers);
      downloadedVersion = check.mirroredVersion;
      _downloadedChangelog = check.mirrored?.release.changelog;
      canInstall = check.canInstall;
      status = check.updateAvailable
          ? LauncherUpdateStatus.readyToInstall
          : LauncherUpdateStatus.upToDate;
      errorMessage = null;
    } catch (e, st) {
      status = LauncherUpdateStatus.error;
      errorMessage = e.toString();
      failure = LauncherUpdateFailure.check;
      AppLogger.instance
          .error('LauncherUpdateController.checkForUpdate נכשל', e, st);
    }
  }

  Future<bool> download() {
    if (isDownloading) return Future.value(false);
    _cancelRequested = false;
    return _downloadRun = _download().whenComplete(() => _downloadRun = null);
  }

  Future<bool>? _downloadRun;
  bool _cancelRequested = false;

  /// עוצר הורדה שרצה ומחכה שתיעצר; החלקי נשמר, וההורדה הבאה ממשיכה ממנו.
  Future<void> cancelAndWait() async {
    final run = _downloadRun;
    if (run == null) return;
    _cancelRequested = true;
    await run;
  }

  Future<bool> _download() async {
    status = LauncherUpdateStatus.downloading;
    downloadReceived = null;
    downloadTotal = null;
    errorMessage = null;
    notifyListeners();

    try {
      await _updater.downloadToMirror(
        release: onlineRelease,
        onProgress: (received, total) {
          downloadReceived = received;
          downloadTotal = total;
          notifyProgress();
        },
        isCancelled: () => _cancelRequested,
      );
      AppLogger.instance.info("גרסה חדשה של הלאנצ'ר הורדה לתיקייה המקומית");
    } on LauncherDownloadCancelled {
      AppLogger.instance.info("הורדת הלאנצ'ר נעצרה; החלקי נשמר להמשך");
      await _loadLocal(cleanupLeftovers: false);
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.instance.error("הורדת גרסת הלאנצ'ר נכשלה", e, st);
      await _loadLocal();
      if (!hasUpdateReady) status = LauncherUpdateStatus.error;
      errorMessage = e.toString();
      failure = LauncherUpdateFailure.download;
      notifyListeners();
      return false;
    }

    await checkForUpdate();
    return true;
  }

  Future<bool> install() async {
    status = LauncherUpdateStatus.installing;
    errorMessage = null;
    needsElevation = false;
    notifyListeners();
    AppLogger.instance.info(
      "התקנת גרסה חדשה של הלאנצ'ר: $currentVersion -> $downloadedVersion",
    );

    try {
      final restarted = await _updater.applyUpdate();
      if (!restarted) {
        status = LauncherUpdateStatus.readyToInstall;
        notifyListeners();
      }
      return restarted;
    } catch (e, st) {
      AppLogger.instance.error("החלפת קובץ ההרצה של הלאנצ'ר נכשלה", e, st);
      await _loadLocal(cleanupLeftovers: false);
      if (!hasUpdateReady) status = LauncherUpdateStatus.error;
      errorMessage = e.toString();
      failure = LauncherUpdateFailure.install;
      needsElevation = Elevation.isAccessDenied(e);
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _updater.dispose();
    super.dispose();
  }
}
