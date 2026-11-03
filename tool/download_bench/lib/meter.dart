// IO counters = bytes written (incl. rewrites); occupancy/footprint = file
// sizes seen, not bytes written; spans = wall-clock, parallel work merged.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'scratch.dart';

typedef IoSnapshot = ({int writeBytes, int writeOps});

DynamicLibrary? _k32Lib;
DynamicLibrary get _k32 => _k32Lib ??= DynamicLibrary.open('kernel32.dll');

IoSnapshot? _ioOfHandle(int handle) {
  final getIo = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint64>),
        int Function(int, Pointer<Uint64>)
      >('GetProcessIoCounters');
  final p = calloc<Uint64>(6);
  try {
    if (getIo(handle, p) == 0) return null;
    return (writeBytes: p[4], writeOps: p[1]);
  } finally {
    calloc.free(p);
  }
}

/// Write counters of this process (Windows); null elsewhere.
IoSnapshot? processWrites() {
  if (!Platform.isWindows) return null;
  final getCurrent = _k32.lookupFunction<IntPtr Function(), int Function()>(
    'GetCurrentProcess',
  );
  return _ioOfHandle(getCurrent());
}

/// Keeps a child's process handle so its counters can be read after exit.
class ChildIo {
  ChildIo._(this._handle);
  final int _handle;

  /// Right after spawn; null when unsupported or the process is gone.
  static ChildIo? open(int childPid) {
    if (!Platform.isWindows) return null;
    final openProcess = _k32
        .lookupFunction<
          IntPtr Function(Uint32, Int32, Uint32),
          int Function(int, int, int)
        >('OpenProcess');
    // QUERY_INFORMATION | QUERY_LIMITED_INFORMATION
    final h = openProcess(0x0400 | 0x1000, 0, childPid);
    return h == 0 ? null : ChildIo._(h);
  }

  IoSnapshot? read() => _ioOfHandle(_handle);

  void close() {
    _k32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseHandle',
    )(_handle);
  }
}

/// Samples file sizes under [dirs]: [peakLive] is the largest live total,
/// [footprintEst] the sum of per-file peaks. Occupancy, not bytes written.
class DirSampler {
  DirSampler(Iterable<String> dirs) : dirs = [for (final d in dirs) _canon(d)];
  final List<String> dirs;
  final peaks = <String, int>{};
  Timer? _timer;
  int peakLive = 0;

  static String _canon(String d) {
    final dir = Directory(d);
    return dir.existsSync()
        ? dir.resolveSymbolicLinksSync()
        : dir.absolute.path;
  }

  void start() {
    sampleNow();
    _timer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => sampleNow(),
    );
  }

  void stop() {
    _timer?.cancel();
    sampleNow();
  }

  /// Call at phase boundaries; the timer alone cannot fire while sync I/O runs.
  void sampleNow() {
    var live = 0;
    for (final d in dirs) {
      final dir = Directory(d);
      if (!dir.existsSync()) continue;
      try {
        for (final e in dir.listSync(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          try {
            final n = e.lengthSync();
            live += n;
            if (n > (peaks[e.path] ?? 0)) peaks[e.path] = n;
          } on FileSystemException {
            // deleted between list and stat
          }
        }
      } on FileSystemException {
        // directory changing under us
      }
    }
    if (live > peakLive) peakLive = live;
  }

  int get footprintEst => peaks.values.fold(0, (a, b) => a + b);

  int footprintUnder(String dir) {
    final prefix = _canon(dir);
    final withSep = prefix.endsWith(Platform.pathSeparator)
        ? prefix
        : '$prefix${Platform.pathSeparator}';
    var sum = 0;
    peaks.forEach((path, n) {
      if (path == prefix || path.startsWith(withSep)) sum += n;
    });
    return sum;
  }
}

typedef FlushOpen = RandomAccessFile Function(String path);
typedef Flusher = Future<Duration> Function(List<String> paths);

RandomAccessFile _openForFlush(String path) =>
    File(path).openSync(mode: FileMode.append);

/// FlushFileBuffers on each of [paths]. Every handle is closed even when its
/// flush throws; any failure makes the whole call throw [BenchFailure].
Future<Duration> flushFiles(List<String> paths, {FlushOpen? open}) async {
  final sw = Stopwatch()..start();
  final errors = <String>[];
  for (final p in paths) {
    RandomAccessFile? f;
    try {
      f = (open ?? _openForFlush)(p);
      await f.flush();
    } on Object catch (e) {
      errors.add('flush $p: $e');
    } finally {
      try {
        await f?.close();
      } on Object catch (e) {
        errors.add('close $p: $e');
      }
    }
  }
  if (errors.isNotEmpty) throw BenchFailure(errors.join('; '));
  return sw.elapsed;
}

/// Hex SHA-256 through the engine's native hash (the one the tool ships), so
/// every path is hashed by the same implementation.
Future<String> hashFile(String path) async {
  final s = Sha256Stream();
  try {
    await for (final c in File(path).openRead()) {
      s.add(c);
    }
    return s.close();
  } finally {
    s.dispose();
  }
}

/// Size and SHA-256 of [path] must match; otherwise throws [BenchFailure].
Future<void> verifyContent(String path, int size, String sha) async {
  final f = File(path);
  if (!f.existsSync()) throw BenchFailure('missing output $path');
  final len = f.lengthSync();
  if (len != size) throw BenchFailure('size $len != $size for $path');
  final got = await hashFile(path);
  if (got != sha.toLowerCase()) {
    throw BenchFailure('sha mismatch for $path: $got != $sha');
  }
}

typedef Span = (int start, int end);

/// Merged, sorted, non-overlapping spans.
List<Span> mergeSpans(Iterable<Span> spans) {
  final s = spans.where((e) => e.$2 > e.$1).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <Span>[];
  for (final e in s) {
    if (out.isNotEmpty && e.$1 <= out.last.$2) {
      if (e.$2 > out.last.$2) out[out.length - 1] = (out.last.$1, e.$2);
    } else {
      out.add(e);
    }
  }
  return out;
}

int spansTotal(List<Span> merged) => merged.fold(0, (a, e) => a + e.$2 - e.$1);

/// Wall time during which both merged span lists are active.
int spansOverlap(List<Span> a, List<Span> b) {
  var i = 0, j = 0, sum = 0;
  while (i < a.length && j < b.length) {
    final lo = a[i].$1 > b[j].$1 ? a[i].$1 : b[j].$1;
    final hi = a[i].$2 < b[j].$2 ? a[i].$2 : b[j].$2;
    if (hi > lo) sum += hi - lo;
    if (a[i].$2 < b[j].$2) {
      i++;
    } else {
      j++;
    }
  }
  return sum;
}

double median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Parses a `RESULT k=v k=v` line; null for any other line.
Map<String, String>? parseResult(String line) {
  if (!line.startsWith('RESULT ')) return null;
  return {
    for (final kv in line.substring(7).split(' '))
      if (kv.contains('='))
        kv.substring(0, kv.indexOf('=')): kv.substring(kv.indexOf('=') + 1),
  };
}

String mib(num bytes) => (bytes / 1048576).toStringAsFixed(1);
String secs(num ms) => (ms / 1000).toStringAsFixed(2);
