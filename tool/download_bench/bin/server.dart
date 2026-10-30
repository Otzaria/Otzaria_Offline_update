// Local test server for issue #149.
// dart run bin/server.dart <port> <range|norange> <perConnBytesPerSec|0> <size> [size...]
// Serves GET /f/<size>/<name>: the first <size> bytes of one deterministic
// pseudo-random buffer. Prints "SHA <size> <sha256>" for each size at startup.
// range   -> honours a single "bytes=a-b" / "bytes=a-" Range with 206 (+ETag)
// norange -> ignores Range, always 200 with the full body (Accept-Ranges still sent,
//            like the CDN behaviour recorded in AGENTS.md)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

late Uint8List buf;
var active = 0;
var peak = 0;
var reqs = 0;
final sw = Stopwatch()..start();
String ts() => (sw.elapsedMilliseconds / 1000).toStringAsFixed(2).padLeft(7);

Future<void> main(List<String> a) async {
  final port = int.parse(a[0]);
  final honour = a[1] == 'range';
  final rate = int.parse(a[2]);
  final sizes = a.sublist(3).map(int.parse).toList();
  final maxSize = sizes.reduce((x, y) => x > y ? x : y);
  buf = Uint8List(maxSize);
  var x = 0x9E3779B9;
  final view = buf.buffer.asUint32List(0, maxSize ~/ 4);
  for (var i = 0; i < view.length; i++) {
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    view[i] = x;
  }
  for (final s in sizes) {
    stdout.writeln(
      'SHA $s ${sha256.convert(Uint8List.sublistView(buf, 0, s))}',
    );
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('READY port=$port mode=${a[1]} perConnRate=$rate');
  await for (final req in server) {
    unawaited(handle(req, honour, rate));
  }
}

Future<void> handle(HttpRequest req, bool honour, int rate) async {
  final id = ++reqs;
  final seg = req.uri.pathSegments;
  final res = req.response;
  if (seg.length < 3 || seg[0] != 'f') {
    res.statusCode = 404;
    await res.close();
    return;
  }
  final size = int.parse(seg[1]);
  var start = 0, end = size - 1, status = 200;
  final range = req.headers.value('range');
  if (honour && range != null) {
    final m = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
    if (m != null) {
      start = int.parse(m[1]!);
      end = m[2]!.isEmpty ? size - 1 : int.parse(m[2]!);
      if (end >= size) end = size - 1;
      if (start > end) {
        res.statusCode = 416;
        res.headers.set('Content-Range', 'bytes */$size');
        await res.close();
        return;
      }
      status = 206;
      res.headers.set('Content-Range', 'bytes $start-$end/$size');
    }
  }
  res.statusCode = status;
  res.headers.set('Accept-Ranges', 'bytes');
  res.headers.set('ETag', '"etag-$size"');
  res.headers.contentType = ContentType.binary;
  res.contentLength = end - start + 1;
  res.bufferOutput = false;
  active++;
  if (active > peak) peak = active;
  stdout.writeln(
    '${ts()} #$id ${req.method} ${req.uri.path} Range=${range ?? '-'} '
    '-> $status active=$active peak=$peak',
  );
  if (req.method == 'HEAD') {
    active--;
    await res.close();
    return;
  }
  const chunk = 64 * 1024;
  final t = Stopwatch()..start();
  var sent = 0;
  try {
    for (var p = start; p <= end; p += chunk) {
      final e = p + chunk - 1 < end ? p + chunk - 1 : end;
      res.add(Uint8List.sublistView(buf, p, e + 1));
      await res.flush();
      sent += e - p + 1;
      if (rate > 0) {
        final due = sent * 1000000 ~/ rate;
        final ahead = due - t.elapsedMicroseconds;
        if (ahead > 0) {
          await Future<void>.delayed(Duration(microseconds: ahead));
        }
      }
    }
    await res.close();
    stdout.writeln('${ts()} #$id done sent=$sent active=${active - 1}');
  } catch (e) {
    stdout.writeln('${ts()} #$id aborted after $sent bytes');
  } finally {
    active--;
  }
}
