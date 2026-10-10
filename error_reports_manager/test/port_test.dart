import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:error_reports_manager/src/port/plugin_report_record.dart';
import 'package:test/test.dart';

// הוקטורים נגזרו מהקוד של אוצריא עצמה, לא נכתבו ביד:
// - `digest_fixtures.json` הועתק כמות שהוא מ-`test/fixtures/text_corrections/`
//   באוצריא (upstream/dev, 52678edb395ff04c98b6cb7adf187086bda5f532) — אותו
//   קובץ שהאתר בודק מולו.
// - `api_payload_golden.json` הופק באותו commit: `DirectErrorReport.fromJson`
//   על כל `stored`, ואז `toApiPayload()` ו-`contentDigest` של אוצריא.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('דיווחי תוכנה ותוספים מול המודלים המקוריים של אוצריא', () {
    final golden = _fixture('other_reports_golden.json');
    test('המקור מתועד', () {
      expect(golden['source'],
          contains('46882aa87d17aaf55783da2b106d74fd587461e5'));
    });
    for (final c in (golden['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final stored = Map<String, dynamic>.from(c['stored'] as Map);
        if (c['expandLargeFields'] == true) {
          stored.addAll({
            'title': '${'a' * 199}😀truncated',
            'diagnostics': {'huge': 'א' * 160000},
            'errorLog': 'א😀' * 50000,
            'images': [],
          });
        }
        final Map<String, dynamic> body;
        if (c['kind'] == 'app') {
          final report = AppReport.fromJson(stored);
          expect(report.validate() == null, c['valid']);
          body = report.toApiPayload();
        } else {
          body = PluginReportRecord.fromJson(stored).toApiPayload();
        }
        if (c['payloadSha256'] != null) {
          expect(sha256.convert(utf8.encode(jsonEncode(body))).toString(),
              c['payloadSha256']);
        } else {
          expect(jsonDecode(jsonEncode(body)), c['payload']);
        }
      });
    }
  });

  group('OCJ-1 מול ה-fixtures של אוצריא והאתר', () {
    final cases =
        (_fixture('digest_fixtures.json')['cases'] as List).cast<Map>();

    test('יש מה לבדוק', () => expect(cases, isNotEmpty));

    for (final c in cases) {
      test('${c['name']}', () {
        expect(canonicalJsonEncode(c['input']), c['canonical']);
        expect(canonicalJsonSha256(c['input']), c['sha256']);
      });
    }

    test('surrogate בודד נדחה, זוג תקין נשמר', () {
      expect(canonicalJsonEncode('😀'), '"😀"');
      expect(() => canonicalJsonEncode('\uD83D'), throwsArgumentError);
    });
  });

  group('toApiPayload זהה לזה של אוצריא', () {
    final golden = _fixture('api_payload_golden.json');
    final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();

    test('המקור מתועד', () {
      expect(golden['source'], contains('52678edb395ff04c98b6cb7adf187086'));
      expect(cases.length, greaterThanOrEqualTo(7));
    });

    for (final c in cases) {
      test('${c['name']}', () {
        final stored = jsonDecode(jsonEncode(c['stored']));
        final report =
            DirectErrorReport.fromJson(stored as Map<String, dynamic>);
        expect(report.isSendable, c['sendable']);
        if (c['payload'] != null) {
          // דרך jsonEncode, כמו על החוט.
          expect(jsonDecode(report.apiBody), c['payload']);
        }
      });
    }
  });

  group('isSendable', () {
    Map<String, dynamic> base() => {
          'id': 'x',
          'senderEmail': '',
          'subject': 's',
          'bookTitle': 'b',
          'currentRef': 'r',
          'lineNumber': 1,
          'createdAt': '2026-09-01T00:00:00.000Z',
          'schemaVersion': 2,
        };

    test('גוף מעל 256KB אינו נשלח', () {
      final report = DirectErrorReport.fromJson({
        ...base(),
        'contextText': 'א' * (DirectErrorReport.maxApiBodyBytes)
      });
      expect(report.isSendable, isFalse);
    });

    test('סכמה חדשה מהמוכרת אינה נשלחת', () {
      final report =
          DirectErrorReport.fromJson({...base(), 'schemaVersion': 3});
      expect(report.isSendable, isFalse);
    });

    test('שדה חובה חסר — fromJson זורק, כמו באוצריא', () {
      expect(
          () => DirectErrorReport.fromJson({...base()}..remove('lineNumber')),
          throwsA(anything));
    });
  });
}
