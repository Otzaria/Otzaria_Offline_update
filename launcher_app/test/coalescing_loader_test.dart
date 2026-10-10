import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/coalescing_loader.dart';

void main() {
  test('בקשות חופפות מתכנסות לטעינה חוזרת אחת', () async {
    var calls = 0;
    final gate = Completer<void>();
    final loader = CoalescingLoader(() async {
      calls++;
      if (calls == 1) await gate.future;
    });

    final first = loader.run();
    for (var i = 0; i < 5; i++) {
      unawaited(loader.run());
    }
    gate.complete();
    await first;
    await pumpEventQueue();
    expect(calls, 2);
  });

  test('בקשה בכל עומק microtask אחרי הסיום אינה אובדת', () async {
    // הרגע שבין סיום הלולאה לניקוי ה-running הוא כמה microtasks; בקשה שמגיעה
    // בו הייתה אובדת. מנסים כל עומק, וכל אחד חייב להניב טעינה שנייה.
    for (var depth = 0; depth <= 12; depth++) {
      var calls = 0;
      final loader = CoalescingLoader(() async {
        calls++;
      });
      final first = loader.run();
      void later(int left) {
        if (left == 0) {
          loader.run();
        } else {
          scheduleMicrotask(() => later(left - 1));
        }
      }

      later(depth);
      await first;
      await pumpEventQueue();
      expect(calls, 2, reason: 'עומק $depth');
    }
  });

  test('לא פעיל: אין טעינה חוזרת', () async {
    var calls = 0;
    var active = true;
    final loader = CoalescingLoader(
      () async {
        calls++;
        active = false;
      },
      isActive: () => active,
    );
    final first = loader.run();
    unawaited(loader.run());
    await first;
    await pumpEventQueue();
    expect(calls, 1);
  });
}
