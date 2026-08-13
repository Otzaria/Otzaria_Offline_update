import 'dart:convert';
import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String root;
  late CustomAppStore store;

  setUp(() {
    root = tempMirrorRoot();
    store = CustomAppStore(mirrorRootDir: root);
  });

  test('מרשם ריק אינו שגיאה — זה המצב אצל רוב המשתמשים', () async {
    expect(await store.loadAll(), isEmpty);
    expect(await store.load('אין-כזה'), isNull);
  });

  test('הוספה ושליפה', () async {
    await store.add(descriptor(name: 'תוכנה א'));

    final entry = await store.load('org.example.app');
    expect(entry, isNotNull);
    expect(entry!.descriptor.name, 'תוכנה א');
    // בלי קובץ התקנה — מצב תקין לגמרי.
    expect(entry.hasInstaller, isFalse);
  });

  test('כל תוכנה בתיקייה משלה — העתקתה לבדה מעבירה תוכנה שלמה', () async {
    await store.add(descriptor());
    expect(
      File(p.join(root, 'apps', 'org.example.app', 'descriptor.json'))
          .existsSync(),
      isTrue,
    );
  });

  test('הוספה כפולה נדחית ואינה דורסת בשקט', () async {
    await store.add(descriptor(name: 'המקורית'));
    await expectLater(
      store.add(descriptor(name: 'המתחזה')),
      throwsA(isA<AppDescriptorException>()),
    );
    expect((await store.load('org.example.app'))!.descriptor.name, 'המקורית');
  });

  test('שמירת תיאור קיים כן דורסת — זו הדרך לעדכן', () async {
    await store.add(descriptor(name: 'ישן'));
    await store.saveDescriptor(descriptor(name: 'חדש'));
    expect((await store.load('org.example.app'))!.descriptor.name, 'חדש');
  });

  test('הרשימה ממוינת לפי שם', () async {
    await store.add(descriptor(id: 'c', name: 'גימל'));
    await store.add(descriptor(id: 'a', name: 'אלף'));
    await store.add(descriptor(id: 'b', name: 'בית'));

    expect(
      (await store.loadAll()).map((e) => e.descriptor.name),
      ['אלף', 'בית', 'גימל'],
    );
  });

  test('תוסף פגום מדולג ואינו מפיל את השאר', () async {
    await store.add(descriptor(id: 'good', name: 'תקין'));
    File(p.join(root, 'apps', 'broken', 'descriptor.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{ זה לא JSON');

    final all = await store.loadAll();
    expect(all.map((e) => e.descriptor.id), ['good']);
  });

  group('קובץ ההתקנה השמור', () {
    test('מטא-דאטה בלי הקובץ עצמו נחשבת כאילו אין — העתקה חלקית', () async {
      await store.add(descriptor());
      await store.saveInstaller(
        'org.example.app',
        StoredInstaller(
          fileName: 'setup.exe',
          version: '1.0.0',
          sizeBytes: 10,
          addedAt: DateTime(2026, 8, 12),
        ),
      );

      expect((await store.load('org.example.app'))!.hasInstaller, isFalse);
    });

    test('מטא-דאטה עם הקובץ — נטען', () async {
      await store.add(descriptor());
      writeFile(p.join(root, 'apps', 'org.example.app', 'setup.exe'));
      await store.saveInstaller(
        'org.example.app',
        StoredInstaller(
          fileName: 'setup.exe',
          version: '1.4.2',
          sizeBytes: 1,
          addedAt: DateTime(2026, 8, 12),
        ),
      );

      final entry = await store.load('org.example.app');
      expect(entry!.hasInstaller, isTrue);
      expect(entry.installer!.version, '1.4.2');
    });

    test('הנתיב מורכב בזמן ריצה — הקובץ שומר שם בלבד', () async {
      final installer = StoredInstaller(
        fileName: 'setup.exe',
        version: '1',
        sizeBytes: 1,
        addedAt: DateTime(2026),
      );
      // המראה נוסעת בין אותיות כונן; נתיב מוחלט שמור היה נשבר ביעד.
      expect(jsonEncode(installer.toJson()), isNot(contains(root)));
      expect(
        store.installerPathFor('org.example.app', installer),
        p.join(root, 'apps', 'org.example.app', 'setup.exe'),
      );
    });
  });

  test('הסרה מוחקת את התיקייה כולה', () async {
    await store.add(descriptor());
    writeFile(p.join(root, 'apps', 'org.example.app', 'setup.exe'));

    await store.remove('org.example.app');

    expect(await store.load('org.example.app'), isNull);
    expect(Directory(p.join(root, 'apps', 'org.example.app')).existsSync(),
        isFalse);
  });

  test('הסרה של מה שאינו קיים אינה שגיאה', () async {
    await store.remove('אין-כזה');
  });
}
