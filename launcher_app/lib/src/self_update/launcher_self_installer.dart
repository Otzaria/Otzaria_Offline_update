import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../app_report/launcher_crash_session.dart';
import 'launcher_install_layout.dart';
import 'launcher_release_client.dart';

class LauncherSelfInstaller {
  LauncherSelfInstaller({
    Future<void> Function(String executable, List<String> arguments)?
        startDetached,
    void Function()? quit,
    int? currentPid,
    String? operatingSystem,
  })  : _startDetached = startDetached ?? _defaultStartDetached,
        _quit = quit ?? _defaultQuit,
        _currentPid = currentPid ?? pid,
        _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final Future<void> Function(String executable, List<String> arguments)
      _startDetached;
  final void Function() _quit;
  final int _currentPid;
  final String _operatingSystem;

  /// הקובץ החדש בזמן ההעתקה, לפני שהוא מקבל את השם האמיתי.
  static const String stagedName = '.launcher-update.exe';

  static const String previousName = '.launcher-previous.exe';

  /// תיקיית חילוץ זמנית ב-macOS, לצד חבילת ה-`.app`.
  static const String macStagingDirName = '.launcher-update-staging';

  Future<bool> apply({
    required LauncherInstallLayout layout,
    required String downloadedFilePath,
  }) async {
    if (_operatingSystem == 'windows') {
      await _replaceFile(layout: layout, sourcePath: downloadedFilePath);
      await _restart(layout);
      return true;
    }
    if (_operatingSystem == 'macos') {
      await _replaceMacBundle(layout: layout, zipPath: downloadedFilePath);
      return false;
    }
    throw LauncherUpdateException(
      AppL10n.strings.launcherUpdate.unsupportedPlatform(_operatingSystem),
    );
  }

  /// מוחק שאריות של החלפה שנקטעה. best-effort — נקרא לפני כל בדיקה, כדי
  /// שקובץ `.launcher-previous.exe` שנשאר נעול לא יישאר לנצח.
  ///
  /// ב-macOS השאריות הן **תיקיות** ולא קבצים — תיקיית ה-staging וחבילת
  /// ה-`.app` הקודמת — וכל אחת מהן היא חבילה שלמה של מאות מגה-בייט. עד
  /// שנוספו כאן הן נשארו על הכונן לנצח אחרי עדכון שנקטע.
  Future<void> cleanupLeftovers(LauncherInstallLayout layout) async {
    for (final name in const [stagedName, previousName]) {
      try {
        final file = File(p.join(layout.executableDir, name));
        if (await file.exists()) await file.delete();
      } catch (_) {
        // כנראה עדיין נעול — הריצה הבאה תנסה שוב.
      }
    }
    for (final path in [
      p.join(layout.executableDir, macStagingDirName),
      _macPreviousBundle(layout),
    ]) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {
        // כמו למעלה — הריצה הבאה תנסה שוב.
      }
    }
  }

  /// חבילת ה-`.app` הקודמת בזמן ההחלפה. שם אחד בשני המקומות — ההחלפה
  /// כותבת אותו, והניקוי מחפש אותו.
  static String _macPreviousBundle(LauncherInstallLayout layout) =>
      '${layout.executablePath}.previous';

  Future<void> _replaceFile({
    required LauncherInstallLayout layout,
    required String sourcePath,
  }) async {
    final dir = layout.executableDir;
    final staged = File(p.join(dir, stagedName));
    final previous = File(p.join(dir, previousName));

    try {
      if (await staged.exists()) await staged.delete();
      if (await previous.exists()) await previous.delete();
      await File(sourcePath).copy(staged.path);
    } on FileSystemException catch (e) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.replaceFailed(e.message),
      );
    }

    try {
      await File(layout.executablePath).rename(previous.path);
    } on FileSystemException catch (e) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.replaceFailed(e.message),
      );
    }

    try {
      await staged.rename(layout.executablePath);
    } catch (e) {
      try {
        await previous.rename(layout.executablePath);
      } catch (_) {}
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.replaceFailed('$e'),
      );
    }
  }

  Future<void> _restart(LauncherInstallLayout layout) async {
    try {
      await _startDetached(layout.executablePath, [
        '${LauncherInstallLayout.afterUpdateFlag}=$_currentPid',
      ]);
    } catch (e) {
      throw LauncherUpdateException(
        await _rollBack(layout)
            ? AppL10n.strings.launcherUpdate.restartFailedRolledBack('$e')
            : AppL10n.strings.launcherUpdate.restartFailed('$e'),
      );
    }
    _quit();
  }

  Future<bool> _rollBack(LauncherInstallLayout layout) async {
    final dir = layout.executableDir;
    final previous = File(p.join(dir, previousName));
    final rejected = File(p.join(dir, stagedName));
    try {
      if (!await previous.exists()) return false;
      if (await rejected.exists()) await rejected.delete();
      await File(layout.executablePath).rename(rejected.path);
    } catch (_) {
      return false;
    }
    try {
      await previous.rename(layout.executablePath);
    } catch (_) {
      try {
        await rejected.rename(layout.executablePath);
      } catch (_) {}
      return false;
    }
    try {
      await rejected.delete();
    } catch (_) {}
    return true;
  }

  /// ⚠️ לא נבדק על חומרה אמיתית. `ditto` ולא `unzip`: הבנייה שלנו ל-macOS
  /// חתומה ad-hoc, ו-`unzip` הורס symlinks ו-xattrs ואיתם את החתימה.
  Future<void> _replaceMacBundle({
    required LauncherInstallLayout layout,
    required String zipPath,
  }) async {
    final dir = layout.executableDir;
    final staging = Directory(p.join(dir, macStagingDirName));
    final previous = Directory(_macPreviousBundle(layout));

    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      final result = await Process.run(
        '/usr/bin/ditto',
        ['-x', '-k', zipPath, staging.path],
      );
      if (result.exitCode != 0) {
        throw LauncherUpdateException(
          AppL10n.strings.appDomain
              .dittoExtractFailed(result.exitCode, '${result.stderr}'),
        );
      }

      Directory? bundle;
      for (final entry in staging.listSync()) {
        if (entry is Directory && p.extension(entry.path) == '.app') {
          bundle = entry;
          break;
        }
      }
      if (bundle == null) {
        throw LauncherUpdateException(
          AppL10n.strings.appDomain.macAppNotFoundInArchive,
        );
      }

      if (await previous.exists()) await previous.delete(recursive: true);
      await Directory(layout.executablePath).rename(previous.path);
      try {
        await bundle.rename(layout.executablePath);
      } catch (e) {
        try {
          await previous.rename(layout.executablePath);
        } catch (_) {}
        throw LauncherUpdateException(
          AppL10n.strings.launcherUpdate.replaceFailed('$e'),
        );
      }
      await previous.delete(recursive: true);

      // אותו שיקול שב-`OtzariaInstaller`: הורדה דרך dart:io אינה מסמנת
      // quarantine, אבל zip שהגיע לכונן מדפדפן או מ-AirDrop כן — ואז
      // Gatekeeper חוסם את הגרסה החדשה, במחשב שאין בו אינטרנט לתקן בו.
      await _stripQuarantineQuietly(layout.executablePath);
    } on FileSystemException catch (e) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.replaceFailed(e.message),
      );
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> _stripQuarantineQuietly(String path) async {
    try {
      await Process.run('/usr/bin/xattr', [
        '-dr',
        'com.apple.quarantine',
        path,
      ]);
    } catch (_) {
      // best-effort בלבד — כישלון כאן לא הופך החלפה שהצליחה לכישלון.
    }
  }

  static Future<void> _defaultStartDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: p.dirname(executable),
      mode: ProcessStartMode.detached,
    );
  }

  static void _defaultQuit() => LauncherCrashSession.exitCleanly();
}
