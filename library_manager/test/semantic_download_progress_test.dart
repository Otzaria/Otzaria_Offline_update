import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

/// Stands in for the engine's downloader and replays what it reports to its
/// callbacks, so the byte counter and the stage text are tested without a
/// network or a real model.
class _ScriptedDownloader extends PatchDownloader {
  _ScriptedDownloader(this.script) : super(decompress: (_) async => null);

  final _Script script;

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
    final size = expectedSize!;
    final file = File(destPath);
    await file.parent.create(recursive: true);
    final held = file.existsSync() ? file.lengthSync() : 0;
    script.requested.add(p.basename(destPath));
    var from = 0;
    if (held >= size) {
      onExistingBytes?.call(size);
      onProgress?.call(size, size);
      for (var done = size ~/ 4; done <= size; done += size ~/ 4) {
        onVerifyProgress?.call(done, size);
        if (done == size) break;
      }
      return;
    }
    if (held > 0) {
      onExistingBytes?.call(held);
      if (script.discardsPrefix) {
        onExistingBytes?.call(0);
      } else {
        from = held;
      }
    }
    if (script.assembles) {
      for (var done = size ~/ 2; done <= size; done += size ~/ 2) {
        onAssembleProgress?.call(done, size);
        if (done == size) break;
      }
    }
    for (var step = 1; step <= 4; step++) {
      final at = from + (size - from) * step ~/ 4;
      if (script.cancelAfterBytes case final limit? when at > limit) {
        await file.writeAsBytes(List<int>.filled(limit, 7));
        throw const PatchDownloadCancelled();
      }
      onProgress?.call(at, size);
    }
    await file.writeAsBytes(List<int>.filled(size, 7));
  }
}

class _Script {
  final requested = <String>[];
  bool discardsPrefix = false;
  bool assembles = false;
  int? cancelAfterBytes;
}

class _Assets extends SemanticSearchAssets {
  _Assets(this.script, {required super.httpClient})
    : super(
        models: fakeModels,
        scheduler: DownloadScheduler(maxConcurrent: 1),
        freeBytesFor: (_) => null,
      );

  final _Script script;

  @override
  PatchDownloader newDownloader({int? maxConnections}) =>
      _ScriptedDownloader(script);
}

void main() {
  late Directory temp;
  late String mirror;
  late FakeVectorsGithub github;
  late _Script script;
  late _Assets assets;

  const version = 30;
  final modelBytes = fakeModels.fold<int>(0, (sum, file) => sum + file.size);
  final planned = modelBytes + 500;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-progress-test-');
    mirror = p.join(temp.path, 'mirror');
    github = FakeVectorsGithub()..legacyBase(version);
    script = _Script();
    assets = _Assets(script, httpClient: github.client);
  });

  tearDown(() async {
    assets.dispose();
    github.client.close();
    await temp.delete(recursive: true);
  });

  String vectorDest([int v = version]) =>
      p.join(mirror, libraryTagOf(v), 'vectors', 'legacy-v$v.oxv.zst');

  Future<void> leave(String path, int length) async {
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsBytes(List<int>.filled(length, 7));
  }

  ({List<(int, int?)> bytes, List<String> stages}) record = (
    bytes: [],
    stages: [],
  );

  Future<void> sync({
    void Function(int, int?)? onBytes,
    bool Function()? isCancelled,
  }) async {
    record = (bytes: <(int, int?)>[], stages: <String>[]);
    try {
      await assets.sync(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(version),
        libraryTagFor: libraryTagOf,
        onStage: record.stages.add,
        onBytesProgress: (done, total) {
          record.bytes.add((done, total));
          onBytes?.call(done, total);
        },
        isCancelled: isCancelled,
      );
    } finally {
      assets.dispose();
    }
  }

  void expectHonestCounter({required int net}) {
    final events = record.bytes;
    expect(events, isNotEmpty);
    var peak = 0;
    for (final (done, total) in events) {
      expect(done, greaterThanOrEqualTo(peak), reason: 'the counter went back');
      expect(done, lessThanOrEqualTo(total ?? done));
      peak = done;
    }
    expect(events.last, (net, net));
  }

  group('the byte counter', () {
    test('a clean start counts every byte once, never backwards', () async {
      await sync();

      expect(record.bytes.first, (0, planned));
      expectHonestCounter(net: planned);
      expect(record.bytes.map((e) => e.$2).toSet(), {planned});
    });

    test(
      'a partial file from before counts only what is still to come',
      () async {
        await leave(vectorDest(), 200);

        await sync();

        expectHonestCounter(net: planned - 200);
      },
    );

    test('a prefix the downloader throws away is counted again', () async {
      await leave(vectorDest(), 200);
      script.discardsPrefix = true;

      await sync();

      expectHonestCounter(net: planned);
    });

    test('a complete file counts nothing and leaves the total', () async {
      await leave(vectorDest(), 500);

      await sync();

      expectHonestCounter(net: modelBytes);
      expect(record.bytes.first.$2, modelBytes);
    });

    test('inside an outer aggregator the drive total only grows', () async {
      final shown = <(int, int?)>[];
      final outer = ByteProgressAggregator(
        onProgress: (done, total) => shown.add((done, total)),
      );
      final export = outer.slot();
      final semantic = outer.slot();
      // The library export finished: its slot reported what it had to bring.
      export.report(4000, 4000);
      await leave(vectorDest(), 200);

      await sync(onBytes: semantic.report);

      var peak = 0;
      for (final (done, _) in shown) {
        expect(done, greaterThanOrEqualTo(peak));
        peak = done;
      }
      expect(shown.last, (4000 + planned - 200, 4000 + planned - 200));
    });
  });

  group('verifying a file already on the drive', () {
    test('is a stage with a percent, never network bytes', () async {
      await leave(vectorDest(), 500);

      await sync();

      final verifying = record.stages.where(isLocalWorkStage).toList();
      expect(verifying, isNotEmpty);
      expect(
        verifying.first,
        AppL10n.strings.libraryDomain.exportVerifying(
          libraryTagOf(version),
          'legacy-v$version.oxv.zst',
          25,
        ),
      );
      expect(verifying.last, contains('100%'));
      expectHonestCounter(net: modelBytes);
    });

    test('hands the stage back to downloading when it ends', () async {
      await leave(vectorDest(), 500);

      await sync();

      expect(
        record.stages.last,
        AppL10n.strings.libraryDomain.semanticDownloading,
      );
    });

    test(
      'joining ranges is an assembling stage, never network bytes',
      () async {
        script.assembles = true;

        await sync();

        final local = record.stages.where(isLocalWorkStage).toList();
        expect(local.where((s) => s.contains('legacy-v')), hasLength(2));
        expect(
          local.first,
          AppL10n.strings.libraryDomain.exportAssembling(
            libraryTagOf(version),
            'legacy-v$version.oxv.zst',
            50,
          ),
        );
        expect(
          record.stages.last,
          AppL10n.strings.libraryDomain.semanticDownloading,
        );
        expectHonestCounter(net: planned);
      },
    );

    test('a download that verifies nothing shows no such stage', () async {
      await sync();

      expect(record.stages.where(isLocalWorkStage), isEmpty);
    });
  });

  group('cancelling and resuming', () {
    test('a cancel keeps the partial file and writes no manifest', () async {
      script.cancelAfterBytes = 300;
      Object? error;
      try {
        await sync();
      } on PatchDownloadCancelled catch (e) {
        error = e;
      }

      expect(error, isA<PatchDownloadCancelled>());
      expect(File(vectorDest()).lengthSync(), 300);
      expect(
        File(
          p.join(mirror, SemanticSearchAssets.manifestFileName),
        ).existsSync(),
        isFalse,
      );
    });

    test('the next run resumes from the kept partial file', () async {
      script.cancelAfterBytes = 300;
      try {
        await sync();
      } on PatchDownloadCancelled {
        // The user closed the download; what arrived stays.
      }
      script.cancelAfterBytes = null;
      assets = _Assets(script, httpClient: github.client);

      await sync();

      expectHonestCounter(net: planned - 300);
      expect(File(vectorDest()).lengthSync(), 500);
      expect(
        File(
          p.join(mirror, SemanticSearchAssets.manifestFileName),
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('the same model in another generation', () {
    Future<void> plainSync(int v) async {
      final online = SemanticSearchAssets(
        httpClient: github.client,
        models: fakeModels,
        freeBytesFor: (_) => null,
      );
      try {
        await online.sync(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(v),
          libraryTagFor: libraryTagOf,
        );
      } finally {
        online.dispose();
      }
    }

    final modelNames = fakeModels.map((m) => m.name).toSet();

    test('is copied from the old generation, not downloaded again', () async {
      github.legacyBase(29);
      await plainSync(29);
      github.downloads.clear();

      await plainSync(version);

      expect(github.downloads.where(modelNames.contains), isEmpty);
      for (final model in fakeModels) {
        expect(
          File(
            p.join(
              mirror,
              libraryTagOf(version),
              SemanticSearchAssets.modelFolder,
              model.name,
            ),
          ).lengthSync(),
          model.size,
        );
      }
      final left = Directory(p.join(mirror, libraryTagOf(29)));
      expect(
        !left.existsSync() ||
            left
                .listSync(recursive: true)
                .whereType<File>()
                .every((f) => p.extension(f.path) == '.lock'),
        isTrue,
      );
    });

    test('a partial model of the old generation is never adopted', () async {
      github.legacyBase(29);
      final oldPartial = p.join(
        mirror,
        libraryTagOf(29),
        SemanticSearchAssets.modelFolder,
        'model.json',
      );
      await leave(oldPartial, 5);

      await plainSync(version);

      expect(github.downloads, contains('model.json'));
      expect(
        File(
          p.join(
            mirror,
            libraryTagOf(version),
            SemanticSearchAssets.modelFolder,
            'model.json',
          ),
        ).readAsStringSync(),
        fakeModelJson,
      );
    });

    test('a model with another content is never taken for the same', () async {
      github.legacyBase(29);
      final other = p.join(
        mirror,
        libraryTagOf(29),
        SemanticSearchAssets.modelFolder,
        'model.json',
      );
      await leave(other, fakeModels.first.size);

      await plainSync(version);

      expect(github.downloads, contains('model.json'));
      expect(
        File(
          p.join(
            mirror,
            libraryTagOf(version),
            SemanticSearchAssets.modelFolder,
            'model.json',
          ),
        ).readAsStringSync(),
        fakeModelJson,
      );
    });
  });
}
