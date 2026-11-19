import 'package:path/path.dart' as p;

import 'json_state_store.dart';

/// הכונן נוסע בין מחשבים; הודעת "ממתינות על הכונן" נזכרת לפי שם המחשב.
class AnnouncedAppsStore {
  AnnouncedAppsStore(String dir, {String? hostName})
      : _store = JsonStateStore(p.join(dir, 'custom_apps_announced.json')),
        _host = stateHostName(hostName);

  final JsonStateStore _store;
  final String _host;

  /// קובץ חסר או פגום = "עוד לא הוצג כלום".
  Future<Set<String>> load() async {
    final byHost = (await _store.load())['announced'];
    final ids = byHost is Map ? byHost[_host] : null;
    return ids is List ? ids.whereType<String>().toSet() : {};
  }

  Future<void> record(Iterable<String> ids) {
    if (ids.isEmpty) return Future<void>.value();
    return _store.update((json) {
      final all = _parseAll(json);
      final existing = all[_host] ?? const <String>[];
      final merged = {...existing, ...ids}.toList()..sort();
      if (merged.length == existing.length) return null;
      all[_host] = merged;
      return {'announced': all};
    });
  }

  static Map<String, List<String>> _parseAll(Map<String, dynamic> json) {
    final byHost = json['announced'];
    if (byHost is! Map) return {};
    return {
      for (final entry in byHost.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: [
            for (final id in entry.value as List)
              if (id is String) id,
          ],
    };
  }
}
