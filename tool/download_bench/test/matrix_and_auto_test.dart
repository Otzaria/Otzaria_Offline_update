import 'dart:io';

import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import '../bin/bench.dart' as bench;

String? _bash() {
  final r = Process.runSync(Platform.isWindows ? 'where' : 'which', ['bash']);
  final candidates = <String>[
    if (r.exitCode == 0)
      ...(r.stdout as String)
          .split(RegExp(r'\r?\n'))
          .where((s) => s.isNotEmpty),
    if (Platform.isWindows && Platform.environment['ProgramFiles'] != null)
      '${Platform.environment['ProgramFiles']}/Git/bin/bash.exe',
  ];
  for (final candidate in candidates) {
    try {
      if (Process.runSync(candidate, ['--version']).exitCode == 0) {
        return candidate;
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}

void main() {
  test('auto is the exporter split for every queue size', () {
    for (final (slots, expected) in [(1, 4), (2, 4), (4, 2), (8, 1), (16, 1)]) {
      expect(
        bench.autoConnections(DownloadScheduler(maxConcurrent: slots)),
        expected,
        reason: '$slots slots',
      );
    }
  });

  final bash = _bash();
  for (final runs in ['abc', '0', '00', '-1', '2x']) {
    test("matrix.sh refuses RUNS='$runs' and creates nothing", () {
      final tmp = Directory.systemTemp.createTempSync('dbench_matrix_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final local = '${tmp.path}/local';
      final usb = '${tmp.path}/usb';
      final r = Process.runSync(
        bash!,
        ['matrix.sh', 'l', 'http://x/y', '1', 'sha', local, usb],
        environment: {'RUNS': runs},
      );
      expect(r.exitCode, isNot(0), reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('RUNS'));
      expect(Directory(local).existsSync(), isFalse);
      expect(Directory(usb).existsSync(), isFalse);
    }, skip: bash == null ? 'no bash' : false);
  }
}
