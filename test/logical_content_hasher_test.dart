import 'dart:io';

import 'package:test/test.dart';
import 'package:seforim_library_updater/src/models/patch_table_spec.dart';
import 'package:seforim_library_updater/src/services/logical_content_hasher.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _hasher = LogicalContentHasher();

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
