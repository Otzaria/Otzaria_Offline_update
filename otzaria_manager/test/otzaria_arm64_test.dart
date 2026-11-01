import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/sandbox.dart';

const _bytes = 'installer-bytes';

Map<String, dynamic> _releaseJson(
  String tag, {
  required bool prerelease,
  bool withArm64 = true,
}) =>
    {
      'tag_name': tag,
      'name': 'Otzaria $tag',
      'prerelease': prerelease,
      'draft': false,
      'published_at': '2026-01-01T00:00:00Z',
      'body': '',
      'assets': [
        {
          'name': 'otzaria-$tag-windows.exe',
          'browser_download_url': 'https://example/$tag/x64.exe',
          'size': _bytes.length,
        },
        if (withArm64)
          {
            'name': 'otzaria-$tag-windows_arm64.exe',
            'browser_download_url': 'https://example/$tag/arm64.exe',
            'size': _bytes.length,
          },
        {
          'name': 'otzaria-$tag-windows_arm64-full.exe',
          'browser_download_url': 'https://example/$tag/arm64-full.exe',
          'size': 99,
        },
      ],
    };

Uint8List _peHeader(int machine) {
  final bytes = ByteData(0x80 + 6);
  bytes.setUint8(0, 0x4d);
  bytes.setUint8(1, 0x5a);
  bytes.setUint32(0x3c, 0x80, Endian.little);
  bytes.setUint8(0x80, 0x50);
  bytes.setUint8(0x81, 0x45);
  bytes.setUint16(0x84, machine, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  sandboxRealDataRoot();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-arm64-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('בחירת אסט לפי ארכיטקטורה', () {
    const selector = OtzariaAssetSelector();
    const names = [
      'otzaria-1.0.0-windows_arm64-full.exe',
      'otzaria-1.0.0-windows_arm64.exe',
      'otzaria-1.0.0-windows.exe',
    ];

    String? pick(OtzariaArch arch) => selector
        .select(
          platform: OtzariaTargetPlatform.windows,
          assets: names,
          nameOf: (n) => n,
          arch: arch,
        )
        ?.$1;

    test('x64 לעולם אינו בוחר את מתקין ה-ARM64', () {
      expect(pick(OtzariaArch.x64), 'otzaria-1.0.0-windows.exe');
    });

    test('ARM64 בוחר את המתקין הייעודי ולא את חבילת ה-FULL', () {
      expect(pick(OtzariaArch.arm64), 'otzaria-1.0.0-windows_arm64.exe');
      expect(
        OtzariaAssetSelector.isFullPackage(
          'otzaria-1.0.0-windows_arm64-full.exe',
        ),
        isTrue,
      );
    });
  });

  group('WindowsArch', () {
    test('משתני הסביבה: PROCESSOR_ARCHITEW6432 קודם', () {
      expect(
        WindowsArch.machineFromEnvironment({
          'PROCESSOR_ARCHITECTURE': 'x86',
          'PROCESSOR_ARCHITEW6432': 'ARM64',
        }),
        OtzariaArch.arm64,
      );
      expect(
        WindowsArch.machineFromEnvironment({'PROCESSOR_ARCHITECTURE': 'AMD64'}),
        OtzariaArch.x64,
      );
    });

    test('קורא את ארכיטקטורת ה-exe מכותרת ה-PE', () {
      final x64 = File(p.join(temp.path, 'x64.exe'))
        ..writeAsBytesSync(_peHeader(0x8664));
      final arm = File(p.join(temp.path, 'arm.exe'))
        ..writeAsBytesSync(_peHeader(0xAA64));
      final text = File(p.join(temp.path, 'text.exe'))
        ..writeAsStringSync('not a pe');

      expect(WindowsArch.ofExecutable(x64.path), OtzariaArch.x64);
      expect(WindowsArch.ofExecutable(arm.path), OtzariaArch.arm64);
      expect(WindowsArch.ofExecutable(text.path), isNull);
      expect(WindowsArch.ofExecutable(p.join(temp.path, 'none.exe')), isNull);
    });

    test(
      'מחשב x64 מזוהה כ-x64 דרך IsWow64Process2',
      () {
        final identifier = Platform.environment['PROCESSOR_IDENTIFIER'] ?? '';
        if (identifier.toUpperCase().contains('ARM')) {
          expect(WindowsArch.machine(), OtzariaArch.arm64);
        } else {
          expect(WindowsArch.machine(), OtzariaArch.x64);
        }
      },
      testOn: 'windows',
    );
  });

  group('המראה מביאה את שתי הארכיטקטורות', () {
    OtzariaAppMirror mirrorWith(List<Map<String, dynamic>> releases) =>
        OtzariaAppMirror(
          mirrorDir: temp.path,
          platform: OtzariaTargetPlatform.windows,
          releaseClient: OtzariaReleaseClient(
            platform: OtzariaTargetPlatform.windows,
            httpClient: MockClient(
              (_) async => http.Response(
                _encodeLatestFixture(releases),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              ),
            ),
          ),
          installer: OtzariaInstaller(
            cacheDir: p.join(temp.path, 'installers'),
            httpClient: MockClient((_) async => http.Response(_bytes, 200)),
            appLocator: const OtzariaAppLocator(
              platform: OtzariaTargetPlatform.windows,
            ),
          ),
          changelogClient: OtzariaChangelogClient(
            httpClient: MockClient((_) async => http.Response('', 404)),
          ),
        );

    test('release בלי מתקין ARM64 נרשם ואינו דורש הורדה חוזרת', () async {
      final mirror = mirrorWith([
        _releaseJson('1.0.0', prerelease: false, withArm64: false),
      ]);

      await mirror.sync();

      expect((await mirror.load(arch: OtzariaArch.arm64)).isEmpty, isTrue);
      expect(await mirror.lacksArm64Installers(), isFalse);
    });

    test('מראה ישנה בלי ARM64 מסומנת כחסרה', () async {
      final mirror = mirrorWith([
        _releaseJson('1.0.0', prerelease: false),
      ]);
      await mirror.sync();
      final file = File(p.join(temp.path, 'latest-release.json'));
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      (json['platforms'] as Map).remove('windows_arm64');
      file.writeAsStringSync(_encodeLatestFixture(json));

      expect(await mirror.lacksArm64Installers(), isTrue);
    });
  });

  group('OtzariaManager במחשב ARM64', () {
    Future<void> writeMirror({required bool withArm64}) async {
      final mirrorDir = p.join(temp.path, 'data', 'mirror', 'app');
      final mirror = OtzariaAppMirror(
        mirrorDir: mirrorDir,
        platform: OtzariaTargetPlatform.windows,
        releaseClient: OtzariaReleaseClient(
          platform: OtzariaTargetPlatform.windows,
          httpClient: MockClient(
            (_) async => http.Response(
              _encodeLatestFixture([
                _releaseJson('2.0.0', prerelease: false, withArm64: withArm64),
              ]),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            ),
          ),
        ),
        installer: OtzariaInstaller(
          cacheDir: p.join(mirrorDir, 'installers'),
          httpClient: MockClient((_) async => http.Response(_bytes, 200)),
        ),
        changelogClient: OtzariaChangelogClient(
          httpClient: MockClient((_) async => http.Response('', 404)),
        ),
      );
      await mirror.sync();
    }

    OtzariaManager managerFor({String? installedExe, OtzariaArch? exeArch}) {
      final manager = OtzariaManager(
        dataDir: p.join(temp.path, 'data'),
        platform: OtzariaTargetPlatform.windows,
        environment: const {},
        runningLocator: _RunningFrom(installedExe),
        installRegistry: const _NoRegistry(),
        versionReader: const _FileContentVersionReader(),
        machineArch: OtzariaArch.arm64,
        exeArchOf: (_) => exeArch,
      );
      addTearDown(manager.dispose);
      return manager;
    }

    String installedExe() {
      final dir = Directory(p.join(temp.path, 'install'))
        ..createSync(recursive: true);
      return (File(p.join(dir.path, 'otzaria.exe'))..writeAsStringSync('1.0.0'))
          .path;
    }

    test('מתקין ARM64 כשיש כזה במראה', () async {
      await writeMirror(withArm64: true);

      final check = await managerFor(
        installedExe: installedExe(),
        exeArch: OtzariaArch.x64,
      ).checkForUpdate();

      expect(check.latestRelease!.installerArch, OtzariaArch.arm64);
    });

    test('ARM64 ישן במראה אינו גובר על x64 חדש בהתקנה שאינה ARM64', () async {
      await writeMirror(withArm64: true);
      final mirrorFile = File(
        p.join(temp.path, 'data', 'mirror', 'app', 'latest-release.json'),
      );
      final json =
          jsonDecode(mirrorFile.readAsStringSync()) as Map<String, dynamic>;
      final arm = (json['platforms'] as Map)['windows_arm64'] as Map;
      (arm['latest'] as Map)['tagName'] = '1.5.0';
      mirrorFile.writeAsStringSync(_encodeLatestFixture(json));

      final x64Check = await managerFor(
        installedExe: installedExe(),
        exeArch: OtzariaArch.x64,
      ).checkForUpdate();
      expect(x64Check.latestRelease!.tagName, '2.0.0');
      expect(x64Check.latestRelease!.installerArch, OtzariaArch.x64);
    });

    test('התקנת ARM64 אינה מוחלפת ב-x64', () async {
      await writeMirror(withArm64: false);

      final check = await managerFor(
        installedExe: installedExe(),
        exeArch: OtzariaArch.arm64,
      ).checkForUpdate();

      expect(check.latestRelease, isNull);
      expect(check.updateAvailable, isFalse);
    });

    test('התקנה חדשה נופלת ל-x64 כשאין ARM64', () async {
      await writeMirror(withArm64: false);

      final check = await managerFor().checkForUpdate();

      expect(check.latestRelease!.installerArch, OtzariaArch.x64);
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

  final String? path;

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: path != null, launchPath: path);
}

class _NoRegistry extends WindowsInstallRegistry {
  const _NoRegistry();

  @override
  Future<List<String>> otzariaInstallDirs() async => const [];
}

String _encodeLatestFixture(Object? value) {
  if (value is List &&
      value.isNotEmpty &&
      value.first is Map &&
      (value.first as Map).containsKey('tag_name')) {
    final candidates = value
        .whereType<Map>()
        .where((r) => r['prerelease'] != true && r['draft'] != true);
    value = candidates.isEmpty ? value.first : candidates.first;
  }
  return jsonEncode(value);
}
