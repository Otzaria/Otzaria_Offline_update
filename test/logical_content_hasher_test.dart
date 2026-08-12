import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:seforim_library_updater/src/models/patch_table_spec.dart';
import 'package:seforim_library_updater/src/services/fast_sha256.dart';
import 'package:seforim_library_updater/src/services/logical_content_hasher.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _hasher = LogicalContentHasher();

/// מימוש-עד עצמאי של פורמט הבתים המתועד, בלי חוצץ ובלי הזרמה. משמש לאימות
/// שה-[LogicalContentHasher] המקובץ מייצר בדיוק את אותו זרם — כולל סביב גבול
/// החוצץ (1MB), שם באג היה משנה סדר בתים בלי לשנות אף hash קטן.
List<int> referenceStream(sqlite3.Database db, List<String> tableOrder) {
  final out = <int>[];
  for (final table in tableOrder) {
    out.addAll(utf8.encode(' table:$table '));
    final info = db.select('PRAGMA table_info("$table")');
    if (info.isEmpty) continue;
    final cols = info.map((r) => r['name'] as String).toList()..sort();
    out.addAll(utf8.encode('cols:${cols.join(',')}'));
    out.add(0x00);

    final selectCols = cols
        .map((c) => 'typeof("$c"),CASE WHEN typeof("$c")=\'text\' '
            'THEN CAST("$c" AS BLOB) ELSE "$c" END')
        .join(',');
    final orderBy =
        cols.contains('id') ? 'id' : cols.map((c) => '"$c"').join(',');
    for (final row
        in db.select('SELECT $selectCols FROM "$table" ORDER BY $orderBy')) {
      final values = row.values;
      for (var i = 0; i < values.length; i += 2) {
        final value = values[i + 1];
        switch (values[i] as String) {
          case 'null':
            out.add(0x00);
          case 'text':
            out.add(0x03);
            out.addAll(value as Uint8List);
          case 'blob':
            out.add(0x01);
            out.addAll(value as Uint8List);
          default:
            out.add(0x02);
            out.addAll(utf8.encode(value.toString()));
        }
        out.add(0x1F);
      }
      out.add(0xFF);
    }
  }
  return out;
}

void main() {
  group('LogicalContentHasher invariants', () {
    test('סדר הכנסה פיזי שונה → אותו hash (בזכות ORDER BY id)', () {
      final a = sqlite3.sqlite3.openInMemory();
      final b = sqlite3.sqlite3.openInMemory();
      for (final db in [a, b]) {
        db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      }
      a.execute("INSERT INTO source VALUES (1,'aleph'),(2,'bet'),(3,'gimel')");
      b.execute("INSERT INTO source VALUES (3,'gimel'),(1,'aleph'),(2,'bet')");

      expect(_hasher.compute(a), _hasher.compute(b));
      a.close();
      b.close();
    });

    test('שינוי ערך בשורה → hash שונה', () {
      final a = sqlite3.sqlite3.openInMemory();
      final b = sqlite3.sqlite3.openInMemory();
      for (final db in [a, b]) {
        db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
        db.execute("INSERT INTO source VALUES (1,'aleph'),(2,'bet')");
      }
      b.execute("UPDATE source SET name='changed' WHERE id=2");

      expect(_hasher.compute(a), isNot(_hasher.compute(b)));
      a.close();
      b.close();
    });

    test('סוגי null/int/text/blob מקודדים — שינוי סוג משנה hash', () {
      final a = sqlite3.sqlite3.openInMemory();
      final b = sqlite3.sqlite3.openInMemory();
      for (final db in [a, b]) {
        db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, v)');
      }
      // ב-a הערך הוא טקסט "1", ב-b הוא מספר 1 — צריך hash שונה (type tag).
      a.execute("INSERT INTO source VALUES (1,'1')");
      b.execute('INSERT INTO source VALUES (1,1)');
      expect(_hasher.compute(a), isNot(_hasher.compute(b)));
      a.close();
      b.close();
    });

    test('טבלה חסרה אינה מפילה את החישוב', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute("INSERT INTO source VALUES (1,'x')");
      // שאר הטבלאות ב-kHashTableOrder חסרות — אסור שזה יזרוק.
      expect(() => _hasher.compute(db), returnsNormally);
      db.close();
    });
  });

  // fixtures — שכבת רגרסיה קבועה ב-CI, ללא תלות ב-DB אמיתי.
  group('LogicalContentHasher fixtures', () {
    test('golden hash של DB ידוע יציב (לוכד רגרסיה לא-מכוונת ב-hasher)', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute("INSERT INTO source VALUES (1,'aleph'),(2,'bet'),(3,'gimel')");
      expect(
        _hasher.compute(db),
        // 34 טבלאות ב-kHashTableOrder (כולל book_base_text) — כל שם נכתב כ-
        // marker גם כשהטבלה נעדרת, לכן ה-golden מתעדכן עם סנכרון הרשימה.
        'be9a9509fc7a2ab495fb17447e6fc1b3aebc7ea7234757cac5748a00daadb265',
      );
      db.close();
    });

    // ה-hash חייב להיות עצמאי מהמימוש של SHA-256: המסלול הנייטיבי
    // (`FastSha256`) והמסלול של package:crypto מייצרים אותו golden. בלי זה
    // רגרסיה במסלול אחד הייתה נראית "עוברת" בפלטפורמה שמשתמשת בשני.
    test('שני מסלולי ה-SHA נותנים אותו golden', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute('INSERT INTO source VALUES (1, ?)', ['﻿שלום']);
      db.execute("INSERT INTO source VALUES (2,'bet'),(3,NULL)");
      db.execute('CREATE TABLE line (id INTEGER PRIMARY KEY, text TEXT)');
      db.execute('INSERT INTO line VALUES (1, ?)', ['x' * 3000]);

      addTearDown(() => FastSha256.useFallbackOnly = false);
      FastSha256.useFallbackOnly = false;
      final native = _hasher.compute(db);
      FastSha256.useFallbackOnly = true;
      final fallback = _hasher.compute(db);
      expect(native, fallback);
      db.close();
    });

    test('BOM (U+FEFF) בתחילת טקסט נכלל ב-hash — המלכוד הקריטי מול Kotlin', () {
      final withBom = sqlite3.sqlite3.openInMemory();
      final without = sqlite3.sqlite3.openInMemory();
      for (final db in [withBom, without]) {
        db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      }
      withBom.execute('INSERT INTO source VALUES (1, ?)', ['﻿aleph']);
      without.execute("INSERT INTO source VALUES (1,'aleph')");
      expect(_hasher.compute(withBom), isNot(_hasher.compute(without)));
      withBom.close();
      without.close();
    });

    // goldens נוספים — נועלים את זרם הבתים גם למקרי הקצה, לא רק ל-DB "רגיל".
    test('golden: DB ללא אף טבלה — רק ה-markers של 34 הטבלאות', () {
      final db = sqlite3.sqlite3.openInMemory();
      expect(
        _hasher.compute(db),
        'a90dcaf32e725f36c18bc4bfaa503768777cea28267328ec65d4cf2b00c1b20f',
      );
      db.close();
    });

    test('golden: טבלה קיימת אך ריקה (cols נכתב, אין שורות)', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      expect(
        _hasher.compute(db),
        'b2ff6c3838f06cff468875141e36898b788ac42a66c9ff4273e7ce59635bd675',
      );
      db.close();
    });

    // ה-golden הזה נשבר ברגע שה-BOM יילקח מ-String מפוענח במקום מ-CAST AS BLOB.
    test('golden: BOM לצד אותו טקסט בלי BOM', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute('INSERT INTO source VALUES (1,?),(2,?)', ['﻿aleph', 'aleph']);
      expect(
        _hasher.compute(db),
        'f23214051daa700264659215f40bf88ca2b4c0905426034ff2d83e8b265b25fa',
      );
      db.close();
    });

    test('golden: עברית, NULL, blob, REAL ומחרוזת ריקה בשורה אחת', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT, '
          'weight REAL, payload BLOB, note TEXT)');
      db.execute('INSERT INTO source VALUES (1,?,?,?,?)', [
        'בראשית',
        1.5,
        [0, 1, 255],
        null
      ]);
      db.execute('INSERT INTO source VALUES (2,?,?,?,?)',
          ['﻿רש״י', -0.0, <int>[], '']);
      expect(
        _hasher.compute(db),
        '70723509e74ff527af77abb47c28c68b1f18d14375ff3d598882921fa4b4336b',
      );
      db.close();
    });
  });

  group('LogicalContentHasher byte stream', () {
    test('זהה למימוש-העד על תוכן מעורב (עברית/BOM/NULL/blob/REAL)', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT, '
          'weight REAL, payload BLOB, note TEXT)');
      db.execute('INSERT INTO source VALUES (1,?,?,?,?)', [
        'בראשית',
        1.5,
        [0, 1, 255],
        null
      ]);
      db.execute(
          'INSERT INTO source VALUES (2,?,?,?,?)', ['﻿רש״י', 0, <int>[], '']);
      db.execute('CREATE TABLE category_closure '
          '(ancestorId INTEGER, descendantId INTEGER)');
      db.execute('INSERT INTO category_closure VALUES (2,3),(1,2),(1,3)');
      expect(
        _hasher.compute(db),
        sha256.convert(referenceStream(db, kHashTableOrder)).toString(),
      );
      db.close();
    });

    // ערך שגדול מהחוצץ (1MB) מוזרם ישירות אחרי flush — הנתיב שבו באג היה
    // משבש את סדר הבתים בלי להישבר על ערכים קטנים.
    test('ערך ענק (>1MB) ושכנים קטנים — זהה למימוש-העד', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute('INSERT INTO source VALUES (1,?)', ['לפני']);
      db.execute('INSERT INTO source VALUES (2,?)', ['א' * 1200000]);
      db.execute('INSERT INTO source VALUES (3,?)', ['אחרי']);
      expect(
        _hasher.compute(db),
        sha256.convert(referenceStream(db, kHashTableOrder)).toString(),
      );
      db.close();
    });

    test('ערכים סביב גבול החוצץ בדיוק — זהה למימוש-העד', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      const capacity = 1 << 20;
      for (final (i, len) in [
        (1, capacity - 1),
        (2, capacity),
        (3, capacity + 1),
      ]) {
        db.execute('INSERT INTO source VALUES (?,?)', [i, 'x' * len]);
      }
      expect(
        _hasher.compute(db),
        sha256.convert(referenceStream(db, kHashTableOrder)).toString(),
      );
      db.close();
    });

    test('onProgress: הדיווח האחרון הוא סך הבתים המדויק ומונוטוני', () {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      for (var i = 0; i < 40; i++) {
        db.execute('INSERT INTO source VALUES (?,?)', [i, 'y' * 900000]);
      }
      final reports = <int>[];
      _hasher.compute(db, onProgress: reports.add);
      expect(reports, isNotEmpty);
      expect(reports.last, referenceStream(db, kHashTableOrder).length);
      expect(reports, orderedEquals(reports.toList()..sort()));
      db.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('LogicalContentHasher canonicalisation', () {
    sqlite3.Database build(String create, List<String> inserts) {
      final db = sqlite3.sqlite3.openInMemory();
      db.execute(create);
      for (final sql in inserts) {
        db.execute(sql);
      }
      return db;
    }

    // העמודות ממוינות אלפביתית לפני הקריאה, ולכן סדר ההצהרה אינו משפיע.
    test('סדר הצהרת העמודות אינו משנה את ה-hash', () {
      final a = build(
        'CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)',
        ["INSERT INTO source VALUES (1,'aleph')"],
      );
      final b = build(
        'CREATE TABLE source (name TEXT, id INTEGER PRIMARY KEY)',
        ["INSERT INTO source (id,name) VALUES (1,'aleph')"],
      );
      expect(_hasher.compute(a), _hasher.compute(b));
      a.close();
      b.close();
    });

    test('שינוי שם עמודה משנה את ה-hash (הקידומת cols:)', () {
      final a = build(
        'CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)',
        ["INSERT INTO source VALUES (1,'aleph')"],
      );
      final b = build(
        'CREATE TABLE source (id INTEGER PRIMARY KEY, title TEXT)',
        ["INSERT INTO source VALUES (1,'aleph')"],
      );
      expect(_hasher.compute(a), isNot(_hasher.compute(b)));
      a.close();
      b.close();
    });

    // טבלה בלי עמודת id ממוינת לפי כל העמודות — junction אינה תלויה בסדר rowid.
    test('טבלה בלי id: סדר הכנסה אינו משנה', () {
      final a = build(
        'CREATE TABLE category_closure (ancestorId INTEGER, descendantId INTEGER)',
        ['INSERT INTO category_closure VALUES (1,2),(1,3),(2,3)'],
      );
      final b = build(
        'CREATE TABLE category_closure (ancestorId INTEGER, descendantId INTEGER)',
        ['INSERT INTO category_closure VALUES (2,3),(1,3),(1,2)'],
      );
      expect(_hasher.compute(a), _hasher.compute(b));
      a.close();
      b.close();
    });

    test('NULL אינו זהה למחרוזת ריקה', () {
      final a = build('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)',
          ['INSERT INTO source VALUES (1,NULL)']);
      final b = build('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)',
          ["INSERT INTO source VALUES (1,'')"]);
      expect(_hasher.compute(a), isNot(_hasher.compute(b)));
      a.close();
      b.close();
    });

    // המספר מקודד דרך toString(): 1 ≠ 1.0, בדיוק כמו בצד ה-Kotlin.
    test('INTEGER 1 אינו זהה ל-REAL 1.0', () {
      final a = build('CREATE TABLE source (id INTEGER PRIMARY KEY, v)',
          ['INSERT INTO source VALUES (1,1)']);
      final b = build('CREATE TABLE source (id INTEGER PRIMARY KEY, v)',
          ['INSERT INTO source VALUES (1,1.0)']);
      expect(_hasher.compute(a), isNot(_hasher.compute(b)));
      a.close();
      b.close();
    });

    test('blob וטקסט בעלי אותם בייטים אינם מתנגשים (בית-סוג שונה)', () {
      final a = build('CREATE TABLE source (id INTEGER PRIMARY KEY, v)',
          ["INSERT INTO source VALUES (1,'AB')"]);
      final b = sqlite3.sqlite3.openInMemory();
      b.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, v)');
      b.execute('INSERT INTO source VALUES (1,?)', [
        [0x41, 0x42]
      ]);
      expect(_hasher.compute(a), isNot(_hasher.compute(b)));
      a.close();
      b.close();
    });

    // marker נכתב לכל טבלה בסדר, גם כשאינה קיימת — הוספת שם לרשימה משנה hash.
    test('טבלה חסרה עדיין תורמת marker לזרם', () {
      final db = build('CREATE TABLE source (id INTEGER PRIMARY KEY)',
          ['INSERT INTO source VALUES (1)']);
      expect(
        _hasher.compute(db, tableOrder: const ['source']),
        isNot(_hasher.compute(db, tableOrder: const ['source', 'author'])),
      );
      db.close();
    });

    test('שינוי סדר הטבלאות משנה את ה-hash', () {
      final db = build(
        'CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)',
        ["INSERT INTO source VALUES (1,'a')"],
      );
      db.execute('CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute("INSERT INTO author VALUES (1,'b')");
      expect(
        _hasher.compute(db, tableOrder: const ['source', 'author']),
        isNot(_hasher.compute(db, tableOrder: const ['author', 'source'])),
      );
      db.close();
    });

    test('סדר-33 וסדר-34 נותנים hash שונה על אותו DB', () {
      final db = build(
        'CREATE TABLE book_base_text (bookId INTEGER, baseBookId INTEGER)',
        ['INSERT INTO book_base_text VALUES (1,2)'],
      );
      expect(
        _hasher.compute(db, tableOrder: kHashTableOrder),
        isNot(_hasher.compute(db, tableOrder: kHashTableOrderSchema1)),
      );
      db.close();
    });
  });

  // אימות מול ה-DBs האמיתיים — ה-ground truth מול מימוש ה-Kotlin.
  // מדלג אם הקבצים אינם זמינים (CI). ריצה מקומית מאמתת התאמה מלאה.
  group('LogicalContentHasher against real DBs', () {
    final releasesDir =
        Platform.environment['SEFORIM_LIBRARY_RELEASES_DIR'] ?? '/nonexistent';
    // כל fixture נבדק בשני הסדרים:
    // * hash34 — סדר 34 הטבלאות הנוכחי ([kHashTableOrder], ברירת המחדל).
    // * hashLegacy — סדר 33 הטבלאות הקפוא ([kHashTableOrderSchema1]); מוכיח
    //   שהרשימה הישנה משחזרת אות-באות את ה-hashes ההיסטוריים של סכמה-1.
    const cases = [
      (
        'v14',
        '3e6fce9860f37395468057b67bc4c53e9adcc45630fdc382a65850e7636d729c',
        '153ba2e803e5334e8e0bcaaf681d7853f14085f482ca87e70dcdd9f861f01319',
      ),
      (
        'v15',
        'f7d5ae802550f5e5580f3a0b4b9f8da02a465b4cc2b79725693dad0a2f3019ae',
        '623302b075bceb4dc823131e0e37c2ebba781f1c0215c1dddcc8b1825727ea7f',
      ),
    ];

    for (final (version, hash34, hashLegacy) in cases) {
      final path = '$releasesDir/$version/seforim.db';
      test('hash($version) — סדר 34 ו-33 תואמים ל-goldens', () {
        final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
        try {
          expect(_hasher.compute(db), hash34);
          expect(
            _hasher.compute(db, tableOrder: kHashTableOrderSchema1),
            hashLegacy,
          );
        } finally {
          db.close();
        }
      },
          skip: File(path).existsSync()
              ? false
              : 'הגדר SEFORIM_LIBRARY_RELEASES_DIR לאימות מול הפצת $version',
          timeout: const Timeout(Duration(minutes: 8)));
    }
  });
}
