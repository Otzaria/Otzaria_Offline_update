import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_state_store.dart';

/// מוצא את נתיב `seforim.db` של המשתמש.
///
/// **סדר החיפוש** (לפי בקשת המשתמש: קודם ברירת מחדל, ואז ידני):
/// 1. נתיב מותאם אישית ששמור מ-[LibraryStateStore] (המשתמש כבר הצביע
///    עליו בעבר).
/// 2. ברירות המחדל של אוצריא בפלטפורמה הנוכחית — ראו [defaultDbDirs].
/// 3. **גיבוי** בווינדוס: `C:\אוצריא\seforim.db`.
///
/// **לא** מפרסים את הגדרות ה-Hive/Settings של אוצריא כדי לקרוא נתיב
/// מותאם אישית שהמשתמש הגדיר שם — אם אף אחד מהמיקומים לא נמצא, פשוט
/// מבקשים מהמשתמש להצביע ידנית (per ההחלטה איתו).
///
/// מחזיר null אם אף מקור לא נמצא — הקורא (UI) צריך לבקש מהמשתמש
/// להצביע על התיקייה, ואז לקרוא ל-[LibraryStateStore.saveCustomDbPath].
class LibraryDbLocator {
  const LibraryDbLocator({
    required this.stateStore,
    String? operatingSystem,
    Map<String, String>? environment,
  })  : _operatingSystemOverride = operatingSystem,
        _environmentOverride = environment;

  final LibraryStateStore stateStore;

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

  Future<String?> resolveDbPath() async {
    final custom = await stateStore.loadCustomDbPath();
    if (custom != null && await File(custom).exists()) {
      return custom;
    }

    final candidates = defaultDbDirs(
      operatingSystem: _operatingSystem,
      environment: _environment,
    );

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
