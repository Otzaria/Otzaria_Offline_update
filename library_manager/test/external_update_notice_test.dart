import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

/// הסימון שאוצריא **תוכל** לקרוא כדי לדעת אילו ספרים לאנדקס מחדש אחרי עדכון
/// שנעשה מחוץ לה. ראו `README.md`, "אינדקס החיפוש".
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
}
