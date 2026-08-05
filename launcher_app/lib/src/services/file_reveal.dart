import 'dart:io';

/// פותח תיקייה במנהל הקבצים של המערכת — Explorer בווינדוס, Finder ב-macOS.
///
/// למה לא `package:url_launcher` עם `file://`: על תיקייה זה מתנהג שונה בין
/// הפלטפורמות (ולפעמים פותח את הקובץ באפליקציה במקום להראות אותו בתיקייה),
/// ואילו כאן רוצים בדיוק דבר אחד — לפתוח חלון על התיקייה כדי שהמשתמש יוכל
/// להעתיק ממנה קבצים ל-USB.
abstract final class FileReveal {
  /// מחזיר true אם הפתיחה הצליחה. **לא זורק** — הקורא מציג במקום זה את
  /// הנתיב כטקסט להעתקה, שזה fallback שימושי יותר מהודעת שגיאה.
  static Future<bool> revealDirectory(String path) async {
    try {
      if (Platform.isWindows) {
        // explorer.exe מחזיר קוד יציאה 1 גם כשהוא הצליח לפתוח את החלון —
        // ולכן אין כאן בדיקת exitCode. (התנהגות מתועדת ומוכרת שלו.)
        await Process.run('explorer.exe', [path]);
        return true;
      }

      if (Platform.isMacOS) {
        final result = await Process.run('/usr/bin/open', [path]);
        return result.exitCode == 0;
      }

      return false;
    } catch (_) {
      return false;
    }
  }
}
