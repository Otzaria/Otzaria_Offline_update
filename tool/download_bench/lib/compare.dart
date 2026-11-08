// Cell statistics over JSONL run records. A verdict needs three runs per
// side and non-overlapping [min, max] ranges; anything else is noise.
import 'dart:convert';

import 'meter.dart';
import 'scratch.dart';

typedef Run = Map<String, Object?>;

const minRunsForVerdict = 3;

List<Run> readJsonl(List<String> lines) {
  final runs = <Run>[];
  for (final (i, line) in lines.indexed) {
    if (line.trim().isEmpty) continue;
    try {
      runs.add((jsonDecode(line) as Map).cast<String, Object?>());
    } on Object {
      throw BenchFailure('line ${i + 1} is not a JSON object');
    }
  }
  return runs;
}

/// Runs that measured the same thing on the same kind of target.
String cellKey(Run r) => switch (r['kind']) {
  'apply' =>
    'apply route=${r['route']} v${r['from_version']}->v${r['to_version']} '
        'steps=${r['steps']} mirror=${r['mirror_kind']}/${r['mirror_fs']} '
        'db=${r['db_kind']}/${r['db_fs']}',
  'export' =>
    'export mode=${r['mode']} exported=${r['exported']} '
        'drive=${r['target_kind']}/${r['target_fs']}',
  'writetest' =>
    'writetest mode=${r['mode']} MiB=${r['MiB']} '
        'drive=${r['target_kind']}/${r['target_fs']} runtime=${r['runtime']}',
  _ =>
    '${r['tool']} target=${r['target']} scheme=${r['scheme'] ?? 'n/a'} '
        'mode=${r['mode']} conns=${r['conns']} files=${r['files']} '
        'MiB=${r['MiB']} drive=${r['target_kind']}/${r['target_fs']} '
        'runtime=${r['runtime']}',
};

bool isMetric(String key) =>
    key.endsWith('_s') || key.endsWith('_MiB') || key.endsWith('_MiBps');

typedef Stats = ({int n, double median, double min, double max});

Stats? stats(Iterable<Run> runs, String metric) {
  final v = [
    for (final r in runs)
      if (double.tryParse('${r[metric]}') case final x?) x,
  ];
  if (v.isEmpty) return null;
  v.sort();
  return (n: v.length, median: median(v), min: v.first, max: v.last);
}

Map<String, List<Run>> cells(List<Run> runs) {
  final out = <String, List<Run>>{};
  for (final r in runs) {
    out.putIfAbsent(cellKey(r), () => []).add(r);
  }
  return out;
}

List<String> _metrics(Iterable<Run> runs) => {
  for (final r in runs)
    for (final k in r.keys)
      if (isMetric(k)) k,
}.toList()..sort();

String _f(double v) => v.toStringAsFixed(2);

List<String> summarize(List<Run> runs) {
  final out = <String>[];
  for (final MapEntry(key: key, value: group) in cells(runs).entries) {
    out.add('CELL $key n=${group.length}');
    if (group.length < minRunsForVerdict) {
      out.add('  (fewer than $minRunsForVerdict runs: no verdict possible)');
    }
    for (final m in _metrics(group)) {
      final s = stats(group, m);
      if (s == null) continue;
      out.add('  $m median=${_f(s.median)} range=[${_f(s.min)}..${_f(s.max)}]');
    }
  }
  return out;
}

/// `lower`/`higher` only when both sides have enough runs and their ranges
/// do not overlap; whether lower is better depends on the metric.
String verdict(Stats a, Stats b) {
  if (a.n < minRunsForVerdict || b.n < minRunsForVerdict) {
    return 'insufficient-runs';
  }
  if (b.max < a.min) return 'lower';
  if (b.min > a.max) return 'higher';
  return 'within-noise';
}

List<String> compareLogs(List<Run> base, List<Run> candidate) {
  final a = cells(base), b = cells(candidate);
  final out = <String>[];
  for (final key in {...a.keys, ...b.keys}) {
    final ga = a[key], gb = b[key];
    if (ga == null || gb == null) {
      out.add('ONLY-IN-${ga == null ? 'CANDIDATE' : 'BASE'} $key');
      continue;
    }
    out.add('CELL $key base_n=${ga.length} candidate_n=${gb.length}');
    for (final m in _metrics([...ga, ...gb])) {
      final sa = stats(ga, m), sb = stats(gb, m);
      if (sa == null || sb == null) continue;
      final change = sa.median == 0
          ? 'n/a'
          : '${((sb.median - sa.median) / sa.median * 100).toStringAsFixed(1)}%';
      out.add(
        '  $m base=${_f(sa.median)} candidate=${_f(sb.median)} '
        'change=$change verdict=${verdict(sa, sb)}',
      );
    }
  }
  return out;
}

/// Facts that must match for runs to be compared at all.
const comparedEnvironment = ['engine', 'os_version', 'cpus'];

List<String> environmentWarnings(List<List<Run>> logs) {
  final out = <String>[];
  for (final field in comparedEnvironment) {
    final seen = {
      for (final log in logs)
        for (final r in log) '${r[field]}',
    };
    if (seen.length > 1) {
      out.add('$field differs between runs: ${seen.join(' | ')}');
    }
  }
  return out;
}
