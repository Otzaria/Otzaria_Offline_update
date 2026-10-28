import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;
import 'package:test/test.dart';

import 'support/native_engine.dart';

/// the real v34 manifest (text 4) gets past the identity check and the same
/// manifest declaring text 1 is `artifactIncompatible` on `text.line_text_version`.
void main() {
  final library = hookEngineLibrary();

  late Directory temp;
  late SearchEngine engine;

  setUp(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(library!));
    temp = await Directory.systemTemp.createTemp('native-install-');
    final index = await Directory(p.join(temp.path, 'index')).create();
    engine = await SearchEngine.newInstance(path: index.path);
  });

  tearDown(() async {
    engine.dispose();
    await temp.delete(recursive: true);
  });

  Future<SemanticError> refusal(int lineTextVersion) async {
    final manifest =
        jsonDecode(
              File('test/support/v34_legacy_manifest.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    ((manifest['identity'] as Map)['text'] as Map)['line_text_version'] =
        lineTextVersion;
    final bytes = utf8.encode(jsonEncode(manifest));
    final segment = File(p.join(temp.path, 'segment.oxv'))
      ..writeAsBytesSync(List.filled(16, 7));
    try {
      await engine.installSemanticVectors(
        input: SemanticVectorsInstallInput(
          vectorsDir: p.join(temp.path, 'vectors'),
          segmentPath: segment.path,
          manifestJson: utf8.decode(bytes),
          publishedManifestSha256: Sha256Stream.ofBytes(bytes),
          modelIdentityJson: jsonEncode((manifest['identity'] as Map)['model']),
        ),
        cancellation: SemanticCancellationToken(),
      );
    } on SemanticError catch (error) {
      return error;
    }
    fail('the install was not refused');
  }

  test('the engine reads the line recipe the launcher expects', () async {
    final expected = await refusal(kSemanticEngineText.lineTextVersion);
    expect(
      expected.field,
      isNot('text.line_text_version'),
      reason: '$expected',
    );

    final other = await refusal(kSemanticEngineText.lineTextVersion - 3);
    expect(other.kind, SemanticErrorKind.artifactIncompatible);
    expect(other.field, 'text.line_text_version');
  }, skip: nativeSkipReason());
}
