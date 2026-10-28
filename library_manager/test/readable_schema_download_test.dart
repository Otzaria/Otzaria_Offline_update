import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/readable_releases_client.dart';
import 'package:library_manager/src/services/recent_library_releases_client.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart' show StorageFullException;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show
        DownloadScheduler,
        LibraryUpdatePlanKind,
        OfflineLibraryUpdateDiscovery,
        OfflineLibraryUpdatePlanner,
        PatchEdge,
        LocalMirrorLibraryReleaseClient,
        fullDbArchiveNameForSchema;

import 'support/failing_writes.dart';

const _libraryReleasesPath = '/repos/Otzaria/SeforimLibrary/releases';

typedef _Patch = ({int from, int to, int fromSchema, int toSchema});

class _Release {
  const _Release(
    this.version, {
    this.fullSchemas = const [],
    this.patches = const [],
    this.prerelease = false,
    this.date = '20261011',
  });

  final int version;
  final List<int> fullSchemas;
  final List<_Patch> patches;
  final bool prerelease;

  /// A re-publish of one version carries a later date in its tag.
  final String date;

  String get tag => 'v$version-$date';
}

_Patch _patch(int from, int to, int fromSchema, int toSchema) =>
    (from: from, to: to, fromSchema: fromSchema, toSchema: toSchema);

class _FakeGithub {
  _FakeGithub(this.releases);

  List<_Release> releases;
  final requests = <Uri>[];
  bool failManifests = false;

  /// Manifest names served as `fullRebase`, and served as broken JSON.
  final rebase = <String>{};
  final broken = <String>{};

  /// Manifests served as valid JSON with a field of the wrong type.
  final mistyped = <String>{};

  /// Manifests whose first request fails with a 500; [onManifest] sees each.
  final flaky = <String>{};
  void Function(String name)? onManifest;

  /// Asset URLs re-uploaded under the same tag: a new GitHub id and time.
  final replaced = <String>{};

  /// Release tags whose patches lead to other content (`corrected-h<N>`) and
  /// weigh more, as a corrected re-publish of the same patch may.
  final corrected = <String>{};

  /// Release tags whose full DB is published split into two parts.
  final splitTags = <String>{};

  /// Sees each request for a vectors release.
  void Function()? onVectors;

  Future<void> Function()? beforeLibraryReleases;
  Future<void> Function()? beforeDictionary;

  int assetFetches() => requests
      .where((u) => u.host == 'lib' && !u.path.endsWith('.manifest.json'))
      .length;

  int get manifestFetches =>
      requests.where((u) => u.path.endsWith('.manifest.json')).length;

  _Patch? _patchNamed(String name) {
    for (final release in releases) {
      for (final patch in release.patches) {
        if ('patch-v${patch.from}-v${patch.to}.db.zst.manifest.json' == name) {
          return patch;
        }
      }
    }
    return null;
  }

  Uint8List _body(String name, [String? url]) {
    final fixed = url != null && corrected.any((tag) => url.contains('/$tag/'));
    final patch = _patchNamed(name);
    if (broken.contains(name)) return Uint8List.fromList(utf8.encode('{'));
    if (patch != null) {
      return _utf8({
        if (rebase.contains(name)) 'fullRebase': true,
        'fromVersion': patch.from,
        'toVersion': mistyped.contains(name) ? '${patch.to}' : patch.to,
        'fromSchemaVersion': patch.fromSchema,
        'toSchemaVersion': patch.toSchema,
        'patchFormatVersion': 4,
        'fromContentHash': 'h${patch.from}',
        'toContentHash': fixed ? 'corrected-h${patch.to}' : 'h${patch.to}',
        'patchFiles': [
          {
            'file': 'patch-v${patch.from}-v${patch.to}.db.zst',
            'compression': 'zstd',
            'sha256': 'unused',
            'size': fixed ? 100 : 1,
            'uncompressedSha256': 'u',
            'uncompressedSize': 99,
          },
        ],
      });
    }
    if (name == 'version.txt') return Uint8List.fromList(utf8.encode('55'));
    if (RegExp(r'^(.+)\.(manifest\.json|part-00([01]))$').firstMatch(name)
        case final split?) {
      final whole = _body(split[1]!);
      final half = whole.length ~/ 2;
      if (split[3] != null) {
        return split[3] == '0' ? whole.sublist(0, half) : whole.sublist(half);
      }
      return _utf8({
        'schemaVersion': 1,
        'archive': split[1],
        'size': whole.length,
        'sha256': '${sha256.convert(whole)}',
        'parts': [
          for (final (i, part) in [
            whole.sublist(0, half),
            whole.sublist(half),
          ].indexed)
            {
              'name': '${split[1]}.part-00$i',
              'size': part.length,
              'sha256': '${sha256.convert(part)}',
            },
        ],
      });
    }
    return Uint8List.fromList(utf8.encode('payload:$name'));
  }

  static Uint8List _utf8(Object json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  Map<String, dynamic> _asset(String name, String url) => {
    'name': name,
    'browser_download_url': url,
    'size': _body(name, url).length,
    'id': (url.hashCode.abs() + (replaced.contains(url) ? 1 : 0)),
    'updated_at': replaced.contains(url)
        ? '2026-09-01T00:00:00Z'
        : '2026-08-01T00:00:00Z',
    'digest': 'sha256:${sha256.convert(_body(name, url))}',
  };

  List<Map<String, dynamic>> _libraryReleases() => [
    for (final release in releases)
      {
        'tag_name': release.tag,
        'prerelease': release.prerelease,
        'draft': false,
        'published_at':
            '${release.date.substring(0, 4)}-${release.date.substring(4, 6)}-'
            '${release.date.substring(6)}T21:00:00Z',
        'assets': [
          for (final name in [
            for (final schema in release.fullSchemas)
              if (splitTags.contains(release.tag)) ...[
                for (final suffix in ['manifest.json', 'part-000', 'part-001'])
                  '${fullDbArchiveNameForSchema(schema)}.$suffix',
              ] else
                fullDbArchiveNameForSchema(schema),
            for (final patch in release.patches) ...[
              'patch-v${patch.from}-v${patch.to}.db.zst.manifest.json',
              'patch-v${patch.from}-v${patch.to}.db.zst',
            ],
          ])
            _asset(name, 'https://lib/${release.tag}/$name'),
        ],
      },
  ];

  Map<String, dynamic> _companion(String tag, List<String> names) => {
    'tag_name': tag,
    'assets': [for (final name in names) _asset(name, 'https://dl/$name')],
  };

  late final MockClient client = MockClient.streaming((request, _) async {
    requests.add(request.url);
    if (request.url.host == 'dl' &&
        request.url.pathSegments.last == 'lexical.db') {
      await beforeDictionary?.call();
    }
    if (request.url.path.contains('/releases/tags/')) onVectors?.call();
    final url = request.url;
    Uint8List? body;
    if (url.host == 'api.github.com') {
      if (url.path == _libraryReleasesPath) {
        await beforeLibraryReleases?.call();
      }
      body = switch (url.path) {
        _libraryReleasesPath => _utf8(
          url.queryParameters['page'] == '1' ? _libraryReleases() : [],
        ),
        '/repos/Otzaria/otzaria-library/releases/latest' => _utf8(
          _companion('lib-v9', ['talmud_bavli_latest.tar.zst']),
        ),
        '/repos/Otzaria/otzar-HB_catalog/releases/latest' => _utf8(
          _companion('cat-v3', ['otzar-HB_catalog.db.zst', 'version.txt']),
        ),
        '/repos/Otzaria/SeforimMagicIndexer/releases/latest' => _utf8(
          _companion('dict-v7', ['lexical.db']),
        ),
        _ => null,
      };
    } else if (url.path.endsWith('.manifest.json') &&
        (failManifests || flaky.remove(url.pathSegments.last))) {
      onManifest?.call(url.pathSegments.last);
      return http.StreamedResponse(const Stream.empty(), 500);
    } else if (url.pathSegments.last != 'library-changes.md') {
      if (url.path.endsWith('.manifest.json')) {
        onManifest?.call(url.pathSegments.last);
      }
      body = _body(url.pathSegments.last, url.toString());
    }
    if (body == null) return http.StreamedResponse(const Stream.empty(), 404);
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
    );
  });
}

/// v29–v30 on schema 5, v31–v32 on schema 6 (v31 by a 5→6 patch), v33 on 7.
const _mixedSchemas = [
  _Release(
    29,
    fullSchemas: [5],
    patches: [(from: 28, to: 29, fromSchema: 5, toSchema: 5)],
  ),
  _Release(
    30,
    fullSchemas: [5],
    patches: [(from: 29, to: 30, fromSchema: 5, toSchema: 5)],
  ),
  _Release(
    31,
    fullSchemas: [6],
    patches: [(from: 30, to: 31, fromSchema: 5, toSchema: 6)],
  ),
  _Release(
    32,
    fullSchemas: [6],
    patches: [(from: 31, to: 32, fromSchema: 6, toSchema: 6)],
  ),
  _Release(
    33,
    fullSchemas: [7],
    patches: [(from: 32, to: 33, fromSchema: 6, toSchema: 7)],
  ),
];

bool dictionaryFailed = false;

void main() {
  late Directory tempDir;
  late String dataDir;
  late _FakeGithub github;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('readable-download-');
    dataDir = p.join(tempDir.path, 'OtzariaData');
    await Directory(dataDir).create(recursive: true);
    github = _FakeGithub(_mixedSchemas);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<T> online<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => github.client);

  Future<MirrorDownloadOutcome> download({
    int? readableDbSchema,
    bool personal = false,
    bool semantic = false,
  }) => online(() async {
    final manager = LibraryManager(
      dataDir: dataDir,
      personalUpdateMode: personal,
    );
    addTearDown(manager.dispose);
    return manager.downloadToMirror(
      readableDbSchema: readableDbSchema,
      includeSemanticSearch: semantic,
    );
  });

  /// The vectors' release tags the smart-search sync or peek asked GitHub for.
  List<String> vectorsAsked() => [
    for (final url in github.requests)
      if (url.path.contains('/releases/tags/')) url.pathSegments.last,
  ];

  LibraryStateStore stateStore() => LibraryStateStore(
    p.join(dataDir, LibraryStateStore.fileName),
    dataDir: dataDir,
  );

  String mirrorDir() => p.join(dataDir, 'mirror', 'library');

  Future<Set<String>> mirroredAssets() async => {
    for (final release in await LocalMirrorLibraryReleaseClient(
      mirrorDir: mirrorDir(),
    ).fetchReleases())
      for (final asset in release.assets)
        if (asset.size > 0) '${release.tag}/${asset.name}',
  };

  test(
    'a settled limited download expires with installer, online or mirror changes',
    () async {
      await download(readableDbSchema: 5);
      var schema = 5;
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          mirroredReadableDbSchema: () async => schema,
        );
        addTearDown(manager.dispose);
        await manager.peekLatestOnlineVersion();
        expect(await manager.isReadableMirrorCurrent(), isTrue);
        schema = 6;
        expect(await manager.isReadableMirrorCurrent(), isFalse);
        schema = 5;
        final file = File(p.join(mirrorDir(), 'releases.json'));
        final previous = await file.readAsBytes();
        await file.writeAsString('{}');
        expect(await manager.isReadableMirrorCurrent(), isFalse);
        await file.writeAsBytes(previous);
        expect(await manager.isReadableMirrorCurrent(), isTrue);
        github.releases = [
          ...github.releases,
          const _Release(34, fullSchemas: [7]),
        ];
        await manager.peekLatestOnlineVersion();
        expect(await manager.isReadableMirrorCurrent(), isFalse);
      });
    },
  );

  test('limited size checks never plan an unfiltered export', () async {
    await online(() async {
      final manager = LibraryManager(
        dataDir: dataDir,
        mirroredReadableDbSchema: () async => 5,
      );
      addTearDown(manager.dispose);
      expect(await manager.probeMirrorDownloadBytes(), isNull);
      expect(await manager.peekedDownloadBytesBound(), isNull);
      expect(github.requests, isEmpty);
      expect(Directory(mirrorDir()).existsSync(), isFalse);
    });
  });

  test(
    'a rolled-back library manifest invalidates the saved verdict',
    () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
      ];
      await download(readableDbSchema: 5);
      final file = File(p.join(mirrorDir(), 'releases.json'));
      final before = await file.readAsBytes();
      github.releases = [
        ...github.releases,
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      await download(readableDbSchema: 5);
      await file.writeAsBytes(before);
      await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          mirroredReadableDbSchema: () async => 5,
        );
        addTearDown(manager.dispose);
        expect(await manager.isReadableMirrorCurrent(), isFalse);
        await expectLater(
          manager.peekPendingSemanticSearch(),
          throwsStateError,
        );
      });
    },
  );

  test('an old installer gets the newest schema-5 library, and why', () async {
    final outcome = await download(readableDbSchema: 5);

    final assets = await mirroredAssets();
    expect(assets, contains('v30-20261011/seforim.db.zst'));
    expect(
      assets.where((a) => a.contains('schema6') || a.contains('schema7')),
      isEmpty,
    );
    expect(
      assets.where((a) => a.contains('patch-v30-v31')),
      isEmpty,
      reason: 'a 5→6 patch must not start from the schema-5 full DB',
    );
    expect(outcome.newerNeedsOtzaria, 33);
    expect(outcome.keptNewerMirror, isFalse);
  });

  test('a schema-6 installer stops before schema 7', () async {
    final outcome = await download(readableDbSchema: 6);

    final assets = await mirroredAssets();
    expect(assets, contains('v32-20261011/seforim-schema6.db.zst'));
    expect(assets.where((a) => a.contains('schema7')), isEmpty);
    expect(assets.where((a) => a.contains('patch-v32-v33')), isEmpty);
    expect(outcome.newerNeedsOtzaria, 33);
  });

  test(
    'a compatible full DB never starts a chain into a newer schema',
    () async {
      github.releases = [
        _Release(30, fullSchemas: [5], patches: [_patch(29, 30, 5, 5)]),
        _Release(31, patches: [_patch(30, 31, 5, 6)]),
      ];

      final outcome = await download(readableDbSchema: 5);

      final assets = await mirroredAssets();
      expect(assets, contains('v30-20261011/seforim.db.zst'));
      expect(assets.where((a) => a.startsWith('v31-')), isEmpty);
      expect(
        Directory(p.join(mirrorDir(), 'assets', 'v31-20261011')).existsSync(),
        isFalse,
      );
      expect(outcome.newerNeedsOtzaria, 31);
    },
  );

  test(
    'an incompatible newer release does not block a compatible one',
    () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        const _Release(31, fullSchemas: [5, 6]),
        const _Release(32, fullSchemas: [6]),
      ];

      final outcome = await download(readableDbSchema: 5);

      expect(await mirroredAssets(), contains('v31-20261011/seforim.db.zst'));
      expect(outcome.newerNeedsOtzaria, 32);
    },
  );

  test(
    'without a limit the schema the launcher applies is downloaded',
    () async {
      final outcome = await download();

      expect(
        await mirroredAssets(),
        contains('v33-20261011/seforim-schema7.db.zst'),
      );
      expect(outcome.newerNeedsOtzaria, isNull);
    },
  );

  test('a newer mirror the old installer still reads is kept', () async {
    github.releases = [
      _Release(30, fullSchemas: [5], patches: [_patch(29, 30, 5, 5)]),
    ];
    await download(readableDbSchema: 5);
    github.releases = [
      ...github.releases,
      _Release(31, fullSchemas: [6], patches: [_patch(30, 31, 5, 6)]),
    ];
    await download(readableDbSchema: 6);
    final before = await mirroredAssets();
    expect(before, contains('v31-20261011/patch-v30-v31.db.zst'));
    expect(before, contains('v30-20261011/seforim.db.zst'));

    final outcome = await download(readableDbSchema: 5);

    expect(outcome.keptNewerMirror, isTrue);
    expect(outcome.libraryLeftAsIs, isTrue);
    expect(outcome.upToDate, isFalse);
    expect(outcome.newerNeedsOtzaria, isNull);
    expect(await mirroredAssets(), before);
  });

  test('a mirror the drive\'s installer cannot read is rebuilt', () async {
    await download();
    expect(
      await mirroredAssets(),
      isNot(contains('v30-20261011/seforim.db.zst')),
    );

    final outcome = await download(readableDbSchema: 5);

    expect(outcome.keptNewerMirror, isFalse);
    final assets = await mirroredAssets();
    expect(assets, contains('v30-20261011/seforim.db.zst'));
    expect(assets.where((a) => a.contains('schema7')), isEmpty);
  });

  test('nothing readable online leaves the drive untouched', () async {
    github.releases = [
      const _Release(31, fullSchemas: [6]),
    ];

    final outcome = await download(readableDbSchema: 5);

    expect(outcome.libraryLeftAsIs, isTrue);
    expect(outcome.newerNeedsOtzaria, 31);
    expect(File(p.join(mirrorDir(), 'releases.json')).existsSync(), isFalse);
  });

  test('a manifest that cannot be fetched fails before any asset', () async {
    github.failManifests = true;

    await expectLater(download(readableDbSchema: 5), throwsA(anything));

    expect(Directory(p.join(mirrorDir(), 'assets')).existsSync(), isFalse);
  });

  test('personal mode stops its patches at the readable schema', () async {
    await LibraryStateStore(
      p.join(dataDir, LibraryStateStore.fileName),
      dataDir: dataDir,
    ).recordOwnDbVersion(28);

    final outcome = await download(readableDbSchema: 5, personal: true);

    final assets = await mirroredAssets();
    expect(assets, contains('v30-20261011/patch-v29-v30.db.zst'));
    expect(assets.where((a) => a.startsWith('v31-')), isEmpty);
    expect(outcome.personalFromVersion, 28);
    expect(outcome.newerNeedsOtzaria, 33);
  });

  test(
    'a personal mirror whose patches start above the fleet is redone',
    () async {
      final state = LibraryStateStore(
        p.join(dataDir, LibraryStateStore.fileName),
        dataDir: dataDir,
      );
      await state.recordOwnDbVersion(30);
      await download(personal: true);
      await state.recordKnownDbVersion('another-machine', 28);

      // Readable patches 30→32 sit on the drive, but none starts at 28.
      final outcome = await download(readableDbSchema: 6, personal: true);

      expect(outcome.keptNewerMirror, isFalse);
      expect(outcome.personalFromVersion, 28);
      final assets = await mirroredAssets();
      expect(assets, contains('v29-20261011/patch-v28-v29.db.zst'));
      expect(assets, contains('v32-20261011/patch-v31-v32.db.zst'));
      expect(assets.where((a) => a.startsWith('v33-')), isEmpty);
    },
  );

  test(
    'a personal mirror beyond the readable schema is reported kept',
    () async {
      final state = LibraryStateStore(
        p.join(dataDir, LibraryStateStore.fileName),
        dataDir: dataDir,
      );
      await state.recordOwnDbVersion(30);
      await download(personal: true);
      final before = await mirroredAssets();
      expect(before, contains('v31-20261011/patch-v30-v31.db.zst'));

      final outcome = await download(readableDbSchema: 5, personal: true);

      expect(outcome.keptNewerMirror, isTrue);
      expect(outcome.upToDate, isFalse);
      expect(outcome.newerNeedsOtzaria, isNull);
      expect(await mirroredAssets(), before);
    },
  );

  group('a kept mirror must hold what justifies keeping it', () {
    Future<File> keptCarrier() async {
      github.releases = [
        _Release(30, fullSchemas: [5], patches: [_patch(29, 30, 5, 5)]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(31, fullSchemas: [6], patches: [_patch(30, 31, 5, 6)]),
      ];
      await download(readableDbSchema: 6);
      return File(
        p.join(mirrorDir(), 'assets', 'v30-20261011', 'seforim.db.zst'),
      );
    }

    test('a re-published readable version reaches the drive', () async {
      await keptCarrier();
      github.releases = [
        ...github.releases,
        _Release(
          30,
          fullSchemas: [5],
          patches: [_patch(29, 30, 5, 5)],
          date: '20261020',
        ),
      ];

      final outcome = await download(readableDbSchema: 5, semantic: true);

      expect(outcome.keptNewerMirror, isFalse);
      expect(await mirroredAssets(), contains('v30-20261020/seforim.db.zst'));
      // The vectors follow the content the drive now holds.
      expect(vectorsAsked().last, 'vectors-v30-20261020');
    });

    test('an asset replaced under the same tag reaches the drive', () async {
      await keptCarrier();
      github.replaced.add('https://lib/v30-20261011/seforim.db.zst');
      final before = github.assetFetches();

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isFalse);
      expect(
        github.requests
            .skip(before)
            .where((u) => u.path == '/v30-20261011/seforim.db.zst'),
        isNotEmpty,
      );
    });

    test('an unchanged mirror is still kept', () async {
      await keptCarrier();

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isTrue);
    });

    test('a missing full DB is downloaded again', () async {
      final carrier = await keptCarrier();
      final size = carrier.lengthSync();
      await carrier.delete();

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isFalse);
      expect(carrier.lengthSync(), size);
    });

    test('a truncated full DB is downloaded again', () async {
      final carrier = await keptCarrier();
      final size = carrier.lengthSync();
      carrier.writeAsBytesSync(carrier.readAsBytesSync().sublist(0, 3));

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isFalse);
      expect(carrier.lengthSync(), size);
    });

    test('a personal chain with a missing patch is redone', () async {
      await stateStore().recordOwnDbVersion(30);
      await download(personal: true);
      final patch = File(
        p.join(mirrorDir(), 'assets', 'v31-20261011', 'patch-v30-v31.db.zst'),
      );
      await patch.delete();

      final outcome = await download(readableDbSchema: 6, personal: true);

      expect(outcome.keptNewerMirror, isFalse);
      expect(patch.existsSync(), isTrue);
    });
  });

  group('a kept route through an older full DB and patches', () {
    // The schema-6 export reuses the v30 full DB and patches past v31 instead
    // of fetching v31's own full DB.
    Future<Set<String>> olderBaseRoute() async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
        _Release(32, fullSchemas: [6], patches: [_patch(31, 32, 5, 6)]),
      ];
      await download(readableDbSchema: 6);
      final assets = await mirroredAssets();
      expect(assets, contains('v32-20261011/patch-v31-v32.db.zst'));
      expect(assets, isNot(contains('v31-20261011/seforim.db.zst')));
      return assets;
    }

    test('an unchanged route is kept whole', () async {
      final before = await olderBaseRoute();

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isTrue);
      expect(await mirroredAssets(), before);
    });

    test('a split base full DB still counts as held', () async {
      github.splitTags.add('v30-20261011');
      final before = await olderBaseRoute();
      expect(before, contains('v30-20261011/seforim.db.zst'));

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isTrue);
      expect(await mirroredAssets(), before);
    });

    // Each is a release the exporter itself would not take in place of what
    // the drive holds, so keeping the route must be a fixed point.
    for (final (what, republish) in [
      (
        'a full re-publish of an older base',
        const _Release(30, fullSchemas: [5], date: '20261020'),
      ),
      (
        'a prerelease re-publish of the base',
        const _Release(
          30,
          fullSchemas: [5],
          date: '20261020',
          prerelease: true,
        ),
      ),
      (
        'a prerelease re-publish on the route',
        _Release(
          31,
          patches: [_patch(30, 31, 5, 5)],
          date: '20261020',
          prerelease: true,
        ),
      ),
      (
        'a patch-only re-publish of the base',
        _Release(30, patches: [_patch(29, 30, 5, 5)], date: '20261012'),
      ),
      (
        'a full-only re-publish on the route',
        const _Release(31, fullSchemas: [5], date: '20261020'),
      ),
    ]) {
      test('$what keeps the route, round after round', () async {
        await olderBaseRoute();
        github.releases = [...github.releases, republish];

        for (var round = 0; round < 2; round++) {
          await download(readableDbSchema: 6);
          final before = await mirroredAssets();
          expect(before.where((a) => a.contains('patch-v31-v32')), isNotEmpty);

          final outcome = await download(readableDbSchema: 5);

          expect(outcome.keptNewerMirror, isTrue, reason: 'round $round');
          expect(await mirroredAssets(), before);
        }
      });
    }

    test('a corrected re-publish on the route reaches the drive', () async {
      await olderBaseRoute();
      github.releases = [
        ...github.releases,
        _Release(31, patches: [_patch(30, 31, 5, 5)], date: '20261020'),
      ];

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isFalse);
      expect(
        await mirroredAssets(),
        contains('v31-20261020/patch-v30-v31.db.zst.manifest.json'),
      );
    });

    // The fake re-uploads the same bytes, so the exporter rightly keeps the
    // file; what must change is the identity the drive records for it.
    String? recordedUpdate(String tag, String name) {
      final json =
          jsonDecode(
                File(p.join(mirrorDir(), 'releases.json')).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final release in json['releases'] as List) {
        if (release['tag'] != tag) continue;
        for (final asset in release['assets'] as List) {
          if (asset['name'] == name) return asset['updatedAt'] as String?;
        }
      }
      return null;
    }

    test('a patch file replaced on the route reaches the drive', () async {
      await olderBaseRoute();
      github.replaced.add('https://lib/v31-20261011/patch-v30-v31.db.zst');

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isFalse);
      expect(
        recordedUpdate('v31-20261011', 'patch-v30-v31.db.zst'),
        '2026-09-01T00:00:00Z',
      );
    });

    test('a replaced base full DB reaches the drive', () async {
      await olderBaseRoute();
      github.replaced.add('https://lib/v30-20261011/seforim.db.zst');

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.keptNewerMirror, isFalse);
      expect(
        recordedUpdate('v30-20261011', 'seforim.db.zst'),
        isNot('2026-08-01T00:00:00Z'),
      );
    });
  });

  group('the vectors follow the plan the engine builds', () {
    // The real offline discovery and planner over the drive, as an offline
    // machine at [local] (null = empty) would run them.
    Future<PatchEdge?> planned({int? local}) async {
      final discovery = await OfflineLibraryUpdateDiscovery(
        client: LocalMirrorLibraryReleaseClient(mirrorDir: mirrorDir()),
        supportedDbSchemaVersion: 5,
      ).discover(allowPrerelease: false);
      final plan = const OfflineLibraryUpdatePlanner().plan(
        localVersion: local ?? 0,
        hasLocalVersionMeta: local != null,
        latestVersion: discovery.latestVersion,
        edges: discovery.edges,
        latestFullDbAsset: discovery.latestFullDbAsset,
        fullDbReleaseTag: discovery.fullDbReleaseTag,
        latestFullDbVersion: discovery.latestFullDbVersion,
      );
      final steps = plan.kind == LibraryUpdatePlanKind.delta
          ? plan.deltaSteps
          : plan.followUpDelta?.deltaSteps ?? const <PatchEdge>[];
      return steps.lastOrNull;
    }

    String tagOf(PatchEdge edge) => p.basename(p.dirname(edge.manifestUrl));

    Future<void> twoPatchContents({required String corrected}) async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
        _Release(31, patches: [_patch(30, 31, 5, 5)], date: '20261020'),
      ];
      github.corrected.add(corrected);
      github.requests.clear();
    }

    for (final (corrected, expected, hash) in [
      ('v31-20261020', 'v31-20261011', 'h31'),
      ('v31-20261011', 'v31-20261020', 'h31'),
    ]) {
      test('two contents of one patch: the planned one, not the latest '
          '($expected)', () async {
        await twoPatchContents(corrected: corrected);

        await download(readableDbSchema: 5, semantic: true);

        final edge = (await planned())!;
        expect(tagOf(edge), expected);
        expect(edge.manifest.toContentHash, hash);
        expect(vectorsAsked(), ['vectors-$expected']);
      });
    }

    test('starts that install different content leave it unknown', () async {
      github.releases = [
        const _Release(29, fullSchemas: [5]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(30, patches: [_patch(29, 30, 5, 5)]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
        _Release(31, patches: [_patch(29, 31, 5, 5)], date: '20261020'),
      ];
      github.corrected.add('v31-20261020');
      github.requests.clear();

      await download(readableDbSchema: 5, semantic: true);

      expect((await planned())!.manifest.toContentHash, 'corrected-h31');
      expect((await planned(local: 30))!.manifest.toContentHash, 'h31');
      expect(vectorsAsked(), isEmpty);
      final decided = await stateStore().loadReadableSemanticTarget();
      expect(decided?['unknown'], isTrue);
      await expectLater(
        online(() async {
          final manager = LibraryManager(
            dataDir: dataDir,
            mirroredReadableDbSchema: () async => 5,
          );
          addTearDown(manager.dispose);
          return manager.peekPendingSemanticSearch();
        }),
        throwsStateError,
      );
    });

    test('a machine below the base counts too', () async {
      github.releases = [
        const _Release(29, fullSchemas: [5]),
        _Release(30, fullSchemas: [5], patches: [_patch(29, 30, 5, 5)]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
        _Release(31, patches: [_patch(29, 31, 5, 5)], date: '20261020'),
      ];
      github.corrected.add('v31-20261020');
      github.requests.clear();

      await download(readableDbSchema: 5, semantic: true);

      expect((await planned())!.manifest.toContentHash, 'h31');
      expect(
        (await planned(local: 29))!.manifest.toContentHash,
        'corrected-h31',
      );
      expect(vectorsAsked(), isEmpty);
      expect(
        (await stateStore().loadReadableSemanticTarget())?['unknown'],
        isTrue,
      );
    });

    test('a full DB and a patch of one release are one content', () async {
      github.releases = [
        const _Release(29, fullSchemas: [5]),
        _Release(30, fullSchemas: [5], patches: [_patch(29, 30, 5, 5)]),
      ];

      await download(readableDbSchema: 5, semantic: true);

      expect(
        await mirroredAssets(),
        contains('v30-20261011/patch-v29-v30.db.zst'),
      );
      expect(vectorsAsked(), ['vectors-v30-20261011']);
    });

    test('personal mode follows its own plan', () async {
      await twoPatchContents(corrected: 'v31-20261020');
      await stateStore().recordOwnDbVersion(30);

      await download(readableDbSchema: 5, personal: true, semantic: true);

      final edge = (await planned(local: 30))!;
      expect(tagOf(edge), 'v31-20261011');
      expect(vectorsAsked(), ['vectors-v31-20261011']);
    });

    test('an unknown personal answer is never "nothing pending"', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
        const _Release(31, fullSchemas: [5], date: '20261020'),
      ];
      await download(readableDbSchema: 5);
      await stateStore().recordOwnDbVersion(31);

      await download(readableDbSchema: 5, personal: true, semantic: true);

      final decided = await stateStore().loadReadableSemanticTarget();
      expect(decided?['tag'], isNull);
      expect(decided?['unknown'], isTrue);
      await expectLater(
        online(() async {
          final manager = LibraryManager(
            dataDir: dataDir,
            personalUpdateMode: true,
            mirroredReadableDbSchema: () async => 5,
          );
          addTearDown(manager.dispose);
          return manager.peekPendingSemanticSearch();
        }),
        throwsStateError,
      );
    });

    test('nothing readable is still a proven "nothing pending"', () async {
      github.releases = [
        const _Release(30, fullSchemas: [6]),
      ];

      await download(readableDbSchema: 5, semantic: true);

      expect(vectorsAsked(), isEmpty);
      final pending = await online(() async {
        final manager = LibraryManager(
          dataDir: dataDir,
          mirroredReadableDbSchema: () async => 5,
        );
        addTearDown(manager.dispose);
        return manager.peekPendingSemanticSearch();
      });
      expect(pending, isFalse);
    });
  });

  group('smart search follows the library the drive reaches', () {
    test('a patch-only newest release names the vectors', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];

      await download(readableDbSchema: 5, semantic: true);

      expect(vectorsAsked(), ['vectors-v31-20261011']);
    });

    test('personal mode names the version its patches reach', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
        _Release(32, fullSchemas: [6], patches: [_patch(31, 32, 5, 6)]),
      ];
      await stateStore().recordOwnDbVersion(30);

      await download(readableDbSchema: 5, personal: true, semantic: true);

      expect(vectorsAsked(), ['vectors-v31-20261011']);
    });

    test('a kept mirror names the version its installer reaches', () async {
      github.releases = [
        _Release(30, fullSchemas: [5], patches: [_patch(29, 30, 5, 5)]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(31, fullSchemas: [6], patches: [_patch(30, 31, 5, 6)]),
      ];
      await download(readableDbSchema: 6);
      github.requests.clear();

      final outcome = await download(readableDbSchema: 5, semantic: true);

      expect(outcome.keptNewerMirror, isTrue);
      expect(vectorsAsked(), ['vectors-v30-20261011']);
    });

    group('the vectors follow the content the route delivers', () {
      Future<void> peek() async {
        try {
          await online(() async {
            final manager = LibraryManager(
              dataDir: dataDir,
              mirroredReadableDbSchema: () async => 5,
            );
            addTearDown(manager.dispose);
            return manager.peekPendingSemanticSearch();
          });
        } catch (_) {
          // The fake serves no vectors; only the tag asked about matters.
        }
      }

      // v31's content reaches the drive as the 30→31 patch; a later
      // full-only re-publish of v31 stays online, its record notwithstanding.
      Future<void> keptPatchRoute() async {
        github.releases = [
          const _Release(30, fullSchemas: [5]),
        ];
        await download(readableDbSchema: 5);
        github.releases = [
          ...github.releases,
          _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
          _Release(32, fullSchemas: [6], patches: [_patch(31, 32, 5, 6)]),
        ];
        await download(readableDbSchema: 6);
        github.releases = [
          ...github.releases,
          const _Release(31, fullSchemas: [5], date: '20261020'),
        ];
        await download(readableDbSchema: 6);
        final held = await mirroredAssets();
        expect(held, contains('v31-20261011/patch-v30-v31.db.zst'));
        expect(held, isNot(contains('v31-20261020/seforim.db.zst')));
        github.requests.clear();
      }

      test('a kept patch route names the patch\'s release', () async {
        await keptPatchRoute();

        final outcome = await download(readableDbSchema: 5, semantic: true);

        expect(outcome.keptNewerMirror, isTrue);
        expect(vectorsAsked(), ['vectors-v31-20261011']);
        expect(
          (await stateStore().loadReadableSemanticTarget())?['tag'],
          'v31-20261011',
        );
      });

      test('the peek after it asks the same, from names alone', () async {
        await keptPatchRoute();
        await download(readableDbSchema: 5, semantic: true);
        github.requests.clear();

        await peek();

        expect(vectorsAsked(), ['vectors-v31-20261011']);
        expect(github.manifestFetches, 0);
      });

      test('names alone would point at a full DB the drive skipped', () async {
        github.releases = [
          const _Release(30, fullSchemas: [5]),
        ];
        await download(readableDbSchema: 5);
        github.releases = [
          ...github.releases,
          _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
          const _Release(31, fullSchemas: [5], date: '20261020'),
        ];
        await download(readableDbSchema: 5, semantic: true);
        expect(
          await mirroredAssets(),
          isNot(contains('v31-20261020/seforim.db.zst')),
        );
        github.requests.clear();

        await peek();

        expect(vectorsAsked(), ['vectors-v31-20261011']);
        expect(github.manifestFetches, 0);
      });

      test('a personal decision does not answer a fleet peek', () async {
        github.releases = [
          const _Release(30, fullSchemas: [5]),
          _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
          const _Release(31, fullSchemas: [5], date: '20261020'),
        ];
        await download(readableDbSchema: 5);
        await stateStore().recordOwnDbVersion(31);
        await download(readableDbSchema: 5, personal: true, semantic: true);
        expect(
          (await stateStore().loadReadableSemanticTarget())?['tag'],
          isNull,
        );

        // The personal "nothing to name" would read as "nothing pending"; with
        // two v31 releases, names alone must say "unknown" instead.
        await expectLater(
          online(() async {
            final manager = LibraryManager(
              dataDir: dataDir,
              mirroredReadableDbSchema: () async => 5,
            );
            addTearDown(manager.dispose);
            return manager.peekPendingSemanticSearch();
          }),
          throwsStateError,
        );
      });

      test('a decision does not outlive its mirror', () async {
        await keptPatchRoute();
        await download(readableDbSchema: 5, semantic: true);
        await Directory(mirrorDir()).delete(recursive: true);
        github.requests.clear();

        await peek();

        expect(vectorsAsked(), isNot(contains('vectors-v31-20261011')));
      });

      test('a re-publish since the download voids the old answer', () async {
        await keptPatchRoute();
        await download(readableDbSchema: 5, semantic: true);
        github.releases = [
          ...github.releases,
          _Release(31, patches: [_patch(30, 31, 5, 5)], date: '20261025'),
        ];
        github.requests.clear();

        await peek();

        expect(vectorsAsked(), isNot(contains('vectors-v31-20261011')));
      });

      test('a re-published patch the drive takes names its release', () async {
        await keptPatchRoute();
        github.releases = [
          ...github.releases,
          _Release(31, patches: [_patch(30, 31, 5, 5)], date: '20261025'),
        ];

        await download(readableDbSchema: 5, semantic: true);

        expect(
          await mirroredAssets(),
          contains('v31-20261025/patch-v30-v31.db.zst'),
        );
        expect(vectorsAsked(), ['vectors-v31-20261025']);
        github.requests.clear();
        await peek();
        expect(vectorsAsked(), ['vectors-v31-20261025']);
      });

      test(
        'a re-published full DB the drive takes names its release',
        () async {
          github.releases = [
            _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
            _Release(
              31,
              fullSchemas: [5],
              patches: [_patch(30, 31, 5, 5)],
              date: '20261020',
            ),
          ];

          await download(readableDbSchema: 5, semantic: true);

          expect(
            await mirroredAssets(),
            contains('v31-20261020/seforim.db.zst'),
          );
          expect(vectorsAsked(), ['vectors-v31-20261020']);
        },
      );

      // The old patch still leads a machine at v30 to the old v31, and
      // nothing proves the re-published full DB holds the same content.
      test('a full-only re-publish beside an old patch is unknown', () async {
        github.releases = [
          _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
          const _Release(31, fullSchemas: [5], date: '20261020'),
        ];

        await download(readableDbSchema: 5, semantic: true);

        expect(
          await mirroredAssets(),
          contains('v31-20261011/patch-v30-v31.db.zst'),
        );
        expect(vectorsAsked(), isEmpty);
        expect(
          (await stateStore().loadReadableSemanticTarget())?['unknown'],
          isTrue,
        );
      });

      test('personal mode at a re-published version names no guess', () async {
        github.releases = [
          const _Release(30, fullSchemas: [5]),
          _Release(31, fullSchemas: [5], patches: [_patch(30, 31, 5, 5)]),
        ];
        await download(readableDbSchema: 5);
        await stateStore().recordOwnDbVersion(31);
        github.requests.clear();

        await download(readableDbSchema: 5, personal: true, semantic: true);
        expect(vectorsAsked(), [
          'vectors-v31-20261011',
        ], reason: 'one release of v31 leaves nothing to guess');

        github.releases = [
          ...github.releases,
          const _Release(31, fullSchemas: [5], date: '20261020'),
        ];
        github.requests.clear();

        await download(readableDbSchema: 5, personal: true, semantic: true);

        expect(vectorsAsked(), isEmpty);
        final decided = await stateStore().loadReadableSemanticTarget();
        expect(decided, isNotNull);
        expect(decided!['tag'], isNull);
      });
    });

    test('a re-published version names its latest release', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        const _Release(30, fullSchemas: [5], date: '20261020'),
      ];

      await download(readableDbSchema: 5, semantic: true);

      expect(vectorsAsked(), ['vectors-v30-20261020']);
    });

    test('a re-publish the installer cannot read is not the target', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        const _Release(30, fullSchemas: [6], date: '20261020'),
      ];

      await download(readableDbSchema: 5, semantic: true);
      final downloaded = vectorsAsked();
      github.requests.clear();
      try {
        await online(() async {
          final manager = LibraryManager(
            dataDir: dataDir,
            mirroredReadableDbSchema: () async => 5,
          );
          addTearDown(manager.dispose);
          return manager.peekPendingSemanticSearch();
        });
      } catch (_) {
        // The fake serves no vectors; only the tag asked about matters.
      }

      expect(downloaded, ['vectors-v30-20261011']);
      expect(vectorsAsked(), downloaded);
    });

    test('unreadable metadata still syncs the reachable library', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
      ];
      await download(readableDbSchema: 5);
      github.releases = [
        ...github.releases,
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      github.broken.add('patch-v30-v31.db.zst.manifest.json');
      github.requests.clear();

      final outcome = await download(readableDbSchema: 5, semantic: true);

      expect(outcome.libraryLeftAsIs, isTrue);
      expect(vectorsAsked(), ['vectors-v30-20261011']);
    });

    test('a cancelled download leaves no decision behind', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      var cancelled = false;
      github.onVectors = () => cancelled = true;

      await expectLater(
        online(() async {
          final manager = LibraryManager(dataDir: dataDir);
          addTearDown(manager.dispose);
          return manager.downloadToMirror(
            readableDbSchema: 5,
            includeSemanticSearch: true,
            isCancelled: () => cancelled,
          );
        }),
        throwsA(anything),
      );

      expect(await stateStore().loadReadableSemanticTarget(), isNull);
    });
  });

  group('smart-search peek under the drive\'s limit', () {
    Future<bool> peekWith(int schema) => online(() async {
      final manager = LibraryManager(
        dataDir: dataDir,
        mirroredReadableDbSchema: () async => schema,
      );
      addTearDown(manager.dispose);
      return manager.peekPendingSemanticSearch();
    });

    test('reads back what the last download decided from manifests', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      await download(readableDbSchema: 5, semantic: true);
      github.requests.clear();

      try {
        await peekWith(5);
      } catch (_) {
        // The fake serves no vectors; only the tag asked about matters.
      }

      expect(vectorsAsked(), ['vectors-v31-20261011']);
      expect(github.manifestFetches, 0);
    });

    test('a patch it cannot judge without a manifest is not guessed', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];

      await expectLater(peekWith(5), throwsStateError);
      expect(vectorsAsked(), isEmpty);
      expect(github.manifestFetches, 0);
    });

    test('a new release online makes the old decision stale', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      await download(readableDbSchema: 5, semantic: true);
      github.releases = [
        ...github.releases,
        _Release(32, patches: [_patch(31, 32, 5, 6)]),
      ];

      await expectLater(peekWith(5), throwsStateError);
    });

    test('a re-published base makes the old decision stale', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      await download(readableDbSchema: 5, semantic: true);
      github.releases = [
        ...github.releases,
        const _Release(30, fullSchemas: [5], date: '20261020'),
      ];

      await expectLater(peekWith(5), throwsStateError);
    });
  });

  group('metadata that cannot be read proves nothing', () {
    Future<void> v30OnDrive() async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
      ];
      await download(readableDbSchema: 5);
      await stateStore().recordOwnDbVersion(30);
      github.releases = [
        ...github.releases,
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
    }

    for (final (label, mark) in [
      ('broken JSON', (_FakeGithub g, String n) => g.broken.add(n)),
      (
        'a field of the wrong type',
        (_FakeGithub g, String n) => g.mistyped.add(n),
      ),
    ]) {
      test('$label is not "up to date", and the drive keeps v30', () async {
        await v30OnDrive();
        mark(github, 'patch-v30-v31.db.zst.manifest.json');

        final outcome = await download(readableDbSchema: 5, personal: true);

        expect(outcome.upToDate, isFalse);
        expect(outcome.unreadableManifests, {
          'patch-v30-v31.db.zst.manifest.json',
        });
        expect(
          File(
            p.join(mirrorDir(), 'assets', 'v30-20261011', 'seforim.db.zst'),
          ).existsSync(),
          isTrue,
        );
        expect(outcome.libraryLeftAsIs, isTrue);
      });
    }

    test('beside readable progress, the export still runs', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        const _Release(31, fullSchemas: [5]),
        _Release(32, patches: [_patch(31, 32, 5, 5)]),
      ];
      github.broken.add('patch-v31-v32.db.zst.manifest.json');

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.libraryLeftAsIs, isFalse);
      expect(outcome.unreadableManifests, isNotEmpty);
      final assets = await mirroredAssets();
      expect(assets, contains('v31-20261011/seforim.db.zst'));
      // The engine keeps it, so offline the version does not vanish.
      expect(
        assets,
        contains('v32-20261011/patch-v31-v32.db.zst.manifest.json'),
      );
    });
  });

  test(
    'a barrier within the readable schema is not a readable version',
    () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 5)]),
      ];
      github.rebase.add('patch-v30-v31.db.zst.manifest.json');

      final outcome = await download(readableDbSchema: 5);

      expect(outcome.newerNeedsOtzaria, isNull);
      final assets = await mirroredAssets();
      expect(assets, contains('v30-20261011/seforim.db.zst'));
      // The barrier stays for the planner; no patch file comes with it.
      expect(
        assets,
        contains('v31-20261011/patch-v30-v31.db.zst.manifest.json'),
      );
      expect(assets, isNot(contains('v31-20261011/patch-v30-v31.db.zst')));
      final check = await LibraryManager(dataDir: dataDir).checkForUpdate();
      expect(check.plan?.kind, LibraryUpdatePlanKind.fullDownload);
      expect(check.plan?.targetVersion, 30);
    },
  );

  test('a blocked version brings no heavy download twice', () async {
    await download(readableDbSchema: 5);
    final before = github.assetFetches();

    final outcome = await download(readableDbSchema: 5);

    expect(outcome.newerNeedsOtzaria, 33);
    expect(github.assetFetches(), before);
  });

  group('smart-search peek under the drive\'s limit (certain)', () {
    Future<bool> peek(int? schema) => online(() async {
      final manager = LibraryManager(
        dataDir: dataDir,
        mirroredReadableDbSchema: () async => schema,
      );
      addTearDown(manager.dispose);
      return manager.peekPendingSemanticSearch();
    });

    bool askedForVectors() =>
        github.requests.any((u) => u.path.contains('/releases/tags/'));

    test('nothing readable online is never pending', () async {
      github.releases = [
        const _Release(31, fullSchemas: [6]),
      ];

      expect(await peek(5), isFalse);
      expect(askedForVectors(), isFalse);
    });

    test('asks about the newest library the installer reads', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        const _Release(31, fullSchemas: [6]),
      ];

      try {
        await peek(5);
      } catch (_) {
        // The fake serves no vectors; only the tag asked about matters.
      }

      final asked = github.requests
          .where((u) => u.path.contains('/releases/tags/'))
          .map((u) => u.pathSegments.last);
      expect(asked, contains('vectors-v30-20261011'));
      expect(asked, isNot(contains('vectors-v31-20261011')));
    });

    test('no installer on the drive is never pending', () async {
      expect(await peek(null), isFalse);
      expect(askedForVectors(), isFalse);
    });
  });

  group('ReadableReleasesClient', () {
    ReadableReleasesClient clientFor({
      required int readableSchema,
      bool allowPrerelease = false,
      int? fromVersion,
      int historyDepth = 10,
    }) => ReadableReleasesClient(
      RecentLibraryReleasesClient(httpClient: github.client),
      readableSchema: readableSchema,
      allowPrerelease: allowPrerelease,
      fromVersion: fromVersion,
      historyDepth: historyDepth,
    );

    List<_Release> chain(int from, int to) => [
      for (var v = from; v <= to; v++)
        _Release(v, fullSchemas: [5], patches: [_patch(v - 1, v, 5, 5)]),
    ];

    test('reads only the manifests the exporter will keep', () async {
      github.releases = chain(1, 30);
      final client = clientFor(readableSchema: 5, historyDepth: 3);

      final releases = await client.fetchReleases();

      expect(github.manifestFetches, 3);
      expect(client.newestReadableVersion, 30);
      final old = releases.firstWhere((r) => r.tag.startsWith('v10-'));
      expect(old.deltaManifestAssets, isEmpty);
      expect(old.fullDbAssetFor(maxSchemaVersion: 5), isNotNull);
    });

    test('personal mode reads every manifest above its version', () async {
      github.releases = chain(1, 30);
      final client = clientFor(
        readableSchema: 5,
        historyDepth: 3,
        fromVersion: 20,
      );

      await client.fetchReleases();

      expect(github.manifestFetches, 12);
    });

    test('the exporter gets the manifests already read', () async {
      github.releases = chain(1, 2);
      final client = clientFor(readableSchema: 5);
      final releases = await client.fetchReleases();
      final fetched = github.manifestFetches;

      await client.fetchManifest(
        releases.first.deltaManifestAssets.single.downloadUrl,
      );

      expect(github.manifestFetches, fetched);
    });

    test('the release channel rules stay as they were', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        const _Release(31, fullSchemas: [5], prerelease: true),
      ];

      final stable = clientFor(readableSchema: 5);
      await stable.fetchReleases();
      final withPrerelease = clientFor(
        readableSchema: 5,
        allowPrerelease: true,
      );
      await withPrerelease.fetchReleases();

      expect(stable.newestReadableVersion, 30);
      expect(withPrerelease.newestReadableVersion, 31);
    });

    test('a barrier or unreadable manifest is not a readable edge', () async {
      github.releases = [
        const _Release(30, fullSchemas: [5]),
        _Release(31, patches: [_patch(30, 31, 5, 6)]),
        _Release(32, patches: [_patch(31, 32, 5, 5)]),
      ];
      github.rebase.add('patch-v30-v31.db.zst.manifest.json');
      github.broken.add('patch-v31-v32.db.zst.manifest.json');

      final client = clientFor(readableSchema: 5);
      final releases = await client.fetchReleases();

      expect(client.newestReadableVersion, 30);
      expect(client.newerUnreadableVersion, isNull);
      // The broken one stays, as the exporter keeps it, and is reported.
      expect(releases.expand((r) => r.deltaManifestAssets).map((a) => a.name), [
        'patch-v31-v32.db.zst.manifest.json',
      ]);
      expect(client.unreadableManifests, {
        'patch-v31-v32.db.zst.manifest.json',
      });
    });

    test('a cancel mid-batch starts no queued manifest', () async {
      github.releases = chain(1, 20);
      var cancelled = false;
      github.onManifest = (_) => cancelled = true;
      final client = ReadableReleasesClient(
        RecentLibraryReleasesClient(httpClient: github.client),
        readableSchema: 5,
        allowPrerelease: false,
        scheduler: DownloadScheduler(),
        isCancelled: () => cancelled,
      );

      await expectLater(client.fetchReleases(), throwsA(anything));
      // Only those already holding one of the scheduler's slots went out.
      expect(github.manifestFetches, lessThanOrEqualTo(4));
    });

    test('a cancel during a retry sends no retry', () async {
      github.releases = chain(1, 1);
      github.flaky.add('patch-v0-v1.db.zst.manifest.json');
      var cancelled = false;
      github.onManifest = (_) => cancelled = true;
      final client = ReadableReleasesClient(
        RecentLibraryReleasesClient(httpClient: github.client),
        readableSchema: 5,
        allowPrerelease: false,
        isCancelled: () => cancelled,
      );

      await expectLater(client.fetchReleases(), throwsA(anything));
      expect(github.manifestFetches, 1);
    });

    test('a cancel stops the manifest scan', () async {
      github.releases = chain(1, 30);
      final client = ReadableReleasesClient(
        RecentLibraryReleasesClient(httpClient: github.client),
        readableSchema: 5,
        allowPrerelease: false,
        isCancelled: () => true,
      );

      await expectLater(client.fetchReleases(), throwsA(anything));
      expect(github.manifestFetches, 0);
    });

    test(
      'an emptied release above the newest readable one is dropped',
      () async {
        github.releases = [
          const _Release(30, fullSchemas: [5]),
          const _Release(31, fullSchemas: [6]),
        ];

        final releases = await clientFor(readableSchema: 5).fetchReleases();

        expect(releases.map((r) => r.tag), ['v30-20261011']);
      },
    );
  });

  group('a full drive in a companion under a readable schema', () {
    Future<Object?> downloadWithFullDictionary() async {
      Object? thrown;
      await runWithFailingRandomWrites(
        () async {
          try {
            await download(readableDbSchema: 5);
          } catch (error) {
            thrown = error;
          }
        },
        matches: (path) {
          final hit = p.basename(path) == 'lexical.db';
          if (hit) dictionaryFailed = true;
          return hit;
        },
      );
      return thrown;
    }

    setUp(() => dictionaryFailed = false);

    test('a finished export keeps its readable target', () async {
      github.beforeDictionary = () async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!File(p.join(mirrorDir(), 'releases.json')).existsSync() &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      };

      final thrown = await downloadWithFullDictionary();

      expect(thrown, isA<StorageFullException>(), reason: '$thrown');
      expect(await mirroredAssets(), contains('v30-20261011/seforim.db.zst'));
      expect(
        (await stateStore().loadReadableSemanticTarget())?['tag'],
        'v30-20261011',
      );
    });

    test('an export stopped by it leaves the previous target and a '
        'consistent mirror', () async {
      await stateStore().saveReadableSemanticTarget({
        'schema': 5,
        'tag': 'previous-tag',
        'unknown': false,
      });
      github.beforeLibraryReleases = () async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!dictionaryFailed && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      };

      final thrown = await downloadWithFullDictionary();

      expect(thrown, isA<StorageFullException>(), reason: '$thrown');
      expect(github.assetFetches(), 0);
      expect(
        (await stateStore().loadReadableSemanticTarget())?['tag'],
        'previous-tag',
      );
      final manifest = File(p.join(mirrorDir(), 'releases.json'));
      if (manifest.existsSync()) {
        for (final asset in await mirroredAssets()) {
          expect(
            File(p.join(mirrorDir(), 'assets', asset)).existsSync(),
            isTrue,
            reason: '$asset is named but missing',
          );
        }
      }
    });
  });
}
