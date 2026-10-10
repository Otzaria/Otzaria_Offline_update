import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// פורט של `test/app_report/app_report_service_test.dart` באוצריא, בלי מה
// שלא הועבר (minidump, מצב לא-מקוון, סימון כנשלח, עריכה) — ועם `product`.

AppReport _report({String? id, String title = 'באג'}) => AppReport(
      reportId: id ?? AppReport.generateReportId(),
      type: AppReportType.bug,
      trigger: AppReportTrigger.manual,
      title: title,
      description: 'תיאור',
      reporterEmail: 'a@b.com',
      appVersion: '0.25',
      platform: 'windows',
      createdAt: DateTime.utc(2026, 9, 17),
      diagnostics: const {'x': 1},
      errorLog: 'log',
    );

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  late Directory tmp;
  final services = <AppReportService>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('launcher_app_reports_');
  });

  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    // שליחה שהתחילה ברקע (`unawaited(flush)`) מסתיימת לפני המחיקה.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    tmp.deleteSync(recursive: true);
  });

  AppReportService build(MockClient client) {
    final service = AppReportService(
      directory: AppReportService.dirIn(tmp.path),
      client: client,
    );
    services.add(service);
    return service;
  }

  test('התור וההיסטוריה ב-reports/launcher, לא תחת mirror', () {
    expect(
      p.split(p.relative(AppReportService.dirIn(tmp.path), from: tmp.path)),
      ['reports', 'launcher'],
    );
  });

  test('200: נשלח עם product, שדות ה-issue נשמרים בהיסטוריה בלי צרופות',
      () async {
    Map<String, dynamic>? sentBody;
    final service = build(
      MockClient((request) async {
        expect(request.url, AppReportService.endpoint);
        sentBody =
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
        return _json(200, {
          'success': true,
          'issueNumber': 55,
          'issueUrl': 'https://github.com/Otzaria/Otzaria_Offline_update/'
              'issues/55',
          'duplicate': false,
          'merged': true,
          'issuePending': false,
        });
      }),
    );
    final report = _report();
    final result = await service.send(report);

    expect(result.isSent, isTrue);
    expect(result.issueNumber, 55);
    expect(result.merged, isTrue);
    expect(sentBody!['product'], 'offline-update');
    expect(sentBody!['schema'], 1);
    expect(sentBody!['reportId'], report.reportId);
    expect(sentBody!['attachments'], {
      'diagnostics': {'x': 1},
      'errorLog': 'log',
    });

    final sent = await service.getSentReports();
    expect(sent, hasLength(1));
    expect(sent.single.issueUrl, contains('/55'));
    expect(sent.single.diagnostics, isNull);
    expect(sent.single.errorLog, isNull);
    expect(sent.single.sentAt, isNotNull);
    expect(await service.getPendingReportsCount(), 0);
    expect(await service.getSentReportsTotal(), 1);
  });

  test('200 עם issuePending נחשב נשלח ולא נכנס לתור', () async {
    final service = build(
      MockClient(
        (_) async => _json(200, {
          'success': true,
          'issueNumber': null,
          'issueUrl': null,
          'issuePending': true,
        }),
      ),
    );
    final result = await service.send(_report());
    expect(result.isSent, isTrue);
    expect(result.issuePending, isTrue);
    expect(result.issueNumber, isNull);
    expect(await service.getPendingReportsCount(), 0);
  });

  test('409: מזהה חדש וניסיון חוזר', () async {
    final ids = <String>[];
    final service = build(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        ids.add(body['reportId'] as String);
        if (ids.length == 1) return _json(409, {'error': 'reportId conflict'});
        return _json(200, {'success': true, 'issueNumber': 1});
      }),
    );
    final report = _report();
    final result = await service.send(report);
    expect(ids, hasLength(2));
    expect(ids.first, report.reportId);
    expect(ids.last, isNot(report.reportId));
    expect(result.isSent, isTrue);
    expect(result.report.reportId, ids.last);
    expect((await service.getSentReports()).single.reportId, ids.last);
  });

  test('409 פעמיים: כשל idConflict, לא נכנס לתור', () async {
    final service = build(MockClient((_) async => _json(409, {})));
    final result = await service.send(_report());
    expect(result.isFailed, isTrue);
    expect(result.failureReason, AppReportFailureReason.idConflict);
    expect(await service.getPendingReportsCount(), 0);
  });

  test('422: דחייה קבועה, לא נכנס לתור', () async {
    final service = build(
      MockClient(
        (_) async => _json(422, {'error': 'invalid', 'field': 'reporterEmail'}),
      ),
    );
    final result = await service.send(_report());
    expect(result.isFailed, isTrue);
    expect(result.failureReason, AppReportFailureReason.rejected);
    expect(result.rejectedField, 'reporterEmail');
    expect(result.httpStatus, 422);
    expect(await service.getPendingReportsCount(), 0);
  });

  for (final status in [400, 413]) {
    test('$status: דחייה קבועה', () async {
      final service = build(MockClient((_) async => _json(status, {})));
      final result = await service.send(_report());
      expect(result.failureReason, AppReportFailureReason.rejected);
      expect(await service.getPendingReportsCount(), 0);
    });
  }

  for (final status in [429, 500, 503]) {
    test('$status נשמר בתור עם הצרופות', () async {
      final service = build(MockClient((_) async => http.Response('', status)));
      final result = await service.send(_report());
      expect(result.isQueued, isTrue);
      expect(result.httpStatus, status);
      expect(await service.getPendingReportsCount(), 1);
      // הרשימה בלי צרופות; הקובץ שומר אותן לשליחה חוזרת.
      expect((await service.getPendingReports()).single.errorLog, isNull);
      final file = Directory(
        p.join(AppReportService.dirIn(tmp.path), 'pending'),
      ).listSync().whereType<File>().single;
      expect(file.readAsStringSync(), contains('"errorLog":"log"'));
    });
  }

  test('timeout ושגיאת רשת נשמרים בתור', () async {
    final slow = build(
      MockClient((_) async => throw TimeoutException('slow')),
    );
    expect((await slow.send(_report())).isQueued, isTrue);
    final offline = build(
      MockClient((_) async => throw const SocketException('no network')),
    );
    expect((await offline.send(_report())).isQueued, isTrue);
    expect(await offline.getPendingReportsCount(), 2);
  });

  test('flush: שולח, מסיר נדחים, מחליף מזהה ב-409 ועוצר בכשל זמני', () async {
    final a = _report(title: 'a');
    final rejected = _report(title: 'rejected');
    final conflict = _report(title: 'conflict');
    final transient = _report(title: 'transient');
    final after = _report(title: 'after');

    final seen = <String>[];
    final service = build(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['product'], 'offline-update');
        final title = body['title'] as String;
        seen.add(title);
        return switch (title) {
          'a' => _json(200, {'success': true, 'issueNumber': 9}),
          'rejected' => _json(400, {'error': 'bad'}),
          'conflict' => _json(409, {'error': 'reportId conflict'}),
          'transient' => http.Response('', 503),
          _ => _json(200, {'success': true}),
        };
      }),
    );
    for (final r in [a, rejected, conflict, transient, after]) {
      await service.queueReport(r);
    }

    final sentCount = await service.flushPendingReports();
    expect(sentCount, 1);
    expect(seen, ['a', 'rejected', 'conflict', 'transient']);

    final pending = await service.getPendingReports();
    expect(pending.map((r) => r.title), ['conflict', 'transient', 'after']);
    expect(pending.first.reportId, isNot(conflict.reportId));
    expect((await service.getSentReports()).single.issueNumber, 9);
  });

  test('flush מסיר כפילות pending שכבר קיימת בהיסטוריה בלי לשלוח', () async {
    var requests = 0;
    final report = _report();
    final online = build(MockClient((_) async => _json(200, {})));
    expect((await online.send(report)).isSent, isTrue);

    final service = build(
      MockClient((_) async {
        requests++;
        return http.Response('', 503);
      }),
    );
    // כאילו נשאר בתור מהרצה שנקטעה אחרי השליחה.
    final file = File(
      p.join(AppReportService.dirIn(tmp.path), 'pending',
          '0000000000000000001.${report.reportId}.json'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'queuedAt': 1, 'report': report.toJson()}),
    );

    expect(await service.flushPendingReports(), 0);
    expect(requests, 0);
    expect(await service.getPendingReportsCount(), 0);
    expect((await service.getSentReports()).single.reportId, report.reportId);
  });

  test('queueReport פעמיים — רשומה אחת', () async {
    final service = build(MockClient((_) async => http.Response('', 503)));
    final report = _report();
    await service.queueReport(report);
    await service.queueReport(report);
    expect(await service.getPendingReportsCount(), 1);
  });

  test('send חוזר על דיווח שנשלח אינו פונה שוב לשרת', () async {
    var requests = 0;
    final service = build(
      MockClient((_) async {
        requests++;
        return _json(200, {'issueNumber': 3});
      }),
    );
    final report = _report();
    await service.send(report);
    final again = await service.send(report);
    expect(requests, 1);
    expect(again.isSent, isTrue);
    expect(again.issueNumber, 3);
    expect(await service.getSentReportsTotal(), 1);
  });

  test('ההיסטוריה נחתכת ל-100, והמונה סופר את כולם', () async {
    final service = build(MockClient((_) async => _json(200, {})));
    for (var i = 0; i < AppReportService.maxSentReportsToKeep + 3; i++) {
      await service.send(_report(title: 'r$i'));
    }
    final sent = await service.getSentReports();
    expect(sent, hasLength(AppReportService.maxSentReportsToKeep));
    expect(sent.first.title, 'r102');
    expect(sent.last.title, 'r3');
    expect(await service.getSentReportsTotal(), 103);

    await service.deleteSentReport(sent.first.reportId);
    expect(await service.getSentReports(), hasLength(99));
    expect(await service.getSentReportsTotal(), 103);
    await service.clearSentReports();
    expect(await service.getSentReports(), isEmpty);
    expect(await service.getSentReportsTotal(), 0);
  });

  test('שליחות מקבילות של דיווחים שונים אינן דורסות זו את ההיסטוריה', () async {
    final service = build(MockClient((_) async => _json(200, {})));
    await Future.wait([for (var i = 0; i < 10; i++) service.send(_report())]);
    expect(await service.getSentReports(), hasLength(10));
    expect(await service.getSentReportsTotal(), 10);
  });

  test('מחיקה מהתור ממתינה לשליחה שבאמצע (נעילה לפי מזהה)', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final service = build(
      MockClient((_) {
        started.complete();
        return response.future;
      }),
    );
    final report = _report();
    await service.queueReport(report);

    final submission = service.submitPendingReport(report);
    await started.future;
    var deleted = false;
    final deleting = service.deletePendingReport(report.reportId).then((_) {
      deleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(deleted, isFalse);

    response.complete(http.Response('', 503));
    expect((await submission).isQueued, isTrue);
    await deleting;
    expect(await service.getPendingReportsCount(), 0);
  });

  test('clearPendingReports וקובץ פגום שמועבר הצידה', () async {
    final service = build(MockClient((_) async => http.Response('', 503)));
    await service.queueReport(_report());
    final bad = File(
      p.join(
        AppReportService.dirIn(tmp.path),
        'pending',
        '0000000000000000001.broken.json',
      ),
    )..writeAsStringSync('{not json');

    expect(await service.getPendingReportsCount(), 2);
    expect(await service.getPendingReports(), hasLength(1));
    expect(bad.existsSync(), isFalse);
    expect(File('${bad.path}.bad').existsSync(), isTrue);

    await service.clearPendingReports();
    expect(await service.getPendingReportsCount(), 0);
  });

  test('צילומי מסך: נשלחים, נשמרים בתור בכשל, ונמחקים מההיסטוריה', () async {
    final image = AppReportImage(
      bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 9]),
      fileName: 'screenshot-1.png',
      mimeType: 'image/png',
    );
    final report = _report().copyWith(images: [image]);

    final offline = build(MockClient((_) async => http.Response('', 503)));
    expect((await offline.send(report)).isQueued, isTrue);
    final file = Directory(
      p.join(AppReportService.dirIn(tmp.path), 'pending'),
    ).listSync().whereType<File>().single;
    expect(file.readAsStringSync(), contains(base64Encode(image.bytes)));
    await offline.clearPendingReports();

    Map<String, dynamic>? sentBody;
    final online = build(
      MockClient((request) async {
        sentBody =
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
        return _json(200, {'success': true, 'issueNumber': 7});
      }),
    );
    expect((await online.send(report)).isSent, isTrue);
    final images = (sentBody!['attachments'] as Map)['images'] as List;
    expect(images.single['data'], base64Encode(image.bytes));
    final sent = (await online.getSentReports()).single;
    expect(sent.images, isEmpty);
    expect(sent.toJson().containsKey('images'), isFalse);
  });

  test('changes מודיע על הוספה לתור', () async {
    final service = build(MockClient((_) async => http.Response('', 503)));
    final events = <void>[];
    final sub = service.changes.listen(events.add);
    await service.queueReport(_report());
    await Future<void>.delayed(Duration.zero);
    expect(events, isNotEmpty);
    await sub.cancel();
  });

  group('חוסן ומכסות', () {
    test('כתיבת היסטוריה שנכשלה: הרשומה נשארת בתור ואינה אובדת', () async {
      final service = build(MockClient((_) async => _json(200, {})));
      await service.queueReport(_report());
      // תיקייה במקום sent.json: ה-rename של הכתיבה נכשל.
      Directory(p.join(AppReportService.dirIn(tmp.path), 'sent.json'))
          .createSync(recursive: true);
      final logs = <String>[];
      final logged = AppReportService(
        directory: AppReportService.dirIn(tmp.path),
        client: MockClient((_) async => _json(200, {})),
        log: logs.add,
      );
      services.add(logged);

      expect(await logged.flushPendingReports(), 0);
      expect(await logged.getPendingReportsCount(), 1);
      expect(logs, isNotEmpty);
    });

    test('שליחה עכשיו בזמן סבב רץ מצטרפת אליו, ואינה מחזירה 0', () async {
      final started = Completer<void>();
      final gate = Completer<http.Response>();
      var requests = 0;
      final service = build(
        MockClient((_) {
          requests++;
          if (!started.isCompleted) started.complete();
          return gate.future;
        }),
      );
      await service.queueReport(_report());

      final background = service.flush();
      await started.future;
      final manual = service.flush(
        maxRequests: AppReportService.maxManualFlushPerRun,
      );
      gate.complete(_json(200, {'issueNumber': 1}));

      expect((await background).sent, 1);
      expect((await manual).sent, 1);
      expect(requests, 1);
    });

    test('סבב ברקע מוגבל ל-4 בקשות, והתקרה אינה כשל', () async {
      var requests = 0;
      final service = build(
        MockClient((_) async {
          requests++;
          return _json(200, {});
        }),
      );
      for (var i = 0; i < 6; i++) {
        await service.queueReport(_report(title: 'r$i'));
      }
      final first = await service.flush();
      expect(first.sent, AppReportService.maxBackgroundFlushPerRun);
      expect(first.capped, isTrue);
      expect(first.stoppedOnTransientFailure, isFalse);
      expect(requests, 4);
      expect(await service.getPendingReportsCount(), 2);

      final manual = await service.flush(
        maxRequests: AppReportService.maxManualFlushPerRun,
      );
      expect(manual.sent, 2);
      expect(manual.capped, isFalse);
    });

    test('כשל זמני בסבב מסומן, בלי להיחשב תקרה', () async {
      final service = build(MockClient((_) async => http.Response('', 503)));
      await service.queueReport(_report());
      final outcome = await service.flush();
      expect(outcome.stoppedOnTransientFailure, isTrue);
      expect(outcome.sent, 0);
    });

    test('409 חוזר: אחרי 3 החלפות מזהה הדיווח מוסר', () async {
      final service = build(MockClient((_) async => _json(409, {})));
      await service.queueReport(_report());
      await service.flush();
      expect(await service.getPendingReportsCount(), 1);
      await service.flush();
      expect(await service.getPendingReportsCount(), 1);
      await service.flush();
      expect(await service.getPendingReportsCount(), 0);
      expect(await service.getSentReports(), isEmpty);
    });

    test('submitPendingReport: הקובץ נשאר בזמן הבקשה ונמחק רק בתוצאה סופית',
        () async {
      final started = Completer<void>();
      final gate = Completer<http.Response>();
      final service = build(
        MockClient((_) {
          started.complete();
          return gate.future;
        }),
      );
      final report = _report();
      await service.queueReport(report);

      final submission = service.submitPendingReport(report);
      await started.future;
      expect(await service.getPendingReportsCount(), 1);

      gate.complete(_json(200, {'issueNumber': 5}));
      expect((await submission).isSent, isTrue);
      expect(await service.getPendingReportsCount(), 0);
      expect((await service.getSentReports()).single.issueNumber, 5);
    });

    test('submitPendingReport: כשל זמני משאיר אותו בתור, ודחייה מסירה',
        () async {
      var status = 503;
      final service = build(
        MockClient((_) async => http.Response('', status)),
      );
      final report = _report();
      await service.queueReport(report);
      expect((await service.submitPendingReport(report)).isQueued, isTrue);
      expect(await service.getPendingReportsCount(), 1);
      status = 422;
      expect((await service.submitPendingReport(report)).isFailed, isTrue);
      expect(await service.getPendingReportsCount(), 0);
    });

    test('הרשימה בחלון בלי צרופות, והשליחה מהתור כוללת אותן', () async {
      Map<String, dynamic>? body;
      final service = build(
        MockClient((request) async {
          body = jsonDecode(utf8.decode(request.bodyBytes))
              as Map<String, dynamic>;
          return _json(200, {});
        }),
      );
      final report = _report().copyWith(
        images: [
          AppReportImage(
            bytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'a.png',
            mimeType: 'image/png',
          ),
        ],
      );
      await service.queueReport(report);

      final listed = (await service.getPendingReports()).single;
      expect(listed.images, isEmpty);
      expect(listed.diagnostics, isNull);
      expect(listed.errorLog, isNull);

      await service.submitPendingReport(listed);
      final attachments = body!['attachments'] as Map;
      expect(attachments['images'], hasLength(1));
      expect(attachments['errorLog'], 'log');
    });

    test('סדר התור הוא סדר ההוספה', () async {
      final service = build(MockClient((_) async => http.Response('', 503)));
      for (final title in ['a', 'b', 'c']) {
        await service.queueReport(_report(title: title));
      }
      expect((await service.getPendingReports()).map((r) => r.title),
          ['a', 'b', 'c']);
    });

    test('היסטוריה פגומה מועברת ל-.bad, וכתיבה הבאה מתחילה נקי', () async {
      final dir = AppReportService.dirIn(tmp.path);
      Directory(dir).createSync(recursive: true);
      final sent = File(p.join(dir, 'sent.json'))
        ..writeAsStringSync('{not json');
      final service = build(MockClient((_) async => _json(200, {})));
      expect(await service.getSentReports(), isEmpty);
      await service.send(_report());
      expect(File('${sent.path}.bad').existsSync(), isTrue);
      expect(await service.getSentReports(), hasLength(1));
    });

    test('כשל קריאה זמני של היסטוריה אינו מוחק אותה ואת המונה', () async {
      if (!Platform.isWindows) return; // נעילת קובץ נאכפת רק ב-Windows
      final service = build(MockClient((_) async => _json(200, {})));
      await service.send(_report());
      await service.send(_report());
      final file = File(p.join(AppReportService.dirIn(tmp.path), 'sent.json'));
      final handle = file.openSync(mode: FileMode.append);
      handle.lockSync(FileLock.blockingExclusive);
      try {
        await expectLater(
          service.clearSentReports(),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        handle.unlockSync();
        handle.closeSync();
      }
      expect(await service.getSentReports(), hasLength(2));
      expect(await service.getSentReportsTotal(), 2);
    });

    test('קבצי tmp שנשארו מכתיבה שנקטעה: לא נספרים, ומנוקים בעלייה', () async {
      final service = build(MockClient((_) async => http.Response('', 503)));
      await service.queueReport(_report());
      final dir = AppReportService.dirIn(tmp.path);
      final tmpSent = File(p.join(dir, 'sent.json.tmp'))
        ..writeAsStringSync('{"tot');
      final tmpPending = File(
        p.join(dir, 'pending', '0000000000000000009.x.json.tmp'),
      )..writeAsStringSync('{');
      final bad = File(p.join(dir, 'pending', '0000000000000000002.y.json.bad'))
        ..writeAsStringSync('x');

      expect(await service.getPendingReportsCount(), 1);
      expect(await service.getSentReports(), isEmpty);

      await service.cleanupStaleTemp();
      expect(tmpSent.existsSync(), isFalse);
      expect(tmpPending.existsSync(), isFalse);
      expect(bad.existsSync(), isTrue);
      expect(await service.getPendingReportsCount(), 1);
    });

    test('כשל בכתיבת הרשומה לא נרשם כשגיאה שלא נתפסה אלא דרך log', () async {
      final logs = <String>[];
      final service = AppReportService(
        directory: AppReportService.dirIn(tmp.path),
        client: MockClient((_) async => _json(200, {})),
        log: logs.add,
      );
      services.add(service);
      await service.queueReport(_report());
      Directory(p.join(AppReportService.dirIn(tmp.path), 'sent.json'))
          .createSync(recursive: true);
      // לא זורק, גם כשהדיסק מסרב.
      await service.flushPendingReports();
      expect(logs.any((l) => l.contains('flush failed')), isTrue);
    });
  });

  group('ספירת תוצאות הסבב', () {
    test('דחיית שרת מוסרת ונספרת כ-dropped, לא כ-sent', () async {
      final service = build(MockClient((_) async => _json(422, {})));
      await service.queueReport(_report());
      final outcome = await service.flush();
      expect(outcome.sent, 0);
      expect(outcome.dropped, 1);
      expect(outcome.failed, 0);
      expect(await service.getPendingReportsCount(), 0);
    });

    test('409 חוזר: ה-dropped נספר בסבב השלישי', () async {
      final service = build(MockClient((_) async => _json(409, {})));
      await service.queueReport(_report());
      expect((await service.flush()).dropped, 0);
      expect((await service.flush()).dropped, 0);
      expect((await service.flush()).dropped, 1);
    });

    test('כשל דיסק בכל הרשומות נספר כ-failed', () async {
      final service = build(MockClient((_) async => _json(200, {})));
      await service.queueReport(_report());
      await service.queueReport(_report());
      Directory(p.join(AppReportService.dirIn(tmp.path), 'sent.json'))
          .createSync(recursive: true);
      final outcome = await service.flush();
      expect(outcome.sent, 0);
      expect(outcome.failed, 2);
      expect(await service.getPendingReportsCount(), 2);
    });

    test('409 ראשון נספר כ-skipped (נכתב מחדש במזהה חדש)', () async {
      final service = build(MockClient((_) async => _json(409, {})));
      await service.queueReport(_report());
      final outcome = await service.flush();
      expect(
        (outcome.skipped, outcome.dropped, outcome.failed, outcome.sent),
        (1, 0, 0, 0),
      );
    });

    test('דיווח שכבר בהיסטוריה וקובץ פגום נספרים כ-skipped', () async {
      final service = build(MockClient((_) async => _json(200, {})));
      final done = _report();
      await service.send(done);
      // send מפעיל סבב ברקע; ממתינים לו, כדי שלא יספור את הקבצים שלהלן.
      await service.flush();
      final dir = Directory(p.join(AppReportService.dirIn(tmp.path), 'pending'))
        ..createSync(recursive: true);
      File(p.join(dir.path, '0000000000000000001.${done.reportId}.json'))
          .writeAsStringSync(
        jsonEncode({'queuedAt': 1, 'report': done.toJson()}),
      );
      File(p.join(dir.path, '0000000000000000002.broken.json'))
          .writeAsStringSync('{nope');
      final outcome = await service.flush();
      expect(outcome.skipped, 2);
      expect(outcome.sent, 0);
      expect(await service.getPendingReportsCount(), 0);
    });

    test('הצלחה מלאה: אפסים', () async {
      final service = build(MockClient((_) async => _json(200, {})));
      await service.queueReport(_report());
      final outcome = await service.flush();
      expect(
        (outcome.sent, outcome.failed, outcome.dropped, outcome.capped),
        (1, 0, 0, false),
      );
    });
  });

  test('היסטוריה עם שדה בסוג שגוי מועברת ל-.bad, ושליחות נשמרות', () async {
    final dir = AppReportService.dirIn(tmp.path);
    Directory(dir).createSync(recursive: true);
    final sent = File(p.join(dir, 'sent.json'))
      ..writeAsStringSync(
        jsonEncode({
          'total': 3,
          'reports': [
            {'reportId': 'x', 'osVersion': 5},
          ],
        }),
      );
    final service = build(MockClient((_) async => _json(200, {})));
    final result = await service.send(_report());
    expect(result.isSent, isTrue);
    expect(File('${sent.path}.bad').existsSync(), isTrue);
    // נשמר בהיסטוריה החדשה, ואינו מוחזר לתור כדי להישלח שוב.
    expect(await service.getSentReports(), hasLength(1));
    expect(await service.getPendingReportsCount(), 0);
  });

  test('קריאות תצוגה לא מעבירות ל-.bad קובץ תקין שנכתב זה עתה', () async {
    final dir = AppReportService.dirIn(tmp.path);
    Directory(dir).createSync(recursive: true);
    final sentFile = File(p.join(dir, 'sent.json'))
      ..writeAsStringSync('{corrupt');
    final service = build(MockClient((_) async => _json(200, {})));

    await Future.wait([
      service.send(_report()),
      for (var i = 0; i < 25; i++) service.getSentReports(),
    ]);
    for (var i = 0; i < 25; i++) {
      await service.getSentReports();
    }

    expect(sentFile.existsSync(), isTrue);
    expect(await service.getSentReports(), hasLength(1));
    // רק העותק הפגום המקורי הועבר הצידה.
    expect(
      Directory(dir).listSync().where((e) => e.path.endsWith('.bad')),
      hasLength(1),
    );
  });

  test('submitPendingReport על רשומה שכבר אינה בתור: notPending, בלי שליחה',
      () async {
    var requests = 0;
    final service = build(
      MockClient((_) async {
        requests++;
        return _json(200, {});
      }),
    );
    final result = await service.submitPendingReport(_report());
    expect(result.isFailed, isTrue);
    expect(result.failureReason, AppReportFailureReason.notPending);
    expect(requests, 0);
  });

  test('קידוד הרשומה לתור (כולל תמונה גדולה) לא רץ ב-isolate של הממשק',
      () async {
    final service = build(MockClient((_) async => http.Response('', 503)));
    final report = _report().copyWith(
      diagnostics: {'probe': const _EncodingIsolateProbe()},
      images: [
        AppReportImage(
          bytes: Uint8List(4 * 1000 * 1000),
          fileName: 'big.png',
          mimeType: 'image/png',
        ),
      ],
    );
    await service.queueReport(report);

    final file = Directory(
      p.join(AppReportService.dirIn(tmp.path), 'pending'),
    ).listSync().whereType<File>().single;
    final stored = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final probe = ((stored['report'] as Map)['diagnostics'] as Map)['probe'];
    expect(probe, isNotNull);
    expect(probe, isNot(Isolate.current.debugName));
  });

  test('אימייל ארוך מ-254 תווים נכשל בבדיקה מקומית', () {
    final long = '${'a' * 250}@b.co';
    expect(
      _report().copyWith(reporterEmail: long).validate(),
      'reporterEmail',
    );
    expect(_report().validate(), isNull);
  });
}

/// נבדק בקידוד: `toJson` רץ באיזה isolate? ראו `_encodePending`.
class _EncodingIsolateProbe {
  const _EncodingIsolateProbe();

  String? toJson() => Isolate.current.debugName;
}
