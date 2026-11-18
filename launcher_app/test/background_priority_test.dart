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

  test('run releases when the body throws', () async {
    final bp = make();
    await expectLater(
      bp.run<void>(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(calls, [true, false]);
    expect(bp.leases, 0);
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
