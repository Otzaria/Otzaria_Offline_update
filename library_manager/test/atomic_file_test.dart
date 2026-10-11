import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/atomic_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String target;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lm-atomic-write-test-');
    target = p.join(temp.path, 'state.json');
  });
  tearDown(() => temp.delete(recursive: true));

  List<String> names() =>
      temp.listSync().map((e) => p.basename(e.path)).toList();

  test('stays the same code as the shared writer in otzaria_downloads', () {
    String normalized(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp(r'[\s,]'), '');

    expect(
      normalized('lib/src/services/atomic_file.dart'),
      normalized('../otzaria_downloads/lib/src/atomic_file.dart'),
    );
  });

  test('replaces the existing file and leaves no temporary file', () async {
    await File(target).writeAsString('old');

    await writeStringAtomically(target, 'new');

    expect(File(target).readAsStringSync(), 'new');
    expect(names(), ['state.json']);
  });

  test('concurrent writes to one path run one after another', () async {
    final original = atomicTempPathFor;
    atomicTempPathFor = (path) => '$path.tmp';
    addTearDown(() => atomicTempPathFor = original);

    await Future.wait([
      for (var i = 0; i < 20; i++) writeStringAtomically(target, 'v$i'),
    ]);

    expect(File(target).readAsStringSync(), 'v19');
    expect(names(), ['state.json']);
  });

  test('every write gets its own temporary file name', () {
    final paths = {for (var i = 0; i < 100; i++) uniqueTempPath(target)};

    expect(paths, hasLength(100));
    for (final path in paths) {
      expect(isAtomicTempNameOf(p.basename(path), 'state.json'), isTrue);
    }
  });

  test('a failed rename removes its temporary file', () async {
    await Directory(target).create();

    await expectLater(
      writeStringAtomically(target, 'new'),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(target).existsSync(), isTrue);
    expect(names(), ['state.json']);
  });

  test('retries a transient Windows rename error', () async {
    var attempts = 0;

    await renameRetryingTransient(() async {
      if (++attempts < 3) {
        throw FileSystemException('rename', target, const OSError('busy', 32));
      }
    }, isWindows: true);

    expect(attempts, 3);
  });
}
