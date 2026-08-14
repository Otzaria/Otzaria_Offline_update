import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/otzaria_install_state.dart';
import '../models/otzaria_release.dart';
import 'otzaria_app_locator.dart';

/// נזרק כשהמשתמש ביטל את ההורדה. חריג נפרד ולא [StateError], כדי שהקורא
/// יוכל להבחין בין בחירה של המשתמש לכשל אמיתי.
class OtzariaDownloadCancelled implements Exception {
  const OtzariaDownloadCancelled();

  @override
  String toString() => AppL10n.strings.appDomain.downloadCancelled;
}

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

  /// התיקייה שבה נשמר קובץ ההתקנה עצמו לצמיתות, תחת תת-תיקייה לפי tag
  /// (למשל `<cacheDir>/v1.2.3/OtzariaSetup.exe`) — לא temp, לא נמחק.
  final String cacheDir;

  final http.Client _httpClient;
  final OtzariaAppLocator _appLocator;

  /// כמה בייטים מותר לצבור ב-`IOSink` לפני שממתינים לכתיבתם בפועל. `IOSink.
  /// add` אינו מפעיל לחץ-נגד: כשקובץ ההתקנה יורד מהר יותר משהכונן הנייד
  /// מספיק לכתוב, ההפרש נערם ב-RAM והתוכנה נתקעת באמצע ההורדה.
  static const int _writeBufferBytes = 4 << 20;

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
    bool Function()? isCancelled,
  }) async {
    final releaseCacheDir = p.join(cacheDir, release.tagName);
    final cachedInstallerPath =
        p.join(releaseCacheDir, release.installerAssetName);
    final cachedFile = File(cachedInstallerPath);

    final alreadyCached = await cachedFile.exists() &&
        await cachedFile.length() == release.installerSizeBytes;

    if (!alreadyCached) {
      // ביטול לפני כל שינוי בדיסק: יצירת התיקייה עצמה היא כבר עקבות שהמסלול
      // הזה משאיר אחריו.
      _throwIfCancelled(isCancelled);
      await Directory(releaseCacheDir).create(recursive: true);
      await _download(
        url: release.installerDownloadUrl,
        destinationPath: cachedInstallerPath,
        expectedSizeBytes: release.installerSizeBytes,
        onProgress: onDownloadProgress,
        isCancelled: isCancelled,
      );
    }

    return cachedInstallerPath;
  }

  /// מתקין קובץ התקנה **שכבר נמצא בדיסק** — בלי לגעת ברשת בכלל. זה המסלול
  /// היחיד: ההורדה נעשית מראש אל המראה המקומית ([ensureCached] דרך
  /// `OtzariaAppMirror`), וההתקנה קוראת משם, גם במחשב בלי אינטרנט. אין כאן
  /// "הורד והתקן" בצעד אחד בכוונה — ראו AGENTS.md §1.
  ///
  /// [installDir] הוא פרמטר חובה ואין לו ברירת מחדל בכוונה: תיקייה משלנו
  /// כברירת מחדל היא בדיוק הבאג שהיה כאן — לאנצ'ר שרץ מכונן נייד התקין את
  /// אוצריא אל הכונן, וכל ההתקנה נסעה איתו במקום להישאר על המחשב. מי
  /// שמחליט לאן מתקינים הוא [OtzariaManager.update].
  ///
  /// [keepCachedTagNames] = התגים שקובצי ההתקנה שלהם יישארו ב-cache אחרי
  /// ההתקנה. ברירת המחדל היא הגרסה שהותקנה בלבד; הקורא מעביר את **כל**
  /// הגרסאות שבמראה, אחרת התקנה של ערוץ אחד הייתה מוחקת את קובץ ההתקנה
  /// של השני.
  Future<OtzariaInstallState> installFromFile({
    required OtzariaRelease release,
    required String installerPath,
    required String installDir,
    Set<String>? keepCachedTagNames,
  }) async {
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

    await pruneCacheExcept(
      keepTagNames: keepCachedTagNames ?? {release.tagName},
    );

    return OtzariaInstallState(
      installedTagName: release.tagName,
      installDir: installDir,
      launchPath: launchPath,
    );
  }

  /// מוחק תתי-תיקיות cache של גרסאות שאינן ב-[keepTagNames], כדי שהתיקייה
  /// לא תצטבר בלי גבול על הכונן הנייד. נקרא אחרי התקנה מוצלחת ואחרי סנכרון
  /// המראה.
  Future<void> pruneCacheExcept({required Set<String> keepTagNames}) async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;
    try {
      await for (final entry in dir.list()) {
        if (entry is Directory &&
            !keepTagNames.contains(p.basename(entry.path))) {
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
    bool Function()? isCancelled,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request).timeout(connectTimeout);

    if (response.statusCode != 200) {
      throw StateError(
        AppL10n.strings.appDomain.installerDownloadFailed(response.statusCode),
      );
    }

    final sink = File(destinationPath).openWrite();
    var received = 0;
    var buffered = 0;
    try {
      // `timeout` על הזרם ולא רק על ה-send: חיבור שנפתח ואז נשתק היה תוקע
      // את ההורדה בלי גבול.
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        // ביטול באמצע נכס — ה-catch שלמטה מוחק את הקובץ החלקי.
        _throwIfCancelled(isCancelled);
        sink.add(chunk);
        received += chunk.length;
        buffered += chunk.length;
        onProgress?.call(received, expectedSizeBytes);
        // לחץ-נגד — ראו [_writeBufferBytes].
        if (buffered >= _writeBufferBytes) {
          buffered = 0;
          await sink.flush();
        }
      }
      await sink.flush();
      await sink.close();
      // ביטול שהתרחש על הצ'אנק האחרון — בלי הבדיקה כאן הוא היה חוזר כהצלחה.
      _throwIfCancelled(isCancelled);
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
        AppL10n.strings.appDomain
            .installerSizeMismatch(received, expectedSizeBytes),
      );
    }
  }

  // ---------------------------------------------------------------- Windows

  Future<void> _runSilentInstall(
      String installerPath, String installDir) async {
    // /VERYSILENT + /SUPPRESSMSGBOXES: אין UI בכלל, כולל תיבות שגיאה.
    // /NORESTART: לא להפעיל מחדש את המחשב גם אם ה-installer "רוצה".
    // /DIR=: נתיב התקנה מפורש, כדי שנדע איפה לחפש את ה-exe אחר כך.
    final args = [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/DIR=$installDir',
    ];

    final result = await Process.run(installerPath, args);
    if (result.exitCode != 0) {
      throw StateError(
        AppL10n.strings.appDomain.installerExitCode(
          result.exitCode,
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        ),
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
        throw StateError(AppL10n.strings.appDomain.macAppNotFoundInArchive);
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
      throw StateError(AppL10n.strings.appDomain.macReplaceFailed('$e'));
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
        AppL10n.strings.appDomain.dittoExtractFailed(
          result.exitCode,
          'stderr: ${result.stderr}',
        ),
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
        AppL10n.strings.appDomain.hdiutilAttachFailed(
          attach.exitCode,
          'stderr: ${attach.stderr}',
        ),
      );
    }

    try {
      final appInDmg = await _appLocator.findIn(mountPoint);
      if (appInDmg == null) {
        throw StateError(AppL10n.strings.appDomain.macAppNotFoundInDmg);
      }

      // גם כאן ditto ולא cp -R, מאותה סיבה שב-[_extractZipTo].
      final copy = await Process.run('/usr/bin/ditto', [
        appInDmg,
        p.join(destinationDir, p.basename(appInDmg)),
      ]);
      if (copy.exitCode != 0) {
        throw StateError(
          AppL10n.strings.appDomain.dittoCopyFailed(
            copy.exitCode,
            'stderr: ${copy.stderr}',
          ),
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

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const OtzariaDownloadCancelled();
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
      AppL10n.strings.appDomain
          .installNotDetected(installDir, timeout.inSeconds),
    );
  }

  void dispose() => _httpClient.close();
}
