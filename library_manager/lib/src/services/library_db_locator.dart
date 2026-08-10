import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_state_store.dart';
import 'otzaria_settings_reader.dart';

/// מוצא את נתיב `seforim.db` של המשתמש.
///
/// **סדר החיפוש**:
/// 1. נתיב מותאם אישית ששמור מ-[LibraryStateStore] (המשתמש כבר הצביע עליו).
/// 2. **ההגדרות של אוצריא עצמה** — `key-library-path` +
///    `key-library-folder-name` מתוך `app_preferences.hive`, בדיוק כמו
///    `DatabaseConstants.getDatabasePath` שם. זה המקור האמיתי: משתמש שהעביר
///    את הספרייה לכונן אחר עשה זאת *שם*, ובלי לקרוא את ההגדרה נעדכן קובץ אחר.
/// 3. ספרייה מצורפת ליד ההתקנה (חבילת FULL ב-macOS) — ראו [bundledLibraryDir].
/// 4. ברירות המחדל של אוצריא בפלטפורמה הנוכחית — ראו [defaultDbDirs].
/// 5. **גיבוי** בווינדוס: `C:\אוצריא\seforim.db`.
///
/// מחזיר null אם אף מקור לא נמצא — הקורא (UI) צריך לבקש מהמשתמש להצביע על
/// הקובץ, ואז לקרוא ל-[LibraryStateStore.saveCustomDbPath].
class LibraryDbLocator {
  const LibraryDbLocator({
    required this.stateStore,
    this.settingsReader = const OtzariaSettingsReader(),
    this.otzariaLaunchPath,
    String? operatingSystem,
    Map<String, String>? environment,
  })  : _operatingSystemOverride = operatingSystem,
        _environmentOverride = environment;

  final LibraryStateStore stateStore;

  /// קורא את קופסת ההגדרות של אוצריא. best-effort — ראו [OtzariaSettingsReader].
  final OtzariaSettingsReader settingsReader;

  /// נתיב ההפעלה של אוצריא (`.exe` בווינדוס, חבילת `.app` ב-macOS), אם ידוע.
  /// דרוש כדי לזהות התקנה **ניידת** (שם שורש הנתונים יושב ליד התוכנה ולא
  /// ב-`%APPDATA%`) וספרייה מצורפת. `null` = פשוט מדלגים על שתי האפשרויות.
  final Future<String?> Function()? otzariaLaunchPath;

  /// דריסות לבדיקות בלבד. בלעדיהן בדיקה כמו "אין DB בשום מקום" הייתה
  /// נכשלת אצל מפתח שאוצריא אמיתית מותקנת אצלו במיקום ברירת המחדל.
  final String? _operatingSystemOverride;
  final Map<String, String>? _environmentOverride;

  String get _operatingSystem =>
      _operatingSystemOverride ?? Platform.operatingSystem;
  Map<String, String> get _environment =>
      _environmentOverride ?? Platform.environment;

  /// ה-context לבניית נתיבים — לפי [_operatingSystem], לא לפי המכונה המריצה,
  /// כדי שדריסת ה-OS בבדיקות תייצר נתיבים באמת בסגנון אותה פלטפורמה.
  p.Context get _path => _operatingSystem == 'windows' ? p.windows : p.posix;

  static const String databaseFileName = 'seforim.db';

  /// סימון ההתקנה הניידת של אוצריא, ליד ה-executable שלה
  /// (`AppPaths.portableMarkerFileName`), ותיקיית הנתונים שהוא מפעיל.
  static const String portableMarkerFileName = 'portable.marker';
  static const String portableDataFolderName = 'otzaria_data';

  /// ספרייה מצורפת בחבילת FULL: תיקיית `אוצריא` ליד ההתקנה, עם קובץ סימון
  /// שה-CI של אוצריא יוצר (`AppPaths._bundledLibraryMarkerFileName`).
  static const String bundledLibraryFolderName = 'אוצריא';
  static const String bundledLibraryMarkerFileName = '.otzaria_bundled_library';

  /// גיבוי משני בווינדוס — לא ברירת המחדל האמיתית. ייתכן שזה עדיין נכון
  /// בהתקנות ישנות/מסוימות (למשל חבילת "FULL" שמתקינה במיקום קבוע).
  static const String legacyFallbackLibraryPath = r'C:\אוצריא';

  /// תיקיות ה-`books` שאוצריא משתמשת בהן כברירת מחדל, לפי סדר עדיפות.
  ///
  /// **נגזר מקוד המקור של אוצריא** (`lib/core/app_paths.dart`,
  /// `getDataRootPath` + `getDefaultLibraryPath`), לא מניחוש:
  ///
  /// * Windows — `%APPDATA%\otzaria\books` (אומת גם מול דיווח משתמש בגרסה
  ///   0.9.9x), ובהתקנה מערכתית `%ProgramData%\otzaria\books`.
  /// * macOS — `~/Library/Application Support/otzaria/books`, ובהתקנה
  ///   מערכתית `/Library/Application Support/otzaria/books`.
  ///
  /// [environment] מוזרק כדי שהבדיקות יוכלו לדמות את שתי הפלטפורמות בלי
  /// לגעת בסביבה האמיתית.
  static List<String> defaultDbDirs({
    required String operatingSystem,
    required Map<String, String> environment,
  }) {
    final dirs = <String>[];
    // ה-context נבחר לפי [operatingSystem] ולא לפי המכונה המריצה: `p.join`
    // הגלובלי היה מרכיב נתיבי macOS עם `\` כשהבדיקות רצות ב-Windows.
    final path = operatingSystem == 'windows' ? p.windows : p.posix;

    switch (operatingSystem) {
      case 'windows':
        final appData = environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          dirs.add(path.join(appData, 'otzaria', 'books'));
        }
        final programData = environment['ProgramData'];
        if (programData != null && programData.isNotEmpty) {
          dirs.add(path.join(programData, 'otzaria', 'books'));
        }
      case 'macos':
        final home = environment['HOME'];
        if (home != null && home.isNotEmpty) {
          dirs.add(path.join(
              home, 'Library', 'Application Support', 'otzaria', 'books'));
        }
        dirs.add(
            path.join('/Library', 'Application Support', 'otzaria', 'books'));
      case 'linux':
        // הלאנצ'ר לא נבנה ללינוקס, אבל הבדיקות רצות שם ב-CI — עדיף להחזיר
        // את המיקום הנכון מלהחזיר רשימה ריקה.
        final home = environment['HOME'];
        if (home != null && home.isNotEmpty) {
          dirs.add(path.join(home, '.local', 'share', 'otzaria', 'books'));
        }
    }

    return dirs;
  }

  /// התיקייה שבה יושב ה-executable של אוצריא, לפי נתיב ההפעלה: ב-macOS זהו
  /// `Contents/MacOS` שבתוך חבילת ה-`.app`, ושם גם יושב סימון ההתקנה הניידת.
  String? exeDirFor(String? launchPath) {
    if (launchPath == null || launchPath.isEmpty) return null;
    if (_operatingSystem == 'macos' &&
        _path.basename(launchPath).toLowerCase().endsWith('.app')) {
      return _path.join(launchPath, 'Contents', 'MacOS');
    }
    return _path.dirname(launchPath);
  }

  /// שורשי הנתונים של אוצריא לפי סדר עדיפות: התקנה ניידת קודמת לכול, בדיוק
  /// כמו `AppPaths.getDataRootPath`.
  Future<List<String>> otzariaDataRoots(String? launchPath) async {
    final roots = <String>[];
    final exeDir = exeDirFor(launchPath);
    if (exeDir != null &&
        await File(_path.join(exeDir, portableMarkerFileName)).exists()) {
      roots.add(_path.join(exeDir, portableDataFolderName));
    }

    switch (_operatingSystem) {
      case 'windows':
        final appData = _environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          roots.add(_path.join(appData, 'otzaria'));
        }
        final programData = _environment['ProgramData'];
        if (programData != null && programData.isNotEmpty) {
          roots.add(_path.join(programData, 'otzaria'));
        }
      case 'macos':
        final home = _environment['HOME'];
        if (home != null && home.isNotEmpty) {
          roots.add(
              _path.join(home, 'Library', 'Application Support', 'otzaria'));
        }
        roots.add(_path.join('/Library', 'Application Support', 'otzaria'));
      default:
        final home = _environment['HOME'];
        if (home != null && home.isNotEmpty) {
          roots.add(_path.join(home, '.local', 'share', 'otzaria'));
        }
    }
    return roots;
  }

  /// תיקיית הספרייה המצורפת (חבילת FULL) ליד ההתקנה, או `null`. הסימון הוא
  /// תנאי — בלעדיו תיקייה בשם `אוצריא` שבמקרה נמצאת שם הייתה נחשבת ספרייה.
  Future<String?> bundledLibraryDir(String? launchPath) async {
    // באוצריא הזיהוי מדולג בווינדוס (שם ה-installer כותב את ההגדרה בעצמו).
    if (_operatingSystem != 'macos') return null;
    final exeDir = exeDirFor(launchPath);
    if (exeDir == null) return null;

    final dir = _path.normalize(
      _path.join(exeDir, '..', '..', '..', bundledLibraryFolderName),
    );
    final marker = File(_path.join(dir, bundledLibraryMarkerFileName));
    final db = File(_path.join(dir, databaseFileName));
    if (await marker.exists() && await db.exists()) return dir;
    return null;
  }

  Future<String?> resolveDbPath() async {
    final custom = await stateStore.loadCustomDbPath();
    if (custom != null && await File(custom).exists()) {
      return custom;
    }

    final launchPath = await otzariaLaunchPath?.call();

    // ההגדרה של אוצריא עצמה — המקור המוסמך כשהיא כבר רצה פעם אחת.
    for (final root in await otzariaDataRoots(launchPath)) {
      final settings = await settingsReader.read(root);
      final fromSettings = settings?.resolveDbPath(
        path: _path,
        fileName: databaseFileName,
      );
      if (fromSettings != null && await File(fromSettings).exists()) {
        return fromSettings;
      }
    }

    final bundled = await bundledLibraryDir(launchPath);
    if (bundled != null) return _path.join(bundled, databaseFileName);

    final candidates = defaultDbDirs(
      operatingSystem: _operatingSystem,
      environment: _environment,
    );
    // התקנה ניידת ששורש הנתונים שלה ליד התוכנה, כשאוצריא עוד לא רצה שם.
    final exeDir = exeDirFor(launchPath);
    if (exeDir != null &&
        await File(_path.join(exeDir, portableMarkerFileName)).exists()) {
      candidates.insert(
        0,
        _path.join(exeDir, portableDataFolderName, 'books'),
      );
    }

    for (final dir in candidates) {
      final candidate = _path.join(dir, databaseFileName);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    if (_operatingSystem == 'windows') {
      final legacyPath =
          _path.join(legacyFallbackLibraryPath, databaseFileName);
      if (await File(legacyPath).exists()) {
        return legacyPath;
      }
    }

    return null;
  }
}
