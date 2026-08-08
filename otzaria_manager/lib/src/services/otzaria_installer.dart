import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/otzaria_install_state.dart';
import '../models/otzaria_release.dart';
import 'otzaria_app_locator.dart';

/// מוריד את חבילת ההתקנה של אוצריא ומתקין אותה לתוך תיקייה נתונה, בשקט,
/// לפי הפלטפורמה:
///
/// * **Windows** — installer של Inno Setup (נבדק ידנית מול גרסה אמיתית
///   מה-releases), מורץ עם דגלי שקט ו-`/DIR=`.
/// * **macOS** — ארכיון `otzaria-macos.zip` (או `.dmg` כגיבוי) שבתוכו חבילת
///   `.app`; מחולץ/מועתק לתיקיית ההתקנה ומחליף שם התקנה קודמת. אין ב-macOS
///   "installer שרץ" בכלל — התקנה היא העתקת bundle, וזה בדיוק מה שנעשה כאן.
///
/// **קובץ ההתקנה עצמו נשמר לצמיתות** תחת [cacheDir] (לא ב-temp, ולא נמחק
/// אחרי ההתקנה) — לפי סדר העבודה המבוקש: בכל כניסה, קודם בודקים אם יש כבר
/// עותק מעודכן בתיקיית ה-cache (ומורידים רק אם אין/ישן), ורק אז בודקים אם
/// המחשב עצמו (ההתקנה בפועל) מעודכן מול מה שב-cache. זה גם נותן
/// חוסן-אופליין חינם: אם ההורדה מ-GitHub נכשלת (או שאין רשת), עדיין אפשר
/// להתקין/לשחזר מהעותק השמור, ואפשר גם להעתיק את תיקיית ה-cache למחשב אחר
/// כדי לשכפל שם את אותה גרסה בלי אינטרנט.
///
/// חשוב (Windows): מבוסס על הנחה מאומתת (strings + innoextract על installer
/// אמיתי) ש-Inno Setup הוא ה-framework, ולכן דגלי השקט (/VERYSILENT וכו')
/// ונתיב ההתקנה (/DIR=) הם דגלי Inno Setup הסטנדרטיים. אם המפתח (Sivan22)
/// יחליף framework בעתיד, הדגלים האלה יפסיקו לעבוד ויהיה צריך לעדכן.
class OtzariaInstaller {
  OtzariaInstaller({
    required this.defaultInstallDir,
    required this.cacheDir,
    http.Client? httpClient,
    OtzariaAppLocator? appLocator,
    this.connectTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  })  : _httpClient = httpClient ?? http.Client(),
        _appLocator = appLocator ?? const OtzariaAppLocator();

  /// זמן קצוב לפתיחת החיבור, ולשקט בין צ'אנקים. בלעדיהם הורדת ה-installer
  /// (~70MB) הייתה יכולה להישאר תלויה לנצח על חיבור שנפל באמצע, והמשתמש היה
  /// רואה מד התקדמות קפוא בלי שגיאה. ניתנים לשינוי מהגדרות הלאנצ'ר.
  Duration connectTimeout;
  Duration stallTimeout;

  /// התיקייה שאליה מתקינים כשלא נבחרה תיקייה אחרת במפורש (למשל
  /// `<data>/otzaria-app`) — ה"מיקום ברירת המחדל" של הלאנצ'ר עצמו.
  final String defaultInstallDir;

  /// התיקייה שבה נשמר קובץ ההתקנה עצמו לצמיתות, תחת תת-תיקייה לפי tag
  /// (למשל `<cacheDir>/v1.2.3/OtzariaSetup.exe`) — לא temp, לא נמחק.
  final String cacheDir;

  final http.Client _httpClient;
  final OtzariaAppLocator _appLocator;

  /// שם תיקיית ה-staging שנוצרת **בתוך** תיקיית ההתקנה בזמן התקנה ב-macOS.
  /// בתוך תיקיית ההתקנה בכוונה — כדי שההעברה של ה-`.app` הגמור למקומו תהיה
  /// `rename` באותו volume (אטומי ומיידי) ולא העתקה של 70MB+ בין דיסקים.
  static const String _macStagingDirName = '.otzaria-install-staging';

  /// שם תיקיית הגיבוי של ההתקנה הקודמת, בזמן ההחלפה בלבד. מאפשרת לשחזר את
  /// ההתקנה הקודמת אם הכנסת החדשה נכשלה באמצע — במקום להישאר בלי כלום.
  static const String _macPreviousDirName = '.otzaria-previous';

  /// מוודא שקובץ ההתקנה של [release] קיים ב-[cacheDir] (מוריד אם חסר, או
  /// אם קובץ קיים אך בגודל שגוי — ככל הנראה הורדה קודמת שנקטעה), בלי
  /// לגעת בהתקנה בפועל. שימושי כדי להפריד "לוודא שיש עותק עדכני מקומי"
  /// מ"להתקין את מה שיש מקומית", כמו שהתבקש.
  ///
  /// מחזיר את הנתיב לקובץ ההתקנה המקומי (מה-cache).
  Future<String> ensureCached({
    required OtzariaRelease release,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final releaseCacheDir = p.join(cacheDir, release.tagName);
    final cachedInstallerPath =
        p.join(releaseCacheDir, release.installerAssetName);
    final cachedFile = File(cachedInstallerPath);

    final alreadyCached = await cachedFile.exists() &&
        await cachedFile.length() == release.installerSizeBytes;

    if (!alreadyCached) {
      await Directory(releaseCacheDir).create(recursive: true);
      await _download(
        url: release.installerDownloadUrl,
        destinationPath: cachedInstallerPath,
        expectedSizeBytes: release.installerSizeBytes,
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
    final installerPath = await ensureCached(
      release: release,
      onDownloadProgress: onDownloadProgress,
    );
    return installFromFile(
      release: release,
      installerPath: installerPath,
      targetInstallDir: targetInstallDir,
    );
  }

  /// מתקין קובץ התקנה **שכבר נמצא בדיסק** — בלי לגעת ברשת בכלל. זה המסלול
  /// שמשמש בפועל: ההורדה נעשית מראש אל המראה המקומית (`OtzariaAppMirror`),
  /// וההתקנה קוראת משם, גם במחשב בלי אינטרנט.
  Future<OtzariaInstallState> installFromFile({
    required OtzariaRelease release,
    required String installerPath,
    String? targetInstallDir,
  }) async {
    final installDir = targetInstallDir ?? defaultInstallDir;
    await Directory(installDir).create(recursive: true);

    final String launchPath;
    switch (release.installerKind) {
      case OtzariaInstallerKind.windowsSetupExe:
        await _runSilentInstall(installerPath, installDir);
        launchPath = await _waitForInstalledApp(
          installDir: installDir,
          timeout: const Duration(minutes: 3),
        );
      case OtzariaInstallerKind.macAppZip:
        launchPath = await _installMacApp(
          installDir: installDir,
          stageApp: (stagingDir) => _extractZipTo(installerPath, stagingDir),
        );
      case OtzariaInstallerKind.macAppDmg:
        launchPath = await _installMacApp(
          installDir: installDir,
          stageApp: (stagingDir) => _copyAppFromDmg(installerPath, stagingDir),
        );
    }

    await _pruneOldCacheEntries(keepTagName: release.tagName);

    return OtzariaInstallState(
      installedTagName: release.tagName,
      installDir: installDir,
      launchPath: launchPath,
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
    final response = await _httpClient.send(request).timeout(connectTimeout);

    if (response.statusCode != 200) {
      throw StateError('הורדת קובץ ההתקנה נכשלה: סטטוס ${response.statusCode}');
    }

    final sink = File(destinationPath).openWrite();
    var received = 0;
    try {
      // `timeout` על הזרם ולא רק על ה-send: חיבור שנפתח ואז נשתק היה תוקע
      // את ההורדה בלי גבול.
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, expectedSizeBytes);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // קובץ חלקי חייב להיעלם: הריצה הבאה בודקת cache-hit לפי גודל, וקובץ
      // שנקטע בדיוק בגודל הנכון היה נראה תקין. סוגרים לפני המחיקה — ב-Windows
      // handle פתוח חוסם אותה.
      try {
        await sink.close();
      } catch (_) {}
      try {
        await File(destinationPath).delete();
      } catch (_) {}
      rethrow;
    }

    if (expectedSizeBytes > 0 && received != expectedSizeBytes) {
      // מוחקים את הקובץ החלקי כדי שניסיון עתידי לא "יראה" cache-hit שגוי.
      try {
        await File(destinationPath).delete();
      } catch (_) {}
      throw StateError(
        'קובץ ההתקנה שהורד לא בגודל הצפוי '
        '(התקבלו $received בתים, צפוי $expectedSizeBytes) — כנראה שהורדה '
        'נקטעה.',
      );
    }
  }

  // ---------------------------------------------------------------- Windows

  Future<void> _runSilentInstall(
      String installerPath, String installDir) async {
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
    // בגלל זה יש polling נפרד ב-_waitForInstalledApp במקום להסתמך רק על
    // סיום התהליך.
  }

  // ------------------------------------------------------------------ macOS

  /// המסלול המשותף לכל התקנה ב-macOS: מכינים את ה-`.app` בתיקיית staging
  /// (דרך [stageApp] — חילוץ zip או העתקה מ-dmg), ואז מחליפים בו את
  /// ההתקנה הקיימת בתיקיית ההתקנה.
  ///
  /// **למה staging ולא חילוץ ישר לתיקיית ההתקנה:** אם החילוץ ייכשל באמצע
  /// (רשת/דיסק/הפסקת חשמל), ההתקנה הקיימת של המשתמש עדיין שלמה ותקינה —
  /// היא מוחלפת רק ברגע אחד, אחרי שה-`.app` החדשה כבר מוכנה במלואה.
  Future<String> _installMacApp({
    required String installDir,
    required Future<void> Function(String stagingDir) stageApp,
  }) async {
    final stagingDir = p.join(installDir, _macStagingDirName);
    final previousDir = p.join(installDir, _macPreviousDirName);

    await _deleteDirQuietly(stagingDir);
    await Directory(stagingDir).create(recursive: true);

    try {
      await stageApp(stagingDir);

      final stagedApp = await _appLocator.findIn(stagingDir);
      if (stagedApp == null) {
        throw StateError(
          'לא נמצאה חבילת .app בתוך חבילת ההתקנה שחולצה — ייתכן שמבנה '
          'האסט של אוצריא ל-macOS השתנה.',
        );
      }

      // ה-app נכנס לתיקיית ההתקנה תחת אותו שם שיש לו בחבילה (למשל
      // "אוצריא.app"), כדי שנחליף בפועל התקנה קודמת ולא ניצור שנייה לידה.
      final appName = p.basename(stagedApp);
      final targetApp = p.join(installDir, appName);

      await _swapInApp(
        stagedApp: stagedApp,
        targetApp: targetApp,
        previousDir: previousDir,
      );

      // ה-app של אוצריא חתום ad-hoc (בלי Developer ID ובלי notarization).
      // אנחנו מורידים את הארכיון ישירות דרך dart:io ולכן macOS לא מסמן
      // אותו ב-quarantine, ו-Gatekeeper לא חוסם — אבל אם המשתמש הביא את
      // הארכיון בעצמו (דפדפן, AirDrop) הסימון כן יהיה שם ויחסום. הסרה
      // best-effort מכסה גם את המקרה הזה.
      await _stripQuarantineQuietly(targetApp);

      return targetApp;
    } finally {
      await _deleteDirQuietly(stagingDir);
    }
  }

  /// מחליף את [targetApp] ב-[stagedApp] דרך שתי פעולות `rename` באותו
  /// volume, עם שחזור אם השנייה נכשלה.
  Future<void> _swapInApp({
    required String stagedApp,
    required String targetApp,
    required String previousDir,
  }) async {
    final existing = Directory(targetApp);
    final hasExisting = await existing.exists();

    String? backupPath;
    if (hasExisting) {
      await _deleteDirQuietly(previousDir);
      await Directory(previousDir).create(recursive: true);
      backupPath = p.join(previousDir, p.basename(targetApp));
      await existing.rename(backupPath);
    }

    try {
      await Directory(stagedApp).rename(targetApp);
    } catch (e) {
      // ההכנסה נכשלה — מחזירים את ההתקנה הקודמת למקומה כדי לא להשאיר את
      // המשתמש בלי אוצריא בכלל.
      if (backupPath != null) {
        try {
          await Directory(backupPath).rename(targetApp);
        } catch (_) {}
      }
      throw StateError('החלפת חבילת ה-.app בתיקיית ההתקנה נכשלה: $e');
    }

    await _deleteDirQuietly(previousDir);
  }

  /// חילוץ עם `ditto` ולא עם unzip/package:archive — `ditto` הוא הכלי
  /// היחיד ב-macOS ששומר על symlinks, resource forks ו-extended attributes
  /// של ה-bundle כמו שהם. חילוץ "רגיל" שובר את החתימה הדיגיטלית של
  /// ה-`.app` (וגם את ה-frameworks שבתוכו), ואז macOS מסרב להריץ אותו.
  Future<void> _extractZipTo(String zipPath, String destinationDir) async {
    final result = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      zipPath,
      destinationDir,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'חילוץ חבילת ההתקנה (ditto) נכשל בקוד ${result.exitCode}.\n'
        'stderr: ${result.stderr}',
      );
    }
  }

  /// מרכיב את ה-dmg על נקודת עגינה מפורשת בתוך [destinationDir] (כדי לא
  /// להיאלץ לפענח את פלט ה-plist של `hdiutil`), מעתיק ממנה את ה-`.app`
  /// ומנתק — גם אם ההעתקה נכשלה.
  Future<void> _copyAppFromDmg(String dmgPath, String destinationDir) async {
    final mountPoint = p.join(destinationDir, '.mnt');
    await Directory(mountPoint).create(recursive: true);

    final attach = await Process.run('/usr/bin/hdiutil', [
      'attach',
      dmgPath,
      '-nobrowse',
      '-readonly',
      '-noverify',
      '-mountpoint',
      mountPoint,
    ]);
    if (attach.exitCode != 0) {
      throw StateError(
        'הרכבת דמות הדיסק (hdiutil attach) נכשלה בקוד ${attach.exitCode}.\n'
        'stderr: ${attach.stderr}',
      );
    }

    try {
      final appInDmg = await _appLocator.findIn(mountPoint);
      if (appInDmg == null) {
        throw StateError('לא נמצאה חבילת .app בתוך דמות הדיסק שהורכבה.');
      }

      // גם כאן ditto ולא cp -R, מאותה סיבה שב-[_extractZipTo].
      final copy = await Process.run('/usr/bin/ditto', [
        appInDmg,
        p.join(destinationDir, p.basename(appInDmg)),
      ]);
      if (copy.exitCode != 0) {
        throw StateError(
          'העתקת ה-.app מדמות הדיסק (ditto) נכשלה בקוד ${copy.exitCode}.\n'
          'stderr: ${copy.stderr}',
        );
      }
    } finally {
      await Process.run('/usr/bin/hdiutil', ['detach', mountPoint, '-quiet']);
      await _deleteDirQuietly(mountPoint);
    }
  }

  Future<void> _stripQuarantineQuietly(String path) async {
    try {
      await Process.run('/usr/bin/xattr', [
        '-dr',
        'com.apple.quarantine',
        path,
      ]);
    } catch (_) {
      // best-effort בלבד.
    }
  }

  Future<void> _deleteDirQuietly(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ----------------------------------------------------------------- משותף

  Future<String> _waitForInstalledApp({
    required String installDir,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final found = await _appLocator.findIn(installDir);
      if (found != null) return found;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw StateError(
      'לא נמצאה התקנה של אוצריא בתוך $installDir תוך '
      '${timeout.inSeconds} שניות מסיום ה-installer. ייתכן שההתקנה עדיין '
      'רצה ברקע, או שנתיב ההתקנה השתנה בגרסה חדשה של ה-installer.',
    );
  }

  void close() => _httpClient.close();
}
