import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String target;
  const url = 'https://example.test/app.exe';
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('resume-test-');
    target = '${temp.path}/app.exe';
  });
  tearDown(() => temp.delete(recursive: true));

  Future<FileDownloadResult> download(
    http.Client client, {
    int? size = 6,
    int attempts = 1,
    String source = url,
    Duration stall = const Duration(milliseconds: 100),
    Duration connect = const Duration(milliseconds: 100),
    void Function(int, int)? progress,
    void Function()? cancelled,
  }) =>
      downloadFile(
        client: client,
        url: source,
        destinationPath: target,
        expectedSize: size,
        maxAttempts: attempts,
        stallTimeout: stall,
        connectTimeout: connect,
        onProgress: progress,
        checkCancelled: cancelled,
        statusError: (status) => StateError('HTTP $status'),
        sizeError: (actual, expected) => StateError('size $actual/$expected'),
      );

  Stream<List<int>> interrupted() async* {
    yield utf8.encode('abc');
    throw http.ClientException('disconnected');
  }

  Future<void> partial({String? etag = '"v1"'}) async {
    final client = MockClient.streaming((_, __) async => http.StreamedResponse(
          interrupted(),
          200,
          contentLength: 6,
          headers: {
            if (etag != null) 'etag': etag,
            'content-disposition': 'attachment; filename=app.exe'
          },
        ));
    addTearDown(client.close);
    await expectLater(download(client), throwsA(isA<http.ClientException>()));
  }

  http.Client responding(
      Future<http.StreamedResponse> Function(http.BaseRequest) fn) {
    final client = MockClient.streaming((req, _) => fn(req));
    addTearDown(client.close);
    return client;
  }

  http.StreamedResponse body(String text,
          {int status = 200, Map<String, String> headers = const {}}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(text)),
        status,
        contentLength: text.length,
        headers: headers,
      );

  test('interrupted bytes survive and a new client resumes with If-Range',
      () async {
    await partial();
    expect(await File('$target.part').readAsString(), 'abc');
    expect(await File(target).exists(), isFalse);
    final progress = <int>[];
    final result = await download(responding((req) async {
      expect(req.headers['Range'], 'bytes=3-');
      expect(req.headers['If-Range'], '"v1"');
      return body('def',
          status: 206, headers: {'content-range': 'bytes 3-5/6'});
    }), progress: (n, _) => progress.add(n));
    expect(await File(target).readAsString(), 'abcdef');
    expect(result.headers['content-disposition'], contains('app.exe'));
    expect(progress, [3, 6]);
    expect(await File('$target.resume').exists(), isFalse);
    expect(await File('$target.part').exists(), isFalse);
  });

  test('a transient disconnect automatically resumes once', () async {
    var requests = 0;
    await download(responding((req) async {
      if (++requests == 1) {
        return http.StreamedResponse(interrupted(), 200,
            contentLength: 6, headers: {'etag': '"v1"'});
      }
      expect(req.headers['Range'], 'bytes=3-');
      return body('def',
          status: 206, headers: {'content-range': 'bytes 3-5/6'});
    }), attempts: 2);
    expect(requests, 2);
    expect(await File(target).readAsString(), 'abcdef');
  });

  test('ignored Range or changed asset replaces bytes, never appends',
      () async {
    await partial();
    final progress = <int>[];
    await download(responding((req) async {
      expect(req.headers['Range'], 'bytes=3-');
      return body('UVWXYZ', headers: {'etag': '"v2"'});
    }), progress: (n, _) => progress.add(n));
    expect(await File(target).readAsString(), 'UVWXYZ');
    expect(progress.first, 0);
  });

  test('416 restarts at most once without draining the rejected body',
      () async {
    await partial();
    var requests = 0;
    final stalled = StreamController<List<int>>();
    await download(responding((req) async {
      if (++requests == 1) return http.StreamedResponse(stalled.stream, 416);
      expect(req.headers.containsKey('Range'), isFalse);
      return body('abcdef');
    }));
    await stalled.close();
    expect(requests, 2);
    expect(await File(target).readAsString(), 'abcdef');
  });

  for (final headers in [
    <String, String>{},
    {'content-range': 'bytes 0-2/6'},
    {'content-range': 'bytes 3-5/9'},
    {'content-range': 'bytes 3-5/6', 'etag': '"different"'},
    {'content-range': 'bytes 3-4/6'},
  ]) {
    test('invalid partial response is rejected: $headers', () async {
      await partial();
      await expectLater(
          download(responding(
              (_) async => body('def', status: 206, headers: headers))),
          throwsStateError);
      expect(await File(target).exists(), isFalse);
      expect(await File('$target.part').exists(), isFalse);
    });
  }

  for (final etag in [null, 'W/"weak"', 'unquoted']) {
    test('no strong validator means restart: $etag', () async {
      await partial(etag: etag);
      expect(await File('$target.part').exists(), isFalse);
      await download(responding((req) async {
        expect(req.headers.containsKey('Range'), isFalse);
        return body('abcdef');
      }));
    });
  }

  test('changed URL cannot reuse old bytes', () async {
    await partial();
    await download(responding((req) async {
      expect(req.headers.containsKey('Range'), isFalse);
      return body('UVWXYZ');
    }), source: '$url?new');
    expect(await File(target).readAsString(), 'UVWXYZ');
  });

  test('corrupt metadata restarts safely', () async {
    await partial();
    await File('$target.resume').writeAsString('{broken');
    await download(responding((req) async {
      expect(req.headers.containsKey('Range'), isFalse);
      return body('abcdef');
    }));
  });

  test('unknown expected size resumes using the original Content-Length',
      () async {
    await expectLater(
        download(
            responding((_) async => http.StreamedResponse(interrupted(), 200,
                contentLength: 6, headers: {'etag': '"v1"'})),
            size: null),
        throwsA(isA<http.ClientException>()));
    await download(responding((req) async {
      expect(req.headers['Range'], 'bytes=3-');
      return body('def',
          status: 206, headers: {'content-range': 'bytes 3-5/6'});
    }), size: null);
    expect(await File(target).readAsString(), 'abcdef');
  });

  test('stall retry is bounded and leaves the previous complete file intact',
      () async {
    await File(target).writeAsString('previous');
    var requests = 0;
    final streams = <StreamController<List<int>>>[];
    await expectLater(
        download(responding((_) async {
          requests++;
          final stream = StreamController<List<int>>()..add(utf8.encode('abc'));
          streams.add(stream);
          return http.StreamedResponse(stream.stream, 200,
              contentLength: 6, headers: {'etag': '"v1"'});
        }), attempts: 2, stall: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
    for (final stream in streams) {
      await stream.close();
    }
    expect(requests, 2);
    expect(await File(target).readAsString(), 'previous');
    expect(await File('$target.part').readAsString(), 'abc');
  });

  test('cancellation is never retried and removes new partial data', () async {
    var cancelled = false;
    var requests = 0;
    await expectLater(
        download(
            responding((_) async {
              requests++;
              return body('abcdef', headers: {'etag': '"v1"'});
            }),
            attempts: 2,
            progress: (n, _) {
              if (n > 0) cancelled = true;
            },
            cancelled: () {
              if (cancelled) throw StateError('cancelled');
            }),
        throwsStateError);
    expect(requests, 1);
    expect(await File(target).exists(), isFalse);
    expect(await File('$target.part').exists(), isFalse);
  });

  test('truncated success and oversized bodies never become complete files',
      () async {
    for (final bytes in ['abc', 'abcdefghi']) {
      await expectLater(
          download(
              responding((_) async => body(bytes, headers: {'etag': '"v1"'}))),
          throwsStateError);
      expect(await File(target).exists(), isFalse);
      expect(await File('$target.part').exists(), isFalse);
    }
  });

  test('slow but advancing download does not hit a total duration deadline',
      () async {
    Stream<List<int>> trickle() async* {
      for (final byte in utf8.encode('abcdef')) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        yield [byte];
      }
    }

    await download(
        responding((_) async =>
            http.StreamedResponse(trickle(), 200, contentLength: 6)),
        stall: const Duration(milliseconds: 100));
    expect(await File(target).readAsString(), 'abcdef');
  });

  test('connection timeout aborts the HTTP request', () async {
    var aborted = false;
    final pending = Completer<http.StreamedResponse>();
    final client = responding((req) {
      unawaited((req as http.AbortableRequest).abortTrigger!.then((_) {
        aborted = true;
      }));
      return pending.future;
    });
    await expectLater(
        download(client, connect: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(Duration.zero);
    expect(aborted, isTrue);
    pending.complete(body('abcdef'));
    await Future<void>.delayed(Duration.zero);
  });

  test('resumed SHA-256 includes the saved prefix', () async {
    await partial();
    final result = await downloadFile(
      client: responding((_) async =>
          body('def', status: 206, headers: {'content-range': 'bytes 3-5/6'})),
      url: url,
      destinationPath: target,
      expectedSize: 6,
      calculateSha256: true,
      statusError: (status) => StateError('HTTP $status'),
      sizeError: (actual, expected) => StateError('size $actual/$expected'),
    );
    expect(result.sha256, sha256.convert(utf8.encode('abcdef')).toString());
  });

  test('decoded response is not measured against compressed Content-Length',
      () async {
    final result = await download(
        responding((_) async => http.StreamedResponse(
              Stream.value(utf8.encode('abcdef')),
              200,
              contentLength: 3,
              headers: {'etag': '"gzip-v1"', 'content-encoding': 'gzip'},
            )),
        size: null);
    expect(result.size, 6);
    expect(await File(target).readAsString(), 'abcdef');
  });

  test('cancelling a resume keeps the partial from before this attempt',
      () async {
    await partial();
    var cancelled = false;
    await expectLater(
        download(
            responding((_) async => body('def',
                status: 206,
                headers: {'content-range': 'bytes 3-5/6'})), progress: (n, _) {
          if (n == 6) cancelled = true;
        }, cancelled: () {
          if (cancelled) throw StateError('cancelled');
        }),
        throwsStateError);
    expect(await File('$target.part').readAsString(), 'abc');
    expect(await File('$target.resume').exists(), isTrue);
    expect(await File(target).exists(), isFalse);
  });

  test('real HTTP transport resumes after a server disconnect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = http.Client();
    addTearDown(client.close);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    final handled = <Future<void>>[];
    Future<void> handle(HttpRequest request) async {
      if (++requests == 1) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 6\r\n'
            'ETag: "v1"\r\nConnection: close\r\n\r\nabc');
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        socket.destroy();
      } else {
        expect(request.headers.value('range'), 'bytes=3-');
        expect(request.headers.value('if-range'), '"v1"');
        request.response.statusCode = 206;
        request.response.contentLength = 3;
        request.response.headers.set('content-range', 'bytes 3-5/6');
        request.response.write('def');
        await request.response.close();
      }
    }

    final subscription = server.listen((req) => handled.add(handle(req)));
    addTearDown(subscription.cancel);
    await download(client,
        source: 'http://127.0.0.1:${server.port}/app.exe',
        attempts: 2,
        connect: const Duration(seconds: 3),
        stall: const Duration(seconds: 3));
    await Future.wait(handled);
    expect(requests, 2);
    expect(await File(target).readAsString(), 'abcdef');
  });
}
