import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _bytes = 'inno-setup-installer-bytes';

OtzariaRelease _release({
  String tag = '0.9.96+736',
  String? sha256,
  int? size,
  String assetName = 'otzaria-0.9.96-windows.exe',
}) =>
    OtzariaRelease(
      tagName: tag,
      name: 'Otzaria $tag',
      isPrerelease: false,
      isDraft: false,
      publishedAt: null,
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: assetName,
      installerDownloadUrl: 'https://example/$assetName',
      installerSizeBytes: size ?? _bytes.length,
      installerSha256: sha256,
    );

String _digestOf(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  late Directory temp;
  late String cacheDir;
  late int requests;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-hardening-');
    cacheDir = p.join(temp.path, 'mirror', 'installers');
    requests = 0;
  });

  tearDown(() async => temp.delete(recursive: true));

  OtzariaInstaller installerWith(http.Client client) => OtzariaInstaller(
        cacheDir: cacheDir,
        httpClient: client,
        appLocator: const OtzariaAppLocator(
          platform: OtzariaTargetPlatform.windows,
        ),
      );

  http.Client serving(String body) => MockClient((_) async {
        requests++;
        return http.Response(body, 200);
      });

  OtzariaAppMirror mirrorOver(String dir) => OtzariaAppMirror(
        mirrorDir: dir,
        platform: OtzariaTargetPlatform.windows,
        releaseClient: OtzariaReleaseClient(
          platform: OtzariaTargetPlatform.windows,
        ),
        installer: installerWith(serving(_bytes)),
      );

  group('OtzariaAppMirror.load - installerPath confinement', () {
    Future<void> writeMirror(String mirrorDir, String relative) async {
      await Directory(mirrorDir).create(recursive: true);
      final release = _release();
      final json = {
        'schemaVersion': 3,
        'source': 'github-latest',
        'latest': release.toJson()..['installerPath'] = relative,
      };
      await File(
        p.join(mirrorDir, 'latest-release.json'),
      ).writeAsString(_encodeLatestFixture(json));
    }

    test('a path escaping the mirror directory is treated as missing',
        () async {
      final mirrorDir = p.join(temp.path, 'mirror', 'app');
      final outside = File(p.join(temp.path, 'mirror', 'evil.exe'));
      await outside.create(recursive: true);
      await outside.writeAsString(_bytes);
      await writeMirror(mirrorDir, '../evil.exe');

      expect((await mirrorOver(mirrorDir).load()).latest, isNull);
    });

    test('a nested relative path still loads', () async {
      final mirrorDir = p.join(temp.path, 'mirror', 'app');
      final nested = File(p.join(mirrorDir, 'installers', 'x', 'a.exe'));
      await nested.create(recursive: true);
      await nested.writeAsString(_bytes);
      await writeMirror(mirrorDir, 'installers/x/a.exe');

      expect((await mirrorOver(mirrorDir).load()).latest, isNotNull);
    });
  });

  group('cache path segments', () {
    test('Windows separators cannot escape the installer cache', () async {
      expect(OtzariaInstaller.cacheSegment(r'..\..\outside'),
          isNot(contains(r'\')));
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);

      final path = await installer.ensureCached(
        release: _release(
          tag: r'..\..\outside',
          assetName: r'..\..\setup.exe',
        ),
      );

      expect(p.isWithin(cacheDir, p.normalize(path)), isTrue);
      expect(p.dirname(p.dirname(path)), cacheDir);
    });

    test('a tag containing a separator stays one directory in the cache',
        () async {
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);

      final path = await installer.ensureCached(
        release: _release(tag: '1.0/../../x'),
      );

      expect(p.isWithin(cacheDir, path), isTrue);
      expect(p.dirname(p.dirname(path)), cacheDir);
    });

    test('prune keeps the directory of a tag that needed sanitizing', () async {
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);
      await installer.ensureCached(release: _release(tag: 'a/b'));

      await installer.pruneCacheExcept(keepTagNames: {'a/b'});

      expect(Directory(cacheDir).listSync(), hasLength(1));
    });

    test('a dot-only name cannot address the parent', () {
      expect(OtzariaInstaller.cacheSegment('..'), isNot('..'));
      expect(OtzariaInstaller.cacheSegment(''), isNotEmpty);
    });
  });

  group('installer digest', () {
    test('normalizedSha256 accepts the GitHub digest form only', () {
      final hex = _digestOf('x');
      expect(OtzariaRelease.normalizedSha256('sha256:$hex'), hex);
      expect(OtzariaRelease.normalizedSha256('sha256:abc'), isNull);
      expect(OtzariaRelease.normalizedSha256(null), isNull);
    });

    test('digest survives the mirror metadata round trip', () {
      final release = _release(sha256: _digestOf(_bytes));
      expect(OtzariaRelease.fromJson(release.toJson()), release);
      expect(
        OtzariaRelease.fromJson(_release().toJson()).installerSha256,
        isNull,
      );
    });

    test('the release client reads the asset digest', () async {
      final hex = _digestOf(_bytes);
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: MockClient(
          (_) async => http.Response(
            _encodeLatestFixture([
              {
                'tag_name': '1.0.0',
                'prerelease': false,
                'draft': false,
                'assets': [
                  {
                    'name': 'otzaria-1.0.0-windows.exe',
                    'browser_download_url': 'u',
                    'size': 5,
                    'digest': 'sha256:$hex',
                  },
                ],
              },
            ]),
            200,
          ),
        ),
      );

      final releases = await client.fetchLatestRelease();

      expect(releases.latest!.installerSha256, hex);
    });

    test('a download that does not match the digest fails and leaves nothing',
        () async {
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);

      await expectLater(
        installer.ensureCached(release: _release(sha256: _digestOf('other'))),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.appDomain.installerDigestMismatch,
          ),
        ),
      );
      expect(
        Directory(cacheDir).listSync(recursive: true).whereType<File>(),
        isEmpty,
      );
    });

    test('a matching digest downloads normally', () async {
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);

      final path = await installer.ensureCached(
        release: _release(sha256: _digestOf(_bytes)),
      );

      expect(File(path).readAsStringSync(), _bytes);
    });

    test('a cached file of the right size but wrong content is re-downloaded',
        () async {
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);
      final release = _release(sha256: _digestOf(_bytes));
      final path = p.join(
        cacheDir,
        release.tagName,
        release.installerAssetName,
      );
      await File(path).create(recursive: true);
      await File(path).writeAsString('X' * _bytes.length);

      await installer.ensureCached(release: release);

      expect(requests, 1);
      expect(File(path).readAsStringSync(), _bytes);
    });

    test('installing a file that does not match the digest is refused',
        () async {
      final installer = installerWith(serving(_bytes));
      addTearDown(installer.dispose);
      final file = File(p.join(temp.path, 'setup.exe'));
      await file.writeAsString('tampered-installer-bytes!');

      await expectLater(
        installer.installFromFile(
          release: _release(sha256: _digestOf(_bytes)),
          installerPath: file.path,
          installDir: p.join(temp.path, 'app'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.appDomain.installerDigestMismatch,
          ),
        ),
      );
    });
  });

  group('OtzariaProcessCloser', () {
    test('the launcher itself is never a taskkill target', () {
      const self = r'C:\launcher\otzaria.exe';
      final paths = {1: r'C:\Otzaria\otzaria.exe', 2: self};

      final pids = OtzariaProcessCloser.pidsToClose(
        [1, 2, 3],
        imagePathOf: (pid) => paths[pid],
        selfPath: self,
      );

      expect(pids, [1, 3]);
    });

    test('the macOS bundle path is an argv argument, never script text', () {
      const hostile = '/Apps/x" to quit\ndo shell script "id';

      final args = OtzariaProcessCloser.macQuitArguments(hostile);

      expect(args.last, hostile);
      expect(
        args.take(args.length - 1).any((a) => a.contains(hostile)),
        isFalse,
      );
    });
  });
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
