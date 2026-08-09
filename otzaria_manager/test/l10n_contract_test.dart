import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// כל מלל שהמשתמש רואה חייב לבוא מ-`otzaria_l10n` — ראו AGENTS.md §4.
/// הבדיקות כאן סורקות את קוד החבילה עצמו, כי אין דרך אחרת לתפוס ליטרל
/// שנשכח בתוך הודעת חריג.

final RegExp _hebrewLetter = RegExp(r'[֐-׿]');

/// ליטרלים בעברית שאינם מלל למשתמש: נתיב התקנה היסטורי ושם החבילה
/// שמשמש לזיהוי — לא מתורגמים, ולא אמורים להיות.
const Set<String> _allowedHebrewLiterals = {r'C:\אוצריא', 'אוצריא'};

/// חריגים שכל מחרוזת שנכנסת אליהם היא מלל למשתמש.
const List<String> _userFacingThrowables = [
  'StateError',
  'UnsupportedError',
  'FormatException',
  'GithubApiException',
];

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// מסיר הערות ומחזיר את תוכן כל מחרוזת ליטרלית שבקוד. סורק תו-תו כי
/// regex לא מבחין בין מחרוזת אמיתית לבין ציטוט בתוך הערה.
({String code, List<String> literals}) _parse(String source) {
  final code = StringBuffer();
  final literals = <String>[];
  var i = 0;

  while (i < source.length) {
    final char = source[i];

    if (char == '/' && i + 1 < source.length) {
      if (source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        continue;
      }
      if (source[i + 1] == '*') {
        i += 2;
        while (i + 1 < source.length &&
            !(source[i] == '*' && source[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }
    }

    if (char == "'" || char == '"') {
      final delimiter = source.startsWith(char * 3, i) ? char * 3 : char;
      final isRaw = i > 0 && source[i - 1] == 'r';
      i += delimiter.length;
      final value = StringBuffer();
      while (i < source.length && !source.startsWith(delimiter, i)) {
        if (!isRaw && source[i] == r'\') {
          i += 2;
          continue;
        }
        value.write(source[i]);
        i++;
      }
      i += delimiter.length;
      literals.add(value.toString());
      // סמן במקום המחרוזת, כדי שליטרל שהועבר לחריג לא ייעלם מהקוד ויתחמק
      // מהבדיקה שאחריה.
      code.write('_LITERAL_');
      continue;
    }

    code.write(char);
    i++;
  }

  return (code: code.toString(), literals: literals);
}

void main() {
  final files = _libFiles();

  test('יש מה לסרוק בכלל', () {
    expect(files, isNotEmpty);
  });

  test('אין ליטרל בעברית בקוד — רק בהערות ובנתיבים מוכרים', () {
    final found = <String>{};
    for (final file in files) {
      final literals = _parse(file.readAsStringSync()).literals;
      for (final literal in literals.where((l) => l.contains(_hebrewLetter))) {
        found.add(literal);
        expect(
          _allowedHebrewLiterals,
          contains(literal),
          reason: '${p.basename(file.path)}: «$literal» — '
              'מלל למשתמש חייב לבוא מ-AppL10n',
        );
      }
    }

    // שמירה מפני בדיקה ריקה: אם הסורק הפסיק למצוא ליטרלים בכלל, הבדיקה
    // הייתה עוברת גם על קוד שבור.
    expect(found, _allowedHebrewLiterals);
  });

  test('כל הודעת חריג נבנית מ-AppL10n.strings', () {
    var sites = 0;
    for (final file in files) {
      final code = _parse(file.readAsStringSync()).code;
      for (final name in _userFacingThrowables) {
        // רק אתרי הזריקה — לא הצהרת הבנאי של החריג עצמו.
        for (final match
            in RegExp('throw\\s+$name\\s*\\(\\s*(\\S*)').allMatches(code)) {
          sites++;
          final argument = match.group(1)!;
          expect(
            argument,
            startsWith('AppL10n.strings'),
            reason: '${p.basename(file.path)}: $name קיבל «$argument»',
          );
        }
      }
    }

    expect(sites, greaterThanOrEqualTo(10), reason: 'הסורק לא מצא זריקות');
  });

  // הסורק עצמו נבדק מול קטע מפוברק, כדי שלא "יעבור" רק כי לא ראה כלום.
  test('הסורק מבחין בין הערה למחרוזת, ובין ליטרל לקריאה ל-l10n', () {
    const snippet = '''
/// הערה בעברית עם 'ציטוט' בתוכה.
void f() {
  // עוד הערה
  throw StateError('שגיאה קשיחה');
  throw UnsupportedError(AppL10n.strings.appDomain.macOnlyReader);
  final path = r'C:\\אוצריא';
}
''';
    final parsed = _parse(snippet);

    expect(parsed.literals, contains('שגיאה קשיחה'));
    expect(parsed.literals, contains(r'C:\אוצריא'));
    expect(parsed.literals.any((l) => l.contains('הערה')), isFalse);
    expect(parsed.code, contains('throw StateError(_LITERAL_'));
    expect(parsed.code, contains('throw UnsupportedError(AppL10n.strings'));
  });

  test('חריג ייעודי אחד מנסח דרך toString, ולא בבנאי', () {
    final source = File(p.join('lib', 'src', 'models', 'otzaria_release.dart'))
        .readAsStringSync();

    expect(source, contains('AppL10n.strings.appDomain.noAssetForPlatform'));
  });
}
