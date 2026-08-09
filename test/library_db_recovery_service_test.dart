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

  test('beginApply יוצר גיבוי מאומת וסימון', () async {
    await service.beginApply(
      dbPath: dbPath,
      fromVersion: 1,
      toVersion: 2,
      timestamp: '2026-06-28T00:00:00Z',
    );
    expect(File(service.backupPathFor(dbPath)).existsSync(), isTrue);
    expect(File(service.markerPathFor(dbPath)).existsSync(), isTrue);
    expect(File(service.backupPathFor(dbPath)).readAsStringSync(), 'ORIGINAL');
    // אין שאריות temp
    expect(File('$dbPath.backup.tmp').existsSync(), isFalse);
  });

  test('beginApply(createBackup: false) כותב סימון בלבד — בלי העתקת ה-DB',
      () async {
    await service.beginApply(
      dbPath: dbPath,
      fromVersion: 1,
      toVersion: 2,
      timestamp: 't',
      createBackup: false,
    );
    expect(File(service.markerPathFor(dbPath)).existsSync(), isTrue);
    expect(File(service.backupPathFor(dbPath)).existsSync(), isFalse);
    expect(File('$dbPath.backup.tmp').existsSync(), isFalse);
  });

  test('rollback ללא גיבוי (מסלול דלתא) מנקה סימון בלי לגעת ב-DB', () async {
    await service.beginApply(
      dbPath: dbPath,
      fromVersion: 1,
      toVersion: 2,
      timestamp: 't',
      createBackup: false,
    );
    await service.rollback(dbPath);
    expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
  });

  test('finishSuccess מנקה גיבוי וסימון', () async {
    await service.beginApply(
        dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
    service.finishSuccess(dbPath);
    expect(File(service.backupPathFor(dbPath)).existsSync(), isFalse);
    expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
  });

  test('rollback משחזר את ה-DB מהגיבוי', () async {
    await service.beginApply(
        dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
    File(dbPath).writeAsStringSync('CORRUPTED-HALF-WRITE');
    await service.rollback(dbPath);
    expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    expect(File(service.backupPathFor(dbPath)).existsSync(), isFalse);
    expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
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
    test('marker+backup → שחזור (סימולציית קריסה)', () async {
      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      File(dbPath).writeAsStringSync('HALF-APPLIED'); // קריסה באמצע
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.restored);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
      expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
      expect(File(service.backupPathFor(dbPath)).existsSync(), isFalse);
    });

    test('אין marker → none', () async {
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.none);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    test('marker ללא backup → blockedMissingBackup (לא מחיקה שקטה)', () async {
      File(service.markerPathFor(dbPath)).writeAsStringSync('{}');
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.blockedMissingBackup);
      expect(result.detail, isNotNull);
      expect(File(service.markerPathFor(dbPath)).existsSync(), isTrue);
    });

    test('backup יתום ללא marker → נמחק, none', () async {
      File(service.backupPathFor(dbPath)).writeAsStringSync('STALE');
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.none);
      expect(File(service.backupPathFor(dbPath)).existsSync(), isFalse);
    });

    test('שארית backup.tmp (קריסה לפני rename) נמחקת ולא משוחזרת ממנה',
        () async {
      // backup.tmp יתום מדמה קריסה באמצע יצירת גיבוי — אסור לשחזר ממנו.
      File('$dbPath.backup.tmp').writeAsStringSync('PARTIAL');
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.none);
      expect(File('$dbPath.backup.tmp').existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL'); // ה-DB לא נגוע
    });

    test('שארית restore.tmp (קריסה באמצע שחזור) נמחקת', () async {
      File('$dbPath.restore.tmp').writeAsStringSync('PARTIAL');
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.none);
      expect(File('$dbPath.restore.tmp').existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    // ה-wal/shm שייכים ל-DB שהוחלף; השארתם אחרי rename מייצרת DB לא עקבי.
    test('שחזור מוחק -wal/-shm ואינו משאיר restore.tmp', () async {
      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      File(dbPath).writeAsStringSync('HALF-APPLIED');
      File('$dbPath-wal').writeAsStringSync('WAL');
      File('$dbPath-shm').writeAsStringSync('SHM');

      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.restored);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
      expect(File('$dbPath-wal').existsSync(), isFalse);
      expect(File('$dbPath-shm').existsSync(), isFalse);
      expect(File('$dbPath.restore.tmp').existsSync(), isFalse);
    });

    test('שחזור עובד גם כשה-DB נעלם לגמרי באמצע העדכון', () async {
      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      File(dbPath).deleteSync();
      final result = await service.recoverIfNeeded(dbPath);
      expect(result.action, RecoveryAction.restored);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    test('תוכן בינארי משוחזר בית-בית', () async {
      final bytes = List.generate(20000, (i) => (i * 7) % 256);
      File(dbPath).writeAsBytesSync(bytes);
      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      File(dbPath).writeAsBytesSync(const [1, 2, 3]);
      await service.recoverIfNeeded(dbPath);
      expect(File(dbPath).readAsBytesSync(), bytes);
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

    test('beginApply מנקה שאריות מריצה קודמת', () async {
      File(service.backupPathFor(dbPath)).writeAsStringSync('OLD-BACKUP');
      File(service.markerPathFor(dbPath)).writeAsStringSync('OLD-MARKER');
      File('$dbPath.backup.tmp').writeAsStringSync('OLD-TMP');

      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      expect(
          File(service.backupPathFor(dbPath)).readAsStringSync(), 'ORIGINAL');
      expect(File('$dbPath.backup.tmp').existsSync(), isFalse);
      expect(File(service.markerPathFor(dbPath)).readAsStringSync(),
          contains('fromVersion'));
    });

    test('clearStaleArtifacts מוחק סימון וגיבוי ומשאיר את ה-DB', () async {
      await service.beginApply(
          dbPath: dbPath, fromVersion: 1, toVersion: 2, timestamp: 't');
      service.clearStaleArtifacts(dbPath);
      expect(File(service.markerPathFor(dbPath)).existsSync(), isFalse);
      expect(File(service.backupPathFor(dbPath)).existsSync(), isFalse);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });

    test('finishSuccess/clearStaleArtifacts אינם זורקים כשאין מה למחוק', () {
      expect(() => service.finishSuccess(dbPath), returnsNormally);
      expect(() => service.clearStaleArtifacts(dbPath), returnsNormally);
    });

    test('rollback בלי סימון ובלי גיבוי אינו נוגע ב-DB', () async {
      await service.rollback(dbPath);
      expect(File(dbPath).readAsStringSync(), 'ORIGINAL');
    });
  });

  test('cloneOrCopyFile מעתיק בית-בית ודורס יעד קיים', () {
    final src = '${tmp.path}/src.bin';
    final dst = '${tmp.path}/dst.bin';
    File(src).writeAsBytesSync(List.generate(5000, (i) => i % 256));
    File(dst).writeAsBytesSync(List.filled(9, 0));
    cloneOrCopyFile(src, dst);
    expect(File(dst).readAsBytesSync(), File(src).readAsBytesSync());
  });

  test('BackupIntegrityException נושא את ההודעה שלו', () {
    const error = BackupIntegrityException('חצי');
    expect('$error', contains('חצי'));
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
