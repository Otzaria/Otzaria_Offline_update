import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/stage_clock.dart';

void main() {
  late DateTime now;
  StageClock clock() => StageClock(now: () => now);
  String format(String stage, String elapsed) => '$stage | $elapsed';

  setUp(() => now = DateTime(2026, 9, 17, 10, 0, 0));

  group('StageClock', () {
    test('שלב חדש מתחיל מדידה, ואותו שלב שוב אינו מאפס אותה', () {
      final c = clock();

      expect(c.start('בודק את שלמות המסד'), isTrue);
      now = now.add(const Duration(seconds: 75));
      // דיווח חוזר על אותו שלב — הזמן ממשיך לרוץ מההתחלה המקורית.
      expect(c.start('בודק את שלמות המסד'), isFalse);

      expect(c.text(format), 'בודק את שלמות המסד | 01:15');
    });

    test('שלב אחר מאפס את המונה', () {
      final c = clock();
      c.start('בודק את שלמות המסד');
      now = now.add(const Duration(seconds: 42));

      expect(c.start('כותב את המסד'), isTrue);
      expect(c.text(format), 'כותב את המסד | 00:00');
    });

    test('mm:ss מרופד גם מעל שעה', () {
      final c = clock();
      c.start('אימות');
      now = now.add(const Duration(minutes: 64, seconds: 3));

      expect(c.text(format), 'אימות | 64:03');
    });

    test('stop מכבה את המדידה', () {
      final c = clock();
      c.start('אימות');
      expect(c.isRunning, isTrue);

      c.stop();
      expect(c.isRunning, isFalse);
      // אחרי כיבוי אותו שם הוא התחלה חדשה לכל דבר.
      expect(c.start('אימות'), isTrue);
    });
  });
}
