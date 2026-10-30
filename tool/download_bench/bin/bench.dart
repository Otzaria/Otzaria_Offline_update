// Issue #149 benchmark: drives the tool's real download code paths.
// Usage:
//   dart run bin/bench.dart probe <url> <rangeStart-rangeEnd>
//   dart run bin/bench.dart pd <outDir> <maxConnections> <url>,<size>,<sha256> ...
//       (PatchDownloader + DownloadScheduler(4), jobs sorted biggest first,
//        like LibraryMirrorExporter; maxConnections=2 reproduces the exporter)
//   dart run bin/bench.dart df <outDir> <url>,<size>,<sha256>   (otzaria_downloads.downloadFile)
//   dart run bin/bench.dart hash <file>
// Logs never print query strings.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart' as od;
import 'package:seforim_library_updater/seforim_library_updater.dart';

final _t0 = Stopwatch()..start();
String ts() => (_t0.elapsedMilliseconds / 1000).toStringAsFixed(2).padLeft(7);
String safe(Uri u) =>
    '${u.scheme}://${u.host}${u.port == 443 || u.port == 80 ? '' : ':${u.port}'}${u.path.length > 40 ? '${u.path.substring(0, 20)}..${u.path.substring(u.path.length - 18)}' : u.path}';

/// Wraps a client: logs each request/response and counts open response bodies.
class LoggingClient extends http.BaseClient {
  LoggingClient(this._inner);
  final http.Client _inner;
  int active = 0;
  int peak = 0;
  int requests = 0;
  final statuses = <int, int>{};
  final _bodyBytes = <int>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = ++requests;
    final range = request.headers['Range'] ?? request.headers['range'] ?? '-';
    final r = await _inner.send(request);
    statuses[r.statusCode] = (statuses[r.statusCode] ?? 0) + 1;
    final cr = r.headers['content-range'] ?? '-';
    stdout.writeln(
      '${ts()} REQ#$id ${request.method} ${safe(request.url)} '
      'Range=$range -> ${r.statusCode} CR=$cr CL=${r.contentLength}',
    );
    if (r.isRedirect || r.statusCode >= 300 && r.statusCode < 400) return r;
    active++;
    if (active > peak) peak = active;
    stdout.writeln('${ts()}   active bodies=$active');
    var bytes = 0;
    var closed = false;
    void close(String why) {
      if (closed) return;
      closed = true;
      active--;
      _bodyBytes.add(bytes);
      stdout.writeln('${ts()} END#$id $why bytes=$bytes active=$active');
    }

    final controller = StreamController<List<int>>();
    late StreamSubscription<List<int>> sub;
    controller.onListen = () {
      sub = r.stream.listen(
        (c) {
          bytes += c.length;
          controller.add(c);
        },
        onError: (Object e, StackTrace s) {
          close('error');
          controller.addError(e, s);
        },
        onDone: () {
          close('done');
          controller.close();
        },
      );
    };
    controller.onPause = () => sub.pause();
    controller.onResume = () => sub.resume();
    controller.onCancel = () async {
      close('cancelled');
      await sub.cancel();
    };
    return http.StreamedResponse(
      controller.stream,
      r.statusCode,
      contentLength: r.contentLength,
      request: r.request,
      headers: r.headers,
      isRedirect: r.isRedirect,
      persistentConnection: r.persistentConnection,
      reasonPhrase: r.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}

Future<void> probe(String url, String range) async {
  stdout.writeln('== package:http, manual redirects (as PatchDownloader)');
  final c = http.Client();
  var u = Uri.parse(url);
  for (var hop = 0; hop < 6; hop++) {
    final req = http.Request('GET', u)
      ..followRedirects = false
      ..headers['Range'] = 'bytes=$range'
      ..headers['Accept'] = 'application/octet-stream';
    final r = await c.send(req);
    stdout.writeln(
      '  ${u.host}: ${r.statusCode} CR=${r.headers['content-range']} '
      'AR=${r.headers['accept-ranges']} CL=${r.contentLength} server=${r.headers['server']}',
    );
    final loc = r.headers['location'];
    await r.stream.listen((_) {}).cancel();
    if (r.statusCode >= 300 && r.statusCode < 400 && loc != null) {
      u = u.resolve(loc);
      continue;
    }
    break;
  }
  stdout.writeln(
    '== package:http, followRedirects=true (default, as downloadFile)',
  );
  final req = http.Request('GET', Uri.parse(url))
    ..headers['Range'] = 'bytes=$range';
  final r = await c.send(req);
  stdout.writeln(
    '  final ${r is http.BaseResponseWithUrl ? (r as http.BaseResponseWithUrl).url.host : '?'}: '
    '${r.statusCode} CR=${r.headers['content-range']} AR=${r.headers['accept-ranges']} CL=${r.contentLength}',
  );
  await r.stream.listen((_) {}).cancel();
  c.close();

  stdout.writeln('== dart:io HttpClient, auto redirects');
  final hc = HttpClient();
  final q = await hc.getUrl(Uri.parse(url));
  q.headers.set('Range', 'bytes=$range');
  final p = await q.close();
  stdout.writeln(
    '  hops=${p.redirects.map((e) => '${e.statusCode}->${e.location.host}').join(',')} '
    'final ${p.statusCode} CR=${p.headers.value('content-range')} '
    'AR=${p.headers.value('accept-ranges')} CL=${p.contentLength}',
  );
  await p.listen((_) {}).cancel();
  hc.close(force: true);
}

({String url, int size, String sha}) parseJob(String s) {
  final parts = s.split(',');
  return (url: parts[0], size: int.parse(parts[1]), sha: parts[2]);
}

Future<void> pd(String outDir, int conns, List<String> specs) async {
  final jobs = specs.map(parseJob).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  final logging = LoggingClient(http.Client());
  final downloader = PatchDownloader(
    httpClient: logging,
    decompress: (_) async => null,
    maxConnections: conns,
  );
  final scheduler = DownloadScheduler();
  final total = jobs.fold<int>(0, (s, j) => s + j.size);
  var lastPrint = 0;
  final agg = ByteProgressAggregator(
    totalBytes: total,
    onProgress: (d, t) {
      final now = _t0.elapsedMilliseconds;
      if (now - lastPrint > 5000) {
        lastPrint = now;
        stdout.writeln(
          '${ts()} progress ${(d / 1048576).toStringAsFixed(1)}MiB '
          'active=${logging.active}',
        );
      }
    },
  );
  final slots = [for (final _ in jobs) agg.slot()];
  agg.announce();
  final start = _t0.elapsedMilliseconds;
  final netEnd = <int>[];
  final verifyMs = <int>[];
  await scheduler.run<void>([
    for (final (i, j) in jobs.indexed)
      () async {
        final name = Uri.parse(j.url).pathSegments.last;
        final fs = _t0.elapsedMilliseconds;
        int? vStart;
        stdout.writeln('${ts()} START $name size=${j.size}');
        await downloader.downloadToFile(
          url: j.url,
          destPath: '$outDir/$name',
          expectedSize: j.size,
          expectedSha256: j.sha,
          resumeToken: 'bench:$name:${j.sha}',
          onProgress: slots[i].report,
          onExistingBytes: slots[i].markExisting,
          onVerifyProgress: (v, t) {
            if (vStart == null) {
              vStart = _t0.elapsedMilliseconds;
              stdout.writeln('${ts()} VERIFY/ASSEMBLE start $name');
            }
          },
        );
        final fe = _t0.elapsedMilliseconds;
        final vs = vStart ?? fe;
        netEnd.add(vs);
        verifyMs.add(fe - vs);
        stdout.writeln(
          '${ts()} DONE $name net=${(vs - fs) / 1000}s '
          'assemble+hash=${(fe - vs) / 1000}s total=${(fe - fs) / 1000}s '
          'avg=${(j.size / 1048576 / ((fe - fs) / 1000)).toStringAsFixed(2)}MiB/s',
        );
      },
  ]);
  final end = _t0.elapsedMilliseconds;
  final secs = (end - start) / 1000;
  stdout.writeln(
    'SUMMARY pd conns=$conns files=${jobs.length} bytes=$total '
    'wall=${secs}s rate=${(total / 1048576 / secs).toStringAsFixed(2)}MiB/s '
    'requests=${logging.requests} statuses=${logging.statuses} '
    'peakBodies=${logging.peak} assembleHashSum=${verifyMs.fold<int>(0, (a, b) => a + b) / 1000}s',
  );
  logging.close();
}

Future<void> df(String outDir, String spec) async {
  final j = parseJob(spec);
  final logging = LoggingClient(http.Client());
  final name = Uri.parse(j.url).pathSegments.last;
  final dest = '$outDir/$name';
  final s = _t0.elapsedMilliseconds;
  await od.downloadFile(
    client: logging,
    url: j.url,
    destinationPath: dest,
    expectedSize: j.size,
    calculateSha256: false,
    statusError: (st) => StateError('status $st'),
    sizeError: (a, e) => StateError('size $a != $e'),
  );
  final n = _t0.elapsedMilliseconds;
  final digest = await hashFile(dest);
  final h = _t0.elapsedMilliseconds;
  final net = (n - s) / 1000;
  stdout.writeln(
    'SUMMARY df bytes=${j.size} net=${net}s hash=${(h - n) / 1000}s '
    'rate=${(j.size / 1048576 / net).toStringAsFixed(2)}MiB/s sha_ok=${digest == j.sha} '
    'requests=${logging.requests} statuses=${logging.statuses} peakBodies=${logging.peak}',
  );
  logging.close();
}

Future<String> hashFile(String path) async {
  final d = await sha256.bind(File(path).openRead()).first;
  return d.toString();
}

Future<void> main(List<String> args) async {
  switch (args.first) {
    case 'probe':
      await probe(args[1], args[2]);
    case 'pd':
      await pd(args[1], int.parse(args[2]), args.sublist(3));
    case 'df':
      await df(args[1], args[2]);
    case 'hash':
      final s = _t0.elapsedMilliseconds;
      final d = await hashFile(args[1]);
      stdout.writeln('hash ${(_t0.elapsedMilliseconds - s) / 1000}s $d');
  }
  exit(0);
}
