import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/json_state_store.dart';
import 'package:otzaria_downloads/atomic_write_testing.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('json-state-');
    file = File(p.join(directory.path, 'state.json'));
  });
  tearDown(() => deleteTempDir(directory));

  test('missing, malformed and non-object states load as empty', () async {
    final store = JsonStateStore(file.path);
    expect(await store.load(), isEmpty);
    for (final text in ['{broken', '[]', 'null', '"text"']) {
      await file.writeAsString(text);
      expect(await store.load(), isEmpty);
    }
    await store.update((json) => {'recovered': true});
    expect(await store.load(), {'recovered': true});
  });

  test('normalized aliases share a complete read-modify-write queue', () async {
    final a = JsonStateStore(file.path);
    final b = JsonStateStore(
      '${directory.path}${p.separator}.${p.separator}state.json',
    );
    await Future.wait([
      a.update((json) => {...json, 'a': 1}),
      b.update((json) => {...json, 'b': 2}),
      a.update((json) => {...json, 'c': 3}),
    ]);
    expect(await a.load(), {'a': 1, 'b': 2, 'c': 3});
  });

  test('a failed atomic write keeps state and does not poison the queue',
      () async {
    await file.writeAsString('{"kept":1}');
    final original = atomicTempPathFor;
    addTearDown(() => atomicTempPathFor = original);
    var writes = 0;
    atomicTempPathFor = (path) => writes++ == 0
        ? p.join(directory.path, 'missing', 'state.tmp')
        : original(path);
    final store = JsonStateStore(file.path);

    await store.update((json) => {...json, 'lost': true});
    expect(jsonDecode(await file.readAsString()), {'kept': 1});
    await store.update((json) => {...json, 'saved': true});
    expect(await store.load(), {'kept': 1, 'saved': true});
    expect(directory.listSync().map((entry) => entry.path), [file.path]);
  });

  test('an unchanged update does not create a file or a directory', () async {
    final nested = p.join(directory.path, 'missing', 'state.json');
    await JsonStateStore(nested).update((json) => null);
    expect(directory.listSync(), isEmpty);
  });

  test('each operation reads disk instead of caching the previous document',
      () async {
    final store = JsonStateStore(file.path);
    await store.update((json) => {'first': true});
    await file.writeAsString('{"external":true}');
    expect(await store.load(), {'external': true});
    await store.update((json) => {...json, 'next': true});
    expect(await store.load(), {'external': true, 'next': true});
  });

  test('hostname fallbacks preserve existing keys', () {
    expect(stateHostName('pc-a'), 'pc-a');
    expect(stateHostName(''), 'unknown');
    final host = Platform.localHostname;
    expect(stateHostName(null), host.isEmpty ? 'unknown' : host);
  });
}
