import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/mirror_download_bound.dart';
import 'package:library_manager/src/services/unpicked_patches.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

// Sizes in bytes: only ratios matter, so per-MB costs are all 1 and nothing is
// fixed; a route is out of range when it is more than twice the full swap.
const _time = ApplyTimeEstimate(
  fullSecondsPerMb: 1,
  stepFixedSeconds: 0,
  stepIntermediateSeconds: 0,
  stepSecondsPerMb: 1,
  slowRouteRatio: 2,
  slowRouteMarginSeconds: 0,
  downloadSecondsPerMb: 0,
);
const _fullBytes = 10000;
const _fullName = 'seforim-schema7.db.zst';

String _manifestJson(int from, int to, int bytes) => jsonEncode({
  'fromVersion': from,
  'toVersion': to,
  'fromSchemaVersion': kSupportedDbSchemaVersion,
  'toSchemaVersion': kSupportedDbSchemaVersion,
  'patchFormatVersion': kSupportedPatchFormatVersion,
  'fromContentHash': 'h$from',
  'toContentHash': 'h$to',
  'patchFiles': [
    {
      'file': 'patch-v$from-v$to.db.zst',
      'compression': 'zstd',
      'sha256': 'unused',
      'size': bytes,
      'uncompressedSha256': 'u',
      'uncompressedSize': bytes,
    },
  ],
});

class _Published {
  final releases = <LibraryRelease>[];
  final bodies = <String, Uint8List>{};

  void release(
    String tag, {
    bool full = false,
    List<(int, int, int)> edges = const [],
  }) {
    final assets = <ReleaseAsset>[];
    void add(String name, Uint8List body) {
      final url = 'https://lib/$tag/$name';
      bodies[url] = body;
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          size: body.length,
          id: bodies.length,
        ),
      );
    }

    if (full) add(_fullName, Uint8List(_fullBytes));
    for (final (from, to, bytes) in edges) {
      add('patch-v$from-v$to.db.zst', Uint8List(bytes));
      add(
        'patch-v$from-v$to.db.zst.manifest.json',
        utf8.encode(_manifestJson(from, to, bytes)),
      );
    }
    releases.add(
      LibraryRelease(
        tag: tag,
        isPrerelease: false,
        isDraft: false,
        publishedAt: null,
        assets: assets,
      ),
    );
  }
}

class _Source extends GithubLibraryReleaseClient {
  _Source(this.published)
    : super(httpClient: MockClient((_) async => http.Response('', 500)));
  final _Published published;

  @override
  Future<List<LibraryRelease>> fetchReleases() async => published.releases;

  @override
  Future<DeltaManifest> fetchManifest(String url) async =>
      DeltaManifest.fromJson(
        jsonDecode(utf8.decode(published.bodies[url]!)) as Map<String, dynamic>,
      );
}

class _FailOneSource extends _Source {
  _FailOneSource(super.published);
  bool failed = false;
  @override
  Future<DeltaManifest> fetchManifest(String url) async {
    if (url.contains('patch-v0-v3') && !failed) {
      failed = true;
      throw const FormatException('transient unreadable manifest');
    }
    return super.fetchManifest(url);
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pruned_export'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<({List<String> stages, List<LibraryUpdatePlan> plans})> export(
    _Published published, {
    required int latest,
  }) async {
    final stages = <String>[];
    final client = PrunedReleasesClient(
      _Source(published),
      allowPrerelease: false,
      onDrive: (_, _) => false,
      onPruned: (n) => stages.add('pruned $n'),
    );
    final exporter = LibraryMirrorExporter(
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      client: client,
      applyTime: _time,
      httpClient: MockClient.streaming((request, _) async {
        final body = published.bodies[request.url.toString()];
        if (body == null) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          Stream.value(body),
          200,
          contentLength: body.length,
        );
      }),
    );
    client.exporter = exporter;
    try {
      await exporter.export(destDir: tmp.path);
    } finally {
      exporter.dispose();
    }
    final d = await OfflineLibraryUpdateDiscovery(
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      client: LocalMirrorLibraryReleaseClient(mirrorDir: tmp.path),
    ).discover(allowPrerelease: false);
    final plans = [
      for (var v = 0; v < latest; v++)
        const OfflineLibraryUpdatePlanner(applyTime: _time).plan(
          localVersion: v,
          hasLocalVersionMeta: v > 0,
          latestVersion: d.latestVersion,
          edges: d.edges,
          latestFullDbAsset: d.latestFullDbAsset,
          fullDbReleaseTag: d.fullDbReleaseTag,
          latestFullDbVersion: d.latestFullDbVersion,
        ),
    ];
    return (stages: stages, plans: plans);
  }

  bool onDisk(String tag, String name) =>
      File('${tmp.path}/assets/$tag/$name').existsSync();

  for (final missingManifest in [false, true]) {
    test(
      'bound covers a pruning failure (missing manifest: $missingManifest)',
      () async {
        final published = _Published()
          ..release(
            'v3',
            full: true,
            edges: [(2, 3, 1000), (1, 3, 1000), (0, 3, 30000)],
          )
          ..release('v2', full: true, edges: [(1, 2, 1000)]);
        final source = _FailOneSource(published);
        for (final release in published.releases) {
          for (final asset in release.deltaManifestAssets) {
            if (missingManifest && asset.name.startsWith('patch-v0-v3')) {
              continue;
            }
            final f = File('${tmp.path}/assets/${release.tag}/${asset.name}');
            f.parent.createSync(recursive: true);
            f.writeAsBytesSync(published.bodies[asset.downloadUrl]!);
            File('${f.path}.resume').writeAsStringSync('${asset.id}');
          }
        }
        File heldAsset(LibraryRelease r, ReleaseAsset a) =>
            File('${tmp.path}/assets/${r.tag}/${a.name}');
        final bound = mirrorDownloadBytesBound(
          relevant: published.releases,
          supportedDbSchemaVersion: kSupportedDbSchemaVersion,
          applyTime: _time,
          complete: (r, a) =>
              heldAsset(r, a).existsSync() &&
              heldAsset(r, a).lengthSync() == a.size,
          heldManifest: (r, a) => !heldAsset(r, a).existsSync()
              ? null
              : DeltaManifest.fromJson(
                  jsonDecode(heldAsset(r, a).readAsStringSync())
                      as Map<String, dynamic>,
                ),
        );
        final client = PrunedReleasesClient(
          source,
          allowPrerelease: false,
          onDrive: (_, _) => false,
        );
        var downloaded = 0;
        final exporter = LibraryMirrorExporter(
          supportedDbSchemaVersion: kSupportedDbSchemaVersion,
          client: client,
          applyTime: _time,
          httpClient: MockClient.streaming((request, _) async {
            final body = published.bodies[request.url.toString()]!;
            downloaded += body.length;
            return http.StreamedResponse(
              Stream.value(body),
              200,
              contentLength: body.length,
            );
          }),
        );
        client.exporter = exporter;
        try {
          await exporter.export(destDir: tmp.path);
        } finally {
          exporter.dispose();
        }
        expect(source.failed, isTrue);
        expect(downloaded, 13000);
        expect(
          bound,
          greaterThanOrEqualTo(downloaded),
          reason: 'bound=$bound actual=$downloaded',
        );
      },
    );
  }

  test('an edge shadowed by a shorter route is not downloaded', () async {
    final published = _Published()
      ..release('v3', full: true, edges: [(2, 3, 100), (1, 3, 100)])
      ..release('v2', full: true, edges: [(1, 2, 100)]);
    final result = await export(published, latest: 3);

    expect(result.stages, ['pruned 2']);
    expect(onDisk('v2', 'patch-v1-v2.db.zst'), isFalse);
    expect(onDisk('v3', 'patch-v1-v3.db.zst'), isTrue);
    expect(onDisk('v3', 'patch-v2-v3.db.zst'), isTrue);
    expect(result.plans[1].deltaSteps.map((e) => e.toVersion), [3]);
    expect(result.plans[2].deltaSteps.map((e) => e.fromVersion), [2]);
  });

  test(
    'a chain the exporter keeps after dropping a slow shortcut stays',
    () async {
      // 34→37 alone is out of range, so the exporter drops it; 34→35→37 is what
      // a v34 machine then takes, and neither of its edges may be pruned.
      final published = _Published()
        ..release('v37', full: true, edges: [(34, 37, 30000), (35, 37, 1000)])
        ..release('v35', full: true, edges: [(34, 35, 1000)]);
      final result = await export(published, latest: 37);

      expect(result.stages, isEmpty);
      expect(onDisk('v35', 'patch-v34-v35.db.zst'), isTrue);
      expect(onDisk('v37', 'patch-v35-v37.db.zst'), isTrue);
      expect(onDisk('v37', 'patch-v34-v37.db.zst'), isFalse);
      expect(result.plans[34].kind, LibraryUpdatePlanKind.delta);
      expect(
        result.plans[34].deltaSteps.map(
          (e) => '${e.fromVersion}-${e.toVersion}',
        ),
        ['34-35', '35-37'],
      );
    },
  );

  test('pruning that would empty a release is undone', () async {
    // Without its only patch v2 has no content, and the exporter's release
    // selection would change; so nothing is pruned.
    final published = _Published()
      ..release('v3', full: true, edges: [(2, 3, 100), (1, 3, 100)])
      ..release('v2', edges: [(1, 2, 100)]);
    final result = await export(published, latest: 3);

    expect(result.stages, isEmpty);
    expect(onDisk('v2', 'patch-v1-v2.db.zst'), isTrue);
  });
}
