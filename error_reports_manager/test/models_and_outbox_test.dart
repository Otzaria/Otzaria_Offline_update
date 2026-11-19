import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('OutboxReport', () {
    test('כתובת מותרת רק ב-https ל-otzaria.org', () {
      bool allowed(String url) =>
          OutboxReport.fromJson(reportJson('a', endpoint: url), filePath: 'a')
              .isAllowedEndpoint;
      expect(allowed('https://otzaria.org/api/reportingerrors'), isTrue);
      expect(allowed('http://otzaria.org/api/reportingerrors'), isFalse);
      expect(allowed('https://evil.example/api'), isFalse);
      expect(allowed('https://otzaria.org.evil.example/api'), isFalse);
      expect(allowed('https://user@otzaria.org/api'), isFalse);
      expect(allowed('https://otzaria.org:8443/api'), isFalse);
    });

    test('רק שלוש נקודות הקצה של הדיווחים, בלי query', () {
      bool allowed(String url) =>
          OutboxReport.fromJson(reportJson('a', endpoint: url), filePath: 'a')
              .isAllowedEndpoint;
      expect(allowed(OutboxReport.appReportingEndpoint), isTrue);
      expect(allowed(OutboxReport.pluginReportingEndpoint), isTrue);
      expect(allowed('https://otzaria.org/api/auth/signin'), isFalse);
      expect(allowed('https://otzaria.org/api/reportingerrors/x'), isFalse);
      expect(allowed('https://otzaria.org/api/reportingerrors?to=x'), isFalse);
      expect(allowed('https://otzaria.org/api/reportingerrors#x'), isFalse);
      expect(allowed('https://otzaria.org/'), isFalse);
    });

    test('שדה חובה חסר זורק', () {
      final json = reportJson('a')..remove('body');
      expect(
        () => OutboxReport.fromJson(json, filePath: 'a'),
        throwsFormatException,
      );
    });

    for (final ids in [
      {'report_id': 'book-id'},
      {'reportId': 'app-id'},
      {'reportId': 'retained-id', 'report_id': 'chosen-id'},
    ]) {
      test('bytes and content key preserve ${ids.keys.join('/')} precedence',
          () {
        final body = <String, dynamic>{
          ...ids,
          'product': 'offline-update',
          'text': 'עברית 🚀\n\u0000\ud800',
          'nested': {
            'z': [1, true, null],
            'a': {'y': 2, 'x': 1},
          },
        };
        final file = OutboxReport.fileJson(
          reportId: 'envelope-id',
          bookTitle: 'ספר',
          createdAt: '2026-10-01T10:00:00Z',
          body: body,
        );
        final before = jsonEncode(file);
        final request = Map.of(body)..remove('product');
        final content = Map.of(request)
          ..remove(body.containsKey('report_id') ? 'report_id' : 'reportId');
        final expectedKey = sha256
            .convert(utf8.encode('${file['endpoint']}\n${jsonEncode(content)}'))
            .toString();

        expect(OutboxReport.encodeFile(file), utf8.encode(before));
        expect(
            OutboxReport.requestBodyOf(file), utf8.encode(jsonEncode(request)));
        expect(OutboxReport.requestBodyOf({...file, 'body': request}),
            utf8.encode(jsonEncode(request)));
        expect(OutboxReport.contentKeyOf(file), expectedKey);
        expect(
            OutboxReport.contentKeyOf({...file, 'body': request}), expectedKey);
        expect(
            OutboxReport.contentKeyOf({
              ...file,
              'endpoint': OutboxReport.appReportingEndpoint,
            }),
            isNot(expectedKey));
        expect(jsonEncode(file), before);
      });
    }

    test('content key requires the selected ID to be a string', () {
      for (final body in [
        null,
        <String, dynamic>{},
        {'reportId': 1},
        {'report_id': null, 'reportId': 'valid'},
      ]) {
        expect(OutboxReport.contentKeyOf({'body': body}), isNull);
      }
    });
  });

  group('DirectoryReportOutbox', () {
    late Directory temp;
    late String dir;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('outbox_test');
      dir = DirectoryReportOutbox.dirIn(temp.path);
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('התיבה יושבת מחוץ ל-mirror/', () {
      expect(p.split(p.relative(dir, from: temp.path)), ['reports', 'outbox']);
    });

    test('תיקייה חסרה = ריק', () async {
      expect(await DirectoryReportOutbox(dir).list(), isEmpty);
    });

    test('מיון עקבי: בלי זמן יצירה — בסוף, ושם הקובץ מכריע', () {
      OutboxReport r(String id, String? created) =>
          OutboxReport.fromJson({...reportJson(id), 'created_at': created},
              filePath: id);
      final list = [
        r('d', null),
        r('c', '2026-09-02T00:00:00Z'),
        r('b', null),
        r('a', '2026-09-02T00:00:00Z'),
        r('e', '2026-09-01T00:00:00Z'),
      ]..sort(DirectoryReportOutbox.compareReports);
      expect(list.map((x) => x.reportId), ['e', 'a', 'c', 'b', 'd']);
    });

    test('מדלג על קבצים פגומים וממיין לפי זמן', () async {
      writeReport(dir, reportJson('b', createdAt: '2026-09-02T00:00:00Z'));
      writeReport(dir, reportJson('a', createdAt: '2026-09-03T00:00:00Z'));
      writeReport(dir, {...reportJson('c'), 'version': 2});
      File(p.join(dir, 'broken.json')).writeAsStringSync('{');
      File(p.join(dir, 'notes.txt')).writeAsStringSync('x');

      final invalid = <String>[];
      final outbox =
          DirectoryReportOutbox(dir, onInvalid: (path, _) => invalid.add(path));
      final list = await outbox.list();

      expect(list.map((r) => r.reportId), ['b', 'a']);
      expect(
          invalid.map(p.basename), unorderedEquals(['c.json', 'broken.json']));

      await outbox.remove(list.first);
      expect((await outbox.list()).map((r) => r.reportId), ['a']);
    });

    test('שני עותקים של אותו תוכן במזהים שונים (קריסה אחרי 409) — נשאר החדש',
        () async {
      Map<String, dynamic> copy(String id) => OutboxReport.fileJson(
            reportId: id,
            bookTitle: 'ספר',
            createdAt: '2026-09-01T10:00:00Z',
            body: {'report_id': id, 'text': 'טעות'},
          );
      writeReport(dir, copy('old'));
      File(p.join(dir, 'old.json')).setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)));
      writeReport(dir, copy('new'));
      writeReport(dir, {
        ...copy('other'),
        'body': {'report_id': 'other', 'text': 'אחר'},
      });

      final list = await DirectoryReportOutbox(dir).list();

      expect(list.map((r) => r.reportId), unorderedEquals(['new', 'other']));
      expect(File(p.join(dir, 'old.json')).existsSync(), isFalse);
    });

    test('count סופר קובצי json בלי לפתוח אותם', () async {
      expect(await DirectoryReportOutbox(dir).count(), 0);
      writeReport(dir, reportJson('a'));
      writeReport(dir, reportJson('b'));
      File(p.join(dir, 'a.json.123.tmp')).writeAsStringSync('{');
      File(p.join(dir, 'notes.txt')).writeAsStringSync('x');

      expect(await DirectoryReportOutbox(dir).count(), 2);
    });

    test('discard מוחק גם את הקובץ הזמני של כתיבה שנכשלה', () async {
      final outbox = DirectoryReportOutbox(dir);
      await outbox.write('r1', OutboxReport.encodeFile(reportJson('r1')));
      final temp = File(p.join(dir, 'r1.json.tmp'))..writeAsStringSync('{');
      await outbox.discard('r1');
      expect(File(p.join(dir, 'r1.json')).existsSync(), isFalse);
      expect(temp.existsSync(), isFalse);
    });

    test('list מוחק קובץ זמני ישן ומשאיר כתיבה שעוד רצה', () async {
      Directory(dir).createSync(recursive: true);
      final stale = File(p.join(dir, 'old.json.tmp'))..writeAsStringSync('{');
      stale.setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 2)));
      final fresh = File(p.join(dir, 'new.json.tmp'))..writeAsStringSync('{');
      final invalid = <String>[];
      final list = await DirectoryReportOutbox(dir,
          onInvalid: (path, _) => invalid.add(path)).list();
      expect(list, isEmpty);
      expect(invalid, isEmpty);
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('כתיבה מבייטים, רשימה בלי גופים, וגוף בקשה בלי product', () async {
      final outbox = DirectoryReportOutbox(dir);
      final file = OutboxReport.fileJson(
        reportId: 'app-1',
        bookTitle: 'תקלה',
        createdAt: '2026-10-01T10:00:00Z',
        endpoint: OutboxReport.appReportingEndpoint,
        body: {
          'reportId': '1',
          'product': 'offline-update',
          'attachments': {
            'images': [
              {'data': 'AQID'}
            ]
          },
        },
      );
      await outbox.write('app-1', OutboxReport.encodeFile(file));
      await outbox.write(
          'b', OutboxReport.encodeFile({...reportJson('b'), 'body': {}}));

      final list = await outbox.list();
      expect(list.map((r) => r.reportId), ['b', 'app-1']);
      expect(list.map((r) => r.hasImages), [false, true]);
      expect(
        jsonDecode(File(list.last.filePath).readAsStringSync()),
        file,
      );
      expect(jsonDecode(utf8.decode(await outbox.requestBody(list.last))), {
        'reportId': '1',
        'attachments': {
          'images': [
            {'data': 'AQID'}
          ]
        },
      });
    });

    test('גוף של קובץ שנפגם אחרי הרשימה זורק', () async {
      writeReport(dir, reportJson('a'));
      final outbox = DirectoryReportOutbox(dir);
      final report = (await outbox.list()).single;
      File(report.filePath).writeAsStringSync('{');
      await expectLater(outbox.requestBody(report), throwsFormatException);
    });
  });
}
