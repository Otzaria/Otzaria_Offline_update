import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/otzaria_install_state.dart';
import '../models/otzaria_release.dart';

/// מוריד את ה-installer של אוצריא (Inno Setup, נבדק ידנית מול גרסה
/// אמיתית מה-releases) ומתקין אותו בשקט לתוך תיקייה מנוהלת קבועה, כדי
/// שנדע תמיד בוודאות איפה התוכנה יושבת.
///
/// חשוב: מבוסס על הנחה מאומתת (strings על installer אמיתי) ש-Inno Setup
/// הוא ה-framework, ולכן דגלי השקט (/VERYSILENT וכו') ונתיב ההתקנה
/// (/DIR=) הם דגלי Inno Setup הסטנדרטיים. אם המפתח (Sivan22) יחליף
/// framework בעתיד, הדגלים האלה יפסיקו לעבוד ויהיה צריך לעדכן.
class OtzariaInstaller {
  OtzariaInstaller({
    required this.managedInstallDir,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// התיקייה הקבועה שבה אנחנו מנהלים את התקנת אוצריא (למשל
  /// `<data>/otzaria-app`). תמיד אותה תיקייה, כדי שגילוי ה-exe אחרי
  /// עדכון יהיה פשוט וצפוי.
  final String managedInstallDir;

  final http.Client _httpClient;

  /// מוריד ומתקין release נתון. מחזיר את מצב ההתקנה החדש (לשמירה על ידי
  /// הקורא, דרך [OtzariaStateStore]).
  ///
  /// [onDownloadProgress] מדווח (received, total) בזמן ההורדה.
  Future<OtzariaInstallState> downloadAndInstall({
    required OtzariaRelease release,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('otzaria-installer-');
    final installerPath = p.join(tempDir.path, release.windowsInstallerAssetName);

    try {
      await _download(
        url: release.windowsInstallerDownloadUrl,
        destinationPath: installerPath,
        expectedSizeBytes: release.windowsInstallerSizeBytes,
        onProgress: onDownloadProgress,
      );

      await Directory(managedInstallDir).create(recursive: true);
      await _runSilentInstall(installerPath);

      final exePath = await _waitForInstalledExe(
        timeout: const Duration(minutes: 3),
      );

      return OtzariaInstallState(
        installedTagName: release.tagName,
        installDir: managedInstallDir,
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

  Future<void> _runSilentInstall(String installerPath) async {
    // /VERYSILENT + /SUPPRESSMSGBOXES: אין UI בכלל, כולל תיבות שגיאה.
    // /NORESTART: לא להפעיל מחדש את המחשב גם אם ה-installer "רוצה".
    // /DIR=: נתיב התקנה קבוע, כדי שנדע איפה לחפש את ה-exe אחר כך.
    final args = [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/DIR=$managedInstallDir',
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

  Future<String> _waitForInstalledExe({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final found = await _findInstalledExe();
      if (found != null) return found;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw StateError(
      'לא נמצא קובץ הפעלה (.exe) בתוך $managedInstallDir תוך '
      '${timeout.inSeconds} שניות מסיום ה-installer. ייתכן שההתקנה עדיין '
      'רצה ברקע, או שנתיב ההתקנה השתנה בגרסה חדשה של ה-installer.',
    );
  }

  /// סורק את תיקיית ההתקנה המנוהלת ומחפש את קובץ ה-exe הראשי. לא מניחים
  /// שם קבוע (otzaria.exe) כדי להישאר עמידים אם זה ישתנה — פוסלים רק את
  /// uninstall-*.exe/unins*.exe שה-installer עצמו יוצר.
  Future<String?> _findInstalledExe() async {
    final dir = Directory(managedInstallDir);
    if (!await dir.exists()) return null;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.exe')) continue;
      if (name.startsWith('unins')) continue;
      return entity.path;
    }
    return null;
  }

  void close() => _httpClient.close();
}
