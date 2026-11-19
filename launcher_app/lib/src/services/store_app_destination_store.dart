import 'package:path/path.dart' as p;

import 'json_state_store.dart';

/// יעד וגרסת החנות העצמאית שייכים למחשב שבו הועתקו, ולא לכונן.
class StoreAppDestinationStore {
  StoreAppDestinationStore(String dir, {String? hostName})
      : _store = JsonStateStore(p.join(dir, 'store_app_destination.json')),
        _host = stateHostName(hostName);

  final JsonStateStore _store;
  final String _host;

  Future<({String dir, String tag})?> load() async {
    final entry = _parseAll(await _store.load())[_host];
    final dir = entry?['dir'];
    final tag = entry?['tag'];
    return dir is String && tag is String && dir.isNotEmpty
        ? (dir: dir, tag: tag)
        : null;
  }

  /// כשל כתיבה אינו שגיאה: לכל היותר המשתמש יבחר תיקייה שוב.
  Future<void> record({required String dir, required String tag}) =>
      _store.update((json) {
        final all = _parseAll(json);
        all[_host] = {'dir': dir, 'tag': tag};
        return {'hosts': all};
      });

  static Map<String, Map<String, Object?>> _parseAll(
    Map<String, dynamic> json,
  ) {
    final hosts = json['hosts'];
    if (hosts is! Map) return {};
    return {
      for (final entry in hosts.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: Map<String, Object?>.from(entry.value as Map),
    };
  }
}
