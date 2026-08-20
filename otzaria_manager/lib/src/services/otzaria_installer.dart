import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

/// המשתמש ביטל את **ההתקנה** באשף של המתקין (או סירב ל-UAC). כמו
/// [OtzariaDownloadCancelled] — בחירה, לא כשל, ולכן הממשק לא מציג שגיאה.
class OtzariaInstallCancelled implements Exception {
  const OtzariaInstallCancelled();

  @override
  String toString() => AppL10n.strings.appDomain.installCancelledByUser;
}

/// האשף הופעל, התהליך שהרצנו חזר, וההתקנה עדיין לא נראית על הדיסק — ראו
/// [OtzariaInstaller.wizardDetectTimeout]. גם זה אינו כשל: המשתמש עוד
/// באמצע, והממשק אומר לו ללחוץ "בדיקה מחדש" כשיסיים.
class OtzariaWizardStillOpen implements Exception {
  const OtzariaWizardStillOpen();

  @override
  String toString() => AppL10n.strings.appDomain.wizardStillOpen;
}

/// איך הסתיימה הרצת המתקין עם האשף — ראו
/// [OtzariaInstaller.wizardOutcomeFor].
enum OtzariaWizardOutcome { finished, cancelled, failed }

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

  /// כמה להמתין להופעת קובץ ההרצה אחרי שה-installer הוחזר. ראו
  /// [_runSilentInstall] — ב-Inno Setup התהליך שמריצים עשוי להסתיים לפני
  /// שההתקנה בפועל הסתיימה.
  static const Duration defaultAppAppearTimeout = Duration(minutes: 3);

  /// אותה המתנה, בחבילת ה-FULL. היא פורסת ~2GB דחוסים לספרייה של כמה
  /// ג'יגה־בייט על הדיסק, ולעיתים גם אל כונן חיצוני — שלוש דקות היו
  /// מכריזות כישלון על התקנה שרק התחילה. הגבול קיים בכל זאת, כדי
  /// שמתקין שנפל בשקט לא ישאיר את הלאנצ'ר תלוי לנצח.
  static const Duration fullPackageAppAppearTimeout = Duration(minutes: 30);

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
  }) =>
      ensureAssetCached(
        tagName: release.tagName,
        assetName: release.installerAssetName,
        downloadUrl: release.installerDownloadUrl,
        sizeBytes: release.installerSizeBytes,
        onDownloadProgress: onDownloadProgress,
        isCancelled: isCancelled,
      );

  /// היכן יושב אסט של [tagName] ב-cache — בלי להוריד ובלי לבדוק קיום.
  String assetPathFor(String tagName, String assetName) =>
      p.join(cacheDir, tagName, assetName);

  /// כמו [ensureCached], אבל לאסט כלשהו של אותו release — כלומר גם לחבילת
  /// ה-FULL, שיושבת באותה תיקיית tag לצד המתקין הרגיל.
  Future<String> ensureAssetCached({
    required String tagName,
    required String assetName,
    required String downloadUrl,
    required int sizeBytes,
    void Function(int received, int total)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    final releaseCacheDir = p.join(cacheDir, tagName);
    final cachedInstallerPath = p.join(releaseCacheDir, assetName);
    final cachedFile = File(cachedInstallerPath);

    final alreadyCached =
        await cachedFile.exists() && await cachedFile.length() == sizeBytes;

    if (!alreadyCached) {
      // ביטול לפני כל שינוי בדיסק: יצירת התיקייה עצמה היא כבר עקבות שהמסלול
      // הזה משאיר אחריו.
      _throwIfCancelled(isCancelled);
      await Directory(releaseCacheDir).create(recursive: true);
      await _download(
        url: downloadUrl,
        destinationPath: cachedInstallerPath,
        expectedSizeBytes: sizeBytes,
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
  ///
  /// [installerKind] נמסר במפורש כשמתקינים אסט שאינו המתקין הרגיל — חבילת
  /// ה-FULL עשויה להיות מסוג אחר (zip מול dmg ב-macOS). ברירת המחדל היא
  /// הסוג של ה-release עצמו.
  /// [installDir] הוא `null` כשמתקינים **התקנה חדשה בווינדוס**: אז לא נמסר
  /// `/DIR=` בכלל, והמתקין מתקין לברירת המחדל שלו — ראו [windowsSilentArgs].
  /// במסלול הזה [locateInstalled] הוא שמוצא לאן זה הלך, והוא חובה. ב-macOS
  /// אין "ברירת מחדל של מתקין" (ההתקנה היא העתקת bundle), ולכן שם התיקייה
  /// נדרשת תמיד.
  Future<OtzariaInstallState> installFromFile({
    required OtzariaRelease release,
    required String installerPath,
    required String? installDir,
    Future<OtzariaInstallState?> Function()? locateInstalled,
    OtzariaInstallerKind? installerKind,
    Duration appAppearTimeout = defaultAppAppearTimeout,
    Set<String>? keepCachedTagNames,
  }) async {
    if (installDir != null) await Directory(installDir).create(recursive: true);

    final OtzariaInstallState installed;
    switch (installerKind ?? release.installerKind) {
      case OtzariaInstallerKind.windowsSetupExe:
        await _runSilentInstall(installerPath, installDir);
        installed = await _findInstalled(
          release: release,
          installDir: installDir,
          locateInstalled: locateInstalled,
          timeout: appAppearTimeout,
        );
      case OtzariaInstallerKind.macAppZip:
        installed = await _installMacAppState(
          release: release,
          installDir: _requireInstallDir(installDir),
          stageApp: (stagingDir) => _extractZipTo(installerPath, stagingDir),
        );
      case OtzariaInstallerKind.macAppDmg:
        installed = await _installMacAppState(
          release: release,
          installDir: _requireInstallDir(installDir),
          stageApp: (stagingDir) => _copyAppFromDmg(installerPath, stagingDir),
        );
    }

    await pruneCacheExcept(
      keepTagNames: keepCachedTagNames ?? {release.tagName},
    );

    return installed;
  }

  /// מריץ את המתקין **עם האשף שלו** — בלי שום דגל שקט, כך שהמשתמש רואה את
  /// אותם עמודי בחירה שהוא רואה בהרצה ידנית (תיקיית יעד, קיצור דרך,
  /// והאזהרות שה-`[Code]` של המתקין מקפיץ). מיועד למחשב שהמשתמש עומד מולו.
  ///
  /// אין `/MERGETASKS` בכוונה: קיצור הדרך הוא בחירה של המשתמש, ולדרוס
  /// אותה בדגל היה מחזיר בדיוק את מה שהמסלול הזה בא לתקן.
  ///
  /// [installDir] = **התיקייה של התקנה קיימת שאנחנו מכירים**, ואז היא
  /// נמסרת ב-`/DIR=`: הגרסה החדשה נכנסת בדיוק לאותו מקום, ולא נוצרת התקנה
  /// שנייה לצד הראשונה. זה אינו סותר את האשף — ב-Inno `/DIR=` קובע את
  /// *ברירת המחדל* של עמוד היעד, והמשתמש עוד יכול לשנותה כשהעמוד מוצג.
  /// ההסתמכות על `UsePreviousAppDir` של Inno לבדה אינה מספיקה: היא עובדת
  /// רק כשהוא מוצא את רשומת ההתקנה שלו עצמו, ולא כשהמשתמש הצביע ידנית על
  /// התקנה שהרשומה שלה חסרה (התקנה ניידת, או כזו שנרשמה למשתמש אחר).
  /// `null` = התקנה חדשה, ואז המתקין בוחר את ברירת המחדל שלו.
  ///
  /// זורק [OtzariaInstallCancelled] כשהמשתמש ביטל (כולל סירוב ל-UAC), ו-
  /// [StateError] בכשל אמיתי. אחרי סיום מוצלח מחפש את ההתקנה דרך
  /// [locateInstalled] — הוא היחיד שיודע לאן המשתמש בחר להתקין.
  Future<OtzariaInstallState> installWithWizard({
    required OtzariaRelease release,
    required String installerPath,
    required Future<OtzariaInstallState?> Function() locateInstalled,
    String? installDir,
    Duration detectTimeout = wizardDetectTimeout,
    Set<String>? keepCachedTagNames,
  }) async {
    final logPath =
        p.join(Directory.systemTemp.path, 'otzaria-install-$pid.log');
    final result = await Process.run(installerPath, [
      if (installDir != null) '/DIR=$installDir',
      '/LOG=$logPath',
    ]);

    switch (wizardOutcomeFor(result.exitCode)) {
      case OtzariaWizardOutcome.cancelled:
        _deleteQuietly(logPath);
        throw const OtzariaInstallCancelled();
      case OtzariaWizardOutcome.failed:
        final details = _installFailureOutput(result, logPath);
        _deleteQuietly(logPath);
        throw StateError(
          AppL10n.strings.appDomain.installerExitCode(result.exitCode, details),
        );
      case OtzariaWizardOutcome.finished:
        _deleteQuietly(logPath);
    }

    // התיקייה שמסרנו קודמת לזיהוי: היא מה שהתבקש, והזיהוי הכללי עלול
    // להחזיר דווקא התקנה אחרת שנשארה במחשב. אם היא ריקה — המשתמש שינה את
    // היעד באשף, ואז הזיהוי הוא התשובה.
    Future<OtzariaInstallState?> locate() async {
      if (installDir != null) {
        final launchPath = await _appLocator.findIn(installDir);
        if (launchPath != null) {
          return OtzariaInstallState(
            installedTagName: release.tagName,
            installDir: installDir,
            launchPath: launchPath,
          );
        }
      }
      return locateInstalled();
    }

    final found = await _pollForInstalled(locate, detectTimeout);
    if (found == null) throw const OtzariaWizardStillOpen();

    await pruneCacheExcept(
      keepTagNames: keepCachedTagNames ?? {release.tagName},
    );
    // התג של ה-release ולא הגרסה שנקראה מה-exe — אותה סמנטיקה שהמסלול
    // השקט שומר, כדי ששני המסלולים לא יכתבו שני דברים שונים לאותו state.
    return OtzariaInstallState(
      installedTagName: release.tagName,
      installDir: found.installDir,
      launchPath: found.launchPath,
    );
  }

  /// כמה זמן מחכים שההתקנה תופיע אחרי שתהליך האשף חזר. קצר בכוונה: ב-Inno
  /// שמתרומם להרשאות מנהל התהליך שהרצנו חוזר מיד, בעוד המשתמש עוד עומד
  /// באשף — ואז "לא נמצא" אינו כשל אלא "עוד לא סיים", ואומרים לו זאת
  /// במקום לתלות את התוכנה לחצי שעה.
  static const Duration wizardDetectTimeout = Duration(seconds: 20);

  /// קודי היציאה של Inno Setup: 0 הצלחה; 2 ו-5 ביטול של המשתמש (לפני
  /// ההתקנה ובאמצעה); 1223 הוא `ERROR_CANCELLED` של Windows — סירוב ל-UAC,
  /// כלומר גם הוא בחירה ולא תקלה.
  static OtzariaWizardOutcome wizardOutcomeFor(int exitCode) =>
      switch (exitCode) {
        0 => OtzariaWizardOutcome.finished,
        2 || 5 || 1223 => OtzariaWizardOutcome.cancelled,
        _ => OtzariaWizardOutcome.failed,
      };

  /// ההתקנה שנוצרה — לפי התיקייה שכפינו, או לפי זיהוי כשלא כפינו.
  Future<OtzariaInstallState> _findInstalled({
    required OtzariaRelease release,
    required String? installDir,
    required Future<OtzariaInstallState?> Function()? locateInstalled,
    required Duration timeout,
  }) async {
    if (installDir != null) {
      final launchPath = await _waitForInstalledApp(
        installDir: installDir,
        timeout: timeout,
      );
      return OtzariaInstallState(
        installedTagName: release.tagName,
        installDir: installDir,
        launchPath: launchPath,
      );
    }

    if (locateInstalled == null) {
      throw ArgumentError.notNull('locateInstalled');
    }
    final found = await _pollForInstalled(locateInstalled, timeout);
    if (found == null) {
      throw StateError(
        AppL10n.strings.appDomain.installNotDetectedAnywhere(timeout.inSeconds),
      );
    }
    // התג של ה-release ולא הגרסה שנקראה מה-exe: זה מה שהמסלול עם `/DIR=`
    // שומר, ו-`_verifyStoredState` קורא מהדיסק בבדיקה הבאה בכל מקרה.
    return OtzariaInstallState(
      installedTagName: release.tagName,
      installDir: found.installDir,
      launchPath: found.launchPath,
    );
  }

  Future<OtzariaInstallState?> _pollForInstalled(
    Future<OtzariaInstallState?> Function() locateInstalled,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final found = await locateInstalled();
      if (found != null) return found;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  String _requireInstallDir(String? installDir) {
    if (installDir == null) throw ArgumentError.notNull('installDir');
    return installDir;
  }

  Future<OtzariaInstallState> _installMacAppState({
    required OtzariaRelease release,
    required String installDir,
    required Future<void> Function(String stagingDir) stageApp,
  }) async {
    final launchPath = await _installMacApp(
      installDir: installDir,
      stageApp: stageApp,
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

  /// המשימה שיוצרת קיצור-דרך בשולחן העבודה. גם ב-`otzaria.iss` וגם
  /// ב-`otzaria_full.iss` היא מוגדרת `Flags: unchecked`, ולכן התקנה שקטה
  /// דילגה עליה והמשתמש קיבל אוצריא בלי אייקון — בשונה מהתקנה ידנית, שבה
  /// סימן את התיבה בעצמו. `/MERGETASKS` מוסיף אותה לברירת המחדל.
  static const String _desktopIconTask = 'desktopicon';

  /// דגלי ההתקנה השקטה. פונקציה טהורה כדי שהרשימה תהיה ניתנת לבדיקה —
  /// הרצת המתקין עצמה אינה.
  ///
  /// `/VERYSILENT` + `/SUPPRESSMSGBOXES`: אין UI בכלל, כולל תיבות שגיאה.
  /// `/NORESTART`: לא להפעיל מחדש את המחשב גם אם ה-installer "רוצה".
  /// `/LOG=`: ראו [_installFailureOutput]. הדגלים מורכבים בשרשור —
  /// `p.join` היה מתייחס אליהם כרכיבי נתיב.
  ///
  /// **`/DIR=` נמסר רק כשיש תיקייה קיימת לעדכן.** בהתקנה חדשה
  /// ([installDir] = `null`) הוא נעדר בכוונה, והמתקין מתקין ל-
  /// `DefaultDirName` שלו — ברירת המחדל של אוצריא ולא ניחוש שלנו, שהתיישן
  /// בעבר. את מקום ההתקנה מוצאים אחר כך בזיהוי (רג'יסטרי ההסרה).
  static List<String> windowsSilentArgs({
    required String? installDir,
    required String logPath,
  }) =>
      [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        if (installDir != null) '/DIR=$installDir',
        '/MERGETASKS=$_desktopIconTask',
        '/LOG=$logPath',
      ];

  Future<void> _runSilentInstall(
      String installerPath, String? installDir) async {
    final logPath =
        p.join(Directory.systemTemp.path, 'otzaria-install-$pid.log');
    final args = windowsSilentArgs(installDir: installDir, logPath: logPath);

    final result = await Process.run(installerPath, args);
    if (result.exitCode != 0) {
      final details = _installFailureOutput(result, logPath);
      _deleteQuietly(logPath);
      throw StateError(
        AppL10n.strings.appDomain.installerExitCode(result.exitCode, details),
      );
    }
    _deleteQuietly(logPath);

    // הערה: ל-installer-ים מבוססי Inno Setup יש לפעמים תהליך "עוטף"
    // (SetupLdr) שמשגר תהליך-בן ומסתיים מיד, עוד לפני שההתקנה בפועל
    // הסתיימה — ולכן exitCode==0 כאן לא מבטיח שהקבצים כבר על הדיסק.
    // בגלל זה יש polling נפרד ב-_waitForInstalledApp במקום להסתמך רק על
    // סיום התהליך.
  }

  /// כמה שורות מסוף לוג ה-Inno נכנסות להודעת השגיאה.
  static const int _installLogTailLines = 40;

  /// מה שיש לומר על כישלון התקנה. `stdout`/`stderr` של מתקין שקט **ריקים
  /// תמיד**, ולכן "קוד יציאה 5" לבדו לא אומר דבר; לוג ה-Inno הוא זה שאומר
  /// אם הקובץ היה נעול, אם נגמר המקום או אם ההרשאות חסרות.
  String _installFailureOutput(ProcessResult result, String logPath) {
    final tail = _readLogTail(logPath);
    if (tail != null) return AppL10n.strings.appDomain.installerLogTail(tail);
    return 'stdout: ${result.stdout}\nstderr: ${result.stderr}';
  }

  String? _readLogTail(String logPath) {
    try {
      final file = File(logPath);
      if (!file.existsSync()) return null;
      // פענוח סלחני: הלוג נכתב בקידוד של ה-installer (ANSI או UTF-16), ובית
      // אחד לא-חוקי לא יבלע את ההסבר היחיד שיש לכישלון. ה-NUL-ים מוסרים כדי
      // ש-UTF-16 לא ייקרא כטקסט מנוקד באפסים.
      final text = utf8
          .decode(file.readAsBytesSync(), allowMalformed: true)
          .replaceAll(String.fromCharCode(0), '');
      final lines = text
          .split('\n')
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;
      final from = math.max(0, lines.length - _installLogTailLines);
      return lines.skip(from).join('\n');
    } catch (_) {
      return null;
    }
  }

  void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
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
