import 'package:seforim_library_updater/src/models/patch_table_spec.dart';
import 'package:seforim_library_updater/src/services/patch_applier.dart';
import 'package:test/test.dart';

/// שתי הרשימות משוכפלות אות-באות מ-SeforimLibrary (Kotlin). הבדיקות כאן
/// שומרות על התכונות המבניות שלהן — הזהות מול Kotlin עצמה נבדקת ב-
/// `patch_tables_contract_test.dart`.
void main() {
  final fkNames = kPatchTablesInFkOrder.map((t) => t.name).toList();

  group('kPatchTablesInFkOrder', () {
    test('34 טבלאות, ללא כפילויות', () {
      expect(kPatchTablesInFkOrder, hasLength(34));
      expect(fkNames.toSet(), hasLength(34));
    });

    test('לכל טבלה יש מפתח ראשי לא ריק', () {
      for (final table in kPatchTablesInFkOrder) {
        expect(table.primaryKey, isNotEmpty, reason: table.name);
        expect(table.primaryKey.toSet(), hasLength(table.primaryKey.length),
            reason: table.name);
      }
    });

    // updatable=false ⇒ upsert עם DO NOTHING; טבלאות junction טהורות בלבד.
    test('טבלאות לא-updatable הן junction עם PK מורכב', () {
      final junction =
          kPatchTablesInFkOrder.where((t) => !t.updatable).map((t) => t.name);
      expect(junction, contains('category_closure'));
      expect(junction, contains('book_author'));
      expect(junction, contains('book_base_text'));
      for (final table in kPatchTablesInFkOrder.where((t) => !t.updatable)) {
        expect(table.primaryKey.length, greaterThan(1), reason: table.name);
      }
    });

    // ה-deletes רצים בסדר ההפוך; הסדר קדימה חייב להתחיל בטבלאות ההורים.
    test('טבלאות ההורים קודמות לילדים בסדר ה-FK', () {
      expect(fkNames.indexOf('book'), lessThan(fkNames.indexOf('line')));
      expect(
          fkNames.indexOf('author'), lessThan(fkNames.indexOf('book_author')));
      expect(fkNames.indexOf('link'), lessThan(fkNames.indexOf('link_anchor')));
      expect(fkNames.indexOf('category'),
          lessThan(fkNames.indexOf('category_closure')));
      expect(fkNames.indexOf('alt_toc_structure'),
          lessThan(fkNames.indexOf('alt_toc_entry')));
    });
  });

  group('kHashTableOrder', () {
    test('34 טבלאות, אותה קבוצה כמו סדר ה-FK', () {
      expect(kHashTableOrder, hasLength(34));
      expect(kHashTableOrder.toSet(), fkNames.toSet());
    });

    // התיעוד מדגיש שאסור להחליף ביניהם — הבדיקה נועלת את העובדה שהם שונים.
    test('סדר ה-hash שונה מסדר ה-FK', () {
      expect(kHashTableOrder, isNot(orderedEquals(fkNames)));
    });

    test('אין כפילויות', () {
      expect(kHashTableOrder.toSet(), hasLength(kHashTableOrder.length));
    });
  });

  group('kHashTableOrderSchema1', () {
    // הרשימה הקפואה חייבת להיות בדיוק סדר-34 פחות book_base_text, אחרת
    // ה-hashes ההיסטוריים של סכמה-1 לא ישוחזרו.
    test('זהה לסדר-34 בהסרת book_base_text בלבד', () {
      expect(kHashTableOrderSchema1, hasLength(33));
      expect(
        kHashTableOrder.where((t) => t != 'book_base_text').toList(),
        kHashTableOrderSchema1,
      );
    });
  });

  group('kBooksTouchedTables', () {
    test('כל טבלה מוכרת גם בסדר ה-FK', () {
      expect(fkNames.toSet(), containsAll(kBooksTouchedTables));
    });

    test('schema_meta אינה נספרת כשינוי תוכן של ספר', () {
      expect(kBooksTouchedTables, isNot(contains('schema_meta')));
    });
  });

  test('PatchTableSpec שומר את מה שהוזן', () {
    const spec = PatchTableSpec('x', ['a', 'b'], updatable: false);
    expect(spec.name, 'x');
    expect(spec.primaryKey, ['a', 'b']);
    expect(spec.updatable, isFalse);
  });
}
