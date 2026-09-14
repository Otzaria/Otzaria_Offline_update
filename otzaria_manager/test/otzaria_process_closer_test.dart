import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

/// בדיקת התהליך היא של מערכת ההפעלה, ולכן נבדק כאן מה שאינו תלוי בה:
/// שאוצריא שאינה רצה אינה מייצרת בקשת סגירה בכלל, ושבקשה שהתהליך שרד
/// מסתיימת ב-`false` במקום להמתין בלי סוף.
class _FakeLocator extends RunningOtzariaLocator {
  _FakeLocator(this.running);

  final bool running;
  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    probes++;
    return (isRunning: running, launchPath: null);
  }
}

void main() {
  test('אוצריא סגורה — מדווח הצלחה בלי לנסות לסגור', () async {
    final locator = _FakeLocator(false);

    expect(await OtzariaProcessCloser(locator: locator).close(), isTrue);
    expect(locator.probes, 1);
  });

  test('תהליך ששרד את הבקשה — כישלון בתום ההמתנה', () async {
    final locator = _FakeLocator(true);
    var requests = 0;

    final closed = await OtzariaProcessCloser(
      locator: locator,
      sendCloseRequest: (_) async => requests++,
    ).close(timeout: const Duration(milliseconds: 500));

    expect(requests, 1);

    expect(closed, isFalse);
    // נבדק שוב ושוב בזמן ההמתנה, ולא רק פעם אחת בהתחלה.
    expect(locator.probes, greaterThan(1));
  });
}
