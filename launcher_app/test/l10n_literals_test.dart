import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

/// שומר על הכלל מ-AGENTS §4: **כל** מלל שהמשתמש רואה יושב ב-`otzaria_l10n`,
/// ולא כמחרוזת בקוד. הסריקה מחפשת ליטרלים עם אותיות עבריות — עברית היא
/// שפת המקור, ולכן כל מלל למשתמש נכתב בה קודם.
///
/// מה שמותר, ומדוע:
/// * הערות ותיעוד — נכתבים בעברית בכוונה (AGENTS §4).
/// * שורות ליומן הפעילות והודעות `assert` — אבחון למפתח, לא מלל ממשק.
/// * `hebrew_date.dart` — שמות חודשים וגימטריה; זה לוח שנה, לא מלל ממשק.
/// * `app_seed_colors.dart` — פורט מאוצריא ואינו בשימוש בלאנצ'ר (אין בו
///   בורר צבעים). אם יתווסף כזה, השמות חייבים לעבור ל-`otzaria_l10n`.
void main() {
  const allowedFiles = {
    'lib/src/services/hebrew_date.dart',
    'lib/src/theme/app_seed_colors.dart',
  };

  /// סימנים שאחריהם הליטרל הוא אבחון למפתח ולא מלל ממשק.
  const diagnosticMarkers = [
    'AppLogger',
    'logger.',
    'log.',
    'debugPrint',
    'print(',
    'assert(',
  ];

  test('אין ב-lib/ מחרוזת עברית שהמשתמש יכול לראות', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'הבדיקה רצה משורש החבילה');

    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.relative(entity.path).replaceAll(r'\', '/');
      if (allowedFiles.contains(relative)) continue;

      final source = entity.readAsStringSync();
      final lines = source.split('\n');

      for (final literal in _stringLiterals(source)) {
        if (!_hebrew.hasMatch(literal.value)) continue;

        // ליטרל שיושב בקריאת אבחון — מותר. נבדקות גם שתי השורות שמעליו,
        // כי קריאות ארוכות נשברות לשורה נפרדת.
        final context = [
          for (var i = literal.line - 3; i < literal.line; i++)
            if (i >= 0 && i < lines.length) lines[i],
        ].join('\n');
        if (diagnosticMarkers.any(context.contains)) continue;

        violations.add('$relative:${literal.line}: "${literal.value}"');
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'מלל למשתמש חייב לבוא מ-AppL10n.strings / context.strings',
    );
  });

  test('אותו מלל קיים בשתי השפות ואינו זהה במקרה', () {
    // דגימה קטנה מהסעיפים שהקוד שבתחום הבדיקות הזה משתמש בהם.
    final he = AppL10n.stringsFor(AppLanguage.hebrew);
    final en = AppL10n.stringsFor(AppLanguage.english);

    expect(he.setupError.title, isNotEmpty);
    expect(en.setupError.title, isNotEmpty);
    expect(en.setupError.title, isNot(he.setupError.title));
    expect(en.units.bytes(3), isNot(he.units.bytes(3)));
    expect(
      en.plugins.catalogTitleFallback,
      isNot(he.plugins.catalogTitleFallback),
    );
  });
}

final RegExp _hebrew = RegExp(r'[֐-׿]');

class _Literal {
  const _Literal(this.value, this.line);

  final String value;
  final int line;
}

/// מוציא את כל ליטרלי המחרוזת מקוד Dart, בלי הערות. סורק תו-תו כדי
/// ש-`//` בתוך מחרוזת (כתובת URL) לא ייחשב הערה, ולהיפך.
List<_Literal> _stringLiterals(String source) {
  final literals = <_Literal>[];
  var i = 0;
  var line = 1;

  while (i < source.length) {
    final c = source[i];

    if (c == '\n') {
      line++;
      i++;
      continue;
    }

    if (c == '/' && i + 1 < source.length) {
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
          if (source[i] == '\n') line++;
          i++;
        }
        i += 2;
        continue;
      }
    }

    if (c == "'" || c == '"') {
      final quote = c;
      final startLine = line;
      final buffer = StringBuffer();
      final isTriple = i + 2 < source.length &&
          source[i + 1] == quote &&
          source[i + 2] == quote;

      if (isTriple) {
        i += 3;
        while (i + 2 < source.length &&
            !(source[i] == quote &&
                source[i + 1] == quote &&
                source[i + 2] == quote)) {
          if (source[i] == '\n') line++;
          buffer.write(source[i]);
          i++;
        }
        i += 3;
      } else {
        i++;
        while (i < source.length && source[i] != quote && source[i] != '\n') {
          if (source[i] == r'\') {
            i += 2;
            continue;
          }
          buffer.write(source[i]);
          i++;
        }
        i++;
      }

      literals.add(_Literal(buffer.toString(), startLine));
      continue;
    }

    i++;
  }

  return literals;
}
