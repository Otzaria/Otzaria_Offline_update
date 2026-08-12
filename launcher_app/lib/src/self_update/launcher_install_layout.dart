import 'dart:io';

import 'package:path/path.dart' as p;

/// מאתר את **הקובץ שהמשתמש מפעיל בפועל** — זה שצריך להוחלף בעדכון, ולא
/// ה-exe שרץ כרגע.
///
/// בווינדוס ההפצה היא exe בודד (ה-stub) שמחלץ לידו `app-files\` ומריץ משם
/// את `launcher_app.exe`; `Platform.resolvedExecutable` מחזיר את השני, ולכן
/// אי אפשר להסתמך עליו. ב-macOS מה שמוחלף הוא חבילת ה-`.app` כולה.
///
/// [LauncherInstallLayout.dataDirName] אינו מופיע כאן במפורש בכוונה:
/// `OtzariaData/` יושבת **בתוך** `app-files`, וההחלפה נוגעת רק בקובץ ההרצה
/// שלצידה — ראו `LauncherSelfInstaller`.
class LauncherInstallLayout {
  const LauncherInstallLayout({required this.executablePath});

  /// הקובץ (או חבילת ה-`.app`) שהמשתמש מפעיל.
  final String executablePath;

  /// התיקייה שבה הוא יושב — לשם מגיעה הגרסה החדשה, "אותו מיקום בדיוק".
  String get executableDir => p.dirname(executablePath);

  /// שם התיקייה שה-stub מחלץ אליה. **חייב להתאים ל-`kPayloadDir` שב-`stub.c`
  /// ול-`$payloadDirName` שב-`package.ps1`** — `stub_contract_test.dart`
  /// מאמת זאת.
  static const String payloadDirName = 'app-files';

  /// משתנה הסביבה שה-stub מציב לפני שהוא מריץ את הלאנצ'ר, עם הנתיב המלא
  /// שלו עצמו. זו התשובה המדויקת; כל השאר הוא ניחוש.
  static const String stubPathEnvVar = 'OTZARIA_LAUNCHER_STUB';

  /// שם ה-exe כפי ש-`package.ps1` מייצר אותו — משמש **רק** כשוברים תיקו בין
  /// כמה exe באותה תיקייה.
  static const String packagedExeName = 'עדכוני אוצריא.exe';

  /// אותו קובץ, בשם שבו הוא יושב על ה-release. גיטהאב מנקה תווים שאינם ASCII
  /// משמות נכסים, ושם שכולו עברית נמחק אצלו עד `default.exe` (כך אכן פורסמה
  /// v0.1.1) — ולכן ג'וב הפרסום נותן לו שם לטיני, וזה השם שנדבק למי שהוריד
  /// ידנית. שני השמות שוברי תיקו, ולא יותר מזה.
  static const String publishedExeName = 'Otzaria-Updates.exe';

  static const Set<String> _ourExeNames = {packagedExeName, publishedExeName};

  /// הדגל שבו מריצים את ה-stub החדש אחרי החלפה: הוא ממתין שהתהליך הזה
  /// ייסגר לפני שהוא מחלץ מחדש ל-`app-files`.
  static const String afterUpdateFlag = '--after-update';

  /// מאתר את המבנה, או `null` כשאין מה להחליף — הרצה מ-`flutter run`, בנייה
  /// לא ארוזה, או פלטפורמה שאינה נתמכת. `null` אינו שגיאה: הוא פשוט אומר
  /// שהעדכון העצמי אינו זמין בהרצה הזאת.
  static LauncherInstallLayout? resolve({
    String? resolvedExecutable,
    Map<String, String>? environment,
    bool? isWindows,
    bool? isMacOS,
  }) {
    final exe = resolvedExecutable ?? Platform.resolvedExecutable;
    final env = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;
    final macOS = isMacOS ?? Platform.isMacOS;

    if (windows) return _resolveWindows(exe, env);
    if (macOS) return _resolveMacOS(exe);
    return null;
  }

  static LauncherInstallLayout? _resolveWindows(
    String resolvedExecutable,
    Map<String, String> environment,
  ) {
    // מה-stub עצמו: הנתיב המדויק, גם אם המשתמש שינה את שם הקובץ.
    final fromStub = environment[stubPathEnvVar];
    if (fromStub != null &&
        fromStub.isNotEmpty &&
        File(fromStub).existsSync()) {
      return LauncherInstallLayout(executablePath: fromStub);
    }

    // גיבוי ל-stub מגרסה שעוד לא הציבה את המשתנה — בלעדיו העדכון הראשון
    // אחרי הוספת המנגנון לא היה אפשרי בכלל.
    final appFilesDir = p.dirname(resolvedExecutable);
    if (p.basename(appFilesDir).toLowerCase() != payloadDirName) return null;

    final parent = p.dirname(appFilesDir);
    final exes = <String>[];
    try {
      for (final entry in Directory(parent).listSync(followLinks: false)) {
        if (entry is File && p.extension(entry.path).toLowerCase() == '.exe') {
          exes.add(entry.path);
        }
      }
    } on FileSystemException {
      return null;
    }

    if (exes.length == 1) {
      return LauncherInstallLayout(executablePath: exes.single);
    }
    for (final exe in exes) {
      if (_ourExeNames.contains(p.basename(exe))) {
        return LauncherInstallLayout(executablePath: exe);
      }
    }
    // כמה exe ואף אחד מהם אינו שלנו — עדיף לא לגעת בכלום.
    return null;
  }

  /// חבילת ה-`.app` שבתוכה רץ ה-exe. `OtzariaData/` יושבת **לצד** החבילה
  /// (ראו `AppPaths`), ולכן החלפת החבילה כולה אינה נוגעת בה.
  static LauncherInstallLayout? _resolveMacOS(String resolvedExecutable) {
    for (var dir = p.dirname(resolvedExecutable);; dir = p.dirname(dir)) {
      if (p.extension(dir) == '.app') {
        return LauncherInstallLayout(executablePath: dir);
      }
      if (p.dirname(dir) == dir) return null; // הגענו לשורש — לא חבילה
    }
  }
}
