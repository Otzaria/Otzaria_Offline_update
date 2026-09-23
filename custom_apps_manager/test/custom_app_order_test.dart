import 'dart:convert';
import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

CustomAppEntry entry(String id, String name) =>
    CustomAppEntry(descriptor: descriptor(id: id, name: name));

void main() {
  late String root;
  late CustomAppOrderStore store;

  setUp(() {
    root = tempMirrorRoot();
    store = CustomAppOrderStore(mirrorRootDir: root);
  });

  group('הקובץ', () {
    test('בלי קובץ — רשימה ריקה, כלומר מיון לפי שם', () async {
      expect(await store.load(), isEmpty);
    });

    test('שמירה וטעינה שומרות על הסדר', () async {
      await store.save(const ['b', 'a', 'c']);
      expect(await store.load(), ['b', 'a', 'c']);
    });

    test('קובץ פגום נקרא כריק ואינו מפיל את הטעינה', () async {
      File(store.filePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{ זה לא JSON');

      expect(await store.load(), isEmpty);
    });

    test('schema חדש יותר נקרא כריק ולא מנוחש', () async {
      File(store.filePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'schemaVersion': CustomAppOrderStore.currentSchemaVersion + 1,
          'order': ['a'],
        }));

      expect(await store.load(), isEmpty);
    });

    test('יושב ליד תיקיות התוכנות, ולכן נוסע על הכונן', () {
      expect(store.filePath, endsWith('order.json'));
      expect(File(store.filePath).parent.path, endsWith('apps'));
    });
  });

  group('המיון', () {
    final apps = [
      entry('gimel', 'ג'),
      entry('alef', 'א'),
      entry('bet', 'ב'),
    ];

    test('בלי סדר שמור — הרשימה נשארת כפי שהגיעה', () {
      expect(
        CustomAppOrderStore.sort(apps, const []).map((e) => e.descriptor.id),
        ['gimel', 'alef', 'bet'],
      );
    });

    test('הסדר השמור קובע', () {
      expect(
        CustomAppOrderStore.sort(apps, const ['bet', 'gimel', 'alef'])
            .map((e) => e.descriptor.id),
        ['bet', 'gimel', 'alef'],
      );
    });

    test('תוכנה שאינה ברשימה נופלת לסוף, ממוינת לפי שם', () {
      // כך מצטרפת תיקיית תוכנה שהועתקה מכונן אחר: בסוף, בלי לדרוס דבר.
      expect(
        CustomAppOrderStore.sort(apps, const ['bet'])
            .map((e) => e.descriptor.id),
        ['bet', 'alef', 'gimel'],
      );
    });

    test('מזהה של תוכנה שהוסרה מדולג', () {
      expect(
        CustomAppOrderStore.sort(apps, const ['nope', 'bet', 'alef', 'gimel'])
            .map((e) => e.descriptor.id),
        ['bet', 'alef', 'gimel'],
      );
    });
  });

  group('דרך המנהל', () {
    test('loadAll מחזיר לפי הסדר שנשמר', () async {
      final manager = CustomAppsManager(
        resolveMirrorDir: () async => root,
        readVersion: (_) => null,
      );
      await manager.add(descriptor(id: 'alef', name: 'א'));
      await manager.add(descriptor(id: 'bet', name: 'ב'));

      expect(
        (await manager.loadAll()).map((e) => e.descriptor.id),
        ['alef', 'bet'],
      );

      await manager.saveOrder(const ['bet', 'alef']);
      expect(
        (await manager.loadAll()).map((e) => e.descriptor.id),
        ['bet', 'alef'],
      );
    });
  });
}
