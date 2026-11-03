import 'dart:io';
import 'dart:typed_data';

import 'package:download_bench/meter.dart';
import 'package:download_bench/scratch.dart';
import 'package:test/test.dart';

class _FakeFile implements RandomAccessFile {
  _FakeFile(this.failFlush);
  final bool failFlush;
  bool closed = false;

  @override
  Future<RandomAccessFile> flush() async {
    if (failFlush) throw const FileSystemException('flush failed');
    return this;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dbench_meter_');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('relative paths are counted by the sampler', () {
    final relative = Directory('.dart_tool').createTempSync('dbench_meter_');
    final absolute = relative.absolute;
    addTearDown(() => absolute.deleteSync(recursive: true));
    final s = DirSampler([relative.path])..start();
    File('${relative.path}/a.bin').writeAsBytesSync(Uint8List(1 << 20));
    s.stop();
    expect(s.footprintEst, 1 << 20);
    expect(s.footprintUnder(relative.path), 1 << 20);
    expect(s.peakLive, 1 << 20);
  });

  test('flush failure surfaces and every handle is closed', () async {
    final opened = <_FakeFile>[];
    await expectLater(
      flushFiles(
        ['a', 'b'],
        open: (p) {
          final f = _FakeFile(p == 'a');
          opened.add(f);
          return f;
        },
      ),
      throwsA(isA<BenchFailure>()),
    );
    expect(opened.length, 2);
    expect(opened.every((f) => f.closed), isTrue);
  });

  test('flush of real files works, a missing file fails', () async {
    final f = File('${tmp.path}/x')..writeAsBytesSync([1, 2, 3]);
    await flushFiles([f.path]);
    await expectLater(
      flushFiles(['${tmp.path}/missing/none']),
      throwsA(isA<BenchFailure>()),
    );
  });

  test('verifyContent rejects a wrong sha and a wrong size', () async {
    final f = File('${tmp.path}/v')..writeAsBytesSync([1, 2, 3]);
    final good = await hashFile(f.path);
    await verifyContent(f.path, 3, good);
    await expectLater(
      verifyContent(f.path, 3, '0' * 64),
      throwsA(isA<BenchFailure>()),
    );
    await expectLater(
      verifyContent(f.path, 4, good),
      throwsA(isA<BenchFailure>()),
    );
  });

  test('io counters count rewrites that file sizes cannot', () {
    final a = processWrites();
    if (a == null) {
      markTestSkipped('Windows only');
      return;
    }
    final f = File('${tmp.path}/w')..writeAsBytesSync(Uint8List(1 << 20));
    for (var i = 0; i < 3; i++) {
      f.writeAsBytesSync(Uint8List(1 << 20));
    }
    final b = processWrites()!;
    expect(b.writeBytes - a.writeBytes, greaterThanOrEqualTo(4 << 20));
    final s = DirSampler([tmp.path])..start();
    s.stop();
    expect(s.footprintEst, 1 << 20, reason: 'sizes undercount overwrites');
  });

  test('child counters are read after the process exits', () async {
    if (!Platform.isWindows) {
      markTestSkipped('Windows only');
      return;
    }
    final out = '${tmp.path}\\child.bin';
    final p = await Process.start('cmd', [
      '/c',
      'ping -n 2 127.0.0.1 > "$out"',
    ]);
    final io = ChildIo.open(p.pid);
    await p.exitCode;
    final snap = io?.read();
    io?.close();
    expect(snap, isNotNull);
    expect(snap!.writeBytes, greaterThan(0));
  });

  test('spans merge, overlap is not summed', () {
    final net = mergeSpans([(0, 10), (5, 20), (30, 40)]);
    final hash = mergeSpans([(15, 35)]);
    expect(net, [(0, 20), (30, 40)]);
    expect(spansTotal(net), 30);
    expect(spansOverlap(net, hash), 10);
  });

  test('median and RESULT parsing', () {
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 2, 3]), 2.5);
    expect(parseResult('RESULT tool=pd ready_s=1.5 x=n/a')!['ready_s'], '1.5');
    expect(parseResult('SUMMARY a=b'), isNull);
  });
}
