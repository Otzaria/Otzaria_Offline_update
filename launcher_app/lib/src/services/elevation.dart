import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// שגיאות "אין הרשאה", וההרמה שפותרת אותן.
///
/// למה זה כאן: אוצריא מותקנת לא פעם ב-`Program Files`, ואז גם עדכון המסד
/// וגם התקנה חדשה נכשלים בהודעה של מערכת ההפעלה שאינה אומרת למשתמש דבר —
/// והפתרון בשטח הוא "הפעל כמנהל". הזיהוי כאן, וההצעה יוצאת מ-`AppShell`.
///
/// **המתקין של אוצריא אינו זקוק לזה** — Inno מרים את עצמו (ולכן קוד יציאה
/// 1223 מטופל כסירוב ל-UAC). מה שכן זקוק הוא מה שהלאנצ'ר כותב בעצמו:
/// המסד, קובצי הנלווים והתוספים.
class Elevation {
  const Elevation._();

  /// הזיהוי העיקרי הוא קוד השגיאה של מערכת ההפעלה, ולא טקסט: ההודעה עצמה
  /// מתורגמת לשפת ווינדוס, ובעברית "הגישה נדחתה" לא היה נתפס.
  static bool isAccessDenied(Object error) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code != null) {
        // 5 = ERROR_ACCESS_DENIED, 13 = EACCES. אינם אותו מספר, ולכן לפי
        // הפלטפורמה: 13 בווינדוס הוא ERROR_INVALID_DATA, שגיאה אחרת לגמרי.
        return Platform.isWindows ? code == 5 : code == 13;
      }
    }
    // מסד בתיקייה מוגנת נכשל ב-sqlite ולא ב-dart:io, ואין שם OSError.
    // הטקסט הוא של sqlite עצמו — באנגלית בכל מערכת, ולכן בטוח להשוואה.
    return error.toString().contains('readonly database');
  }

  /// מוסיף להודעת השגיאה את מה שאפשר לעשות — ורק כשזו שגיאת הרשאות.
  /// בכל מקרה אחר ההודעה נשארת בדיוק כשהייתה.
  static String describe(Object error) => isAccessDenied(error)
      ? '$error\n\n${AppL10n.strings.elevation.hint}'
      : error.toString();

  /// מפעיל מחדש את **אותו** קובץ הרצה עם בקשת הרשאות מנהל (UAC), ויוצא.
  /// מחזיר `null` כשההרמה יצאה לדרך — ואז התהליך הזה כבר נסגר — או את מה
  /// שמנע אותה, כדי שהמשתמש יקבל סיבה ולא רק "נכשל".
  ///
  /// דרך PowerShell כי `-Verb RunAs` הוא הדרך היחידה להרים תהליך בלי FFI;
  /// `Process.start` רגיל לא מרים. הנתיב נמסר במרכאות יחידות עם הכפלה של
  /// גרש בתוכו — נתיב עם `'` היה שובר את הפקודה.
  static Future<Object?> restartElevated({
    Future<void> Function(String executable, List<String> arguments)?
        startDetached,
    void Function()? quit,
  }) async {
    if (!Platform.isWindows) return 'unsupported: ${Platform.operatingSystem}';
    final start = startDetached ?? _defaultStartDetached;
    final exe = Platform.resolvedExecutable;
    try {
      await start('powershell', [
        '-NoProfile',
        '-WindowStyle',
        'Hidden',
        '-Command',
        "Start-Process -FilePath '${exe.replaceAll("'", "''")}' -Verb RunAs",
      ]);
    } catch (e) {
      return e;
    }
    (quit ?? _defaultQuit)();
    return null;
  }

  static Future<void> _defaultStartDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: p.dirname(Platform.resolvedExecutable),
      mode: ProcessStartMode.detached,
    );
  }

  static void _defaultQuit() => exit(0);
}
