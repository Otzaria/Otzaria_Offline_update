import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

class _Recording extends PatchDownloader {
  _Recording(this.owner, int? maxConnections)
    : super(decompress: (_) async => null, maxConnections: maxConnections ?? 2);

  final _Assets owner;
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Future<void> downloadToFile({
    required String url,
    required String destPath,
    int? expectedSize,
    String? expectedSha256,
    String? resumeToken,
    void Function(int downloaded, int? total)? onProgress,
    void Function(int verified, int total)? onVerifyProgress,
    void Function(int done, int total)? onAssembleProgress,
    void Function(int bytes)? onExistingBytes,
    bool Function()? isCancelled,
    int? connections,
  }) async {
    owner.byDest[destPath] = maxConnections;
    final size = expectedSize!;
    await File(destPath).parent.create(recursive: true);
    await File(destPath).writeAsBytes(List<int>.filled(size, 7));
    onProgress?.call(size, size);
  }
}

class _Assets extends SemanticSearchAssets {
  _Assets({
    required super.httpClient,
    required super.removableProbe,
    required super.writeProbe,
  }) : super(
         models: fakeModels,
         scheduler: DownloadScheduler(maxConcurrent: 4),
         freeBytesFor: (_) => null,
       );

  final connections = <int?>[];
  final created = <_Recording>[];
  final byDest = <String, int>{};

  @override
  PatchDownloader newDownloader({int? maxConnections}) {
    connections.add(maxConnections);
    final downloader = _Recording(this, maxConnections);
    created.add(downloader);
    return downloader;
  }
}

void main() {
  const version = 30;
  late Directory temp;
  late FakeVectorsGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-conn-test-');
    github = FakeVectorsGithub()..legacyBase(version);
  });

  tearDown(() async {
    github.client.close();
    await temp.delete(recursive: true);
  });

  Future<_Assets> sync({
    required bool removable,
    required double? speed,
    String mirrorName = 'mirror',
    List<String>? probed,
  }) async {
    final assets = _Assets(
      httpClient: github.client,
      removableProbe: (_) => removable,
      writeProbe: (dir) async {
        probed?.add(dir);
        return speed;
      },
    );
    try {
      await assets.sync(
        mirrorDir: p.join(temp.path, mirrorName),
        libraryTag: libraryTagOf(version),
        libraryTagFor: libraryTagOf,
      );
    } finally {
      assets.dispose();
    }
    return assets;
  }

  Future<(List<int?>, List<String>)> run({
    required bool removable,
    required double? speed,
  }) async {
    final probed = <String>[];
    final assets = await sync(
      removable: removable,
      speed: speed,
      probed: probed,
    );
    return (assets.connections, probed);
  }

  test('removable and slow: one connection, measured on the mirror', () async {
    final (connections, probed) = await run(removable: true, speed: 3e6);
    expect(connections, isNotEmpty);
    expect(connections, everyElement(1));
    expect(probed, [p.join(temp.path, 'mirror')]);
  });

  test('removable and fast: the shared split', () async {
    final (connections, _) = await run(removable: true, speed: 50e6);
    expect(connections, everyElement(2));
  });

  test('removable and unmeasurable: one connection', () async {
    final (connections, _) = await run(removable: true, speed: null);
    expect(connections, everyElement(1));
  });

  test('a fixed drive is not measured', () async {
    final (connections, probed) = await run(removable: false, speed: 1e6);
    expect(connections, everyElement(2));
    expect(probed, isEmpty);
  });

  group('per asset', () {
    void writeState(String dest, String token) {
      File('$dest.segments').parent.createSync(recursive: true);
      File('$dest.segments').writeAsStringSync(
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

    // Destinations learned from a first run, re-rooted under a fresh mirror.
    Future<Map<String, String>> destsUnder(String mirrorName) async {
      final first = await sync(removable: false, speed: null);
      final root = p.join(temp.path, 'mirror');
      expect(first.byDest.length, greaterThanOrEqualTo(2));
      return {
        for (final dest in first.byDest.keys)
          p.basename(dest): p.join(
            temp.path,
            mirrorName,
            p.relative(dest, from: root),
          ),
      };
    }

    test('a live state of asset A does not spare asset B', () async {
      final dests = await destsUnder('second');
      final live = dests['model.json']!;
      final token = fakeModels.firstWhere((a) => a.name == 'model.json').sha256;
      writeState(live, token);

      final assets = await sync(
        removable: true,
        speed: 3e6,
        mirrorName: 'second',
      );
      expect(assets.byDest[live], 2, reason: 'live state keeps its split');
      for (final entry in dests.entries.where((e) => e.key != 'model.json')) {
        expect(assets.byDest[entry.value], 1, reason: entry.key);
      }
    });

    test('an orphan state does not change the choice', () async {
      final dests = await destsUnder('second');
      for (final dest in dests.values) {
        writeState(dest, 'another-token');
      }
      final assets = await sync(
        removable: true,
        speed: 3e6,
        mirrorName: 'second',
      );
      expect(assets.byDest.values, everyElement(1));
    });

    test('every downloader is disposed', () async {
      final assets = await sync(removable: true, speed: 3e6);
      expect(assets.created.length, greaterThanOrEqualTo(2));
      expect(assets.created.every((d) => d.disposed), isTrue);
    });

    test('cancelling while deciding downloads nothing and disposes', () async {
      var cancelled = false;
      final assets = _Assets(
        httpClient: github.client,
        removableProbe: (_) => true,
        writeProbe: (_) async {
          cancelled = true;
          return 3e6;
        },
      );
      addTearDown(assets.dispose);
      await expectLater(
        assets.sync(
          mirrorDir: p.join(temp.path, 'mirror'),
          libraryTag: libraryTagOf(version),
          libraryTagFor: libraryTagOf,
          isCancelled: () => cancelled,
        ),
        throwsA(anything),
      );
      expect(assets.byDest, isEmpty);
      expect(assets.created.every((d) => d.disposed), isTrue);
    });
  });
}
