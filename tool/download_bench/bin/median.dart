// Median per cell over RESULT lines read from stdin (several runs per cell).
// dart run bin/median.dart < results.txt
import 'dart:convert';
import 'dart:io';

import 'package:download_bench/meter.dart';

const _cols = [
  'connect_s',
  'net_s',
  'waitWrite_s',
  'join_s',
  'hash_s',
  'copy_s',
  'flush_s',
  'cleanup_s',
  'ready_s',
  'rate_net_MiBps',
  'rate_ready_MiBps',
  'proc_write_MiB',
  'child_write_MiB',
  'write_amp_io',
];

Future<void> main() async {
  final cells = <String, List<Map<String, String>>>{};
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final r = parseResult(line);
    if (r == null) continue;
    cells
        .putIfAbsent(
          '${r['tool']} ${r['target']} ${r['mode']} conns=${r['conns']}'
          '${(r['reason'] ?? 'n/a') == 'n/a' ? '' : ' ${r['reason']}'}',
          () => [],
        )
        .add(r);
  }
  stdout.writeln(['cell', 'n', ..._cols, 'content_ok'].join('\t'));
  for (final e in cells.entries) {
    final cols = [
      for (final c in _cols)
        () {
          final nums = [
            for (final r in e.value)
              if (double.tryParse(r[c] ?? '') case final v?) v,
          ];
          if (nums.isEmpty) return e.value.first[c] ?? '-';
          return median(nums).toStringAsFixed(2);
        }(),
    ];
    final ok = e.value.every((r) => r['content_ok'] == 'true');
    stdout.writeln([e.key, e.value.length, ...cols, ok].join('\t'));
  }
}
