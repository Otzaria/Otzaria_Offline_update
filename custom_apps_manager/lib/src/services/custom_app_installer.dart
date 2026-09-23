import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';
import '../models/custom_install_outcome.dart';
import '../models/custom_installer_kind.dart';
import 'elevated_process.dart';
import 'installer_kind_sniffer.dart';

/// מריץ תהליך ומחזיר את תוצאתו. מוזרק כדי שבדיקות לא יריצו installer
/// אמיתי על המחשב שמריץ את החבילה.
typedef CustomProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// הרצה דרך ShellExecute — ראו [ElevatedProcess.run]. מוזרק מאותה סיבה.
typedef CustomShellRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required bool elevate,
  required bool rawLastArgument,
});

/// מתקין תוכנה נוספת מקובץ שכבר יושב על הכונן — **בלי לגעת ברשת**.
///
/// אותו עיקרון של `OtzariaInstaller`: ההורדה נעשית מראש אל המראה,
/// וההתקנה קוראת משם גם במחשב שאין בו אינטרנט.
class CustomAppInstaller {
  CustomAppInstaller({
    CustomProcessRunner? processRunner,
    CustomShellRunner? shellRunner,
    String? downloadsDir,
  })  : _run = processRunner ?? Process.run,
        _runShell = shellRunner ?? ElevatedProcess.run,
        _downloadsDir = downloadsDir;

  final CustomProcessRunner _run;

  /// כש-`Process.run` אינו יכול: מתקין שדורש מנהל, או `/D=` שאסור לצטט.
  final CustomShellRunner _runShell;
  final String? _downloadsDir;

  /// תיקיית ההורדות של המשתמש — לשם מגיעה תוכנה מסוג ארכיון.
  String get downloadsDir => _downloadsDir ?? _defaultDownloadsDir();

  static String _defaultDownloadsDir() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'];
    if (home == null || home.isEmpty) return Directory.current.path;
    return p.join(home, 'Downloads');
  }

  /// מתקין את [installerPath] לפי הכללים שב-[descriptor].
  ///
  /// זורק [AppDescriptorException] עם הודעה מתורגמת בכל כשל — הממשק מציג
  /// אותה כמות שהיא.
  ///
  /// מחזיר את הסוג שזוהה, ואת נתיב היעד כשהקובץ רק הועתק.
  ///
  /// [copyToDir] הוא היעד של **קובץ נייד** — מה שהמשתמש בחר בדיאלוג. ארכיון
  /// מתעלם ממנו והולך לתיקיית ההורדות, כי אין לו יעד טבעי אחר.
  Future<CustomInstallOutcome> install({
    required AppDescriptor descriptor,
    required String installerPath,
    String? copyToDir,
  }) async {
    final t = AppL10n.strings.customAppsDomain;

    if (!await File(installerPath).exists()) {
      throw AppDescriptorException(t.installerFileMissing(installerPath));
    }

    // **סוג ההתקנה נקבע כאן ולא נשמר ברשומה** — חוץ מהצהרת "זו התוכנה
    // עצמה", שהיא הדבר היחיד כאן שאי אפשר להריח מהבייטים (ראו
    // [AppDescriptor.portableFile]). כל השאר נגזר מהקובץ שעומד לרוץ ברגע
    // זה, ולכן אינו יכול להתיישן, והמשתמש אינו נשאל עליו בכלל.
    final kind = descriptor.portableFile
        ? CustomInstallerKind.portableFile
        : await const InstallerKindSniffer().sniff(installerPath) ??
            CustomInstallerKind.interactive;

    // אין כאן התקנה — רק העתקה. ארכיון מונח בתיקיית ההורדות (אין ל-ZIP
    // מיקום התקנה טבעי, וניחוש שלנו היה יוצר תיקייה שאיש לא ביקש), וקובץ
    // נייד מגיע לתיקייה שהמשתמש הצביע עליה.
    if (kind.isCopyOnly) {
      return CustomInstallOutcome(
        kind: kind,
        copiedPath: await _copyInto(
          kind.isArchive ? downloadsDir : (copyToDir ?? downloadsDir),
          installerPath,
        ),
      );
    }

    final command = kind.silentCommand(
      installerPath: installerPath,
      installDir: descriptor.installDir,
    );
    if (command == null) return CustomInstallOutcome(kind: kind);

    // `Process.run` היה עוטף במרכאות, ו-NSIS היה מתקין לנתיב שמסתיים ב-`"`.
    if (command.rawLastArgument &&
        ElevatedProcess.needsQuoting(command.arguments.last)) {
      return _installViaShell(kind, command, elevate: false);
    }

    final ProcessResult result;
    try {
      result = await _run(command.executable, command.arguments);
    } on ProcessException catch (e) {
      if (!ElevatedProcess.isElevationRequired(e)) rethrow;
      return _installViaShell(kind, command, elevate: true);
    }
    if (result.exitCode != 0) {
      throw AppDescriptorException(
        t.installerExitCode(
          result.exitCode,
          'stdout: ${result.stdout}\nstderr: ${result.stderr}',
        ),
      );
    }
    return CustomInstallOutcome(kind: kind);
  }

  /// דרך ShellExecute, שיודע להקפיץ UAC — `CreateProcess` אינו יודע.
  /// סירוב ל-UAC מקבל הודעה משלו — אינו "שגיאה בהתקנה".
  Future<CustomInstallOutcome> _installViaShell(
    CustomInstallerKind kind,
    CustomInstallerCommand command, {
    required bool elevate,
  }) async {
    final t = AppL10n.strings.customAppsDomain;
    final result = await _runShell(
      command.executable,
      command.arguments,
      elevate: elevate,
      rawLastArgument: command.rawLastArgument,
    );
    if (result.exitCode == ElevatedProcess.cancelledCode) {
      throw AppDescriptorException(t.installerElevationDeclined);
    }
    if (result.exitCode != 0) {
      throw AppDescriptorException(
        t.installerExitCode(result.exitCode, 'stderr: ${result.stderr}'),
      );
    }
    return CustomInstallOutcome(kind: kind);
  }

  /// מעתיק את הקובץ ל-[targetDir], בלי לדרוס קובץ קיים בעל אותו שם.
  Future<String> _copyInto(String targetDir, String sourcePath) async {
    try {
      final dir = Directory(targetDir);
      await dir.create(recursive: true);

      final target = _freeNameIn(dir.path, p.basename(sourcePath));
      await File(sourcePath).copy(target);
      return target;
    } catch (e) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.fileCopyFailed('$e'),
      );
    }
  }

  /// `app.zip` → `app (2).zip` כשהראשון תפוס. דריסה שקטה של קובץ בתיקיית
  /// ההורדות היא בדיוק מה שמשתמש לא מצפה לו.
  static String _freeNameIn(String dir, String fileName) {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);

    var candidate = p.join(dir, fileName);
    for (var i = 2; File(candidate).existsSync() && i < 1000; i++) {
      candidate = p.join(dir, '$base ($i)$ext');
    }
    return candidate;
  }
}
