import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/otzaria_install_state.dart';
import '../models/otzaria_release.dart';
import 'otzaria_exe_locator.dart';

/// מוריד את ה-installer של אוצריא (Inno Setup, נבדק ידנית מול גרסה
/// אמיתית מה-releases) ומתקין אותו בשקט לתוך תיקייה נתונה.
///
/// **קובץ ה-installer עצמו נשמר לצמיתות** תחת [cacheDir] (לא ב-temp, ולא
/// נמחק אחרי ההתקנה) — לפי סדר העבודה המבוקש: בכל כניסה, קודם בודקים אם
/// יש כבר עותק מעודכן בתיקיית ה-cache (ומורידים רק אם אין/ישן), ורק אז
/// בודקים אם המחשב עצמו (ההתקנה בפועל) מעודכן מול מה שב-cache. זה גם
/// נותן חוסן-אופליין חינם: אם ההורדה מ-GitHub נכשלת (או שאין רשת), עדיין
/// אפשר להתקין/לשחזר מהעותק השמור, ואפשר גם להעתיק את תיקיית ה-cache
/// למחשב אחר כדי לשכפל שם את אותה גרסה בלי אינטרנט.
///
/// חשוב: מבוסס על הנחה מאומתת (strings + innoextract על installer אמיתי)
/// ש-Inno Setup הוא ה-framework, ולכן דגלי השקט (/VERYSILENT וכו') ונתיב
/// ההתקנה (/DIR=) הם דגלי Inno Setup הסטנדרטיים. אם המפתח (Sivan22)
/// יחליף framework בעתיד, הדגלים האלה יפסיקו לעבוד ויהיה צריך לעדכן.
class OtzariaInstaller {
  OtzariaInstaller({
    required this.defaultInstallDir,
    required this.cacheDir,
    http.Client? httpClient,
    OtzariaExeLocator? exeLocator,
  })  : _httpClient = httpClient ?? http.Client(),
        _exeLocator = exeLocator ?? const OtzariaExeLocator();

  /// התיקייה שאליה מתקינים כשלא נבחרה תיקייה אחרת במפורש (למשל
  /// `<data>/otzaria-app`) — ה"מיקום ברירת המחדל" של הלאנצ'ר עצמו.
  final String defaultInstallDir;

  /// התיקייה שבה נשמר קובץ ה-installer עצמו לצמיתות, תחת תת-תיקייה לפי
  /// tag (למשל `<cacheDir>/v1.2.3/OtzariaSetup.exe`) — לא temp, לא נמחק.
  final String cacheDir;

  final http.Client _httpClient;
  final OtzariaExeLocator _exeLocator;

  /// מוודא שה-installer של [release] קיים ב-[cacheDir] (מוריד אם חסר, או
  /// אם קובץ קיים אך בגודל שגוי — ככל הנראה הורדה קודמת שנקטעה), בלי
  /// לגעת בהתקנה בפועל. שימושי כדי להפריד "לוודא שיש עותק עדכני מקומי"
  /// מ"להתקין את מה שיש מקומית", כמו שהתבקש.
  ///
  /// מחזיר את הנתיב לקובץ ה-installer המקומי (מה-cache).
  Future<String> ensureCached({
    required OtzariaRelease release,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final releaseCacheDir = p.join(cacheDir, release.tagName);
    final cachedInstallerPath = p.join(releaseCacheDir, release.windowsInstallerAssetName);
    final cachedFile = File(cachedInstallerPath);

    final alreadyCached = await cachedFile.exists() &&
        await cachedFile.length() == release.windowsInstallerSizeBytes;

    if (!alreadyCached) {
      await Directory(releaseCacheDir).create(recursive: true);
      await _download(
        url: release.windowsInstallerDownloadUrl,
        destinationPath: cachedInstallerPath,
        expectedSizeBytes: release.windowsInstallerSizeBytes,
        onProgress: onDownloadProgress,
      );
    }

    return cachedInstallerPath;
  }

  /// מוריד (אם צריך — ראו [ensureCached]) ומתקין release נתון. מחזיר את
  /// מצב ההתקנה החדש (לשמירה על ידי הקורא, דרך [OtzariaStateStore]).
  ///
  /// [targetInstallDir] מאפשר להתקין לתיקייה שאינה [defaultInstallDir] —
  /// למשל כשהמשתמש כבר הצביע בעבר על תיקיית התקנה קיימת משלו
  /// ([OtzariaManager.adoptExistingInstall]), ורוצים לעדכן אותה במקום,
  /// לא ליצור התקנה שנייה בתיקייה המנוהלת.
  ///
  /// [onDownloadProgress] מדווח (received, total) בזמן ההורדה (רק אם
  /// בפועל הורדנו — אם כבר קיים ב-cache, לא נקרא בכלל).
  Future<OtzariaInstallState> downloadAndInstall({
    required OtzariaRelease release,
    String? targetInstallDir,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final installDir = targetInstallDir ?? defaultInstallDir;

    final installerPath = await ensureCached(
      release: release,
      onDownloadProgress: onDownloadProgress,
    );

    await Directory(installDir).create(recursive: true);
    await _runSilentInstall(installerPath, installDir);

    final exePath = await _waitForInstalledExe(
      installDir: installDir,
      timeout: const Duration(minutes: 3),
    );

    await _pruneOldCacheEntries(keepTagName: release.tagName);

    return OtzariaInstallState(
      installedTagName: release.tagName,
      installDir: installDir,
      exePath: exePath,
    );
  }

  /// מוחק תתי-תיקיות cache של גרסאות ישנות אחרי התקנה מוצלחת, כדי
  /// שהתיקייה לא תצטבר בלי גבול — משאיר רק את הגרסה הנוכחית.
  Future<void> _pruneOldCacheEntries({required String keepTagName}) async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is Directory && p.basename(entry.path) != keepTagName) {
          await entry.delete(recursive: true);
        }
      }
    } catch (_) {
      // ניקוי best-effort — כישלון כאן לא אמור לחסום את ההתקנה שכבר הצליחה.
    }
  }

  Future<void> _download({
    required String url,
    required String destinationPath,
    required int expectedSizeBytes,
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      throw StateError('הורדת ה-installer נכשלה: סטטוס ${response.statusCode}');
    }

    final sink = File(destinationPath).openWrite();
    var received = 0;
    try {
      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, expectedSizeBytes);
      }).asFuture<void>();
    } finally {
      await sink.close();
    }

    if (expectedSizeBytes > 0 && received != expectedSizeBytes) {
      // מוחקים את הקובץ החלקי כדי שניסיון עתידי לא "יראה" cache-hit שגוי.
      try {
        await File(destinationPath).delete();
      } catch (_) {}
      throw StateError(
        'קובץ ה-installer שהורד לא בגודל הצפוי '
        '(התקבלו $received בתים, צפוי $expectedSizeBytes) — כנראה שהורדה '
        'נקטעה.',
      );
    }
  }

  Future<void> _runSilentInstall(String installerPath, String installDir) async {
    // /VERYSILENT + /SUPPRESSMSGBOXES: אין UI בכלל, כולל תיבות שגיאה.
    // /NORESTART: לא להפעיל מחדש את המחשב גם אם ה-installer "רוצה".
    // /DIR=: נתיב התקנה מפורש, כדי שנדע איפה לחפש את ה-exe אחר כך.
    //
    // הערה: זה עדיין רץ בשקט (בלי ויזארד) — ההחלטה "להוריד קובץ installer
    // רגיל, לא שקט" נוגעת לכך שהקובץ שנשמר ב-cache הוא ה-installer המלא
    // הרגיל (כמו שמפורסם ב-GitHub, בלי גרסת "silent-only" מיוחדת), ושהוא
    // נשמר כארטיפקט של ממש — לא לאופן הרצתו בפועל על המחשב. אם התכוונת
    // שדווקא ההתקנה על המחשב תציג ויזארד למשתמש (לא שקטה), תגיד ונשנה.
    final args = [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/DIR=$installDir',
    ];

    final result = await Process.run(installerPath, args);
    if (result.exitCode != 0) {
      throw StateError(
        'ריצת ה-installer החזירה קוד יציאה ${result.exitCode}.\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }

    // הערה: ל-installer-ים מבוססי Inno Setup יש לפעמים תהליך "עוטף"
    // (SetupLdr) שמשגר תהליך-בן ומסתיים מיד, עוד לפני שההתקנה בפועל
    // הסתיימה — ולכן exitCode==0 כאן לא מבטיח שהקבצים כבר על הדיסק.
    // בגלל זה יש polling נפרד ב-_waitForInstalledExe במקום להסתמך רק על
    // סיום התהליך.
  }

  Future<String> _waitForInstalledExe({
    required String installDir,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final found = await _exeLocator.findExeIn(installDir);
      if (found != null) return found;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw StateError(
      'לא נמצא קובץ הפעלה (.exe) בתוך $installDir תוך '
      '${timeout.inSeconds} שניות מסיום ה-installer. ייתכן שההתקנה עדיין '
      'רצה ברקע, או שנתיב ההתקנה השתנה בגרסה חדשה של ה-installer.',
    );
  }

  void close() => _httpClient.close();
}
