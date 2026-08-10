import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';
import 'package:seforim_library_updater/src/services/library_db_recovery_service.dart';

void main() {
  const service = LibraryDbRecoveryService();
  late Directory tmp;
  late String dbPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('recovery_test');
    dbPath = '${tmp.path}/seforim.db';
    File(dbPath).writeAsStringSync('ORIGINAL');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('beginApply כותב סימון בלבד — בלי העתקה של ה-DB', () async {
    await service.beginApply(
      dbPath: dbPath,
      fromVersion: 1,
      toVersion: 2,
      timestamp: '2026-06-28T00:00:00Z',
    );
    expect(File(service.markerPathFor(dbPath)).existsSync(), isTrue);
    expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    // אף עותק נוסף של המסד לא נוצר — זו כל הנקודה. רק ה-DB והסימון.
    expect(tmp.listSync().length, 2);
  });

  test('finishSuccess מנקה את הסימון', () async {
    await service.beginApply(
        dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
    service.finishSuccess(dbPath);
    expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
    expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
  });

  group('checkDbHealthAfterCrash', () {
    test('מגלגל hot journal (קריסה באמצע apply) ומחזיר true', () {
      final crashed = _makeHotJournalDb(tmp.path);
      // רגרסיה: פתיחת readOnly על hot journal נכשלת ב-"readonly database".
      // ה-handle נסגר במפורש: ב-Windows חיבור שנשאר פתוח חוסם את מחיקת
      // תיקיית ה-temp ב-tearDown (וגם את פתיחת ה-RW שאחריו).
      final probe =
          sqlite3.sqlite3.open(crashed, mode: sqlite3.OpenMode.readOnly);
      try {
        expect(
          () => probe.select('PRAGMA quick_check'),
          throwsA(isA<sqlite3.SqliteException>()),
        );
      } finally {
        probe.close();
      }
      // ה-RW של השירות מגלגל את ה-journal ומאמת תקינות.
      expect(service.checkDbHealthAfterCrash(crashed), isTrue);
      expect(File('$crashed-journal').existsSync(), isFalse);
    });

    test('DB פגום → false', () {
      final broken = '${tmp.path}/broken.db';
      File(broken).writeAsBytesSync(List.filled(4096, 0x7a));
      expect(service.checkDbHealthAfterCrash(broken), isFalse);
    });
  });

  group('recoverIfNeeded', () {
    test('אין marker → none, ה-DB לא נגוע', () async {
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.none);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    test('marker → interrupted, והסימון נשאר לקורא', () async {
      File(service.markerPathFor(dbPath)).writeAsStringSync('{}');
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.interrupted);
      expect(result.detail, isNotNull);
      expect(File(service.markerPathFor(dbPath)).existsSync(), isTrue);
      // אין שחזור: ה-DB נשאר בדיוק כפי שהיה, והקורא בודק תקינות בעצמו.
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    // מי שעדכן מגרסה שכן יצרה גיבוי — הקבצים האלה שווים ~1GB על הכונן.
    test('שאריות הגיבוי מהמנגנון שהוסר נמחקות, בלי לשחזר מהן', () async {
      File('$dbPath.backup').writeAsStringSync('OLD-BACKUP');
      File('$dbPath.backup.tmp').writeAsStringSync('PARTIAL');
      File('$dbPath.restore.tmp').writeAsStringSync('PARTIAL');

      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.none);
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File('$dbPath.backup.tmp').existsSync(), isFalse);
      expect(File('$dbPath.restore.tmp').existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    test('שאריות גיבוי נמחקות גם כשיש marker', () async {
      File('$dbPath.backup').writeAsStringSync('OLD-BACKUP');
      File(service.markerPathFor(dbPath)).writeAsStringSync('{}');

      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.interrupted);
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });
  });

  group('סימון ה-apply', () {
    test('הסימון מכיל את הגרסאות ואת חותמת הזמן', () async {
      await service.beginApply(
        dbPath: dbPath,
        fromVersion: 14,
        toVersion: 15,
        timestamp: '2026-06-28T00:00:00Z',
      );
      final marker =
          jsonDecode(File(service.markerPathFor(dbPath)).readAsStringSync())
              as Map<String, dynamic>;
      expect(marker['fromVersion'], 14);
      expect(marker['toVersion'], 15);
      expect(marker['timestamp'], '2026-06-28T00:00:00Z');
    });

    test('beginApply מנקה שאריות גיבוי מריצה קודמת', () async {
      File('$dbPath.backup').writeAsStringSync('OLD-BACKUP');
      File(service.markerPathFor(dbPath)).writeAsStringSync('OLD-MARKER');

      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File(service.markerPathFor(dbPath)).readAsStringSync(),
          contains('fromVersion'));
    });

    test('clearStaleArtifacts מוחק סימון ומשאיר את ה-DB', () async {
      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      service.clearStaleArtifacts(dbPath);
      expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    test('finishSuccess/clearStaleArtifacts אינם זורקים כשאין מה למחוק', () {
      expect(() => service.finishSuccess(dbPath), returnsNormally);
      expect(() => service.clearStaleArtifacts(dbPath), returnsNormally);
    });
  });
}

/// בונה DB עם hot journal אמיתי (מדמה קריסה באמצע transaction) ומחזיר את נתיבו.
/// cache_size זעיר מכריח דפים מלוכלכים להישפך ל-DB תוך כדי ה-transaction, כך
/// שהעתקת הזוג (db+journal) לפני ה-COMMIT לוכדת מצב שדורש גלגול.
String _makeHotJournalDb(String dir) {
  final src = '$dir/live.db';
  var c = sqlite3.sqlite3.open(src);
  c.execute('PRAGMA journal_mode=DELETE');
  c.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)');
  c.execute('BEGIN');
  final ins = c.prepare('INSERT INTO t VALUES (?,?)');
  for (var i = 0; i < 20000; i++) {
    ins.execute([i, 'A']);
  }
  ins.close();
  c.execute('COMMIT');
  c.close();

  c = sqlite3.sqlite3.open(src);
  c.execute('PRAGMA journal_mode=DELETE');
  c.execute('PRAGMA cache_size=10');
  c.execute('BEGIN IMMEDIATE');
  c.execute("UPDATE t SET v='B'");

  final crashed = '$dir/crashed.db';
  File(src).copySync(crashed);
  File('$src-journal').copySync('$crashed-journal');

  c.execute('ROLLBACK');
  c.close();
  return crashed;
}
