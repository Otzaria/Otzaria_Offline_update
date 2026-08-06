import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/hebrew_date.dart';

void main() {
  group('HebrewDate.fromDateTime', () {
    // עוגנים היסטוריים מוכרים — כל אחד מהם תפס באג אמיתי בחישוב ההדחיות.
    const anchors = {
      '1948-05-14': "ה' באייר ה'תש\"ח", // הכרזת העצמאות
      '2023-10-07': 'כ"ב בתשרי ה\'תשפ"ד', // שמיני עצרת תשפ"ד
      '2024-03-24': 'י"ד באדר ב׳ ה\'תשפ"ד', // פורים בשנה מעוברת
      '2025-09-23': 'א\' בתשרי ה\'תשפ"ו', // ראש השנה תשפ"ו
      '2026-04-02': 'ט"ו בניסן ה\'תשפ"ו', // פסח תשפ"ו
      '2000-01-01': 'כ"ג בטבת ה\'תש"ס',
    };

    anchors.forEach((iso, expected) {
      test('$iso = $expected', () {
        expect(
            HebrewDate.fromDateTime(DateTime.parse(iso)).toString(), expected);
      });
    });

    test('ראש השנה לא נופל בימים א׳, ד׳ או ו׳ (לא אד"ו ראש)', () {
      for (var year = 5750; year <= 5820; year++) {
        var found = false;
        // סורקים את חודשי ספטמבר-אוקטובר של השנה הלועזית המקבילה.
        final civil = year - 3761;
        for (var day = DateTime.utc(civil, 9, 1);
            day.isBefore(DateTime.utc(civil, 10, 31));
            day = day.add(const Duration(days: 1))) {
          final hebrew = HebrewDate.fromDateTime(day);
          if (hebrew.year == year && hebrew.month == 7 && hebrew.day == 1) {
            found = true;
            // 0 = ראשון, 3 = רביעי, 5 = שישי
            expect(day.weekday % 7, isNot(anyOf(0, 3, 5)), reason: 'שנה $year');
          }
        }
        expect(found, isTrue, reason: 'לא נמצא א׳ בתשרי לשנת $year');
      }
    });
  });

  group('HebrewDate.toHebrewNumeral', () {
    test('יחידות ועשרות', () {
      expect(HebrewDate.toHebrewNumeral(1), "א'");
      expect(HebrewDate.toHebrewNumeral(9), "ט'");
      expect(HebrewDate.toHebrewNumeral(10), "י'");
      expect(HebrewDate.toHebrewNumeral(21), 'כ"א');
      expect(HebrewDate.toHebrewNumeral(30), "ל'");
    });

    test('טו וטז נכתבים כך ולא כי"ה/י"ו', () {
      expect(HebrewDate.toHebrewNumeral(15), 'ט"ו');
      expect(HebrewDate.toHebrewNumeral(16), 'ט"ז');
    });

    test('שנים', () {
      expect(HebrewDate.toHebrewNumeral(5786), 'ה\'תשפ"ו');
      expect(HebrewDate.toHebrewNumeral(5708), 'ה\'תש"ח');
      expect(HebrewDate.toHebrewNumeral(5760), 'ה\'תש"ס');
    });

    test('אפס ומספר מחוץ לטווח', () {
      expect(HebrewDate.toHebrewNumeral(0), '');
      expect(HebrewDate.toHebrewNumeral(12345), '12345');
    });
  });

  group('HebrewDate.format', () {
    test('מפרמט YYYY-MM-DD מה-API', () {
      expect(HebrewDate.format('2026-04-02'), 'ט"ו בניסן ה\'תשפ"ו');
    });

    test('מפרמט ISO-8601 מלא', () {
      expect(
        HebrewDate.format('2026-04-02T10:30:00.000Z'),
        'ט"ו בניסן ה\'תשפ"ו',
      );
    });

    test('קלט ריק או לא-תאריך אינו מפיל את המסך', () {
      expect(HebrewDate.format(null), '');
      expect(HebrewDate.format(''), '');
      expect(HebrewDate.format('לא תאריך'), 'לא תאריך');
    });
  });
}
