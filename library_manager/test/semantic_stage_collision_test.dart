import 'dart:async';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

class _Overlap {
  final qa491Started = Completer<void>();
  final releaseQa491 = Completer<void>();
  void Function()? onRound2Bytes;
}

class _Downloader extends PatchDownloader {
  _Downloader(this.overlap) : super(decompress: (_) async => null);

  final _Overlap overlap;

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
    if (p.basename(destPath) == 'LICENSE') {
      onVerifyProgress?.call(size ~/ 2, size);
      if (p.basename(p.dirname(destPath)) == SemanticModelSpec.qa491.folder) {
        overlap.qa491Started.complete();
        await overlap.releaseQa491.future;
      } else {
        await overlap.qa491Started.future;
        onProgress?.call(size, size);
        overlap.onRound2Bytes?.call();
        overlap.releaseQa491.complete();
      }
    }
    onProgress?.call(size, size);
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(size, 7));
  }
}

class _Assets extends SemanticSearchAssets {
  _Assets(this.overlap, {required super.httpClient})
    : super(
        models: fakeModels,
        specs: fakeSpecs,
        scheduler: DownloadScheduler(maxConcurrent: 8),
        freeBytesFor: (_) => null,
      );

  final _Overlap overlap;

  @override
  PatchDownloader newDownloader({int? maxConnections}) => _Downloader(overlap);
}

void main() {
  test('same-named files of two generations keep independent local-work '
      'stages', () async {
    final temp = await Directory.systemTemp.createTemp('semantic-stage-names-');
    final github = FakeVectorsGithub()
      ..legacyBase(30)
      ..qa491Base(30, windows: false);
    final overlap = _Overlap();
    final assets = _Assets(overlap, httpClient: github.client);
    addTearDown(() async {
      assets.dispose();
      github.client.close();
      await temp.delete(recursive: true);
    });
    var stage = '';
    String? whileQa491Verifies;
    overlap.onRound2Bytes = () => whileQa491Verifies = stage;

    await assets.sync(
      mirrorDir: p.join(temp.path, 'mirror'),
      libraryTag: libraryTagOf(30),
      libraryTagFor: libraryTagOf,
      fleet: const SemanticFleet([], [
        SemanticModelGeneration.round2,
        SemanticModelGeneration.qa491,
      ]),
      onStage: (value) => stage = value,
    );

    expect(whileQa491Verifies, isNotNull);
    expect(whileQa491Verifies, contains('LICENSE'));
    expect(isLocalWorkStage(whileQa491Verifies!), isTrue);
    expect(stage, AppL10n.strings.libraryDomain.semanticDownloading);
  });
}
