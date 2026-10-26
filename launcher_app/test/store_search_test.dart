// החיפוש המקומי בחנות: אותיות סופיות, ניקוד וגרשיים אינם מפריעים, וההדגשה
// נופלת על הטקסט המקורי.

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/store_search.dart';

void main() {
  test('אות סופית בשאילתה מוצאת אות רגילה בטקסט, ולהפך', () {
    expect(storeTextMatches('ערכים', normalizeStoreQuery('ערך')), isTrue);
    expect(storeTextMatches('סידורים', normalizeStoreQuery('סידורימ')), isTrue);
    expect(storeTextMatches('ספר', normalizeStoreQuery('ספר')), isTrue);
  });

  test('ניקוד, גרש וגרשיים אינם נספרים', () {
    expect(storeTextMatches('שַׁבָּת', normalizeStoreQuery('שבת')), isTrue);
    expect(storeTextMatches('רש"י', normalizeStoreQuery('רשי')), isTrue);
    expect(storeTextMatches('רשי', normalizeStoreQuery('רש״י')), isTrue);
  });

  test('בלי רישיות, ושאילתה של רווחים בלבד מתאימה לכול', () {
    expect(storeTextMatches('Zmanim', normalizeStoreQuery('ZMAN')), isTrue);
    expect(normalizeStoreQuery('   '), isEmpty);
    expect(storeTextMatches('כל דבר', normalizeStoreQuery('   ')), isTrue);
    expect(storeTextMatches('לוח', normalizeStoreQuery('סידור')), isFalse);
  });

  test('טווח ההדגשה במיקומי הטקסט המקורי — גם עם ניקוד באמצע', () {
    const text = 'לוח שַׁבָּת';
    final range = storeMatchRange(text, 'שבת')!;
    expect(text.substring(range.start, range.end), 'שַׁבָּת');

    expect(storeMatchRange('לוח שנה', 'סידור'), isNull);
    expect(storeMatchRange('לוח שנה', ''), isNull);
  });

  test('מקף עברי (־) נחשב רווח — "בית־הכנסת" נמצא ב"בית הכנסת"', () {
    expect(
      storeTextMatches('דיני בית־הכנסת', normalizeStoreQuery('בית הכנסת')),
      isTrue,
    );
    expect(
      storeTextMatches('דיני בית הכנסת', normalizeStoreQuery('בית־הכנסת')),
      isTrue,
    );
    const text = 'דיני בית־הכנסת';
    final range = storeMatchRange(text, 'בית הכנסת')!;
    expect(text.substring(range.start, range.end), 'בית־הכנסת');
  });

  // İ נעשית בשני תווים ב-lowercase; המיקומים חייבים להישאר מיושרים לטקסט.
  test('אות שמתארכת ב-lowercase אינה שוברת את טווח ההדגשה', () {
    const text = 'İstanbul מדריך';
    final range = storeMatchRange(text, 'מדריך')!;
    expect(text.substring(range.start, range.end), 'מדריך');
    final whole = storeMatchRange(text, text)!;
    expect(text.substring(whole.start, whole.end), text);
  });
}
