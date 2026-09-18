import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import 'otzaria_settings_reader.dart';

/// מכוון את ההגדרה של אוצריא **למיקום הספרייה** — הכתיבה היחידה שלנו
/// לקופסת ההגדרות שלה.
///
/// **למה בכלל.** `DatabaseConstants.getDatabasePath` באוצריא נופל ל-`'.'`
/// כש-`key-library-path` ריק — היא לעולם אינה סורקת את ברירת המחדל שלה
/// עצמה. ספרייה שהתקנו ב-`%APPDATA%\otzaria\books` לכן פשוט אינה נראית,
/// והמשתמש נשאר עם מסך "ספרייה ריקה" (דיווח בפורום, פוסט 39342).
///
/// **מתי מותר.** רק כשההגדרה עדיין ריקה — בחירה קיימת של המשתמש אינה
/// נדרסת לעולם — ורק כשאוצריא סגורה (`OtzariaProcessGuard`, נבדק שוב
/// ב-`LibraryManager._pointOtzariaAtFreshDb` מיד לפני הכתיבה: פתיחה
/// במקום לוקחת נעילה בתיקייה שלה). בניגוד ל-[OtzariaSettingsReader] כאן
/// חייבים לפתוח את הקופסה **במקומה**, ולכן היא נפתחת ונסגרת מיד.
class OtzariaSettingsWriter {
  const OtzariaSettingsWriter();

  /// כותב `key-library-path` = תיקיית [dbPath] ו-`key-library-folder-name`
  /// ריק — בדיוק מה שאוצריא עצמה כותבת כשהמשתמש בוחר תיקייה
  /// (`EmptyLibraryBloc`). `false` = לא נכתב דבר, והקורא צריך לומר למשתמש
  /// להצביע על המיקום ידנית.
  ///
  /// [allowCreate] מרשה ליצור את שורש הנתונים והקופסה כשאוצריא מותקנת אך
  /// עוד לא רצה אף פעם. בלעדיו לא ניצור תיקיות לאוצריא שאינה מותקנת כלל.
  Future<bool> pointLibraryAt({
    required String dataRootPath,
    required String dbPath,
    bool allowCreate = false,
  }) =>
      OtzariaSettingsReader.runExclusively(
        () => _write(dataRootPath, dbPath, allowCreate),
      );

  Future<bool> _write(
    String dataRootPath,
    String dbPath,
    bool allowCreate,
  ) async {
    // נתיב יחסי היה נכתב כמו שהוא, ואוצריא הייתה מחפשת אותו יחסית לתיקיית
    // העבודה **שלה** — כלומר במקום אקראי.
    if (!p.isAbsolute(dbPath)) return false;

    final root = Directory(dataRootPath);
    if (!await root.exists()) {
      if (!allowCreate) return false;
      try {
        await root.create(recursive: true);
      } catch (_) {
        return false;
      }
    }

    Box<dynamic>? box;
    try {
      Hive.init(dataRootPath);
      box = await Hive.openBox<dynamic>(
        OtzariaSettingsReader.boxName,
        path: dataRootPath,
        // **הדגל הקריטי כאן.** ברירת המחדל של Hive היא "לשחזר" קופסה
        // פגומה — כלומר לקצץ את הקובץ במקום, לפני שכתבנו מילה. הקורא עושה
        // זאת על עותק ולכן לא אכפת לו; כאן זה קובץ ההגדרות **החי** של
        // המשתמש. קופסה שאינה נפתחת נקייה תיזרוק, ונוותר על הכתיבה.
        crashRecovery: false,
      );
      // Hive מאתר קופסה פתוחה **לפי שם בלבד** ומתעלם מה-`path` שנמסר: אם
      // קופסה בשם הזה נשארה פתוחה על שורש אחר, קיבלנו אותה — וכתבנו
      // להתקנה הלא נכונה. הנתיב בפועל הוא הבדיקה היחידה שתופסת את זה.
      final expected = p.join(dataRootPath, OtzariaSettingsReader.boxFileName);
      if (box.path == null || !p.equals(box.path!, expected)) return false;

      // כתיבה אחת ולא שתיים: קריסה בין שני `put` הייתה משאירה נתיב ספרייה
      // חדש לצד שם תיקייה ישן, כלומר נתיב מסד שאינו קיים.
      await box.putAll({
        OtzariaSettingsReader.keyLibraryPath: p.dirname(dbPath),
        OtzariaSettingsReader.keyLibraryFolderName: '',
      });
      return true;
    } catch (_) {
      // כשל כאן אינו הופך עדכון שהצליח לכישלון — הוא רק מחזיר `false`,
      // והמשתמש מקבל את ההוראה להצביע על המיקום בעצמו.
      return false;
    } finally {
      // הסגירה משחררת את קובץ הנעילה שנוצר בתיקייה של אוצריא ומוחקת אותו.
      try {
        await box?.close();
      } catch (_) {}
    }
  }
}
