import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

void _createOtzariaSchema(Database db, {int userVersion = 2}) {
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
  if (userVersion < 2) return;
  // Same separate local tables as Otzaria's ReportDraftStore.
  db.execute('''CREATE TABLE report_drafts (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
    payload_json TEXT NOT NULL, created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL, revision INTEGER NOT NULL
  )''');
  db.execute('''CREATE TABLE report_draft_attachments (
    draft_id TEXT PRIMARY KEY REFERENCES report_drafts(id) ON DELETE CASCADE,
    payload_json TEXT NOT NULL
  )''');
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

  Database create({int userVersion = 2}) {
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

  test(
      'local drafts and their attachments are never collected, explicit queued reports are',
      () async {
    final fixture = jsonDecode(
            File('test/fixtures/app_report_schema2.json').readAsStringSync())
        as Map;
    final app = Map<String, dynamic>.from(fixture['stored'] as Map);
    final book = _stored('book-draft');
    final db = create();
    for (final (id, kind, payload) in [
      ('app-draft', 'app', app),
      ('book-draft', 'book', book),
    ]) {
      db.execute('INSERT INTO report_drafts VALUES (?,?,?,?,0,0,1)',
          [id, kind, 'unfinished', jsonEncode(payload)]);
      db.execute('INSERT INTO report_draft_attachments VALUES (?,?)', [
        id,
        jsonEncode({'images': app['images'], 'localOnly': 'draft-secret'})
      ]);
    }
    // A fully valid legacy draft must also remain local, even though its old
    // storage uses pending_reports with a different kind.
    insert(db, 'app_reports_queue/draft', app);
    insert(db, pending, _stored('old-pending'));
    insert(db, pending, _stored('explicitly-queued'));
    insert(db, UserStateReportQueue.appPendingKindV2, app);
    final draftRows = db
        .select('SELECT * FROM report_drafts ORDER BY id')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final attachmentRows = db
        .select('SELECT * FROM report_draft_attachments ORDER BY draft_id')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    db.close();

    final outbox = MemoryOutbox(const []);
    final queue = UserStateReportQueue(dbPath, reportsQueueFormat: 2);
    expect(await queue.countSendable(), 3);
    expect((await queue.collectTo(outbox)).collected, 3);
    expect(outbox.reports.map((r) => r.reportId),
        ['old-pending', 'explicitly-queued', 'app-${app['reportId']}']);
    expect(outbox.bodyOf(outbox.reports.last), fixture['payload']);
    for (final report in outbox.reports) {
      expect(
          jsonEncode(outbox.bodyOf(report)), isNot(contains('draft-secret')));
    }
    expect(rows('app_reports_queue/draft'), [app]);
    final after = sqlite3.open(dbPath);
    try {
      expect(
          after
              .select('SELECT * FROM report_drafts ORDER BY id')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          draftRows);
      expect(
          after
              .select(
                  'SELECT * FROM report_draft_attachments ORDER BY draft_id')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
          attachmentRows);
    } finally {
      after.close();
    }
  });

  for (final userVersion in [1, 2]) {
    for (final queueFormat in <int?>[null, 1, 2]) {
      test('DB $userVersion, queue format $queueFormat preserves both schemas',
          () async {
        final fixture = jsonDecode(File('test/fixtures/app_report_schema2.json')
            .readAsStringSync()) as Map;
        final schema2 = Map<String, dynamic>.from(fixture['stored'] as Map);
        final schema1 = {...schema2, 'reportId': 'legacy'}..remove('schema');
        final db = create(userVersion: userVersion);
        insert(db, UserStateReportQueue.appPendingKind, schema1);
        insert(db, UserStateReportQueue.appPendingKindV2, schema2);
        db.close();
        final outbox = MemoryOutbox(const []);
        final queue =
            UserStateReportQueue(dbPath, reportsQueueFormat: queueFormat);
        expect((await queue.collectTo(outbox)).collected, 2);
        expect(outbox.bodyOf(outbox.reports[0])['schema'], 1);
        expect(outbox.bodyOf(outbox.reports[1])['schema'], 2);
        expect(rows(UserStateReportQueue.appPendingKind), isEmpty);
        expect(rows(UserStateReportQueue.appPendingKindV2), isEmpty);
        expect(rows('app_reports_queue/sent_reports').length, 2);
      });
    }
  }

  test(
      '20 MiB payload survives real queue and outbox; an excess byte stays pending',
      () async {
    const limit = 10 * 1024 * 1024;
    final fixture = jsonDecode(
            File('test/fixtures/app_report_schema2.json').readAsStringSync())
        as Map;
    final data = base64Encode(Uint8List(limit));
    final stored = {
      ...Map<String, dynamic>.from(fixture['stored'] as Map),
      'images': [
        {'fileName': 'first.gif', 'mimeType': 'image/gif', 'data': data},
        {'fileName': 'second.gif', 'mimeType': 'image/gif', 'data': data},
      ],
    }
      ..remove('diagnostics')
      ..remove('errorLog')
      ..remove('minidump');
    final db = create();
    insert(db, UserStateReportQueue.appPendingKindV2, stored);
    insert(db, UserStateReportQueue.appPendingKindV2,
        {...stored, 'reportId': 'excess', 'errorLog': 'x'});
    db.close();
    final queue = UserStateReportQueue(dbPath, reportsQueueFormat: 2);
    expect(await queue.countSendable(), 1);
    final outbox = MemoryOutbox(const []);
    expect((await queue.collectTo(outbox)).collected, 1);
    final payload = outbox.bodyOf(outbox.reports.single);
    expect(payload['schema'], 2);
    expect(
        ((payload['attachments'] as Map)['images'] as List)
            .map((i) => base64Decode(i['data'] as String).length),
        [limit, limit]);
    expect(rows(UserStateReportQueue.appPendingKindV2).single['reportId'],
        'excess');
  });

  test('כל עבודת ה-SQLite עוברת ב-isolate, ובאיסוף שורה אחת בכל פעם', () async {
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
    expect(calls, 4);
  });

  test('כשל של שלב הסימון כולו — כל הקבצים נמחקים, והשורות נשארות', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    insert(db, pending, _stored('b'));
    db.close();

    var calls = 0;
    Future<R> failMark<R>(FutureOr<R> Function() computation) {
      if (++calls == 4) return Future.error(StateError('database is locked'));
      return Isolate.run(computation);
    }

    final outbox = MemoryOutbox(const []);
    final queue = UserStateReportQueue(dbPath, runIsolated: failMark);
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
    expect(result.error, isNull);
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
      if (++calls == 3) File(dbPath).deleteSync();
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
    expect(outbox.bodyOf(a)['report_id'], 'a');
    expect(outbox.bodyOf(a)['schema_version'], 2);

    expect(rows(pending).map((r) => r['id']), ['newer']);
    expect(rows(sent).map((r) => r['id']), ['old', 'a', 'b']);
    expect(counter(), 3);
  });

  test('שלושת התורים נאספים ליעדיהם עם מונים והיסטוריה נפרדים', () async {
    final db = create();
    insert(db, pending, _stored('same'));
    insert(db, UserStateReportQueue.appPendingKind, {
      'reportId': 'same',
      'type': 'bug',
      'trigger': 'manual',
      'title': 'תקלה בתוכנה',
      'description': 'פירוט התקלה',
      'reporterEmail': 'a@b.co',
      'appVersion': '1.0',
      'platform': 'windows',
      'createdAt': '2026-09-01T10:00:00.000Z',
      'diagnostics': {'version': '1.0'},
      'errorLog': 'לוג',
      'product': AppReport.offlineUpdateProduct,
      'images': [
        {'fileName': 'צילום.png', 'mimeType': 'image/png', 'data': 'AQID'}
      ],
    });
    insert(db, UserStateReportQueue.pluginPendingKind, {
      'reportId': 'same',
      'pluginUid': 'plugin-uid',
      'pluginName': 'תוסף',
      'pluginVersion': '2.0',
      'reportType': 'bug',
      'details': 'תקלה בתוסף',
      'platform': 'windows',
      'createdAt': '2026-09-01T10:00:00.000Z',
    });
    db.close();

    final queue = UserStateReportQueue(dbPath);
    expect(await queue.countSendable(), 3);
    final outbox = MemoryOutbox(const []);
    expect((await queue.collectTo(outbox)).collected, 3);
    expect(outbox.reports.map((r) => r.reportId),
        ['same', 'app-same', 'plugin-same']);
    expect(outbox.reports.map((r) => r.endpoint.toString()), [
      OutboxReport.reportingEndpoint,
      OutboxReport.appReportingEndpoint,
      OutboxReport.pluginReportingEndpoint,
    ]);
    final app = outbox.bodyOf(outbox.reports[1]);
    expect(app['reportId'], 'same');
    expect(app.containsKey('product'), isFalse);
    expect((app['attachments'] as Map)['images'], [
      {'fileName': 'צילום.png', 'mimeType': 'image/png', 'data': 'AQID'}
    ]);
    expect((app['attachments'] as Map)['errorLog'], 'לוג');
    expect(outbox.bodyOf(outbox.reports[2]), {
      'reportId': 'same',
      'pluginUid': 'plugin-uid',
      'pluginName': 'תוסף',
      'pluginVersion': '2.0',
      'reportType': 'bug',
      'details': 'תקלה בתוסף',
      'platform': 'windows',
    });
    for (final box in [
      'error_reports_queue',
      'app_reports_queue',
      'plugin_reports_queue'
    ]) {
      expect(rows('$box/pending_reports'), isEmpty);
      final history = rows('$box/sent_reports').single;
      expect(history['carriedBy'], UserStateReportQueue.carriedBy);
      expect(DateTime.tryParse(history['carriedAt'] as String), isNotNull);
      if (box == 'app_reports_queue') {
        expect(history.containsKey('images'), isFalse);
        expect(history.containsKey('diagnostics'), isFalse);
        expect(history.containsKey('errorLog'), isFalse);
        expect(history['sentAt'], isNotNull);
      }
      final check = sqlite3.open(dbPath);
      try {
        expect(
            jsonDecode(check.select(
              'SELECT payload_json FROM lists WHERE box = ? AND key = ?',
              [box, 'sent_reports_total'],
            ).single['payload_json'] as String),
            [1]);
      } finally {
        check.close();
      }
    }
  });

  test('minidump שהמשתמש הסכים לו עובר לתיבה, ולא להיסטוריה', () async {
    final dump = base64Encode(
        List<int>.filled(AppReportMinidump.maxRawBytes, 0x41, growable: false));
    final db = create();
    insert(db, UserStateReportQueue.appPendingKind, {
      'reportId': 'crash',
      'type': 'crash',
      'trigger': 'crash_prompt',
      'title': 'קריסה',
      'appVersion': '1.0',
      'platform': 'windows',
      'createdAt': '2026-09-01T10:00:00.000Z',
      'errorLog': 'לוג',
      'minidump': {'fileName': 'crash.dmp', 'data': dump},
    });
    db.close();

    final queue = UserStateReportQueue(dbPath);
    expect(await queue.countSendable(), 1);
    final outbox = MemoryOutbox(const []);
    expect((await queue.collectTo(outbox)).collected, 1);
    final attachments =
        outbox.bodyOf(outbox.reports.single)['attachments'] as Map;
    expect(attachments['minidump'], {'fileName': 'crash.dmp', 'data': dump});
    expect(attachments['errorLog'], 'לוג');

    expect(rows(UserStateReportQueue.appPendingKind), isEmpty);
    final history = rows('app_reports_queue/sent_reports').single;
    expect(history.containsKey('minidump'), isFalse);
    expect(history.containsKey('errorLog'), isFalse);
    expect(history['reportId'], 'crash');
  });

  test('דיווחי תוכנה ותוספים פגומים נשארים בתור', () async {
    final db = create();
    insert(db, UserStateReportQueue.appPendingKind,
        {'reportId': 'app', 'title': 'תקלה'});
    insert(db, UserStateReportQueue.pluginPendingKind,
        {'reportId': 'plugin', 'details': 'תקלה בלי מזהה תוסף'});
    db.close();
    final queue = UserStateReportQueue(dbPath);
    expect(await queue.countSendable(), 0);
    expect((await queue.collectTo(MemoryOutbox(const []))).collected, 0);
    expect(rows(UserStateReportQueue.appPendingKind), hasLength(1));
    expect(rows(UserStateReportQueue.pluginPendingKind), hasLength(1));
  });

  for (final kind in ['app', 'plugin']) {
    Map<String, dynamic> stored() {
      final golden = jsonDecode(File('test/fixtures/other_reports_golden.json')
          .readAsStringSync()) as Map;
      final c = (golden['cases'] as List)
          .cast<Map>()
          .firstWhere((c) => c['kind'] == kind);
      return Map<String, dynamic>.from(c['stored'] as Map);
    }

    final pendingKind = '${kind}_reports_queue/pending_reports';
    final sentKind = '${kind}_reports_queue/sent_reports';

    test('$kind: עותק כפול נאסף פעם אחת בלי לאבד את הקובץ', () async {
      final db = create();
      insert(db, pendingKind, stored());
      insert(db, pendingKind, stored());
      db.close();
      final queue = UserStateReportQueue(dbPath);
      expect(await queue.countSendable(), 1);
      final outbox = MemoryOutbox(const []);
      expect((await queue.collectTo(outbox)).collected, 1);
      expect(outbox.reports, hasLength(1));
      expect(rows(pendingKind), isEmpty);
      expect(rows(sentKind), hasLength(1));
    });

    test('$kind: כשל בסימון משאיר את התור המקורי בלי קובץ לשליחה', () async {
      final db = create();
      insert(db, pendingKind, stored());
      db.execute('DROP TABLE lists');
      db.close();
      final outbox = MemoryOutbox(const []);
      final result = await UserStateReportQueue(dbPath).collectTo(outbox);
      expect(result.collected, 0);
      expect(result.error, isNotNull);
      expect(outbox.reports, isEmpty);
      expect(rows(pendingKind), hasLength(1));
      expect(rows(sentKind), isEmpty);
    });

    test('$kind: דיווח שנערך לפני הסימון נשאר בתור', () async {
      final db = create();
      insert(db, pendingKind, stored());
      db.close();
      final outbox = _ChangingOutbox(() {
        final other = sqlite3.open(dbPath);
        try {
          other.execute('UPDATE pending_reports SET payload_json = ?', [
            jsonEncode({...stored(), 'reportId': 'edited'})
          ]);
        } finally {
          other.close();
        }
      });
      expect(
          (await UserStateReportQueue(dbPath).collectTo(outbox)).collected, 0);
      expect(outbox.reports, isEmpty);
      expect(rows(pendingKind).single['reportId'], 'edited');
      expect(rows(sentKind), isEmpty);
    });
  }

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
    db.execute('DROP TABLE lists');
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

  group('פורמט התור מ-otzaria_capabilities.json (C3)', () {
    test('פורמט 1 עם user_version לא מוכר — לא נוגעים בכלום', () async {
      final db =
          create(userVersion: UserStateReportQueue.knownSchemaVersion + 1);
      insert(db, pending, _stored('a'));
      db.close();
      final before = File(dbPath).readAsBytesSync();

      final queue = UserStateReportQueue(dbPath, reportsQueueFormat: 1);
      expect(await queue.countSendable(), 0);
      expect((await queue.collectTo(MemoryOutbox(const []))).collected, 0);
      expect(File(dbPath).readAsBytesSync(), before);
    });

    test('פורמט 1 עם user_version מוכר — נאסף', () async {
      final db = create();
      insert(db, pending, _stored('a'));
      db.close();

      final queue = UserStateReportQueue(dbPath, reportsQueueFormat: 1);
      expect(await queue.countSendable(), 1);
      expect((await queue.collectTo(MemoryOutbox(const []))).collected, 1);
    });

    test('פורמט לא מוכר — לא נוגעים בכלום, גם ב-user_version מוכר', () async {
      final db = create();
      insert(db, pending, _stored('a'));
      db.close();
      final before = File(dbPath).readAsBytesSync();

      final queue = UserStateReportQueue(dbPath, reportsQueueFormat: 3);
      expect(await queue.countSendable(), 0);
      expect((await queue.collectTo(MemoryOutbox(const []))).collected, 0);
      expect(File(dbPath).readAsBytesSync(), before);
    });
  });

  test('שורה שהשתנתה בין הקריאה לכתיבת הקובץ — אינה נכתבת', () async {
    final db = create();
    insert(db, pending, _stored('a'));
    db.close();

    var calls = 0;
    Future<R> editBeforeEncode<R>(FutureOr<R> Function() computation) {
      if (++calls == 2) {
        final other = sqlite3.open(dbPath);
        other.execute(
          'UPDATE pending_reports SET payload_json = ? WHERE id = 1',
          [
            jsonEncode(_stored('a', extra: {'errorDetails': 'נערך'}))
          ],
        );
        other.close();
      }
      return Isolate.run(computation);
    }

    final outbox = MemoryOutbox(const []);
    final result =
        await UserStateReportQueue(dbPath, runIsolated: editBeforeEncode)
            .collectTo(outbox);
    expect(result.collected, 0);
    expect(outbox.reports, isEmpty);
    expect(rows(pending), hasLength(1));
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

    test('מאתר באותה תיקייה גם מסד אחר של אוצריא לפי שם', () async {
      final custom = p.join(temp.path, 'custom');
      final f = touch(p.join(custom, 'plugins_host.db'));
      touch(p.join(custom, 'user_state.db'));
      expect(
        await locateUserStateDb(
          dataRoot: dataRoot,
          databasesPathSetting: custom,
          fileName: 'plugins_host.db',
        ),
        f.path,
      );
      expect(
        await locateUserStateDb(
          dataRoot: dataRoot,
          fileName: 'plugins_host.db',
        ),
        isNull,
      );
    });
  });
}

class _ChangingOutbox extends MemoryOutbox {
  _ChangingOutbox(this.onWrite) : super(const []);

  final void Function() onWrite;

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {
    await super.write(reportId, fileBytes);
    onWrite();
  }
}

class _FailingOutbox extends MemoryOutbox {
  _FailingOutbox(this.failFor) : super(const []);

  final String failFor;

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {
    if (reportId == failFor) throw const FileSystemException('disk full');
    await super.write(reportId, fileBytes);
  }
}
