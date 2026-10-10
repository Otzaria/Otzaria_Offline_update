import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  const he = HebrewStrings();
  const en = EnglishStrings();

  test('עברית: יחיד ורבים בהודעות השליחה', () {
    final t = he.appReports;
    expect(t.flushSentSnack(1), 'נשלח 1 דיווח');
    expect(t.flushSentSnack(3), 'נשלחו 3 דיווחים');
    expect(t.flushDroppedSnack(1, 1), contains('1 דיווח נדחה'));
    expect(t.flushDroppedSnack(2, 2), contains('2 דיווחים נדחו'));
    expect(t.flushRemainingSnack(1, 1), contains('נשאר עוד 1 דיווח'));
    expect(t.flushRemainingSnack(4, 3), contains('נשארו עוד 3 דיווחים'));
    expect(t.flushFailedSnack(1), contains('1 דיווח עדיין שמור'));
    expect(t.flushFailedSnack(2), contains('2 דיווחים'));
    expect(t.flushErrorSnack(1), contains('1 דיווח'));
    expect(t.flushErrorSnack(2), contains('2 דיווחים'));
    expect(t.flushPartialSnack(1, 1), contains('1 דיווח לא נשלח'));
    expect(t.flushPartialSnack(2, 2), contains('2 דיווחים לא נשלחו'));
    expect(t.pendingCount(1), contains('1 דיווח שמור'));
    expect(t.sentSummary(1, 1), 'נשלח 1 דיווח');
    // אף משפט אינו מכיל "1 דיווחים".
    for (final text in [
      t.flushSentSnack(1),
      t.flushDroppedSnack(1, 1),
      t.flushRemainingSnack(1, 1),
      t.flushFailedSnack(1),
      t.flushErrorSnack(1),
      t.flushPartialSnack(1, 1),
      t.pendingCount(1),
      t.sentSummary(1, 1),
    ]) {
      expect(text, isNot(contains('1 דיווחים')), reason: text);
    }
  });

  test('אנגלית: יחיד ורבים בהודעות השליחה', () {
    final t = en.appReports;
    expect(t.flushSentSnack(1), '1 report sent');
    expect(t.flushSentSnack(3), '3 reports sent');
    expect(t.flushDroppedSnack(1, 1), contains('1 report was sent'));
    expect(t.flushDroppedSnack(1, 1), contains('1 was rejected'));
    expect(t.flushDroppedSnack(2, 2), contains('2 were rejected'));
    expect(t.flushRemainingSnack(1, 1), contains('1 more is still queued'));
    expect(t.flushRemainingSnack(2, 2), contains('2 more are still queued'));
    expect(t.flushFailedSnack(1), contains('1 report is still'));
    expect(t.flushPartialSnack(1, 1), contains('1 report was not sent'));
    expect(t.flushPartialSnack(2, 2), contains('2 reports were not sent'));
    for (final text in [
      t.flushDroppedSnack(1, 1),
      t.flushRemainingSnack(1, 1),
      t.flushPartialSnack(1, 1),
    ]) {
      expect(text, isNot(contains('1 reports')), reason: text);
    }
  });
}
