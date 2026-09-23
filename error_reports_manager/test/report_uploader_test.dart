import 'dart:async';
import 'dart:convert';

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
          jsonEncode({'ok': true, 'duplicate': requests.length == 2}), 200);
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

  test('דחייה סופית (400/409/413/422) נמחקת ונספרת', () async {
    final outbox = MemoryOutbox(['a', 'b', 'c', 'd', 'e']);
    const codes = [400, 409, 413, 422, 200];
    var i = 0;
    final result = await uploader((_) async => http.Response('bad', codes[i++]))
        .upload(outbox);
    expect(result.rejected, 4);
    expect(result.sent, 1);
    expect(result.remaining, 0);
    expect(result.rejections.first.reason, startsWith('400'));
    expect(outbox.reports, isEmpty);
  });

  test('כתובת שאינה של אוצריא נדחית בלי שליחה', () async {
    final outbox = MemoryOutbox([]);
    outbox.reports.add(OutboxReport.fromJson(
        reportJson('x', endpoint: 'https://evil.example/api'),
        filePath: 'x'));
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
        await uploader((_) async => http.Response('', i++ == 0 ? 200 : 503))
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
      return http.Response('{}', 200);
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
    final up = uploader((_) async => http.Response('{}', 200));

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
      return http.Response('{}', 200);
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
      return http.Response('{}', 200);
    }).upload(outbox);
    expect(result.sent, 9);
    final lastEnd = sentAt[7].add(const Duration(seconds: 2));
    expect(sentAt[8].difference(lastEnd), const Duration(seconds: 65));
  });

  test('כתובת אסורה אינה ממתינה לחלון', () async {
    final outbox = MemoryOutbox(_ids(8));
    outbox.reports.add(OutboxReport.fromJson(
        reportJson('x', endpoint: 'http://otzaria.org/api'),
        filePath: 'x'));
    final result =
        await uploader((_) async => http.Response('{}', 200)).upload(outbox);
    expect(result.sent, 8);
    expect(result.rejected, 1);
    expect(time.waits, isEmpty);
  });

  test('מאזיני העצירה אינם מצטברים לאורך ריצה', () async {
    final outbox = MemoryOutbox(_ids(20));
    final cancellation = ReportUploadCancellation();
    await uploader((_) async => http.Response('{}', 200))
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
}
