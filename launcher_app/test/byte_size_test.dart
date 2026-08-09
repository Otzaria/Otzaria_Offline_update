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
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 512), '512 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });

    test('ספרה אחרי הנקודה רק מתחת ל-10MB', () {
      expect(formatBytes(1024 * 1024 * 5 + 512 * 1024), '5.5 MB');
      expect(formatBytes(1024 * 1024 * 73), '73 MB');
    });

    test('ג׳יגה בשתי ספרות — כמו במסד של ~1GB', () {
      expect(formatBytes((1.1 * 1024 * 1024 * 1024).round()), '1.10 GB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('ערך שלילי או אבסורדי אינו מפיל את המסך', () {
      expect(formatBytes(-1), AppL10n.strings.units.bytes(-1));
      expect(formatBytes(-1024 * 1024), AppL10n.strings.units.bytes(-1048576));
      expect(formatBytes(1 << 50), endsWith('GB'));
    });

    test('אנגלית: היחידה המילולית מתחלפת, המספרים לא', () {
      AppL10n.use(AppLanguage.english);

      expect(formatBytes(1), '1 byte');
      expect(formatBytes(0), '0 bytes');
      expect(formatBytes(1023), '1023 bytes');
      // KB/MB/GB אינם מתורגמים — הם אותם סמלים בשתי השפות.
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
    });
  });

  group('formatBytesProgress', () {
    test('null כשעוד לא הגיע דיווח בייטים', () {
      expect(formatBytesProgress(null, 100), isNull);
      expect(formatBytesProgress(null, null), isNull);
    });

    test('בלי יעד ידוע — רק כמה ירד עד כה', () {
      expect(formatBytesProgress(2048, null), '2 KB');
      expect(formatBytesProgress(2048, 0), '2 KB');
      expect(formatBytesProgress(2048, -1), '2 KB');
    });

    test('עם יעד — הניסוח מגיע מ-otzaria_l10n', () {
      expect(
        formatBytesProgress(1024 * 1024 * 412, 1024 * 1024 * 1024),
        AppL10n.strings.units.progressOf('412 MB', '1.00 GB'),
      );

      AppL10n.use(AppLanguage.english);
      expect(formatBytesProgress(1024, 2048), '1 KB of 2 KB');
    });
  });
}
