import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:download_bench/meter.dart';
import 'package:download_bench/scratch.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadException;
import 'package:test/test.dart';

import '../bin/bench.dart' as bench;

const _size = 1 << 20;
const _wrong =
    '0000000000000000000000000000000000000000000000000000000000000000';

void main() {
  late HttpServer server;
  late Directory tmp;
  late Uint8List data;
  late String goodSha;
  late String url;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('dbench_e2e_');
    data = Uint8List(_size);
    for (var i = 0; i < _size; i++) {
      data[i] = (i * 31 + 7) & 0xff;
    }
    final f = File('${tmp.path}/ref.bin')..writeAsBytesSync(data);
    goodSha = await hashFile(f.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.headers.set('Accept-Ranges', 'bytes');
      req.response.headers.set('ETag', '"v1"');
      final range = req.headers.value('range');
      if (range != null) {
        final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
        final a = int.parse(m[1]!);
        final b = m[2]!.isEmpty ? _size - 1 : int.parse(m[2]!);
        req.response.statusCode = 206;
        req.response.headers.set('Content-Range', 'bytes $a-$b/$_size');
        req.response.contentLength = b - a + 1;
        req.response.add(Uint8List.sublistView(data, a, b + 1));
      } else {
        req.response.contentLength = _size;
        req.response.add(data);
      }
      await req.response.close();
    });
    url = 'http://127.0.0.1:${server.port}/f/$_size/test.bin';
  });
  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  Future<Never> failingFlush(List<String> p) async =>
      throw BenchFailure('flush boom');

  test('df: wrong sha fails and leaves no output', () async {
    final dir = '${tmp.path}/df';
    await expectLater(
      bench.df(dir, '$url,$_size,$_wrong', {}),
      throwsA(isA<BenchFailure>()),
    );
    expect(File('$dir/test.bin').existsSync(), isFalse);
  });

  test('df: good sha is ready and the output is kept', () async {
    final dir = '${tmp.path}/df-ok';
    await bench.df(dir, '$url,$_size,$goodSha', {});
    expect(File('$dir/test.bin').lengthSync(), _size);
  });

  test('df: a failing flush fails the run and removes the output', () async {
    final dir = '${tmp.path}/df-flush';
    await expectLater(
      bench.df(dir, '$url,$_size,$goodSha', {}, flusher: failingFlush),
      throwsA(isA<BenchFailure>()),
    );
    expect(File('$dir/test.bin').existsSync(), isFalse);
  });

  test('pd: wrong sha fails and leaves no output', () async {
    final dir = '${tmp.path}/pd';
    await expectLater(
      bench.pd(dir, '1', ['$url,$_size,$_wrong'], {}),
      throwsA(anything),
    );
    expect(File('$dir/test.bin').existsSync(), isFalse);
  });

  test('pd: a failing flush fails the run', () async {
    final dir = '${tmp.path}/pd-flush';
    await expectLater(
      bench.pd(dir, '1', ['$url,$_size,$goodSha'], {}, flusher: failingFlush),
      throwsA(isA<BenchFailure>()),
    );
    expect(File('$dir/test.bin').existsSync(), isFalse);
  });

  List<String> dataFiles(String dir) => [
    for (final f in Directory(dir).listSync().whereType<File>())
      if (!f.path.endsWith(ownedMarker) && !f.path.endsWith('.lock')) f.path,
  ];

  test('stage: wrong sha fails, nothing reaches the target', () async {
    final out = '${tmp.path}/s-out', cache = '${tmp.path}/s-cache';
    await expectLater(
      bench.stage(cache, out, '1', ['$url,$_size,$_wrong'], {}),
      throwsA(isA<PatchDownloadException>()),
    );
    expect(dataFiles(out), isEmpty);
    expect(dataFiles(cache), isEmpty);
  });

  test('stage: several files are all copied, verified, and unstaged', () async {
    final out = '${tmp.path}/s-many', cache = '${tmp.path}/s-many-c';
    final base = url.substring(0, url.lastIndexOf('/'));
    await bench.stage(cache, out, '1', [
      for (final n in ['a.bin', 'b.bin', 'c.bin']) '$base/$n,$_size,$goodSha',
    ], {});
    expect(dataFiles(out).map((f) => f.split(RegExp(r'[\\/]')).last).toSet(), {
      'a.bin',
      'b.bin',
      'c.bin',
    });
    expect(dataFiles(cache), isEmpty);
  });

  test('writetest: bad arguments fail before touching the disk', () async {
    final dir = '${tmp.path}/wt-bad';
    await expectLater(
      bench.writetest(dir, 4, [64], {'writers': '0'}),
      throwsA(isA<BenchFailure>()),
    );
    await expectLater(
      bench.writetest(dir, 4, [64], {'rounds': '0'}),
      throwsA(isA<BenchFailure>()),
    );
    expect(Directory(dir).existsSync(), isFalse);
  });

  test('writetest: uneven split leaves no scratch files', () async {
    final dir = '${tmp.path}/wt';
    await bench.writetest(dir, 4, [1024], {'writers': '3', 'rounds': '1'});
    expect(dataFiles(dir), isEmpty);
  });

  test('--insecure trusts loopback only', () {
    expect(bench.isLoopbackHost('127.0.0.1'), isTrue);
    expect(bench.isLoopbackHost('localhost'), isTrue);
    expect(bench.isLoopbackHost('::1'), isTrue);
    expect(bench.isLoopbackHost('github.com'), isFalse);
    expect(bench.isLoopbackHost('10.0.0.1'), isFalse);
  });

  test('stage: good run leaves only the verified target file', () async {
    final out = '${tmp.path}/s-out2', cache = '${tmp.path}/s-cache2';
    await bench.stage(cache, out, '1', ['$url,$_size,$goodSha'], {});
    expect(dataFiles(out), [endsWith('test.bin')]);
    expect(await hashFile('$out/test.bin'), goodSha);
    expect(dataFiles(cache), isEmpty, reason: 'staged copy must be removed');
  });

  test('stage: a failing flush fails the run and removes the output', () async {
    final out = '${tmp.path}/s-out3';
    await expectLater(
      bench.stage(
        '${tmp.path}/s-cache3',
        out,
        '1',
        ['$url,$_size,$goodSha'],
        {},
        flusher: failingFlush,
      ),
      throwsA(isA<BenchFailure>()),
    );
    expect(dataFiles(out), isEmpty);
  });

  test('stage: refuses the production policy (local cache is not a drive)', () {
    expect(
      bench.stage('${tmp.path}/c', '${tmp.path}/o', 'policy', [
        '$url,$_size,$goodSha',
      ], {}),
      throwsA(isA<BenchFailure>()),
    );
  });

  test('assist: wrong sha fails, no output, no copy', () async {
    final r = Process.runSync('curl', ['--version']);
    if (r.exitCode != 0) {
      markTestSkipped('curl not available');
      return;
    }
    final out = '${tmp.path}/a-out';
    await expectLater(
      bench.assist(
        '${tmp.path}/a-cache',
        out,
        ['$url,$_size,$_wrong'],
        {'segments': '1'},
      ),
      throwsA(isA<BenchFailure>()),
    );
    expect(
      Directory(out).listSync().whereType<File>().map((e) => e.path),
      everyElement(endsWith(ownedMarker)),
    );
  });

  test('assist: good run keeps only the verified output', () async {
    final r = Process.runSync('curl', ['--version']);
    if (r.exitCode != 0) {
      markTestSkipped('curl not available');
      return;
    }
    final out = '${tmp.path}/a-out2';
    await bench.assist(
      '${tmp.path}/a-cache2',
      out,
      ['$url,$_size,$goodSha'],
      {'segments': '1'},
    );
    expect(File('$out/test.bin').lengthSync(), _size);
    expect(File('$out/test.bin.bench-copy').existsSync(), isFalse);
  });
}
