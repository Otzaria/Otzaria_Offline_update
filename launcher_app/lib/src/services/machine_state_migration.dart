import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:library_manager/library_manager.dart'
    show LibraryStateStore, SemanticMachineState;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:path/path.dart' as p;

/// Runs under the startup instance locks, before any state store is opened.
class MachineStateMigration {
  const MachineStateMigration({
    required this.sourceDir,
    required this.targetDir,
    required this.fileNames,
    this.machineKey,
  });

  final String sourceDir;
  final String targetDir;
  final List<String> fileNames;
  final String? machineKey;

  Future<void> run() async {
    final machineKey =
        this.machineKey ?? await LibraryStateStore.currentMachineKey();
    final records = _StateRecords(machineKey, targetDir);
    final id = sha256.convert(utf8.encode(machineKey)).toString();
    final journal = File(p.join(targetDir, 'logs', 'migrations', '$id.json'));
    final saved = await _readObject(journal);
    if (saved != null && (saved['version'] != 1 || saved['files'] is! Map)) {
      throw FormatException('Invalid state migration checkpoint', journal.path);
    }
    final files = _map(saved?['files']);

    Future<void> checkpoint() async {
      await journal.parent.create(recursive: true);
      await writeStringAtomically(
        journal.path,
        jsonEncode({'version': 1, 'files': files}),
      );
    }

    for (final name in fileNames) {
      var entry = _map(files[name]);
      if (files.containsKey(name) &&
          (entry['source'] is! Map || entry['target'] is! Map)) {
        throw FormatException('Invalid state migration entry', journal.path);
      }

      Future<void> finishPending() async {
        final pending = _map(entry['pending']);
        if (pending['source'] is! Map ||
            pending['before'] is! Map ||
            pending['after'] is! Map) {
          throw FormatException(
              'Invalid pending state migration', journal.path);
        }
        final target = File(p.join(targetDir, 'logs', name));
        final json = await _readState(targetDir, name) ?? <String, dynamic>{};
        final current = await records.read(name, json);
        final before = _map(pending['before']);
        final after = _map(pending['after']);
        final recovered = {...current};
        for (final key in {...before.keys, ...after.keys}) {
          // A restart may follow another computer's write: replay only our patch.
          if (!_same(before[key], after[key]) &&
              _same(current[key], before[key])) {
            _put(recovered, key, after[key]);
          }
        }
        if (!_same(current, recovered)) {
          records.write(name, json, current, recovered);
          await target.parent.create(recursive: true);
          await writeStringAtomically(target.path, jsonEncode(json));
        }
        final imported = _map(pending['source']);
        entry = {'source': imported, 'target': _select(after, imported.keys)};
        files[name] = entry;
        await checkpoint();
      }

      if (entry.containsKey('pending')) await finishPending();
      final sourceJson = await _readState(sourceDir, name);
      if (sourceJson == null) continue;
      final source = await records.read(name, sourceJson);
      final previousSource = _map(entry['source']);
      if (_same(source, previousSource)) continue;
      final targetJson =
          await _readState(targetDir, name) ?? <String, dynamic>{};
      final target = await records.read(name, targetJson);
      final after = records.merge(
        source,
        target,
        previousSource: entry.isEmpty ? null : previousSource,
        previousTarget: _map(entry['target']),
      );
      final affected = {...source.keys, ...previousSource.keys};
      entry = {
        'source': previousSource,
        'target': _map(entry['target']),
        'pending': {
          'source': source,
          'before': _select(target, affected),
          'after': _select(after, affected),
        },
      };
      files[name] = entry;
      await checkpoint();
      await finishPending();
    }
  }

  static Future<Map<String, dynamic>?> _readState(
      String dir, String name) async {
    final current = File(p.join(dir, 'logs', name));
    return await _readObject(current) ??
        await _readObject(File(p.join(dir, name)));
  }

  static Future<Map<String, dynamic>?> _readObject(File file) async {
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected a state object', file.path);
    }
    return value;
  }
}

class _StateRecords {
  _StateRecords(this.machineKey, this.dataDir);

  final String machineKey;
  final String dataDir;
  final String legacyKey = LibraryStateStore.legacyMachineKey();

  String _key(String key) => key == legacyKey ? machineKey : key;

  Map<String, dynamic> _machines(Object? value) {
    final raw = _stateMap(value);
    return {
      for (final entry in raw.entries)
        if (legacyKey == machineKey ||
            entry.key != legacyKey ||
            !raw.containsKey(machineKey))
          _key(entry.key): entry.value,
    };
  }

  Future<Map<String, dynamic>> read(
    String name,
    Map<String, dynamic> json,
  ) async {
    final result = <String, dynamic>{};
    void add(List<String> path, Object? value) {
      if (value != null) result[jsonEncode(path)] = value;
    }

    void require(bool valid) {
      if (!valid) throw FormatException('Invalid state record', name);
    }

    final mapFields = switch (name) {
      'library_state.json' => const [
          'customDbPaths',
          'customDbPathsExplicit',
          'appliedReleases',
          'deliveredCompanions',
          'knownDbVersions',
          'knownDbVersionsSeen',
          'knownDbVersionsLocalTime',
          'knownDbVersionsNames',
          'semanticMachines',
        ],
      'custom_apps_announced.json' => const ['announced'],
      'notices_seen.json' => const ['seen'],
      'plugins_known.json' || 'store_app_destination.json' => const ['hosts'],
      _ => const <String>[],
    };
    for (final field in mapFields) {
      require(!json.containsKey(field) || json[field] is Map);
    }

    switch (name) {
      case 'library_state.json':
        final paths = _machines(json['customDbPaths']);
        final explicit = _machines(json['customDbPathsExplicit']);
        require(explicit.values.every((value) => value is String));
        final legacy = json['customDbPath'];
        require(!json.containsKey('customDbPath') || legacy is String);
        if (!paths.containsKey(machineKey) &&
            legacy is String &&
            p.isAbsolute(legacy) &&
            !p.equals(dataDir, legacy) &&
            !p.isWithin(dataDir, p.normalize(legacy)) &&
            await Directory(p.dirname(legacy)).exists()) {
          paths[machineKey] = legacy;
        }
        for (final MapEntry(:key, :value) in paths.entries) {
          require(value is String && value.isNotEmpty);
          if (value is String && value.isNotEmpty) {
            add(['path', key],
                {'path': value, 'explicit': explicit[key] == value});
          }
        }
        for (final MapEntry(:key, :value)
            in _machines(json['appliedReleases']).entries) {
          require(value is Map &&
              value['tag'] is String &&
              value['dbVersion'] is int);
          if (value is Map) add(['appliedReleases', key], value);
        }
        for (final MapEntry(:key, :value)
            in _machines(json['deliveredCompanions']).entries) {
          require(value is Map);
          for (final marker in _stateMap(value).entries) {
            require(marker.value is String);
            add(['deliveredCompanions', key, marker.key], marker.value);
          }
        }
        final seen = _machines(json['knownDbVersionsSeen']);
        final localTime = _machines(json['knownDbVersionsLocalTime']);
        final names = _machines(json['knownDbVersionsNames']);
        for (final metadata in [seen, localTime, names]) {
          require(metadata.values.every((value) => value is String));
        }
        for (final MapEntry(:key, :value)
            in _machines(json['knownDbVersions']).entries) {
          require(value is int && value > 0);
          if (value is int && value > 0) {
            add([
              'known',
              key
            ], {
              'version': value,
              if (seen[key] != null) 'seen': seen[key],
              if (localTime[key] != null) 'localTime': localTime[key],
              if (names[key] != null) 'name': names[key],
            });
          }
        }
        for (final MapEntry(:key, :value)
            in _machines(json['semanticMachines']).entries) {
          require(SemanticMachineState.fromJson(value) != null);
          if (value is Map) add(['semanticMachines', key], value);
        }
      case 'otzaria_install_state.json':
        require(json['appVersion'] == null || json['appVersion'] is String);
        require(json.isEmpty ||
            (json['installedTagName'] is String &&
                json['installDir'] is String &&
                (json['launchPath'] ?? json['exePath']) is String));
        if (json['installedTagName'] is String &&
            json['installDir'] is String &&
            (json['launchPath'] ?? json['exePath']) is String) {
          add(['install'], json);
        }
      case 'custom_apps_announced.json':
      case 'notices_seen.json':
        final field = name == 'notices_seen.json' ? 'seen' : 'announced';
        for (final MapEntry(:key, :value) in _stateMap(json[field]).entries) {
          require(value is List);
          if (value is List) {
            require(value.every((id) => id is String));
            add([field, key], value.whereType<String>().toList());
          }
        }
      case 'plugins_known.json':
        for (final host in _stateMap(json['hosts']).entries) {
          require(host.value is Map);
          final lists = _stateMap(host.value);
          for (final field in ['seen', 'notified']) {
            final value = lists[field];
            require(!lists.containsKey(field) || value is List);
            if (value is List) {
              require(value.every((id) => id is String));
              add(['hosts', host.key, field],
                  value.whereType<String>().toList());
            }
          }
        }
      case 'store_app_destination.json':
        for (final host in _stateMap(json['hosts']).entries) {
          final value = _stateMap(host.value);
          require(value['dir'] is String && value['tag'] is String);
          if (value['dir'] is String && value['tag'] is String) {
            add(['hosts', host.key], value);
          }
        }
    }
    return result;
  }

  Map<String, dynamic> merge(
    Map<String, dynamic> source,
    Map<String, dynamic> target, {
    required Map<String, dynamic>? previousSource,
    required Map<String, dynamic> previousTarget,
  }) {
    final result = {...target};
    final sourceClocks = _clocks(source);
    final targetClocks = _clocks(target);
    for (final key in {...?previousSource?.keys, ...source.keys}) {
      final incoming = source[key];
      final old = previousSource?[key];
      final current = target[key];
      if (previousSource != null && _same(incoming, old)) continue;
      if (incoming is List) {
        final before =
            old is List ? old.whereType<String>().toSet() : <String>{};
        final additions =
            incoming.whereType<String>().toSet().difference(before);
        final removals =
            before.difference(incoming.whereType<String>().toSet());
        result[key] = {
          if (current is List) ...current.whereType<String>(),
          ...additions,
        }.difference(removals).toList()
          ..sort();
      } else if ((previousSource == null && current == null) ||
          (previousSource != null && _same(current, previousTarget[key])) ||
          _newer(incoming, current)) {
        _put(
            result, key, _alignSeen(key, incoming, sourceClocks, targetClocks));
      }
    }
    return result;
  }

  static bool _newer(Object? incoming, Object? current) {
    if (incoming is! Map || current is! Map) return false;
    // Independent logical clocks cannot establish which copy of a record is newer.
    final left = _stamp(incoming['localTime']);
    final right = _stamp(current['localTime']);
    return left != null && right != null && left.isAfter(right);
  }

  static Object? _alignSeen(
    String key,
    Object? incoming,
    Map<String, DateTime> source,
    Map<String, DateTime> target,
  ) {
    if (incoming is! Map) return incoming;
    final prefix = _clockGroup(key);
    final seen = _stamp(incoming['seen']);
    if (prefix == null || seen == null) return incoming;
    final sourceClock = source[prefix];
    final targetClock = target[prefix];
    if (sourceClock == null || targetClock == null) return incoming;
    return {
      ..._map(incoming),
      'seen':
          targetClock.subtract(sourceClock.difference(seen)).toIso8601String(),
    };
  }

  static String? _clockGroup(String key) => key.startsWith('["known",')
      ? 'known'
      : key.startsWith('["semanticMachines",')
          ? 'semantic'
          : null;

  static Map<String, DateTime> _clocks(Map<String, dynamic> records) {
    final clocks = <String, DateTime>{};
    for (final entry in records.entries) {
      final group = _clockGroup(entry.key);
      final value = _stamp(_map(entry.value)['seen']);
      if (group != null &&
          value != null &&
          (clocks[group] == null || value.isAfter(clocks[group]!))) {
        clocks[group] = value;
      }
    }
    return clocks;
  }

  void write(
    String name,
    Map<String, dynamic> json,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    for (final key in {...before.keys, ...after.keys}) {
      if (_same(before[key], after[key])) continue;
      final path = (jsonDecode(key) as List).cast<String>();
      final value = after[key];
      if (name == 'library_state.json') {
        void putMachine(String field, Object? value) {
          final entries = _child(json, field);
          if (path[1] == machineKey) entries.remove(legacyKey);
          _put(entries, path[1], value);
          json[field] = entries;
        }

        switch (path[0]) {
          case 'path':
            final choice = _map(value);
            putMachine('customDbPaths', choice['path']);
            putMachine('customDbPathsExplicit',
                choice['explicit'] == true ? choice['path'] : null);
            if (path[1] == machineKey) json.remove('customDbPath');
          case 'known':
            final record = _map(value);
            putMachine('knownDbVersions', record['version']);
            putMachine('knownDbVersionsSeen', record['seen']);
            putMachine('knownDbVersionsLocalTime', record['localTime']);
            putMachine('knownDbVersionsNames', record['name']);
          case 'deliveredCompanions':
            final machines = _child(json, path[0]);
            if (path[1] == machineKey &&
                !machines.containsKey(machineKey) &&
                machines.containsKey(legacyKey)) {
              machines[machineKey] = machines[legacyKey];
            }
            final markers = _child(machines, path[1]);
            _put(markers, path[2], value);
            putMachine(path[0], markers);
          default:
            putMachine(path[0], value);
        }
      } else if (path[0] == 'install') {
        json
          ..clear()
          ..addAll(_map(value));
      } else {
        final hosts = _child(json, path[0]);
        if (path.length == 3) {
          final host = _child(hosts, path[1]);
          _put(host, path[2], value);
          hosts[path[1]] = host;
        } else {
          _put(hosts, path[1], value);
        }
        json[path[0]] = hosts;
      }
    }
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

Map<String, dynamic> _select(
        Map<String, dynamic> records, Iterable<String> keys) =>
    {
      for (final key in keys)
        if (records.containsKey(key)) key: records[key],
    };

Map<String, dynamic> _stateMap(Object? value) {
  if (value != null && value is! Map) {
    throw const FormatException('Invalid state map');
  }
  return _map(value);
}

Map<String, dynamic> _child(Map<String, dynamic> parent, String key) {
  final value = parent[key];
  if (value is Map<String, dynamic>) return value;
  final result = _map(value);
  parent[key] = result;
  return result;
}

DateTime? _stamp(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

void _put(Map<String, dynamic> map, String key, Object? value) {
  if (value == null) {
    map.remove(key);
  } else {
    map[key] = value;
  }
}

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}
