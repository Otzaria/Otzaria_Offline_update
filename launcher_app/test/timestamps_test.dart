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
    // חד-משמעי — וזה גם מה ש-`HebrewDate.format` כבר עושה שם.
    test('אנגלית: ISO, כמו התקדים ב-HebrewDate.format', () {
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
}
