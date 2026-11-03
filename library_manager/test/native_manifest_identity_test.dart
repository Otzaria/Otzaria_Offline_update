import 'dart:convert';
import 'dart:io';

import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;
import 'package:test/test.dart';

import 'support/native_engine.dart';

/// The published QA491 manifest carries `query_max_tokens`; an engine that does
/// not know the field recomputes another identity digest and rejects it. A
/// manifest without the field (v34) must keep its digest and be accepted.
void main() {
  final library = hookEngineLibrary();

  late Directory temp;
  late SearchEngine engine;

  setUpAll(() async {
    if (library == null) return;
    await RustLib.init(externalLibrary: ExternalLibrary.open(library));
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('native-manifest-identity-');
    final index = await Directory(p.join(temp.path, 'index')).create();
    engine = await SearchEngine.newInstance(path: index.path);
  });

  tearDown(() async {
    engine.dispose();
    await temp.delete(recursive: true);
  });

  // A 16-byte segment is deliberately invalid: the install must get past the
  // identity check and fail on the segment, not on the manifest.
  Future<SemanticError> refusal(String manifestPath) async {
    final text = File(manifestPath).readAsStringSync();
    final manifest = jsonDecode(text) as Map<String, dynamic>;
    final bytes = utf8.encode(text);
    final segment = File(p.join(temp.path, 'segment.oxv'))
      ..writeAsBytesSync(List.filled(16, 7));
    final cancellation = SemanticCancellationToken();
    try {
      await engine.installSemanticVectors(
        input: SemanticVectorsInstallInput(
          vectorsDir: p.join(temp.path, 'vectors'),
          segmentPath: segment.path,
          manifestJson: text,
          publishedManifestSha256: Sha256Stream.ofBytes(bytes),
          modelIdentityJson: jsonEncode((manifest['identity'] as Map)['model']),
        ),
        cancellation: cancellation,
      );
    } on SemanticError catch (error) {
      return error;
    } finally {
      cancellation.dispose();
    }
    fail('the invalid segment was accepted');
  }

  for (final manifest in [
    'test/fixtures/qa491.manifest.json',
    'test/support/v34_legacy_manifest.json',
  ]) {
    test('$manifest passes the identity digest check', () async {
      final error = await refusal(manifest);
      expect(error.kind, SemanticErrorKind.artifactCorrupt);
      expect(error.message, contains('the segment is 16 bytes'));
      expect(
        error.message,
        isNot(contains('identity digest')),
        reason: '$error',
      );
    }, skip: nativeSkipReason());
  }
}
