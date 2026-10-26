import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/timestamps.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// חותמות הזמן של המסגרת. היו שני מעצבים inline בשני מסכים, כל אחד בפורמט
/// אחר — הבדיקה הזאת היא מה שמחזיק את ההתנהגות במקום אחד.
void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  /// זמן מקומי במפורש: המעצבים קוראים ל-`toLocal()`, ובדיקה שבונה UTC הייתה
  /// נכשלת או עוברת לפי אזור הזמן של המכונה שמריצה אותה.
  final noon = DateTime(2026, 8, 3, 14, 5, 9);

  group('formatClock', () {
    test('שעון 24 שעות עם ריפוד אפס', () {
      expect(formatClock(noon), '14:05');
      expect(formatClock(DateTime(2026, 1, 1, 0, 0)), '00:00');
      expect(formatClock(DateTime(2026, 1, 1, 9, 7)), '09:07');
    });

    test('אינו תלוי בשפה — שעון 24 חד-משמעי בשתיהן', () {
      AppL10n.use(AppLanguage.hebrew);
      final he = formatClock(noon);
      AppL10n.use(AppLanguage.english);
      expect(formatClock(noon), he);
    });
  });

  group('formatTimestamp', () {
    test('עברית: dd.mm.yyyy עם שעה מלאה', () {
      AppL10n.use(AppLanguage.hebrew);
      expect(formatTimestamp(noon), '03.08.2026, 14:05:09');
    });

    // באנגלית `03.08.2026` נקרא כ-3 באוגוסט או כ-8 במרץ, תלוי בקורא. ISO
    // חד-משמעי.
    test('אנגלית: ISO', () {
      AppL10n.use(AppLanguage.english);
      expect(formatTimestamp(noon), '2026-08-03 14:05:09');
    });

    test('כל השדות מרופדים לשתי ספרות', () {
      AppL10n.use(AppLanguage.hebrew);
      expect(formatTimestamp(DateTime(2026, 1, 2, 3, 4, 5)),
          '02.01.2026, 03:04:05');
      AppL10n.use(AppLanguage.english);
      expect(formatTimestamp(DateTime(2026, 1, 2, 3, 4, 5)),
          '2026-01-02 03:04:05');
    });

    test('שתי השפות מכילות את אותם מספרים, בסדר אחר', () {
      AppL10n.use(AppLanguage.hebrew);
      final he = formatTimestamp(noon);
      AppL10n.use(AppLanguage.english);
      final en = formatTimestamp(noon);

      expect(he, isNot(en));
      List<String> digitsOf(String s) =>
          RegExp(r'\d+').allMatches(s).map((m) => m.group(0)!).toList()..sort();
      expect(digitsOf(he), digitsOf(en));
    });
  });

  group('formatStoreDate — תאריכי החנויות', () {
    test('עברית: תאריך עברי כמו באתר; אנגלית: לועזי בשם חודש', () {
      AppL10n.use(AppLanguage.hebrew);
      expect(formatStoreDate(DateTime(2026, 10, 20, 12)), 'ט\' חשוון ה\'תשפ"ז');
      AppL10n.use(AppLanguage.english);
      expect(formatStoreDate(DateTime(2026, 10, 20, 12)), 'October 20, 2026');
    });

    test('מחרוזת מה-API: תאריך בלבד אינו זז, ומה שאינו תאריך חוזר כמות שהוא',
        () {
      for (final language in AppLanguage.values) {
        AppL10n.use(language);
        expect(formatStoreDateRaw(''), '');
        expect(formatStoreDateRaw(null), '');
        expect(formatStoreDateRaw('לא תאריך'), 'לא תאריך');
        expect(formatStoreDateRaw('02/04/2026'), '02/04/2026');
      }
      AppL10n.use(AppLanguage.hebrew);
      expect(formatStoreDateRaw('2026-01-01'), 'י"ב טבת ה\'תשפ"ו');
      expect(
          formatStoreDateRaw('2026-04-02T10:30:00.000Z'), 'ט"ו ניסן ה\'תשפ"ו');
      AppL10n.use(AppLanguage.english);
      expect(formatStoreDateRaw('2026-01-01'), 'January 1, 2026');
    });

    test('רגע מלא נקרא ב-UTC, כמו בחנות שבאתר — לא לפי השעון המקומי', () {
      AppL10n.use(AppLanguage.hebrew);
      // בישראל זה כבר 2/4 (ט"ו בניסן); באתר — 1/4.
      expect(formatStoreDateRaw('2026-04-01T22:30:00Z'), 'י"ד ניסן ה\'תשפ"ו');
      expect(
        formatStoreDate(DateTime.utc(2026, 4, 1, 22, 30)),
        'י"ד ניסן ה\'תשפ"ו',
      );
    });

    test('רגע שנרשם במחשב הזה נקרא בלוח המקומי — גם אחרי חצות', () {
      // שדות מקומיים: היום יוצא 24/10 בכל אזור זמן; ב-UTC בישראל זה עדיין 23/10.
      final afterMidnight = DateTime(2026, 10, 24, 0, 30);
      AppL10n.use(AppLanguage.hebrew);
      expect(formatStoreLocalDate(afterMidnight), 'י"ג חשוון ה\'תשפ"ז');
      // כך הוא נשמר ונקרא מהקובץ — ISO בלי היסט, ונקרא כמקומי.
      expect(
        formatStoreLocalDate(DateTime.parse(afterMidnight.toIso8601String())),
        'י"ג חשוון ה\'תשפ"ז',
      );
      AppL10n.use(AppLanguage.english);
      expect(formatStoreLocalDate(afterMidnight), 'October 24, 2026');
    });
  });
}
