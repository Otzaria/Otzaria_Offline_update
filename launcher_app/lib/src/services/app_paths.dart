import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../self_update/launcher_install_layout.dart';

enum AppPathsFailure {
  cannotWrite,
  driveFull,
  appTranslocated,
  runningFromTemp,
  systemDrive,
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
  });

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

  /// שלושת ה-manifest שכל אחד מהם לבדו מוכיח שהמראה נמלאה בפועל.
  static const List<List<String>> _mirrorManifests = [
    ['mirror', 'library', 'releases.json'],
    ['mirror', 'app', 'latest-release.json'],
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
    if (failure == null) {
      return AppPaths(dataDir: dataDir, stateDir: dataDir);
    }

    final diskFull = _isDiskFull(failure);
    if (await _hasMirror(dataDir)) {
      final stateDir = machineStateDir(
        environment ?? Platform.environment,
        isWindows: Platform.isWindows,
        isMacOS: macOS,
      );
      if (stateDir != null && await _probeWritable(stateDir) == null) {
        return AppPaths(
          dataDir: dataDir,
          stateDir: stateDir,
          readOnly: true,
          driveFull: diskFull,
        );
      }
    }

    throw AppPathsException(
      message: diskFull
          ? AppL10n.strings.setupError.driveFull
          : writeFailureMessage(failure, isMacOS: macOS),
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
    final File probe;
    try {
      await Directory(dir).create(recursive: true);
      probe = File(p.join(dir, '.write-test-$pid'));
      await probe.writeAsString('ok', flush: true);
    } on FileSystemException catch (e) {
      return e;
    }
    try {
      await probe.delete();
    } on FileSystemException catch (_) {}
    return null;
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
          await source.copy(target.path);
          await source.delete();
        }
      } catch (_) {
        // best-effort: קובץ שלא עבר נשאר בשורש; זה לא כשל הרצה.
        continue;
      }
    }
  }

  /// שמות קובצי ההעדפות שנוסעים עם הכונן — ראו [seedPreferences].
  static const List<String> preferenceFileNames = [
    'launcher_settings.json',
    'faq_customization.json',
  ];

  /// מעתיק פעם אחת את **העדפות** המשתמש מהכונן לתיקיית הכתיבה שבמחשב, כדי
  /// שכונן נעול שיצא מהבית עם שפה, ערכת נושא וערוץ נבחר יגיע איתם. קובצי
  /// המצב (מה מותקן ואיפה) אינם מועתקים בכוונה: הם מתארים את המחשב שכתב
  /// אותם, ולא את זה שקורא אותם עכשיו. best-effort — העדפה שלא הועתקה
  /// פירושה ברירת מחדל, לא כשל הרצה.
  Future<void> seedPreferences() async {
    if (!readOnly) return;
    for (final name in preferenceFileNames) {
      try {
        final target = File(p.join(stateDir, name));
        if (await target.exists()) continue;
        final source = File(p.join(dataDir, name));
        if (!await source.exists()) continue;
        await source.copy(target.path);
      } on FileSystemException {
        continue;
      }
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
