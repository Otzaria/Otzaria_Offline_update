import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/sleep_inhibitor.dart';
import 'package:win32/win32.dart';

void main() {
  test('native request can be acquired and released repeatedly without leaks',
      () {
    final errors = <Object>[];
    final inhibitor = SleepInhibitor(onError: errors.add);
    int handles() => using((arena) {
          final getCount = DynamicLibrary.open('kernel32.dll').lookupFunction<
              Int32 Function(IntPtr, Pointer<Uint32>),
              int Function(int, Pointer<Uint32>)>('GetProcessHandleCount');
          final count = arena<Uint32>();
          expect(getCount(GetCurrentProcess(), count), isNonZero);
          return count.value;
        });
    inhibitor.setActive(true);
    expect(errors, isEmpty);
    expect(inhibitor.isActive, isTrue);
    inhibitor.setActive(false);
    final before = Platform.isWindows ? handles() : 0;
    for (var i = 0; i < 500; i++) {
      inhibitor.setActive(true);
      expect(inhibitor.isActive, isTrue);
      inhibitor.setActive(false);
      expect(inhibitor.isActive, isFalse);
    }
    inhibitor.dispose();
    expect(errors, isEmpty);
    // הספירה היא של כל התהליך, ו-thread pool של ה-VM פותח לפעמים handle
    // באמצע. דליפה אמיתית כאן הייתה +500 (אחד לכל סבב).
    if (Platform.isWindows) expect(handles(), lessThanOrEqualTo(before + 8));
  }, skip: !Platform.isWindows && !Platform.isMacOS);

  test('10000 random overlapping task transitions preserve ownership', () {
    final tasks = <int>{};
    var acquired = 0;
    var released = 0;
    final inhibitor = SleepInhibitor(acquire: () {
      acquired++;
      return () => released++;
    });
    final random = Random(20261014);
    for (var i = 0; i < 10000; i++) {
      final id = random.nextInt(12);
      if (random.nextBool()) {
        tasks.add(id);
      } else {
        tasks.remove(id);
      }
      inhibitor.setActive(tasks.isNotEmpty);
      expect(acquired - released, tasks.isEmpty ? 0 : 1);
    }
    inhibitor.dispose();
    expect(acquired, released);
  });

  test('idle does not acquire; repeated updates hold just one request', () {
    var acquired = 0;
    var released = 0;
    final inhibitor = SleepInhibitor(acquire: () {
      acquired++;
      return () => released++;
    });
    inhibitor.setActive(false);
    expect(acquired, 0);
    for (var i = 0; i < 1000; i++) {
      inhibitor.setActive(true);
    }
    expect(acquired, 1);
    expect(inhibitor.isActive, isTrue);
    inhibitor.setActive(false);
    inhibitor.setActive(false);
    expect(released, 1);
    expect(inhibitor.isActive, isFalse);
    inhibitor.setActive(true);
    inhibitor.dispose();
    inhibitor.dispose();
    inhibitor.setActive(true);
    expect(acquired, 2);
    expect(released, 2);
  });

  test('failed acquisition does not stop updates and can be retried', () {
    var attempts = 0;
    final errors = <Object>[];
    final inhibitor = SleepInhibitor(
      acquire: () {
        if (++attempts == 1) throw StateError('acquire');
        return () {};
      },
      onError: errors.add,
    );
    inhibitor.setActive(true);
    expect(inhibitor.isActive, isFalse);
    expect(errors, hasLength(1));
    inhibitor.setActive(true);
    expect(inhibitor.isActive, isTrue);
    inhibitor.dispose();
  });

  test('failed release retains ownership for a later retry', () {
    var attempts = 0;
    final errors = <Object>[];
    final inhibitor = SleepInhibitor(
      acquire: () => () {
        if (++attempts == 1) throw StateError('release');
      },
      onError: errors.add,
    );
    inhibitor.setActive(true);
    inhibitor.setActive(false);
    expect(errors, hasLength(1));
    expect(inhibitor.isActive, isTrue);
    inhibitor.setActive(false);
    expect(inhibitor.isActive, isFalse);
    inhibitor.dispose();
  });
}
