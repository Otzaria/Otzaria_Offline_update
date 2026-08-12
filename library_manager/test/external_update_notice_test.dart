import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

/// הסימון שבקשת עדכון אינדקס ממתינה לאוצריא, אחרי עדכון מסד שנעשה מחוץ לה.
/// ראו `README.md`, "אינדקס החיפוש".
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('external-notice-');
    dbPath = p.join(tempDir.path, 'seforim.db');
    await File(dbPath).writeAsString('db');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Map<String, dynamic> readNotice() => jsonDecode(
        File(p.join(tempDir.path, ExternalUpdateNotice.fileName))
            .readAsStringSync(),
      ) as Map<String, dynamic>;

  test('מסלול דלתא רושם את מזהי הספרים שהשתנו, ממוינים', () async {
    await const ExternalUpdateNotice().write(
      dbPath: dbPath,
      route: ExternalUpdateNotice.routeDelta,
      booksTouched: {7, 2, 5},
      dbVersion: 15,
      releaseTag: 'v15',
    );

    final json = readNotice();
    expect(json['route'], ExternalUpdateNotice.routeDelta);
    expect(json['booksTouched'], [2, 5, 7]);
    expect(json['dbVersion'], 15);
    expect(json['releaseTag'], 'v15');
    expect(json['source'], 'otzaria-launcher');
  });

  test('הורדה מלאה רושמת רשימה ריקה — שם ההשוואה היא לפי טביעות-אצבע',
      () async {
    await const ExternalUpdateNotice().write(
      dbPath: dbPath,
      route: ExternalUpdateNotice.routeFull,
      dbVersion: 16,
    );

    final json = readNotice();
    expect(json['route'], ExternalUpdateNotice.routeFull);
    expect(json['booksTouched'], isEmpty);
  });

  test('שני עדכונים לפני שאוצריא נפתחה — הספרים מצטברים ולא נדרסים', () async {
    const notice = ExternalUpdateNotice();
    await notice.write(
      dbPath: dbPath,
      route: ExternalUpdateNotice.routeDelta,
      booksTouched: {3, 1},
      dbVersion: 15,
    );
    await notice.write(
      dbPath: dbPath,
      route: ExternalUpdateNotice.routeDelta,
      booksTouched: {4, 1},
      dbVersion: 16,
    );

    final json = readNotice();
    expect(json['booksTouched'], [1, 3, 4]);
    // הגרסה היא של העדכון האחרון — היא מתארת את המסד כפי שהוא עכשיו.
    expect(json['dbVersion'], 16);
  });

  test('מסלול מלא מנצח במיזוג — הוא גורף ממילא', () async {
    const notice = ExternalUpdateNotice();
    await notice.write(
      dbPath: dbPath,
      route: ExternalUpdateNotice.routeFull,
      dbVersion: 15,
    );
    await notice.write(
      dbPath: dbPath,
      route: ExternalUpdateNotice.routeDelta,
      booksTouched: {9},
      dbVersion: 16,
    );

    expect(readNotice()['route'], ExternalUpdateNotice.routeFull);
  });

  test('כשל כתיבה אינו זורק — העדכון עצמו כבר הצליח', () async {
    // נתיב לתיקייה שאינה קיימת: הכתיבה נכשלת ונבלעת.
    await const ExternalUpdateNotice().write(
      dbPath: p.join(tempDir.path, 'nope', 'deeper', 'seforim.db'),
      route: ExternalUpdateNotice.routeDelta,
    );
  });

  group('read — הסימון שהלאנצ׳ר קורא בעלייה', () {
    const notice = ExternalUpdateNotice();

    test('בלי קובץ אין בקשה ממתינה', () async {
      expect(await notice.read(dbPath: dbPath), isNull);
    });

    test('קורא בחזרה את מה שנכתב', () async {
      await notice.write(
        dbPath: dbPath,
        route: ExternalUpdateNotice.routeDelta,
        booksTouched: {5, 1},
        dbVersion: 21,
        releaseTag: 'v21',
      );

      final data = (await notice.read(dbPath: dbPath))!;
      expect(data.route, ExternalUpdateNotice.routeDelta);
      expect(data.isFullRoute, isFalse);
      expect(data.booksTouched, {1, 5});
      expect(data.dbVersion, 21);
      expect(data.releaseTag, 'v21');
      expect(data.updatedAt, isNotNull);
    });

    // JSON פגום או פורמט זר הוא "אין בקשה" — ולא נמחק. גרסת פורמט שלא הובנה
    // עשויה להיות מובנת לגרסה אחרת של הלאנצ'ר.
    test('קובץ פגום ופורמט לא מוכר נחשבים "אין", בלי למחוק', () async {
      final file = File(p.join(tempDir.path, ExternalUpdateNotice.fileName));

      await file.writeAsString('{ לא JSON');
      expect(await notice.read(dbPath: dbPath), isNull);
      expect(file.existsSync(), isTrue);

      await file.writeAsString(jsonEncode({'formatVersion': 99}));
      expect(await notice.read(dbPath: dbPath), isNull);
      expect(file.existsSync(), isTrue);
    });

    test('מיזוג נשען על read — פורמט לא מוכר אינו נבלע לתוך הסימון החדש',
        () async {
      await File(p.join(tempDir.path, ExternalUpdateNotice.fileName))
          .writeAsString(jsonEncode({
        'formatVersion': 99,
        'route': ExternalUpdateNotice.routeFull,
        'booksTouched': [42],
      }));

      await notice.write(
        dbPath: dbPath,
        route: ExternalUpdateNotice.routeDelta,
        booksTouched: {7},
      );

      final json = readNotice();
      expect(json['route'], ExternalUpdateNotice.routeDelta);
      expect(json['booksTouched'], [7]);
    });
  });

  group('clear — רק אחרי שהבקשה נמסרה', () {
    const notice = ExternalUpdateNotice();

    test('מוחק את הסימון', () async {
      await notice.write(
        dbPath: dbPath,
        route: ExternalUpdateNotice.routeFull,
      );
      expect(await notice.read(dbPath: dbPath), isNotNull);

      await notice.clear(dbPath: dbPath);

      expect(await notice.read(dbPath: dbPath), isNull);
      expect(
        File(p.join(tempDir.path, ExternalUpdateNotice.fileName)).existsSync(),
        isFalse,
      );
    });

    test('מחיקה בלי קובץ אינה זורקת', () async {
      await notice.clear(dbPath: dbPath);
      await notice.clear(dbPath: p.join(tempDir.path, 'nope', 'seforim.db'));
    });
  });
}
