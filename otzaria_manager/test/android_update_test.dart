import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/android_fixtures.dart';

Matcher fails(AndroidUpdateFailure failure) => throwsA(
    isA<AndroidUpdateException>().having((e) => e.failure, 'failure', failure));

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('android-update-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  for (final compressed in [false, true]) {
    for (final utf8Pool in [false, true]) {
      test('reads APK manifest and ABIs (deflate=$compressed utf8=$utf8Pool)',
          () async {
        final apk = File(p.join(temp.path, 'test.apk'));
        await apk.writeAsBytes(androidApk(
            compressed: compressed,
            utf8Pool: utf8Pool,
            abis: ['arm64-v8a', 'armeabi-v7a', 'x86_64']));
        final info = await const ApkInspector().inspect(apk.path);
        expect(info.applicationId, otzariaAndroidApplicationId);
        expect(info.versionCode, 20);
        expect(info.minSdk, 24);
        expect(info.targetSdk, 36);
        expect(info.abis, ['arm64-v8a', 'armeabi-v7a', 'x86_64']);
      });
    }
  }

  test('rejects foreign package, truncated ZIP and oversized manifest',
      () async {
    final file = File(p.join(temp.path, 'invalid.apk'));
    for (final bytes in [
      androidApk(applicationId: 'other.application'),
      androidApk().sublist(0, 40),
      zipEntries({
        'AndroidManifest.xml': Uint8List(ApkInspector.maxManifestBytes + 1)
      }),
    ]) {
      await file.writeAsBytes(bytes);
      await expectLater(const ApkInspector().inspect(file.path),
          fails(AndroidUpdateFailure.invalidApk));
    }
  });

  test('limits inflated manifest even when ZIP reports a smaller size',
      () async {
    final bytes = zipEntries(
        {'AndroidManifest.xml': Uint8List(ApkInspector.maxManifestBytes * 2)});
    final view = ByteData.sublistView(bytes);
    final central = view.getUint32(bytes.length - 6, Endian.little);
    view.setUint32(central + 24, 1, Endian.little);
    final file = File(p.join(temp.path, 'oversized-inflated.apk'));
    await file.writeAsBytes(bytes);
    await expectLater(const ApkInspector().inspect(file.path),
        fails(AndroidUpdateFailure.invalidApk));
  });

  for (final name in ['otzaria-android.apk', 'app-release.apk']) {
    test('downloads $name and installs selected device without network',
        () async {
      final harness = _Harness(temp.path, assetName: name);
      addTearDown(harness.manager.dispose);
      final mirror =
          await harness.manager.downloadLatest(AndroidCancellation());
      expect(mirror.info.versionCode, 20);
      final networkRequests = harness.requests.length;
      await harness.prepareTools();
      final installed =
          await harness.manager.install('second', AndroidCancellation());
      expect(installed.versionCode, 20);
      expect(harness.requests.length, networkRequests);
      final install =
          harness.runner.calls.singleWhere((c) => c.contains('install'));
      expect(install.sublist(1, 7),
          ['-s', 'second', 'install', '-r', '--user', '0']);
      expect(install.last, mirror.apkPath);
      expect(
          harness.runner.calls.any((c) =>
              c.contains('uninstall') ||
              c.contains('clear') ||
              c.contains('-d')),
          isFalse);
    });
  }

  test('prefers named APK, validates sidecar against actual manifest',
      () async {
    final harness = _Harness(temp.path, sidecar: true, addLegacy: true);
    addTearDown(harness.manager.dispose);
    final firstRelease =
        await harness.manager.downloadLatest(AndroidCancellation());
    expect(harness.requests.any((url) => url.endsWith('app-release.apk')),
        isFalse);
    harness.sidecarVersion = 21;
    harness.assetId = 3;
    await expectLater(harness.manager.downloadLatest(AndroidCancellation()),
        fails(AndroidUpdateFailure.invalidApk));
    expect((await harness.manager.loadMirror())!.info.versionCode, 20);
    expect(await File(firstRelease.apkPath).exists(), isTrue);
    harness.sidecarVersion = 20;
    final nextRelease =
        await harness.manager.downloadLatest(AndroidCancellation());
    expect(await File(nextRelease.apkPath).exists(), isTrue);
    expect(await File(firstRelease.apkPath).exists(), isFalse);
  });

  test('rejects modified cached APK before executing an installation',
      () async {
    final harness = _Harness(temp.path);
    addTearDown(harness.manager.dispose);
    final release = await harness.manager.downloadLatest(AndroidCancellation());
    await harness.prepareTools();
    final bytes = await File(release.apkPath).readAsBytes();
    bytes[100] ^= 1;
    await File(release.apkPath).writeAsBytes(bytes);
    await expectLater(harness.manager.install('first', AndroidCancellation()),
        fails(AndroidUpdateFailure.digestMismatch));
    expect(harness.runner.calls.any((c) => c.contains('install')), isFalse);
  });

  test('uses versionCode and refuses downgrade, SDK and ABI mismatch',
      () async {
    final harness = _Harness(temp.path);
    addTearDown(harness.manager.dispose);
    await harness.manager.downloadLatest(AndroidCancellation());
    await harness.prepareTools();
    harness.runner.installedVersion = 21;
    await expectLater(harness.manager.install('first', AndroidCancellation()),
        fails(AndroidUpdateFailure.downgrade));
    harness.runner.installedVersion = 10;
    harness.runner.sdk = 23;
    await expectLater(harness.manager.install('first', AndroidCancellation()),
        fails(AndroidUpdateFailure.incompatibleSdk));
    harness.runner.sdk = 36;
    harness.runner.abi = 'x86';
    await expectLater(harness.manager.install('first', AndroidCancellation()),
        fails(AndroidUpdateFailure.incompatibleAbi));
    expect(harness.runner.calls.any((c) => c.contains('install')), isFalse);
  });

  test('signature rejection preserves installation and never tries uninstall',
      () async {
    final harness = _Harness(temp.path);
    addTearDown(harness.manager.dispose);
    await harness.manager.downloadLatest(AndroidCancellation());
    await harness.prepareTools();
    harness.runner.installFailure = 'INSTALL_FAILED_UPDATE_INCOMPATIBLE';
    await expectLater(harness.manager.install('first', AndroidCancellation()),
        fails(AndroidUpdateFailure.signatureMismatch));
    expect(harness.runner.installedVersion, 10);
    expect(
        harness.runner.calls.where((c) => c.contains('install')), hasLength(1));
    expect(harness.runner.calls.any((c) => c.contains('uninstall')), isFalse);
  });

  test('unauthorized and disconnected targets cannot install', () async {
    final harness = _Harness(temp.path);
    addTearDown(harness.manager.dispose);
    await harness.manager.downloadLatest(AndroidCancellation());
    await harness.prepareTools();
    harness.runner.devicesOutput =
        'List of devices attached\nfirst unauthorized\n';
    await expectLater(harness.manager.install('first', AndroidCancellation()),
        fails(AndroidUpdateFailure.unauthorized));
    await expectLater(harness.manager.install('second', AndroidCancellation()),
        fails(AndroidUpdateFailure.deviceUnavailable));
    expect(harness.runner.calls.any((c) => c.contains('install')), isFalse);
  });

  test(
      'read-only mirror permits install and export, blocks downloads and tool copying',
      () async {
    final harness = _Harness(p.join(temp.path, 'drive'));
    addTearDown(harness.manager.dispose);
    final release = await harness.manager.downloadLatest(AndroidCancellation());
    final tools = await harness.prepareTools();
    final before =
        await File(p.join(harness.manager.mirrorDir, 'latest-release.json'))
            .readAsBytes();
    final offline = AndroidUpdateManager(
        dataDir: harness.root,
        stateDir: p.join(temp.path, 'machine-state'),
        readOnly: true,
        operatingSystem: 'windows',
        machineKey: 'machine',
        runner: harness.runner,
        httpClient: MockClient((_) => throw StateError('offline request')));
    addTearDown(offline.dispose);
    await offline.selectTools(tools, AndroidCancellation());
    expect(
        await File(p.join(temp.path, 'machine-state', 'android_tools.json'))
            .exists(),
        isTrue);
    await offline.install('first', AndroidCancellation());
    final exported = p.join(temp.path, 'exported.apk');
    await offline.exportApk(exported, AndroidCancellation());
    expect(await androidFileSha256(File(exported), AndroidCancellation()),
        release.sha256);
    expect(
        await File(p.join(offline.mirrorDir, 'latest-release.json'))
            .readAsBytes(),
        before);
    await expectLater(offline.downloadLatest(AndroidCancellation()),
        fails(AndroidUpdateFailure.readOnly));
    await expectLater(
        offline.selectTools(tools, AndroidCancellation(), copyToDrive: true),
        fails(AndroidUpdateFailure.readOnly));
    await expectLater(offline.exportApk(release.apkPath, AndroidCancellation()),
        fails(AndroidUpdateFailure.exportTarget));
  });

  test('portable ADB copy includes DLLs and local choice is per machine',
      () async {
    final harness = _Harness(temp.path);
    addTearDown(harness.manager.dispose);
    final source = await harness.prepareTools();
    final copied = await harness.manager
        .selectTools(source, AndroidCancellation(), copyToDrive: true);
    expect(
        await File(p.join(p.dirname(copied), 'AdbWinApi.dll')).readAsString(),
        'fixture');
    expect(await File(p.join(p.dirname(copied), 'AdbWinUsbApi.dll')).exists(),
        isTrue);
    await Directory(source).delete(recursive: true);
    expect(await harness.manager.tools.resolve(), copied);
    final other = AndroidTools(
        mirrorDir: harness.manager.mirrorDir,
        stateDir: p.join(temp.path, 'state'),
        operatingSystem: 'windows',
        machineKey: 'other');
    expect(await other.resolve(), copied);
  });

  test('cancellation and timeout stop the client subprocess', () async {
    final script = File(p.join(temp.path, 'wait.dart'));
    await script.writeAsString(
        'Future<void> main() async { await Future<void>.delayed(const Duration(minutes: 1)); }');
    for (final cancelling in [false, true]) {
      final cancel = AndroidCancellation();
      final timer = cancelling
          ? Timer(const Duration(milliseconds: 100), cancel.cancel)
          : null;
      final clock = Stopwatch()..start();
      await expectLater(
          const AndroidProcessRunner().run(
              Platform.resolvedExecutable, [script.path],
              timeout: cancelling
                  ? const Duration(seconds: 30)
                  : const Duration(milliseconds: 100),
              cancellation: cancel),
          fails(cancelling
              ? AndroidUpdateFailure.cancelled
              : AndroidUpdateFailure.timeout));
      timer?.cancel();
      expect(clock.elapsed, lessThan(const Duration(seconds: 6)));
    }
  });
}

class _Harness {
  _Harness(this.root,
      {this.assetName = 'otzaria-android.apk',
      this.sidecar = false,
      this.addLegacy = false}) {
    manager = AndroidUpdateManager(
        dataDir: root,
        stateDir: p.join(root, 'state'),
        operatingSystem: 'windows',
        machineKey: 'machine',
        runner: runner,
        httpClient: MockClient(_request));
  }
  final String root;
  final String assetName;
  final bool sidecar;
  final bool addLegacy;
  final runner = FakeAndroidRunner();
  final requests = <String>[];
  final apk = androidApk();
  int sidecarVersion = 20;
  int assetId = 1;
  late final AndroidUpdateManager manager;
  String get digest => crypto.sha256.convert(apk).toString();
  List<int> get metadata => utf8.encode(jsonEncode({
        'schemaVersion': 1,
        'applicationId': otzariaAndroidApplicationId,
        'versionCode': sidecarVersion,
        'versionName': '1.0.0',
        'minSdk': 24,
        'targetSdk': 36,
        'abis': ['arm64-v8a'],
        'apk': {'name': assetName, 'size': apk.length, 'sha256': digest},
      }));

  Map<String, Object> _asset(String name, List<int> bytes, int id) => {
        'id': id,
        'name': name,
        'size': bytes.length,
        'state': 'uploaded',
        'browser_download_url':
            'https://github.com/Otzaria/otzaria/releases/download/v1/$name',
        'digest': 'sha256:${crypto.sha256.convert(bytes)}',
      };

  Future<http.Response> _request(http.Request request) async {
    requests.add('${request.url}');
    if (request.url.host == 'api.github.com') {
      return http.Response(
          jsonEncode({
            'tag_name': 'v1',
            'draft': false,
            'prerelease': false,
            'assets': [
              if (addLegacy) _asset('app-release.apk', [1, 2], 99),
              _asset(assetName, apk, assetId),
              if (sidecar)
                _asset('otzaria-android.json', metadata, assetId + 1),
            ],
          }),
          200);
    }
    if (request.url.path.endsWith(assetName)) {
      return http.Response.bytes(apk, 200);
    }
    if (request.url.path.endsWith('otzaria-android.json')) {
      return http.Response.bytes(metadata, 200);
    }
    throw StateError('Unexpected URL: ${request.url}');
  }

  Future<String> prepareTools() async {
    final dir = Directory(p.join(root, 'tools'));
    await dir.create();
    for (final name in ['adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll']) {
      await File(p.join(dir.path, name)).writeAsString('fixture');
    }
    await manager.selectTools(dir.path, AndroidCancellation());
    return dir.path;
  }
}
