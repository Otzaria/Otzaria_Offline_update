import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/byte_size.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// [formatBytes] נראה טריוויאלי אבל הוא מוצג בכל מד התקדמות, והחלק
/// המילולי שלו ("בייט", "X מתוך Y") מגיע מ-`otzaria_l10n` — ולכן נבדק
/// בשתי השפות.
void main() {
  setUp(() => AppL10n.use(AppLanguage.hebrew));
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  group('formatBytes — גבולות', () {
    test('מתחת ל-KB מוצג כבייטים דרך המלל המתורגם', () {
      expect(formatBytes(0), AppL10n.strings.units.bytes(0));
      expect(formatBytes(1), AppL10n.strings.units.bytes(1));
      expect(formatBytes(1023), AppL10n.strings.units.bytes(1023));
    });

    test('כפולות מדויקות של 1024', () {
      final u = AppL10n.strings.units;
      expect(formatBytes(1024), u.kilobytes('1'));
      expect(formatBytes(1024 * 512), u.kilobytes('512'));
      expect(formatBytes(1024 * 1024), u.megabytes('1.0'));
      expect(formatBytes(1024 * 1024 * 1024), u.gigabytes('1.00'));
    });

    test('ספרה אחרי הנקודה רק מתחת ל-10MB', () {
      final u = AppL10n.strings.units;
      expect(formatBytes(1024 * 1024 * 5 + 512 * 1024), u.megabytes('5.5'));
      expect(formatBytes(1024 * 1024 * 73), u.megabytes('73'));
    });

    test('ג׳יגה בשתי ספרות — כמו במסד של ~1GB', () {
      final u = AppL10n.strings.units;
      expect(
        formatBytes((1.1 * 1024 * 1024 * 1024).round()),
        u.gigabytes('1.10'),
      );
      expect(formatBytes(3 * 1024 * 1024 * 1024), u.gigabytes('3.00'));
    });

    test('ערך שלילי או אבסורדי אינו מפיל את המסך', () {
      expect(formatBytes(-1), AppL10n.strings.units.bytes(-1));
      expect(formatBytes(-1024 * 1024), AppL10n.strings.units.bytes(-1048576));
      expect(
        formatBytes(1 << 50),
        AppL10n.strings.units.gigabytes('1048576.00'),
      );
    });

    test('גם יחידות הגודל מתורגמות — לא רק המילה "בייט"', () {
      // עברית: היחידה בעברית, ובלי סימני האנגלית.
      expect(formatBytes(1024 * 1024), '1.0 מ״ב');
      expect(formatBytes(1024 * 1024), isNot(contains('MB')));

      AppL10n.use(AppLanguage.english);
      expect(formatBytes(1), '1 byte');
      expect(formatBytes(0), '0 bytes');
      expect(formatBytes(1023), '1023 bytes');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });

  group('formatBytesProgress', () {
    test('null כשעוד לא הגיע דיווח בייטים', () {
      expect(formatBytesProgress(null, 100), isNull);
      expect(formatBytesProgress(null, null), isNull);
    });

    test('בלי יעד ידוע — רק כמה ירד עד כה', () {
      final kb2 = AppL10n.strings.units.kilobytes('2');
      expect(formatBytesProgress(2048, null), kb2);
      expect(formatBytesProgress(2048, 0), kb2);
      expect(formatBytesProgress(2048, -1), kb2);
    });

    test('עם יעד — הניסוח מגיע מ-otzaria_l10n', () {
      final u = AppL10n.strings.units;
      expect(
        formatBytesProgress(1024 * 1024 * 412, 1024 * 1024 * 1024),
        u.progressOf(u.megabytes('412'), u.gigabytes('1.00')),
      );

      AppL10n.use(AppLanguage.english);
      expect(formatBytesProgress(1024, 2048), '1 KB of 2 KB');
    });
  });
}
