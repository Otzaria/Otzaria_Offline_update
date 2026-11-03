import 'dart:io';

import 'package:download_bench/scratch.dart';
import 'package:test/test.dart';

String _names(Directory d) {
  final n = [
    for (final e in d.listSync())
      e.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();
  return n.join(',');
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dbench_scratch_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('foreign directory is refused; cleanup keeps locks and outputs', () {
    final dir = Directory('${tmp.path}/out')..createSync();
    File('${dir.path}/other-user-file.txt').writeAsStringSync('mine');
    File('${dir.path}/old.bin.lock').writeAsStringSync('');
    File('${dir.path}/old.bin.resume').writeAsStringSync('x');
    expect(() => OwnedDir.open(dir.path), throwsA(isA<BenchFailure>()));
    expect(File('${dir.path}/other-user-file.txt').existsSync(), isTrue);
    expect(File('${dir.path}/old.bin.lock').existsSync(), isTrue);
    expect(File('${dir.path}/old.bin.resume').existsSync(), isTrue);

    final fresh = OwnedDir.open('${tmp.path}/fresh');
    File(fresh.file('asset.bin')).writeAsStringSync('a');
    File('${fresh.path}/asset.bin.lock').writeAsStringSync('');
    File('${fresh.path}/asset.bin.resume').writeAsStringSync('r');
    File(fresh.file('asset.bin.part')).writeAsStringSync('p');
    fresh.cleanup(keep: {'asset.bin'});
    expect(
      _names(Directory(fresh.path)),
      '.download_bench_owned,asset.bin,asset.bin.lock',
    );
  });

  test('files that existed before the run survive cleanup and discard', () {
    final first = OwnedDir.open('${tmp.path}/again');
    File(first.file('user-added.txt')).writeAsStringSync('keep');
    File('${first.path}/stale.lock').writeAsStringSync('');
    final second = OwnedDir.open(first.path);
    File(second.file('new.part')).writeAsStringSync('x');
    File(second.file('out.bin')).writeAsStringSync('bad');
    expect(second.discard(outputs: {'out.bin'}), isEmpty);
    expect(
      _names(Directory(second.path)),
      '.download_bench_owned,stale.lock,user-added.txt',
    );
    second.cleanup(keep: {});
    expect(File(second.file('user-added.txt')).existsSync(), isTrue);
  });

  test(
    'a case-only rename does not make a previous file owned by this run',
    () {
      final own = OwnedDir.open('${tmp.path}/case');
      File(own.file('user-added.txt')).writeAsStringSync('keep');
      final next = OwnedDir.open(own.path);
      File(own.file('user-added.txt')).renameSync(own.file('USER-ADDED.TXT'));
      next.cleanup(keep: {});
      expect(File(own.file('USER-ADDED.TXT')).readAsStringSync(), 'keep');
    },
    skip: Platform.isWindows ? false : 'Windows names are case-insensitive',
  );

  test('canonical path refusals', () {
    expect(() => canonicalScratchPath(''), throwsA(isA<BenchFailure>()));
    expect(
      () => canonicalScratchPath('${tmp.path}/a/../b'),
      throwsA(isA<BenchFailure>()),
    );
    final cwd = Directory.current.absolute.path;
    final root = Directory(cwd).parent.path == cwd
        ? cwd
        : cwd.substring(0, cwd.indexOf(Platform.pathSeparator) + 1);
    expect(() => canonicalScratchPath(root), throwsA(isA<BenchFailure>()));
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!;
    expect(() => canonicalScratchPath(home), throwsA(isA<BenchFailure>()));
    expect(
      () => canonicalScratchPath(Directory(home).parent.path),
      throwsA(isA<BenchFailure>()),
    );
    expect(
      canonicalScratchPath('${tmp.path}/new/dir'),
      endsWith('new${Platform.pathSeparator}dir'),
    );
  });

  test('a link in the path is refused', () {
    final target = Directory('${tmp.path}/real')..createSync();
    final link = '${tmp.path}/lnk';
    var made = true;
    try {
      Link(link).createSync(target.path);
    } on FileSystemException {
      made = false;
      if (Platform.isWindows) {
        final r = Process.runSync('cmd', [
          '/c',
          'mklink',
          '/J',
          link.replaceAll('/', '\\'),
          target.path.replaceAll('/', '\\'),
        ]);
        made = r.exitCode == 0;
      }
    }
    if (!made) {
      markTestSkipped('cannot create a link here');
      return;
    }
    expect(
      () => canonicalScratchPath('$link/sub'),
      throwsA(isA<BenchFailure>()),
    );
  });

  test('removeTree needs the marker', () {
    final plain = Directory('${tmp.path}/plain')..createSync();
    File('${plain.path}/x').writeAsStringSync('x');
    expect(() => OwnedDir.removeTree(plain.path), throwsA(isA<BenchFailure>()));
    expect(File('${plain.path}/x').existsSync(), isTrue);
    final own = OwnedDir.open('${tmp.path}/own');
    OwnedDir.removeTree(own.path);
    expect(Directory(own.path).existsSync(), isFalse);
  });
}
