import 'dart:io';

import 'package:seforim_library_updater/src/services/local_db_version_reader.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

const _reader = LocalDbVersionReader();

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
