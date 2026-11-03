import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

/// One vectors file over loopback, with Range + If-Range on a fixed ETag. A
/// chunk delay keeps the body in flight while other assets work.
class _Server {
  _Server(this.body, {this.chunkDelay = Duration.zero});

  final Uint8List body;
  final Duration chunkDelay;
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
      for (var at = 0; at < chunk.length; at += 50) {
        response.add(chunk.sublist(at, (at + 50).clamp(0, chunk.length)));
        await response.flush();
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      }
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
    return inner.send(
      http.Request(
        request.method,
        Uri.parse('http://127.0.0.1:$port/$routedName'),
      )..headers.addAll(request.headers),
    );
  }
}

class _Assets extends SemanticSearchAssets {
  _Assets(this.routed, {required super.httpClient, int concurrent = 1})
    : super(
        models: fakeModels,
        scheduler: DownloadScheduler(maxConcurrent: concurrent),
        freeBytesFor: (_) => null,
      );

  final http.Client routed;

  @override
  PatchDownloader newDownloader({int? maxConnections}) => PatchDownloader(
    httpClient: routed,
    decompress: (_) async => null,
    maxConnections: 1,
  );
}

void main() {
  const version = 30;
  const segmentName = 'legacy-v$version.oxv.zst';
  final tag = libraryTagOf(version);
  final downloading = AppL10n.strings.libraryDomain.semanticDownloading;

  late Directory temp;
  late String mirror;
  late FakeVectorsGithub github;
  late Uint8List segment;
  late _Server server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-stage-');
    mirror = p.join(temp.path, 'mirror');
    github = FakeVectorsGithub()..legacyBase(version);
    segment = Uint8List.fromList(
      await github.client.readBytes(
        Uri.parse(
          'https://github.com/Otzaria/SeforimLibrary/releases/download/'
          'vectors-$tag/$segmentName',
        ),
      ),
    );
  });

  tearDown(() async {
    await server.stop();
    github.client.close();
    await temp.delete(recursive: true);
  });

  String vectorDest() => p.join(mirror, tag, 'vectors', segmentName);

  Future<void> leave(String dest, List<int> bytes, String token) async {
    await Directory(p.dirname(dest)).create(recursive: true);
    await File(dest).writeAsBytes(bytes);
    await File(
      PatchDownloader.resumeSidecarPath(dest),
    ).writeAsString('$token\n"v1"');
  }

  Future<void> models() =>
      installModels(p.join(mirror, tag, SemanticSearchAssets.modelFolder));

  /// Every stage seen, and the one showing at each arrival of new bytes.
  Future<({List<String> stages, List<String> atBytes})> sync({
    int concurrent = 1,
  }) async {
    final stages = <String>[];
    final atBytes = <String>[];
    var stage = '';
    var last = 0;
    final assets = _Assets(
      _Routed(github.client, server.port, segmentName),
      httpClient: github.client,
      concurrent: concurrent,
    );
    try {
      await assets.sync(
        mirrorDir: mirror,
        libraryTag: tag,
        libraryTagFor: libraryTagOf,
        onStage: (value) {
          stage = value;
          stages.add(value);
        },
        onBytesProgress: (done, _) {
          if (done > last) atBytes.add(stage);
          last = done;
        },
      );
    } finally {
      assets.dispose();
    }
    return (stages: stages, atBytes: atBytes);
  }

  test(
    'prefix verified, then the rest arrives: stage is downloading',
    () async {
      server = _Server(segment);
      await server.start();
      await leave(
        vectorDest(),
        segment.sublist(0, 10),
        Sha256Stream.ofBytes(segment),
      );
      await models();

      final run = await sync();

      expect(server.ranges, ['bytes=10-']);
      expect(run.stages.where(isLocalWorkStage), isNotEmpty);
      expect(run.atBytes, isNotEmpty);
      expect(run.atBytes, everyElement(downloading));
      expect(run.stages.last, downloading);
      expect(File(vectorDest()).readAsBytesSync(), segment);
    },
  );

  test('a corrupt whole file: verified, dropped, then downloaded', () async {
    server = _Server(segment);
    await server.start();
    final corrupt = Uint8List.fromList(segment)..[3] ^= 0xff;
    await leave(vectorDest(), corrupt, Sha256Stream.ofBytes(segment));
    await models();

    final run = await sync();

    expect(
      run.stages.where(isLocalWorkStage).any((s) => s.contains('100%')),
      isTrue,
    );
    expect(server.ranges, [null]);
    expect(run.atBytes, isNotEmpty);
    expect(run.atBytes, everyElement(downloading));
    expect(run.stages.last, downloading);
    expect(File(vectorDest()).readAsBytesSync(), segment);
  });

  test('an intact whole file: verified only, stage cleared', () async {
    server = _Server(segment);
    await server.start();
    await leave(vectorDest(), segment, Sha256Stream.ofBytes(segment));
    await models();

    final run = await sync();

    expect(server.ranges, isEmpty);
    expect(run.stages.where(isLocalWorkStage), isNotEmpty);
    expect(run.stages.last, downloading);
  });

  test('one asset verifies while another downloads: no stage sticks', () async {
    server = _Server(segment, chunkDelay: const Duration(milliseconds: 40));
    await server.start();
    await leave(
      vectorDest(),
      segment.sublist(0, 10),
      Sha256Stream.ofBytes(segment),
    );
    // A complete but corrupt model file: the engine verifies it, drops it and
    // downloads it again while the vectors are still streaming.
    final model = fakeModels.first;
    final modelDest = p.join(
      mirror,
      tag,
      SemanticSearchAssets.modelFolder,
      model.name,
    );
    await leave(modelDest, Uint8List(model.size), model.sha256);

    final run = await sync(concurrent: 3);

    final local = run.stages.where(isLocalWorkStage).toList();
    expect(local.any((s) => s.contains(model.name)), isTrue, reason: '$local');
    // The vectors' bytes never arrive under a stage still naming them.
    expect(
      run.atBytes.where((s) => s.contains(segmentName)),
      isEmpty,
      reason: '${run.atBytes}',
    );
    expect(run.stages.last, downloading);
    expect(File(vectorDest()).readAsBytesSync(), segment);
  });
}
