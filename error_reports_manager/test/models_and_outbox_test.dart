import 'dart:io';

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

    test('שדה חובה חסר זורק', () {
      final json = reportJson('a')..remove('body');
      expect(
        () => OutboxReport.fromJson(json, filePath: 'a'),
        throwsFormatException,
      );
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
  });
}
