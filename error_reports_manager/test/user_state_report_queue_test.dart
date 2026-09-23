import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

/// הסכמה של `UserStateDatabase._createSchema` באוצריא (upstream/dev,
/// 52678edb3), מילה במילה — כך הבדיקה רצה מול המבנה האמיתי.
void _createOtzariaSchema(Database db, {int userVersion = 1}) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS lists (
      box TEXT NOT NULL,
      key TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (box, key)
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS pending_reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  ''');
  db.execute('PRAGMA user_version = $userVersion');
}

Map<String, dynamic> _stored(String id,
        {Map<String, dynamic> extra = const {}}) =>
    {
      'id': id,
      'senderEmail': 'a@b.co',
      'subject': 'נושא',
      'bookTitle': 'ספר $id',
      'currentRef': 'פרק א',
      'lineNumber': 3,
      'errorDetails': 'טעות',
      'createdAt': '2026-09-01T10:00:00.000Z',
      'schemaVersion': 2,
      ...extra,
    };

void main() {
  late Directory temp;
  late String dbPath;
  const pending = UserStateReportQueue.pendingKind;
  const sent = UserStateReportQueue.sentKind;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('user_state_test');
    dbPath = p.join(temp.path, 'user_state.db');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Database create({int userVersion = 1}) {
    final db = sqlite3.open(dbPath);
    _createOtzariaSchema(db, userVersion: userVersion);
    return db;
  }

  void insert(Database db, String kind, Object payload) => db.execute(
        'INSERT INTO pending_reports (kind, payload_json, created_at) '
        'VALUES (?, ?, 0)',
        [kind, payload is String ? payload : jsonEncode(payload)],
      );

  List<Map<String, dynamic>> rows(String kind) {
    final db = sqlite3.open(dbPath);
    try {
      return [
        for (final r in db.select(
            'SELECT payload_json FROM pending_reports WHERE kind = ? ORDER BY id',
            [kind]))
          jsonDecode(r['payload_json'] as String) as Map<String, dynamic>,
      ];
    } finally {
      db.close();
    }
  }

  int? counter() {
    final db = sqlite3.open(dbPath);
    try {
      final r = db.select(
          "SELECT payload_json FROM lists WHERE box = 'error_reports_queue' "
          "AND key = 'sent_reports_total'");
      return r.isEmpty
          ? null
          : (jsonDecode(r.first['payload_json'] as String) as List).first
              as int;
    } finally {
      db.close();
    }
  }

  test('כל עבודת ה-SQLite עוברת ב-isolate: אחת לספירה, שתיים לאיסוף', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    db.close();

    var calls = 0;
    Future<R> counting<R>(FutureOr<R> Function() computation) {
      calls++;
      return Isolate.run(computation);
    }

    final queue = UserStateReportQueue(dbPath, runIsolated: counting);
    expect(await queue.countSendable(), 1);
    expect(calls, 1);
    final result = await queue.collectTo(MemoryOutbox(const []));
    expect(result.collected, 1);
    expect(calls, 3); // קריאה, ואחרי כתיבת הקבצים — הסימון
  });

  test('כשל של שלב הסימון כולו — כל הקבצים נמחקים, והשורות נשארות', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('b'));
    db.close();

    var calls = 0;
    Future<R> failSecond<R>(FutureOr<R> Function() computation) {
      if (++calls == 2) return Future.error(StateError('database is locked'));
      return Isolate.run(computation);
    }

    final outbox = MemoryOutbox(const []);
    final queue = UserStateReportQueue(dbPath, runIsolated: failSecond);
    await expectLater(queue.collectTo(outbox), throwsStateError);
    expect(outbox.reports, isEmpty);
    expect(rows(pending), hasLength(2));
    expect(rows(sent), isEmpty);
  });

  test('כתיבה שנכשלה לדיווח אחד — הוא נשאר באוצריא, השני נאסף', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('b'));
    db.close();

    final outbox = _FailingOutbox('a');
    final result = await UserStateReportQueue(dbPath).collectTo(outbox);

    expect(result.collected, 1);
    expect(result.error, contains('disk full'));
    expect(outbox.reports.map((r) => r.reportId), ['b']);
    expect(rows(pending).map((r) => r['id']), ['a']);
    expect(rows(sent).map((r) => r['id']), ['b']);
  });

  test('ריצה מעורבת — שורה שהשתנתה נמחקת מהתיבה, זו שהועברה נשארת', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('b'));
    db.close();

    final outbox = _ChangingOutbox(() {
      final other = sqlite3.open(dbPath);
      other.execute(
        'UPDATE pending_reports SET payload_json = ? WHERE id = 2',
        [
          jsonEncode(_stored('b', extra: {'errorDetails': 'נערך'}))
        ],
      );
      other.close();
    });
    final result = await UserStateReportQueue(dbPath).collectTo(outbox);

    expect(result.collected, 1);
    expect(result.error, isNull); // שורה שהשתנתה אינה שגיאה
    expect(outbox.reports.map((r) => r.reportId), ['a']);
    expect(rows(pending).map((r) => r['id']), ['b']);
    expect(rows(sent).map((r) => r['id']), ['a']);
  });

  test('המסד נעלם בין הקריאה לסימון — הקבצים נמחקים, והשגיאה ליומן', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    db.close();

    var calls = 0;
    Future<R> deleteBeforeMark<R>(FutureOr<R> Function() computation) {
      if (++calls == 2) File(dbPath).deleteSync();
      return Isolate.run(computation);
    }

    final outbox = MemoryOutbox(const []);
    final result =
        await UserStateReportQueue(dbPath, runIsolated: deleteBeforeMark)
            .collectTo(outbox);
    expect(result.collected, 0);
    expect(result.error, isNotNull);
    expect(outbox.reports, isEmpty);
  });

  test('סופר רק דיווחים שאפשר לשלוח, ורק מהתור של השגיאות', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('newer', extra: {'schemaVersion': 3}));
    insert(db, pending, _stored('broken', extra: {'errorDetails': '\uD83D'}));
    insert(db, pending, '{not json');
    insert(db, pending, {'id': 'missing-fields'});
    insert(db, 'plugin_reports_queue/pending_reports', _stored('plugin'));
    db.close();

    expect(await UserStateReportQueue(dbPath).countSendable(), 1);
  });

  test('איסוף: קובץ בתיבה, השורה עוברת להיסטוריה, המונה עולה', () async {
    final db = create();
    insert(db, sent, _stored('old'));
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('b'));
    insert(db, pending, _stored('newer', extra: {'schemaVersion': 3}));
    db.close();

    final outbox = MemoryOutbox(const []);
    final result = await UserStateReportQueue(dbPath).collectTo(outbox);

    expect(result.collected, 2);
    expect(result.error, isNull);
    expect(outbox.reports.map((r) => r.reportId), ['a', 'b']);
    final a = outbox.reports.first;
    expect(a.bookTitle, 'ספר a');
    expect(a.isAllowedEndpoint, isTrue);
    expect(a.body['report_id'], 'a');
    expect(a.body['schema_version'], 2);

    expect(rows(pending).map((r) => r['id']), ['newer']);
    expect(rows(sent).map((r) => r['id']), ['old', 'a', 'b']);
    // בלי מונה קודם — מתחיל מגודל ההיסטוריה (1), כמו `increment(floor:)`.
    expect(counter(), 3);
  });

  test('דיווח שכבר בהיסטוריה מוחלף, והמונה אינו עולה עליו', () async {
    final db = create();
    insert(db, sent, _stored('a', extra: {'errorDetails': 'ישן'}));
    insert(db, pending, _stored('a'));
    db.close();

    await UserStateReportQueue(dbPath).collectTo(MemoryOutbox(const []));
    expect(rows(sent).map((r) => r['errorDetails']), ['טעות']);
    expect(counter(), isNull);
  });

  test('ההיסטוריה נחתכת ל-100', () async {
    final db = create();
    for (var i = 0; i < 100; i++) {
      insert(db, sent, _stored('s$i'));
    }
    insert(db, pending, _stored('new'));
    db.close();

    await UserStateReportQueue(dbPath).collectTo(MemoryOutbox(const []));
    final history = rows(sent);
    expect(history, hasLength(100));
    expect(history.first['id'], 's1');
    expect(history.last['id'], 'new');
  });

  test('שורה שהשתנתה בין הקריאה לסימון — לא מועברת, והקובץ נמחק', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    db.close();

    final outbox = _ChangingOutbox(() {
      final other = sqlite3.open(dbPath);
      other.execute('UPDATE pending_reports SET payload_json = ?', [
        jsonEncode(_stored('a', extra: {'errorDetails': 'נערך'}))
      ]);
      other.close();
    });
    final result = await UserStateReportQueue(dbPath).collectTo(outbox);

    expect(result.collected, 0);
    expect(outbox.reports, isEmpty);
    expect(rows(pending), hasLength(1));
    expect(rows(sent), isEmpty);
  });

  test('שתי שורות באותו מזהה — נאסף פעם אחת, והקובץ נשאר', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('a', extra: {'errorDetails': 'עותק'}));
    db.close();

    final queue = UserStateReportQueue(dbPath);
    expect(await queue.countSendable(), 1);
    final outbox = MemoryOutbox(const []);
    final result = await queue.collectTo(outbox);

    expect(result.collected, 1);
    expect(result.error, isNull);
    expect(outbox.reports.map((r) => r.reportId), ['a']);
    expect(rows(pending), isEmpty);
    expect(rows(sent).map((r) => r['errorDetails']), ['טעות']);
  });

  test('כשל בסימון — הקובץ נמחק, השורה נשארת, והשגיאה מדווחת', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    db.execute('DROP TABLE lists'); // המונה נכשל באמצע הטרנזקציה
    db.close();

    final outbox = MemoryOutbox(const []);
    final result = await UserStateReportQueue(dbPath).collectTo(outbox);

    expect(result.collected, 0);
    expect(result.error, isNotNull);
    expect(outbox.reports, isEmpty);
    expect(rows(pending), hasLength(1));
    expect(rows(sent), isEmpty);
  });

  test('סכמת מסד חדשה מהמוכרת — לא נוגעים בכלום', () async {
    final db = create(userVersion: UserStateReportQueue.knownSchemaVersion + 1);
    insert(db, pending, _stored('a'));
    db.close();
    final before = File(dbPath).readAsBytesSync();

    final queue = UserStateReportQueue(dbPath);
    expect(await queue.countSendable(), 0);
    expect((await queue.collectTo(MemoryOutbox(const []))).collected, 0);
    expect(rows(pending), hasLength(1));
    expect(File(dbPath).readAsBytesSync(), before);
  });

  test('אין מסד — אין מה להציע, ושום קובץ אינו נוצר', () async {
    expect(await UserStateReportQueue(dbPath).countSendable(), 0);
    expect(File(dbPath).existsSync(), isFalse);
  });

  group('locateUserStateDb', () {
    late String dataRoot;
    setUp(() => dataRoot = p.join(temp.path, 'otzaria'));

    File touch(String path) => File(path)..createSync(recursive: true);

    test('הגדרת תיקיית המסדים מנצחת', () async {
      final custom = p.join(temp.path, 'custom');
      final f = touch(p.join(custom, 'user_state.db'));
      touch(p.join(dataRoot, 'databases', 'user_state.db'));
      expect(
        await locateUserStateDb(
            dataRoot: dataRoot, databasesPathSetting: custom),
        f.path,
      );
    });

    test('בלי הגדרה: <dataRoot>/databases כשהיא קיימת', () async {
      final f = touch(p.join(dataRoot, 'databases', 'user_state.db'));
      touch(p.join(temp.path, 'databases', 'user_state.db'));
      expect(
        await locateUserStateDb(
          dataRoot: dataRoot,
          libraryPathSetting: p.join(temp.path, 'books'),
        ),
        f.path,
      );
    });

    test('אחרת — ליד הספרייה', () async {
      final f = touch(p.join(temp.path, 'databases', 'user_state.db'));
      expect(
        await locateUserStateDb(
          dataRoot: dataRoot,
          libraryPathSetting: p.join(temp.path, 'books'),
        ),
        f.path,
      );
    });

    test('המועדפת כתיבה אבל בלי מסד — אוצריא תיצור שם חדש, אין מה להציע',
        () async {
      final custom = p.join(temp.path, 'custom');
      touch(p.join(dataRoot, 'databases', 'user_state.db'));
      expect(
        await locateUserStateDb(
            dataRoot: dataRoot, databasesPathSetting: custom),
        isNull,
      );
      // הבדיקה אינה יוצרת את התיקייה, ואינה משאירה קובץ בדיקה.
      expect(Directory(custom).existsSync(), isFalse);
      expect(
        temp.listSync().whereType<File>().map((f) => p.basename(f.path)),
        isNot(contains('.otzaria_launcher_write_probe')),
      );
    });

    test('המועדפת אינה כתיבה — הנפילה ל-<dataRoot>/databases', () async {
      final custom = p.join(temp.path, 'custom');
      touch(p.join(custom, 'user_state.db'));
      final f = touch(p.join(dataRoot, 'databases', 'user_state.db'));
      expect(
        await locateUserStateDb(
          dataRoot: dataRoot,
          databasesPathSetting: custom,
          isWritable: (_) async => false,
        ),
        f.path,
      );
    });

    test('שום מסד — null, ושום תיקייה אינה נוצרת', () async {
      expect(await locateUserStateDb(dataRoot: dataRoot), isNull);
      expect(Directory(dataRoot).existsSync(), isFalse);
    });
  });
}

/// תיבה שמשנה את המסד בדיוק בין כתיבת הקובץ לסימון באוצריא.
class _ChangingOutbox extends MemoryOutbox {
  _ChangingOutbox(this.onWrite) : super(const []);

  final void Function() onWrite;

  @override
  Future<void> write(String reportId, Map<String, dynamic> fileJson) async {
    await super.write(reportId, fileJson);
    onWrite();
  }
}

/// תיבה שהכתיבה לדיווח אחד בה נכשלת.
class _FailingOutbox extends MemoryOutbox {
  _FailingOutbox(this.failFor) : super(const []);

  final String failFor;

  @override
  Future<void> write(String reportId, Map<String, dynamic> fileJson) async {
    if (reportId == failFor) throw const FileSystemException('disk full');
    await super.write(reportId, fileJson);
  }
}
