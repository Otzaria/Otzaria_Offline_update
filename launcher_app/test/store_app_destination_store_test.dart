import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/store_app_destination_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('store-dest-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('אין רישום → null; רישום נשמר ונקרא', () async {
    final store = StoreAppDestinationStore(dir.path, hostName: 'a');
    expect(await store.load(), isNull);
    await store.record(dir: r'D:\store', tag: 'v12');
    expect(await store.load(), (dir: r'D:\store', tag: 'v12'));
  });

  test('כל מחשב מקבל רישום משלו', () async {
    await StoreAppDestinationStore(dir.path, hostName: 'a')
        .record(dir: 'x', tag: 'v1');
    expect(
      await StoreAppDestinationStore(dir.path, hostName: 'b').load(),
      isNull,
    );
  });

  test('concurrent destination updates preserve every host', () async {
    final target = File(p.join(dir.path, 'store_app_destination.json'));
    await target.writeAsString(
      '{"hosts":{"existing":{"dir":"old","tag":"v0"}}}',
    );
    final parent = Zone.current;
    var reads = 0;
    await IOOverrides.runZoned(
      () async {
        final a = StoreAppDestinationStore(dir.path, hostName: 'a');
        final b = StoreAppDestinationStore(dir.path, hostName: 'b');
        await Future.wait([
          a.record(dir: 'one', tag: 'v1'),
          b.record(dir: 'two', tag: 'v2'),
        ]);
      },
      createFile: (path) {
        final file = parent.run(() => File(path));
        return p.equals(path, target.path)
            ? _SnapshotReadFile(file, () => reads++)
            : file;
      },
    );
    expect(reads, 2);
    expect(jsonDecode(await target.readAsString()), {
      'hosts': {
        'existing': {'dir': 'old', 'tag': 'v0'},
        'a': {'dir': 'one', 'tag': 'v1'},
        'b': {'dir': 'two', 'tag': 'v2'},
      },
    });
  });

  test('destination follows a state path through a symlink and parent',
      () async {
    final nested = await Directory(p.join(dir.path, 'target', 'nested'))
        .create(recursive: true);
    final link = await Link(p.join(dir.path, 'alias')).create(nested.path);
    final actual = p.join(nested.parent.path, 'logs');
    final lexical = p.join(dir.path, 'logs');
    final correct = StoreAppDestinationStore(actual, hostName: 'a');
    final other = StoreAppDestinationStore(lexical, hostName: 'a');
    await correct.record(dir: 'correct', tag: 'v1');
    await other.record(dir: 'other', tag: 'v0');

    final alias = StoreAppDestinationStore(
      p.join(link.path, '..', 'logs'),
      hostName: 'a',
    );
    expect(await alias.load(), (dir: 'correct', tag: 'v1'));
    await alias.record(dir: 'new', tag: 'v2');
    expect(await correct.load(), (dir: 'new', tag: 'v2'));
    expect(await other.load(), (dir: 'other', tag: 'v0'));
  }, skip: Platform.isWindows);

  test('רישום שני דורס את הראשון, וערך מסוג שגוי נקרא כריק', () async {
    final store = StoreAppDestinationStore(dir.path, hostName: 'a');
    await store.record(dir: 'x', tag: 'v1');
    await store.record(dir: 'y', tag: 'v2');
    expect(await store.load(), (dir: 'y', tag: 'v2'));
    File(p.join(dir.path, 'store_app_destination.json'))
        .writeAsStringSync('{"hosts":{"a":{"dir":1}}}');
    expect(await store.load(), isNull);
  });

  test('קובץ פגום נקרא כ"אין רישום"', () async {
    File(p.join(dir.path, 'store_app_destination.json'))
        .writeAsStringSync('{broken');
    expect(
      await StoreAppDestinationStore(dir.path, hostName: 'a').load(),
      isNull,
    );
  });
}

class _SnapshotReadFile implements File {
  _SnapshotReadFile(this.delegate, this.onRead);

  final File delegate;
  final void Function() onRead;

  @override
  String get path => delegate.path;

  @override
  File get absolute => delegate.absolute;

  @override
  Directory get parent => delegate.parent;

  @override
  Future<bool> exists() => Future.value(delegate.existsSync());

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    onRead();
    // שתי קריאות שאינן בתור יקבלו אותה תמונת מצב לפני שכתיבה כלשהי מתחילה.
    final snapshot = delegate.readAsStringSync(encoding: encoding);
    return Future(() => snapshot);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
