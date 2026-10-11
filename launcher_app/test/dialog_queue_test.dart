import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/dialog_queue.dart';

void main() {
  late bool active;
  late bool blocked;

  setUp(() {
    active = true;
    blocked = false;
  });

  DialogQueue newQueue() =>
      DialogQueue(isActive: () => active, isBlocked: () => blocked);

  test('runs at once when nothing blocks it', () {
    fakeAsync((async) {
      final queue = newQueue();
      String? result;
      queue.run(() async => 'shown').then((value) => result = value);
      async.flushMicrotasks();
      expect(result, 'shown');
    });
  });

  test('two bodies never overlap: the second waits for the first', () {
    fakeAsync((async) {
      final queue = newQueue();
      final log = <String>[];
      queue.run(() async {
        log.add('first start');
        await Future<void>.delayed(const Duration(seconds: 5));
        log.add('first end');
      });
      queue.run(() async => log.add('second'));

      async.flushMicrotasks();
      expect(log, ['first start']);

      async.elapse(const Duration(seconds: 5));
      expect(log, ['first start', 'first end', 'second']);
    });
  });

  test('waits while blocked and runs once it clears', () {
    fakeAsync((async) {
      final queue = newQueue();
      blocked = true;
      var shown = false;
      queue.run(() async => shown = true);

      async.elapse(const Duration(seconds: 30));
      expect(shown, isFalse);

      blocked = false;
      async.elapse(const Duration(milliseconds: 500));
      expect(shown, isTrue);
    });
  });

  test('gives up after a minute and lets the next one try', () {
    fakeAsync((async) {
      final queue = newQueue();
      blocked = true;
      var done = false;
      Object? result = 'pending';
      var nextShown = false;
      queue.run(() async => 'shown').then((value) {
        done = true;
        result = value;
      });
      queue.run(() async => nextShown = true);

      async.elapse(const Duration(seconds: 59));
      expect(done, isFalse);

      async.elapse(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(result, isNull);

      blocked = false;
      async.elapse(const Duration(milliseconds: 500));
      expect(nextShown, isTrue);
    });
  });

  test('forever keeps waiting past the minute', () {
    fakeAsync((async) {
      final queue = newQueue();
      blocked = true;
      var shown = false;
      queue.run(() async => shown = true, forever: true);

      async.elapse(const Duration(minutes: 5));
      expect(shown, isFalse);

      blocked = false;
      async.elapse(const Duration(milliseconds: 500));
      expect(shown, isTrue);
    });
  });

  test('an inactive shell shows nothing', () {
    fakeAsync((async) {
      final queue = newQueue();
      active = false;
      var shown = false;
      Object? result = 'pending';
      queue.run(() async => shown = true).then((value) => result = value);
      async.flushMicrotasks();
      expect(shown, isFalse);
      expect(result, isNull);
    });
  });

  test('dispose wakes a waiting body, which then gives up', () {
    fakeAsync((async) {
      final queue = newQueue();
      blocked = true;
      Object? result = 'pending';
      queue.run(() async => 'shown').then((value) => result = value);
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1));

      active = false;
      queue.dispose();
      async.flushMicrotasks();
      expect(result, isNull);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
