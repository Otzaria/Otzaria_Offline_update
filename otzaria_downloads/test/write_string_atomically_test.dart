import 'dart:io';

import 'package:otzaria_downloads/otzaria_downloads.dart';
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

    expect(int.parse(File(target).readAsStringSync()), inInclusiveRange(0, 29));
    expect(names(), ['state.json']);
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
}
