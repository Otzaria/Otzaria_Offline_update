import 'dart:convert';
import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/sandbox.dart';

void main() {
  sandboxRealDataRoot();

  group('versionFromDisk', () {
    test('מפענח hotfix מקוד הגרסה שב-build', () {
      expect(
        OtzariaUpdateCheckResult.versionFromDisk('0.9.97+99702'),
        '0.9.97.2',
      );
      expect(
        OtzariaUpdateCheckResult.versionFromDisk('1.2.3+1020315'),
        '1.2.3.15',
      );
    });

    test('hotfix 0 נשאר בשלושה חלקים', () {
      expect(
        OtzariaUpdateCheckResult.versionFromDisk('0.9.97+99700'),
        '0.9.97',
      );
    });

    test('build שאינו קוד גרסה תואם אינו מפוענח', () {
      expect(OtzariaUpdateCheckResult.versionFromDisk('0.9.97+740'), '0.9.97');
      expect(
        OtzariaUpdateCheckResult.versionFromDisk('0.9.97+99802'),
        '0.9.97',
      );
      expect(OtzariaUpdateCheckResult.versionFromDisk('v0.9.97'), '0.9.97');
      expect(
        OtzariaUpdateCheckResult.versionFromDisk('0.9.97.1+99701'),
        '0.9.97.1',
      );
    });
  });

  group('השוואה מול תגי גיטהאב אמיתיים', () {
    test('hotfix מהדיסק שווה לתג בן שלושה חלקים עם build', () {
      expect(
        OtzariaUpdateCheckResult.compareVersions('0.9.97.2', '0.9.97+789'),
        0,
      );
      expect(
        OtzariaUpdateCheckResult.sameVersion('0.9.97.2', '0.9.97+789'),
        isTrue,
      );
    });

    test('hotfix נספר כששני הצדדים נושאים אותו', () {
      expect(
        OtzariaUpdateCheckResult.compareVersions('0.9.97', '0.9.97.2'),
        lessThan(0),
      );
      expect(
        OtzariaUpdateCheckResult.compareVersions('0.9.97.2+800', '0.9.97.3'),
        lessThan(0),
      );
      expect(
        OtzariaUpdateCheckResult.compareVersions('0.9.96+736', '0.9.96+741'),
        lessThan(0),
      );
    });
  });

  group('התקנת hotfix מזוהה כגרסה שהותקנה', () {
    late Directory root;
    late String exe;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('otzaria-hotfix-test-');
      final installDir = Directory(p.join(root.path, 'install'))
        ..createSync(recursive: true);
      exe = p.join(installDir.path, 'otzaria.exe');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> writeMirror(String tag) async {
      final mirror = p.join(root.path, 'data', 'mirror', 'app');
      final installers = Directory(p.join(mirror, 'installers', tag))
        ..createSync(recursive: true);
      final name = 'otzaria-$tag-windows.exe';
      File(p.join(installers.path, name)).writeAsStringSync('x');
      final release = OtzariaRelease(
        tagName: tag,
        name: tag,
        isPrerelease: false,
        isDraft: false,
        publishedAt: DateTime.utc(2026, 1, 1),
        installerKind: OtzariaInstallerKind.windowsSetupExe,
        installerAssetName: name,
        installerDownloadUrl: 'https://example.invalid/$name',
        installerSizeBytes: 1,
      );
      File(p.join(mirror, 'latest-release.json')).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 3,
          'source': 'github-latest',
          'latest': release.toJson()
            ..['installerPath'] = 'installers/$tag/$name',
        }),
      );
    }

    /// הנתיב נגזר מ-dataRootFor, כמו בקוד: ב-macOS הנתיב של ווינדוס בנוי עם `\`.
    void writeCapabilities(String appData, Map<String, Object> json) {
      final dataRoot = OtzariaCapabilities.dataRootFor(
        exe,
        platform: OtzariaTargetPlatform.windows,
        environment: {'APPDATA': appData},
      )!;
      Directory(dataRoot).createSync(recursive: true);
      File(p.join(dataRoot, OtzariaCapabilities.fileName))
          .writeAsStringSync(jsonEncode(json));
    }

    OtzariaManager manager({Map<String, String> environment = const {}}) {
      final manager = OtzariaManager(
        dataDir: p.join(root.path, 'data'),
        platform: OtzariaTargetPlatform.windows,
        environment: environment,
        runningLocator: _RunningFrom(exe),
        installRegistry: const _NoRegistry(),
        versionReader: const _FileContentVersionReader(),
      );
      addTearDown(manager.dispose);
      return manager;
    }

    for (final scenario in [
      (
        installed: '1.0.0+900',
        disk: '1.0.0+1000002',
        target: '1.0.0.1',
        update: false,
        newer: true
      ),
      (
        installed: '1.0.0+900',
        disk: '1.0.0+1000002',
        target: '1.0.0.2+901',
        update: false,
        newer: false
      ),
      (
        installed: '1.0.0+900',
        disk: '1.0.0+1000002',
        target: '1.0.0.3+901',
        update: true,
        newer: false
      ),
      (
        installed: '1.0.0.2+900',
        disk: '1.0.0',
        target: '1.0.0.1+901',
        update: false,
        newer: true
      ),
      (
        installed: '1.0.0+900',
        disk: '1.0.0+1000000',
        target: '1.0.0.1+901',
        update: true,
        newer: false
      ),
      (
        installed: '1.0.0.2+900',
        disk: '1.0.0+1000002',
        target: '1.0.0.1+901',
        update: false,
        newer: true
      ),
      (
        installed: '1.0.0+900',
        disk: '1.0.0+1000000',
        target: '1.0.0+901',
        update: false,
        newer: false
      ),
      (
        installed: '1.0.0.0+900',
        disk: '1.0.0+1000000',
        target: '1.0.0+901',
        update: false,
        newer: false
      ),
    ]) {
      test(
          'persisted install ${scenario.installed} to Latest ${scenario.target}',
          () async {
        File(exe).writeAsStringSync(scenario.disk);
        await writeMirror(scenario.target);
        final state =
            File(p.join(root.path, 'data', 'otzaria_install_state.json'));
        state.writeAsStringSync(jsonEncode(OtzariaInstallState(
          installedTagName: scenario.installed,
          appVersion: scenario.disk,
          installDir: p.dirname(exe),
          launchPath: exe,
        ).toJson()));
        final check = await manager().checkForUpdate();
        expect(check.currentState!.installedTagName, scenario.installed);
        expect(check.currentState!.appVersion, scenario.disk);
        expect(check.updateAvailable, scenario.update);
        expect(check.installedIsNewer, scenario.newer);
      });
    }

    test('0.9.97+99702 על הדיסק הוא 0.9.97.2 — אין עדכון חוזר', () async {
      File(exe).writeAsStringSync('0.9.97+99702');
      await writeMirror('0.9.97.2');

      final check = await manager().checkForUpdate();

      expect(check.currentState!.installedTagName, '0.9.97.2');
      expect(check.updateAvailable, isFalse);
      expect(check.installedIsNewer, isFalse);
    });

    test('hotfix מותקן מול Latest ללא hotfix — אין הצעת נסיגה', () async {
      File(exe).writeAsStringSync('0.9.97+99702');
      await writeMirror('0.9.97+789');

      final check = await manager().checkForUpdate();

      expect(check.updateAvailable, isFalse);
      expect(check.installedIsNewer, isTrue);
    });

    test('exe בלי hotfix מול תג hotfix — יש עדכון', () async {
      File(exe).writeAsStringSync('0.9.97+99700');
      await writeMirror('0.9.97.2');

      expect((await manager().checkForUpdate()).updateAvailable, isTrue);
    });

    test('hotfix חדש יותר במראה עדיין מוצע', () async {
      File(exe).writeAsStringSync('0.9.97+99702');
      await writeMirror('0.9.97.3');

      expect((await manager().checkForUpdate()).updateAvailable, isTrue);
    });

    test('הגרסה מ-otzaria_capabilities.json גוברת כשה-build תואם', () async {
      File(exe).writeAsStringSync('1.2.3+5');
      await writeMirror('1.2.3.4');
      final appData = p.join(root.path, 'appdata');
      writeCapabilities(appData, {
        'formatVersion': 1,
        'appVersion': '1.2.3.4',
        'buildNumber': 5,
        'exePath': exe,
      });

      final check = await manager(
        environment: {'APPDATA': appData},
      ).checkForUpdate();

      expect(check.currentState!.installedTagName, '1.2.3.4');
      expect(check.updateAvailable, isFalse);
    });

    test('capabilities של build אחר אינו נאמן', () async {
      File(exe).writeAsStringSync('1.2.3+6');
      final appData = p.join(root.path, 'appdata');
      writeCapabilities(appData, {
        'appVersion': '1.2.3.4',
        'buildNumber': 5,
        'exePath': exe,
      });

      final check = await manager(
        environment: {'APPDATA': appData},
      ).checkForUpdate();

      expect(check.currentState!.installedTagName, '1.2.3');
    });
  });
}

class _FileContentVersionReader implements InstalledVersionReader {
  const _FileContentVersionReader();

  @override
  String? readVersion(String launchPath) =>
      File(launchPath).readAsStringSync().trim();
}

class _RunningFrom extends RunningOtzariaLocator {
  const _RunningFrom(this.path);

  final String path;

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: true, launchPath: path);
}

class _NoRegistry extends WindowsInstallRegistry {
  const _NoRegistry();

  @override
  Future<List<String>> otzariaInstallDirs() async => const [];
}
