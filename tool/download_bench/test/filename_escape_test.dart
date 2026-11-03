import 'dart:convert';
import 'dart:io';

import 'package:download_bench/scratch.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import '../bin/bench.dart' as bench;

// Last path segments as the tool decodes them from the URL.
const _bad = [
  '%2e%2e%5cescaped.txt',
  '..%2fescaped.txt',
  '%2e%2e',
  '%2e',
  '%252e%252e%255cescaped.txt',
  '%5cescaped.txt',
  '%2fescaped.txt',
  'C%3a%5cescaped.txt',
  'a.txt%3astream',
  'CON',
  'nul.txt',
  'COM1',
  'lpt9.bin',
  'x.bin.',
  'x.bin%20',
  'PROGRA~1',
  'a%3Cb',
  'a%22b',
  'a%7Cb',
  'a%3Fb',
  'a%2Ab',
  'a.bin.lock',
  'a.bin.resume',
  'a.bin.segments',
  'a.bin.seg-1',
  'a.bin.seg2',
  'a.bin.joining',
  'a.bin.bench-copy',
  'a.bin.partial',
  'a.bin.part-001.resume',
  '.download_bench_owned',
  'a.bin.0123456789ab',
];

void main() {
  late Directory tmp;
  late File foreign;
  late HttpServer server;
  final data = utf8.encode('REPLACED');
  late String sha;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('dbench_escape_');
    foreign = File('${tmp.path}/escaped.txt')
      ..writeAsStringSync('KEEP USER CONTENT');
    sha = Sha256Stream.ofBytes(data);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.contentLength = data.length;
      r.response.add(data);
      await r.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  String url(String last) => 'http://127.0.0.1:${server.port}/files/$last';
  String spec(String last) => '${url(last)},${data.length},$sha';
  void untouched() => expect(foreign.readAsStringSync(), 'KEEP USER CONTENT');

  test('names are refused by the shared check, double encoding included', () {
    for (final raw in _bad) {
      expect(
        () => assetNameOf(url(raw)),
        throwsA(isA<BenchFailure>()),
        reason: raw,
      );
    }
    for (final ok in [
      'library.db.zst',
      'v35 patch.bin',
      'חומש.zip',
      'a-b_c.7z',
    ]) {
      expect(assetNameOf(url(Uri.encodeComponent(ok))), ok);
    }
  });

  test('OwnedDir.file refuses separators, traversal and links', () {
    final own = OwnedDir.open('${tmp.path}/own');
    for (final n in [
      '..',
      '../escaped.txt',
      r'..\escaped.txt',
      '/abs',
      'a/b',
    ]) {
      expect(() => own.file(n), throwsA(isA<BenchFailure>()), reason: n);
    }
    expect(own.file('ok.bin'), '${own.path}${Platform.pathSeparator}ok.bin');
    Directory('${own.path}/sub').createSync();
    expect(() => own.file('sub'), throwsA(isA<BenchFailure>()));
  });

  test('temporary suffixes cannot create streams or nested paths', () {
    final own = OwnedDir.open('${tmp.path}/own');
    for (final suffix in [
      ':stream',
      r'\nested\file',
      '/nested/file',
      '.tmp\n',
    ]) {
      expect(
        () => own.derived('good.bin', suffix),
        throwsA(isA<BenchFailure>()),
        reason: suffix,
      );
    }
    untouched();
  });

  for (final raw in _bad) {
    test('pd/df/assist leave the outside file alone: $raw', () async {
      for (final route in ['pd', 'df', 'assist']) {
        final out = '${tmp.path}/o_$route';
        final f = <String, String>{};
        final Future<void> run = switch (route) {
          'pd' => bench.pd(out, '2', [spec(raw)], f),
          'df' => bench.df(out, spec(raw), f),
          _ => bench.assist(
            '${tmp.path}/c_$route',
            out,
            [spec(raw)],
            {'curl': 'curl-that-must-not-run'},
          ),
        };
        await expectLater(run, throwsA(isA<BenchFailure>()), reason: route);
        untouched();
        expect(Directory(out).existsSync(), isFalse, reason: '$route created');
      }
    });
  }

  test('a clean name still downloads on every route', () async {
    await bench.df('${tmp.path}/ok_df', spec('good.bin'), {});
    expect(File('${tmp.path}/ok_df/good.bin').readAsBytesSync(), data);
    await bench.pd('${tmp.path}/ok_pd', '1', [spec('good.bin')], {});
    expect(File('${tmp.path}/ok_pd/good.bin').readAsBytesSync(), data);
    untouched();
  });

  test('duplicate names (case-insensitive) are refused before any write', () {
    expect(
      bench.pd('${tmp.path}/dup', '1', [spec('a.bin'), spec('A.bin')], {}),
      throwsA(isA<BenchFailure>()),
    );
    expect(Directory('${tmp.path}/dup').existsSync(), isFalse);
  });

  test('pd policy mode needs the decision from the real policy', () {
    final s = DownloadScheduler(maxConcurrent: 2);
    expect(() => bench.pdPlan('policy', s, {}), throwsA(isA<BenchFailure>()));
    final p = bench.pdPlan('policy', s, {'decided': '1', 'reason': 'x'});
    expect((p.mode, p.conns), ('production-policy', 1));
    expect(bench.pdPlan('auto', s, {}).mode, 'static');
    expect(bench.pdPlan('4', s, {}).conns, 4);
    expect(() => bench.pdPlan('0', s, {}), throwsA(isA<BenchFailure>()));
  });
}
