import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/search_feedback_controller.dart';
import 'package:launcher_app/src/services/search_feedback_auto_sync.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

/// תור קיים בזיכרון: בדיקות הזרימה אינן תלויות בדיסק או בשרת.
class _MemoryFeedback extends SearchFeedbackTransport {
  _MemoryFeedback()
      : super('unused',
            client: MockClient((_) async => http.Response('{}', 200)));

  int sourceEvents = 2;
  int carriedEvents = 0;
  int collections = 0;
  int uploads = 0;
  bool online = true;
  bool throwOnCollect = false;
  bool throwOnUpload = false;
  DateTime? storedRetryAt;
  Duration? offlineRetry = const Duration(minutes: 2);
  Completer<void>? uploadGate;
  Completer<void>? collectGate;
  bool stopped = false;
  int stops = 0;

  @override
  Future<int> pendingForCollection(String sourceDirectory) async =>
      sourceEvents;

  @override
  Future<int> count() async => carriedEvents;

  @override
  Future<int> collect(String sourceDirectory,
      {required Future<bool> Function() mayCollect}) async {
    collections++;
    if (throwOnCollect) throw const FileSystemException('drive full');
    await collectGate?.future;
    if (!await mayCollect()) return 0;
    final collected = sourceEvents;
    carriedEvents += collected;
    sourceEvents = 0;
    return collected;
  }

  @override
  Future<DateTime?> retryAt() async => storedRetryAt;

  @override
  void stop() {
    stopped = true;
    stops++;
    final gate = uploadGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<SearchFeedbackUploadResult> upload() async {
    uploads++;
    stopped = false;
    await uploadGate?.future;
    if (stopped) return (sent: 0, rejected: 0, remaining: carriedEvents);
    if (throwOnUpload) throw StateError('boom');
    if (!online) {
      final delay = offlineRetry;
      storedRetryAt = delay == null ? null : DateTime.now().add(delay);
      return (sent: 0, rejected: 0, remaining: carriedEvents);
    }
    final sent = carriedEvents;
    carriedEvents = 0;
    storedRetryAt = null;
    return (sent: sent, rejected: 0, remaining: 0);
  }
}

class _RunningOtzaria extends RunningOtzariaLocator {
  const _RunningOtzaria();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: true, launchPath: null);
}

void main() {
  late _MemoryFeedback transport;
  late SearchFeedbackController controller;
  var consent = true;
  var otzariaOpen = false;
  late List<String> printed;
  DebugPrintCallback? previousPrint;

  setUp(() {
    consent = true;
    otzariaOpen = false;
    transport = _MemoryFeedback();
    controller = SearchFeedbackController(
      transport: transport,
      resolveSource: () async => consent && !otzariaOpen ? 'source' : null,
    );
    printed = [];
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
  });

  tearDown(() {
    debugPrint = previousPrint!;
    controller.dispose();
  });

  group('synchronize — no prompt, no message', () {
    test('collects available feedback and uploads it in one run', () async {
      expect(await controller.synchronize(), isNull);
      expect(transport.collections, 1);
      expect(transport.uploads, 1);
      expect(transport.sourceEvents, 0);
      expect(transport.carriedEvents, 0);
      expect(printed.where((m) => m.startsWith('UiSnack')), isEmpty);
    });

    test('uploads what the drive already carries with nothing to collect',
        () async {
      transport
        ..sourceEvents = 0
        ..carriedEvents = 3;
      expect(await controller.synchronize(), isNull);
      expect(transport.collections, 0);
      expect(transport.uploads, 1);
      expect(transport.carriedEvents, 0);
    });

    test('without consent nothing is collected or sent', () async {
      consent = false;
      expect(await controller.synchronize(), isNull);
      expect(transport.collections, 0);
      expect(transport.uploads, 0);
      expect(transport.sourceEvents, 2);
    });

    test('carried feedback uploads without Otzaria on the online PC', () async {
      transport.carriedEvents = 3;
      final onlineController = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
        consentState: () async => SearchFeedbackConsent.unknown,
      );
      expect(await onlineController.synchronize(), isNull);
      expect(transport.collections, 0);
      expect(transport.uploads, 1);
      expect(transport.carriedEvents, 0);
    });

    test('explicitly revoked consent blocks carried feedback upload', () async {
      transport.carriedEvents = 3;
      final onlineController = SearchFeedbackController(
        transport: transport,
        resolveSource: () async => null,
        consentState: () async => SearchFeedbackConsent.revoked,
      );
      expect(await onlineController.synchronize(), isNull);
      expect(transport.collections, 0);
      expect(transport.uploads, 0);
      expect(transport.carriedEvents, 3);
    });

    test('Otzaria open: no collection; collected once it closes', () async {
      otzariaOpen = true;
      expect(await controller.synchronize(), isNull);
      expect(transport.collections, 0);
      expect(transport.sourceEvents, 2);
      otzariaOpen = false;
      expect(await controller.synchronize(), isNull);
      expect(transport.sourceEvents, 0);
      expect(transport.uploads, 1);
    });

    test('no network keeps the data and waits for the stored backoff',
        () async {
      transport.online = false;
      final delay = await controller.synchronize();
      expect(transport.carriedEvents, 2);
      expect(delay, isNotNull);
      expect(delay! > const Duration(minutes: 1), isTrue);
      expect(delay <= const Duration(minutes: 2), isTrue);
      expect(printed.where((m) => m.startsWith('UiSnack')), isEmpty);

      transport.online = true;
      transport.storedRetryAt = null;
      expect(await controller.synchronize(), isNull);
      expect(transport.carriedEvents, 0);
    });

    for (final (stored, expected) in [
      (const Duration(seconds: 1), SearchFeedbackController.minRetry),
      (null, null),
    ]) {
      test('backoff $stored never becomes a tight loop', () async {
        transport
          ..online = false
          ..offlineRetry = stored;
        expect(await controller.synchronize(), expected);
        expect(transport.carriedEvents, 2);
      });
    }

    test('a failed upload is logged only and retried later', () async {
      transport.throwOnUpload = true;
      expect(
          await controller.synchronize(), SearchFeedbackController.idleRetry);
      expect(transport.carriedEvents, 2);
      expect(controller.isUploading, isFalse);
      expect(printed.where((m) => m.startsWith('UiSnack')), isEmpty);
    });

    test('a failed collection still uploads what is already carried', () async {
      transport
        ..throwOnCollect = true
        ..carriedEvents = 1;
      expect(await controller.synchronize(), isNull);
      expect(transport.uploads, 1);
      expect(transport.sourceEvents, 2);
      expect(controller.isCollecting, isFalse);
    });

    test('runs never overlap', () async {
      transport.uploadGate = Completer<void>();
      final first = controller.synchronize();
      await pumpEventQueue();
      expect(controller.isUploading, isTrue);
      expect(await controller.synchronize(), isNull);
      expect(await controller.collect(), 0);
      transport.uploadGate!.complete();
      await first;
      expect(transport.collections, 1);
      expect(transport.uploads, 1);
    });

    test('after dispose nothing runs', () async {
      final disposed = SearchFeedbackController(
        transport: _MemoryFeedback(),
        resolveSource: () async => 'source',
      );
      final memory = disposed.transport as _MemoryFeedback;
      disposed.dispose();
      expect(await disposed.synchronize(), isNull);
      expect(memory.collections, 0);
      expect(memory.uploads, 0);
    });

    test('an orderly stop ends the upload, keeps the queue and retries soon',
        () async {
      transport.uploadGate = Completer<void>();
      final run = controller.synchronize();
      await pumpEventQueue();
      expect(controller.isUploading, isTrue);
      await controller.stopAndWait();
      expect(controller.isUploading, isFalse);
      expect(transport.carriedEvents, 2);
      expect(transport.storedRetryAt, isNull);
      expect(await run, SearchFeedbackController.minRetry);
      expect(printed.where((m) => m.startsWith('UiSnack')), isEmpty);
    });

    test('a stop during collection skips the upload', () async {
      transport.collectGate = Completer<void>();
      final run = controller.synchronize();
      await pumpEventQueue();
      expect(controller.isCollecting, isTrue);
      final stopping = controller.stopAndWait();
      transport.collectGate!.complete();
      await stopping;
      expect(await run, SearchFeedbackController.minRetry);
      expect(transport.carriedEvents, 2);
      expect(transport.uploads, 0);
    });

    test('a stop while counting skips the collection', () async {
      final counting = Completer<void>();
      final c = SearchFeedbackController(
        transport: transport,
        resolveSource: () async {
          await counting.future;
          return 'source';
        },
      );
      addTearDown(c.dispose);
      final run = c.synchronize();
      await pumpEventQueue();
      final stopping = c.stopAndWait();
      counting.complete();
      await stopping;
      expect(await run, SearchFeedbackController.minRetry);
      expect(transport.collections, 0);
      expect(transport.sourceEvents, 2);
      expect(transport.uploads, 0);
    });

    test('stopping with nothing running does nothing', () async {
      await controller.stopAndWait();
      expect(transport.stops, 0);
      expect(await controller.synchronize(), isNull);
      expect(transport.uploads, 1);
    });

    test('dispose during an upload stops the run without a retry', () async {
      final local = _MemoryFeedback()..uploadGate = Completer<void>();
      final c = SearchFeedbackController(
        transport: local,
        resolveSource: () async => 'source',
      );
      final run = c.synchronize();
      await pumpEventQueue();
      expect(c.isUploading, isTrue);
      c.dispose();
      expect(local.stops, 1);
      expect(await run, isNull);
    });
  });

  group('SearchFeedbackAutoSync', () {
    test('runs in the background and retries after the returned delay', () {
      fakeAsync((async) {
        final delays = <Duration?>[const Duration(minutes: 2), null];
        var runs = 0;
        final sync = SearchFeedbackAutoSync(
          run: () async {
            runs++;
            return delays.removeAt(0);
          },
          isBusy: () => false,
        );
        unawaited(sync.request());
        async.flushMicrotasks();
        expect(runs, 1);
        expect(sync.hasScheduledRetry, isTrue);
        async.elapse(const Duration(minutes: 1, seconds: 59));
        expect(runs, 1);
        async.elapse(const Duration(seconds: 1));
        expect(runs, 2);
        expect(sync.hasScheduledRetry, isFalse);
        async.elapse(const Duration(hours: 1));
        expect(runs, 2);
        sync.dispose();
      });
    });

    test('a busy launcher defers the run until resume', () {
      fakeAsync((async) {
        var busy = true;
        var runs = 0;
        final sync = SearchFeedbackAutoSync(
          run: () async {
            runs++;
            return null;
          },
          isBusy: () => busy,
        );
        unawaited(sync.request());
        async.flushMicrotasks();
        expect(runs, 0);
        sync.resume();
        async.flushMicrotasks();
        expect(runs, 0);
        busy = false;
        sync.resume();
        async.flushMicrotasks();
        expect(runs, 1);
        sync.dispose();
      });
    });

    test('a retry that fires while busy waits for resume', () {
      fakeAsync((async) {
        var busy = false;
        var runs = 0;
        final sync = SearchFeedbackAutoSync(
          run: () async {
            runs++;
            return runs == 1 ? const Duration(seconds: 30) : null;
          },
          isBusy: () => busy,
        );
        unawaited(sync.request());
        async.flushMicrotasks();
        busy = true;
        async.elapse(const Duration(seconds: 30));
        expect(runs, 1);
        busy = false;
        sync.resume();
        async.flushMicrotasks();
        expect(runs, 2);
        sync.dispose();
      });
    });

    test('Otzaria closing triggers a run; opening does not', () {
      fakeAsync((async) {
        var runs = 0;
        final sync = SearchFeedbackAutoSync(
          run: () async {
            runs++;
            return null;
          },
          isBusy: () => false,
        );
        sync.onRunningState(running: true);
        async.flushMicrotasks();
        expect(runs, 0);
        sync.onRunningState(running: false);
        async.flushMicrotasks();
        expect(runs, 1);
        sync.dispose();
      });
    });

    test('requests during a run are coalesced, never parallel', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        var active = 0;
        var maxActive = 0;
        var runs = 0;
        final sync = SearchFeedbackAutoSync(
          run: () async {
            runs++;
            active++;
            if (active > maxActive) maxActive = active;
            if (runs == 1) await gate.future;
            active--;
            return null;
          },
          isBusy: () => false,
        );
        unawaited(sync.request());
        unawaited(sync.request());
        unawaited(sync.request());
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();
        expect(maxActive, 1);
        expect(runs, 2);
        sync.dispose();
      });
    });

    test('dispose cancels the retry and ignores later triggers', () {
      fakeAsync((async) {
        var runs = 0;
        final sync = SearchFeedbackAutoSync(
          run: () async {
            runs++;
            return const Duration(minutes: 1);
          },
          isBusy: () => false,
        );
        unawaited(sync.request());
        async.flushMicrotasks();
        sync.dispose();
        expect(sync.hasScheduledRetry, isFalse);
        async.elapse(const Duration(hours: 1));
        unawaited(sync.request());
        sync.onRunningState(running: true);
        sync.onRunningState(running: false);
        async.flushMicrotasks();
        expect(runs, 1);
      });
    });

    test('a throwing run is logged and does not escape', () {
      fakeAsync((async) {
        final sync = SearchFeedbackAutoSync(
          run: () async => throw StateError('boom'),
          isBusy: () => false,
        );
        Object? escaped;
        runZonedGuarded(() => unawaited(sync.request()), (e, _) => escaped = e);
        async.flushMicrotasks();
        expect(escaped, isNull);
        expect(sync.hasScheduledRetry, isFalse);
        sync.dispose();
      });
    });
  });

  test('the source is resolved with a fresh process probe every time',
      () async {
    final temporary = await Directory.systemTemp.createTemp('feedback-fresh-');
    addTearDown(() => temporary.delete(recursive: true));
    final locator = _CountingOtzaria();
    final drive = SearchFeedbackController.forDrive(
      dataDir: p.join(temporary.path, 'drive'),
      stateDir: temporary.path,
      runningLocator: locator,
      launchPath: () async => null,
    );
    addTearDown(drive.dispose);
    await drive.resolveSource();
    await drive.resolveSource();
    expect(locator.probes, 2);
  });

  test(
      'grant while Otzaria runs does not touch settings or resolve launch path',
      () async {
    final temporary =
        await Directory.systemTemp.createTemp('feedback-consent-');
    addTearDown(() => temporary.delete(recursive: true));
    final settings = File(p.join(temporary.path, 'settings.hive'));
    await settings.writeAsBytes([1, 2, 3]);
    var launchReads = 0;
    final guarded = SearchFeedbackController.forDrive(
      dataDir: p.join(temporary.path, 'drive'),
      stateDir: temporary.path,
      runningLocator: const _RunningOtzaria(),
      launchPath: () async {
        launchReads++;
        return p.join(temporary.path, 'otzaria.exe');
      },
    );
    addTearDown(guarded.dispose);
    expect(await guarded.grantConsent(), ConsentWrite.failed);
    expect(launchReads, 0);
    expect(await settings.readAsBytes(), [1, 2, 3]);
    expect(await Directory(p.join(temporary.path, 'drive')).exists(), false);
  });
}

class _CountingOtzaria extends RunningOtzariaLocator {
  _CountingOtzaria();

  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    probes++;
    return (isRunning: false, launchPath: null);
  }
}
