import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart'
    show AppReportService, DirectoryReportOutbox, SearchFeedbackTransport;
import 'package:ffi/ffi.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart'
    show writeBytesAtomically;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../self_update/launcher_install_layout.dart';
import 'machine_state_migration.dart';

enum AppPathsFailure {
  cannotWrite,
  driveFull,
  appTranslocated,
  runningFromTemp,
  systemDrive,
  stateMigration,
}

class AppPathsException implements Exception {
  const AppPathsException({
    required this.message,
    required this.attemptedDir,
    this.kind = AppPathsFailure.cannotWrite,
  });

  final String message;
  final String attemptedDir;
  final AppPathsFailure kind;

  @override
  String toString() => 'AppPathsException: $message ($attemptedDir)';
}

/// תיקיית הנתונים של הלאנצ'ר — **תמיד** צמודה לקובץ ההרצה, ואינה ניתנת
/// לשינוי. זו הדרישה המרכזית של עבודה מכונן נייד: הנתונים נוסעים עם
/// התוכנה, ולא נשארים על המחשב שממנו הורידו אותם.
class AppPaths {
  const AppPaths({
    required this.dataDir,
    required this.stateDir,
    this.readOnly = false,
    this.driveFull = false,
    this.mirrorLocked = false,
    String? prefsDir,
  }) : _prefsDir = prefsDir;

  /// שם התיקייה שנוצרת לצד קובץ ההרצה.
  static const String dirName = 'OtzariaData';

  /// שם התיקייה שבה נשמרים לוג ומצב כשהכונן עצמו לקריאה בלבד ([readOnly]).
  static const String machineDirName = 'OtzariaOfflineUpdate';

  /// המראה — המקור שממנו קוראים בדיקות והתקנות — תמיד לצד קובץ ההרצה.
  final String dataDir;

  /// לאן **כותבים**: לוג, הגדרות ומצב. זהה ל-[dataDir] בהרצה רגילה, ומצביע
  /// לתיקיית המשתמש שבמחשב הזה כשהכונן מוגן מפני כתיבה.
  final String stateDir;

  /// `true` = הכונן לקריאה בלבד. ההתקנות עובדות (הן כותבות למחשב), ההורדות
  /// מהרשת ועדכון הלאנצ'ר עצמו לא — אין לאן להוריד.
  final bool readOnly;

  final bool driveFull;

  /// `mirror/` נעולה אך תיקיות הנתונים (לוגים, דוחות, משוב) כתיבות: [readOnly]
  /// נשאר `true` ומכבה הורדות, אבל איסוף הדוחות והמשוב פעילים.
  final bool mirrorLocked;

  final String? _prefsDir;

  /// היכן יושבים `launcher_settings.json` ו-FAQ. במראה נעולה השורש נעול,
  /// ולכן הם במחשב ([stateDir] עצמו נשאר בכונן, כדי שהדוחות יעברו איתו).
  String get prefsDir => _prefsDir ?? stateDir;

  /// שלושת ה-manifest שכל אחד מהם לבדו מוכיח שהמראה נמלאה בפועל.
  static const List<List<String>> _mirrorManifests = [
    ['mirror', 'library', 'releases.json'],
    ['mirror', 'app', 'latest-release.json'],
    ['mirror', 'android', 'latest-release.json'],
    ['mirror', 'plugins', 'catalog.json'],
  ];

  static Future<AppPaths> resolve({
    Map<String, String>? environment,
    String? resolvedExecutable,
    bool? isMacOS,
    bool? isWindows,
    List<String>? tempDirs,
  }) async {
    final macOS = isMacOS ?? Platform.isMacOS;
    final windows = isWindows ?? Platform.isWindows;
    final executable = resolvedExecutable ?? Platform.resolvedExecutable;
    final dataDir = p.join(
      executableRoot(executable, isMacOS: macOS),
      dirName,
    );
    if (macOS && executable.contains('/AppTranslocation/')) {
      throw AppPathsException(
        message: AppL10n.strings.setupError.appTranslocated,
        attemptedDir: dataDir,
        kind: AppPathsFailure.appTranslocated,
      );
    }
    if (windows &&
        isTemporaryLocation(
          p.windows.dirname(executable),
          tempDirs: tempDirs ?? _windowsTempDirs(environment),
        )) {
      throw AppPathsException(
        message: AppL10n.strings.setupError.runningFromTemp,
        attemptedDir: dataDir,
        kind: AppPathsFailure.runningFromTemp,
      );
    }
    final env = environment ?? Platform.environment;
    // נתיב ה-stub קיים רק בהרצה הארוזה, ולכן `flutter run` ובדיקות פטורים.
    final stubPath = env[LauncherInstallLayout.stubPathEnvVar] ?? '';
    if (windows && isOnSystemDrive(stubPath, systemDrive: env['SystemDrive'])) {
      throw AppPathsException(
        message: AppL10n.strings.setupError.systemDrive,
        attemptedDir: p.windows.dirname(stubPath),
        kind: AppPathsFailure.systemDrive,
      );
    }
    final failure = await _probeWritable(dataDir);
    final mirrorFailure = await _mirrorWriteFailure(dataDir);
    final mirrorLocked = mirrorFailure != null;
    if (failure == null && !mirrorLocked) {
      return AppPaths(dataDir: dataDir, stateDir: dataDir);
    }

    final writeFailure = failure ?? mirrorFailure!;
    final diskFull = _isDiskFull(writeFailure);
    if (await _hasMirror(dataDir)) {
      final machineDir = machineStateDir(
        environment ?? Platform.environment,
        isWindows: Platform.isWindows,
        isMacOS: macOS,
      );
      if (machineDir != null && await _probeWritable(machineDir) == null) {
        if (mirrorLocked && !diskFull && await _dataFoldersWritable(dataDir)) {
          return AppPaths(
            dataDir: dataDir,
            stateDir: dataDir,
            readOnly: true,
            mirrorLocked: true,
            prefsDir: machineDir,
          );
        }
        return AppPaths(
          dataDir: dataDir,
          stateDir: machineDir,
          readOnly: true,
          driveFull: diskFull,
        );
      }
    }
    throw AppPathsException(
      message: diskFull
          ? AppL10n.strings.setupError.driveFull
          : writeFailureMessage(writeFailure, isMacOS: macOS),
      attemptedDir: dataDir,
      kind: diskFull ? AppPathsFailure.driveFull : AppPathsFailure.cannotWrite,
    );
  }

  /// Explorer מריץ exe שנפתח מתוך zip מעותק תחת `%TEMP%` (`Temp1_<שם>.zip`),
  /// ומה שנכתב שם נמחק. תיקיית temp שהיא שורש כונן אינה נחשבת. = `stub.c`.
  static bool isTemporaryLocation(
    String dir, {
    required List<String> tempDirs,
  }) {
    final normalized = p.windows.normalize(dir).toLowerCase();
    for (final temp in tempDirs) {
      if (temp.isEmpty) continue;
      final root = p.windows.normalize(temp).toLowerCase();
      if (p.windows.rootPrefix(root) == root) continue;
      if (normalized == root || p.windows.isWithin(root, normalized)) {
        return true;
      }
    }
    return false;
  }

  /// `true` כש-[path] יושב על כונן המערכת. נתיב רשת (UNC) וכל אות כונן אחרת,
  /// כולל כונן קבוע חיצוני, מותרים — הכלי נוסע בין מחשבים ואינו שייך לאחד מהם.
  static bool isOnSystemDrive(String path, {required String? systemDrive}) {
    final pathLetter = _driveLetter(path);
    final systemLetter = _driveLetter(systemDrive ?? '');
    return pathLetter != null && pathLetter == systemLetter;
  }

  static String? _driveLetter(String path) {
    final match = RegExp(r'^(?:\\\\\?\\)?([A-Za-z]):').firstMatch(path);
    return match?.group(1)!.toUpperCase();
  }

  static List<String> _windowsTempDirs(Map<String, String>? environment) {
    final env = environment ?? Platform.environment;
    final dirs = <String>{
      for (final key in const ['TEMP', 'TMP'])
        if (env[key] case final value? when value.isNotEmpty) value,
    };
    final buffer = wsalloc(MAX_PATH + 1);
    try {
      final length = GetTempPath(MAX_PATH + 1, buffer);
      if (length > 0 && length <= MAX_PATH) dirs.add(buffer.toDartString());
      for (final dir in dirs.toList()) {
        final short = dir.toNativeUtf16();
        try {
          final long = GetLongPathName(short, buffer, MAX_PATH + 1);
          if (long > 0 && long <= MAX_PATH) dirs.add(buffer.toDartString());
        } finally {
          free(short);
        }
      }
    } finally {
      free(buffer);
    }
    return dirs.toList();
  }

  /// ב-macOS מיקום שהמשתמש לא אישר (TCC) נכשל ב-EPERM, והודעת המערכת אינה
  /// אומרת איפה מאשרים.
  static String writeFailureMessage(
    FileSystemException failure, {
    required bool isMacOS,
  }) {
    final t = AppL10n.strings.setupError;
    if (isMacOS && failure.osError?.errorCode == 1) {
      return t.macVolumeAccessDenied;
    }
    return t.cannotWriteToDataDir(failure.osError?.message ?? failure.message);
  }

  static bool _isDiskFull(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == null) return false;
    return Platform.isWindows ? code == 39 || code == 112 : code == 28;
  }

  /// התיקייה שבה "יושבת" התוכנה מנקודת מבט המשתמש.
  ///
  /// ב-macOS קובץ ההרצה קבור ב-`<App>.app/Contents/MacOS`, ותיקייה שנוצרת
  /// לצידו נכנסת **לתוך** החבילה: המשתמש אינו רואה אותה ב-Finder, והעדכון
  /// העצמי — שמחליף את החבילה כולה — מוחק אותה. לכן מטפסים החוצה אל
  /// התיקייה שבה יושבת החבילה עצמה, בדיוק כמו ליד ה-exe בווינדוס.
  static String executableRoot(
    String resolvedExecutable, {
    required bool isMacOS,
  }) {
    final exeDir = p.dirname(resolvedExecutable);
    if (!isMacOS) return exeDir;
    final bundle = enclosingAppBundle(exeDir);
    return bundle == null ? exeDir : p.dirname(bundle);
  }

  /// חבילת ה-`.app` שמכילה את [path], או `null` כשההרצה אינה מתוך חבילה
  /// (`flutter run`, בדיקות, בינארי חשוף).
  static String? enclosingAppBundle(String path) {
    var current = p.normalize(path);
    while (true) {
      if (p.extension(current).toLowerCase() == '.app') return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  static Future<FileSystemException?> _probeWritable(String dir) async {
    File? probe;
    try {
      await Directory(dir).create(recursive: true);
      probe = File(p.join(dir, '.write-test-$pid'));
      await probe.writeAsString('ok', flush: true);
      return null;
    } on FileSystemException catch (e) {
      return e;
    } finally {
      // גם כתיבה שנכשלה באמצע (דיסק מלא) עלולה להשאיר קובץ ב-mirror/.
      try {
        await probe?.delete();
      } catch (_) {
        // best-effort: מחיקה שנכשלה אינה כשל בדיקה.
      }
    }
  }

  /// `mirror/` קיימת ואי אפשר לכתוב בה. חסרה = אפשר ליצור אותה, ולא נעולה.
  static Future<FileSystemException?> _mirrorWriteFailure(
      String dataDir) async {
    final mirror = p.join(dataDir, 'mirror');
    try {
      if (!await Directory(mirror).exists()) return null;
    } on FileSystemException catch (error) {
      return error;
    }
    // כשל חולף (אנטי-וירוס, הפרת שיתוף) בכונן כתיב לא יהפוך אותו לנעול.
    FileSystemException? failure;
    for (var attempt = 0; attempt < mirrorProbeAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(mirrorProbeBackoff * attempt);
      }
      failure = await _probeWritable(mirror);
      if (failure == null) return null;
    }
    return failure;
  }

  static const int mirrorProbeAttempts = 3;
  static const Duration mirrorProbeBackoff = Duration(milliseconds: 100);

  /// התיקיות שהמשגר כותב אליהן במחשב לא-מקוון: לוג ומצב, דוחות, משוב חיפוש.
  static Future<bool> _dataFoldersWritable(String dataDir) async {
    for (final dir in [
      p.join(dataDir, logsDirName),
      DirectoryReportOutbox.dirIn(dataDir),
      AppReportService.dirIn(dataDir),
      SearchFeedbackTransport.dirIn(dataDir),
    ]) {
      if (await _probeWritable(dir) != null) return false;
    }
    return true;
  }

  /// `true` אם המראה נושאת תוכן — קיומו של manifest אחד מספיק. תיקייה ריקה
  /// על כונן נעול אינה "מצב קריאה" אלא סתם מקום שאין ממנו מה להתקין.
  static Future<bool> _hasMirror(String dataDir) async {
    for (final parts in _mirrorManifests) {
      try {
        if (await File(p.joinAll([dataDir, ...parts])).exists()) return true;
      } on FileSystemException {
        // כונן שלא ניתן לקרוא ממנו בכלל — אין מראה, וזה נאמר בשגיאה.
      }
    }
    return false;
  }

  /// תיקיית הלוגים — שם יושבים גם קובצי המצב, כדי ששורש הנתונים יישאר נקי.
  static const String logsDirName = 'logs';

  /// קובצי המצב שהיו בשורש [stateDir] ועברו ל-[stateFilesDir].
  static const List<String> stateFileNames = [
    'otzaria_install_state.json',
    'library_state.json',
    'custom_apps_announced.json',
    'plugins_known.json',
    'notices_seen.json',
    'store_app_destination.json',
  ];

  /// היכן נכתבים קובצי המצב. נגזר מ-[stateDir] ולא מהלוגר, שנופל ל-temp.
  String get stateFilesDir => p.join(stateDir, logsDirName);

  /// מעביר קובצי מצב מהשורש ל-[stateFilesDir]; קובץ שכבר קיים שם גובר.
  /// חייב לרוץ לפני שמישהו קורא אותם, אחרת ההתקנה הקיימת נראית כחדשה.
  Future<void> migrateStateFiles() async {
    for (final name in stateFileNames) {
      try {
        final source = File(p.join(stateDir, name));
        final target = File(p.join(stateFilesDir, name));
        if (!await source.exists() || await target.exists()) continue;
        await target.parent.create(recursive: true);
        try {
          await source.rename(target.path);
        } on FileSystemException {
          await writeBytesAtomically(target.path, await source.readAsBytes());
          await source.delete();
        }
      } catch (_) {
        // best-effort: קובץ שלא עבר נשאר בשורש; זה לא כשל הרצה.
        continue;
      }
    }
  }

  /// המצב מתמזג לפי רשומה; דוחות ממתינים עוברים לכונן רק אחרי כתיבה בטוחה.
  /// כשל עוצר לפני פתיחת החנויות ושליחת התור, כדי שההפעלה הבאה תוכל להשלים.
  Future<void> seedStateFromMachine() async {
    if (!mirrorLocked || prefsDir == stateDir) return;
    try {
      await MachineStateMigration(
        sourceDir: prefsDir,
        targetDir: stateDir,
        fileNames: stateFileNames,
      ).run();
      final reports =
          AppReportService(directory: AppReportService.dirIn(stateDir));
      try {
        await reports.migratePendingFrom(AppReportService.dirIn(prefsDir));
      } finally {
        reports.dispose();
      }
    } catch (error) {
      throw AppPathsException(
        message: AppL10n.strings.setupError.stateMigrationFailed('$error'),
        attemptedDir: stateFilesDir,
        kind: AppPathsFailure.stateMigration,
      );
    }
  }

  /// הגדרות המחשב מועתקות מהכונן הנעול רק אם טרם נשמרו כאן.
  Future<void> seedPreferences() async {
    if (!readOnly) return;
    const name = 'launcher_settings.json';
    final target = File(p.join(prefsDir, name));
    try {
      if (await target.exists()) return;
      final source = File(p.join(dataDir, name));
      await writeBytesAtomically(target.path, await source.readAsBytes());
    } on FileSystemException {
      // כשל העתקה משאיר את ברירת המחדל.
    }
  }

  /// תיקיית הכתיבה שבמחשב הזה, או `null` כשאין ממה לגזור אותה. ציבורית כדי
  /// שבדיקה אחת תאמת את שלוש הפלטפורמות מאותה מכונה.
  ///
  /// ב-macOS זו `~/Library/Application Support` — המקום שבו אפליקציה שומרת
  /// מצב, ואותו שורש שאוצריא עצמה משתמשת בו. `XDG_DATA_HOME` הוא מוסכמה של
  /// לינוקס, ותיקייה מוסתרת תחת `~/.local` היא מקום שמשתמש מק לא ימצא בו.
  static String? machineStateDir(
    Map<String, String> environment, {
    required bool isWindows,
    required bool isMacOS,
  }) {
    final String? base;
    if (isWindows) {
      base = environment['LOCALAPPDATA'] ?? environment['APPDATA'];
    } else if (isMacOS) {
      base = _joinHome(environment, ['Library', 'Application Support']);
    } else {
      base = environment['XDG_DATA_HOME'] ??
          _joinHome(environment, ['.local', 'share']);
    }
    if (base == null || base.isEmpty) return null;
    return p.join(base, machineDirName);
  }

  static String? _joinHome(Map<String, String> environment, List<String> rest) {
    final home = environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return p.joinAll([home, ...rest]);
  }
}
