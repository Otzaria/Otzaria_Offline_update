import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/offer_decline.dart';
import 'package:launcher_app/src/services/report_offer_coordinator.dart';

void main() {
  late bool taskRunning;
  late int performed;
  late bool active;
  late Future<bool?> Function(Future<bool> Function() body) runDialog;
  late ReportOfferCoordinator coordinator;

  setUp(() {
    taskRunning = false;
    performed = 0;
    active = true;
    runDialog = (body) => body();
    coordinator = ReportOfferCoordinator(
      isTaskRunning: () => taskRunning,
      isActive: () => active,
      prepare: () async => true,
      runDialog: (body) => runDialog(body),
      perform: () async => performed++,
    );
  });

  tearDown(() => coordinator.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a task that starts while the dialog waits defers the offer', () async {
    var first = true;
    runDialog = (body) async {
      if (first) {
        first = false;
        taskRunning = true;
      }
      return body();
    };

    await coordinator.request();
    expect(performed, 0);

    coordinator.resume();
    await settle();
    expect(performed, 0);

    taskRunning = false;
    coordinator.resume();
    await settle();
    expect(performed, 1);
  });

  test('a dialog queue that gave up defers the offer', () async {
    var first = true;
    runDialog = (body) async {
      if (first) {
        first = false;
        return null;
      }
      return body();
    };

    await coordinator.request();
    expect(performed, 0);

    coordinator.resume();
    await settle();
    expect(performed, 1);
  });

  test(
      'an offer is not opened when the dialog queue gave up on an inactive'
      ' shell', () async {
    runDialog = (body) async => null;
    active = false;
    await coordinator.request();
    coordinator.resume();
    await settle();
    expect(performed, 0);
  });

  test('an upload flow blocks the offer, and ending it resumes it', () async {
    coordinator.setUploadActive(true);
    await coordinator.request();
    expect(performed, 0);

    coordinator.setUploadActive(false);
    await settle();
    expect(performed, 1);
  });

  test('a second upload cannot start while one is active', () async {
    final gate = Completer<void>();
    var runs = 0;
    Future<void> run(void Function(bool) onActive) async {
      runs++;
      onActive(true);
      await gate.future;
      onActive(false);
    }

    final first = coordinator.guardedUpload(blocked: () => false, run: run);
    await settle();
    await coordinator.guardedUpload(blocked: () => false, run: run);
    expect(runs, 1);
    gate.complete();
    await first;
    await coordinator.guardedUpload(blocked: () => false, run: run);
    expect(runs, 2);
  });

  test('a blocked upload (read-only drive) never runs', () async {
    var runs = 0;
    await coordinator.guardedUpload(
      blocked: () => true,
      run: (_) async => runs++,
    );
    expect(runs, 0);
  });

  testWidgets('a launcher-initiated close holds the offer for the grace period',
      (tester) async {
    coordinator.onRunningState(running: true);
    await coordinator.holdFor(() async {
      coordinator.onRunningState(running: false);
      return true;
    });
    await tester.pump(const Duration(seconds: 2));
    expect(performed, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(performed, 1);
  });

  testWidgets('a new hold cancels the previous grace timer', (tester) async {
    coordinator.onRunningState(running: true);
    await coordinator.holdFor(() async {
      coordinator.onRunningState(running: false);
    });
    await tester.pump(const Duration(seconds: 2));
    await coordinator.holdFor(() async {});
    await tester.pump(const Duration(seconds: 2));
    expect(performed, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(performed, 1);
  });

  testWidgets('a hold that ends after dispose leaves no timer', (tester) async {
    final gate = Completer<void>();
    final holding = coordinator.holdFor(() => gate.future);
    coordinator.dispose();
    gate.complete();
    await holding;
    expect(performed, 0);
  });

  testWidgets('dispose cancels a pending grace timer', (tester) async {
    coordinator.onRunningState(running: true);
    await coordinator.holdFor(() async {
      coordinator.onRunningState(running: false);
    });
    coordinator.dispose();
    expect(performed, 0);
  });

  test('a decline also covers reports left after the count drops', () {
    final decline = OfferDecline()..mark(5);
    expect(decline.filter(5), 0);
    expect(decline.filter(6), 6);
    expect(decline.filter(2), 0);
    expect(decline.filter(3), 0);
  });
}
