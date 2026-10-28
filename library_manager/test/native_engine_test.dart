import 'dart:io';

import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/native_engine.dart';

void main() {
  final library = hookEngineLibrary();

  test('the pinned engine loads and reads an empty vector set', () async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(library!));
    final temp = await Directory.systemTemp.createTemp('native-engine-');
    addTearDown(() => temp.delete(recursive: true));
    final index = await Directory(p.join(temp.path, 'index')).create();
    final engine = await SearchEngine.newInstance(path: index.path);
    addTearDown(engine.dispose);

    final info = await engine.semanticVectorsInfo(
      vectorsDir: p.join(temp.path, 'vectors'),
    );

    expect(info.present, isFalse);
  }, skip: nativeSkipReason());
}
