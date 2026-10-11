import 'dart:async';
import 'dart:io';

typedef ElevationQuery = Future<ProcessResult> Function();

class ElevatedProcess {
  const ElevatedProcess._();

  static const elevationRequiredCode = 740;

  static const cancelledCode = 1223;

  static const elevationQueryTimeout = Duration(seconds: 10);

  static const elevationQueryArgs = [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '([Security.Principal.WindowsPrincipal]'
        '[Security.Principal.WindowsIdentity]::GetCurrent())'
        '.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
  ];

  static bool isElevationRequired(Object error) =>
      error is ProcessException && error.errorCode == elevationRequiredCode;

  static bool? _currentElevated;
  static Future<bool>? _pendingElevated;

  static Future<bool> isCurrentProcessElevated() {
    if (!Platform.isWindows) return Future.value(false);
    return resolveElevated(_runElevationQuery);
  }

  static Future<bool> resolveElevated(
    ElevationQuery query, {
    Duration timeout = elevationQueryTimeout,
  }) {
    final cached = _currentElevated;
    if (cached != null) return Future.value(cached);
    return _pendingElevated ??= _queryElevated(query, timeout)
        .whenComplete(() => _pendingElevated = null);
  }

  static void resetElevatedCache() {
    _currentElevated = null;
    _pendingElevated = null;
  }

  static bool parseElevatedResult(int exitCode, Object? stdout) =>
      exitCode == 0 && '$stdout'.trim().toLowerCase() == 'true';

  static Future<bool> _queryElevated(
    ElevationQuery query,
    Duration timeout,
  ) async {
    try {
      final result = await query().timeout(timeout);
      return _currentElevated =
          parseElevatedResult(result.exitCode, result.stdout);
    } on TimeoutException {
      return false;
    } catch (_) {
      return _currentElevated = false;
    }
  }

  static Future<ProcessResult> _runElevationQuery() async {
    final process = await Process.start('powershell', elevationQueryArgs);
    final stdout = process.stdout.transform(systemEncoding.decoder).join();
    unawaited(process.stderr.drain<void>());
    try {
      final exitCode = await process.exitCode.timeout(elevationQueryTimeout);
      return ProcessResult(process.pid, exitCode, await stdout, '');
    } on TimeoutException {
      process.kill();
      rethrow;
    }
  }

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

  static bool needsQuoting(String arg) =>
      arg.isEmpty || arg.contains(RegExp(r'[ \t"]'));

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

  static String _psQuote(String s) =>
      "'${s.replaceAllMapped(RegExp("['\u2018-\u201B]"), (m) => m[0]! * 2)}'";
}
