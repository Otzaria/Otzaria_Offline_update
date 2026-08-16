import 'package:flutter/foundation.dart';

import '../self_update/launcher_release.dart';
import '../self_update/launcher_self_updater.dart';
import '../self_update/launcher_version.dart';
import '../services/app_logger.dart';
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

/// עוטף את [LauncherSelfUpdater] כמצב הניתן לצפייה עבור הדשבורד — אותה
/// חלוקה כמו שאר הקונטרולרים: [download] נוגע ברשת, [install] לא.
class LauncherUpdateController extends ChangeNotifier with ProgressNotifier {
  LauncherUpdateController(
      {required String dataDir, LauncherSelfUpdater? updater})
      : _updater = updater ?? LauncherSelfUpdater(dataDir: dataDir);

  final LauncherSelfUpdater _updater;

  LauncherUpdateStatus status = LauncherUpdateStatus.idle;

  /// הגרסה שרצה כרגע — מוצגת גם כשאין שום עדכון.
  String get currentVersion => _updater.currentVersion;

  /// הגרסה שמוכנה בתיקייה, אם יש.
  String? downloadedVersion;

  /// מה שהבדיקה הקלה מצאה ברשת — `null` כשלא נבדק או שאין רשת.
  LauncherRelease? onlineRelease;
  String? onlineCheckError;
  DateTime? onlineCheckedAt;

  String? errorMessage;

  /// `false` כשאין לנו את קובץ ההרצה להחלפה (למשל הרצה מ-`flutter run`) —
  /// אז הכפתור "התקנה" אינו מוצג בכלל.
  bool canInstall = false;

  int? downloadReceived;
  int? downloadTotal;

  bool get isDownloading => status == LauncherUpdateStatus.downloading;
  bool get isInstalling => status == LauncherUpdateStatus.installing;

  /// יש בתיקייה גרסה חדשה, מוכנה להתקנה בלי רשת.
  bool get hasUpdateReady => status == LauncherUpdateStatus.readyToInstall;

  /// יש ברשת גרסה חדשה יותר מזו שכבר הורדה (או מזו שרצה, אם לא הורדה
  /// כלום) — כלומר יש **מה להוריד**. אחרי הורדה מוצלחת זה נכבה מעצמו.
  bool get hasOnlineUpdate {
    final online = onlineRelease;
    if (online == null) return false;
    final best = downloadedVersion ?? currentVersion;
    return LauncherVersion.isNewer(online.tagName, best);
  }

  /// הגרסה שנמצאה ברשת ועדיין לא הורדה. `null` כשאין ברשת חדש ממה שכבר יש —
  /// לא הגרסה שבתיקייה, שאחרי עדכון עצמי היא בדיוק זו שרצה כרגע.
  String? get onlineUpdateVersion =>
      hasOnlineUpdate ? onlineRelease?.version : null;

  /// בדיקה קלה ברשת. כשל (בעיקר "אין חיבור") הוא מצב תקין ונשמר בשקט, בדיוק
  /// כמו במודולים האחרים — בדיקה אוטומטית לא מציגה שגיאה כשאין רשת.
  Future<void> checkOnline() async {
    onlineCheckError = null;
    notifyListeners();

    try {
      onlineRelease = await _updater.peekLatestOnline();
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

  /// בודק מה מוכן בתיקייה שלצד התוכנה. לא נוגע ברשת.
  Future<void> checkForUpdate() async {
    try {
      final check = await _updater.checkForUpdate();
      downloadedVersion = check.mirroredVersion;
      canInstall = check.canInstall;
      status = check.updateAvailable
          ? LauncherUpdateStatus.readyToInstall
          : LauncherUpdateStatus.upToDate;
      errorMessage = null;
    } catch (e, st) {
      status = LauncherUpdateStatus.error;
      errorMessage = e.toString();
      AppLogger.instance
          .error('LauncherUpdateController.checkForUpdate נכשל', e, st);
    }
    notifyListeners();
  }

  /// מוריד את הגרסה שברשת אל התיקייה שלצד התוכנה. לא מתקין.
  Future<void> download() async {
    if (isDownloading) return;

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
      );
      AppLogger.instance.info("גרסה חדשה של הלאנצ'ר הורדה לתיקייה המקומית");
    } catch (e, st) {
      status = LauncherUpdateStatus.error;
      errorMessage = e.toString();
      AppLogger.instance.error("הורדת גרסת הלאנצ'ר נכשלה", e, st);
      notifyListeners();
      return;
    }

    // הבדיקה המקומית היא שקובעת את המצב — היא מאמתת שהקובץ בדיסק בגודל
    // הנכון, ולא סומכת על כך שההורדה "אמרה" שהצליחה.
    await checkForUpdate();
  }

  /// מחליף את קובץ ההרצה ומפעיל מחדש. מחזיר `true` אם הגרסה החדשה הופעלה —
  /// ואז התהליך הזה כבר בדרך להסתיים, ואין למה לעדכן UI.
  Future<bool> install() async {
    status = LauncherUpdateStatus.installing;
    errorMessage = null;
    notifyListeners();
    AppLogger.instance.info(
      "התקנת גרסה חדשה של הלאנצ'ר: $currentVersion -> $downloadedVersion",
    );

    try {
      final restarted = await _updater.applyUpdate();
      // ב-macOS ההחלפה הצליחה אך התוכנה הזאת ממשיכה לרוץ בגרסה הישנה, ולכן
      // "מתקין" היה נשאר על המסך עם מחוון סובב לנצח. הקובץ עוד במראה.
      if (!restarted) {
        status = LauncherUpdateStatus.readyToInstall;
        notifyListeners();
      }
      return restarted;
    } catch (e, st) {
      // חוזרים ל"מוכן להתקנה" ולא ל-error: הקובץ עדיין במראה, וב-`error`
      // הכפתור נעלם — במחשב המנותק זו הפעולה היחידה שנשארה, ורק הפעלה
      // מחדש של הלאנצ'ר הייתה מחזירה אותה. ההודעה עצמה מוצגת לצדו.
      status = LauncherUpdateStatus.readyToInstall;
      errorMessage = e.toString();
      AppLogger.instance.error("החלפת קובץ ההרצה של הלאנצ'ר נכשלה", e, st);
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
