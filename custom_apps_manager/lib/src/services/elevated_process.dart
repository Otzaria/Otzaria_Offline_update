import 'dart:io';

/// הרצה עם הרשאות מנהל, כשווינדוס מסרבת להריץ בלעדיהן.
///
/// `Process.run` עובר דרך `CreateProcess`, שאינו יודע להקפיץ UAC: קובץ
/// שהמניפסט שלו `requireAdministrator` (נפוץ ב-NSIS) נופל בשגיאה 740.
class ElevatedProcess {
  const ElevatedProcess._();

  /// `ERROR_ELEVATION_REQUIRED` — הקובץ דורש מנהל ולא הורץ בכלל.
  static const elevationRequiredCode = 740;

  /// `ERROR_CANCELLED` — המשתמש לחץ "לא" בחלון ה-UAC.
  static const cancelledCode = 1223;

  static bool isElevationRequired(Object error) =>
      error is ProcessException && error.errorCode == elevationRequiredCode;

  /// מריץ דרך ShellExecute וממתין לסיום. קוד היציאה הוא של התהליך עצמו, או
  /// [cancelledCode] כשה-UAC נדחה.
  ///
  /// בלי [elevate] אין `runas`, אבל ShellExecute עדיין מקפיץ UAC כשהמניפסט
  /// דורש — מה שמאפשר [rawLastArgument] גם למתקין שאינו דורש מנהל.
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool elevate = true,
    bool rawLastArgument = false,
  }) =>
      Process.run(
        'powershell',
        powershellArgs(
          executable,
          arguments,
          elevate: elevate,
          rawLastArgument: rawLastArgument,
        ),
      );

  /// כמו [run], אבל חוזר מיד כשהתהליך עלה — להפעלת תוכנה, לא להתקנה.
  static Future<ProcessResult> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) =>
      Process.run(
        'powershell',
        powershellArgs(
          executable,
          arguments,
          wait: false,
          workingDirectory: workingDirectory,
        ),
      );

  /// חשוף לבדיקות. `Process.Start` ולא `Start-Process`: ב-PowerShell 5.1
  /// השני בולע את ה-Win32Exception, וסירוב ל-UAC היה יוצא "1" ולא 1223.
  static List<String> powershellArgs(
    String executable,
    List<String> arguments, {
    bool wait = true,
    bool elevate = true,
    bool rawLastArgument = false,
    String? workingDirectory,
  }) {
    final commandLine =
        buildCommandLine(arguments, rawLastArgument: rawLastArgument);
    final script = [
      r"$ErrorActionPreference = 'Stop'",
      'try {',
      r'  $i = New-Object Diagnostics.ProcessStartInfo',
      '  \$i.FileName = ${_psQuote(executable)}',
      '  \$i.Arguments = ${_psQuote(commandLine)}',
      if (workingDirectory != null)
        '  \$i.WorkingDirectory = ${_psQuote(workingDirectory)}',
      if (elevate) r"  $i.Verb = 'runas'",
      r'  $i.UseShellExecute = $true',
      r'  $p = [Diagnostics.Process]::Start($i)',
      wait ? r'  $p.WaitForExit(); exit $p.ExitCode' : '  exit 0',
      '} catch {',
      r'  $e = $_.Exception',
      r'  while ($e) {',
      r'    if ($e -is [ComponentModel.Win32Exception]) { exit $e.NativeErrorCode }',
      r'    $e = $e.InnerException',
      '  }',
      r'  [Console]::Error.WriteLine($_); exit 1',
      '}',
    ].join('\n');
    return [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      script,
    ];
  }

  /// שורת הפקודה בכללי הציטוט של Dart; עם [rawLastArgument] האחרון נשאר
  /// גולמי — `/D=` של NSIS עם מרכאות נבלע כחלק מהנתיב.
  static String buildCommandLine(
    List<String> arguments, {
    bool rawLastArgument = false,
  }) =>
      [
        for (var i = 0; i < arguments.length; i++)
          rawLastArgument && i == arguments.length - 1
              ? arguments[i]
              : quoteWindowsArg(arguments[i]),
      ].join(' ');

  /// האם [quoteWindowsArg] היה עוטף את [arg] במרכאות.
  static bool needsQuoting(String arg) =>
      arg.isEmpty || arg.contains(RegExp(r'[ \t"]'));

  /// אותם כללי ציטוט ש-Dart מפעיל בעצמו ב-`Process.run`, כדי שהמתקין יקבל
  /// שורת פקודה זהה בשני המסלולים.
  static String quoteWindowsArg(String arg) {
    if (!needsQuoting(arg)) return arg;
    final out = StringBuffer('"');
    var backslashes = 0;
    for (final ch in arg.split('')) {
      if (ch == r'\') {
        backslashes++;
        continue;
      }
      if (ch == '"') {
        out.write(r'\' * (backslashes * 2 + 1));
      } else {
        out.write(r'\' * backslashes);
      }
      backslashes = 0;
      out.write(ch);
    }
    out
      ..write(r'\' * (backslashes * 2))
      ..write('"');
    return out.toString();
  }

  static String _psQuote(String s) => "'${s.replaceAll("'", "''")}'";
}
