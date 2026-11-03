import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

/// A loopback server for one vectors file: honours Range with an ETag and
/// drops the connection mid-body for the first [cuts] requests.
class _FlakyServer {
  _FlakyServer(this.body, {this.cutAfter = 200});

  final Uint8List body;
  int cuts = 1;
  final int cutAfter;
  final ranges = <String?>[];
  late final HttpServer _server;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final range = request.headers.value('range');
      ranges.add(range);
      final partial =
          range != null && request.headers.value('if-range') == '"v1"';
      final from = partial
          ? int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!)
          : 0;
      final chunk = body.sublist(from);
      final response = request.response
        ..statusCode = partial ? 206 : 200
        ..contentLength = chunk.length;
      response.headers.set('etag', '"v1"');
      if (partial) {
        response.headers.set(
          'content-range',
          'bytes $from-${body.length - 1}/${body.length}',
        );
      }
      if (cuts > 0) {
        cuts--;
        final socket = await response.detachSocket();
        socket.add(chunk.sublist(0, math.min(cutAfter, chunk.length)));
        await socket.flush();
        socket.destroy();
        return;
      }
      response.add(chunk);
      await response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

class _Routed extends http.BaseClient {
  _Routed(this.rest, this.port, this.routedName);

  final http.Client rest;
  final int port;
  final String routedName;
  final inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.pathSegments.last != routedName) return rest.send(request);
    final routed = http.Request(
      request.method,
      Uri.parse('http://127.0.0.1:$port/$routedName'),
    )..headers.addAll(request.headers);
    return inner.send(routed);
  }
}

class _Assets extends SemanticSearchAssets {
  _Assets(
    this.routed, {
    required super.httpClient,
    required this.retryDelays,
    int concurrent = 1,
  }) : super(
         models: fakeModels,
         scheduler: DownloadScheduler(maxConcurrent: concurrent),
         freeBytesFor: (_) => null,
       );

  final http.Client routed;
  final List<Duration> retryDelays;

  @override
  PatchDownloader newDownloader({int? maxConnections}) => PatchDownloader(
    httpClient: routed,
    decompress: (_) async => null,
    networkRetryDelays: retryDelays,
    maxConnections: 1,
  );
}

void main() {
  const version = 30;
  const segmentName = 'legacy-v$version.oxv.zst';
  final modelBytes = fakeModels.fold<int>(0, (sum, file) => sum + file.size);
  final planned = modelBytes + 500;

  late Directory temp;
  late String mirror;
  late FakeVectorsGithub github;
  late Uint8List segment;
  late _FlakyServer server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-real-engine-');
    mirror = p.join(temp.path, 'mirror');
    github = FakeVectorsGithub()..legacyBase(version);
    segment = await github.client.readBytes(
      Uri.parse(
        'https://github.com/Otzaria/SeforimLibrary/releases/download/'
        'vectors-${libraryTagOf(version)}/$segmentName',
      ),
    );
  });

  tearDown(() async {
    await server.stop();
    github.client.close();
    await temp.delete(recursive: true);
  });

  Future<List<(int, int?)>> sync({
    required void Function(int, int?) report,
    List<Duration> retryDelays = const [Duration(milliseconds: 5)],
    int concurrent = 1,
  }) async {
    final events = <(int, int?)>[];
    final assets = _Assets(
      _Routed(github.client, server.port, segmentName),
      httpClient: github.client,
      retryDelays: retryDelays,
      concurrent: concurrent,
    );
    try {
      await assets.sync(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(version),
        libraryTagFor: libraryTagOf,
        onStage: (_) {},
        onBytesProgress: (done, total) {
          events.add((done, total));
          report(done, total);
        },
      );
    } finally {
      assets.dispose();
    }
    return events;
  }

  void expectNeverBackwards(List<(int, int?)> events) {
    expect(events, isNotEmpty);
    var peak = 0;
    for (final (done, total) in events) {
      expect(done, greaterThanOrEqualTo(peak), reason: '$events');
      expect(done, lessThanOrEqualTo(total ?? done), reason: '$events');
      peak = done;
    }
  }

  String vectorDest() =>
      p.join(mirror, libraryTagOf(version), 'vectors', segmentName);

  Future<void> leavePrefix(int length) async {
    final dest = vectorDest();
    await Directory(p.dirname(dest)).create(recursive: true);
    await File(dest).writeAsBytes(segment.sublist(0, length));
    await File(
      PatchDownloader.resumeSidecarPath(dest),
    ).writeAsString('${Sha256Stream.ofBytes(segment)}\n"v1"');
  }

  test('clean start: a cut and resume never move the counter back', () async {
    server = _FlakyServer(segment);
    await server.start();

    final events = await sync(report: (_, _) {});

    expect(server.ranges, [null, 'bytes=200-']);
    expectNeverBackwards(events);
    expect(events.last, (planned, planned));
    expect(File(vectorDest()).readAsBytesSync(), segment);
  });

  test('a partial from before: counted from it, a cut never rewinds', () async {
    server = _FlakyServer(segment, cutAfter: 150);
    await server.start();
    await leavePrefix(100);

    final events = await sync(report: (_, _) {});

    expect(server.ranges, ['bytes=100-', 'bytes=250-']);
    expectNeverBackwards(events);
    expect(events.last, (planned - 100, planned - 100));
  });

  test('several files at once: one steady counter', () async {
    server = _FlakyServer(segment);
    await server.start();

    final events = await sync(report: (_, _) {}, concurrent: 3);

    expectNeverBackwards(events);
    expect(events.map((e) => e.$2).toSet().last, planned);
    expect(events.last, (planned, planned));
  });

  test(
    'a retry in a later run holds an outer peak and still finishes',
    () async {
      server = _FlakyServer(segment);
      await server.start();
      final shown = <(int, int?)>[];
      final outer = ByteProgressAggregator(
        onProgress: (done, total) => shown.add((done, total)),
      );
      final slot = outer.slot();

      await expectLater(
        sync(report: slot.report, retryDelays: const []),
        throwsA(anything),
      );
      final afterFailure = shown.last.$1;
      expect(afterFailure, greaterThan(0));
      await sync(report: slot.report);

      expectNeverBackwards(shown);
      expect(shown.last.$1, shown.last.$2);
      expect(shown.last.$1, greaterThanOrEqualTo(afterFailure));
    },
  );
}
