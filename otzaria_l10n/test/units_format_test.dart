import 'dart:io';

import 'package:test/test.dart';

/// גודל (מספר ויחידה) במלל — באותו פורמט כמו `units`:
/// - עברית: המספר והיחידה הלטינית יחד בתוך LRI…PDI, עם רווח קשיח
///   (`\u2066` 1.5 `\u00a0` GB `\u2069`). יחידה עברית אחרי מספר ("2 ג׳יגה")
///   אסורה; כמילה בלי מספר ("כמה ג׳יגה־בייט") היא מותרת.
/// - אנגלית: מספר, רווח רגיל ויחידה ("1.5 GB"); "tens of MB" נכתב במילים.
void main() {
  for (final (file, hebrew) in [
    ('lib/src/strings_he.dart', true),
    ('lib/src/strings_en.dart', false),
  ]) {
    test('גדלים בפורמט של units: $file', () {
      final source = File(file).readAsStringSync();
      expect(sizeFormatViolations(source, hebrew: hebrew), isEmpty);
    });
  }

  group('הבודק עצמו', () {
    List<String> he(String source) => sizeFormatViolations(source);
    List<String> en(String source) =>
        sizeFormatViolations(source, hebrew: false);

    test('עברית: תקין', () {
      expect(he(r"'כ-\u20661.5\u00a0GB\u2069.'"), isEmpty);
      expect(he(r"'\u2066$amount\u00a0MB\u2069'"), isEmpty);
      expect(he(r"'\u2066${n.toStringAsFixed(1)}\u00a0KB\u2069'"), isEmpty);
      expect(he("'כ-\u20662\u00a0GB\u2069'"), isEmpty, reason: 'תווים ממשיים');
      expect(he(r"'כמה ג׳יגה־בייט, ועשרות מגה־בייט'"), isEmpty);
      expect(he("  // 2 GB בהערה\n  /// גם 3 MB\n'x'"), isEmpty);
      expect(he("'בערך \\u20662'\n      '\\u00a0GB\\u2069'"), isEmpty,
          reason: 'מחרוזות מחוברות');
      expect(he(r"'$count בייט'"), isEmpty);
    });

    test('עברית: נתפס', () {
      expect(he(r"'כ-1.5GB'"), hasLength(1));
      expect(he(r"'כ-1.5 \u2066GB\u2069'"), hasLength(1));
      expect(he(r"'כמה \u2066GB\u2069'"), hasLength(1));
      expect(he(r"'\u20661.5 GB\u2069'"), hasLength(1), reason: 'רווח רגיל');
      expect(he(r"'2 ג׳יגה'"), hasLength(1));
      expect(he(r"'2 גיגה'"), hasLength(1));
      expect(he(r"'1.5 מגה־בייט'"), hasLength(1));
      expect(he(r"'2 ג״ב'"), hasLength(1));
      expect(he(r"'300 מ״ב'"), hasLength(1));
      expect(he(r"'$size ג׳יגה־בייט'"), hasLength(1));
    });

    test('אנגלית', () {
      expect(en(r"'about 1.5 GB, $amount MB, ${n} KB'"), isEmpty);
      expect(en(r"'tens of megabytes'"), isEmpty);
      expect(en(r"'tens of MB'"), hasLength(1));
      expect(en(r"'about 1.5GB'"), hasLength(1));
      expect(en(r"'about 1.5\u00a0GB'"), hasLength(1));
    });
  });
}

const _unit = r'(?<![A-Za-z])[KMGT]B(?![A-Za-z])';
const _number = r'(?:\d+(?:\.\d+)?|\$\w+|\$\{[^}]*\})';
final _latinUnit = RegExp(_unit);
final _isolate = RegExp(r'\\u2066(.*?)\\u2069');
final _isolatedSize = RegExp('^$_number' r'\\u00a0' '$_unit\$');
final _hebrewUnitAfterNumber = RegExp(
  '$_number' r"""\s*[-־]?\s*(?:ג[׳'"״]?יגה|מגה|קילו|[גמק][״"]ב)""",
);
final _englishSize = RegExp('$_number $_unit');

/// השורות ב-[source] שבהן גודל אינו בפורמט של `units`.
List<String> sizeFormatViolations(String source, {bool hebrew = true}) {
  final code = source
      .replaceAll('\r', '')
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n')
      // מחרוזות סמוכות ('…' בסוף שורה ו-'…' בתחילת הבאה) הן מחרוזת אחת.
      .replaceAll(RegExp(r"'[ \t]*\n[ \t]*'"), '')
      .replaceAll('\u2066', r'\u2066')
      .replaceAll('\u2069', r'\u2069')
      .replaceAll('\u00a0', r'\u00a0');
  final hits = <String>[];
  for (final line in code.split('\n')) {
    if (hebrew) {
      final isolates = _isolate.allMatches(line).map((m) => m[1]!);
      final outside = line.replaceAll(_isolate, ' ');
      if (_latinUnit.hasMatch(outside) ||
          isolates.any(
            (s) => _latinUnit.hasMatch(s) && !_isolatedSize.hasMatch(s),
          ) ||
          _hebrewUnitAfterNumber.hasMatch(line)) {
        hits.add(line.trim());
      }
    } else {
      final units = _latinUnit.allMatches(line).length;
      if (units > _englishSize.allMatches(line).length) hits.add(line.trim());
    }
  }
  return hits;
}
