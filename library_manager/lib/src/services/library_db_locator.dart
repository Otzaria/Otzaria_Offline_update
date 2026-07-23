import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_state_store.dart';

/// מוצא את נתיב `seforim.db` של המשתמש.
///
/// **סדר החיפוש** (לפי בקשת המשתמש: קודם ברירת מחדל, ואז ידני):
/// 1. נתיב מותאם אישית ששמור מ-[LibraryStateStore] (המשתמש כבר הצביע
///    עליו בעבר).
/// 2. ברירת המחדל **של אוצריא עצמה** בווינדוס: `C:/אוצריא/seforim.db`
///    — אומת ישירות מול קוד המקור של Otzaria
///    (`lib/main.dart:initLibraryPath` ו-
///    `lib/data/constants/database_constants.dart`, יולי 2026): אם
///    המשתמש לא שינה את ה-`key-library-path` שלו, אוצריא עצמה שומרת שם
///    את הקובץ. **לא** מפרסים את הגדרות ה-Hive/Settings של אוצריא כדי
///    לקרוא נתיב מותאם אישית שהמשתמש הגדיר שם — אם ברירת המחדל לא
///    נמצאת, פשוט מבקשים מהמשתמש להצביע ידנית (per ההחלטה איתו).
///
/// מחזיר null אם שני המקורות לא נמצאו — הקורא (UI) צריך לבקש מהמשתמש
/// להצביע על התיקייה, ואז לקרוא ל-[LibraryStateStore.saveCustomDbPath].
class LibraryDbLocator {
  const LibraryDbLocator({required this.stateStore});

  final LibraryStateStore stateStore;

  /// ברירת המחדל הקבועה של אוצריא בווינדוס כשלא הוגדר נתיב אחר.
  static const String otzariaDefaultLibraryPath = r'C:\אוצריא';
  static const String databaseFileName = 'seforim.db';

  Future<String?> resolveDbPath() async {
    final custom = await stateStore.loadCustomDbPath();
    if (custom != null && await File(custom).exists()) {
      return custom;
    }

    final defaultPath = p.join(otzariaDefaultLibraryPath, databaseFileName);
    if (await File(defaultPath).exists()) {
      return defaultPath;
    }

    return null;
  }
}
