import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class PluginInstallReport {
  const PluginInstallReport({
    required this.path,
    required this.outcome,
    required this.at,
    this.pluginId,
    this.version,
    this.message,
  });

  final String path;
  final String outcome;
  final DateTime at;
  final String? pluginId;
  final String? version;
  final String? message;

  bool get succeeded => outcome == 'installed' || outcome == 'updated';

  bool get cancelled => outcome == 'cancelled';

  static PluginInstallReport? fromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['path'];
    final outcome = json['outcome'];
    final rawAt = json['at'];
    final at = rawAt is String ? DateTime.tryParse(rawAt) : null;
    if (path is! String || outcome is! String || at == null) return null;
    String? text(Object? value) => value is String ? value : null;
    return PluginInstallReport(
      path: path,
      outcome: outcome,
      at: at,
      pluginId: text(json['pluginId']),
      version: text(json['version']),
      message: text(json['message']),
    );
  }
}

abstract final class PluginInstallResults {
  static const String fileName = 'plugin_install_results.jsonl';

  static const Duration clockSkew = Duration(seconds: 2);

  static Future<List<PluginInstallReport>> read(String dataRoot) async {
    final List<String> lines;
    try {
      lines = await File(p.join(dataRoot, fileName)).readAsLines();
    } on FileSystemException {
      return const [];
    }
    return _parseLines(lines).toList();
  }

  static Iterable<PluginInstallReport> _parseLines(List<String> lines) sync* {
    for (final line in lines) {
      if (_parse(line) case final report?) yield report;
    }
  }

  static PluginInstallReport? latestFor(
    List<PluginInstallReport> reports,
    String path,
    DateTime since,
  ) {
    final from = since.subtract(clockSkew);
    PluginInstallReport? latest;
    for (final report in reports) {
      if (!p.equals(report.path, path) || report.at.isBefore(from)) continue;
      if (latest == null || !report.at.isBefore(latest.at)) latest = report;
    }
    return latest;
  }

  static PluginInstallReport? _parse(String line) {
    if (line.trim().isEmpty) return null;
    try {
      return PluginInstallReport.fromJson(jsonDecode(line));
    } on FormatException {
      return null;
    }
  }
}

class PluginInstallResultsSnapshot {
  const PluginInstallResultsSnapshot._(this._latest);

  static const _empty = PluginInstallResultsSnapshot._({});

  final Map<String, PluginInstallReport> _latest;

  factory PluginInstallResultsSnapshot._fromLines(List<String> lines) {
    final latest = HashMap<String, PluginInstallReport>(
      equals: p.equals,
      hashCode: p.hash,
    );
    for (final report in PluginInstallResults._parseLines(lines)) {
      final previous = latest[report.path];
      if (previous == null || !report.at.isBefore(previous.at)) {
        latest[report.path] = report;
      }
    }
    return PluginInstallResultsSnapshot._(latest);
  }

  PluginInstallReport? latestFor(String path, DateTime since) {
    final latest = _latest[path];
    return latest == null ||
            latest.at.isBefore(since.subtract(PluginInstallResults.clockSkew))
        ? null
        : latest;
  }
}

/// Reuses the index while the result log is unchanged.
class PluginInstallResultsReader {
  final _pending = <String, Future<PluginInstallResultsSnapshot>>{};
  Future<void> _tail = Future<void>.value();
  ({String path, FileStat stat, PluginInstallResultsSnapshot snapshot})? _cache;
  var _generation = 0;

  Future<PluginInstallResultsSnapshot> read(String dataRoot) {
    final path = p.absolute(dataRoot, PluginInstallResults.fileName);
    return _pending.putIfAbsent(path, () {
      final generation = _generation;
      late final Future<PluginInstallResultsSnapshot> result;
      result = _tail.then((_) => _read(path, generation)).whenComplete(() {
        if (identical(_pending[path], result)) _pending.remove(path);
      });
      _tail = result.then<void>((_) {}, onError: (Object _) {});
      return result;
    });
  }

  void clear() {
    _generation++;
    _cache = null;
    _pending.clear();
  }

  Future<PluginInstallResultsSnapshot> _read(
    String path,
    int generation,
  ) async {
    if (generation != _generation) return PluginInstallResultsSnapshot._empty;
    try {
      final file = File(path);
      var stat = await file.stat();
      for (var attempt = 0; attempt < 2; attempt++) {
        if (generation != _generation) {
          return PluginInstallResultsSnapshot._empty;
        }
        if (stat.type != FileSystemEntityType.file) break;
        final previous = _cache;
        if (previous != null &&
            previous.path == path &&
            _sameStat(previous.stat, stat)) {
          return previous.snapshot;
        }
        final lines = await file.readAsLines();
        final after = await file.stat();
        if (generation != _generation) {
          return PluginInstallResultsSnapshot._empty;
        }
        if (_sameStat(stat, after)) {
          final snapshot = PluginInstallResultsSnapshot._fromLines(lines);
          _cache = (path: path, stat: after, snapshot: snapshot);
          return snapshot;
        }
        // The append can be followed by a rotation while this poll is reading.
        stat = after;
      }
    } on FileSystemException {
      // Ignore unreadable results and let the controller scan installed plugins.
    }
    if (generation == _generation) _cache = null;
    return PluginInstallResultsSnapshot._empty;
  }

  static bool _sameStat(FileStat left, FileStat right) =>
      left.type == right.type &&
      left.size == right.size &&
      left.modified == right.modified &&
      left.changed == right.changed &&
      left.mode == right.mode;
}
