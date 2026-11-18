import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/concurrent_companions.dart';
import 'package:library_manager/src/services/library_update_applier.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

void main() {
  const progress = LibraryApplyProgress(
    stage: LibraryApplyStage.installingCompanions,
    statusText: 'x',
  );

  test('רץ מיד ומחזיר את התוצאה ב-join', () async {
    final gate = Completer<void>();
    var ran = false;
    final c = ConcurrentCompanions<int>(
      run: (_, _, _) async {
        ran = true;
        await gate.future;
        return 7;
      },
    )..start();

    await Future<void>.delayed(Duration.zero);
    expect(ran, isTrue);
    gate.complete();
    expect(await c.join(), 7);
  });

  test(
    'התקדמות מושתקת עד join, ואז מדווחת תווית אחת ומעבירה את השאר',
    () async {
      final seen = <LibraryApplyProgress>[];
      final gate = Completer<void>();
      final c = ConcurrentCompanions<int>(
        run: (_, emit, _) async {
          emit(progress);
          await gate.future;
          emit(progress);
          return 1;
        },
        onProgress: seen.add,
      )..start();

      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);

      final joined = c.join();
      expect(seen, hasLength(1));
      expect(seen.single.statusText, isNull);
      gate.complete();
      await joined;
      expect(seen, hasLength(2));
    },
  );

  test('התקנה שכבר הסתיימה אינה מדליקה תווית נלווים ב-join', () async {
    final seen = <LibraryApplyProgress>[];
    final c = ConcurrentCompanions<int>(
      run: (_, emit, _) async {
        emit(progress);
        return 1;
      },
      onProgress: seen.add,
    )..start();
    await Future<void>.delayed(Duration.zero);

    expect(await c.join(), 1);
    expect(seen, isEmpty);
  });

  test('כשל ההתקנה אינו נזרק לפני join ונזרק בו', () async {
    final c = ConcurrentCompanions<int>(
      run: (_, _, _) async => throw StateError('companions broke'),
    )..start();
    await Future<void>.delayed(Duration.zero);

    await expectLater(c.join(), throwsStateError);
  });

  test('abandon מבטל, ממתין לסיום ובולע את תוצאת ההתקנה', () async {
    var sawCancel = false;
    var settled = false;
    final c = ConcurrentCompanions<int>(
      run: (cancelled, _, _) async {
        while (!cancelled()) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        sawCancel = true;
        settled = true;
        throw StateError('cancelled');
      },
    )..start();

    await c.abandon();

    expect(sawCancel, isTrue);
    expect(settled, isTrue);
  });

  test('ביטול המשתמש מגיע להתקנה', () async {
    var user = false;
    final c = ConcurrentCompanions<bool>(
      run: (cancelled, _, _) async {
        while (!cancelled()) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        return true;
      },
      isCancelled: () => user,
    )..start();

    user = true;
    expect(await c.join(), isTrue);
  });

  test('dbOutcome נשאר פתוח עד join ואז מאפשר commit', () async {
    var committed = false;
    final c = ConcurrentCompanions<int>(
      run: (_, _, dbOutcome) async {
        await dbOutcome();
        committed = true;
        return 1;
      },
    )..start();

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(committed, isFalse);
    expect(await c.join(), 1);
    expect(committed, isTrue);
  });

  test('abandon גורם ל-dbOutcome לזרוק ביטול ומסמן aborted', () async {
    Object? thrown;
    final c = ConcurrentCompanions<int>(
      run: (_, _, dbOutcome) async {
        try {
          await dbOutcome();
        } catch (e) {
          thrown = e;
          rethrow;
        }
        return 1;
      },
    )..start();
    await Future<void>.delayed(Duration.zero);
    expect(c.aborted, isFalse);

    await c.abandon();

    expect(thrown, isA<PatchDownloadCancelled>());
    expect(c.aborted, isTrue);
  });

  test('start חוזר אינו מריץ פעמיים', () async {
    var runs = 0;
    final c = ConcurrentCompanions<int>(run: (_, _, _) async => ++runs)
      ..start();
    c.start();

    await c.join();
    expect(runs, 1);
    expect(c.started, isTrue);
  });
}
