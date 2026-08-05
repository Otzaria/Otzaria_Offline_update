@TestOn('mac-os')
library;

import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// בדיקת קצה-לקצה של מסלול ההתקנה ב-macOS מול **חבילה אמיתית**.
///
/// אופציונלית, כמו הבדיקות מול הפצות אמיתיות ב-`seforim_library_updater`:
/// רצה רק כשמשתנה הסביבה `OTZARIA_MACOS_ZIP` מצביע על `otzaria-macos.zip`
/// שהורד מ-releases. אחרת מדולגת — כדי שה-CI לא יוריד 73MB בכל ריצה.
///
/// ```sh
/// curl -L -o /tmp/otzaria-macos.zip \
///   'https://github.com/Otzaria/otzaria/releases/download/0.9.96%2B736/otzaria-macos.zip'
/// OTZARIA_MACOS_ZIP=/tmp/otzaria-macos.zip dart test test/otzaria_installer_macos_test.dart
/// ```
///
/// למה בדיקה מול חבילה אמיתית ולא fixture מזויף: כל מה שמעניין כאן הוא
/// דווקא מה ש-`.app` אמיתית מביאה איתה — symlinks בתוך frameworks, חתימה
/// ad-hoc, ו-Info.plist בפורמט binary. fixture של תיקיות ריקות לא היה בודק
/// שום דבר מזה.
void main() {
  final zipPath = Platform.environment['OTZARIA_MACOS_ZIP'];

  group(
    'OtzariaInstaller (macOS, real release zip)',
    skip: zipPath == null
        ? 'הוגדר OTZARIA_MACOS_ZIP? אם לא — מדולג (ראו doc בראש הקובץ).'
        : null,
    () {
      const tag = '0.9.96+736';
      const assetName = 'otzaria-macos.zip';

      late Directory tempDir;
      late String installDir;
      late String cacheDir;
      late OtzariaRelease release;

      setUp(() async {
        tempDir =
            await Directory.systemTemp.createTemp('otzaria-installer-test-');
        installDir = p.join(tempDir.path, 'install');
        cacheDir = p.join(tempDir.path, 'cache');

        // מכינים את ה-zip ב-cache באותו מקום ובאותו גודל שה-installer מצפה
        // לו, כך ש-ensureCached יראה cache-hit ולא ייגע ברשת בכלל.
        final releaseCacheDir = Directory(p.join(cacheDir, tag))
          ..createSync(recursive: true);
        final cached = File(p.join(releaseCacheDir.path, assetName));
        await File(zipPath!).copy(cached.path);

        release = OtzariaRelease(
          tagName: tag,
          name: 'Otzaria $tag',
          isPrerelease: false,
          isDraft: false,
          publishedAt: null,
          installerKind: OtzariaInstallerKind.macAppZip,
          installerAssetName: assetName,
          // כתובת לא-קיימת בכוונה: אם הבדיקה תיגע ברשת, היא תיכשל במקום
          // לעבור בשקט על הורדה אמיתית.
          installerDownloadUrl:
              'https://example.invalid/must-not-be-downloaded',
          installerSizeBytes: cached.lengthSync(),
        );
      });

      tearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      OtzariaInstaller newInstaller() => OtzariaInstaller(
            defaultInstallDir: installDir,
            cacheDir: cacheDir,
          );

      test('installs the .app, and the bundle stays runnable', () async {
        final installer = newInstaller();
        addTearDown(installer.close);

        final state = await installer.downloadAndInstall(release: release);

        expect(state.installedTagName, tag);
        expect(state.installDir, installDir);
        expect(p.extension(state.launchPath), '.app');
        expect(Directory(state.launchPath).existsSync(), isTrue);

        // ה-launchPath שנשמר הוא באמת מה שהתגלה בתיקיית ההתקנה.
        expect(
          await const OtzariaAppLocator(platform: OtzariaTargetPlatform.macos)
              .findIn(installDir),
          state.launchPath,
        );

        // הגרסה נקראת מה-Info.plist (binary plist) — בלי החלק שאחרי ה-+.
        expect(
          const MacAppVersionReader().readVersion(state.launchPath),
          OtzariaUpdateCheckResult.normalizeVersion(tag),
        );

        // הבדיקה שבאמת מצדיקה שימוש ב-ditto: החתימה של ה-bundle שרדה את
        // החילוץ. חילוץ עם unzip היה שובר אותה, ואז macOS מסרב להריץ.
        final verify = await Process.run('/usr/bin/codesign', [
          '--verify',
          '--deep',
          state.launchPath,
        ]);
        expect(
          verify.exitCode,
          0,
          reason: 'codesign --verify נכשל: ${verify.stderr}',
        );

        // ה-staging וה-גיבוי לא נשארו מאחור.
        expect(
          Directory(installDir)
              .listSync()
              .map((e) => p.basename(e.path))
              .where((name) => name.startsWith('.otzaria-')),
          isEmpty,
        );
      });

      test('re-installing replaces the existing bundle in place', () async {
        final installer = newInstaller();
        addTearDown(installer.close);

        final first = await installer.downloadAndInstall(release: release);
        // סמן שנשתול בתוך ההתקנה הראשונה: אם ההתקנה השנייה באמת החליפה את
        // ה-bundle (ולא הוסיפה עותק שני לידו), הסמן ייעלם.
        final marker =
            File(p.join(first.launchPath, 'Contents', '.stale-marker'))
              ..writeAsStringSync('x');
        expect(marker.existsSync(), isTrue);

        final second = await installer.downloadAndInstall(release: release);

        expect(second.launchPath, first.launchPath);
        expect(marker.existsSync(), isFalse);

        // בדיוק חבילת .app אחת בתיקיית ההתקנה — לא שתיים.
        final bundles = Directory(installDir)
            .listSync()
            .where((e) => p.extension(e.path) == '.app')
            .toList();
        expect(bundles, hasLength(1));
      });
    },
  );
}
