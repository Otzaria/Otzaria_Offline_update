import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/app_descriptor.dart';
import '../models/custom_install_outcome.dart';
import '../models/custom_installer_kind.dart';
import 'installer_kind_sniffer.dart';

/// מריץ תהליך ומחזיר את תוצאתו. מוזרק כדי שבדיקות לא יריצו installer
/// אמיתי על המחשב שמריץ את החבילה.
typedef CustomProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// מתקין תוכנה נוספת מקובץ שכבר יושב על הכונן — **בלי לגעת ברשת**.
///
/// אותו עיקרון של `OtzariaInstaller`: ההורדה נעשית מראש אל המראה,
/// וההתקנה קוראת משם גם במחשב שאין בו אינטרנט.
class CustomAppInstaller {
  CustomAppInstaller({
    CustomProcessRunner? processRunner,
    String? downloadsDir,
  })  : _run = processRunner ?? Process.run,
        _downloadsDir = downloadsDir;

  final CustomProcessRunner _run;
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
  /// מחזיר את הסוג שזוהה, ואת נתיב הארכיון כשמדובר בתוכנה מסוג ארכיון.
  Future<CustomInstallOutcome> install({
    required AppDescriptor descriptor,
    required String installerPath,
  }) async {
    final t = AppL10n.strings.customAppsDomain;

    if (!await File(installerPath).exists()) {
      throw AppDescriptorException(t.installerFileMissing(installerPath));
    }

    // **סוג ההתקנה נקבע כאן ולא נשמר ברשומה.** הוא נגזר מהבייטים של הקובץ
    // שעומד לרוץ ברגע זה, ולכן אינו יכול להתיישן — ובעיקר, המשתמש אינו
    // נשאל עליו בכלל. שאלה "איזה framework בנה את ה-installer" היא השאלה
    // היחידה בכל התהליך שמשתמש רגיל אינו יכול לענות עליה.
    final kind = await const InstallerKindSniffer().sniff(installerPath) ??
        CustomInstallerKind.interactive;

    // ארכיון אינו "מותקן" — הוא פשוט מונח בתיקיית ההורדות, והמשתמש עושה
    // איתו מה שהוא רוצה. אין ל-ZIP מיקום התקנה טבעי, וניחוש שלנו היה
    // יוצר תיקייה שאיש לא ביקש.
    if (kind.isArchive) {
      return CustomInstallOutcome(
        kind: kind,
        archivePath: await _copyToDownloads(installerPath),
      );
    }

    final command = kind.silentCommand(
      installerPath: installerPath,
      installDir: descriptor.installDir,
    );
    if (command == null) return CustomInstallOutcome(kind: kind);

    final result = await _run(command.executable, command.arguments);
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

  /// מעתיק את הארכיון לתיקיית ההורדות, בלי לדרוס קובץ קיים בעל אותו שם.
  Future<String> _copyToDownloads(String archivePath) async {
    try {
      final dir = Directory(downloadsDir);
      await dir.create(recursive: true);

      final target = _freeNameIn(dir.path, p.basename(archivePath));
      await File(archivePath).copy(target);
      return target;
    } catch (e) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.archiveExtractFailed('$e'),
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
