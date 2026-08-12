import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'launcher_install_layout.dart';
import 'launcher_release.dart';
import 'launcher_release_client.dart';
import 'launcher_self_installer.dart';
import 'launcher_update_mirror.dart';
import 'launcher_version.dart';

/// תוצאת בדיקה **מקומית** של עדכון ללאנצ'ר — מהתיקייה שלצד התוכנה בלבד.
class LauncherUpdateCheck {
  const LauncherUpdateCheck({
    required this.currentVersion,
    this.mirrored,
    this.canInstall = false,
  });

  final String currentVersion;

  /// הגרסה שיושבת מוכנה בתיקייה, אם יש.
  final MirroredLauncherRelease? mirrored;

  /// `false` כשאין לנו את הנתיב של קובץ ההרצה — למשל הרצה מ-`flutter run`.
  /// אז אפשר להוריד אך לא להתקין, וה-UI אומר זאת במקום להיכשל בלחיצה.
  final bool canInstall;

  /// יש בתיקייה גרסה **חדשה** מזו שרצה כרגע.
  bool get updateAvailable {
    final ready = mirrored;
    return ready != null &&
        LauncherVersion.isNewer(ready.release.tagName, currentVersion);
  }

  String? get mirroredVersion => mirrored?.release.version;
}

/// עדכון עצמי של הלאנצ'ר, באותה חלוקה כמו כל שאר המודולים: [peekLatestOnline]
/// ו-[downloadToMirror] נוגעות ברשת, [checkForUpdate] ו-[applyUpdate] קוראות
/// **רק** מהתיקייה שלצד התוכנה.
///
/// כך גם העדכון של התוכנה עצמה נוסע על הכונן: מורידים במחשב המקוון, ואפשר
/// להתקין בכל מחשב — כולל המנותק, שם הכפתור עובד בלי רשת.
class LauncherSelfUpdater {
  /// factory ולא constructor רגיל: הלקוח וההורדה חולקים `http.Client` אחד
  /// (חיבורים ל-`api.github.com` ול-CDN מוחזקים פעם אחת), ורשימת אתחול
  /// אינה יכולה ליצור משתנה משותף.
  factory LauncherSelfUpdater({
    required String dataDir,
    http.Client? httpClient,
    LauncherReleaseClient? releaseClient,
    LauncherUpdateMirror? mirror,
    LauncherSelfInstaller? installer,
    LauncherInstallLayout? layout,
    bool resolveLayout = true,
  }) {
    final client = httpClient ?? http.Client();
    return LauncherSelfUpdater._(
      releaseClient: releaseClient ?? LauncherReleaseClient(httpClient: client),
      mirror: mirror ??
          LauncherUpdateMirror(
            mirrorDir: p.join(dataDir, 'mirror', 'launcher'),
            httpClient: client,
          ),
      installer: installer ?? LauncherSelfInstaller(),
      layout:
          layout ?? (resolveLayout ? LauncherInstallLayout.resolve() : null),
    );
  }

  LauncherSelfUpdater._({
    required LauncherReleaseClient releaseClient,
    required LauncherUpdateMirror mirror,
    required LauncherSelfInstaller installer,
    required LauncherInstallLayout? layout,
  })  : _releaseClient = releaseClient,
        _mirror = mirror,
        _installer = installer,
        _layout = layout;

  final LauncherReleaseClient _releaseClient;
  final LauncherUpdateMirror _mirror;
  final LauncherSelfInstaller _installer;
  final LauncherInstallLayout? _layout;

  /// הגרסה שרצה כרגע — הקבוע שנקבע בבנייה, ולא קריאה מהדיסק.
  String get currentVersion => launcherVersion;

  String get mirrorDir => _mirror.mirrorDir;

  /// הקובץ שיוחלף בעדכון, או `null` כשאין מה להחליף בהרצה הזאת.
  String? get executablePath => _layout?.executablePath;

  /// בדיקה קלה ברשת: מה הגרסה היציבה האחרונה. לא מוריד דבר.
  Future<LauncherRelease?> peekLatestOnline() =>
      _releaseClient.fetchLatestStable();

  /// מוריד את הגרסה שברשת אל התיקייה שלצד התוכנה. **דורש אינטרנט.**
  ///
  /// [release] הוא מה שהבדיקה הקלה כבר מצאה; בלעדיו נשלף מחדש.
  Future<MirroredLauncherRelease?> downloadToMirror({
    LauncherRelease? release,
    void Function(int received, int total)? onProgress,
  }) async {
    final target = release ?? await peekLatestOnline();
    if (target == null) return null;
    return _mirror.sync(target, onProgress: onProgress);
  }

  /// בודק מה מוכן בתיקייה מול הגרסה שרצה. לא נוגע ברשת ולא זורק על מראה
  /// ריקה — "אין מה להתקין" היא תשובה תקינה.
  Future<LauncherUpdateCheck> checkForUpdate() async {
    final layout = _layout;
    if (layout != null) await _installer.cleanupLeftovers(layout);

    return LauncherUpdateCheck(
      currentVersion: currentVersion,
      mirrored: await _mirror.load(),
      canInstall: layout != null,
    );
  }

  /// מחליף את קובץ ההרצה בגרסה שבתיקייה ומפעיל מחדש. מחזיר `true` אם הגרסה
  /// החדשה כבר הופעלה (ואז התהליך הזה מסתיים מיד), `false` כשנדרשת פתיחה
  /// ידנית — ראו [LauncherSelfInstaller.apply].
  ///
  /// זורק [LauncherUpdateException] כשאין מה להתקין או כשההחלפה נכשלה.
  Future<bool> applyUpdate() async {
    final layout = _layout;
    if (layout == null) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.executableNotFound,
      );
    }

    final mirrored = await _mirror.load();
    if (mirrored == null) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.mirrorMissing,
      );
    }

    return _installer.apply(
      layout: layout,
      downloadedFilePath: mirrored.filePath,
    );
  }

  void dispose() {
    _releaseClient.dispose();
    _mirror.dispose();
  }
}
