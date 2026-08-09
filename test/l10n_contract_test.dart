import 'dart:io';

import 'package:test/test.dart';

/// AGENTS §4: כל מלל שהמשתמש רואה יושב ב-`otzaria_l10n`, לעולם לא כליטרל
/// בקוד. הבדיקה סורקת את `lib/` ומחפשת מחרוזת עם אותיות עבריות מחוץ להערה —
/// כך שני הליטרלים ש"נשכחו" ב-`_deleteRequired` לא יחזרו בשקט.
void main() {
  final hebrew = RegExp(r'[\u0590-\u05FF]');
  final quoted = RegExp('''r?'([^']*)'|r?"([^"]*)"''');

  test('אין ליטרל עברי בקוד תחת lib/', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue; // הערה — מותר בעברית
        for (final match in quoted.allMatches(line)) {
          final value = match.group(1) ?? match.group(2) ?? '';
          if (hebrew.hasMatch(value)) {
            offenders.add('${entity.path}:${i + 1}: $value');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'העבר את המחרוזות ל-otzaria_l10n:\n${offenders.join('\n')}');
  });
}
