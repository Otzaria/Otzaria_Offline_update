import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:test/test.dart';

const _url = 'https://example.test/asset.bin';
const _bound = Duration(seconds: 3);

class _WaitingClient extends http.BaseClient {
  _WaitingClient(this.response);

  final Future<http.StreamedResponse> response;
  final started = Completer<http.AbortableRequest>();
  var requests = 0;
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    started.complete(request as http.AbortableRequest);
    return response;
  }

  @override
  void close() => closed = true;
}

void main() {
  late Directory temp;
  late String target;
  late List<Timer> timers;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('download-cancellation-');
    target = '${temp.path}/asset.bin';
    timers = [];
  });
  tearDown(() => temp.delete(recursive: true));

  Future<({Object error, StackTrace stack})?> download(
    http.Client client, {
    void Function()? checkCancelled,
    void Function(int, int)? progress,
    int size = 6,
    bool keepPartial = false,
  }) =>
      runZoned(
        () => downloadFile(
          client: client,
          url: _url,
          destinationPath: target,
          expectedSize: size,
          connectTimeout: const Duration(hours: 1),
          stallTimeout: const Duration(hours: 1),
          checkCancelled: checkCancelled,
          onProgress: progress,
          keepPartialOnCancel: keepPartial,
          calculateSha256: true,
          maxAttempts: 2,
          statusError: (status) => StateError('HTTP $status'),
          sizeError: (actual, expected) => StateError('size $actual/$expected'),
        ).then<({Object error, StackTrace stack})?>(
          (_) => null,
          onError: (Object error, StackTrace stack) =>
              (error: error, stack: stack),
        ),
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, callback) {
            final timer = parent.createPeriodicTimer(zone, period, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );

  void expectStopped(_WaitingClient client) {
    expect(client.requests, 1);
    expect(client.closed, isFalse);
    expect(timers.every((timer) => !timer.isActive), isTrue);
  }

  test('cancellation wakes a request without headers and closes a late body',
      () async {
    final pending = Completer<http.StreamedResponse>();
    final client = _WaitingClient(pending.future);
    addTearDown(client.close);
    final lateCancelled = Completer<void>();
    final lateBody = StreamController<List<int>>(
      onCancel: () => lateCancelled.complete(),
    );
    var cancel = false;
    var cancellationChecks = 0;
    final error = TimeoutException('requested cancellation');
    final stack = StackTrace.fromString('original cancellation stack');
    final result = download(client, checkCancelled: () {
      if (!cancel) return;
      cancellationChecks++;
      Error.throwWithStackTrace(error, stack);
    });
    final request = await client.started.future.timeout(_bound);
    cancel = true;
    try {
      final failure = await result.timeout(_bound);
      expect(failure?.error, same(error));
      expect(failure?.stack.toString(), stack.toString());
      expect(cancellationChecks, 1);
      await request.abortTrigger!.timeout(_bound);
      expectStopped(client);
      expect(await File('$target.part').exists(), isFalse);
      expect(await File('$target.resume').exists(), isFalse);
    } finally {
      lateBody.add(const [0]);
      pending.complete(http.StreamedResponse(lateBody.stream, 200));
      await result.timeout(_bound);
      await lateCancelled.future.timeout(_bound);
      await lateBody.close();
    }
  });

  for (final resumed in [false, true]) {
    for (final keepPartial in [false, true]) {
      test(
          'cancellation wakes a quiet body: resumed=$resumed, '
          'keepPartial=$keepPartial', () async {
        await File(target).writeAsString('previous complete file');
        String? savedMetadata;
        if (resumed) {
          await File('$target.part').writeAsString('abc');
          savedMetadata = jsonEncode({
            'url': _url,
            'expectedSize': 9,
            'etag': '"v1"',
            'total': 9,
            'headers': {'etag': '"v1"', 'original': 'retained'},
          });
          await File('$target.resume').writeAsString(savedMetadata);
        }
        final bodyCancelled = Completer<void>();
        final body = StreamController<List<int>>(
          onCancel: () => bodyCancelled.complete(),
        )..add(utf8.encode(resumed ? 'def' : 'abc'));
        final client = _WaitingClient(Future.value(http.StreamedResponse(
          body.stream,
          resumed ? 206 : 200,
          contentLength: 6,
          headers: {
            'etag': '"v1"',
            if (resumed) 'content-range': 'bytes 3-8/9',
          },
        )));
        addTearDown(client.close);
        var cancel = false;
        final error = StateError('requested cancellation');
        final written = Completer<void>();
        final result = download(
          client,
          size: resumed ? 9 : 6,
          keepPartial: keepPartial,
          checkCancelled: () {
            if (cancel) throw error;
          },
          progress: (received, _) {
            if (received == (resumed ? 6 : 3)) written.complete();
          },
        );
        try {
          await written.future.timeout(_bound);
          cancel = true;
          final failure = await result.timeout(_bound);
          expect(failure?.error, same(error));
          final request = await client.started.future;
          expect(request.headers['Range'], resumed ? 'bytes=3-' : isNull);
          await request.abortTrigger!.timeout(_bound);
          await bodyCancelled.future.timeout(_bound);
          expectStopped(client);
          expect(await File(target).readAsString(), 'previous complete file');
          if (keepPartial || resumed) {
            expect(await File('$target.part').readAsString(),
                resumed && keepPartial ? 'abcdef' : 'abc');
            expect(await File('$target.resume').exists(), isTrue);
            if (resumed && !keepPartial) {
              expect(
                  await File('$target.resume').readAsString(), savedMetadata);
            }
          } else {
            expect(await File('$target.part').exists(), isFalse);
            expect(await File('$target.resume').exists(), isFalse);
          }
        } finally {
          await body.close();
          await result.timeout(_bound);
        }
      });
    }
  }

  test('a completed download stops polling and leaves its client usable',
      () async {
    final client = _WaitingClient(Future.value(http.StreamedResponse(
      Stream.value(utf8.encode('abcdef')),
      200,
      contentLength: 6,
    )));
    addTearDown(client.close);
    expect(
        await download(client, checkCancelled: () {}).timeout(_bound), isNull);
    expectStopped(client);
    expect(await File(target).readAsString(), 'abcdef');
  });

  test('a failed download stops polling and closes an unconsumed body',
      () async {
    final cancelled = Completer<void>();
    final body = StreamController<List<int>>(
      onCancel: () => cancelled.complete(),
    );
    final client = _WaitingClient(
      Future.value(http.StreamedResponse(body.stream, 503)),
    );
    addTearDown(client.close);
    final failure =
        await download(client, checkCancelled: () {}).timeout(_bound);
    expect(failure?.error, isA<StateError>());
    await cancelled.future.timeout(_bound);
    expectStopped(client);
    await body.close();
  });

  test('a download without a cancellation callback creates no polling timer',
      () async {
    final client = _WaitingClient(Future.value(http.StreamedResponse(
      Stream.value(utf8.encode('abcdef')),
      200,
      contentLength: 6,
    )));
    addTearDown(client.close);
    expect(await download(client).timeout(_bound), isNull);
    expect(timers, isEmpty);
    expectStopped(client);
  });
}
