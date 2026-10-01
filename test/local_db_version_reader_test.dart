import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/services/local_db_version_reader.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

const _reader = LocalDbVersionReader();

/// Lock tests must not wait out the production timeout.
const _impatient =
    LocalDbVersionReader(busyTimeout: Duration(milliseconds: 50));

void main() {
  late Directory tmp;
  var counter = 0;

  setUp(() => tmp = Directory.systemTemp.createTempSync('db_version_reader'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// בונה קובץ sqlite אמיתי על הדיסק — הקורא פותח קובץ, לא DB בזיכרון.
  String buildDb(void Function(sqlite3.Database db) build) {
    final path = '${tmp.path}/seforim_${counter++}.db';
    final db = sqlite3.sqlite3.open(path);
    try {
      build(db);
    } finally {
      db.close();
    }
    return path;
  }

  String withSchemaMeta(List<(String, Object)> rows) => buildDb((db) {
        db.execute(
            'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
        for (final (key, value) in rows) {
          db.execute('INSERT INTO schema_meta VALUES (?,?)', [key, value]);
        }
      });

  group('LocalDbVersionReader', () {
    test('קורא db_version ו-db_schema_version מקובץ sqlite אמיתי', () {
      final path =
          withSchemaMeta([('db_version', '15'), ('db_schema_version', '2')]);
      final version = _reader.read(path);
      expect(version.dbVersion, 15);
      expect(version.schemaVersion, 2);
      expect(version.hasVersionMeta, isTrue);
    });

    // SeforimLibrary כותב את הערכים כטקסט, אך INTEGER חייב להתפרש זהה.
    test('ערך מספרי (INTEGER) נקרא כמו טקסט', () {
      final path =
          withSchemaMeta([('db_version', 15), ('db_schema_version', 2)]);
      final version = _reader.read(path);
      expect(version.dbVersion, 15);
      expect(version.schemaVersion, 2);
      expect(version.hasVersionMeta, isTrue);
    });

    test('db_schema_version חסר → null, אך hasVersionMeta נשאר true', () {
      final path = withSchemaMeta([('db_version', '15')]);
      final version = _reader.read(path);
      expect(version.dbVersion, 15);
      expect(version.schemaVersion, isNull);
      expect(version.hasVersionMeta, isTrue);
    });

    test('db_version חסר → 0 ו-hasVersionMeta=false (מסלול הורדה מלאה)', () {
      final path = withSchemaMeta([('db_schema_version', '2')]);
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.schemaVersion, 2);
      expect(version.hasVersionMeta, isFalse);
    });

    test('ערך שאינו מספר נחשב חסר', () {
      final path = withSchemaMeta([('db_version', 'לא-מספר')]);
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.hasVersionMeta, isFalse);
    });

    test('DB ללא טבלת schema_meta → 0/false בלי לזרוק (DB ישן מאוד)', () {
      final path = buildDb((db) => db.execute('CREATE TABLE t (id INTEGER)'));
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.schemaVersion, isNull);
      expect(version.hasVersionMeta, isFalse);
    });

    test('DB ריק לגמרי (קובץ באורך 0) → 0/false', () {
      final path = '${tmp.path}/empty.db';
      File(path).writeAsBytesSync(const []);
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.hasVersionMeta, isFalse);
    });

    // קובץ שאינו DB אינו מבחין את עצמו מ-DB ישן: שניהם hasVersionMeta=false,
    // והתוכנן שנבחר עבורם זהה (הורדה מלאה) — לכן זו התנהגות ולא כשל.
    test('קובץ שאינו DB → 0/false ולא זריקה', () {
      final path = '${tmp.path}/not_a_db.db';
      File(path).writeAsStringSync('זה בכלל לא בסיס נתונים');
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.hasVersionMeta, isFalse);
    });

    // A locked DB is not a DB without a version: reporting 0/false here let the
    // planner skip its no-downgrade guard and replace a newer live DB.
    test('DB locked by another connection throws instead of 0/false', () {
      final path =
          withSchemaMeta([('db_version', '26'), ('db_schema_version', '4')]);
      final writer = sqlite3.sqlite3.open(path);
      try {
        writer.execute('BEGIN EXCLUSIVE');
        writer.execute(
            "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'");
        expect(
          () => _impatient.read(path),
          throwsA(isA<LocalDbUnreadableException>()
              .having((e) => e.reason, 'reason', LocalDbUnreadableReason.locked)
              .having((e) => e.extendedResultCode & 0xFF, 'resultCode',
                  5 /* SQLITE_BUSY */)),
        );
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
      }
      expect(_reader.read(path).dbVersion, 26);
    });

    // The check runs this from the UI isolate: the error must cross the hop
    // intact and still render in the caller's language.
    test('readInIsolate rethrows the localized locked error', () async {
      final path = withSchemaMeta([('db_version', '26')]);
      expect((await _impatient.readInIsolate(path)).dbVersion, 26);
      final writer = sqlite3.sqlite3.open(path);
      AppL10n.use(AppLanguage.english);
      try {
        writer.execute('BEGIN EXCLUSIVE');
        writer.execute(
            "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'");
        await expectLater(
          _impatient.readInIsolate(path),
          throwsA(isA<LocalDbUnreadableException>().having(
            (e) => e.toString(),
            'toString',
            AppL10n.strings.libraryDomain.localDbLocked,
          )),
        );
        expect(
            AppL10n.strings.libraryDomain.localDbLocked, contains('Otzaria'));
      } finally {
        AppL10n.use(AppLanguage.hebrew);
        writer.execute('ROLLBACK');
        writer.close();
      }
    });

    // Otzaria killed mid-write leaves a hot journal a read-only open cannot
    // roll back; the version under it is unknown, not 0.
    test('hot journal throws LocalDbUnreadableException, not 0/false', () {
      final path = buildDb((db) {
        db.execute(
            'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
        db.execute("INSERT INTO schema_meta VALUES ('db_version', '26')");
        db.execute('CREATE TABLE filler (blob BLOB)');
        for (var i = 0; i < 50; i++) {
          db.execute('INSERT INTO filler VALUES (zeroblob(4096))');
        }
      });
      final crashed = '${tmp.path}/crashed.db';
      final writer = sqlite3.sqlite3.open(path);
      try {
        // A tiny cache spills dirty pages into the DB file before COMMIT.
        writer.execute('PRAGMA cache_size = 1');
        writer.execute('BEGIN');
        writer.execute('UPDATE filler SET blob = randomblob(4096)');
        File(path).copySync(crashed);
        File('$path-journal').copySync('$crashed-journal');
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
      }
      expect(
        () => _reader.read(crashed),
        throwsA(isA<LocalDbUnreadableException>()
            .having((e) => e.reason, 'reason',
                LocalDbUnreadableReason.interruptedWrite)
            .having((e) => e.extendedResultCode, 'extendedResultCode',
                776 /* SQLITE_READONLY_ROLLBACK */)),
      );
    });

    // A WAL DB on a write-denied folder: SQLite cannot create `-shm`. Windows
    // reports CANTOPEN; the old catch-all read it as version 0.
    test('WAL DB in a write-denied folder throws readOnlyLocation', () {
      final dir = Directory('${tmp.path}/locked_dir')..createSync();
      final path = '${dir.path}/seforim.db';
      final db = sqlite3.sqlite3.open(path);
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute("INSERT INTO schema_meta VALUES ('db_version', '26')");
      db.close();
      final user = Platform.environment['USERNAME']!;
      final deny =
          Process.runSync('icacls', [dir.path, '/deny', '$user:(W,D,DC)']);
      expect(deny.exitCode, 0, reason: '${deny.stdout}${deny.stderr}');
      try {
        expect(
          () => _reader.read(path),
          throwsA(isA<LocalDbUnreadableException>().having((e) => e.reason,
              'reason', LocalDbUnreadableReason.readOnlyLocation)),
        );
      } finally {
        Process.runSync('icacls', [dir.path, '/remove:d', user]);
      }
    }, testOn: 'windows');

    // Some other tool's schema_meta: not ours, so no version, not a crash.
    test('schema_meta without key/value columns gives 0/false', () {
      final path = buildDb((db) {
        db.execute('CREATE TABLE schema_meta (name TEXT, version INTEGER)');
        db.execute("INSERT INTO schema_meta VALUES ('db_version', 26)");
      });
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.hasVersionMeta, isFalse);
    });

    // Codes that are impractical to reproduce on every OS (LOCKED needs shared
    // cache, RECOVERY a crashed WAL, READONLY_DIRECTORY a write-denied folder).
    test('classifies SQLite codes into no-version, transient or rethrow', () {
      const reasonFor = LocalDbVersionReader.unreadableReasonFor;
      expect(reasonFor(5), LocalDbUnreadableReason.locked); // BUSY
      expect(reasonFor(517), LocalDbUnreadableReason.locked); // BUSY_SNAPSHOT
      expect(reasonFor(6), LocalDbUnreadableReason.locked); // LOCKED
      expect(
          reasonFor(262), LocalDbUnreadableReason.locked); // LOCKED_SHAREDCACHE
      expect(reasonFor(264),
          LocalDbUnreadableReason.interruptedWrite); // READONLY_RECOVERY
      expect(reasonFor(776),
          LocalDbUnreadableReason.interruptedWrite); // READONLY_ROLLBACK
      expect(reasonFor(1544),
          LocalDbUnreadableReason.readOnlyLocation); // READONLY_DIRECTORY
      expect(reasonFor(520),
          LocalDbUnreadableReason.readOnlyLocation); // READONLY_CANTLOCK
      expect(reasonFor(1288),
          LocalDbUnreadableReason.readOnlyLocation); // READONLY_CANTINIT
      for (final other in [1, 8, 10, 14, 266]) {
        expect(reasonFor(other), isNull, reason: 'code $other');
      }
      // CANTOPEN after the open succeeded is the WAL side file, not the DB.
      expect(reasonFor(14, opened: true),
          LocalDbUnreadableReason.readOnlyLocation);

      const permanent = LocalDbVersionReader.isPermanentlyUnreadable;
      expect(permanent(11), isTrue); // CORRUPT
      expect(permanent(267), isTrue); // CORRUPT_VTAB
      expect(permanent(26), isTrue); // NOTADB
      expect(permanent(5), isFalse);
      expect(permanent(1544), isFalse);
    });

    // A corrupt file is permanent and has no trustworthy version, so the full
    // download that replaces it must stay available.
    test('truncated DB (SQLITE_CORRUPT) gives 0/false', () {
      final path = buildDb((db) {
        db.execute('CREATE TABLE filler (blob BLOB)');
        for (var i = 0; i < 50; i++) {
          db.execute('INSERT INTO filler VALUES (zeroblob(4096))');
        }
        db.execute(
            'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
        db.execute("INSERT INTO schema_meta VALUES ('db_version', '26')");
      });
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      final version = _reader.read(path);
      expect(version.dbVersion, 0);
      expect(version.hasVersionMeta, isFalse);
    });

    test('קובץ חסר → זורק', () {
      expect(
        () => _reader.read('${tmp.path}/missing.db'),
        throwsA(isA<sqlite3.SqliteException>()),
      );
    });

    // הפתיחה read-only: אסור שהבדיקה תשנה את ה-DB של המשתמש או תשאיר -wal/-shm.
    test('הקריאה אינה משנה את הקובץ ואינה יוצרת קובצי לוואי', () {
      final path = withSchemaMeta([('db_version', '15')]);
      final before = File(path).readAsBytesSync();
      _reader.read(path);
      expect(File(path).readAsBytesSync(), before);
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File('$path-shm').existsSync(), isFalse);
      expect(File('$path-journal').existsSync(), isFalse);
    });
  });
}
