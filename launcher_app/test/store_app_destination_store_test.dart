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
