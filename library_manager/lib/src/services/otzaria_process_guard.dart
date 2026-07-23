import 'dart:io';

/// בודק אם תהליך אוצריא רץ כרגע — כדי לא לגעת ב-`seforim.db` בזמן
/// שאוצריא מחזיקה בו handle פתוח (ראו PACKAGE_PLAN.md של
/// seforim_library_updater: ה-orchestrator המקורי בתוך אוצריא סוגר את
/// חיבור ה-SQLite שלו לפני שינוי חיצוני ולוקח אותו בחזרה אחר כך —
/// אנחנו, כתהליך נפרד, לא יכולים לעשות את זה בשבילה, ולכן פשוט חוסמים
/// ומבקשים מהמשתמש לסגור ידנית).
///
/// מומש דרך `tasklist` (פקודת Windows מובנית) ולא FFI — פשוט ומספיק
/// לצורך הזה.
class OtzariaProcessGuard {
  const OtzariaProcessGuard();

  /// [processImageName] הוא שם קובץ ה-exe בלבד (למשל "otzaria.exe"), לא
  /// נתיב מלא — כך ש-`tasklist` יכול להתאים לפי `IMAGENAME` בלי תלות
  /// במיקום ההתקנה.
  Future<bool> isRunning(String processImageName) async {
    final result = await Process.run(
      'tasklist',
      ['/FI', 'IMAGENAME eq $processImageName', '/NH'],
    );

    if (result.exitCode != 0) {
      // אם tasklist עצמו נכשל (נדיר), עדיף להניח "כן רץ" ולחסום, ולא
      // להסתכן בכתיבה בזמן שהתוכנה בכל זאת פתוחה.
      return true;
    }

    final output = result.stdout.toString();
    // כש-tasklist לא מוצא תהליך תואם, הוא מדפיס הודעה כמו "INFO: No tasks
    // are running which match the specified criteria." ולא את השם עצמו.
    return output.toLowerCase().contains(processImageName.toLowerCase());
  }
}

/// נזרק על ידי [LibraryManager] כשמנסים לעדכן DB בזמן שאוצריא רצה.
class OtzariaIsRunningException implements Exception {
  const OtzariaIsRunningException();

  @override
  String toString() =>
      'אוצריא פתוחה כרגע — יש לסגור אותה לפני עדכון המסד, כדי למנוע נעילת '
      'קובץ.';
}
