import 'dart:async';

import 'package:flutter/foundation.dart';
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
  })  : _preferPrerelease = preferPrerelease,
        _manager = OtzariaManager(
          dataDir: dataDir,
          preferPrerelease: preferPrerelease,
        );

  final OtzariaManager _manager;
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

  /// זמן קצוב לפעולות רשת (מהגדרות "רשת") — נכנס לתוקף בבקשה הבאה.
  set networkTimeout(Duration value) => _manager.networkTimeout = value;

  OtzariaModuleStatus status = OtzariaModuleStatus.idle;
  String? currentVersion;

  /// הגרסה שיושבת בתיקייה המקומית ומוכנה להתקנה **בערוץ שנבחר**, או null
  /// אם טרם הורדה.
  String? latestVersion;
  String? errorMessage;

  /// הגרסאות שבתיקייה המקומית לפי ערוץ — `null` לערוץ שאין בו גרסה.
  String? stableVersion;
  String? prereleaseVersion;

  /// שתי הגרסאות יושבות בתיקייה — רק אז מוצגת למשתמש בחירת ערוץ.
  bool hasChannelChoice = false;

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

  /// `true` אם הבדיקה הקלה מצאה ברשת תג שונה ממה שמותקן/יושב במראה
  /// המקומית כרגע — אינדיקציה בלבד; ההשוואה הקובעת היא [checkForUpdate]
  /// אחרי הורדה בפועל.
  bool get hasOnlineUpdate {
    final online = onlineLatestRelease;
    if (online == null) return false;
    final known = currentVersion ?? latestVersion;
    if (known == null) return true;
    return OtzariaUpdateCheckResult.normalizeVersion(online.tagName) !=
        OtzariaUpdateCheckResult.normalizeVersion(known);
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
  Future<void> download() async {
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
          downloadStage = 'מוריד את תוכנת אוצריא (גרסה ${channel.label})...';
          downloadReceived = null;
          downloadTotal = null;
          notifyListeners();
        },
      );
      downloadStage = null;
      downloadStatus = OtzariaDownloadStatus.done;
      lastDownloadedAt = DateTime.now();
      notifyListeners();
      await checkForUpdate();
      return;
    } catch (e, st) {
      downloadStage = null;
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
      stableVersion = check.stableRelease?.tagName;
      prereleaseVersion = check.prereleaseRelease?.tagName;
      hasChannelChoice = check.hasChannelChoice;
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
