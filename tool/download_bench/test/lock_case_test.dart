import 'dart:io';

import 'package:download_bench/scratch.dart';
import 'package:test/test.dart';

void main() {
  test('lock files survive cleanup and discard whatever their case', () {
    final tmp = Directory.systemTemp.createTempSync('dbench_lockcase_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dir = OwnedDir.open('${tmp.path}/own');
    for (final name in ['a.bin.LOCK', 'b.bin.Lock', 'c.bin.lock', 'd.part']) {
      File('${dir.path}/$name').writeAsStringSync('x');
    }
    expect(dir.discard(), isEmpty);
    expect(File(dir.file('d.part')).existsSync(), isFalse);
    for (final name in ['a.bin.LOCK', 'b.bin.Lock', 'c.bin.lock']) {
      expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
    }
    dir.cleanup(keep: {});
    for (final name in ['a.bin.LOCK', 'b.bin.Lock', 'c.bin.lock']) {
      expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
    }
  });
}
