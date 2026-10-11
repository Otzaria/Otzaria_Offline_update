import 'dart:io';

import 'package:otzaria_downloads/atomic_write_testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_downloads/src/atomic_file.dart' show uniqueTempPath;
import 'package:otzaria_downloads/src/atomic_file.dart' as atomic;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String target;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('atomic-write-test-');
    target = '${temp.path}/state.json';
  });
  tearDown(() => temp.delete(recursive: true));

  List<String> names() => temp
      .listSync()
      .map((e) => e.path.substring(temp.path.length + 1))
      .toList();

  void overrideTempPath(String Function(String path) tempPath) {
    final original = atomicTempPathFor;
    atomicTempPathFor = tempPath;
    addTearDown(() => atomicTempPathFor = original);
  }

  test('replaces the existing file and leaves no temporary file', () async {
    await File(target).writeAsString('old');

    await writeStringAtomically(target, 'new');

    expect(File(target).readAsStringSync(), 'new');
    expect(names(), ['state.json']);
  });

  test('concurrent writes to one path do not collide', () async {
    await Future.wait([
      for (var i = 0; i < 30; i++) writeStringAtomically(target, '$i'),
    ]);

    expect(File(target).readAsStringSync(), '29');
    expect(names(), ['state.json']);
  });

  test('concurrent writes to one path run one after another', () async {
    overrideTempPath((path) => '$path.tmp');

    await Future.wait([
      for (var i = 0; i < 20; i++) writeStringAtomically(target, 'v$i'),
    ]);

    expect(File(target).readAsStringSync(), 'v19');
    expect(names(), ['state.json']);
  });

  test('a failed write does not block the next one queued on the path',
      () async {
    var calls = 0;
    overrideTempPath(
      (path) => calls++ == 0
          ? '${temp.path}/missing/state.json.tmp'
          : uniqueTempPath(path),
    );

    final first = writeStringAtomically(target, 'first');
    final second = writeStringAtomically(target, 'second');

    await expectLater(first, throwsA(isA<FileSystemException>()));
    await second;
    expect(File(target).readAsStringSync(), 'second');
    expect(names(), ['state.json']);
  });

  test('every write gets its own temporary file name', () {
    final names = {for (var i = 0; i < 100; i++) uniqueTempPath(target)};

    expect(names, hasLength(100));
    for (final name in names) {
      expect(name, startsWith('$target.'));
      expect(name, endsWith('.tmp'));
      expect(
        isAtomicTempNameOf(name.substring(temp.path.length + 1), 'state.json'),
        isTrue,
      );
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

  test('a failure leaves another writer\'s temporary file alone', () async {
    final foreign = File('$target.tmp')..writeAsStringSync('other');
    await Directory(target).create();

    await expectLater(
      writeStringAtomically(target, 'new'),
      throwsA(isA<FileSystemException>()),
    );

    expect(foreign.readAsStringSync(), 'other');
    expect(names().toSet(), {'state.json', 'state.json.tmp'});
    expect(Directory(target).existsSync(), isTrue);
  });

  test('recognises temporary names of the target only', () {
    expect(isAtomicTempNameOf('installer.json.tmp', 'installer.json'), isTrue);
    expect(
      isAtomicTempNameOf('Installer.JSON.1-2-3.TMP', 'installer.json'),
      isTrue,
    );
    expect(isAtomicTempNameOf('installer.json', 'installer.json'), isFalse);
    expect(
      isAtomicTempNameOf('installer.jsonx.tmp', 'installer.json'),
      isFalse,
    );
    expect(isAtomicTempNameOf('setup.exe.tmp', 'installer.json'), isFalse);
  });

  group('renameRetryingTransient', () {
    FileSystemException failure(int code) =>
        FileSystemException('rename', target, OSError('busy', code));

    for (final code in [5, 32, 33]) {
      test('retries Windows error $code until the rename succeeds', () async {
        var attempts = 0;

        await atomic.renameRetryingTransient(
          () async {
            if (++attempts < 3) throw failure(code);
          },
          isWindows: true,
        );

        expect(attempts, 3);
      });
    }

    test('gives up after five transient failures', () async {
      var attempts = 0;

      await expectLater(
        atomic.renameRetryingTransient(
          () async {
            attempts++;
            throw failure(32);
          },
          isWindows: true,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(attempts, 5);
    });

    test('does not retry an error that is not transient', () async {
      var attempts = 0;

      await expectLater(
        atomic.renameRetryingTransient(
          () async {
            attempts++;
            throw failure(2);
          },
          isWindows: true,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(attempts, 1);
    });

    test('does not retry outside Windows', () async {
      var attempts = 0;

      await expectLater(
        atomic.renameRetryingTransient(
          () async {
            attempts++;
            throw failure(32);
          },
          isWindows: false,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(attempts, 1);
    });
  });
}
