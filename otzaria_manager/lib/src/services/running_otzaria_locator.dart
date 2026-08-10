import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'mac_app_version_reader.dart';

/// מה שנצפה על תהליך אוצריא בבדיקה **אחת**. שני השדות אינם חופפים:
/// תהליך שרץ מוגבה (כמנהל) מזוהה כרץ, אבל הנתיב שלו אינו קריא.
typedef RunningOtzariaProbe = ({bool isRunning, String? launchPath});

/// מאתר את ההתקנה של אוצריא לפי **התהליך שרץ כרגע**, ולא לפי ניחוש
/// תיקיות: הנתיב של תהליך חי הוא בדיוק העותק שהמשתמש מפעיל בפועל, גם אם
/// הותקן במקום שאינו ברשימת ברירות המחדל של
/// [OtzariaManager] (`_autoDetectDirs`).
///
/// עובד כמובן רק כשאוצריא פתוחה — אבל זה בדיוק הרגע שבו הלאנצ'ר כבר
/// מציג "אוצריא פתוחה, יש לסגור אותה" (`OtzariaProcessGuard` ב-
/// `library_manager` מזהה את אותו תהליך, בשמו בלבד), והתוצאה נשמרת
/// ב-state ולכן נשארת גם אחרי שהיא נסגרת.
///
/// **מה זה לא פותר:** מיקום ה-`seforim.db`. הוא יושב תחת `%APPDATA%`
/// ללא קשר לתיקיית ההתקנה, ולגזור אותו מהתהליך היה מחייב סריקת
/// ה-handles הפתוחים שלו — ראו `LibraryDbLocator`.
class RunningOtzariaLocator {
  const RunningOtzariaLocator();

  /// גודל החוצץ ל-`QueryFullProcessImageNameW`. `MAX_PATH` (260) אינו
  /// מספיק — נתיב ארוך אפשרי, ואז הקריאה הייתה נכשלת דווקא במקרה הלא-שגרתי
  /// שבגללו כל המנגנון הזה קיים.
  static const int _maxPathChars = 32768;

  /// שמות התהליך של אוצריא. **חייב להישאר תואם ל-
  /// `OtzariaProcessGuard.processNamesFor`** ב-`library_manager` — אותו
  /// זיהוי בדיוק, בשתי חבילות: שם חוסמים עדכון DB, כאן שולפים נתיב.
  /// יש בדיקה ב-`launcher_app` שמאמתת שהרשימות זהות.
  static List<String> processNamesFor(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => const ['otzaria.exe'],
      'macos' => const ['אוצריא', 'otzaria'],
      _ => const ['otzaria'],
    };
  }

  /// נתיב ההפעלה של אוצריא הרצה כרגע — קובץ ה-`.exe` בווינדוס, חבילת
  /// ה-`.app` ב-macOS — או null.
  ///
  /// null אינו שגיאה: אוצריא אינה רצה, אין הרשאה לקרוא את נתיב התהליך
  /// (היא רצה כמנהל והלאנצ'ר לא), או שהתהליך אינו יושב בתוך `.app`
  /// ב-macOS. הקורא פשוט ממשיך לזיהוי לפי תיקיות ברירת המחדל.
  Future<String?> findLaunchPath() async => (await probe()).launchPath;

  /// בדיקה אחת שמחזירה גם "רצה?" וגם את הנתיב. הקורא צריך את שניהם —
  /// הממשק מציג "אוצריא פתוחה" והזיהוי צריך את הנתיב — וקודם זה עלה שתי
  /// הרצות נפרדות של `tasklist`, שהן הפעולה היקרה ביותר בעליית הלאנצ'ר.
  ///
  /// כשל בבדיקה עצמה מדווח כ"רצה", בדיוק כמו `OtzariaProcessGuard`: עדיף
  /// לחסום שינוי מסד לשווא מלכתוב לקובץ שאוצריא מחזיקה פתוח.
  Future<RunningOtzariaProbe> probe() async {
    try {
      if (Platform.isWindows) return await _probeWindows();
      if (Platform.isMacOS) return await _probeMac();
    } on ProcessException {
      // הכלי עצמו חסר/חסום. כמו כשל בהרצתו: מדווחים "רצה" ולא מפילים —
      // הבדיקה הזו רצה במקביל לאחרות, וחריג ממנה היה בורח כשגיאה לא-נתפסת.
      return (isRunning: true, launchPath: null);
    }
    return (isRunning: false, launchPath: null);
  }

  Future<RunningOtzariaProbe> _probeWindows() async {
    var isRunning = false;
    for (final name in processNamesFor('windows')) {
      final pids = await _windowsPidsOrNull(name);
      if (pids == null) return (isRunning: true, launchPath: null);
      if (pids.isNotEmpty) isRunning = true;

      for (final processId in pids) {
        final path = windowsImagePathOfPid(processId);
        if (path == null) continue;
        // הלאנצ'ר עצמו לעולם לא ייקרא otzaria.exe, אבל ביטוח זול.
        if (_isSelf(path)) continue;
        return (isRunning: true, launchPath: path);
      }
    }
    return (isRunning: isRunning, launchPath: null);
  }

  Future<RunningOtzariaProbe> _probeMac() async {
    final result = await Process.run('/bin/ps', ['-A', '-o', 'comm=']);
    if (result.exitCode != 0) return (isRunning: true, launchPath: null);

    final executablePath = selectMacExecutablePath(
      const LineSplitter().convert(result.stdout.toString()),
      processNamesFor('macos'),
    );
    if (executablePath == null) return (isRunning: false, launchPath: null);

    // `ps` מחזיר את הבינארי שבתוך החבילה; כל השאר בקוד עובד מול ה-.app.
    return (
      isRunning: true,
      launchPath: MacAppVersionReader.bundleRootOf(executablePath),
    );
  }

  bool _isSelf(String path) => p.equals(path, Platform.resolvedExecutable);

  /// ה-PIDים של תהליך בשם [imageName], דרך `tasklist` בפורמט CSV (הפורמט
  /// היחיד שאפשר לפרסר ממנו בביטחון — הפורמט הטבלאי מיישר בעמודות).
  static Future<List<int>> windowsPidsOf(String imageName) async =>
      await _windowsPidsOrNull(imageName) ?? const [];

  /// כמו [windowsPidsOf], אך `null` = `tasklist` עצמו נכשל, להבדיל מרשימה
  /// ריקה שפירושה "נבדק, ואינו רץ". ההבחנה נחוצה ל-[probe] fail-safe.
  static Future<List<int>?> _windowsPidsOrNull(String imageName) async {
    final result = await Process.run(
      'tasklist',
      ['/FI', 'IMAGENAME eq $imageName', '/NH', '/FO', 'CSV'],
    );
    if (result.exitCode != 0) return null;
    return parseTasklistPids(result.stdout.toString());
  }

  /// שורת CSV של tasklist: `"otzaria.exe","1234","Console","1","309,328 K"` —
  /// ה-PID בעמודה השנייה. כשאין תהליך תואם מודפסת שורת INFO חופשית, שפשוט
  /// אינה מתפרשת ומחזירה רשימה ריקה.
  static List<int> parseTasklistPids(String stdout) {
    final pids = <int>[];
    for (final line in const LineSplitter().convert(stdout)) {
      final fields = line.split(',');
      if (fields.length < 2) continue;
      final pid = int.tryParse(fields[1].replaceAll('"', '').trim());
      if (pid != null) pids.add(pid);
    }
    return pids;
  }

  /// הנתיב המלא של תהליך לפי [processId], דרך Win32 (`OpenProcess` +
  /// `QueryFullProcessImageNameW`, package:win32 — כמו ב-
  /// [WindowsExeVersionReader]).
  ///
  /// null כשהפתיחה נכשלה: `PROCESS_QUERY_LIMITED_INFORMATION` מספיק
  /// לתהליך של אותו משתמש, אך לא לתהליך מוגבה כשאנחנו לא.
  static String? windowsImagePathOfPid(int processId) {
    if (!Platform.isWindows) return null;

    final handle = OpenProcess(
      PROCESS_QUERY_LIMITED_INFORMATION,
      FALSE,
      processId,
    );
    if (handle == 0) return null;

    final buffer = calloc<Uint16>(_maxPathChars).cast<Utf16>();
    final sizePtr = calloc<Uint32>()..value = _maxPathChars;
    try {
      if (QueryFullProcessImageName(handle, 0, buffer, sizePtr) == 0) {
        return null;
      }
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
      calloc.free(sizePtr);
      CloseHandle(handle);
    }
  }

  /// בוחר מתוך פלט `ps -A -o comm=` (שב-macOS מדפיס **נתיב מלא**) את
  /// התהליך של אוצריא.
  ///
  /// ההתאמה היא על שם הקובץ **במלואו**, כמו `pgrep -x` — ולא כתת-מחרוזת,
  /// שהייתה תופסת גם את הלאנצ'ר עצמו: הנתיב שלו מכיל את המילה otzaria.
  static String? selectMacExecutablePath(
    Iterable<String> psLines,
    List<String> processNames,
  ) {
    for (final line in psLines) {
      final path = line.trim();
      if (path.isEmpty) continue;
      if (!processNames.contains(p.basename(path))) continue;
      return path;
    }
    return null;
  }
}
