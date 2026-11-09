import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/unpicked_patches.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

const _mb = 1 << 20;

LibraryRelease _release(String tag, Map<String, int> assets) => LibraryRelease(
  tag: tag,
  isPrerelease: false,
  isDraft: false,
  publishedAt: null,
  assets: [
    for (final e in assets.entries)
      ReleaseAsset(name: e.key, downloadUrl: '$tag/${e.key}', size: e.value),
  ],
);

DeltaManifest _manifest(
  int from,
  int to, {
  bool fullRebase = false,
  String? file,
}) => DeltaManifest(
  fromVersion: from,
  toVersion: to,
  fromSchemaVersion: kSupportedDbSchemaVersion,
  toSchemaVersion: kSupportedDbSchemaVersion,
  patchFormatVersion: kSupportedPatchFormatVersion,
  fromContentHash: 'a',
  toContentHash: 'b',
  fullRebase: fullRebase,
  patchFiles: [
    PatchFileEntry(
      file: file ?? 'patch-v$from-v$to.db.zst',
      compression: 'zstd',
      sha256: 's',
      size: _mb,
      uncompressedSha256: 'u',
      uncompressedSize: _mb,
    ),
  ],
);

Future<DeltaManifest> _fetch(String url) async {
  final m = RegExp(r'patch-v(\d+)-v(\d+)').firstMatch(url)!;
  return _manifest(int.parse(m[1]!), int.parse(m[2]!));
}

Map<String, int> _edge(int from, int to) => {
  'patch-v$from-v$to.db.zst': _mb,
  'patch-v$from-v$to.db.zst.manifest.json': 500,
};

// 1→3 is one hop shorter than 1→2→3, so 1→2 is never picked.
List<LibraryRelease> _shortcut() => [
  _release('v3', {
    'seforim.db.zst': 1000 * _mb,
    ..._edge(2, 3),
    ..._edge(1, 3),
  }),
  _release('v2', {'seforim.db.zst': 1000 * _mb, ..._edge(1, 2)}),
];

Set<String> _names(List<LibraryRelease> releases) => {
  for (final r in releases)
    for (final a in r.assets) '${r.tag}/${a.name}',
};

void main() {
  group('pickedEdges', () {
    test('an edge with a shorter route above it is not picked', () {
      expect(
        pickedEdges(
          edges: const [
            (from: 1, to: 2, bytes: _mb),
            (from: 2, to: 3, bytes: _mb),
            (from: 1, to: 3, bytes: _mb),
          ],
          fullDbBytes: 1000 * _mb,
          fullDbVersion: 3,
        ),
        {1, 2},
      );
    });

    test('the v37 shape: a heavy edge loses to the full DB', () {
      expect(
        pickedEdges(
          edges: const [
            (from: 34, to: 37, bytes: 250 * _mb),
            (from: 35, to: 37, bytes: 90 * _mb),
            (from: 36, to: 37, bytes: 88 * _mb),
          ],
          fullDbBytes: 1900 * _mb,
          fullDbVersion: 37,
        ),
        {1, 2},
      );
    });

    test('the follow-up after an older full DB is always picked', () {
      expect(
        pickedEdges(
          edges: const [
            (from: 1, to: 2, bytes: _mb),
            (from: 2, to: 3, bytes: _mb),
            (from: 1, to: 3, bytes: _mb),
          ],
          fullDbBytes: 1000 * _mb,
          fullDbVersion: 2,
        ),
        {1, 2},
      );
    });

    test('null when every edge is picked or there is no full DB', () {
      expect(
        pickedEdges(
          edges: const [
            (from: 1, to: 2, bytes: _mb),
            (from: 2, to: 3, bytes: _mb),
          ],
          fullDbBytes: 1000 * _mb,
          fullDbVersion: 3,
        ),
        isNull,
      );
      expect(
        pickedEdges(
          edges: const [(from: 1, to: 3, bytes: _mb)],
          fullDbBytes: 0,
          fullDbVersion: 3,
        ),
        isNull,
      );
    });
  });

  group('pruneUnpickedPatches', () {
    Future<({List<LibraryRelease> releases, int dropped})> prune(
      List<LibraryRelease> releases, {
      Future<DeltaManifest> Function(String)? fetch,
      bool Function(LibraryRelease, ReleaseAsset)? onDrive,
      List<LibraryRelease> Function(List<LibraryRelease>)? relevantOf,
    }) => pruneUnpickedPatches(
      releases: releases,
      relevantOf: relevantOf ?? (all) => all,
      fetchManifest: fetch ?? _fetch,
      onDrive: onDrive ?? (_, _) => false,
    );

    test('drops the unpicked edge and its manifest, nothing else', () async {
      final result = await prune(_shortcut());
      expect(result.dropped, 2);
      expect(_names(_shortcut()).difference(_names(result.releases)), {
        'v2/patch-v1-v2.db.zst',
        'v2/patch-v1-v2.db.zst.manifest.json',
      });
    });

    test('a barrier manifest is neither an edge nor dropped', () async {
      final releases = [
        ..._shortcut(),
        _release('v4', {'seforim.db.zst': 1000 * _mb, ..._edge(3, 4)}),
      ];
      final result = await prune(
        releases,
        fetch: (url) async => url.contains('v3-v4')
            ? _manifest(3, 4, fullRebase: true)
            : _fetch(url),
      );
      expect(
        _names(result.releases),
        containsAll(['v4/patch-v3-v4.db.zst.manifest.json']),
      );
    });

    test('a manifest that fails to load stops the pruning', () async {
      expect(
        () => prune(_shortcut(), fetch: (_) => Future.error(Exception('net'))),
        throwsException,
      );
    });

    test(
      'an older full DB on the drive may be kept, so nothing goes',
      () async {
        final result = await prune(
          _shortcut(),
          onDrive: (release, _) => release.tag == 'v2',
        );
        expect(result.dropped, 0);
      },
    );

    test('the newest full DB on the drive does not stop it', () async {
      final result = await prune(_shortcut(), onDrive: (_, _) => true);
      expect(result.dropped, 2);
    });

    test('pruning that would change the release selection is undone', () async {
      // A selection keyed on patch content: losing v1→v2 empties v2.
      List<LibraryRelease> withPatches(List<LibraryRelease> all) => [
        for (final r in all)
          if (r.assets.any((a) => a.name.startsWith('patch-'))) r,
      ];
      final releases = [
        _release('v3', {
          'seforim.db.zst': 1000 * _mb,
          ..._edge(2, 3),
          ..._edge(1, 3),
        }),
        _release('v2', _edge(1, 2)),
      ];
      final result = await prune(releases, relevantOf: withPatches);
      expect(result.dropped, 0);
      expect(identical(result.releases, releases), isTrue);
    });

    test('a patch file two manifests share stops the pruning', () async {
      final result = await prune(
        _shortcut(),
        fetch: (url) async => url.contains('v2-v3')
            ? _manifest(2, 3, file: 'patch-v1-v3.db.zst')
            : _fetch(url),
      );
      expect(result.dropped, 0);
    });

    test('a split full DB is left alone', () async {
      final releases = [
        _release('v3', {
          'seforim.db.zst.manifest.json': 900,
          ..._edge(2, 3),
          ..._edge(1, 3),
        }),
        _release('v2', _edge(1, 2)),
      ];
      final result = await prune(releases);
      expect(result.dropped, 0);
    });
  });

  group('PrunedReleasesClient', () {
    test('a failed manifest is not cached, so a retry fetches again', () async {
      final source = _FlakySource(_shortcut());
      final client = PrunedReleasesClient(
        source,
        allowPrerelease: false,
        onDrive: (_, _) => false,
      );
      const url = 'v2/patch-v1-v2.db.zst.manifest.json';
      await expectLater(client.fetchManifest(url), throwsException);
      expect((await client.fetchManifest(url)).toVersion, 2);
      await client.fetchManifest(url);
      expect(source.manifestCalls, 2);
    });

    test('without an exporter the releases pass through untouched', () async {
      final releases = _shortcut();
      final client = PrunedReleasesClient(
        _FlakySource(releases),
        allowPrerelease: false,
        onDrive: (_, _) => false,
      );
      expect(identical(await client.fetchReleases(), releases), isTrue);
    });

    test('a manifest failure leaves the releases whole', () async {
      final releases = _shortcut();
      final exporter = LibraryMirrorExporter(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      );
      addTearDown(exporter.dispose);
      final pruned = <int>[];
      final client = PrunedReleasesClient(
        _FlakySource(releases),
        allowPrerelease: false,
        onDrive: (_, _) => false,
        onPruned: pruned.add,
      )..exporter = exporter;
      expect(identical(await client.fetchReleases(), releases), isTrue);
      expect(pruned, isEmpty);
    });
  });
}

/// Fails the first fetch of every manifest.
class _FlakySource extends GithubLibraryReleaseClient {
  _FlakySource(this._releases);
  final List<LibraryRelease> _releases;
  final _failed = <String>{};
  var manifestCalls = 0;

  @override
  Future<List<LibraryRelease>> fetchReleases() async => _releases;

  @override
  Future<DeltaManifest> fetchManifest(String url) async {
    manifestCalls++;
    if (_failed.add(url)) throw Exception('transient');
    return _fetch(url);
  }
}
