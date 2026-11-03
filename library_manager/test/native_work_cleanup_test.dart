import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/native_engine.dart';

// A Tantivy callback retains the absolute index path after engine.dispose().
// Recreate its lock after delete has enumerated and removed the index files.
class _DeletingDirectory implements Directory {
  _DeletingDirectory(this.directory, this.callback);

  final Directory directory;
  final Future<void> Function() callback;

  @override
  String get path => directory.path;

  @override
  Future<Directory> rename(String newPath) async =>
      _DeletingDirectory(await directory.rename(newPath), callback);

  @override
  Future<Directory> delete({bool recursive = false}) async {
    final index = Directory(p.join(path, 'index'));
    for (final file in await index.list().toList()) {
      await file.delete(recursive: true);
    }
    await callback();
    await index.delete();
    await directory.delete();
    return directory;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'a late native reload cannot recreate a lock during scratch cleanup',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'semantic-cleanup-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final work = await Directory(p.join(temp.path, 'work')).create();
      final oldIndex = await Directory(p.join(work.path, 'index')).create();
      await File(p.join(oldIndex.path, 'meta.json')).writeAsString('{}');
      var lateWriteRefused = false;
      final deleting = _DeletingDirectory(work, () async {
        try {
          await File(
            p.join(oldIndex.path, '.tantivy-meta.lock'),
          ).writeAsString('');
        } on FileSystemException {
          lateWriteRefused = !await oldIndex.exists();
        }
      });

      await disposeSemanticEngineWork(null, deleting);

      expect(lateWriteRefused, isTrue);
      expect(await temp.list().toList(), isEmpty);
    },
  );

  test(
    '200 native engines leave no scratch directory after disposal',
    () async {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(hookEngineLibrary()!),
      );
      final temp = await Directory.systemTemp.createTemp(
        'native-cleanup-stress-',
      );
      addTearDown(() => temp.delete(recursive: true));
      for (var i = 0; i < 200; i++) {
        final work = await Directory(p.join(temp.path, 'work-$i')).create();
        final index = await Directory(p.join(work.path, 'index')).create();
        final engine = await SearchEngine.newInstance(path: index.path);
        engine.dispose();
        await disposeSemanticEngineWork(null, work);
      }
      expect(await temp.list().toList(), isEmpty);
    },
    skip: nativeSkipReason(),
  );
}
