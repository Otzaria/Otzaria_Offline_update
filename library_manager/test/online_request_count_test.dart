import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/download_connections.dart';
import 'package:library_manager/src/services/recent_library_releases_client.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show
        LibraryRelease,
        LocalMirrorLibraryReleaseClient,
        DownloadScheduler,
        PatchDownloadCancelled,
        PatchDownloadException;

import 'support/failing_writes.dart';
import 'support/semantic_fixtures.dart';

const _libraryReleasesPath = '/repos/Otzaria/SeforimLibrary/releases';
const _talmudPath = '/repos/Otzaria/otzaria-library/releases/latest';
const _catalogPath = '/repos/Otzaria/otzar-HB_catalog/releases/latest';
const _dictionaryPath = '/repos/Otzaria/SeforimMagicIndexer/releases/latest';

class _FullDirectory implements Directory {
  _FullDirectory(this.path);

  @override
  final String path;

  @override
  Future<Directory> create({bool recursive = false}) async =>
      throw FileSystemException(
        'mkdir failed',
        path,
        OSError('', diskFullErrno),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeGithub {
  final requests = <Uri>[];
  int libraryTo = 2;

  /// `library-changes.md` לפי גרסה; `null` = רשום ברשימת הנכסים אך 404.
  final notes = <int, String?>{};

  Future<void> Function()? beforeLibraryReleases;
  Future<void> Function()? beforeDictionary;
  Future<void> Function()? beforeTalmud;

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
          if (notes.containsKey(to))
            {
              'name': 'library-changes.md',
              'browser_download_url':
                  'https://lib/v$to-20261011/library-changes.md',
              'size': utf8.encode(notes[to] ?? '').length,
            },
        ],
      },
  ];

  late final MockClient client = MockClient.streaming((request, _) async {
    requests.add(request.url);
    if (request.url.host == 'dl' &&
        request.url.pathSegments.last == 'talmud_bavli_latest.tar.zst') {
      await beforeTalmud?.call();
    }
    if (request.url.host == 'dl' &&
        request.url.pathSegments.last == 'lexical.db') {
      await beforeDictionary?.call();
    }
    final url = request.url;
    Uint8List? body;
    if (url.host == 'api.github.com') {
      if (url.path == _libraryReleasesPath) {
        await beforeLibraryReleases?.call();
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
    } else if (url.pathSegments.last == 'library-changes.md') {
      final version = int.parse(
        RegExp(r'^v(\d+)').firstMatch(url.pathSegments.first)!.group(1)!,
      );
      final text = notes[version];
      body = text == null ? null : Uint8List.fromList(utf8.encode(text));
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
    test(
      'a later session keeps unchanged library and companion payloads',
      () async {
        await online(() async {
          final first = LibraryManager(dataDir: dataDir);
          try {
            await first.downloadToMirror();
          } finally {
            first.dispose();
          }
          github.requests.clear();
          final next = LibraryManager(dataDir: dataDir);
          addTearDown(next.dispose);

          expect(await next.peekLatestOnlineVersion(), 2);
          expect(await next.peekPendingCompanions(), isEmpty);
          await next.downloadToMirror();

          expect(
            github.requests.where(
              (u) =>
                  (u.host == 'lib' && !u.path.endsWith('.manifest.json')) ||
                  (u.host == 'dl' && !u.path.endsWith('/version.txt')),
            ),
            isEmpty,
          );
        });
      },
    );

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

    for (final personal in [false, true]) {
      test('download progress includes smart search before showing a known '
          'total (personal up to date: $personal, issue #156)', () async {
        final vectors = FakeVectorsGithub()..legacyBase(2);
        addTearDown(vectors.client.close);
        await online(() async {
          if (personal) {
            await LibraryStateStore(
              p.join(dataDir, LibraryStateStore.fileName),
            ).recordOwnDbVersion(2);
          }
          var semanticStarted = false;
          final progress = <(int, int?, bool)>[];
          final warnings = <Object>[];
          final manager = LibraryManager(
            dataDir: dataDir,
            personalUpdateMode: personal,
            semanticAssetsFactory: (scheduler) => _RealVectorsAssets(
              vectors.client,
              scheduler,
              onSync: () => semanticStarted = true,
            ),
          );
          addTearDown(manager.dispose);

          final outcome = await manager.downloadToMirror(
            includeSemanticSearch: true,
            onBytesProgress: (done, total) =>
                progress.add((done, total, semanticStarted)),
            onCompanionWarning: (_, error) => warnings.add(error),
          );

          expect(warnings, isEmpty);
          expect(outcome.upToDate, personal);
          expect(vectors.downloads, contains('legacy-v2.oxv.zst'));
          final beforeSemantic = progress.where((sample) => !sample.$3);
          expect(beforeSemantic, isNotEmpty);
          expect(
            beforeSemantic.where(
              (sample) =>
                  sample.$2 != null &&
                  sample.$2! > 0 &&
                  sample.$1 >= sample.$2!,
            ),
            isEmpty,
            reason:
                'DB and companion completion must not show 100% while '
                'smart search is still pending: $progress',
          );
          final known = progress.where((sample) => (sample.$2 ?? 0) > 0);
          expect(known, isNotEmpty);
          expect(known.map((sample) => sample.$2).toSet(), {known.last.$2});
          double previous = 0;
          for (final (done, total, _) in known) {
            final fraction = done / total!;
            expect(fraction, greaterThanOrEqualTo(previous));
            previous = fraction;
          }
          expect(progress.last.$1, progress.last.$2);
          expect(previous, 1);
        });
      });
    }

    for (final personal in [false, true]) {
      test('download progress without smart search completes with a known '
          'total (personal up to date: $personal)', () async {
        await online(() async {
          if (personal) {
            await LibraryStateStore(
              p.join(dataDir, LibraryStateStore.fileName),
            ).recordOwnDbVersion(2);
          }
          final progress = <(int, int?)>[];
          final manager = LibraryManager(
            dataDir: dataDir,
            personalUpdateMode: personal,
          );
          addTearDown(manager.dispose);

          final outcome = await manager.downloadToMirror(
            onBytesProgress: (done, total) => progress.add((done, total)),
          );

          expect(outcome.upToDate, personal);
          expect(progress, isNotEmpty);
          expect(progress.last.$2, greaterThan(0));
          expect(progress.last.$1, progress.last.$2);
          expect(
            github.requests.where((u) => u.path.contains('/releases/tags/')),
            isEmpty,
          );
        });
      });
    }

    test('download progress finishes with a known total after a smart-search '
        'warning before its first report', () async {
      await online(() async {
        const failure = FormatException('bad manifest');
        final progress = <(int, int?)>[];
        final warnings = <(String, Object)>[];
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (_) => _FailingSemanticAssets(failure),
        );
        addTearDown(manager.dispose);

        await manager.downloadToMirror(
          includeSemanticSearch: true,
          onBytesProgress: (done, total) => progress.add((done, total)),
          onCompanionWarning: (name, error) => warnings.add((name, error)),
        );

        expect(warnings, [
          (AppL10n.strings.libraryDomain.companionSemanticName, failure),
        ]);
        expect(progress.last.$2, greaterThan(0));
        expect(progress.last.$1, progress.last.$2);
        expect(
          progress.take(progress.length - 1).map((sample) => sample.$2),
          everyElement(isNull),
        );
      });
    });

    test('download progress preserves an unfinished smart-search total after '
        'a warning', () async {
      await online(() async {
        const failure = FormatException('truncated vectors');
        final progress = <(int, int?)>[];
        final warnings = <(String, Object)>[];
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (_) =>
              _FailingSemanticAssets(failure, progressBeforeFailure: (25, 100)),
        );
        addTearDown(manager.dispose);

        await manager.downloadToMirror(
          includeSemanticSearch: true,
          onBytesProgress: (done, total) => progress.add((done, total)),
          onCompanionWarning: (name, error) => warnings.add((name, error)),
        );

        expect(warnings, [
          (AppL10n.strings.libraryDomain.companionSemanticName, failure),
        ]);
        final known = progress.where((sample) => sample.$2 != null);
        expect(known, isNotEmpty);
        expect(known.map((sample) => sample.$2).toSet(), {progress.last.$2});
        expect(progress.last.$2! - progress.last.$1, 75);
        expect(progress.last.$1, lessThan(progress.last.$2!));
      });
    });

    test('the export picks its connections per asset by the drive\'s write '
        'speed', () async {
      resetWriteSpeedCache();
      await online(() async {
        final probed = <String>[];
        final manager = LibraryManager(
          dataDir: dataDir,
          removableProbe: (_) => true,
          segmentThresholdBytes: 1,
          writeProbe: (dir) async {
            probed.add(dir);
            return 1024 * 1024;
          },
        );
        addTearDown(manager.dispose);

        await manager.downloadToMirror();

        expect(
          probed,
          contains(p.join(manager.mirrorDir, 'assets', 'v2-20261011')),
          reason: 'the decision is per asset, in the asset\'s own folder',
        );
      });
    });

    group('exportConnectionsFor', () {
      const mib = 1024 * 1024;
      late int defaultConnections;
      late String dest;

      setUp(() {
        resetWriteSpeedCache();
        defaultConnections = connectionsPerFile(DownloadScheduler());
        dest = p.join(tempDir.path, 'mirror', 'assets', 'v1');
        Directory(dest).createSync(recursive: true);
      });

      void liveState(String asset, String token) {
        File('${p.join(dest, asset)}.segments').writeAsStringSync(
          jsonEncode({
            'v': 1,
            'token': token,
            'url': 'u',
            'size': 200,
            'sha256': null,
            'etag': 'e',
            'bounds': [0, 100, 200],
            'assembled': 1,
          }),
        );
      }

      LibraryManager manager({
        bool removable = true,
        double? speed = 3.0 * mib,
        List<String>? probed,
      }) {
        final m = LibraryManager(
          dataDir: dataDir,
          removableProbe: (_) => removable,
          segmentThresholdBytes: 100,
          writeProbe: (dir) async {
            probed?.add(dir);
            return speed;
          },
        );
        addTearDown(m.dispose);
        return m;
      }

      test('a live split asset stays split and a fresh one on a slow '
          'removable drive gets one connection', () async {
        liveState('a.zst', 'tok-a');
        final probed = <String>[];
        final m = manager(probed: probed);

        expect(
          await m.exportConnectionsFor(p.join(dest, 'a.zst'), 500, 'tok-a'),
          defaultConnections,
        );
        expect(probed, isEmpty, reason: 'no measurement for a resumed split');
        expect(
          await m.exportConnectionsFor(p.join(dest, 'b.zst'), 500, 'tok-b'),
          1,
        );
        expect(probed, [dest]);
      });

      test(
        'small assets (manifests) are neither measured nor reduced',
        () async {
          final probed = <String>[];
          final m = manager(probed: probed);

          expect(
            await m.exportConnectionsFor(p.join(dest, 'm.json'), 50, 'x'),
            defaultConnections,
          );
          expect(probed, isEmpty);
        },
      );

      test('a fixed drive is unchanged and unmeasured', () async {
        final probed = <String>[];
        final m = manager(removable: false, probed: probed);

        expect(
          await m.exportConnectionsFor(p.join(dest, 'b.zst'), 500, 'x'),
          defaultConnections,
        );
        expect(probed, isEmpty);
      });

      test('a fast removable drive keeps the default', () async {
        final m = manager(speed: 40.0 * mib);
        expect(
          await m.exportConnectionsFor(p.join(dest, 'b.zst'), 500, 'x'),
          defaultConnections,
        );
      });

      test('cancel returns the default without throwing', () async {
        final m = manager();
        expect(
          await m.exportConnectionsFor(
            p.join(dest, 'b.zst'),
            500,
            'x',
            isCancelled: () => true,
          ),
          defaultConnections,
        );
      });
    });

    test('the download brings the what-is-new notes without failing on a '
        'missing one', () async {
      await online(() async {
        github
          ..libraryTo = 3
          ..notes.addAll({3: '# v3', 2: null});
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);
        final warnings = <String>[];

        await manager.downloadToMirror(
          onCompanionWarning: (name, _) => warnings.add(name),
        );

        final changes = p.join(manager.mirrorDir, 'changes');
        expect(
          File(p.join(changes, 'v3-20261011.md')).readAsStringSync(),
          '# v3',
        );
        expect(File(p.join(changes, 'v2-20261011.md')).existsSync(), isFalse);
        expect(warnings, isEmpty);
        expect(github.count(_libraryReleasesPath), 1);
      });
    });

    test(
      'the notes reuse the export list even after a long download',
      () async {
        await online(() async {
          github
            ..libraryTo = 3
            ..notes[3] = '# v3';
          final start = DateTime.utc(2026, 10, 13, 8);
          var clockCalls = 0;
          final manager = LibraryManager(
            dataDir: dataDir,
            releaseClient: RecentLibraryReleasesClient(
              httpClient: github.client,
              clock: () => clockCalls++ == 0
                  ? start
                  : start.add(const Duration(hours: 1)),
            ),
          );
          addTearDown(manager.dispose);

          await manager.downloadToMirror();

          expect(github.count(_libraryReleasesPath), 1);
          expect(
            File(
              p.join(manager.mirrorDir, 'changes', 'v3-20261011.md'),
            ).existsSync(),
            isTrue,
          );
        });
      },
    );

    test(
      'the size probe plans without payload, and the download matches it',
      () async {
        await online(() async {
          github.libraryTo = 3;
          final manager = LibraryManager(dataDir: dataDir);
          addTearDown(manager.dispose);

          final probed = await manager.probeMirrorDownloadBytes();

          bool payload(Uri u) =>
              (u.host == 'lib' && !u.path.endsWith('.manifest.json')) ||
              (u.host == 'dl' && u.pathSegments.last != 'version.txt');
          expect(github.requests.where(payload), isEmpty);
          final mirror = Directory(p.join(dataDir, 'mirror'));
          final files = mirror.existsSync()
              ? mirror.listSync(recursive: true).whereType<File>().toList()
              : const <File>[];
          expect(files, isEmpty);
          expect(probed, greaterThan(0));

          int? total;
          await manager.downloadToMirror(onBytesProgress: (_, t) => total = t);
          expect(total, probed);
          expect(github.count(_libraryReleasesPath), 1);
          expect(github.companionApiCalls, 3);
        });
      },
    );

    test('in personal mode the probe is the personal export, not the full '
        'library', () async {
      await online(() async {
        github.libraryTo = 3;
        await LibraryStateStore(
          p.join(dataDir, 'library_state.json'),
        ).recordKnownDbVersion(await LibraryStateStore.currentMachineKey(), 2);
        final full = LibraryManager(dataDir: dataDir);
        addTearDown(full.dispose);
        final fullBytes = await full.probeMirrorDownloadBytes();
        final manager = LibraryManager(
          dataDir: dataDir,
          personalUpdateMode: true,
        );
        addTearDown(manager.dispose);

        final probed = await manager.probeMirrorDownloadBytes();
        int? total;
        await manager.downloadToMirror(onBytesProgress: (_, t) => total = t);

        expect(probed, total);
        expect(probed, lessThan(fullBytes!));
      });
    });

    test('a download stops a running probe before it exports', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        final probe = manager.probeMirrorDownloadBytes().then<int?>(
          (bytes) => bytes,
          onError: (_) => null,
        );
        await manager.downloadToMirror();
        await probe;

        expect(await manager.hasMirror, isTrue);
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

    test('personal mode repairs a damaged releases.json with a full export '
        '(issue #127)', () async {
      await online(() async {
        await LibraryStateStore(
          p.join(dataDir, 'library_state.json'),
        ).recordKnownDbVersion(await LibraryStateStore.currentMachineKey(), 2);
        final manager = LibraryManager(
          dataDir: dataDir,
          personalUpdateMode: true,
        );
        addTearDown(manager.dispose);
        final releases = File(p.join(manager.mirrorDir, 'releases.json'));
        await releases.parent.create(recursive: true);
        await releases.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0xFF, 0xFE]);
        final stages = <String>[];

        final outcome = await manager.downloadToMirror(onStage: stages.add);

        expect(outcome.upToDate, isFalse);
        expect(outcome.repairedDamagedMirror, isTrue);
        expect(outcome.personalFromVersion, isNull);
        expect(
          stages,
          contains(AppL10n.strings.libraryDomain.exportPersonalMirrorDamaged),
        );
        expect(
          await LocalMirrorLibraryReleaseClient(
            mirrorDir: manager.mirrorDir,
          ).fetchReleases(),
          isNotEmpty,
        );
      });
    });

    for (final personal in [true, false]) {
      test('a damaged releases.json behind latest is rewritten by the usual '
          'export (personal: $personal)', () async {
        await online(() async {
          github.libraryTo = 3;
          await LibraryStateStore(
            p.join(dataDir, 'library_state.json'),
          ).recordKnownDbVersion(
            await LibraryStateStore.currentMachineKey(),
            2,
          );
          final manager = LibraryManager(
            dataDir: dataDir,
            personalUpdateMode: personal,
          );
          addTearDown(manager.dispose);
          final releases = File(p.join(manager.mirrorDir, 'releases.json'));
          await releases.parent.create(recursive: true);
          await releases.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0xFF, 0xFE]);

          final outcome = await manager.downloadToMirror();

          expect(outcome.repairedDamagedMirror, isFalse);
          expect(outcome.personalFromVersion, personal ? 2 : isNull);
          expect(
            github.requests.any((u) => u.path.endsWith('/seforim.db.zst')),
            !personal,
          );
          expect(
            await LocalMirrorLibraryReleaseClient(
              mirrorDir: manager.mirrorDir,
            ).fetchReleases(),
            isNotEmpty,
          );
        });
      });
    }

    test('personal mode already up to date takes the smart-search tag from the '
        'same list', () async {
      await online(() async {
        await LibraryStateStore(
          p.join(dataDir, 'library_state.json'),
        ).recordKnownDbVersion(await LibraryStateStore.currentMachineKey(), 2);
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

    group('smart-search failure during the download', () {
      Future<({List<String> warnings, Object? thrown, LibraryManager manager})>
      run(Object failure) async {
        late LibraryManager manager;
        final warnings = <String>[];
        Object? thrown;
        await online(() async {
          manager = LibraryManager(
            dataDir: dataDir,
            semanticAssetsFactory: (_) => _FailingSemanticAssets(failure),
          );
          addTearDown(manager.dispose);
          try {
            await manager.downloadToMirror(
              includeSemanticSearch: true,
              onCompanionWarning: (name, _) => warnings.add(name),
            );
          } catch (error) {
            thrown = error;
          }
        });
        return (warnings: warnings, thrown: thrown, manager: manager);
      }

      String semanticName() =>
          AppL10n.strings.libraryDomain.companionSemanticName;

      test('a full drive stops the download once the finished components are '
          'kept', () async {
        final result = await run(
          const StorageFullException(neededBytes: 5, freeBytes: 1),
        );

        expect(result.thrown, isA<StorageFullException>());
        expect((result.thrown as StorageFullException).neededBytes, 5);
        expect(result.warnings, isNot(contains(semanticName())));
        expect(
          File(p.join(result.manager.mirrorDir, 'releases.json')).existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(
              result.manager.companionsMirrorDir,
              CompanionMirrorManifest.fileName,
            ),
          ).existsSync(),
          isTrue,
        );
      });

      test('a system disk-full error reaches the caller as '
          'StorageFullException', () async {
        final cause = FileSystemException(
          'write failed',
          'E:/mirror/semantic/x',
          OSError('There is not enough space on the disk.', diskFullErrno),
        );

        final result = await run(cause);

        expect(result.thrown, isA<StorageFullException>());
        expect((result.thrown as StorageFullException).cause, same(cause));
        expect(result.warnings, isNot(contains(semanticName())));
      });

      test('a point failure stays a warning', () async {
        final result = await run(const FormatException('bad manifest'));

        expect(result.thrown, isNull);
        expect(result.warnings, contains(semanticName()));
      });

      String wrappedWrite(int errno) =>
          'save failed: FileSystemException: Write failed, path = '
          "'E:\\mirror\\semantic\\x.zst' (OS Error: simulated, errno = $errno)";

      test('a disk-full write wrapped by the downloader as text is a storage '
          'failure, not a warning', () async {
        final result = await run(
          PatchDownloadException(wrappedWrite(diskFullErrno)),
        );

        expect(result.thrown, isA<StorageFullException>());
        expect(result.warnings, isNot(contains(semanticName())));
      });

      test('a wrapped access-denied write stays a warning', () async {
        final errno = Platform.isWindows ? 5 : 13;
        final result = await run(PatchDownloadException(wrappedWrite(errno)));

        expect(result.thrown, isNull);
        expect(result.warnings, contains(semanticName()));
      });
    });

    test('a disk-full write inside the real smart-search downloader crosses '
        'the boundary as StorageFullException', () async {
      final vectors = FakeVectorsGithub()..legacyBase(2);
      addTearDown(vectors.client.close);
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (scheduler) =>
              _RealVectorsAssets(vectors.client, scheduler),
        );
        addTearDown(manager.dispose);
        final warnings = <String>[];
        final escaped = <Object>[];
        final finished = Completer<Object?>();

        runZonedGuarded(() {
          runWithFailingRandomWrites(
            () => manager.downloadToMirror(
              includeSemanticSearch: true,
              onCompanionWarning: (name, _) => warnings.add(name),
            ),
            matches: (path) => p.basename(path) == 'legacy-v2.oxv.zst',
          ).then(
            (_) => finished.complete(null),
            onError: (Object error) => finished.complete(error),
          );
        }, (error, _) => escaped.add(error));
        final thrown = await finished.future;

        expect(escaped, isEmpty);
        expect(thrown, isA<StorageFullException>(), reason: '$thrown');
        expect(
          warnings,
          isNot(contains(AppL10n.strings.libraryDomain.companionSemanticName)),
        );
        expect(
          File(p.join(manager.mirrorDir, 'releases.json')).existsSync(),
          isTrue,
        );
      });
    });

    group('a full drive in one parallel branch gates the other', () {
      /// Holds the library list until [release] and then a little longer, so
      /// the companions hit the full drive before any library asset starts.
      void holdLibraryUntil(bool Function() release) {
        github.beforeLibraryReleases = () async {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!release() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        };
      }

      List<Uri> libraryAssets() => [
        for (final u in github.requests)
          if (u.host == 'lib' && u.path.endsWith('.zst')) u,
      ];

      for (final damaged in [false, true]) {
        test(
          'after a companion hits a ${damaged ? 'damaged' : 'full'} drive no library asset starts and '
          'the cause is kept',
          () async {
            await online(() async {
              var tripped = false;
              holdLibraryUntil(() => tripped);
              final manager = LibraryManager(
                dataDir: dataDir,
                semanticAssetsFactory: (_) => _FailingSemanticAssets(
                  const FormatException('must not run'),
                ),
              );
              addTearDown(manager.dispose);
              final warnings = <String>[];
              Object? thrown;

              await runWithFailingRandomWrites(
                () async {
                  try {
                    await manager.downloadToMirror(
                      includeSemanticSearch: true,
                      onCompanionWarning: (name, _) => warnings.add(name),
                    );
                  } catch (error) {
                    thrown = error;
                  }
                },
                matches: (path) {
                  final hit = p.basename(path) == 'lexical.db';
                  if (hit) tripped = true;
                  return hit;
                },
                errno: damaged ? (Platform.isWindows ? 1392 : 5) : null,
              );

              expect(
                thrown,
                damaged
                    ? isA<StorageCorruptException>()
                    : isA<StorageFullException>(),
                reason: '$thrown',
              );
              expect(libraryAssets(), isEmpty);
              expect(
                warnings,
                isNot(
                  contains(AppL10n.strings.libraryDomain.companionSemanticName),
                ),
              );
            });
          },
        );
      }

      test('a companion failure gates the export while another companion '
          'is still active', () async {
        await online(() async {
          final failed = Completer<void>();
          final peer = Completer<void>();
          github.beforeTalmud = () => peer.future;
          holdLibraryUntil(() => failed.isCompleted);
          final manager = LibraryManager(dataDir: dataDir);
          addTearDown(manager.dispose);
          Object? thrown;

          await runWithFailingRandomWrites(
            () async {
              final download = manager.downloadToMirror().then<void>(
                (_) {},
                onError: (Object error) => thrown = error,
              );
              try {
                await failed.future.timeout(const Duration(seconds: 5));
                await Future<void>.delayed(const Duration(milliseconds: 300));
              } finally {
                peer.complete();
                await download;
              }
            },
            matches: (path) {
              final hit = p.basename(path) == 'lexical.db';
              if (hit && !failed.isCompleted) failed.complete();
              return hit;
            },
          );

          expect(thrown, isA<StorageFullException>(), reason: '$thrown');
          expect(libraryAssets(), isEmpty);
          final manifest = await CompanionMirrorManifest.load(
            manager.companionsMirrorDir,
          );
          expect(manifest?.entries[CompanionAsset.talmud], isNotNull);
        });
      });

      test(
        'a full drive creating the companions directory gates the export',
        () async {
          await online(() async {
            var tripped = false;
            holdLibraryUntil(() => tripped);
            final manager = LibraryManager(dataDir: dataDir);
            addTearDown(manager.dispose);
            Object? thrown;
            await IOOverrides.runZoned(
              () async {
                try {
                  await manager.downloadToMirror();
                } catch (error) {
                  thrown = error;
                }
              },
              createDirectory: (path) {
                if (p.equals(path, manager.companionsMirrorDir)) {
                  tripped = true;
                  return _FullDirectory(path);
                }
                return Zone.root.run(() => Directory(path));
              },
            );
            expect(thrown, isA<StorageFullException>(), reason: '$thrown');
            expect(libraryAssets(), isEmpty);
          });
        },
      );

      test('a real user cancel still surfaces as a cancel', () async {
        await online(() async {
          var cancelled = false;
          github.beforeLibraryReleases = () async => cancelled = true;
          final manager = LibraryManager(dataDir: dataDir);
          addTearDown(manager.dispose);
          Object? thrown;

          try {
            await manager.downloadToMirror(isCancelled: () => cancelled);
          } catch (error) {
            thrown = error;
          }

          expect(thrown, isA<PatchDownloadCancelled>(), reason: '$thrown');
        });
      });
    });

    test('a disk-full write inside the real downloader crosses the boundary '
        'as StorageFullException', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);
        final warnings = <String>[];
        Object? thrown;

        await runWithFailingRandomWrites(() async {
          try {
            await manager.downloadToMirror(
              includeSemanticSearch: true,
              onCompanionWarning: (name, _) => warnings.add(name),
            );
          } catch (error) {
            thrown = error;
          }
        }, matches: (path) => p.basename(path) == 'seforim.db.zst');

        expect(thrown, isA<StorageFullException>(), reason: '$thrown');
        expect(
          github.requests.where((u) => u.path.contains('/releases/tags/')),
          isEmpty,
        );
      });
    });

    test('a full drive in a companion keeps the finished DB export and skips '
        'the smart search', () async {
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (_) =>
              _FailingSemanticAssets(const FormatException('must not run')),
        );
        addTearDown(manager.dispose);
        // The companion fails only after the export finished, so the test
        // holds regardless of how the two branches interleave.
        github.beforeDictionary = () async {
          final releases = File(p.join(manager.mirrorDir, 'releases.json'));
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!releases.existsSync() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        };
        final warnings = <String>[];
        Object? thrown;

        await runWithFailingRandomWrites(() async {
          try {
            await manager.downloadToMirror(
              includeSemanticSearch: true,
              onCompanionWarning: (name, _) => warnings.add(name),
            );
          } catch (error) {
            thrown = error;
          }
        }, matches: (path) => p.basename(path) == 'lexical.db');

        expect(thrown, isA<StorageFullException>(), reason: '$thrown');
        expect(
          warnings,
          isNot(contains(AppL10n.strings.libraryDomain.companionSemanticName)),
        );
        expect(
          File(p.join(manager.mirrorDir, 'releases.json')).existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(
              manager.mirrorDir,
              'assets',
              'v2-20261011',
              'seforim.db.zst',
            ),
          ).existsSync(),
          isTrue,
        );
      });
    });

    test('a damaged drive in a companion keeps the finished DB export and '
        'skips the smart search', () async {
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (_) =>
              _FailingSemanticAssets(const FormatException('must not run')),
        );
        addTearDown(manager.dispose);
        github.beforeDictionary = () async {
          final releases = File(p.join(manager.mirrorDir, 'releases.json'));
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!releases.existsSync() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        };
        final warnings = <String>[];
        Object? thrown;

        await runWithFailingRandomWrites(
          () async {
            try {
              await manager.downloadToMirror(
                includeSemanticSearch: true,
                onCompanionWarning: (name, _) => warnings.add(name),
              );
            } catch (error) {
              thrown = error;
            }
          },
          matches: (path) => p.basename(path) == 'lexical.db',
          errno: Platform.isWindows ? 1392 : 5,
        );

        expect(thrown, isA<StorageCorruptException>(), reason: '$thrown');
        expect(
          warnings,
          isNot(contains(AppL10n.strings.libraryDomain.companionSemanticName)),
        );
        expect(
          File(
            p.join(
              manager.mirrorDir,
              'assets',
              'v2-20261011',
              'seforim.db.zst',
            ),
          ).existsSync(),
          isTrue,
        );
      });
    });

    test('a damaged drive in the smart search is thrown after the finished '
        'export is saved', () async {
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (_) => _FailingSemanticAssets(
            StorageCorruptException(dir: dataDir, errno: 1392),
          ),
        );
        addTearDown(manager.dispose);
        Object? thrown;
        try {
          await manager.downloadToMirror(includeSemanticSearch: true);
        } catch (error) {
          thrown = error;
        }

        expect(thrown, isA<StorageCorruptException>(), reason: '$thrown');
        expect(
          File(p.join(manager.mirrorDir, 'releases.json')).existsSync(),
          isTrue,
        );
      });
    });

    test('the light check exposes why nothing is offered', () async {
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          semanticAssetsFactory: (_) => _UnreadableSemanticAssets(),
        );
        addTearDown(manager.dispose);
        expect(manager.peekedSemanticIncompatibility, isNull);

        expect(await manager.peekPendingSemanticSearch(), isFalse);

        expect(manager.peekedSemanticIncompatibility?.lineTextVersion, 1);
      });
    });

    for (final scenario in [
      (null, [SemanticModelGeneration.round2]),
      (<String>[], <SemanticModelGeneration>[]),
      (['v0.9.98.3'], [SemanticModelGeneration.qa491]),
      (['v0.9.98.3-rc1', 'latest'], <SemanticModelGeneration>[]),
      (
        ['v0.9.98.2', 'v0.9.98.3'],
        [SemanticModelGeneration.round2, SemanticModelGeneration.qa491],
      ),
    ]) {
      test('a drive without machine records plans for its installers '
          '${scenario.$1}', () async {
        await online(() async {
          final seen = <SemanticFleet>[];
          final versions = scenario.$1;
          final manager = LibraryManager(
            dataDir: dataDir,
            mirroredOtzariaVersions: versions == null
                ? null
                : () async => versions,
            semanticAssetsFactory: (_) => _RecordingSemanticAssets(seen),
          );
          addTearDown(manager.dispose);

          await manager.peekPendingSemanticSearch();

          expect([
            for (final group in seen.single.groups) group.generation,
          ], scenario.$2);
        });
      });
    }

    test(
      'a new installer generation is served beside older recorded machines',
      () async {
        await online(() async {
          await File(p.join(dataDir, LibraryStateStore.fileName)).writeAsString(
            jsonEncode({
              'semanticMachines': {
                'offline-pc|user': const SemanticMachineState(
                  supportsWindows: false,
                  family: SemanticVectorsFamily.legacy,
                  generation: SemanticModelGeneration.round2,
                ).toJson(),
              },
            }),
          );
          final manager = LibraryManager(
            dataDir: dataDir,
            mirroredOtzariaVersions: () async => ['v0.9.98.3'],
          );
          addTearDown(manager.dispose);

          final fleet = await manager.semanticFleetForTest();

          expect(
            {for (final group in fleet.groups) group.generation},
            {SemanticModelGeneration.round2, SemanticModelGeneration.qa491},
          );
          final persisted = await LibraryStateStore(
            p.join(dataDir, LibraryStateStore.fileName),
          ).liveSemanticStates(excludeOwn: true);
          expect(persisted, hasLength(1));
          expect(persisted.single.generation, SemanticModelGeneration.round2);
        });
      },
    );

    List<String> vectorTags() => [
      for (final url in github.requests)
        if (url.path.startsWith('$_libraryReleasesPath/tags/'))
          url.pathSegments.last,
    ];

    test('without a recorded machine only the legacy vectors are asked '
        'for', () async {
      await online(() async {
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        await manager.downloadToMirror(
          includeSemanticSearch: true,
          onCompanionWarning: (_, _) {},
        );

        expect(vectorTags(), ['vectors-v2-20261011']);
        expect(github.count(_libraryReleasesPath), 1);
      });
    });

    test(
      'the online machine\'s own record does not shape the download',
      () async {
        await online(() async {
          await LibraryStateStore(
            p.join(dataDir, LibraryStateStore.fileName),
          ).recordOwnSemanticState(
            const SemanticMachineState(supportsWindows: true, family: null),
          );
          final manager = LibraryManager(dataDir: dataDir);
          addTearDown(manager.dispose);

          await manager.downloadToMirror(
            includeSemanticSearch: true,
            onCompanionWarning: (_, _) {},
          );

          expect(vectorTags(), ['vectors-v2-20261011']);
        });
      },
    );

    test('machines that all support windows vectors cost one more call, and '
        'only while that family is unpublished', () async {
      await online(() async {
        await File(p.join(dataDir, LibraryStateStore.fileName)).writeAsString(
          jsonEncode({
            'semanticMachines': {
              'offline-pc|user': const SemanticMachineState(
                supportsWindows: true,
                family: null,
              ).toJson(),
            },
          }),
        );
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        expect(await manager.peekLatestOnlineVersion(), 2);
        expect(await manager.peekPendingSemanticSearch(), isFalse);
        await manager.downloadToMirror(
          includeSemanticSearch: true,
          onCompanionWarning: (_, _) {},
        );

        expect(vectorTags(), [
          'vectors-windows-v2-20261011',
          'vectors-v2-20261011',
          'vectors-windows-v2-20261011',
          'vectors-v2-20261011',
        ]);
        expect(github.count(_libraryReleasesPath), 1);
      });
    });
  });
}

List<String> _tags(List<LibraryRelease> releases) => [
  for (final release in releases) release.tag,
];

/// סנכרון חיפוש חכם שנכשל בדרך שנבחרה בבדיקה, בלי רשת ובלי מודל.
class _FailingSemanticAssets extends SemanticSearchAssets {
  _FailingSemanticAssets(this.failure, {this.progressBeforeFailure});

  final Object failure;
  final (int, int?)? progressBeforeFailure;

  @override
  Future<void> sync({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
    String? Function(int version)? libraryTagFor,
    void Function(String)? onStage,
    void Function(int, int?)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    if (progressBeforeFailure case (final done, final total)?) {
      onBytesProgress?.call(done, total);
    }
    throw failure;
  }
}

class _RecordingSemanticAssets extends SemanticSearchAssets {
  _RecordingSemanticAssets(this.fleets);

  final List<SemanticFleet> fleets;

  @override
  Future<bool> peekPending({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
  }) async {
    fleets.add(fleet);
    return false;
  }
}

/// בדיקה קלה שמצהירה שהווקטורים שפורסמו אינם קריאים למנוע.
class _UnreadableSemanticAssets extends SemanticSearchAssets {
  @override
  SemanticEngineIncompatibleException? get peekedIncompatibility =>
      const SemanticEngineIncompatibleException(
        lineTextVersion: 1,
        keyVersion: 1,
      );

  @override
  Future<bool> peekPending({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
  }) async => false;
}

/// The real downloader against the in-memory vectors release of the library
/// tag the fixtures use.
class _RealVectorsAssets extends SemanticSearchAssets {
  _RealVectorsAssets(
    http.Client client,
    DownloadScheduler scheduler, {
    this.onSync,
  }) : super(
         scheduler: scheduler,
         httpClient: client,
         models: fakeModels,
         freeBytesFor: (_) => null,
       );

  final void Function()? onSync;

  @override
  Future<void> sync({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
    String? Function(int version)? libraryTagFor,
    void Function(String)? onStage,
    void Function(int, int?)? onBytesProgress,
    bool Function()? isCancelled,
  }) {
    onSync?.call();
    return super.sync(
      mirrorDir: mirrorDir,
      libraryTag: libraryTagOf(2),
      fleet: fleet,
      libraryTagFor: libraryTagOf,
      onStage: onStage,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
  }
}
