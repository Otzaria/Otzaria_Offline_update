import 'package:path/path.dart' as p;

import 'json_state_store.dart';

/// שתי רשימות לכל מחשב: מה כבר נראה בחנות ומה הוזכר בדף הבית.
/// איחודן היה גורם להודעת הבית לבלוע את סימון התוסף החדש בחנות.
class KnownPluginsStore {
  KnownPluginsStore(String dir, {String? hostName})
      : _store = JsonStateStore(p.join(dir, 'plugins_known.json')),
        _host = stateHostName(hostName);

  final JsonStateStore _store;
  final String _host;

  /// null פירושו שאין נקודת התחלה; רשימה ריקה שנשמרה היא נתון תקף.
  Future<Set<String>?> loadSeen() => _load('seen');

  Future<Set<String>?> loadNotified() => _load('notified');

  Future<void> recordSeen(Iterable<String> ids) => _record('seen', ids);

  Future<void> recordNotified(Iterable<String> ids) => _record('notified', ids);

  Future<Set<String>?> _load(String list) async =>
      _parseAll(await _store.load())[_host]?[list]?.toSet();

  Future<void> _record(String list, Iterable<String> ids) =>
      _store.update((json) {
        final all = _parseAll(json);
        final host = {...?all[_host]};
        final existing = host[list];
        final merged = {...?existing, ...ids}.toList()..sort();
        if (existing != null && merged.length == existing.length) return null;
        host[list] = merged;
        all[_host] = host;
        return {'hosts': all};
      });

  static Map<String, Map<String, List<String>>> _parseAll(
    Map<String, dynamic> json,
  ) {
    final hosts = json['hosts'];
    if (hosts is! Map) return {};
    return {
      for (final entry in hosts.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: {
            for (final list in (entry.value as Map).entries)
              if (list.key is String && list.value is List)
                list.key as String: [
                  for (final id in list.value as List)
                    if (id is String) id,
                ],
          },
    };
  }
}
