import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/otzaria_install_state.dart';
import '../models/otzaria_release.dart';
import 'otzaria_exe_locator.dart';

/// מוריד את ה-installer של אוצריא (Inno Setup, נבדק ידנית מול גרסה
/// אמיתית מה-releases) ומתקין אותו בשקט לתוך תיקייה נתונה.
///
/// חשוב: מבוסס על הנחה מאומתת (strings + innoextract על installer אמיתי)
/// ש-Inno Setup הוא ה-framework, ולכן דגלי השקט (/VERYSILENT וכו') ונתיב
/// ההתקנה (/DIR=) הם דגלי Inno Setup הסטנדרטיים. אם המפתח (Sivan22)
/// יחליף framework בעתיד, הדגלים האלה יפסיקו לעבוד ויהיה צריך לעדכן.
class OtzariaInstaller {
  OtzariaInstaller({
    required this.defaultInstallDir,
    http.Client? httpClient,
    OtzariaExeLocator? exeLocator,
  })  : _httpClient = httpClient ?? http.Client(),
        _exeLocator = exeLocator ?? const OtzariaExeLocator();

  /// התיקייה שאליה מתקינים כשלא נבחרה תיקייה אחרת במפורש (למשל
  /// `<data>/otzaria-app`) — ה"מיקום ברירת המחדל" של הלאנצ'ר עצמו.
  final String defaultInstallDir;

  final http.Client _httpClient;
  final OtzariaExeLocator _exeLocator;

  /// מוריד ומתקין release נתון. מחזיר את מצב ההתקנה החדש (לשמירה על ידי
  /// הקורא, דרך [OtzariaStateStore]).
  ///
  /// [targetInstallDir] מאפשר להתקין לתיקייה שאינה [defaultInstallDir] —
  /// למשל כשהמשתמש כבר הצביע בעבר על תיקיית התקנה קיימת משלו
  /// ([OtzariaManager.adoptExistingInstall]), ורוצים לעדכן אותה במקום,
  /// לא ליצור התקנה שנייה בתיקייה המנוהלת.
  ///
  /// [onDownloadProgress] מדווח (received, total) בזמן ההורדה.
  Future<OtzariaInstallState> downloadAndInstall({
    required OtzariaRelease release,
    String? targetInstallDir,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final installDir = targetInstallDir ?? defaultInstallDir;
    final tempDir = await Directory.systemTemp.createTemp('otzaria-installer-');
    final installerPath = p.join(tempDir.path, release.windowsInstallerAssetName);

    try {
      await _download(
        url: release.windowsInstallerDownloadUrl,
        destinationPath: installerPath,
        expectedSizeBytes: release.windowsInstallerSizeBytes,
        onProgress: onDownloadProgress,
      );

      await Directory(installDir).create(recursive: true);
      await _runSilentInstall(installerPath, installDir);

      final exePath = await _waitForInstalledExe(
        installDir: installDir,
        timeout: const Duration(minutes: 3),
      );

      return OtzariaInstallState(
        installedTagName: release.tagName,
        installDir: installDir,
        exePath: exePath,
      );
    } finally {
      // מנקים את ה-installer הזמני בכל מקרה (הצלחה או כישלון) — לא
      // צריך אותו יותר אחרי שהריצה הסתיימה.
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _download({
    required String url,
    required String destinationPath,
    required int expectedSizeBytes,
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);

    if (response.statusCode != 200) {
      throw StateError('הורדת ה-installer נכשלה: סטטוס ${response.statusCode}');
    }

    final sink = File(destinationPath).openWrite();
    var received = 0;
    try {
      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, expectedSizeBytes);
      }).asFuture<void>();
    } finally {
      await sink.close();
    }

    if (expectedSizeBytes > 0 && received != expectedSizeBytes) {
      throw StateError(
        'קובץ ה-installer שהורד לא בגודל הצפוי '
        '(התקבלו $received בתים, צפוי $expectedSizeBytes) — כנראה שהורדה '
        'נקטעה.',
      );
    }
  }

  Future<void> _runSilentInstall(String installerPath, String installDir) async {
    // /VERYSILENT + /SUPPRESSMSGBOXES: אין UI בכלל, כולל תיבות שגיאה.
    // /NORESTART: לא להפעיל מחדש את המחשב גם אם ה-installer "רוצה".
    // /DIR=: נתיב התקנה מפורש, כדי שנדע איפה לחפש את ה-exe אחר כך.
    final args = [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/DIR=$installDir',
    ];

    final result = await Process.run(installerPath, args);
    if (result.exitCode != 0) {
      throw StateError(
        'ריצת ה-installer החזירה קוד יציאה ${result.exitCode}.\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }

    // הערה: ל-installer-ים מבוססי Inno Setup יש לפעמים תהליך "עוטף"
    // (SetupLdr) שמשגר תהליך-בן ומסתיים מיד, עוד לפני שההתקנה בפועל
    // הסתיימה — ולכן exitCode==0 כאן לא מבטיח שהקבצים כבר על הדיסק.
    // בגלל זה יש polling נפרד ב-_waitForInstalledExe במקום להסתמך רק על
    // סיום התהליך.
  }

  Future<String> _waitForInstalledExe({
    required String installDir,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final found = await _exeLocator.findExeIn(installDir);
      if (found != null) return found;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw StateError(
      'לא נמצא קובץ הפעלה (.exe) בתוך $installDir תוך '
      '${timeout.inSeconds} שניות מסיום ה-installer. ייתכן שההתקנה עדיין '
      'רצה ברקע, או שנתיב ההתקנה השתנה בגרסה חדשה של ה-installer.',
    );
  }

  void close() => _httpClient.close();
}
