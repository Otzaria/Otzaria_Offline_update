import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart' show ElevatedProcess;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../app_report/launcher_crash_session.dart';

/// "אין הרשאה" במה שהכלי כותב בעצמו (ספרייה, נלווים, תוספים), וההפעלה
/// מחדש כמנהל. ב-macOS אין הרמה — שם [describe] מציע מיקום אחר.
class Elevation {
  const Elevation._();

  /// הזיהוי העיקרי הוא קוד השגיאה של מערכת ההפעלה, ולא טקסט: ההודעה עצמה
  /// מתורגמת לשפת ווינדוס, ובעברית "הגישה נדחתה" לא היה נתפס.
  static bool isAccessDenied(Object error, {bool? isWindows}) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code != null) {
        // 5 = ERROR_ACCESS_DENIED, 13 = EACCES ו-1 = EPERM. אינם אותו מספר,
        // ולכן לפי הפלטפורמה: 13 בווינדוס הוא ERROR_INVALID_DATA, שגיאה
        // אחרת לגמרי. EPERM הוא מה ש-macOS מחזיר על כתיבה לתיקייה מוגנת
        // ב-SIP או על נכס שהבעלות עליו אינה של המשתמש.
        return (isWindows ?? Platform.isWindows)
            ? code == 5
            : code == 13 || code == 1;
      }
    }
    // מסד בתיקייה מוגנת נכשל ב-sqlite ולא ב-dart:io, ואין שם OSError.
    // הטקסט הוא של sqlite עצמו — באנגלית בכל מערכת, ולכן בטוח להשוואה.
    return error.toString().contains('readonly database');
  }

  /// מוסיף להודעת השגיאה את מה שאפשר לעשות — ורק כשזו שגיאת הרשאות.
  /// בכל מקרה אחר ההודעה נשארת בדיוק כשהייתה.
  ///
  /// העצה עצמה שונה בין הפלטפורמות: בווינדוס יש "הפעל כמנהל", וב-macOS אין
  /// דבר כזה — ולכן הנוסח שם מצביע על מיקום שאפשר לכתוב אליו. הצגת ההוראה
  /// של ווינדוס למשתמש מק היא עצה שאי אפשר לבצע.
  static String describe(Object error, {bool? isMacOS, bool? isWindows}) {
    final macOS = isMacOS ?? Platform.isMacOS;
    // שתי הפלטפורמות היחידות שהלאנצ'ר נבנה להן, ולכן הזרקת האחת קובעת גם
    // את השנייה — כך בדיקה מאמתת את שני המסלולים מאותה מכונה. בלי הזרקה
    // בכלל נשארת הפלטפורמה שרצה בפועל (הבדיקות רצות גם בלינוקס).
    final windows =
        isWindows ?? (isMacOS == null ? Platform.isWindows : !macOS);
    if (!isAccessDenied(error, isWindows: windows)) return error.toString();
    final t = AppL10n.strings.elevation;
    return '$error\n\n${macOS ? t.macHint : t.hint}';
  }

  /// מה ש-[restartElevated] מחזיר כשחלון ה-UAC נסגר בלי אישור (או שהגישה
  /// נחסמה): בחירה של המשתמש ולא תקלה, ולכן בלי הודעת שגיאה.
  static const Object cancelled = _ElevationCancelled();

  static Future<Object?> restartElevated({
    Future<int> Function(String executable, List<String> arguments)? run,
    void Function()? quit,
  }) async {
    if (!Platform.isWindows) return 'unsupported: ${Platform.operatingSystem}';
    final exe = Platform.resolvedExecutable;
    final int exitCode;
    try {
      exitCode = await (run ?? _defaultRun)(exe, const []);
    } catch (e) {
      return e;
    }
    if (exitCode == ElevatedProcess.cancelledCode) return cancelled;
    if (exitCode != 0) return 'exit code $exitCode';
    (quit ?? _defaultQuit)();
    return null;
  }

  static Future<int> _defaultRun(
    String executable,
    List<String> arguments,
  ) async {
    final result = await ElevatedProcess.start(
      executable,
      arguments,
      workingDirectory: p.dirname(executable),
    );
    return result.exitCode;
  }

  static void _defaultQuit() => LauncherCrashSession.exitCleanly();
}

class _ElevationCancelled {
  const _ElevationCancelled();

  @override
  String toString() => 'cancelled';
}
