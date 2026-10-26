import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/tasks/transfer_rate.dart';

void main() {
  late DateTime now;
  late TransferRateMeter meter;

  setUp(() {
    now = DateTime(2026, 10, 23, 12);
    meter = TransferRateMeter(clock: () => now);
  });

  void at(int seconds, int bytes) {
    now = DateTime(2026, 10, 23, 12).add(Duration(seconds: seconds));
    meter.add(bytes);
  }

  test('אין מהירות לפני שנייה של מדידה', () {
    expect(meter.bytesPerSecond, isNull);
    at(0, 0);
    expect(meter.bytesPerSecond, isNull);
    now = now.add(const Duration(milliseconds: 500));
    meter.add(1000);
    expect(meter.bytesPerSecond, isNull);
    expect(meter.remaining(10000), isNull);
  });

  test('מהירות קבועה וזמן שנותר', () {
    at(0, 0);
    at(1, 1000);
    at(2, 2000);
    expect(meter.bytesPerSecond, closeTo(1000, 0.001));
    expect(meter.remaining(10000), const Duration(seconds: 8));
    expect(meter.remaining(2000), Duration.zero);
  });

  test('ממוצע על החלון האחרון בלבד', () {
    at(0, 0);
    for (var s = 1; s <= 10; s++) {
      at(s, s * 100);
    }
    // מכאן מהר פי עשרה; אחרי חלון שלם המדידה הישנה כבר לא נכנסת.
    for (var s = 11; s <= 20; s++) {
      at(s, 1000 + (s - 10) * 1000);
    }
    expect(meter.bytesPerSecond, closeTo(1000, 0.001));
  });

  test('מונה שירד — רכיב או קובץ חדש — מתחיל מחדש', () {
    at(0, 5000);
    at(5, 10000);
    expect(meter.bytesPerSecond, isNotNull);
    at(6, 100);
    expect(meter.bytesPerSecond, isNull);
    at(8, 2100);
    expect(meter.bytesPerSecond, closeTo(1000, 0.001));
  });

  // המהירות נמדדת עד עכשיו: שנייה בלי בייטים היא שנייה איטית יותר.
  test('דיווח חוזר של אותו מונה — המהירות יורדת, לא קופאת', () {
    at(0, 0);
    at(2, 2000);
    at(4, 2000);
    expect(meter.bytesPerSecond, closeTo(500, 0.001));
  });

  test('בלי בייט חדש כמה שניות — תקוע, בלי מהירות ובלי זמן', () {
    at(0, 0);
    at(2, 2000);
    expect(meter.isStalled, isFalse);
    now = now.add(const Duration(seconds: 6));
    expect(meter.isStalled, isTrue);
    expect(meter.bytesPerSecond, isNull);
    expect(meter.remaining(10000), isNull);
    at(9, 3000);
    expect(meter.isStalled, isFalse);
    expect(meter.bytesPerSecond, isNotNull);
  });

  test('איפוס', () {
    at(0, 0);
    at(2, 2000);
    meter.reset();
    expect(meter.bytesPerSecond, isNull);
  });
}
