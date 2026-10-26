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
      expect(formatBytes(1024 * 1024), u.megabytes('1'));
      expect(formatBytes(1024 * 1024 * 1024), u.gigabytes('1.0'));
    });

    test('MB תמיד שלם', () {
      final u = AppL10n.strings.units;
      expect(formatBytes(1024 * 1024 * 5 + 600 * 1024), u.megabytes('6'));
      expect(formatBytes(1024 * 1024 * 73), u.megabytes('73'));
    });

    test('GB עם ספרה אחת אחרי הנקודה — כמו במסד של ~1GB', () {
      final u = AppL10n.strings.units;
      expect(
        formatBytes((1.1 * 1024 * 1024 * 1024).round()),
        u.gigabytes('1.1'),
      );
      expect(formatBytes(3 * 1024 * 1024 * 1024), u.gigabytes('3.0'));
    });

    test('ערך שלילי או אבסורדי אינו מפיל את המסך', () {
      expect(formatBytes(-1), AppL10n.strings.units.bytes(-1));
      expect(formatBytes(-1024 * 1024), AppL10n.strings.units.bytes(-1048576));
      expect(
        formatBytes(1 << 50),
        AppL10n.strings.units.gigabytes('1048576.0'),
      );
    });

    test('יחידות לטיניות בשתי השפות; בעברית מבודדות, ברווח קשיח', () {
      // בלי הבידוד ה-bidi בעברית מציג "MB 403".
      const lri = '\u2066', pdi = '\u2069', nbsp = '\u00a0';
      expect(formatBytes(1024 * 1024 * 403), '${lri}403${nbsp}MB$pdi');
      expect(formatBytes(1024), '${lri}1${nbsp}KB$pdi');
      expect(formatBytes(1024 * 1024 * 1024), '${lri}1.0${nbsp}GB$pdi');
      expect(formatBytes(1024 * 1024), isNot(contains('מ״ב')));

      AppL10n.use(AppLanguage.english);
      expect(formatBytes(1), '1 byte');
      expect(formatBytes(0), '0 bytes');
      expect(formatBytes(1023), '1023 bytes');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 1024), '1 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('מהירות: MB/s, ספרה אחרי הנקודה מתחת ל-10', () {
      const mb = 1024 * 1024;
      AppL10n.use(AppLanguage.english);
      expect(formatRate(6.8 * mb), '6.8 MB/s');
      expect(formatRate(12.4 * mb), '12 MB/s');
      expect(formatRate(500 * 1024), '500 KB/s');

      AppL10n.use(AppLanguage.hebrew);
      expect(formatRate(6.8 * mb), contains('6.8\u00a0MB'));
      expect(formatRate(6.8 * mb), endsWith('/s\u2069'));
    });
  });

  group('formatBytesProgress', () {
    test('null כשעוד לא הגיע דיווח בייטים', () {
      expect(formatBytesProgress(null, 100), isNull);
      expect(formatBytesProgress(null, null), isNull);
    });

    test('הורדה שאין בה מה להוריד — בלי "0 בייט" מיותר', () {
      // כל הקבצים כבר על הכונן: היעד 0, ואין מה להציג.
      expect(formatBytesProgress(0, 0), isNull);
      expect(formatBytesProgress(0, null), isNull);
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
        u.progressOf(u.megabytes('412'), u.gigabytes('1.0')),
      );

      AppL10n.use(AppLanguage.english);
      expect(formatBytesProgress(1024, 2048), '1 KB of 2 KB');
    });
  });

  test('ליומן ול"העתק פרטים" — בלי תווי בידוד ועם רווח רגיל', () {
    final shown = formatBytes(1024 * 1024 * 403);
    expect(shown, isNot('403 MB'));
    expect(withoutBidiMarks(shown), '403 MB');
    expect(
      withoutBidiMarks(formatRate(6.8 * 1024 * 1024)),
      '6.8 MB/s',
    );
  });
}
