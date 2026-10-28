import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:library_manager/src/services/storage_guard.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;
import 'package:test/test.dart';

import 'support/native_engine.dart';

/// Installs a real vector set (built by the engine's own artifact builder, 11KB,
/// text 4) through the bundled binary: what it accepts is proven by running it.
void main() {
  final library = hookEngineLibrary();
  const fixture = 'test/support/native_vector_set';

  final skip = nativeSkipReason(needsVectorSet: true);
  late Directory temp;
  late SearchEngine engine;

  setUpAll(() async {
    if (library != null) {
      await RustLib.init(externalLibrary: ExternalLibrary.open(library));
    }
  });
  setUp(() async {
    if (skip != null) return;
    temp = await Directory.systemTemp.createTemp('native-vector-install-');
    final index = await Directory(p.join(temp.path, 'index')).create();
    engine = await SearchEngine.newInstance(path: index.path);
  });

  tearDown(() async {
    if (skip != null) return;
    engine.dispose();
    await temp.delete(recursive: true);
  });

  Map<String, dynamic> manifest() =>
      jsonDecode(File('$fixture/release.json').readAsStringSync())
          as Map<String, dynamic>;

  Future<SemanticVectorsInstallReport> install(
    Map<String, dynamic> release, {
    String? vectorsDir,
  }) {
    final bytes = utf8.encode(jsonEncode(release));
    return engine.installSemanticVectors(
      input: SemanticVectorsInstallInput(
        vectorsDir: vectorsDir ?? p.join(temp.path, 'vectors'),
        segmentPath: '$fixture/segment.oxv',
        manifestJson: utf8.decode(bytes),
        publishedManifestSha256: Sha256Stream.ofBytes(bytes),
        modelIdentityJson: File('$fixture/model.json').readAsStringSync(),
      ),
      cancellation: SemanticCancellationToken(),
    );
  }

  test(
    'a text-4 set installs and its identity is what pending() reads',
    () async {
      final release = manifest();
      final report = await install(release);

      expect(report.libraryVersion, 1);
      final vectors = p.join(temp.path, 'vectors');
      expect(
        (await engine.semanticVectorsInfo(vectorsDir: vectors)).present,
        isTrue,
      );
      final sets = await SemanticSearchAssets.readInstalledSets(vectors);
      expect(sets, hasLength(1));
      expect(sets.single.identityDigest, release['identityDigest']);
      expect(sets.single.libraryReleaseTag, release['libraryReleaseTag']);
    },
    skip: skip,
  );

  test(
    'the same set declaring text 1 is refused and nothing is installed',
    () async {
      final release = manifest();
      ((release['identity'] as Map)['text'] as Map)['line_text_version'] = 1;

      await expectLater(
        install(release),
        throwsA(
          isA<SemanticError>()
              .having(
                (e) => e.kind,
                'kind',
                SemanticErrorKind.artifactIncompatible,
              )
              .having((e) => e.field, 'field', 'text.line_text_version'),
        ),
      );
      expect(
        File(p.join(temp.path, 'vectors', 'CURRENT')).existsSync(),
        isFalse,
      );
    },
    skip: skip,
  );

  test(
    'an install the OS refuses is a visible failure, not a full drive',
    () async {
      final blocker = File(p.join(temp.path, 'file'))..writeAsStringSync('x');

      Object? failure;
      try {
        await install(manifest(), vectorsDir: p.join(blocker.path, 'vectors'));
      } on Object catch (error) {
        failure = error;
      }

      expect(failure, isA<SemanticError>());
      expect(storageFullFromEngine(failure!, temp.path), isNull);
    },
    skip: skip,
  );

  group('the engine\'s I/O failure text (no native library needed)', () {
    // The shape the binary produced for a refused install (os error 183);
    // only the code differs below.
    String real(int code) =>
        'failed to install the semantic vectors into X:/v: Semantic artifact '
        'error: Artifact IO error (creating X:/v): The OS text. '
        '(os error $code)';

    SemanticError internal(int code) =>
        SemanticError(kind: SemanticErrorKind.internal, message: real(code));

    test('access denied or an existing file stay visible failures', () {
      expect(storageFullFromEngine(internal(5), 'X:'), isNull);
      expect(storageFullFromEngine(internal(183), 'X:'), isNull);
    });

    test('the full-drive code is a StorageFullException', () {
      final code = Platform.isWindows ? 112 : 28;
      expect(storageFullFromEngine(internal(code), 'X:'), isNotNull);
    });
  });
}
