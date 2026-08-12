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

    test(
        'מוריד רמת הזחה אחידה מכל שורות הפסקה, כדי שזו תהיה רשימת Markdown '
        'שטוחה ולא שהשורה הראשונה (שנפגעת מ-trim) שונה מהשאר', () async {
      final client =
          OtzariaChangelogClient(httpClient: _mockChangelog(_fakeChangelog));

      final notes = await client.notesFor('0.9.96');

      expect(
        notes,
        '- שורה א של 0.9.96\n- שורה ב של 0.9.96',
      );
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

    test('הפסקה האחרונה בקובץ נקראת עד הסוף', () async {
      final client =
          OtzariaChangelogClient(httpClient: _mockChangelog(_fakeChangelog));

      expect(await client.notesFor('0.9.90'), '- שורה ישנה');
    });

    // שורה ריקה באמצע פסקה מפרידה בין תת-רשימות; הסרתה הייתה מדביקה אותן.
    test('שורות ריקות נשמרות באמצע ומוסרות רק מהקצוות', () async {
      final client = OtzariaChangelogClient(
        httpClient: _mockChangelog(
          '* **1.0.0**\n\n  - א\n\n  - ב\n\n* **0.9.0**\n  - ישן\n',
        ),
      );

      expect(await client.notesFor('1.0.0'), '- א\n\n- ב');
    });

    test('פסקה ריקה לגמרי מחזירה null', () async {
      final client = OtzariaChangelogClient(
        httpClient: _mockChangelog('* **1.0.0**\n\n\n* **0.9.0**\n  - ישן\n'),
      );

      expect(await client.notesFor('1.0.0'), isNull);
    });

    // רק כותרת גרסה (`* **1.2.3**`) סוגרת פסקה — כותרות Markdown רגילות לא.
    test('כותרת שאינה כותרת גרסה נשארת חלק מהפסקה', () async {
      final client = OtzariaChangelogClient(
        httpClient: _mockChangelog(
          '* **1.0.0**\n  ## תיקוני באגים\n  - א\n* **0.9.0**\n  - ישן\n',
        ),
      );

      expect(await client.notesFor('1.0.0'), '## תיקוני באגים\n- א');
    });

    test('קובץ ריק או בלי כותרות בכלל מחזיר null', () async {
      for (final body in ['', 'סתם טקסט בלי כותרות\n']) {
        final client = OtzariaChangelogClient(httpClient: _mockChangelog(body));

        expect(await client.notesFor('0.9.96'), isNull, reason: body);
      }
    });

    test('הקובץ נשלף מענף dev של Otzaria/otzaria', () {
      expect(OtzariaChangelogClient.url, startsWith('https://'));
      expect(OtzariaChangelogClient.url, contains('/Otzaria/otzaria/dev/'));
    });

    test('close לא זורק', () {
      final client =
          OtzariaChangelogClient(httpClient: _mockChangelog(_fakeChangelog));

      expect(client.dispose, returnsNormally);
    });
  });
}
