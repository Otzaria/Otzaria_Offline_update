import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _tag = '0.9.98';

OtzariaRelease _release() => const OtzariaRelease(
      tagName: _tag,
      name: 'Otzaria $_tag',
      isPrerelease: false,
      isDraft: false,
      publishedAt: null,
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria-$_tag-windows.exe',
      installerDownloadUrl: 'https://example/otzaria.exe',
      installerSizeBytes: 1,
    );

void main() {
  late Directory temp;
  late String installDir;
  late String exe;
  late String setup;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-relaunch-test-');
    installDir = p.join(temp.path, 'install');
    exe = p.join(installDir, 'otzaria.exe');
    Directory(installDir).createSync(recursive: true);
    File(exe).writeAsStringSync('0.9.97+99700');
    setup = await _exitScript(temp.path, exitCode: 1);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  OtzariaInstaller installerWith(
    Future<bool?> Function(String, Duration, bool Function()) wait,
  ) =>
      OtzariaInstaller(
        cacheDir: p.join(temp.path, 'cache'),
        appLocator: const OtzariaAppLocator(
          platform: OtzariaTargetPlatform.windows,
        ),
        versionReader: const _FileContentVersionReader(),
        pollInterval: const Duration(milliseconds: 20),
        waitForRelaunchedSetup: wait,
      );

  test('exit 1: ממתינים למתקין שהופעל מחדש, ואז ההתקנה מזוהה', () async {
    String? waitedFor;
    var announced = false;
    final installer = installerWith((path, _, __) async {
      waitedFor = path;
      expect(announced, isTrue);
      File(exe).writeAsStringSync('0.9.98+99800');
      return true;
    });

    final state = await installer.installWithWizard(
      release: _release(),
      installerPath: setup,
      installDir: installDir,
      locateInstalled: (_) async => null,
      detectTimeout: Duration.zero,
      onSetupContinuesElsewhere: () => announced = true,
    );

    expect(waitedFor, setup);
    expect(state.launchPath, exe);
    expect(state.installedTagName, _tag);
  });

  test('המתקין שהופעל מחדש עדיין רץ בתום ההמתנה — עדיין פתוח', () async {
    final installer = installerWith((_, __, ___) async => false);

    await expectLater(
      installer.installWithWizard(
        release: _release(),
        installerPath: setup,
        installDir: installDir,
        locateInstalled: (_) async => null,
        detectTimeout: Duration.zero,
      ),
      throwsA(
        isA<OtzariaWizardStillOpen>()
            .having((e) => e.setupExited, 'setupExited', isFalse),
      ),
    );
  });

  test('אין מתקין שהופעל מחדש וההתקנה לא השתנתה — נסגר בלי להתקין', () async {
    final installer = installerWith((_, __, ___) async => null);

    await expectLater(
      installer.installWithWizard(
        release: _release(),
        installerPath: setup,
        installDir: installDir,
        locateInstalled: (_) async => null,
        detectTimeout: Duration.zero,
      ),
      throwsA(
        isA<OtzariaWizardStillOpen>()
            .having((e) => e.setupExited, 'setupExited', isTrue),
      ),
    );
  });

  test('exit 2 כשהאשף שוגר מחדש לכל המשתמשים: ממתינים לו (#2677)', () async {
    final relaunched = await _exitScript(
      temp.path,
      exitCode: 2,
      name: 'mode-change',
    );
    var announced = false;
    final installer = installerWith((_, timeout, __) async {
      if (timeout == Duration.zero) return false;
      File(exe).writeAsStringSync('0.9.98+99800');
      return true;
    });

    final state = await installer.installWithWizard(
      release: _release(),
      installerPath: relaunched,
      installDir: installDir,
      locateInstalled: (_) async => null,
      detectTimeout: Duration.zero,
      onSetupContinuesElsewhere: () => announced = true,
    );

    expect(announced, isTrue);
    expect(state.launchPath, exe);
  });

  test('exit 2 בלי אשף שרץ עדיין — ביטול', () async {
    final cancelled = await _exitScript(
      temp.path,
      exitCode: 2,
      name: 'cancelled',
    );
    final installer = installerWith((_, __, ___) async => null);

    await expectLater(
      installer.installWithWizard(
        release: _release(),
        installerPath: cancelled,
        installDir: installDir,
        locateInstalled: (_) async => null,
        detectTimeout: Duration.zero,
      ),
      throwsA(isA<OtzariaInstallCancelled>()),
    );
  });

  test('exit 0 אינו ממתין למתקין נוסף', () async {
    var waited = false;
    final finished = await _exitScript(
      temp.path,
      exitCode: 0,
      name: 'finished',
    );
    File(exe).writeAsStringSync('0.9.98+99800');
    final installer = installerWith((_, __, ___) async {
      waited = true;
      return true;
    });

    await installer.installWithWizard(
      release: _release(),
      installerPath: finished,
      installDir: installDir,
      locateInstalled: (_) async => null,
      detectTimeout: Duration.zero,
    );

    expect(waited, isFalse);
  });

  for (final elevated in [true, false]) {
    test(
      'התקנה חדשה מתהליך ${elevated ? 'מורם' : 'רגיל'}: /CURRENTUSER ${elevated ? 'נמסר' : 'אינו נמסר'} לאשף',
      () async {
        final argsFile = p.join(temp.path, 'args.txt');
        final recorder = p.join(temp.path, 'record.bat');
        File(recorder).writeAsStringSync(
          '@echo off\r\necho %* > "$argsFile"\r\nexit /b 2\r\n',
        );
        final installer = OtzariaInstaller(
          cacheDir: p.join(temp.path, 'cache'),
          isElevated: () => elevated,
        );

        await expectLater(
          installer.installWithWizard(
            release: _release(),
            installerPath: recorder,
            locateInstalled: (_) async => null,
          ),
          throwsA(isA<OtzariaInstallCancelled>()),
        );

        final args = File(argsFile).readAsStringSync();
        expect(args, contains('/NOLAUNCH=1'));
        expect(args.contains('/CURRENTUSER'), elevated);
      },
      testOn: 'windows',
    );

    for (final allUsers in [false, true]) {
      test(
        'known ${allUsers ? 'all-users' : 'per-user'} install keeps the wizard '
        'from an ${elevated ? 'elevated' : 'unelevated'} launcher (#177)',
        () async {
          if (allUsers) {
            File(p.join(
              installDir,
              OtzariaInstaller.systemInstallMarkerFileName,
            )).writeAsStringSync('');
          }
          final argsFile = p.join(temp.path, 'args.txt');
          final recorder = p.join(temp.path, 'record.bat');
          File(recorder).writeAsStringSync(
            '@echo off\r\necho %* > "$argsFile"\r\nexit /b 2\r\n',
          );
          final installer = OtzariaInstaller(
            cacheDir: p.join(temp.path, 'cache'),
            versionReader: const _FileContentVersionReader(),
            isElevated: () => elevated,
            waitForRelaunchedSetup: (_, __, ___) async => null,
          );
          addTearDown(installer.dispose);

          await expectLater(
            installer.installWithWizard(
              release: _release(),
              installerPath: recorder,
              installDir: installDir,
              locateInstalled: (_) async => null,
            ),
            throwsA(isA<OtzariaInstallCancelled>()),
          );

          final args = File(argsFile).readAsStringSync();
          expect(args.contains('/CURRENTUSER'), !allUsers);
          expect(args.contains('/ALLUSERS'), allUsers);
          expect(args, contains('/DIR=$installDir'));
          expect(args, contains('/NOLAUNCH=1'));
          expect(args, isNot(contains('/SILENT')));
          expect(args, isNot(contains('/VERYSILENT')));
          expect(args, isNot(contains('/MERGETASKS')));
        },
        testOn: 'windows',
      );
    }
  }

  test(
    'legacy custom install leaves scope detection to the wizard (#177)',
    () async {
      File(exe).writeAsStringSync('0.9.70');
      final argsFile = p.join(temp.path, 'args.txt');
      final recorder = p.join(temp.path, 'record.bat');
      File(recorder).writeAsStringSync(
        '@echo off\r\necho %* > "$argsFile"\r\nexit /b 2\r\n',
      );
      final installer = OtzariaInstaller(
        cacheDir: p.join(temp.path, 'cache'),
        versionReader: const _FileContentVersionReader(),
        isElevated: () => false,
        waitForRelaunchedSetup: (_, __, ___) async => null,
      );
      addTearDown(installer.dispose);

      await expectLater(
        installer.installWithWizard(
          release: _release(),
          installerPath: recorder,
          installDir: installDir,
          locateInstalled: (_) async => null,
        ),
        throwsA(isA<OtzariaInstallCancelled>()),
      );

      final args = File(argsFile).readAsStringSync();
      expect(args, isNot(contains('/CURRENTUSER')));
      expect(args, isNot(contains('/ALLUSERS')));
      expect(args, contains('/DIR=$installDir'));
    },
    testOn: 'windows',
  );

  test('ביטול ההמתנה מפסיק להמתין בלי לטעון שהמתקין נסגר', () async {
    var cancelled = false;
    final installer = installerWith((_, __, isCancelled) async {
      cancelled = isCancelled();
      return false;
    });

    await expectLater(
      installer.installWithWizard(
        release: _release(),
        installerPath: setup,
        installDir: installDir,
        locateInstalled: (_) async => null,
        isWaitCancelled: () => true,
      ),
      throwsA(
        isA<OtzariaWizardStillOpen>()
            .having((e) => e.setupExited, 'setupExited', isFalse),
      ),
    );
    expect(cancelled, isTrue);
  });

  test('ההמתנה למתקין שרץ נעצרת כשמבטלים', () async {
    final started = DateTime.now();
    final result = await RunningOtzariaLocator.waitForImageToExit(
      RunningOtzariaLocator.windowsImagePathOfPid(pid) ??
          Platform.resolvedExecutable,
      const Duration(minutes: 5),
      () => DateTime.now().difference(started) > const Duration(seconds: 1),
      pollInterval: const Duration(milliseconds: 200),
    );
    if (Platform.isWindows) {
      expect(result, isFalse);
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 10)),
      );
    }
  });

  test('C:\\אוצריא בלי סמן נשאר התקנת מנהל, כמו ב-otzaria.iss', () {
    expect(
      OtzariaInstaller.windowsInstallScopeOf(
        r'C:\אוצריא',
        environment: const {},
      ),
      OtzariaWindowsInstallScope.allUsers,
    );
  });

  test('האשף מקבל /NOLAUNCH=1, שמתקין חדש מעביר להפעלה השקטה', () {
    final source = File(
      p.join('lib', 'src', 'services', 'otzaria_installer.dart'),
    ).readAsStringSync();
    final body = source.substring(
      source.indexOf('Future<OtzariaInstallState> installWithWizard('),
      source.indexOf('static const Duration wizardDetectTimeout'),
    );
    expect(body, contains("'/NOLAUNCH=1'"));
  });
}

Future<String> _exitScript(
  String dir, {
  required int exitCode,
  String name = 'fake-setup',
}) async {
  if (Platform.isWindows) {
    final path = p.join(dir, '$name.bat');
    await File(path).writeAsString('@echo off\r\nexit /b $exitCode\r\n');
    return path;
  }
  final path = p.join(dir, '$name.sh');
  await File(path).writeAsString('#!/bin/sh\nexit $exitCode\n');
  await Process.run('chmod', ['+x', path]);
  return path;
}

class _FileContentVersionReader implements InstalledVersionReader {
  const _FileContentVersionReader();

  @override
  String? readVersion(String launchPath) {
    final file = File(launchPath);
    return file.existsSync() ? file.readAsStringSync().trim() : null;
  }
}
