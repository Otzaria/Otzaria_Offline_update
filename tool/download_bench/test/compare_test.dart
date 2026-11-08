import 'dart:io';
import 'dart:typed_data';

import 'package:download_bench/compare.dart';
import 'package:download_bench/meter.dart';
import 'package:download_bench/scratch.dart';
import 'package:test/test.dart';

Run _pd(double ready, {String drive = 'removable', String engine = 'abc'}) => {
  'kind': 'download',
  'tool': 'pd',
  'target': 'usb',
  'mode': 'static',
  'conns': 1,
  'files': 1,
  'MiB': '96.0',
  'target_kind': drive,
  'target_fs': 'FAT32',
  'engine': engine,
  'ready_s': '$ready',
  'rate_net_MiBps': 'n/a',
};

void main() {
  test('a malformed line names its line number', () {
    expect(
      () => readJsonl(['{"a":1}', '', 'nope']),
      throwsA(
        isA<BenchFailure>().having((e) => e.message, 'm', contains('line 3')),
      ),
    );
  });

  test('runs on another kind of drive are another cell', () {
    expect(
      cells([
        _pd(1),
        _pd(2),
        _pd(3, drive: 'fixed'),
      ]).values.map((g) => g.length),
      [2, 1],
    );
  });

  test('a JIT run never shares a cell with a compiled one', () {
    expect(
      cells([
        _pd(1),
        {..._pd(2), 'runtime': 'aot'},
      ]),
      hasLength(2),
    );
  });

  test('n/a values are not counted as measurements', () {
    final s = stats([_pd(1), _pd(3)], 'rate_net_MiBps');
    expect(s, isNull);
    expect(stats([_pd(1), _pd(3)], 'ready_s')!.median, 2);
  });

  group('verdict', () {
    Stats s(double lo, double hi, {int n = 3}) =>
        (n: n, median: (lo + hi) / 2, min: lo, max: hi);
    test('needs three runs on each side', () {
      expect(verdict(s(1, 2, n: 2), s(10, 11)), 'insufficient-runs');
    });
    test('overlapping ranges are noise even with different medians', () {
      expect(verdict(s(10, 20), s(5, 11)), 'within-noise');
    });
    test('separated ranges give a direction', () {
      expect(verdict(s(10, 20), s(5, 9)), 'lower');
      expect(verdict(s(10, 20), s(21, 30)), 'higher');
    });
  });

  test('compare reports cells present on one side only', () {
    final lines = compareLogs([_pd(1)], [_pd(1, drive: 'fixed')]);
    expect(lines, contains(startsWith('ONLY-IN-BASE')));
    expect(lines, contains(startsWith('ONLY-IN-CANDIDATE')));
  });

  test('a different engine pin is a warning, not a silent merge', () {
    expect(
      environmentWarnings([
        [_pd(1)],
        [_pd(1, engine: 'def')],
      ]),
      [contains('engine')],
    );
  });

  test('StageClock accumulates a stage entered twice, keeps first order', () {
    var now = 0;
    final c = StageClock(() => now)..enter('a');
    now = 5;
    c.enter('b');
    now = 7;
    c.enter('a');
    now = 10;
    c.stop();
    expect(c.order, ['a', 'b']);
    expect(c.ms, {'a': 8, 'b': 2});
  });

  group('copyVerified', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('dbench_copy_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a mismatch never creates the final name', () async {
      final src = File('${tmp.path}/a')..writeAsBytesSync(Uint8List(4096));
      await expectLater(
        copyVerified(
          src.path,
          '${tmp.path}/b.tmp',
          '${tmp.path}/b',
          4096,
          '0' * 64,
        ),
        throwsA(isA<BenchFailure>()),
      );
      expect(File('${tmp.path}/b').existsSync(), isFalse);
      expect(File('${tmp.path}/b.tmp').existsSync(), isFalse);
    });

    test('a match renames into place and reports the bytes', () async {
      final src = File('${tmp.path}/a')..writeAsBytesSync(Uint8List(4096));
      final sha = await hashFile(src.path);
      final n = await copyVerified(
        src.path,
        '${tmp.path}/b.tmp',
        '${tmp.path}/b',
        4096,
        sha,
      );
      expect(n, 4096);
      expect(await hashFile('${tmp.path}/b'), sha);
    });
  });

  test('driveInfo names the kind of the system drive on Windows', () {
    final d = driveInfo(Directory.systemTemp.path);
    if (Platform.isWindows) {
      expect(d.kind, isNot('n/a'));
      expect(d.fs, isNotEmpty);
    } else {
      expect(d, (kind: 'n/a', fs: 'n/a'));
    }
  });

  test('http and https runs of one variant are separate cells', () {
    expect(
      cellKey({..._pd(1), 'scheme': 'http'}),
      isNot(cellKey({..._pd(1), 'scheme': 'https'})),
    );
  });

  test('a failed export is not pooled with successful ones', () {
    Run export(bool ok) => {
      'kind': 'export',
      'mode': 'full-mirror',
      'exported': ok,
      'target_kind': 'fixed',
      'target_fs': 'NTFS',
    };
    expect(cellKey(export(true)), isNot(cellKey(export(false))));
    expect(cellKey(export(true)), isNot(contains('null')));
  });

  test('writetest cells split by write pattern', () {
    Run w(String mode) => {
      'kind': 'writetest',
      'mode': mode,
      'MiB': '256',
      'target_kind': 'removable',
      'target_fs': 'NTFS',
      'runtime': 'aot',
    };
    expect(
      cellKey(w('block-1024KiB-writers-1')),
      isNot(cellKey(w('block-1024KiB-writers-4'))),
    );
    expect(cellKey(w('block-1024KiB-writers-1')), isNot(contains('null')));
  });

  test('the test VM is not mistaken for a compiled bench', () {
    expect(isAotRuntime(), isFalse);
  });
}
