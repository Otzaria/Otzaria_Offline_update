import 'dart:async';

import 'package:plugins_manager/src/services/download_pool.dart';
import 'package:test/test.dart';

void main() {
  group('runPooled', () {
    test('מריץ עד maxConcurrent במקביל ולא יותר', () async {
      var running = 0;
      var peak = 0;
      final gates = List.generate(6, (_) => Completer<void>());

      final future = runPooled(
        [
          for (var i = 0; i < 6; i++)
            () async {
              running++;
              if (running > peak) peak = running;
              await gates[i].future;
              running--;
            },
        ],
        maxConcurrent: 2,
      );

      for (final gate in gates) {
        await Future<void>.delayed(Duration.zero);
        gate.complete();
      }
      await future;
      expect(peak, 2);
    });

    test('מריץ את כל המשימות', () async {
      final ran = <int>[];
      await runPooled(
        [for (var i = 0; i < 7; i++) () async => ran.add(i)],
        maxConcurrent: 3,
      );
      expect(ran..sort(), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('רשימה ריקה אינה שגיאה', () async {
      await runPooled(const [], maxConcurrent: 4);
    });

    test('maxConcurrent קטן מ-1 נכפה ל-1', () async {
      var running = 0;
      var peak = 0;
      await runPooled(
        [
          for (var i = 0; i < 3; i++)
            () async {
              running++;
              if (running > peak) peak = running;
              await Future<void>.delayed(Duration.zero);
              running--;
            },
        ],
        maxConcurrent: 0,
      );
      expect(peak, 1);
    });

    test('שגיאה נזרקת ואינה מתחילה משימות נוספות', () async {
      final started = <int>[];
      await expectLater(
        runPooled(
          [
            () async {
              started.add(0);
              throw StateError('boom');
            },
            () async => started.add(1),
          ],
          maxConcurrent: 1,
        ),
        throwsA(isA<StateError>()),
      );
      expect(started, [0]);
    });

    test('שגיאה ממתינה למשימות שכבר רצות', () async {
      var finished = false;
      final slow = Completer<void>();
      final future = runPooled(
        [
          () async {
            await slow.future;
            finished = true;
          },
          () async => throw StateError('boom'),
        ],
        maxConcurrent: 2,
      );

      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      slow.complete();
      await expectLater(future, throwsA(isA<StateError>()));
      expect(finished, isTrue);
    });
  });
}
