// Summarises JSONL run logs (`--json=` of bench, APPLY_JSON of the apply
// runner) per cell, or compares a baseline log with a candidate log.
//   dart run bin/compare.dart runs.jsonl
//   dart run bin/compare.dart before.jsonl after.jsonl
import 'dart:io';

import 'package:download_bench/compare.dart';
import 'package:download_bench/scratch.dart';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('usage: compare.dart <runs.jsonl> [<candidate.jsonl>]');
    exit(2);
  }
  try {
    final logs = [for (final a in args) readJsonl(File(a).readAsLinesSync())];
    for (final w in environmentWarnings(logs)) {
      stdout.writeln('WARNING $w');
    }
    final lines = logs.length == 1
        ? summarize(logs.first)
        : compareLogs(logs.first, logs.last);
    lines.forEach(stdout.writeln);
  } on BenchFailure catch (e) {
    stderr.writeln('FAILED: $e');
    exit(1);
  }
}
