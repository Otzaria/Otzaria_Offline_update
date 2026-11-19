import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/background_priority.dart';

void main() {
  late List<bool> calls;
  late List<String> warns;
  late bool ok;

  BackgroundPriority make() => BackgroundPriority(
        platformSwitch: (enter) {
          calls.add(enter);
          return ok;
        },
        onSwitch: (enter, ok) {
          if (!ok) warns.add(enter ? 'enter' : 'leave');
        },
      );

  setUp(() {
    calls = [];
    warns = [];
    ok = true;
  });

  test('enters on 0 to 1 and leaves on 1 to 0 only', () {
    final bp = make();
    final a = bp.acquire();
    final b = bp.acquire();
    expect(calls, [true]);
    a();
    expect(calls, [true]);
    b();
    expect(calls, [true, false]);
    expect(bp.isActive, isFalse);
  });

  test('release is idempotent', () {
    final bp = make();
    final a = bp.acquire();
    final b = bp.acquire();
    a();
    a();
    expect(bp.leases, 1);
    expect(bp.isActive, isTrue);
    b();
    expect(calls, [true, false]);
  });

  test('a child starts at the normal class and the lease resumes after',
      () async {
    final bp = make();
    final release = bp.acquire();
    bool? loweredDuringStart;
    await bp.aroundChildStart(() async => loweredDuringStart = bp.isActive);
    expect(loweredDuringStart, isFalse);
    expect(bp.isActive, isTrue);
    expect(calls, [true, false, true]);
    release();
    expect(calls, [true, false, true, false]);
  });

  test('the log follows the leases, not the lift around a child start',
      () async {
    final seen = <(bool, bool)>[];
    final bp = BackgroundPriority(
      platformSwitch: (_) => true,
      onSwitch: (lower, ok) => seen.add((lower, ok)),
    );
    final release = bp.acquire();
    await bp.aroundChildStart(() async {});
    expect(seen, [(true, true)]);
    late void Function() second;
    await bp.aroundChildStart(() async {
      release();
      second = bp.acquire();
    });
    second();
    expect(seen, [(true, true), (false, true), (true, true), (false, true)]);
  });

  test('a child start without a lease touches nothing', () async {
    final bp = make();
    await bp.aroundChildStart(() async {});
    expect(calls, isEmpty);
  });

  test('a failing child start still restores the lease', () async {
    final bp = make();
    bp.acquire();
    await expectLater(
      bp.aroundChildStart<void>(() async => throw StateError('spawn')),
      throwsStateError,
    );
    expect(bp.isActive, isTrue);
  });

  test('a lease taken during a child start waits for it', () async {
    final bp = make();
    late void Function() release;
    await bp.aroundChildStart(() async => release = bp.acquire());
    expect(calls, [true]);
    release();
    expect(calls, [true, false]);
  });

  test('failed enter warns, never throws, and does not try to leave', () {
    ok = false;
    final bp = make();
    bp.acquire()();
    expect(calls, [true]);
    expect(warns, hasLength(1));
  });

  test('a throwing platform hook is swallowed', () {
    final bp = BackgroundPriority(
      platformSwitch: (_) => throw StateError('ffi'),
      onSwitch: (enter, ok) {
        if (!ok) warns.add(enter ? 'enter' : 'leave');
      },
    );
    bp.acquire()();
    expect(warns, hasLength(1));
    expect(bp.leases, 0);
  });
}
