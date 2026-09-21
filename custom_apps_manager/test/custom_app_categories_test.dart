import 'dart:convert';
import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String root;
  late CustomAppCategoriesStore store;

  setUp(() {
    root = tempMirrorRoot();
    store = CustomAppCategoriesStore(mirrorRootDir: root);
  });

  group('המרשם', () {
    test('בלי קובץ — רשימה ריקה, וזה המצב הרגיל', () async {
      expect(await store.load(), isEmpty);
    });

    test('שמירה וטעינה', () async {
      await store.save(const [
        CustomAppCategory(slug: 'tools', name: 'כלים', description: 'עזרים'),
        CustomAppCategory(slug: 'study', name: 'לימוד'),
      ]);

      final loaded = await store.load();
      expect(loaded.map((c) => c.slug), ['tools', 'study']);
      expect(loaded.first.name, 'כלים');
      expect(loaded.first.description, 'עזרים');
      // הסדר הוא סדר התצוגה שנקבע, ולא מיון מחדש.
      expect(loaded.last.description, isEmpty);
    });

    test('קובץ פגום נקרא כריק ואינו מפיל את הטעינה', () async {
      File(store.filePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{ זה לא JSON');

      expect(await store.load(), isEmpty);
    });

    test('רשומה בלי slug תקין מדולגת, והשאר נטענות', () async {
      File(store.filePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'schemaVersion': 1,
          'categories': [
            {'slug': '../escape', 'name': 'זדוני'},
            {'name': 'בלי slug'},
            {'slug': 'ok', 'name': 'תקינה'},
          ],
        }));

      final loaded = await store.load();
      expect(loaded.map((c) => c.slug), ['ok']);
    });

    test('קובץ מפורמט חדש יותר אינו מנוחש', () async {
      File(store.filePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'schemaVersion': 99,
          'categories': [
            {'slug': 'ok', 'name': 'תקינה'},
          ],
        }));

      expect(await store.load(), isEmpty);
    });
  });

  group('ייצור slug', () {
    test('נגזר מהשם כשהוא לטיני', () {
      expect(CustomAppCategory.slugFor('Study Tools'), 'study-tools');
    });

    // שם בעברית אינו משאיר תו לטיני — ה-slug הוא מפתח ואינו מוצג.
    test('שם בעברית נופל לבסיס קבוע ואינו מתנגש', () {
      final first = CustomAppCategory.slugFor('כלים');
      expect(first, CustomAppCategory.slugFallback);

      final second = CustomAppCategory.slugFor('לימוד', taken: {first});
      expect(second, isNot(first));
    });
  });
}
