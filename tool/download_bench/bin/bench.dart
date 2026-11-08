// Issue #149 benchmark: drives the tool's real download code paths.
// Subcommands: probe, pd, df, assist, stage, hash, scratch, writetest; args:
// see the switch in `main`. `--json=<file>` appends each RESULT as a JSON line.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:download_bench/meter.dart';
import 'package:download_bench/scratch.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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
  int lastEnd = -1;
  int firstResponseMs = -1;
  int netBytes = 0;
  final statuses = <int, int>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = ++requests;
    final range = request.headers['Range'] ?? request.headers['range'] ?? '-';
    final r = await _inner.send(request);
    if (firstResponseMs < 0) firstResponseMs = _t0.elapsedMilliseconds;
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
      lastEnd = _t0.elapsedMilliseconds;
      stdout.writeln('${ts()} END#$id $why bytes=$bytes active=$active');
    }

    final controller = StreamController<List<int>>();
    late StreamSubscription<List<int>> sub;
    controller.onListen = () {
      sub = r.stream.listen(
        (c) {
          bytes += c.length;
          netBytes += c.length;
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

Future<void> probe(String url, String range, Map<String, String> flags) async {
  stdout.writeln('== package:http, manual redirects (as PatchDownloader)');
  final c = _client(flags);
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
  final hc = _ioClient(flags);
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
  if (parts.length != 3) throw BenchFailure("job must be url,size,sha: '$s'");
  final size = int.tryParse(parts[1]);
  if (size == null || size <= 0) throw BenchFailure("bad size '${parts[1]}'");
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(parts[2])) {
    throw BenchFailure('sha256 must be 64 hex digits');
  }
  assetNameOf(parts[0]);
  return (url: parts[0], size: size, sha: parts[2].toLowerCase());
}

/// Checked, case-insensitively unique file names of [jobs].
Set<String> jobNames(List<({String url, int size, String sha})> jobs) {
  final seen = <String>{}, names = <String>{};
  for (final j in jobs) {
    final n = assetNameOf(j.url);
    if (!seen.add(n.toLowerCase())) throw BenchFailure("duplicate name '$n'");
    names.add(n);
  }
  return names;
}

/// `--key=value` flags; everything else stays positional.
({Map<String, String> flags, List<String> rest}) parseFlags(List<String> a) {
  final flags = <String, String>{};
  final rest = <String>[];
  for (final s in a) {
    if (s.startsWith('--')) {
      final i = s.indexOf('=');
      flags[i < 0 ? s.substring(2) : s.substring(2, i)] = i < 0
          ? 'true'
          : s.substring(i + 1);
    } else {
      rest.add(s);
    }
  }
  return (flags: flags, rest: rest);
}

/// Set by `main` once per process: one bench process is one run.
String? _jsonOut;
String _label = 'n/a';
String _scheme = 'n/a';
Map<String, Object?> _env = const {};
IoSnapshot? _io0;
double? _cpu0;

/// Process counters at the READY moment, before the bench's own re-check.
typedef ReadyMark = ({IoSnapshot? io, double? cpu, int rss});

ReadyMark readyMark() =>
    (io: processWrites(), cpu: processCpuSeconds(), rss: peakRssBytes());

/// The one RESULT line, printed only once the run is READY (final files
/// verified and flushed); any failure exits non-zero with no RESULT.
void result(
  String tool,
  String target,
  Map<String, Object?> fields, {
  required String targetDir,
  required ReadyMark ready,
  bool childProcesses = false,
}) {
  final io = ready.io, cpu = ready.cpu;
  final read = io == null || _io0 == null
      ? null
      : io.readBytes - _io0!.readBytes;
  final drive = driveInfo(targetDir);
  // Under `dart run` the compiler shares the process (~700MiB, seconds of
  // CPU); children (curl) are not in this process's counters.
  final own = isAotRuntime() && !childProcesses;
  final all = <String, Object?>{
    ...fields,
    'scheme': _scheme,
    'runtime': isAotRuntime() ? 'aot' : 'jit',
    'cpu_s': !own || cpu == null || _cpu0 == null
        ? 'n/a'
        : (cpu - _cpu0!).toStringAsFixed(2),
    'peak_rss_MiB': own ? mib(ready.rss) : 'n/a',
    'proc_read_MiB': read == null ? 'n/a' : mib(read),
    'target_kind': drive.kind,
    'target_fs': drive.fs,
  };
  final kv = all.entries.map((e) => '${e.key}=${e.value}').join(' ');
  stdout.writeln('RESULT tool=$tool target=$target $kv');
  if (_jsonOut case final path?) {
    appendJsonl(path, {
      'kind': 'download',
      'label': _label,
      'tool': tool,
      'target': target,
      ..._env,
      ...all,
    });
  }
}

String _rate(int? bytes, int ms) =>
    bytes == null || bytes <= 0 || ms <= 0 ? 'n/a' : mib(bytes / (ms / 1000));

String _amp(int? written, int content) =>
    written == null ? 'n/a' : (written / content).toStringAsFixed(2);

Future<void> _failCleanup(OwnedDir own, Set<String> names, Object error) async {
  final left = own.discard(outputs: names);
  if (left.isNotEmpty) {
    stderr.writeln('could not remove after failure (${own.path}): $left');
  }
}

/// The per-file connection count the mirror exporter really uses for
/// [scheduler]; library_manager's `connectionsPerFile` is asserted equal to it.
int autoConnections(DownloadScheduler scheduler) {
  final exporter = LibraryMirrorExporter(
    supportedDbSchemaVersion: 1,
    scheduler: scheduler,
  );
  try {
    return exporter.connectionsPerFile;
  } finally {
    exporter.dispose();
  }
}

/// Connection plan of `pd`. `static` is a fixed number (or `auto`, the
/// exporter's static share); `policy` takes the number decided by
/// library_manager's real `connectionsForDir` (policy/policy_decision.dart,
/// run by matrix.sh) as `--decided=N --reason=...` and is tagged
/// `production-policy`; the bench cannot import that Flutter package.
({int conns, String mode, String basis, String reason}) pdPlan(
  String connsArg,
  DownloadScheduler scheduler,
  Map<String, String> flags,
) {
  if (connsArg == 'policy') {
    final n = int.tryParse(flags['decided'] ?? '');
    final reason = flags['reason'] ?? '';
    if (n == null || n < 1 || n > 8 || reason.isEmpty) {
      throw BenchFailure(
        'pd policy needs --decided=N (1-8) --reason=... from '
        'policy/policy_decision.dart; it is not computed here',
      );
    }
    return (
      conns: n,
      mode: 'production-policy',
      basis: 'connectionsForDir',
      reason: reason,
    );
  }
  if (connsArg == 'auto') {
    return (
      conns: autoConnections(scheduler),
      mode: 'static',
      basis: 'static-share',
      reason: 'n/a',
    );
  }
  final n = int.tryParse(connsArg);
  if (n == null || n < 1 || n > 8) {
    throw BenchFailure("conns must be 1-8, auto or policy: '$connsArg'");
  }
  return (conns: n, mode: 'static', basis: 'fixed', reason: 'n/a');
}

Future<void> pd(
  String outDir,
  String connsArg,
  List<String> specs,
  Map<String, String> flags, {
  Flusher? flusher,
}) async {
  final jobs = specs.map(parseJob).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  final scheduler = DownloadScheduler(
    maxConcurrent: int.parse(
      flags['sched'] ?? '${DownloadScheduler.defaultMaxConcurrent}',
    ),
  );
  final plan = pdPlan(connsArg, scheduler, flags);
  final conns = plan.conns;
  final target = flags['target'] ?? 'local';
  final names = jobNames(jobs);
  final own = OwnedDir.open(outDir);
  final logging = LoggingClient(_client(flags));
  final downloader = PatchDownloader(
    httpClient: logging,
    decompress: (_) async => null,
    maxConnections: conns,
  );
  final total = jobs.fold<int>(0, (s, j) => s + j.size);
  var lastPrint = 0;
  final agg = ByteProgressAggregator(
    totalBytes: total,
    onProgress: (d, t) {
      final now = _t0.elapsedMilliseconds;
      if (now - lastPrint > 5000) {
        lastPrint = now;
        stdout.writeln(
          '${ts()} progress ${mib(d)}MiB active=${logging.active}',
        );
      }
    },
  );
  final slots = [for (final _ in jobs) agg.slot()];
  agg.announce();
  final sampler = DirSampler([own.path])..start();
  final io0 = processWrites();
  final start = _t0.elapsedMilliseconds;
  final assets = <({String name, int fs, int vs, int fe})>[];
  try {
    await scheduler.run<void>([
      for (final (i, j) in jobs.indexed)
        () async {
          final name = assetNameOf(j.url);
          final fs = _t0.elapsedMilliseconds;
          int? vStart;
          stdout.writeln('${ts()} START $name size=${j.size}');
          await downloader.downloadToFile(
            url: j.url,
            destPath: own.file(name),
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
          assets.add((name: name, fs: fs, vs: vs, fe: fe));
          stdout.writeln(
            '${ts()} DONE $name net=${(vs - fs) / 1000}s '
            'assemble+hash=${(fe - vs) / 1000}s total=${(fe - fs) / 1000}s',
          );
        },
    ]);
    final lastDone = assets.fold<int>(start, (m, a) => a.fe > m ? a.fe : m);
    sampler.sampleNow();
    for (final j in jobs) {
      final f = File(own.file(assetNameOf(j.url)));
      if (!f.existsSync() || f.lengthSync() != j.size) {
        throw BenchFailure('${f.path} missing or wrong size after download');
      }
    }
    final flush = await (flusher ?? flushFiles)([
      for (final n in names) own.file(n),
    ]);
    final clean = own.cleanup(keep: names);
    final readyAt = _t0.elapsedMilliseconds;
    final mark = readyMark();
    final io1 = mark.io;
    sampler.stop();
    for (final j in jobs) {
      await verifyContent(own.file(assetNameOf(j.url)), j.size, j.sha);
    }
    final netSpans = mergeSpans([for (final a in assets) (a.fs, a.vs)]);
    final hashSpans = mergeSpans([for (final a in assets) (a.vs, a.fe)]);
    final single = jobs.length == 1;
    final netEnd = logging.lastEnd < 0 ? lastDone : logging.lastEnd;
    final a0 = assets.first;
    final netMs = single
        ? (netEnd.clamp(a0.fs, a0.vs) - a0.fs)
        : spansTotal(netSpans);
    final waitMs = single ? (a0.vs - netEnd).clamp(0, 1 << 30) : null;
    final readyMs = readyAt - start;
    for (final a in assets) {
      stdout.writeln(
        'ASSET pd ${a.name} start_s=${secs(a.fs - start)} '
        'verify_start_s=${secs(a.vs - start)} end_s=${secs(a.fe - start)}',
      );
    }
    stdout.writeln(
      'SUMMARY pd conns=$conns files=${jobs.length} bytes=$total '
      'requests=${logging.requests} statuses=${logging.statuses} '
      'peakBodies=${logging.peak}',
    );
    final wr = io0 == null || io1 == null
        ? null
        : io1.writeBytes - io0.writeBytes;
    result(
      'pd',
      target,
      {
        'mode': plan.mode,
        'basis': plan.basis,
        'reason': plan.reason,
        'conns': conns,
        'sched': scheduler.maxConcurrent,
        'files': jobs.length,
        'MiB': mib(total),
        'net_MiB': mib(logging.netBytes),
        'connect_s': secs(
          logging.firstResponseMs < 0 ? 0 : logging.firstResponseMs - start,
        ),
        'net_s': secs(netMs),
        'waitWrite_s': waitMs == null ? 'n/a' : secs(waitMs),
        'join_s': 'incl',
        'hash_s': secs(spansTotal(hashSpans)),
        'copy_s': 'n/a',
        'flush_s': secs(flush.inMilliseconds),
        'cleanup_s': secs(clean.inMilliseconds),
        'overlap_s': secs(spansOverlap(netSpans, hashSpans)),
        'ready_s': secs(readyMs),
        'rate_net_MiBps': _rate(logging.netBytes, netMs),
        'rate_ready_MiBps': mib(total / (readyMs / 1000)),
        'peak_live_MiB': mib(sampler.peakLive),
        'footprint_est_MiB': mib(sampler.footprintEst),
        'proc_write_MiB': wr == null ? 'n/a' : mib(wr),
        'child_write_MiB': '0.0',
        'write_amp_io': _amp(wr, total),
        // pd writes nothing outside the target directory.
        'target_write_MiB': wr == null ? 'n/a' : mib(wr),
        'local_write_MiB': '0.0',
        'content_ok': true,
      },
      targetDir: own.path,
      ready: mark,
    );
  } on Object {
    sampler.stop();
    await _failCleanup(own, names, 'pd');
    rethrow;
  } finally {
    logging.close();
  }
}

Future<void> df(
  String outDir,
  String spec,
  Map<String, String> flags, {
  Flusher? flusher,
}) async {
  final j = parseJob(spec);
  final target = flags['target'] ?? 'local';
  final name = assetNameOf(j.url);
  final own = OwnedDir.open(outDir);
  final dest = own.file(name);
  final logging = LoggingClient(_client(flags));
  final sampler = DirSampler([own.path])..start();
  final io0 = processWrites();
  final s = _t0.elapsedMilliseconds;
  try {
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
    sampler.sampleNow();
    // The engine returns before any SHA check; verification is part of ready.
    await verifyContent(dest, j.size, j.sha);
    final h = _t0.elapsedMilliseconds;
    final flush = await (flusher ?? flushFiles)([dest]);
    final clean = own.cleanup(keep: {name});
    final readyAt = _t0.elapsedMilliseconds;
    final mark = readyMark();
    final io1 = mark.io;
    sampler.stop();
    await verifyContent(dest, j.size, j.sha);
    final readyMs = readyAt - s;
    final netMs = n - s;
    stdout.writeln(
      'SUMMARY df bytes=${j.size} requests=${logging.requests} '
      'statuses=${logging.statuses} peakBodies=${logging.peak}',
    );
    final wr = io0 == null || io1 == null
        ? null
        : io1.writeBytes - io0.writeBytes;
    result(
      'df',
      target,
      {
        'mode': 'static',
        'basis': 'downloadFile-single',
        'conns': 1,
        'files': 1,
        'MiB': mib(j.size),
        'net_MiB': mib(logging.netBytes),
        'connect_s': secs(
          logging.firstResponseMs < 0 ? 0 : logging.firstResponseMs - s,
        ),
        'net_s': secs(netMs),
        'waitWrite_s': 'n/a',
        'join_s': 'n/a',
        'hash_s': secs(h - n),
        'copy_s': 'n/a',
        'flush_s': secs(flush.inMilliseconds),
        'cleanup_s': secs(clean.inMilliseconds),
        'overlap_s': '0.00',
        'ready_s': secs(readyMs),
        'rate_net_MiBps': _rate(logging.netBytes, netMs),
        'rate_ready_MiBps': mib(j.size / (readyMs / 1000)),
        'peak_live_MiB': mib(sampler.peakLive),
        'footprint_est_MiB': mib(sampler.footprintEst),
        'proc_write_MiB': wr == null ? 'n/a' : mib(wr),
        'child_write_MiB': '0.0',
        'write_amp_io': _amp(wr, j.size),
        'target_write_MiB': wr == null ? 'n/a' : mib(wr),
        'local_write_MiB': '0.0',
        'content_ok': true,
      },
      targetDir: own.path,
      ready: mark,
    );
  } on Object {
    sampler.stop();
    await _failCleanup(own, {name}, 'df');
    rethrow;
  } finally {
    logging.close();
  }
}

/// One curl run; the child's write counters are read through a handle opened
/// right after spawn (null when unsupported or the process was already gone).
Future<({int code, String out, String err, IoSnapshot? io})> _curl(
  String curl,
  List<String> args,
) async {
  final p = await Process.start(curl, args);
  final io = ChildIo.open(p.pid);
  final out = p.stdout.transform(utf8.decoder).join();
  final err = p.stderr.transform(utf8.decoder).join();
  final code = await p.exitCode;
  final snap = io?.read();
  io?.close();
  return (code: code, out: await out, err: await err, io: snap);
}

/// Models the Windows download assistant (curl, local cache, 4 ranges);
/// the algorithm, not the assistant itself.
Future<void> assist(
  String cacheDir,
  String outDir,
  List<String> specs,
  Map<String, String> flags, {
  Flusher? flusher,
}) async {
  final curl = flags['curl'] ?? 'curl';
  final segN = int.parse(flags['segments'] ?? '4');
  final target = flags['target'] ?? 'local';
  final jobs = specs.map(parseJob).toList();
  final names = jobNames(jobs);
  final cache = OwnedDir.open(cacheDir);
  final out = OwnedDir.open(outDir);
  final sampler = DirSampler([cache.path, out.path])..start();
  final io0 = processWrites();
  final start = _t0.elapsedMilliseconds;
  var probeMs = 0, netMs = 0, joinMs = 0, hashMs = 0, copyMs = 0, total = 0;
  var netBytes = 0, netKnown = true, childKnown = io0 != null;
  var childWrites = 0;
  void child(IoSnapshot? io) {
    if (io == null) {
      childKnown = false;
    } else {
      childWrites += io.writeBytes;
    }
  }

  try {
    for (final j in jobs) {
      final name = assetNameOf(j.url);
      total += j.size;
      final base = cache.file(name);
      final tp = _t0.elapsedMilliseconds;
      // Same rule as _ioClient: a self-signed certificate only from loopback.
      final insecure =
          flags['insecure'] == 'true' && isLoopbackHost(Uri.parse(j.url).host);
      final probe = await _curl(curl, [
        if (insecure) '-k' else '--location',
        '--fail', '--silent', '--show-error', '--range', '0-0',
        '--max-filesize', '1024', '--max-time', '60', '--dump-header',
        '$base.probe.hdr', '-o', '$base.probe', j.url, //
      ]);
      probeMs += _t0.elapsedMilliseconds - tp;
      child(probe.io);
      final hdrFile = File('$base.probe.hdr');
      final hdr = hdrFile.existsSync()
          ? hdrFile.readAsStringSync().toLowerCase()
          : '';
      final ranged =
          probe.code == 0 && hdr.contains('content-range: bytes 0-0/${j.size}');
      final n = ranged && j.size >= 67108864 ? segN : 1;
      stdout.writeln('${ts()} assist $name probe_ok=$ranged segments=$n');
      final t0 = _t0.elapsedMilliseconds;
      final per = j.size ~/ n;
      final procs =
          <Future<({int code, String out, String err, IoSnapshot? io})>>[];
      for (var k = 0; k < n; k++) {
        final s = k * per;
        final e = k == n - 1 ? j.size - 1 : (k + 1) * per - 1;
        procs.add(
          _curl(curl, [
            if (insecure) '-k' else '--location',
            '--fail', '--silent', '--show-error',
            '--write-out', '%{size_download}',
            if (n > 1) ...['--range', '$s-$e'],
            '-o', k == 0 ? '$base.partial' : '$base.seg$k', j.url, //
          ]),
        );
      }
      for (final r in await Future.wait(procs)) {
        if (r.code != 0) throw BenchFailure('curl failed: ${r.err}');
        child(r.io);
        final b = int.tryParse(r.out.trim());
        if (b == null) {
          netKnown = false;
        } else {
          netBytes += b;
        }
      }
      final t1 = _t0.elapsedMilliseconds;
      sampler.sampleNow();
      // CurlAppend: segments appended to segment 0 in the (local) cache.
      if (n > 1) {
        final dst = await File('$base.partial').open(mode: FileMode.append);
        try {
          for (var k = 1; k < n; k++) {
            final seg = File('$base.seg$k');
            final inp = await seg.open();
            try {
              for (
                var c = await inp.read(1 << 20);
                c.isNotEmpty;
                c = await inp.read(1 << 20)
              ) {
                await dst.writeFrom(c);
              }
            } finally {
              await inp.close();
            }
            await seg.delete();
          }
        } finally {
          await dst.close();
        }
      }
      final t2 = _t0.elapsedMilliseconds;
      sampler.sampleNow();
      await verifyContent('$base.partial', j.size, j.sha);
      final t3 = _t0.elapsedMilliseconds;
      // Copy under a temporary name; the final name only ever holds
      // content that was verified.
      final tmp = out.derived(name, '.bench-copy');
      await File('$base.partial').copy(tmp);
      await File(tmp).rename(out.file(name));
      final t4 = _t0.elapsedMilliseconds;
      sampler.sampleNow();
      netMs += t1 - t0;
      joinMs += t2 - t1;
      hashMs += t3 - t2;
      copyMs += t4 - t3;
    }
    final flush = await (flusher ?? flushFiles)([
      for (final n in names) out.file(n),
    ]);
    final clean = cache.cleanup(keep: {}) + out.cleanup(keep: names);
    final readyAt = _t0.elapsedMilliseconds;
    final mark = readyMark();
    final io1 = mark.io;
    sampler.stop();
    for (final j in jobs) {
      await verifyContent(out.file(assetNameOf(j.url)), j.size, j.sha);
    }
    final readyMs = readyAt - start;
    stdout.writeln('SUMMARY assist files=${jobs.length} bytes=$total');
    final wr = io0 == null || io1 == null
        ? null
        : io1.writeBytes - io0.writeBytes;
    final all = wr == null || !childKnown ? null : wr + childWrites;
    result(
      'assist',
      target,
      {
        'mode': 'assistant-imitation',
        'basis': 'curl-algorithm-not-real-assistant',
        'conns': segN,
        'files': jobs.length,
        'MiB': mib(total),
        'net_MiB': netKnown ? mib(netBytes) : 'n/a',
        'connect_s': secs(probeMs),
        'net_s': secs(netMs),
        'waitWrite_s': 'n/a',
        'join_s': secs(joinMs),
        'hash_s': secs(hashMs),
        'copy_s': secs(copyMs),
        'flush_s': secs(flush.inMilliseconds),
        'cleanup_s': secs(clean.inMilliseconds),
        'overlap_s': '0.00',
        'ready_s': secs(readyMs),
        'rate_net_MiBps': netKnown ? _rate(netBytes, netMs) : 'n/a',
        'rate_ready_MiBps': mib(total / (readyMs / 1000)),
        'peak_live_MiB': mib(sampler.peakLive),
        'footprint_est_MiB': mib(sampler.footprintEst),
        'proc_write_MiB': wr == null ? 'n/a' : mib(wr),
        'child_write_MiB': childKnown ? mib(childWrites) : 'n/a',
        'write_amp_io': _amp(all, total),
        // By construction: only the final copy reaches the target.
        'target_write_MiB': mib(total),
        'local_write_MiB': all == null ? 'n/a' : mib(all - total),
        'content_ok': true,
      },
      targetDir: out.path,
      ready: mark,
      childProcesses: true,
    );
  } on Object {
    sampler.stop();
    await _failCleanup(out, names, 'assist');
    await _failCleanup(cache, {}, 'assist');
    rethrow;
  }
}

/// Proposed staging: the real [PatchDownloader] into a local [cacheDir], then
/// serial hashed copies to [outDir] that overlap the remaining downloads.
Future<void> stage(
  String cacheDir,
  String outDir,
  String connsArg,
  List<String> specs,
  Map<String, String> flags, {
  Flusher? flusher,
}) async {
  if (connsArg == 'policy') {
    throw BenchFailure('stage downloads to a local disk; use 1-8 or auto');
  }
  final jobs = specs.map(parseJob).toList()
    ..sort((a, b) => b.size.compareTo(a.size));
  final scheduler = DownloadScheduler(
    maxConcurrent: int.parse(
      flags['sched'] ?? '${DownloadScheduler.defaultMaxConcurrent}',
    ),
  );
  final plan = pdPlan(connsArg, scheduler, flags);
  final target = flags['target'] ?? 'local';
  final names = jobNames(jobs);
  final cache = OwnedDir.open(cacheDir);
  final out = OwnedDir.open(outDir);
  final logging = LoggingClient(_client(flags));
  final downloader = PatchDownloader(
    httpClient: logging,
    decompress: (_) async => null,
    maxConnections: plan.conns,
  );
  final total = jobs.fold<int>(0, (s, j) => s + j.size);
  final sampler = DirSampler([cache.path, out.path])..start();
  final io0 = processWrites();
  final start = _t0.elapsedMilliseconds;
  final netSpans = <Span>[], hashSpans = <Span>[], copySpans = <Span>[];
  var copied = 0;
  var lastDownload = start;
  Future<void> copies = Future.value();
  Object? copyError;
  try {
    await scheduler.run<void>([
      for (final j in jobs)
        () async {
          final name = assetNameOf(j.url);
          final local = cache.file(name);
          final fs = _t0.elapsedMilliseconds;
          int? vs;
          await downloader.downloadToFile(
            url: j.url,
            destPath: local,
            expectedSize: j.size,
            expectedSha256: j.sha,
            resumeToken: 'bench:$name:${j.sha}',
            onVerifyProgress: (_, _) => vs ??= _t0.elapsedMilliseconds,
          );
          final fe = _t0.elapsedMilliseconds;
          if (fe > lastDownload) lastDownload = fe;
          netSpans.add((fs, vs ?? fe));
          hashSpans.add((vs ?? fe, fe));
          stdout.writeln('${ts()} DOWNLOADED $name, queued for copy');
          copies = copies.then((_) async {
            if (copyError != null) return;
            final cs = _t0.elapsedMilliseconds;
            try {
              copied += await copyVerified(
                local,
                out.derived(name, '.bench-copy'),
                out.file(name),
                j.size,
                j.sha,
              );
              File(local).deleteSync();
            } on Object catch (e) {
              copyError = e;
              stdout.writeln('${ts()} COPY FAILED $name: $e');
              return;
            }
            copySpans.add((cs, _t0.elapsedMilliseconds));
            sampler.sampleNow();
            stdout.writeln('${ts()} COPIED $name');
          });
        },
    ]);
    await copies;
    if (copyError case final e?) throw BenchFailure('copy failed: $e');
    final flush = await (flusher ?? flushFiles)([
      for (final n in names) out.file(n),
    ]);
    final clean = cache.cleanup(keep: {}) + out.cleanup(keep: names);
    final readyAt = _t0.elapsedMilliseconds;
    final mark = readyMark();
    final io1 = mark.io;
    sampler.stop();
    for (final j in jobs) {
      await verifyContent(out.file(assetNameOf(j.url)), j.size, j.sha);
    }
    final net = mergeSpans(netSpans), copy = mergeSpans(copySpans);
    final netMs = spansTotal(net);
    final readyMs = readyAt - start;
    final wr = io0 == null || io1 == null
        ? null
        : io1.writeBytes - io0.writeBytes;
    stdout.writeln(
      'SUMMARY stage conns=${plan.conns} files=${jobs.length} bytes=$total '
      'requests=${logging.requests} statuses=${logging.statuses}',
    );
    result(
      'stage',
      target,
      {
        'mode': 'local-staging',
        'basis': plan.basis,
        'reason': 'n/a',
        'conns': plan.conns,
        'sched': scheduler.maxConcurrent,
        'files': jobs.length,
        'MiB': mib(total),
        'net_MiB': mib(logging.netBytes),
        'connect_s': secs(
          logging.firstResponseMs < 0 ? 0 : logging.firstResponseMs - start,
        ),
        'net_s': secs(netMs),
        'waitWrite_s': 'n/a',
        'join_s': 'incl',
        'hash_s': secs(spansTotal(mergeSpans(hashSpans))),
        // copy_s includes each file's FlushFileBuffers, so flush_s is ~0 here.
        'copy_s': secs(spansTotal(copy)),
        // The copy time no download hides: what staging adds at the end.
        'copy_tail_s': secs(
          ((copy.isEmpty ? lastDownload : copy.last.$2) - lastDownload).clamp(
            0,
            1 << 30,
          ),
        ),
        'flush_s': secs(flush.inMilliseconds),
        'cleanup_s': secs(clean.inMilliseconds),
        'overlap_s': secs(spansOverlap(net, copy)),
        'ready_s': secs(readyMs),
        'rate_net_MiBps': _rate(logging.netBytes, netMs),
        'rate_ready_MiBps': mib(total / (readyMs / 1000)),
        'peak_live_MiB': mib(sampler.peakLive),
        'footprint_est_MiB': mib(sampler.footprintEst),
        'local_footprint_est_MiB': mib(sampler.footprintUnder(cache.path)),
        'proc_write_MiB': wr == null ? 'n/a' : mib(wr),
        'child_write_MiB': '0.0',
        'write_amp_io': _amp(wr, total),
        'target_write_MiB': mib(copied),
        'local_write_MiB': wr == null ? 'n/a' : mib(wr - copied),
        'cache_kind': driveInfo(cache.path).kind,
        'content_ok': true,
      },
      targetDir: out.path,
      ready: mark,
    );
  } on Object {
    sampler.stop();
    await copies.catchError((_) {});
    await _failCleanup(out, names, 'stage');
    await _failCleanup(cache, names, 'stage');
    rethrow;
  } finally {
    logging.close();
  }
}

/// Write throughput of [dir] per write size (KiB) and per number of files
/// written at once (`--writers=1,4`), the way the engine writes.
Future<void> writetest(
  String dir,
  int totalMiB,
  List<int> blocksKiB,
  Map<String, String> flags,
) async {
  final rounds = int.parse(flags['rounds'] ?? '3');
  final writers = [
    for (final w in (flags['writers'] ?? '1').split(',')) int.parse(w),
  ];
  if (totalMiB < 1 ||
      blocksKiB.isEmpty ||
      rounds < 1 ||
      blocksKiB.any((b) => b < 1) ||
      writers.any((w) => w < 1 || w > totalMiB)) {
    throw BenchFailure(
      'writetest needs MiB >= 1, rounds >= 1, blocks >= 1 '
      'and 1 <= writers <= MiB',
    );
  }
  final own = OwnedDir.open(dir);
  final variants = [
    for (final b in blocksKiB)
      for (final w in writers) (kib: b, writers: w),
  ];
  final total = totalMiB << 20;
  final drive = driveInfo(own.path);
  for (var round = 0; round < rounds; round++) {
    for (var i = 0; i < variants.length; i++) {
      final (:kib, writers: n) = variants[(i + round) % variants.length];
      final block = Uint8List(kib << 10);
      for (var k = 0; k < block.length; k++) {
        block[k] = (k * 131 + round) & 0xff;
      }
      Future<void> writeOne(String path, int bytes) async {
        final out = await File(path).open(mode: FileMode.write);
        try {
          for (var done = 0; done < bytes; done += block.length) {
            final left = bytes - done;
            await out.writeFrom(block, 0, left < block.length ? left : null);
          }
          await out.flush();
        } finally {
          await out.close();
        }
      }

      final paths = [
        for (var w = 0; w < n; w++) own.file('writetest_${kib}k_$w.bin'),
      ];
      final sw = Stopwatch()..start();
      final int ms;
      try {
        await Future.wait([for (final p in paths) writeOne(p, total ~/ n)]);
        ms = sw.elapsedMilliseconds;
      } finally {
        for (final p in paths) {
          final f = File(p);
          if (f.existsSync()) f.deleteSync();
        }
      }
      // The rate counts what was written: n * (total ~/ n) bytes.
      final written = (total ~/ n) * n;
      final rate = ms == 0
          ? 'n/a'
          : (written / 1048576 / (ms / 1000)).toStringAsFixed(2);
      stdout.writeln(
        'WRITETEST round=${round + 1} block_KiB=$kib writers=$n MiB=$totalMiB '
        'seconds=${secs(ms)} MiBps=$rate drive=${drive.kind}/${drive.fs}',
      );
      if (_jsonOut case final path?) {
        appendJsonl(path, {
          'kind': 'writetest',
          'label': _label,
          ..._env,
          'tool': 'writetest',
          'mode': 'block-${kib}KiB-writers-$n',
          'MiB': '$totalMiB',
          'target_kind': drive.kind,
          'target_fs': drive.fs,
          'runtime': isAotRuntime() ? 'aot' : 'jit',
          'write_s': secs(ms),
          'rate_MiBps': rate,
        });
      }
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: see the header of bin/bench.dart');
    exit(2);
  }
  final f = parseFlags(args.skip(1).toList());
  final r = f.rest;
  _io0 = processWrites();
  _cpu0 = processCpuSeconds();
  _jsonOut = f.flags['json'];
  _label = f.flags['label'] ?? 'n/a';
  // http vs https of the same variant must not share a cell.
  _scheme = r
      .map((a) => RegExp(r'\b(https?)://').firstMatch(a)?.group(1))
      .firstWhere((s) => s != null, orElse: () => 'n/a')!;
  try {
    if (_jsonOut != null) _env = await runEnvironment();
    switch (args.first) {
      case 'probe':
        await probe(r[0], r[1], f.flags);
      case 'scratch':
        stdout.writeln(OwnedDir.open(r[0]).path);
      case 'scratch-rm':
        OwnedDir.removeTree(r[0]);
      case 'pd':
        await pd(r[0], r[1], r.sublist(2), f.flags);
      case 'df':
        await df(r[0], r[1], f.flags);
      case 'assist':
        await assist(r[0], r[1], r.sublist(2), f.flags);
      case 'writetest':
        await writetest(r[0], int.parse(r[1]), [
          for (final b in r.sublist(2)) int.parse(b),
        ], f.flags);
      case 'stage':
        await stage(r[0], r[1], r[2], r.sublist(3), f.flags);
      case 'hash':
        final s = _t0.elapsedMilliseconds;
        final d = await hashFile(r[0]);
        stdout.writeln('hash ${(_t0.elapsedMilliseconds - s) / 1000}s $d');
      default:
        stderr.writeln('unknown command ${args.first}');
        exit(2);
    }
  } on Object catch (e, st) {
    stderr.writeln('FAILED: $e');
    if (e is! BenchFailure) stderr.writeln(st);
    exit(1);
  }
  exit(0);
}

/// `--insecure` accepts a self-signed certificate, from loopback hosts only.
HttpClient _ioClient(Map<String, String> flags) {
  final c = HttpClient();
  if (flags['insecure'] == 'true') {
    c.badCertificateCallback = (_, host, _) => isLoopbackHost(host);
  }
  return c;
}

http.Client _client(Map<String, String> flags) => IOClient(_ioClient(flags));

bool isLoopbackHost(String host) =>
    host == 'localhost' ||
    (InternetAddress.tryParse(host)?.isLoopback ?? false);
