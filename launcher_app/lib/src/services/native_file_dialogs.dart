import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';

/// דיאלוגי הקבצים של מערכת ההפעלה — **כל** קריאה ל-`FilePicker` עוברת כאן.
///
/// ⚠️ שני דברים שנשברו כשקראו ל-`FilePicker` ישירות:
///
/// - **החלון אינו מקבל בחזרה את מיקוד המקלדת** כשהדיאלוג נסגר. שורת הכותרת
///   של המערכת מוסתרת (`TitleBarStyle.hidden` ב-`main.dart`), ואז ווינדוס
///   מחזירה את המיקוד לחלון שפתח את הדיאלוג ולא לחלון שלנו. התוצאה: שדות
///   טקסט שנראים תקינים ואינם מקבלים הקלדה עד קליק — בדיוק מה שנראה
///   כ"טופס התוכנה אינו עובד" אחרי בחירת קובץ מהמחשב.
/// - **`files.single` זורק** על רשימה ריקה, ויש מסלולי ביטול שמחזירים
///   בדיוק כזו. החריגה בורחת אל ה-`Future` של הלחיצה, והכפתור פשוט נראה
///   מת.
abstract final class NativeFileDialogs {
  /// בחירת קובץ אחד, או `null` בביטול.
  static Future<String?> pickFile({
    required String dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: dialogTitle,
        type: allowedExtensions == null ? FileType.any : FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      final files = picked?.files ?? const [];
      return files.isEmpty ? null : files.first.path;
    } finally {
      await _restoreWindowFocus();
    }
  }

  /// בחירת תיקייה, או `null` בביטול.
  static Future<String?> pickDirectory({required String dialogTitle}) async {
    try {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );
    } finally {
      await _restoreWindowFocus();
    }
  }

  /// בחירת יעד לשמירה, או `null` בביטול.
  static Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
    List<String>? allowedExtensions,
  }) async {
    try {
      return await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: allowedExtensions == null ? FileType.any : FileType.custom,
        allowedExtensions: allowedExtensions,
      );
    } finally {
      await _restoreWindowFocus();
    }
  }

  /// כשל כאן הוא קוסמטי בלבד, ובבדיקות אין תוסף חלון בכלל — ולכן הוא נבלע.
  static Future<void> _restoreWindowFocus() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    try {
      await windowManager.focus();
    } catch (_) {}
  }
}
