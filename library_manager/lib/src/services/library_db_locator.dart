import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_state_store.dart';

/// מוצא את נתיב `seforim.db` של המשתמש.
///
/// **סדר החיפוש** (לפי בקשת המשתמש: קודם ברירת מחדל, ואז ידני):
/// 1. נתיב מותאם אישית ששמור מ-[LibraryStateStore] (המשתמש כבר הצביע
///    עליו בעבר).
/// 2. ברירת המחדל **האמיתית** של אוצריא בווינדוס:
///    `%APPDATA%\otzaria\books\seforim.db` — מבוססת על דיווח בפועל
///    ממשתמש בגרסה 0.9.9x (יולי 2026), לא על קריאת קוד המקור (הניחוש
///    הקודם, `C:\אוצריא\seforim.db`, היה שגוי — ⚠️ **לא באמת אומת** מול
///    קוד המקור כפי שנטען אז).
/// 3. **גיבוי**: `C:\אוצריא\seforim.db` — ייתכן שזה עדיין נכון בהתקנות
///    ישנות/מסוימות (למשל חבילת "FULL" שמתקינה במיקום קבוע); לא הוסר,
///    רק הפך למשני.
///
/// **לא** מפרסים את הגדרות ה-Hive/Settings של אוצריא כדי לקרוא נתיב
/// מותאם אישית שהמשתמש הגדיר שם — אם אף אחד מהמיקומים לא נמצא, פשוט
/// מבקשים מהמשתמש להצביע ידנית (per ההחלטה איתו).
///
/// מחזיר null אם אף מקור לא נמצא — הקורא (UI) צריך לבקש מהמשתמש
/// להצביע על התיקייה, ואז לקרוא ל-[LibraryStateStore.saveCustomDbPath].
class LibraryDbLocator {
  const LibraryDbLocator({required this.stateStore});

  final LibraryStateStore stateStore;

  static const String databaseFileName = 'seforim.db';

  /// גיבוי משני — לא ברירת המחדל האמיתית (ראו doc-comment של המחלקה).
  static const String legacyFallbackLibraryPath = r'C:\אוצריא';

  /// `%APPDATA%\otzaria\books` — ברירת המחדל האמיתית שאומתה מול משתמש.
  String? get _appDataBooksDir {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return p.join(appData, 'otzaria', 'books');
  }

  Future<String?> resolveDbPath() async {
    final custom = await stateStore.loadCustomDbPath();
    if (custom != null && await File(custom).exists()) {
      return custom;
    }

    final appDataDir = _appDataBooksDir;
    if (appDataDir != null) {
      final appDataPath = p.join(appDataDir, databaseFileName);
      if (await File(appDataPath).exists()) {
        return appDataPath;
      }
    }

    final legacyPath = p.join(legacyFallbackLibraryPath, databaseFileName);
    if (await File(legacyPath).exists()) {
      return legacyPath;
    }

    return null;
  }
}
