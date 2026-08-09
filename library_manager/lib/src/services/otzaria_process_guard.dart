import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';

/// בודק אם תהליך אוצריא רץ כרגע — כדי לא לגעת ב-`seforim.db` בזמן
/// שאוצריא מחזיקה בו handle פתוח (ראו PACKAGE_PLAN.md של
/// seforim_library_updater: ה-orchestrator המקורי בתוך אוצריא סוגר את
/// חיבור ה-SQLite שלו לפני שינוי חיצוני ולוקח אותו בחזרה אחר כך —
/// אנחנו, כתהליך נפרד, לא יכולים לעשות את זה בשבילה, ולכן פשוט חוסמים
/// ומבקשים מהמשתמש לסגור ידנית).
///
/// מומש דרך כלי מערכת (`tasklist` בווינדוס, `pgrep` ב-macOS/לינוקס) ולא
/// FFI — פשוט ומספיק לצורך הזה.
class OtzariaProcessGuard {
  const OtzariaProcessGuard();

  /// שמות התהליך של אוצריא בכל פלטפורמה.
  ///
  /// ב-macOS שם התהליך הוא ה-`CFBundleExecutable` של החבילה, שהוא **בעברית**
  /// (`אוצריא`) — אומת מול `otzaria-macos.zip` אמיתי. `pgrep` מתמודד עם
  /// UTF-8 בשם התהליך (נבדק). `otzaria` נשאר ברשימה כגיבוי, למקרה שהשם
  /// באנגלית בבנייה מסוימת.
  static List<String> processNamesFor(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => const ['otzaria.exe'],
      'macos' => const ['אוצריא', 'otzaria'],
      _ => const ['otzaria'],
    };
  }

  /// האם רץ תהליך שתואם לאחד מ-[processNames].
  ///
  /// [processNames] הם שמות תהליך בלבד (למשל "otzaria.exe" או "אוצריא"), לא
  /// נתיבים מלאים — כך שההתאמה אינה תלויה במיקום ההתקנה.
  Future<bool> isAnyRunning(List<String> processNames) async {
    for (final name in processNames) {
      if (await isRunning(name)) return true;
    }
    return false;
  }

  Future<bool> isRunning(String processName) async {
    if (Platform.isWindows) {
      return _isRunningWindows(processName);
    }
    if (Platform.isMacOS || Platform.isLinux) {
      return _isRunningPosix(processName);
    }
    // פלטפורמה שאין לנו בה דרך לבדוק — אין מה לחסום.
    return false;
  }

  Future<bool> _isRunningWindows(String processImageName) async {
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

  /// `pgrep -x` מתאים את **שם התהליך במלואו**, לא תת-מחרוזת — חשוב, כי
  /// התאמה חלקית (`pgrep` בלי `-x`, או `-f` על שורת הפקודה המלאה) הייתה
  /// נתפסת גם על הלאנצ'ר עצמו: הנתיב שלו מכיל את המילה otzaria, והיינו
  /// חוסמים את העדכון בגלל התהליך שמריץ אותו.
  ///
  /// קודי היציאה של pgrep: 0 = נמצא, 1 = לא נמצא, ≥2 = שגיאה אמיתית.
  Future<bool> _isRunningPosix(String processName) async {
    final result = await Process.run('/usr/bin/pgrep', ['-x', processName]);

    return switch (result.exitCode) {
      0 => true,
      1 => false,
      // כמו בווינדוס: אם הבדיקה עצמה נכשלה, חוסמים ליתר ביטחון.
      _ => true,
    };
  }
}

/// נזרק על ידי [LibraryManager] כשמנסים לעדכן DB בזמן שאוצריא רצה.
class OtzariaIsRunningException implements Exception {
  const OtzariaIsRunningException();

  @override
  String toString() => AppL10n.strings.libraryDomain.otzariaIsRunning;
}
