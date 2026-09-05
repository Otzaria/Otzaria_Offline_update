import 'package:seforim_library_updater/src/models/patch_table_spec.dart';
import 'package:seforim_library_updater/src/services/patch_applier.dart';
import 'package:test/test.dart';

/// שתי הרשימות משוכפלות אות-באות מ-SeforimLibrary (Kotlin). הבדיקות כאן
/// שומרות על התכונות המבניות שלהן — הזהות מול Kotlin עצמה נבדקת ב-
/// `patch_tables_contract_test.dart`.
void main() {
  final fkNames = kPatchTablesInFkOrder.map((t) => t.name).toList();

  group('kPatchTablesInFkOrder', () {
    test('37 טבלאות, ללא כפילויות', () {
      expect(kPatchTablesInFkOrder, hasLength(37));
      expect(fkNames.toSet(), hasLength(37));
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
      expect(fkNames.indexOf('book'), lessThan(fkNames.indexOf('line_ref')));
      expect(fkNames.indexOf('link'),
          lessThan(fkNames.indexOf('link_suppressed_side')));
    });

    // `line_dh` נושאת מסכמה 5 את `dhDisplay`, ולכן upsert עליה חייב להיות
    // DO UPDATE — אחרת שינוי בצורה המודפסת נבלע ב-DO NOTHING.
    test('line_dh ניתנת לעדכון, line_ref לא', () {
      PatchTableSpec spec(String name) =>
          kPatchTablesInFkOrder.firstWhere((t) => t.name == name);
      expect(spec('line_dh').updatable, isTrue);
      expect(spec('line_ref').updatable, isFalse);
    });
  });

  group('kHashTableOrder', () {
    test('37 טבלאות, אותה קבוצה כמו סדר ה-FK', () {
      expect(kHashTableOrder, hasLength(37));
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

  // כל רשימה קפואה היא בדיוק הרשימה שמעליה בהסרת הטבלאות שנוספו בסכמה
  // שאחריה. סטייה כלשהי פירושה ש-hashes היסטוריים לא ישוחזרו, וכל patch
  // ישן ייפסל ב-preflight.
  group('סדרי ה-hash הקפואים', () {
    test('סכמה 3 = סכמה 4 בהסרת line_ref ו-line_dh', () {
      expect(kHashTableOrderSchema3, hasLength(35));
      expect(
        kHashTableOrderSchema4
            .where((t) => t != 'line_ref' && t != 'line_dh')
            .toList(),
        kHashTableOrderSchema3,
      );
    });

    test('סכמה 2 = סכמה 3 בהסרת link_suppressed_side', () {
      expect(kHashTableOrderSchema2, hasLength(34));
      expect(
        kHashTableOrderSchema3
            .where((t) => t != 'link_suppressed_side')
            .toList(),
        kHashTableOrderSchema2,
      );
    });

    test('סכמה 1 = סכמה 2 בהסרת book_base_text', () {
      expect(kHashTableOrderSchema1, hasLength(33));
      expect(
        kHashTableOrderSchema2.where((t) => t != 'book_base_text').toList(),
        kHashTableOrderSchema1,
      );
    });
  });

  // המפה הזו היא נקודת האמת היחידה ל"איזו סכמה אנחנו יודעים להחיל patch
  // עליה" — התכנון וייצוא המראה נגזרים ממנה. חוסר התאמה בינה, הקבוע
  // ו-[isSupportedSchemaVersion] שולח patch לכישלון אחרי שהמסד החי הוחלף.
  group('kHashTableOrderBySchemaVersion', () {
    test('kSupportedDbSchemaVersion הוא המפתח הגבוה במפה', () {
      expect(
        kSupportedDbSchemaVersion,
        kHashTableOrderBySchemaVersion.keys.reduce((a, b) => a > b ? a : b),
      );
    });

    test('כל סכמה ממופה לקבוע הקפוא שלה', () {
      expect(kHashTableOrderBySchemaVersion.keys.toList(), [1, 2, 3, 4, 5]);
      expect(kHashTableOrderBySchemaVersion[1], same(kHashTableOrderSchema1));
      expect(kHashTableOrderBySchemaVersion[2], same(kHashTableOrderSchema2));
      expect(kHashTableOrderBySchemaVersion[3], same(kHashTableOrderSchema3));
      expect(kHashTableOrderBySchemaVersion[4], same(kHashTableOrderSchema4));
      // סכמה 5 שינתה עמודה בתוך `line_dh`, לא את סדר הטבלאות.
      expect(kHashTableOrderBySchemaVersion[5], same(kHashTableOrderSchema4));
    });

    test('isSupportedSchemaVersion נתמך ל-1 עד 5', () {
      for (var schema = 1; schema <= 5; schema++) {
        expect(isSupportedSchemaVersion(schema), isTrue, reason: '$schema');
      }
      // 0 אינה סכמה, ו-6 היא סכמה עתידית שאין לנו סדר hash לה.
      expect(isSupportedSchemaVersion(0), isFalse);
      expect(isSupportedSchemaVersion(6), isFalse);
    });
  });

  // הציר השני: `patch_meta.schema_version`. סכמת DB 5 פורסמה בפורמט 4, ולכן
  // קבוע משותף לשני הצירים היה מקבל פורמט 5 שאיננו יודעים להחיל.
  group('פורמט ה-patch', () {
    test('הקבועים אינם נגזרים זה מזה', () {
      expect(kSupportedPatchFormatVersion, 4);
      expect(kSupportedDbSchemaVersion, 5);
    });

    test('isSupportedPatchFormatVersion נתמך ל-1 עד 4', () {
      for (var format = 1; format <= 4; format++) {
        expect(isSupportedPatchFormatVersion(format), isTrue,
            reason: '$format');
      }
      expect(isSupportedPatchFormatVersion(0), isFalse);
      expect(isSupportedPatchFormatVersion(5), isFalse);
    });
  });

  group('kBooksTouchedTables', () {
    test('כל טבלה מוכרת גם בסדר ה-FK', () {
      expect(fkNames.toSet(), containsAll(kBooksTouchedTables));
    });

    test('schema_meta אינה נספרת כשינוי תוכן של ספר', () {
      expect(kBooksTouchedTables, isNot(contains('schema_meta')));
    });

    // אינדקסים נגזרים, לא תוכן חיפוש — ראו [kBooksTouchedTables].
    test('line_ref ו-line_dh אינן ברשימה', () {
      expect(kBooksTouchedTables, isNot(contains('line_ref')));
      expect(kBooksTouchedTables, isNot(contains('line_dh')));
    });
  });

  test('PatchTableSpec שומר את מה שהוזן', () {
    const spec = PatchTableSpec('x', ['a', 'b'], updatable: false);
    expect(spec.name, 'x');
    expect(spec.primaryKey, ['a', 'b']);
    expect(spec.updatable, isFalse);
  });
}
