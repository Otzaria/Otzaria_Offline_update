import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

const _good = 'MZ-v7-bytes';
const _bad = 'MZ-v7-bytez';

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

StoreAppRelease _v7({String? sha256}) => StoreAppRelease(
      tagName: 'v7',
      version: 7,
      assetName: 'Otzaria-Plugin-Store.exe',
      downloadUrl: 'https://example.invalid/v7.exe',
      sizeBytes: _good.length,
      sha256: sha256,
    );

void main() {
  late Directory temp;
  late String mirrorDir;

  setUp(() {
    temp = createTempDir();
    mirrorDir = p.join(temp.path, 'mirror', 'store-app');
  });
  tearDown(() {
    GithubRateLimitGate.shared.reset();
    deleteTempDir(temp);
  });

  String exePath() =>
      p.join(mirrorDir, 'files', 'v7', 'Otzaria-Plugin-Store.exe');

  Map<String, dynamic> metadata() => jsonDecode(
          File(p.join(mirrorDir, 'latest-release.json')).readAsStringSync())
      as Map<String, dynamic>;

  StoreAppMirror mirrorServing(String body, void Function() onRequest) =>
      StoreAppMirror(
        mirrorDir: mirrorDir,
        httpClient: MockClient((_) async {
          onRequest();
          return http.Response.bytes(utf8.encode(body), 200);
        }),
      );

  group('StoreAppReleaseClient.parse', () {
    test('keeps the GitHub digest as lowercase sha256', () {
      final release = StoreAppReleaseClient.parse({
        'tag_name': 'v7',
        'assets': [
          {
            'name': 'Otzaria-Plugin-Store.exe',
            'browser_download_url': 'https://x/basic.exe',
            'size': 627200,
            'digest': 'sha256:ABCDEF',
          },
        ],
      })!;
      expect(release.sha256, 'abcdef');
      expect(release.toJson()['sha256'], 'abcdef');
      expect(StoreAppRelease.fromJson(release.toJson())!.sha256, 'abcdef');
    });

    test('an asset still uploading is skipped', () {
      Map<String, Object?> asset(String name, {String? state, int size = 9}) =>
          {
            'name': name,
            'browser_download_url': 'https://x/$name',
            'size': size,
            if (state != null) 'state': state,
          };
      expect(
        StoreAppReleaseClient.parse({
          'tag_name': 'v7',
          'assets': [asset('Store.exe', state: 'starter')],
        }),
        isNull,
      );
      expect(
        StoreAppReleaseClient.parse({
          'tag_name': 'v7',
          'assets': [asset('Store.exe', size: 0)],
        }),
        isNull,
      );
    });
  });

  test('metadata without a digest still loads, verifies and is not rewritten',
      () async {
    final release = _v7();
    expect(release.toJson().containsKey('sha256'), isFalse);
    expect(StoreAppRelease.fromJson(release.toJson())!.sha256, isNull);

    var requests = 0;
    final mirror = mirrorServing(_good, () => requests++);
    addTearDown(mirror.dispose);
    final synced = await mirror.sync(release);
    expect(metadata()['release'], isNot(contains('sha256')));
    expect(await mirror.verify(synced), isTrue);

    File(exePath()).writeAsStringSync(_bad);
    await mirror.sync(release);
    expect(requests, 1);
    expect((await mirror.load())!.release.sha256, isNull);
  });

  test('a matching download stores the digest in the metadata', () async {
    var requests = 0;
    final mirror = mirrorServing(_good, () => requests++);
    addTearDown(mirror.dispose);

    final synced = await mirror.sync(_v7(sha256: _sha(_good)));
    expect(metadata()['release']['sha256'], _sha(_good));
    expect((await mirror.load())!.release.sha256, _sha(_good));
    expect(await mirror.verify(synced), isTrue);

    await mirror.sync(_v7(sha256: _sha(_good)));
    expect(requests, 1);
  });

  test('a download that does not match the digest is deleted and rejected',
      () async {
    final mirror = mirrorServing(_bad, () {});
    addTearDown(mirror.dispose);

    await expectLater(
      mirror.sync(_v7(sha256: _sha(_good))),
      throwsA(isA<PluginStoreException>()),
    );
    expect(File(exePath()).existsSync(), isFalse);
    expect(
        File(p.join(mirrorDir, 'latest-release.json')).existsSync(), isFalse);
  });

  test(
      'a failed re-download of the recorded version reads as not downloaded, '
      'not as removed', () async {
    final good = mirrorServing(_good, () {});
    addTearDown(good.dispose);
    await good.sync(_v7(sha256: _sha(_good)));
    File(exePath()).writeAsStringSync(_bad);

    final bad = mirrorServing(_bad, () {});
    addTearDown(bad.dispose);
    await expectLater(
      bad.sync(_v7(sha256: _sha(_good))),
      throwsA(isA<PluginStoreException>()),
    );
    expect(File(exePath()).existsSync(), isFalse);
    expect(await bad.load(), isNull);
    expect(await bad.wasRemoved, isFalse);

    final store = PluginMirrorStore(p.join(temp.path, 'mirror'));
    await expectLater(
      StoreAppExporter(store: store, appMirror: bad)
          .exportTo(p.join(temp.path, 'dest')),
      throwsA(
        isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          AppL10n.strings.pluginsDomain.exportAppMissing,
        ),
      ),
    );
  });

  test('a failed download of a newer version keeps the previous one usable',
      () async {
    final v6 = StoreAppRelease(
      tagName: 'v6',
      version: 6,
      assetName: 'Otzaria-Plugin-Store.exe',
      downloadUrl: 'https://example.invalid/v6.exe',
      sizeBytes: _good.length,
      sha256: _sha(_good),
    );
    final good = mirrorServing(_good, () {});
    addTearDown(good.dispose);
    await good.sync(v6);

    final bad = mirrorServing(_bad, () {});
    addTearDown(bad.dispose);
    await expectLater(
      bad.sync(_v7(sha256: _sha(_good))),
      throwsA(isA<PluginStoreException>()),
    );
    final loaded = await bad.load();
    expect(loaded, isNotNull);
    expect(loaded!.release.tagName, 'v6');
    expect(await bad.verify(loaded), isTrue);
    expect(await bad.wasRemoved, isFalse);
  });

  test('a same-size file with the wrong hash is downloaded again', () async {
    File(exePath())
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_bad);
    var requests = 0;
    final mirror = mirrorServing(_good, () => requests++);
    addTearDown(mirror.dispose);

    await mirror.sync(_v7(sha256: _sha(_good)));
    expect(requests, 1);
    expect(File(exePath()).readAsStringSync(), _good);
  });

  test('export refuses a mirrored program that no longer matches its digest',
      () async {
    final mirror = mirrorServing(_good, () {});
    addTearDown(mirror.dispose);
    await mirror.sync(_v7(sha256: _sha(_good)));
    File(exePath()).writeAsStringSync(_bad);

    final store = PluginMirrorStore(p.join(temp.path, 'mirror'));
    final dest = p.join(temp.path, 'dest');
    await expectLater(
      StoreAppExporter(store: store, appMirror: mirror).exportTo(dest),
      throwsA(
        isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          AppL10n.strings.pluginsDomain.exportAppDamaged,
        ),
      ),
    );
    expect(
      File(p.join(dest, 'Otzaria-Plugin-Store.exe')).existsSync(),
      isFalse,
    );
    expect(File(exePath()).existsSync(), isTrue);
  });

  group('PluginsManager.peekStoreApp', () {
    Future<StoreAppRelease?> peekWith(String? digest) {
      final manager = PluginsManager(
        resolveMirrorDir: () async => p.join(temp.path, 'mirror'),
      );
      final releases = [
        {
          'tag_name': 'v7',
          'assets': [
            {
              'name': 'Otzaria-Plugin-Store.exe',
              'browser_download_url': 'https://example.invalid/v7.exe',
              'size': _good.length,
              'state': 'uploaded',
              if (digest != null) 'digest': 'sha256:$digest',
            },
          ],
        },
      ];
      return http.runWithClient(
        manager.peekStoreApp,
        () => MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode(releases)),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
    }

    test('an intact mirrored copy of the latest version is not offered again',
        () async {
      final mirror = mirrorServing(_good, () {});
      addTearDown(mirror.dispose);
      await mirror.sync(_v7(sha256: _sha(_good)));

      expect(await peekWith(_sha(_good)), isNull);
    });

    test('a same-size copy that no longer matches its digest is offered again',
        () async {
      final mirror = mirrorServing(_good, () {});
      addTearDown(mirror.dispose);
      await mirror.sync(_v7(sha256: _sha(_good)));
      File(exePath()).writeAsStringSync(_bad);

      final offered = await peekWith(_sha(_good));
      expect(offered, isNotNull);
      expect(offered!.tagName, 'v7');
      expect(offered.sha256, _sha(_good));

      var requests = 0;
      final again = mirrorServing(_good, () => requests++);
      addTearDown(again.dispose);
      await again.sync(offered);
      expect(requests, 1);
      expect(File(exePath()).readAsStringSync(), _good);
      expect(await peekWith(_sha(_good)), isNull);
    });

    test('metadata without a digest keeps the size-only answer', () async {
      final mirror = mirrorServing(_good, () {});
      addTearDown(mirror.dispose);
      await mirror.sync(_v7());
      File(exePath()).writeAsStringSync(_bad);

      expect(await peekWith(null), isNull);
    });
  });

  test('a rate-limited release check is reported as such', () async {
    final client = StoreAppReleaseClient(
      httpClient: MockClient(
        (_) async => http.Response('', 403, headers: {
          'x-ratelimit-remaining': '0',
          'retry-after': '120',
        }),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.fetchLatestStable(),
      throwsA(isA<GithubRateLimitException>()
          .having((e) => e.retryAfterMinutes, 'minutes', 2)),
    );
  });
}
