@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// מה שמצוטט במירכאות ואינו תווית בכלי: תפריטים של Windows, של אוצריא ושל
/// אתרים אחרים — המשתמש מוצא אותם שם, בשמם שם.
const _external = {
  'הוצאה בטוחה', // הסרת כונן ב-Windows
  'הפעל כמנהל', // תפריט ההקשר של Windows
  'אפשר במכשיר', // Windows Defender
  'Applications', // macOS
  'העתק נתיב', // בהגדרות אוצריא
  'ספרייה', // לשונית בהגדרות אוצריא
  'מערכת', // לשונית בהגדרות אוצריא
  'חיפוש חכם (ניסיוני)', // כרטיס בהגדרות אוצריא
  'שיפור המנגנון', // מתג ההסכמה בהגדרות אוצריא
  'קופות נוספות', // נדרים פלוס
  'צרכי רבים־קרנות', // נדרים פלוס
};

void main() {
  test('כל כפתור או דף שמצוטט בעברית קיים בשם הזה בדיוק', () {
    final source = File('lib/src/strings_he.dart').readAsStringSync();
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final labels = {
      for (final m
          in RegExp(r"String get \w+ =>\s*'([^'$]*)';").allMatches(code))
        m.group(1)!,
    };
    final quoted = [
      for (final m in RegExp(r'"([^"\n$]{1,40})"').allMatches(code))
        m.group(1)!,
    ].where((q) => RegExp('[א-ת]').hasMatch(q) || q == 'Applications');

    expect(quoted.length, greaterThan(30), reason: 'הסורק לא מצא ציטוטים');
    final unknown = {
      for (final q in quoted)
        if (!labels.contains(q) && !_external.contains(q)) q,
    };
    expect(unknown, isEmpty, reason: 'ציטוט שאינו שם של כפתור או דף');
  });
}
