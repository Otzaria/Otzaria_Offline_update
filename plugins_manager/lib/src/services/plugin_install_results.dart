import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    return [
      for (final line in lines)
        if (_parse(line) case final report?) report,
    ];
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
  const PluginInstallResultsSnapshot._(this._latest, this._trailing);

  static const _empty = PluginInstallResultsSnapshot._({}, null);

  final Map<String, PluginInstallReport> _latest;
  final PluginInstallReport? _trailing;

  PluginInstallReport? latestFor(String path, DateTime since) {
    var latest = _latest[p.canonicalize(path)];
    final trailing = _trailing;
    if (trailing != null &&
        p.equals(trailing.path, path) &&
        (latest == null || !trailing.at.isBefore(latest.at))) {
      latest = trailing;
    }
    return latest == null ||
            latest.at.isBefore(since.subtract(PluginInstallResults.clockSkew))
        ? null
        : latest;
  }
}

/// Polls unchanged logs without rereading them. A changed prefix is verified
/// before reusing its index, because a replacement can also grow the file.
class PluginInstallResultsReader {
  final _pending = <String, Future<PluginInstallResultsSnapshot>>{};
  Future<void> _tail = Future<void>.value();
  _InstallResultsCache? _cache;
  var _generation = 0;

  Future<PluginInstallResultsSnapshot> read(String dataRoot) {
    final path =
        p.canonicalize(p.join(dataRoot, PluginInstallResults.fileName));
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
      String path, int generation) async {
    if (generation != _generation) return PluginInstallResultsSnapshot._empty;
    try {
      final file = File(path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        if (generation == _generation) _cache = null;
        return PluginInstallResultsSnapshot._empty;
      }
      final previous = _cache?.path == path ? _cache : null;
      if (previous != null && _sameStat(previous.stat, stat)) {
        return generation == _generation
            ? previous.snapshot
            : PluginInstallResultsSnapshot._empty;
      }
      final next = await _scan(file, stat, previous);
      final after = await file.stat();
      if (generation != _generation) return PluginInstallResultsSnapshot._empty;
      _cache = _sameStat(stat, after) ? next : null;
      return _cache?.snapshot ?? PluginInstallResultsSnapshot._empty;
    } on FileSystemException {
      if (generation == _generation) _cache = null;
      return PluginInstallResultsSnapshot._empty;
    }
  }

  Future<_InstallResultsCache> _scan(
    File file,
    FileStat stat,
    _InstallResultsCache? previous,
  ) async {
    final handle = await file.open();
    try {
      var digest = _ResultDigest();
      var hash = sha256.startChunkedConversion(digest);
      var builder = _ResultsBuilder();
      var offset = 0;
      if (previous != null && stat.size > previous.stat.size) {
        final prefixDigest = _ResultDigest();
        final prefix = sha256.startChunkedConversion(prefixDigest);
        await _readBytes(handle, previous.stat.size, (bytes) {
          prefix.add(bytes);
          hash.add(bytes);
        });
        prefix.close();
        if (prefixDigest.value == previous.digest) {
          builder =
              _ResultsBuilder(previous.snapshot._latest, previous.pending);
          offset = previous.stat.size;
        } else {
          hash.close();
          digest = _ResultDigest();
          hash = sha256.startChunkedConversion(digest);
          await handle.setPosition(0);
        }
      }
      await _readBytes(handle, stat.size - offset, (bytes) {
        hash.add(bytes);
        builder.add(bytes);
      });
      hash.close();
      final pending = builder.pending.takeBytes();
      return _InstallResultsCache(
        file.path,
        stat,
        digest.value,
        pending,
        PluginInstallResultsSnapshot._(builder.latest, _parseBytes(pending)),
      );
    } finally {
      await handle.close();
    }
  }

  static Future<void> _readBytes(
    RandomAccessFile handle,
    int remaining,
    void Function(Uint8List) consume,
  ) async {
    while (remaining > 0) {
      final bytes = await handle.read(remaining < 65536 ? remaining : 65536);
      if (bytes.isEmpty) {
        throw FileSystemException(
            'result log changed while reading', handle.path);
      }
      consume(bytes);
      remaining -= bytes.length;
    }
  }

  static bool _sameStat(FileStat left, FileStat right) =>
      left.type == right.type &&
      left.size == right.size &&
      left.modified == right.modified &&
      left.changed == right.changed &&
      left.mode == right.mode;
}

class _InstallResultsCache {
  _InstallResultsCache(
    this.path,
    this.stat,
    this.digest,
    this.pending,
    this.snapshot,
  );

  final String path;
  final FileStat stat;
  final Digest digest;
  final Uint8List pending;
  final PluginInstallResultsSnapshot snapshot;
}

class _ResultsBuilder {
  _ResultsBuilder([
    Map<String, PluginInstallReport> previous = const {},
    List<int> trailing = const [],
  ]) : latest = Map.of(previous) {
    pending.add(trailing);
  }

  final Map<String, PluginInstallReport> latest;
  final pending = BytesBuilder(copy: false);

  void add(Uint8List bytes) {
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 10 && bytes[i] != 13) continue;
      pending.add(Uint8List.sublistView(bytes, start, i));
      final report = _parseBytes(pending.takeBytes());
      if (report != null) {
        final key = p.canonicalize(report.path);
        final before = latest[key];
        if (before == null || !report.at.isBefore(before.at)) {
          latest[key] = report;
        }
      }
      start = i + 1;
    }
    pending.add(Uint8List.sublistView(bytes, start));
  }
}

PluginInstallReport? _parseBytes(List<int> bytes) {
  try {
    return PluginInstallResults._parse(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
}

class _ResultDigest implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
