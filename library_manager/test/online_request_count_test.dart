import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/recent_library_releases_client.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show LibraryRelease;

const _libraryReleasesPath = '/repos/Otzaria/SeforimLibrary/releases';
const _talmudPath = '/repos/Otzaria/otzaria-library/releases/latest';
const _catalogPath = '/repos/Otzaria/otzar-HB_catalog/releases/latest';
const _dictionaryPath = '/repos/Otzaria/SeforimMagicIndexer/releases/latest';

class _FakeGithub {
  final requests = <Uri>[];
  int libraryTo = 2;

  int count(String path) => requests
      .where((u) => u.host == 'api.github.com' && u.path == path)
      .length;

  int get companionApiCalls =>
      count(_talmudPath) + count(_catalogPath) + count(_dictionaryPath);

  int get catalogVersionFetches =>
      requests.where((u) => u.path.endsWith('/version.txt')).length;

  Uint8List _body(String name) {
    final match = RegExp(
      r'^patch-v(\d+)-v(\d+)\.db\.zst\.manifest\.json$',
    ).firstMatch(name);
    if (match != null) {
      final from = int.parse(match.group(1)!);
      final to = int.parse(match.group(2)!);
      return _utf8({
        'fromVersion': from,
        'toVersion': to,
        'fromSchemaVersion': 2,
        'toSchemaVersion': 2,
        'fromContentHash': 'h$from',
        'toContentHash': 'h$to',
        'patchFiles': [
          {
            'file': 'patch-v$from-v$to.db.zst',
            'compression': 'zstd',
            'sha256': 'unused',
            'size': 1,
            'uncompressedSha256': 'u',
            'uncompressedSize': 99,
          },
        ],
      });
    }
    if (name == 'version.txt') return Uint8List.fromList(utf8.encode('55'));
    return Uint8List.fromList(utf8.encode('payload:$name'));
  }

  static Uint8List _utf8(Object json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  Map<String, dynamic> _asset(String name, String url) => {
    'name': name,
    'browser_download_url': url,
    'size': _body(name).length,
    'id': name.hashCode.abs(),
    'updated_at': '2026-08-01T00:00:00Z',
    'digest': 'sha256:${sha256.convert(_body(name))}',
  };

  Map<String, dynamic> _companionRelease(String tag, List<String> names) => {
    'tag_name': tag,
    'assets': [for (final name in names) _asset(name, 'https://dl/$name')],
  };

  List<Map<String, dynamic>> _libraryReleases() => [
    for (var to = libraryTo; to >= 2; to--)
      {
        'tag_name': 'v$to-20261011',
        'prerelease': false,
        'draft': false,
        'published_at': '2026-06-27T21:00:00Z',
        'assets': [
          for (final name in [
            if (to == libraryTo) 'seforim.db.zst',
            'patch-v${to - 1}-v$to.db.zst.manifest.json',
            'patch-v${to - 1}-v$to.db.zst',
          ])
            _asset(name, 'https://lib/v$to-20261011/$name'),
        ],
      },
  ];

  late final MockClient client = MockClient.streaming((request, _) async {
    requests.add(request.url);
    final url = request.url;
    Uint8List? body;
    if (url.host == 'api.github.com') {
      if (url.path == _libraryReleasesPath) {
        body = _utf8(
          url.queryParameters['page'] == '1' ? _libraryReleases() : [],
        );
      } else if (url.path == _talmudPath) {
        body = _utf8(
          _companionRelease('lib-v9', ['talmud_bavli_latest.tar.zst']),
        );
      } else if (url.path == _catalogPath) {
        body = _utf8(
          _companionRelease('cat-v3', [
            'otzar-HB_catalog.db.zst',
            'version.txt',
          ]),
        );
      } else if (url.path == _dictionaryPath) {
        body = _utf8(_companionRelease('dict-v7', ['lexical.db']));
      }
    } else {
      body = _body(url.pathSegments.last);
    }
    if (body == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
    );
  });
}

void main() {
  late Directory tempDir;
  late String dataDir;
  late _FakeGithub github;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('online-request-count-');
    dataDir = p.join(tempDir.path, 'OtzariaData');
    await Directory(dataDir).create(recursive: true);
    github = _FakeGithub();
  });

  tearDown(() async {
    AppL10n.use(AppLanguage.hebrew);
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<T> online<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => github.client);

  group('RecentLibraryReleasesClient', () {
    late DateTime now;
    late RecentLibraryReleasesClient client;

    setUp(() {
      now = DateTime.utc(2026, 10, 11, 12);
      client = RecentLibraryReleasesClient(
        httpClient: github.client,
        clock: () => now,
      );
    });

    test('fetchReleases reuses the fresh list inside the window', () async {
      final fresh = await client.fetchFreshReleases();
      now = now.add(const Duration(minutes: 9));
      final reused = await client.fetchReleases();

      expect(reused, same(fresh));
      expect(github.count(_libraryReleasesPath), 1);
    });

    test('fetchFreshReleases always asks GitHub', () async {
      await client.fetchFreshReleases();
      await client.fetchFreshReleases();

      expect(github.count(_libraryReleasesPath), 2);
    });

    test('a list older than the window is fetched again', () async {
      await client.fetchFreshReleases();
      now = now.add(const Duration(minutes: 10));
      await client.fetchReleases();

      expect(github.count(_libraryReleasesPath), 2);
    });

    test('a clock that moved backwards does not reuse', () async {
      await client.fetchFreshReleases();
      now = now.subtract(const Duration(minutes: 1));
      await client.fetchReleases();

      expect(github.count(_libraryReleasesPath), 2);
    });

    test('forgetReleases drops the list', () async {
      await client.fetchFreshReleases();
      client.forgetReleases();
      await client.fetchReleases();

      expect(github.count(_libraryReleasesPath), 2);
    });

    test(
      'a release published after the check is seen by the next check',
      () async {
        expect(_tags(await client.fetchFreshReleases()), ['v2-20261011']);
        github.libraryTo = 3;

        expect(_tags(await client.fetchFreshReleases()), [
          'v3-20261011',
          'v2-20261011',
        ]);
      },
    );
  });

  group('CompanionAssetsMirror plan reuse', () {
    late DateTime now;
    late String destDir;
    late CompanionAssetsMirror mirror;

    setUp(() {
      now = DateTime.utc(2026, 10, 11, 12);
      destDir = p.join(tempDir.path, 'companions');
      mirror = CompanionAssetsMirror(
        httpClient: github.client,
        clock: () => now,
      );
    });

    test(
      'a sync right after the light check asks GitHub nothing new',
      () async {
        expect(
          await mirror.peekPending(destDir: destDir),
          CompanionAsset.values.toSet(),
        );
        expect(github.companionApiCalls, 3);
        expect(github.catalogVersionFetches, 1);

        now = now.add(const Duration(minutes: 5));
        final manifest = await mirror.sync(destDir: destDir);

        expect(manifest.entries.keys, containsAll(CompanionAsset.values));
        expect(github.companionApiCalls, 3);
        expect(github.catalogVersionFetches, 1);
        expect(await mirror.peekPending(destDir: destDir), isEmpty);
      },
    );

    test('the peeked plans serve one sync only', () async {
      await mirror.peekPending(destDir: destDir);
      await mirror.sync(destDir: destDir);
      await mirror.sync(destDir: destDir);

      expect(github.companionApiCalls, 6);
    });

    test('plans older than the window are made again', () async {
      await mirror.peekPending(destDir: destDir);
      now = now.add(const Duration(minutes: 10));
      await mirror.sync(destDir: destDir);

      expect(github.companionApiCalls, 6);
    });

    test('plans peeked for another folder are not reused', () async {
      await mirror.peekPending(destDir: p.join(tempDir.path, 'elsewhere'));
      await mirror.sync(destDir: destDir);

      expect(github.companionApiCalls, 6);
    });
  });

  group('LibraryManager check + download session', () {
    test('the download reuses what the light check fetched', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        expect(await manager.peekLatestOnlineVersion(), 2);
        expect(await manager.peekPendingCompanions(), isNotEmpty);
        expect(github.count(_libraryReleasesPath), 1);
        expect(github.companionApiCalls, 3);

        await manager.downloadToMirror();

        expect(await manager.hasMirror, isTrue);
        expect(github.count(_libraryReleasesPath), 1);
        expect(github.companionApiCalls, 3);
        expect(github.catalogVersionFetches, 1);

        final before = github.requests.length;
        await manager.checkForUpdate();
        expect(github.requests.length, before);
      });
    });

    test('a download with no check before it fetches each list once', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        await manager.downloadToMirror();

        expect(github.count(_libraryReleasesPath), 1);
        expect(github.companionApiCalls, 3);
      });
    });

    test('a new light check asks GitHub again', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        expect(await manager.peekLatestOnlineVersion(), 2);
        github.libraryTo = 3;
        expect(await manager.peekLatestOnlineVersion(), 3);
        expect(github.count(_libraryReleasesPath), 2);
      });
    });

    test('a failed export drops the list so a retry fetches anew', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);
        await manager.peekLatestOnlineVersion();
        await File(p.join(dataDir, 'mirror')).writeAsString('not a folder');

        await expectLater(manager.downloadToMirror(), throwsA(anything));
        await File(p.join(dataDir, 'mirror')).delete();
        await manager.downloadToMirror();

        expect(github.count(_libraryReleasesPath), 2);
      });
    });

    test('personal mode already up to date takes the smart-search tag from the '
        'same list', () async {
      await online(() async {
        await LibraryStateStore(
          p.join(dataDir, 'library_state.json'),
        ).recordKnownDbVersion(LibraryStateStore.currentMachineKey(), 2);
        final manager = LibraryManager(
          dataDir: dataDir,
          personalUpdateMode: true,
        );
        addTearDown(manager.dispose);
        final warnings = <String>[];

        final outcome = await manager.downloadToMirror(
          includeSemanticSearch: true,
          onCompanionWarning: (name, _) => warnings.add(name),
        );

        expect(outcome.upToDate, isTrue);
        expect(github.count(_libraryReleasesPath), 1);
        expect(
          github.requests.where(
            (u) =>
                u.path ==
                '/repos/Otzaria/SeforimLibrary/releases/tags/'
                    'vectors-v2-20261011',
          ),
          isNotEmpty,
        );
        expect(
          warnings,
          contains(AppL10n.strings.libraryDomain.companionSemanticName),
        );
      });
    });
  });
}

List<String> _tags(List<LibraryRelease> releases) => [
  for (final release in releases) release.tag,
];
