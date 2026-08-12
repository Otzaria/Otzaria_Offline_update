import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'launcher_install_layout.dart';
import 'launcher_release_client.dart';

/// מחליף את קובץ ההרצה של הלאנצ'ר בגרסה שהורדה, **באותו מיקום בדיוק**, ומריץ
/// אותו מחדש.
///
/// מה *לא* נוגעים בו: `OtzariaData/` — ההגדרות, המראות וההתקנה המנוהלת של
/// אוצריא. בווינדוס היא יושבת בתוך `app-files\`, וההחלפה כאן נוגעת רק
/// ב-exe שמחוץ לה; ה-stub החדש מחלץ את `app-files` מחדש **מעל** הקיים, בלי
/// למחוק דבר. ב-macOS היא יושבת לצד חבילת ה-`.app` שמוחלפת.
///
/// ההחלפה עצמה היא **שתי החלפות שם ולא מחיקה-ואז-החלפה**, בדיוק כמו החלפת
/// `seforim.db`: הקובץ הקיים מוסט הצידה, החדש נכנס במקומו, ורק אז הישן נמחק.
/// כך אין רגע שבו אין קובץ הרצה בכלל, ואם ההחלפה השנייה נכשלה — הראשונה
/// מתגלגלת אחורה.
class LauncherSelfInstaller {
  LauncherSelfInstaller({
    Future<void> Function(String executable, List<String> arguments)?
        startDetached,
    void Function()? quit,
    int? currentPid,
  })  : _startDetached = startDetached ?? _defaultStartDetached,
        _quit = quit ?? _defaultQuit,
        _currentPid = currentPid ?? pid;

  final Future<void> Function(String executable, List<String> arguments)
      _startDetached;
  final void Function() _quit;
  final int _currentPid;

  /// הקובץ החדש בזמן ההעתקה, לפני שהוא מקבל את השם האמיתי.
  static const String stagedName = '.launcher-update.exe';

  /// הקובץ הקודם, בזמן ההחלפה בלבד.
  static const String previousName = '.launcher-previous.exe';

  /// תיקיית חילוץ זמנית ב-macOS, לצד חבילת ה-`.app`.
  static const String macStagingDirName = '.launcher-update-staging';

  /// מחליף ומפעיל מחדש. מחזיר `true` אם הגרסה החדשה כבר הופעלה (ווינדוס),
  /// ו-`false` כשההחלפה הושלמה אך על המשתמש לפתוח את התוכנה בעצמו (macOS).
  ///
  /// זורק [LauncherUpdateException] כשההחלפה נכשלה — במקרה כזה הקובץ הקודם
  /// חוזר למקומו והתוכנה ממשיכה לרוץ.
  Future<bool> apply({
    required LauncherInstallLayout layout,
    required String downloadedFilePath,
  }) async {
    if (Platform.isWindows) {
      await _replaceFile(layout: layout, sourcePath: downloadedFilePath);
      await _restart(layout);
      return true;
    }
    if (Platform.isMacOS) {
      await _replaceMacBundle(layout: layout, zipPath: downloadedFilePath);
      // אין הפעלה מחדש אוטומטית: `open` על חבילה שהוחלפה תחת אפליקציה שעדיין
      // רצה מתנהגת באופן לא צפוי (LaunchServices מחזיק את הישנה במטמון).
      // התוכנה הפתוחה ממשיכה לעבוד; המשתמש מתבקש לפתוח אותה מחדש.
      return false;
    }
    throw LauncherUpdateException(
      AppL10n.strings.launcherUpdate
          .unsupportedPlatform(Platform.operatingSystem),
    );
  }

  /// מוחק שאריות של החלפה שנקטעה. best-effort — נקרא לפני כל בדיקה, כדי
  /// שקובץ `.launcher-previous.exe` שנשאר נעול לא יישאר לנצח.
  Future<void> cleanupLeftovers(LauncherInstallLayout layout) async {
    for (final name in const [stagedName, previousName]) {
      try {
        final file = File(p.join(layout.executableDir, name));
        if (await file.exists()) await file.delete();
      } catch (_) {
        // כנראה עדיין נעול — הריצה הבאה תנסה שוב.
      }
    }
  }

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
      // מעתיקים לשם זמני **באותה תיקייה**: החלפת שם בתוך אותו כונן היא
      // אטומית, ולכן קובץ הרצה חצי-מועתק לא יכול לקבל את השם האמיתי.
      await File(sourcePath).copy(staged.path);
    } on FileSystemException catch (e) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.replaceFailed(e.message),
      );
    }

    // גם ההסטה הראשונה עטופה: exe נעול (אנטי-וירוס, תיקייה לקריאה בלבד)
    // היה מפיל מכאן `FileSystemException` גולמית באנגלית, בניגוד לחוזה.
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
      // גלגול אחורה — עדיף להישאר בגרסה הישנה מאשר בלי קובץ הרצה.
      try {
        await previous.rename(layout.executablePath);
      } catch (_) {}
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.replaceFailed('$e'),
      );
    }

    try {
      await previous.delete();
    } catch (_) {
      // ה-stub אינו רץ כרגע ולכן זה אמור להצליח; אם לא — [cleanupLeftovers].
    }
  }

  /// מריץ את הקובץ החדש ומסיים. ה-stub החדש ממתין שהתהליך הזה ייסגר לפני
  /// שהוא מחלץ מחדש את `app-files` — אחרת הוא היה מנסה לכתוב על ה-DLL
  /// וה-exe שאנחנו עצמנו מחזיקים נעולים.
  Future<void> _restart(LauncherInstallLayout layout) async {
    try {
      await _startDetached(layout.executablePath, [
        '${LauncherInstallLayout.afterUpdateFlag}=$_currentPid',
      ]);
    } catch (e) {
      throw LauncherUpdateException(
        AppL10n.strings.launcherUpdate.restartFailed('$e'),
      );
    }
    _quit();
  }

  /// ⚠️ לא נבדק על חומרה אמיתית. `ditto` ולא `unzip`: הבנייה שלנו ל-macOS
  /// חתומה ad-hoc, ו-`unzip` הורס symlinks ו-xattrs ואיתם את החתימה.
  Future<void> _replaceMacBundle({
    required LauncherInstallLayout layout,
    required String zipPath,
  }) async {
    final dir = layout.executableDir;
    final staging = Directory(p.join(dir, macStagingDirName));
    final previous = Directory('${layout.executablePath}.previous');

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

  static void _defaultQuit() => exit(0);
}
