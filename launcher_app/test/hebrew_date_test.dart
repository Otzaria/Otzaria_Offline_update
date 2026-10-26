import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/hebrew_date.dart';

void main() {
  group('HebrewDate.fromDateTime', () {
    // עוגנים היסטוריים מוכרים — כל אחד מהם תפס באג אמיתי בחישוב ההדחיות.
    // הערכים הם הפלט של `formatHebrewDate` בחנות התוספים באתר (src/lib/hebrewDate.ts).
    const anchors = {
      '1948-05-14': 'ה\' אייר ה\'תש"ח', // הכרזת העצמאות
      '2023-10-07': 'כ"ב תשרי ה\'תשפ"ד', // שמיני עצרת תשפ"ד
      '2024-03-24': 'י"ד אדר ב׳ ה\'תשפ"ד', // פורים בשנה מעוברת
      '2025-09-23': 'א\' תשרי ה\'תשפ"ו', // ראש השנה תשפ"ו
      '2026-04-02': 'ט"ו ניסן ה\'תשפ"ו', // פסח תשפ"ו
      '2000-01-01': 'כ"ג טבת ה\'תש"ס',
      '2026-10-20': 'ט\' חשוון ה\'תשפ"ז',
      '2025-06-01': 'ה\' סיוון ה\'תשפ"ה',
      '2027-02-15': 'ח\' אדר א׳ ה\'תשפ"ז',
      // שנים שבהן קבוע המולד השגוי (11 במקום 5 שעות) הסיט יום או שניים.
      '2008-04-20': 'ט"ו ניסן ה\'תשס"ח',
      '2008-09-30': 'א\' תשרי ה\'תשס"ט',
      '2001-12-10': 'כ"ה כסלו ה\'תשס"ב',
      '2018-09-10': 'א\' תשרי ה\'תשע"ט',
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

  group('שנים מעוברות ושמות חודשים', () {
    test('isLeapYear לפי מחזור ה-19', () {
      // 7 שנים מעוברות בכל מחזור: ג, ו, ח, יא, יד, יז, יט.
      const leap = {5784, 5787, 5790, 5793, 5795, 5798, 5801};
      for (var year = 5784; year <= 5802; year++) {
        expect(HebrewDate.isLeapYear(year), leap.contains(year),
            reason: 'שנת $year');
      }
    });

    test('אדר נקרא "אדר א׳" רק בשנה מעוברת', () {
      expect(const HebrewDate(5784, 12, 15).monthName, 'אדר א׳');
      expect(const HebrewDate(5785, 12, 15).monthName, 'אדר');
      expect(const HebrewDate(5784, 13, 14).monthName, 'אדר ב׳');
    });

    test('כל שנים-עשר שמות החודשים מופיעים במחזור שנה', () {
      final names = <String>{};
      for (var day = DateTime.utc(2025, 9, 23);
          day.isBefore(DateTime.utc(2026, 9, 12));
          day = day.add(const Duration(days: 1))) {
        names.add(HebrewDate.fromDateTime(day).monthName);
      }

      expect(names, {
        'תשרי',
        'חשוון',
        'כסלו',
        'טבת',
        'שבט',
        'אדר',
        'ניסן',
        'אייר',
        'סיוון',
        'תמוז',
        'אב',
        'אלול',
      });
    });

    test('אורך השנה העברית הוא אחד מששת הערכים החוקיים', () {
      DateTime roshHashana(int hebrewYear) {
        final civil = hebrewYear - 3761;
        for (var day = DateTime.utc(civil, 8, 25);
            day.isBefore(DateTime.utc(civil, 11, 5));
            day = day.add(const Duration(days: 1))) {
          final hebrew = HebrewDate.fromDateTime(day);
          if (hebrew.year == hebrewYear &&
              hebrew.month == 7 &&
              hebrew.day == 1) {
            return day;
          }
        }
        throw StateError('לא נמצא א׳ בתשרי לשנת $hebrewYear');
      }

      var previous = roshHashana(5780);
      for (var year = 5781; year <= 5800; year++) {
        final current = roshHashana(year);
        final length = current.difference(previous).inDays;
        expect(
          length,
          anyOf(353, 354, 355, 383, 384, 385),
          reason: 'אורך שנת ${year - 1} יצא $length',
        );
        // שנה מעוברת ארוכה תמיד — זו כל מטרתו של אדר ב׳.
        expect(length >= 383, HebrewDate.isLeapYear(year - 1),
            reason: 'שנת ${year - 1}');
        previous = current;
      }
    });

    test('ימים לועזיים רצופים = ימים עבריים רצופים', () {
      var previous = HebrewDate.fromDateTime(DateTime.utc(2026, 1, 1));
      for (var day = DateTime.utc(2026, 1, 2);
          day.isBefore(DateTime.utc(2027, 1, 1));
          day = day.add(const Duration(days: 1))) {
        final current = HebrewDate.fromDateTime(day);
        final continued = current.day == previous.day + 1;
        // או שהתחיל חודש חדש — ואז היום הוא 1 והחודש הקודם נגמר ב-29/30.
        final newMonth =
            current.day == 1 && (previous.day == 29 || previous.day == 30);
        expect(continued || newMonth, isTrue,
            reason: '$previous → $current ב-$day');
        previous = current;
      }
    });

    test('שעת היום אינה משנה את התאריך — אין מודל של שקיעה', () {
      // מכוון: התאריך משמש לתצוגת "עודכן ב-" בחנות, לא לזמני היום.
      final morning = HebrewDate.fromDateTime(DateTime(2026, 4, 2, 6));
      final night = HebrewDate.fromDateTime(DateTime(2026, 4, 2, 23, 59));

      expect(morning.toString(), night.toString());
      expect(morning.toString(), 'ט"ו ניסן ה\'תשפ"ו');
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

    test('מספר שלילי מוחזר ריק ולא זורק', () {
      expect(HebrewDate.toHebrewNumeral(-5), '');
    });

    test('מאות, כולל אלה שאין להן אות משלהן', () {
      expect(HebrewDate.toHebrewNumeral(100), "ק'");
      expect(HebrewDate.toHebrewNumeral(400), "ת'");
      expect(HebrewDate.toHebrewNumeral(500), 'ת"ק');
      expect(HebrewDate.toHebrewNumeral(700), 'ת"ש');
      expect(HebrewDate.toHebrewNumeral(900), 'תת"ק');
    });

    test('גבול העליון של הטווח', () {
      expect(HebrewDate.toHebrewNumeral(9999), isNot('9999'));
      expect(HebrewDate.toHebrewNumeral(10000), '10000');
    });
  });
}
