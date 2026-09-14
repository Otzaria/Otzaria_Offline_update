import 'dart:io';

import 'running_otzaria_locator.dart';

/// מבקש מאוצריא הרצה להיסגר, כדי שהמשתמש לא יצטרך לעבור לחלון שלה ולסגור
/// ידנית: הלאנצ'ר חוסם עדכון מסד והתקנה כל עוד היא פתוחה, וזה הרגע היחיד
/// שבו האזהרה מוצגת.
///
/// **בקשה, לא הריגה.** בווינדוס `taskkill` בלי `/F` שולח `WM_CLOSE` לחלונות
/// התהליך, ב-macOS `osascript ... to quit` הוא בקשת ה-Quit הרגילה ובלינוקס
/// `pkill` שולח `SIGTERM` — בכל המסלולים אוצריא מספיקה לשמור את מצבה ולסגור
/// את חיבור ה-SQLite שלה. סגירה כפויה הייתה משאירה מסד באמצע כתיבה, בדיוק
/// הנזק שכל החסימה הזו קיימת כדי למנוע.
class OtzariaProcessCloser {
  const OtzariaProcessCloser({
    RunningOtzariaLocator locator = const RunningOtzariaLocator(),
    // תפר לבדיקות: בלעדיו בדיקה של ההמתנה הייתה מבקשת סגירה אמיתית מהמחשב
    // שמריץ אותה — כלומר סוגרת את אוצריא של מי שמריץ את הבדיקות.
    Future<void> Function(String? launchPath)? sendCloseRequest,
  })  : _locator = locator,
        _sendCloseRequest = sendCloseRequest;

  final RunningOtzariaLocator _locator;
  final Future<void> Function(String? launchPath)? _sendCloseRequest;

  /// כל כמה זמן נבדק מחדש אם התהליך נעלם. אוצריא נסגרת תוך שבריר שנייה
  /// ברוב המקרים, ולכן הבדיקה תכופה — `tasklist` אחד כל 400ms.
  static const Duration _pollInterval = Duration(milliseconds: 400);

  /// מבקש סגירה וממתין עד [timeout]. `true` = אוצריא אינה רצה יותר (כולל
  /// המקרה שבו כבר לא רצה מלכתחילה); `false` = הבקשה נשלחה אך התהליך שרד,
  /// והקורא מבקש מהמשתמש לסגור ידנית.
  Future<bool> close({Duration timeout = const Duration(seconds: 8)}) async {
    final probe = await _locator.probe();
    if (!probe.isRunning) return true;

    try {
      await (_sendCloseRequest ?? _requestClose)(probe.launchPath);
    } on ProcessException {
      // הכלי עצמו חסר/חסום — אין מה להמתין לו.
      return false;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollInterval);
      if (!(await _locator.probe()).isRunning) return true;
    }
    return false;
  }

  Future<void> _requestClose(String? launchPath) async {
    if (Platform.isWindows) return _requestCloseWindows();
    if (Platform.isMacOS) return _requestCloseMac(launchPath);
    await _pkill(RunningOtzariaLocator.processNamesFor('linux'));
  }

  Future<void> _requestCloseWindows() async {
    for (final name in RunningOtzariaLocator.processNamesFor('windows')) {
      for (final pid in await RunningOtzariaLocator.windowsPidsOf(name)) {
        // לפי PID ולא לפי שם: `/IM` היה תופס גם מופע נוסף שאינו זה שזוהה,
        // והנתיב שכבר נבדק הוא מה שמפריד את אוצריא מהלאנצ'ר עצמו.
        await Process.run('taskkill', ['/PID', '$pid']);
      }
    }
  }

  /// `tell application <path> to quit` — הבקשה שעוברת דרך Launch Services,
  /// כמו בחירה ב-Quit מהתפריט. נתיב החבילה ולא שם התוכנה: השם ב-macOS הוא
  /// בעברית, ותלות בו הייתה נשברת בבנייה שבה הוא באנגלית.
  Future<void> _requestCloseMac(String? launchPath) async {
    if (launchPath != null) {
      final result = await Process.run(
        '/usr/bin/osascript',
        ['-e', 'tell application "$launchPath" to quit'],
      );
      if (result.exitCode == 0) return;
    }
    await _pkill(RunningOtzariaLocator.processNamesFor('macos'));
  }

  /// `-x` מתאים את שם התהליך במלואו — בלעדיו היינו תופסים גם את הלאנצ'ר
  /// עצמו, שהנתיב שלו מכיל את המילה otzaria (ראו `OtzariaProcessGuard`).
  Future<void> _pkill(List<String> processNames) async {
    for (final name in processNames) {
      await Process.run('/usr/bin/pkill', ['-x', name]);
    }
  }
}
