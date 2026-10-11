import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

/// שעון מדומה שההמתנה המוזרקת מקדמת — בלי לחכות בזמן אמת.
class _FakeTime {
  DateTime now = DateTime.utc(2026, 9, 1);
  final waits = <Duration>[];
  Future<void> delay(Duration d) async {
    waits.add(d);
    now = now.add(d);
  }
}

const _ok = '{"success":true}';

List<String> _ids(int n) => [for (var i = 0; i < n; i++) 'r$i'];

void main() {
  late _FakeTime time;
  setUp(() => time = _FakeTime());

  ErrorReportUploader uploader(MockClientHandler handler) =>
      ErrorReportUploader(
        httpClient: MockClient(handler),
        delay: time.delay,
        clock: () => time.now,
      );

  test('שולח את הגוף עם הכותרות, ומוחק על 200 (גם duplicate)', () async {
    final outbox = MemoryOutbox(['a', 'b']);
    final requests = <http.Request>[];
    final result = await uploader((req) async {
      requests.add(req);
      return http.Response(
          jsonEncode({'success': true, 'duplicate': requests.length == 2}),
          200);
    }).upload(outbox);

    expect(result.sent, 2);
    expect(result.remaining, 0);
    expect(outbox.reports, isEmpty);
    final first = requests.first;
    expect(first.method, 'POST');
    expect(first.url.toString(), 'https://otzaria.org/api/reportingerrors');
    expect(first.headers['Content-Type'], 'application/json; charset=utf-8');
    expect(first.headers['Accept'], 'application/json');
    expect(first.headers['User-Agent'], 'otzaria-launcher');
    expect(jsonDecode(first.body), {'id': 'a', 'text': 'טעות'});
  });

  test('product בקובץ מהכונן אינו נשלח (דיווח של אוצריא)', () async {
    final json = reportJson(
      'app1',
      endpoint: 'https://otzaria.org/api/app-reports',
    );
    (json['body'] as Map<String, dynamic>)['product'] = 'offline-update';
    final outbox = MemoryOutbox(const []);
    outbox.add(json, filePath: 'app1.json');
    Map<String, dynamic>? sent;
    await uploader((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(_ok, 200);
    }).upload(outbox);
    expect(sent, isNotNull);
    expect(sent!.containsKey('product'), isFalse);
    expect(sent!['id'], 'app1');
  });

  test('גוף נטען רק לפני הבקשה שלו, אחד בכל פעם', () async {
    final outbox = MemoryOutbox(['a', 'b', 'c']);
    final readsAtRequest = <int>[];
    final result = await uploader((_) async {
      readsAtRequest.add(outbox.bodyReads.length);
      return http.Response('{}', 200);
    }).upload(outbox);
    expect(result.sent, 3);
    expect(readsAtRequest, [1, 2, 3]);
    expect(outbox.bodyReads, ['a', 'b', 'c']);
  });

  test('גוף שאינו נקרא עוצר את הריצה ושומר את הספירה', () async {
    final outbox = MemoryOutbox(['a', 'b']);
    outbox.files.remove('b.json');
    final result =
        await uploader((_) async => http.Response('{}', 200)).upload(outbox);
    expect(result.sent, 1);
    expect(result.remaining, 1);
    expect(result.error, isNotNull);
    expect(outbox.reports.map((r) => r.reportId), ['b']);
  });

  test('דחייה סופית (400/409/413/422) נמחקת ונספרת', () async {
    final outbox = MemoryOutbox(['a', 'b', 'c', 'd', 'e']);
    const codes = [400, 409, 413, 422, 200];
    var i = 0;
    final result = await uploader((_) async => http.Response(_ok, codes[i++]))
        .upload(outbox);
    expect(result.rejected, 4);
    expect(result.sent, 1);
    expect(result.remaining, 0);
    expect(result.rejections.first.reason, startsWith('400'));
    expect(outbox.reports, isEmpty);
  });

  test('דיווחי תוכנה ותוספים נשלחים ליעדם עם הגוף והצרופות', () async {
    final outbox = MemoryOutbox([]);
    const endpoints = [
      OutboxReport.appReportingEndpoint,
      OutboxReport.pluginReportingEndpoint,
    ];
    for (var i = 0; i < endpoints.length; i++) {
      await outbox.write(
          'r$i',
          OutboxReport.encodeFile(OutboxReport.fileJson(
            reportId: 'r$i',
            bookTitle: 'דיווח',
            createdAt: '2026-10-01T10:00:00Z',
            endpoint: endpoints[i],
            body: {
              'reportId': 'r$i',
              'details': 'פירוט',
              if (i == 0)
                'attachments': {
                  'images': [
                    {
                      'fileName': 'צילום.png',
                      'mimeType': 'image/png',
                      'data': 'AQID'
                    }
                  ]
                }
            },
          )));
    }
    final bodies = outbox.reports.map(outbox.bodyOf).toList();
    var calls = 0;
    final result = await uploader((request) async {
      expect(request.url.toString(), endpoints[calls]);
      expect(jsonDecode(utf8.decode(request.bodyBytes)), bodies[calls]);
      calls++;
      return http.Response(_ok, 201);
    }).upload(outbox);
    expect(calls, 2);
    expect(result.sent, 2);
    expect(outbox.reports, isEmpty);
  });

  test('דיווח תוכנה עם תמונות מקבל זמן העלאה ארוך יותר', () async {
    final outbox = MemoryOutbox([]);
    await outbox.write(
        'app',
        OutboxReport.encodeFile(OutboxReport.fileJson(
          reportId: 'app',
          bookTitle: 'תקלה',
          createdAt: '2026-10-01T10:00:00Z',
          endpoint: OutboxReport.appReportingEndpoint,
          body: {
            'attachments': {
              'images': [
                {'data': 'AQID'}
              ]
            }
          },
        )));
    final sender = ErrorReportUploader(
      requestTimeout: const Duration(milliseconds: 1),
      requestTimeoutWithImages: const Duration(seconds: 2),
      httpClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(_ok, 200);
      }),
    );
    addTearDown(sender.close);
    expect((await sender.upload(outbox)).sent, 1);
  });

  Future<MemoryOutbox> dumpOutbox({bool withLog = true}) async {
    final outbox = MemoryOutbox([]);
    await outbox.write(
        'app',
        OutboxReport.fileJson(
          reportId: 'app',
          bookTitle: 'קריסה',
          createdAt: '2026-10-01T10:00:00Z',
          endpoint: OutboxReport.appReportingEndpoint,
          body: {
            'reportId': 'app',
            'attachments': {
              if (withLog) 'errorLog': 'לוג',
              'minidump': {'fileName': 'crash.dmp', 'data': 'AQID'},
            },
          },
        ));
    return outbox;
  }

  test('דיווח תוכנה עם minidump מקבל זמן העלאה ארוך יותר', () async {
    final outbox = await dumpOutbox();
    final sender = ErrorReportUploader(
      requestTimeout: const Duration(milliseconds: 1),
      requestTimeoutWithImages: const Duration(seconds: 2),
      httpClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('{}', 200);
      }),
    );
    addTearDown(sender.close);
    expect((await sender.upload(outbox)).sent, 1);
  });

  for (final (status, response) in [
    (413, 'too large'),
    (422, jsonEncode({'field': 'attachments.minidump'})),
  ]) {
    test('$status על ה-minidump — נשלח שוב בלעדיו, ונספר כנשלח', () async {
      final outbox = await dumpOutbox();
      final bodies = <Map<String, dynamic>>[];
      final result = await uploader((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return bodies.length == 1
            ? http.Response(response, status)
            : http.Response('{}', 201);
      }).upload(outbox);
      expect(bodies, hasLength(2));
      expect(
          (bodies.first['attachments'] as Map).containsKey('minidump'), isTrue);
      expect(bodies.last, {
        'reportId': 'app',
        'attachments': {'errorLog': 'לוג'},
      });
      expect(result.sent, 1);
      expect(result.rejected, 0);
      expect(outbox.reports, isEmpty);
    });
  }

  test('minidump בלבד שנדחה — הגוף נשלח שוב בלי attachments', () async {
    final outbox = await dumpOutbox(withLog: false);
    final bodies = <Map<String, dynamic>>[];
    await uploader((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('', bodies.length == 1 ? 413 : 200);
    }).upload(outbox);
    expect(bodies.last, {'reportId': 'app'});
  });

  test('422 על שדה אחר — נדחה בלי שליחה חוזרת', () async {
    final outbox = await dumpOutbox();
    var calls = 0;
    final result = await uploader((_) async {
      calls++;
      return http.Response(jsonEncode({'field': 'title'}), 422);
    }).upload(outbox);
    expect(calls, 1);
    expect(result.rejected, 1);
    expect(outbox.reports, isEmpty);
  });

  test('גם השליחה בלי ה-minidump נדחית — הקובץ נמחק כנדחה', () async {
    final outbox = await dumpOutbox();
    var calls = 0;
    final result = await uploader((_) async {
      calls++;
      return http.Response('too large', 413);
    }).upload(outbox);
    expect(calls, 2);
    expect(result.rejected, 1);
    expect(result.sent, 0);
    expect(outbox.reports, isEmpty);
  });

  bool hasDump(Map<String, dynamic> body) =>
      (body['attachments'] as Map?)?.containsKey('minidump') ?? false;

  for (final (name, MockClientHandler second) in [
    ('500', (_) async => http.Response('oops', 500)),
    ('שגיאת רשת', (_) async => throw http.ClientException('down')),
  ]) {
    test('$name אחרי שה-minidump נדחה — הקובץ נשמר בלי ה-dump', () async {
      final outbox = await dumpOutbox();
      final bodies = <Map<String, dynamic>>[];
      final first = await uploader((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        if (bodies.length == 1) return http.Response('too large', 413);
        return second(req);
      }).upload(outbox);
      expect(first.error, isNotNull);
      expect(first.remaining, 1);
      expect(bodies, hasLength(2));
      final kept = outbox.reports.single;
      expect(kept.body, {
        'reportId': 'app',
        'attachments': {'errorLog': 'לוג'},
      });
      expect(kept.createdAt, DateTime.utc(2026, 10, 1, 10));
      expect(kept.endpoint.toString(), OutboxReport.appReportingEndpoint);
      expect(kept.bookTitle, 'קריסה');

      final again = <Map<String, dynamic>>[];
      final next = await uploader((req) async {
        again.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{}', 200);
      }).upload(outbox);
      expect(again, hasLength(1));
      expect(hasDump(again.single), isFalse);
      expect(next.sent, 1);
      expect(outbox.reports, isEmpty);
    });
  }

  test('עצירה בהמתנה לפני השליחה בלי ה-minidump — הקובץ נשמר בלעדיו', () async {
    final outbox = await dumpOutbox();
    final cancellation = ReportUploadCancellation();
    final up = ErrorReportUploader(
      httpClient: MockClient((_) async => http.Response('too large', 413)),
      batchSize: 1,
      delay: time.delay,
      clock: () => time.now,
    );
    final result =
        await up.upload(outbox, cancellation: cancellation, onProgress: (p) {
      if (p.isWaiting) cancellation.cancel();
    });
    expect(result.cancelled, isTrue);
    expect(hasDump(outbox.reports.single.body), isFalse);
  });

  test('כשל זמני בלי דחיית minidump — הקובץ נשאר כמו שהוא', () async {
    final outbox = await dumpOutbox();
    final result =
        await uploader((_) async => http.Response('oops', 503)).upload(outbox);
    expect(result.error, isNotNull);
    expect(hasDump(outbox.reports.single.body), isTrue);
  });

  test('בתיבה על הדיסק — אותו קובץ נדרס בלי ה-dump, בלי כפילות', () async {
    final dir = await Directory.systemTemp.createTemp('outbox_dump_');
    addTearDown(() => dir.delete(recursive: true));
    final outbox = DirectoryReportOutbox(dir.path);
    final source = await dumpOutbox();
    final original = source.reports.single;
    await outbox.write(
        'app',
        OutboxReport.fileJson(
          reportId: 'app',
          bookTitle: original.bookTitle,
          createdAt: '2026-10-01T10:00:00Z',
          endpoint: OutboxReport.appReportingEndpoint,
          body: original.body,
        ));
    var calls = 0;
    await uploader((_) async {
      calls++;
      return http.Response('', calls == 1 ? 413 : 502);
    }).upload(outbox);
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final kept = (await outbox.list()).single;
    expect(kept.filePath, files.single.path);
    expect(hasDump(kept.body), isFalse);
    expect(kept.body['attachments'], {'errorLog': 'לוג'});
  });

  test('כתובת שאינה של אוצריא נדחית בלי שליחה', () async {
    final outbox = MemoryOutbox([]);
    outbox.add(reportJson('x', endpoint: 'https://evil.example/api'),
        filePath: 'x');
    var calls = 0;
    final result = await uploader((_) async {
      calls++;
      return http.Response('', 200);
    }).upload(outbox);
    expect(calls, 0);
    expect(result.rejected, 1);
    expect(outbox.reports, isEmpty);
  });

  test('שגיאת שרת עוצרת את הריצה ומשאירה את הקובץ', () async {
    final outbox = MemoryOutbox(['a', 'b', 'c']);
    var i = 0;
    final result =
        await uploader((_) async => http.Response(_ok, i++ == 0 ? 200 : 503))
            .upload(outbox);
    expect(result.sent, 1);
    expect(result.remaining, 2);
    expect(result.error, isNotNull);
    expect(outbox.reports.map((r) => r.reportId), ['b', 'c']);
  });

  test('שגיאת רשת וזמן קצוב נשארים בתיבה', () async {
    final outbox = MemoryOutbox(['a']);
    var result = await uploader((_) => throw http.ClientException('down'))
        .upload(outbox);
    expect(result.error, contains('down'));
    expect(outbox.reports, hasLength(1));

    result = await ErrorReportUploader(
      httpClient: MockClient((_) => Completer<http.Response>().future),
      requestTimeout: const Duration(milliseconds: 10),
    ).upload(outbox);
    expect(result.error, isNotNull);
    expect(outbox.reports, hasLength(1));
  });

  test('מנות של 8, והמתנה של 65 שניות ביניהן', () async {
    final outbox = MemoryOutbox(_ids(20));
    final sentAt = <DateTime>[];
    final progress = <ReportUploadProgress>[];
    final result = await uploader((_) async {
      sentAt.add(time.now);
      return http.Response(_ok, 200);
    }).upload(outbox, onProgress: progress.add);

    expect(result.sent, 20);
    final start = sentAt.first;
    expect(sentAt.where((t) => t == start), hasLength(8));
    expect(sentAt[8].difference(start), const Duration(seconds: 65));
    expect(sentAt[16].difference(start), const Duration(seconds: 130));
    expect(progress.where((p) => p.isWaiting), isNotEmpty);
    expect(time.waits.every((w) => w <= const Duration(seconds: 1)), isTrue);
  });

  test('עצירה באמצע ההמתנה — מיידית, והמשך ממתין לסוף החלון', () async {
    final outbox = MemoryOutbox(_ids(10));
    final cancellation = ReportUploadCancellation();
    final up = uploader((_) async => http.Response(_ok, 200));

    final result =
        await up.upload(outbox, cancellation: cancellation, onProgress: (p) {
      if (p.isWaiting) cancellation.cancel();
    });
    expect(result.cancelled, isTrue);
    expect(result.sent, 8);
    expect(result.remaining, 2);
    expect(outbox.reports, hasLength(2));

    // המשך מיד: החלון עוד מלא, ולכן ממתינים לפני הבקשה הראשונה.
    time.waits.clear();
    final resumed = await up.upload(outbox);
    expect(resumed.sent, 2);
    expect(time.waits, isNotEmpty);
    expect(outbox.reports, isEmpty);
  });

  test('עצירה באמצע בקשה אינה ממתינה לה', () async {
    final outbox = MemoryOutbox(['a']);
    final cancellation = ReportUploadCancellation();
    final pending = Completer<http.Response>();
    final future = uploader((_) => pending.future)
        .upload(outbox, cancellation: cancellation);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    final result = await future;
    expect(result.cancelled, isTrue);
    expect(outbox.reports, hasLength(1));
    pending.complete(http.Response('', 200));
  });

  test('429 → המתנה של חלון שלם ואותו דיווח שוב, ואז ממשיכים', () async {
    final outbox = MemoryOutbox(['a', 'b']);
    final seen = <String>[];
    final sentAt = <DateTime>[];
    var first = true;
    final result = await uploader((req) async {
      seen.add((jsonDecode(req.body) as Map)['id'] as String);
      sentAt.add(time.now);
      if (first) {
        first = false;
        return http.Response('slow down', 429);
      }
      return http.Response(_ok, 200);
    }).upload(outbox);

    expect(result.error, isNull);
    expect(result.sent, 2);
    expect(seen, ['a', 'a', 'b']);
    expect(sentAt[1].difference(sentAt[0]), const Duration(seconds: 65));
  });

  test('429 שחוזר שוב ושוב עוצר אחרי מספר ניסיונות סביר', () async {
    final outbox = MemoryOutbox(['a']);
    var calls = 0;
    final result = await uploader((_) async {
      calls++;
      return http.Response('', 429);
    }).upload(outbox);
    expect(calls, 4); // הניסיון הראשון ועוד שלושה
    expect(result.error, isNotNull);
    expect(outbox.reports, hasLength(1));
  });

  test('החלון הבא נמדד מסוף הבקשה האחרונה במנה, לא מתחילתה', () async {
    final outbox = MemoryOutbox(_ids(9));
    final sentAt = <DateTime>[];
    final result = await uploader((_) async {
      sentAt.add(time.now);
      // כל בקשה "אורכת" 2 שניות לפי השעון המדומה.
      time.now = time.now.add(const Duration(seconds: 2));
      return http.Response(_ok, 200);
    }).upload(outbox);
    expect(result.sent, 9);
    final lastEnd = sentAt[7].add(const Duration(seconds: 2));
    expect(sentAt[8].difference(lastEnd), const Duration(seconds: 65));
  });

  test('כתובת אסורה אינה ממתינה לחלון', () async {
    final outbox = MemoryOutbox(_ids(8));
    outbox.add(reportJson('x', endpoint: 'http://otzaria.org/api'),
        filePath: 'x');
    final result =
        await uploader((_) async => http.Response(_ok, 200)).upload(outbox);
    expect(result.sent, 8);
    expect(result.rejected, 1);
    expect(time.waits, isEmpty);
  });

  test('מאזיני העצירה אינם מצטברים לאורך ריצה', () async {
    final outbox = MemoryOutbox(_ids(20));
    final cancellation = ReportUploadCancellation();
    await uploader((_) async => http.Response(_ok, 200))
        .upload(outbox, cancellation: cancellation);
    expect(cancellation.listenerCount, 0);
  });

  test('הערכת זמן', () {
    final up = ErrorReportUploader(httpClient: MockClient((_) async {
      return http.Response('', 200);
    }));
    expect(up.estimateMinutes(8), 1);
    expect(up.estimateMinutes(9), 2);
    expect(up.estimateMinutes(40), 5);
  });

  for (final body in ['<html>blocked</html>', '{}', '{"success":false}']) {
    test('2xx בלי תשובת פרוטוקול ($body) אינו מוחק את הקובץ', () async {
      final outbox = MemoryOutbox(['a', 'b']);
      var calls = 0;
      final result = await uploader((_) async {
        calls++;
        return http.Response(body, 200);
      }).upload(outbox);
      expect(calls, 1);
      expect(result.sent, 0);
      expect(result.remaining, 2);
      expect(result.error, isNotNull);
      expect(outbox.reports.map((r) => r.reportId), ['a', 'b']);
    });
  }

  test('עצירה באמצע בקשה מבטלת אותה ברשת', () async {
    final outbox = MemoryOutbox(['a']);
    final cancellation = ReportUploadCancellation();
    final started = Completer<void>();
    var aborted = false;
    final up = ErrorReportUploader(
      httpClient: MockClient.streaming((request, body) async {
        await body.drain<void>();
        started.complete();
        await (request as http.Abortable).abortTrigger;
        aborted = true;
        throw http.RequestAbortedException(request.url);
      }),
      delay: time.delay,
      clock: () => time.now,
    );
    final future = up.upload(outbox, cancellation: cancellation);
    await started.future;
    cancellation.cancel();
    final result = await future;
    await Future<void>.delayed(Duration.zero);
    expect(result.cancelled, isTrue);
    expect(aborted, isTrue);
    expect(outbox.reports, hasLength(1));
  });

  test('בקשה שחרגה מהזמן מבוטלת ברשת', () async {
    final outbox = MemoryOutbox(['a']);
    final aborted = Completer<void>();
    final result = await ErrorReportUploader(
      httpClient: MockClient.streaming((request, body) async {
        await body.drain<void>();
        await (request as http.Abortable).abortTrigger;
        aborted.complete();
        throw http.RequestAbortedException(request.url);
      }),
      requestTimeout: const Duration(milliseconds: 10),
    ).upload(outbox);
    expect(result.error, isNotNull);
    expect(outbox.reports, hasLength(1));
    await aborted.future.timeout(const Duration(seconds: 5));
  });
}
