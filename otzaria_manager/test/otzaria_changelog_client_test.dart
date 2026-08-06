import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

const Map<String, String> _utf8TextHeaders = {
  'content-type': 'text/plain; charset=utf-8',
};

const String _fakeChangelog = '''
* **0.9.96**
  - שורה א של 0.9.96
  - שורה ב של 0.9.96
* **0.9.95**
  - שורה א של 0.9.95
* **0.9.90**
  - שורה ישנה
''';

http.Client _mockChangelog(String body, {int status = 200}) =>
    MockClient((request) async {
      expect(request.url.toString(), OtzariaChangelogClient.url);
      return http.Response(body, status, headers: _utf8TextHeaders);
    });

void main() {
  group('OtzariaChangelogClient.notesFor', () {
    test('מחלץ רק את הפסקה של הגרסה המבוקשת, בלי הכותרת ובלי הגרסה הבאה',
        () async {
      final client =
          OtzariaChangelogClient(httpClient: _mockChangelog(_fakeChangelog));

      final notes = await client.notesFor('0.9.95');

      expect(notes, isNotNull);
      expect(notes, contains('שורה א של 0.9.95'));
      expect(notes, isNot(contains('0.9.96')));
      expect(notes, isNot(contains('שורה ישנה')));
    });

    test('מנרמל תג עם v מוביל וסיומת build', () async {
      final client =
          OtzariaChangelogClient(httpClient: _mockChangelog(_fakeChangelog));

      final notes = await client.notesFor('v0.9.96+736');

      expect(notes, contains('שורה א של 0.9.96'));
      expect(notes, contains('שורה ב של 0.9.96'));
    });

    test('מחזיר null כשהגרסה לא מופיעה בקובץ', () async {
      final client =
          OtzariaChangelogClient(httpClient: _mockChangelog(_fakeChangelog));

      expect(await client.notesFor('1.0.0'), isNull);
    });

    test('מחזיר null בסטטוס לא תקין, בלי לזרוק', () async {
      final client = OtzariaChangelogClient(
        httpClient: _mockChangelog(_fakeChangelog, status: 404),
      );

      expect(await client.notesFor('0.9.96'), isNull);
    });

    test('מחזיר null בכשל רשת, בלי לזרוק', () async {
      final client = OtzariaChangelogClient(
        httpClient: MockClient((request) async => throw Exception('offline')),
      );

      expect(await client.notesFor('0.9.96'), isNull);
    });
  });
}
