import 'dart:convert';
import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/sandbox.dart';

const _bytes = 'installer-bytes';

void main() {
  test('published schema-7 preview does not widen the stable schema-6 release',
      () {
    expect(OtzariaCapabilities.readableDbSchemaForAppVersion('0.9.98+801'), 6);
    expect(
        OtzariaCapabilities.readableDbSchemaForAppVersion('0.9.98.2+807'), 7);
  });
  sandboxRealDataRoot();

  late Directory temp;
  late String mirrorDir;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('readable-schema-test-');
    mirrorDir = p.join(temp.path, 'data', 'mirror', 'app');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Map<String, dynamic> entry(
    String tag, {
    bool prerelease = false,
    OtzariaInstallerKind kind = OtzariaInstallerKind.windowsSetupExe,
    OtzariaArch arch = OtzariaArch.x64,
    bool writeFile = true,
  }) {
    final relative = 'installers/$tag/otzaria-$tag-windows_${arch.name}.exe';
    if (writeFile) {
      File(p.join(mirrorDir, relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(_bytes);
    }
    return OtzariaRelease(
      tagName: tag,
      name: tag,
      isPrerelease: prerelease,
      isDraft: false,
      publishedAt: DateTime.utc(2026),
      installerKind: kind,
      installerAssetName: 'otzaria-$tag-windows.exe',
      installerDownloadUrl: 'https://example/$tag',
      installerSizeBytes: _bytes.length,
      installerArch: arch,
    ).toJson()
      ..['installerPath'] = relative
      ..['newerThanStable'] = prerelease ? '0.9.97+789' : null;
  }

  void writeMirror(Map<String, dynamic> channels) {
    File(p.join(mirrorDir, 'latest-release.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'schemaVersion': 2, ...channels}));
  }

  Future<int?> readable({
    OtzariaArch machine = OtzariaArch.x64,
    OtzariaArch? installedExe,
  }) {
    final dataDir = p.join(temp.path, 'data');
    if (installedExe != null) {
      final exe = File(p.join(temp.path, 'install', 'otzaria.exe'))
        ..createSync(recursive: true);
      File(p.join(dataDir, 'otzaria_install_state.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'installedTagName': '0.9.97+789',
            'installDir': exe.parent.path,
            'launchPath': exe.path,
          }),
        );
    }
    final manager = OtzariaManager(
      dataDir: dataDir,
      platform: OtzariaTargetPlatform.windows,
      environment: const {},
      machineArch: machine,
      exeArchOf: (_) => installedExe,
    );
    addTearDown(manager.dispose);
    return manager.mirroredReadableDbSchema();
  }

  Map<String, dynamic> arm64(Map<String, dynamic> channels) => {
        'platforms': {'windows_arm64': channels},
      };

  group('architecture follows the installer selection rules', () {
    test('an ARM64 machine counts an ARM64-only mirror', () async {
      writeMirror(
        arm64({'stable': entry('0.9.98+801', arch: OtzariaArch.arm64)}),
      );

      expect(await readable(machine: OtzariaArch.arm64), 6);
    });

    test('an x64 machine does not count an ARM64 installer', () async {
      writeMirror(
        arm64({'stable': entry('0.9.98+801', arch: OtzariaArch.arm64)}),
      );

      expect(await readable(), isNull);
    });

    test('an ARM64 machine falls back to x64 without an ARM64 install',
        () async {
      writeMirror({'stable': entry('0.9.98+801')});

      expect(await readable(machine: OtzariaArch.arm64), 6);
    });

    test('a mixed mirror counts the newer of the two on ARM64', () async {
      writeMirror({
        'stable': entry('0.9.98+801'),
        ...arm64({'stable': entry('0.9.97+789', arch: OtzariaArch.arm64)}),
      });

      expect(await readable(machine: OtzariaArch.arm64), 6);
    });

    test('an ARM64 install is never offered the x64 installer', () async {
      writeMirror({
        'stable': entry('0.9.98+801'),
        ...arm64({'stable': entry('0.9.97+789', arch: OtzariaArch.arm64)}),
      });

      expect(
        await readable(
          machine: OtzariaArch.arm64,
          installedExe: OtzariaArch.arm64,
        ),
        5,
      );
    });
  });

  test('no installer on the drive reads nothing', () async {
    expect(await readable(), isNull);
  });

  test('an old installer reads the legacy schema only', () async {
    writeMirror({'stable': entry('0.9.97+789')});

    expect(await readable(), 5);
  });

  test('one suitable installer in either channel is enough', () async {
    writeMirror({
      'stable': entry('0.9.97+789'),
      'prerelease': entry('0.9.98+801', prerelease: true),
    });

    expect(await readable(), 6);
  });

  test('metadata whose installer file is missing does not count', () async {
    writeMirror({
      'stable': entry('0.9.97+789'),
      'prerelease': entry('0.9.98+801', prerelease: true, writeFile: false),
    });

    expect(await readable(), 5);
  });

  test('an installer for another platform does not count', () async {
    writeMirror({
      'stable': entry('0.9.98+801', kind: OtzariaInstallerKind.macAppZip),
    });

    expect(await readable(), isNull);
  });
}
