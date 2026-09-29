import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// זוכר אילו תוספים כבר נראו בחנות **במחשב הזה**, כדי שהודעת "תוסף חדש"
/// תיאמר פעם אחת בלבד ולא בכל הרצה.
///
/// המפתח הוא שם המחשב, כמו ב-`AnnouncedAppsStore`: הקובץ נוסע על הכונן,
/// ו"כבר נראה" הוא תכונה של המחשב. לכל מחשב שתי רשימות נפרדות — מה שכבר
/// הוצג בטוסט של החנות ([loadSeen]), ומה שכבר הוזכר בחלון שבמסך הראשי
/// ([loadNotified]) — כדי שהחלון בעלייה לא יבלע את הטוסט שבחנות.
class KnownPluginsStore {
  KnownPluginsStore(String dir, {String? hostName})
      : _file = File(p.join(dir, 'plugins_known.json')),
        _host = _resolveHost(hostName);

  static const String _unknownHost = 'unknown';

  final File _file;
  final String _host;

  /// התוספים שהטוסט של החנות כבר הכיר במחשב הזה, או `null` כשעוד לא נרשם
  /// כלום — הרגע שבו רק שומרים את הקיים ולא מודיעים על כולו כחדש.
  Future<Set<String>?> loadSeen() => _load('seen');

  /// התוספים שהחלון שבמסך הראשי כבר הזכיר במחשב הזה, או `null`.
  Future<Set<String>?> loadNotified() => _load('notified');

  Future<void> recordSeen(Iterable<String> ids) => _record('seen', ids);

  Future<void> recordNotified(Iterable<String> ids) => _record('notified', ids);

  Future<Set<String>?> _load(String list) async {
    final ids = (await _loadAll())[_host]?[list];
    return ids == null ? null : ids.toSet();
  }

  /// מוסיף מזהים לרשימה של המחשב הזה. גם רשימה ריקה נרשמת כשהיא עוד לא
  /// קיימת — היא מסמנת ש"נקודת ההתחלה" כבר נקבעה. כשל כתיבה אינו שגיאה
  /// שמוצגת: לכל היותר ההודעה תחזור בהרצה הבאה.
  Future<void> _record(String list, Iterable<String> ids) async {
    try {
      final all = await _loadAll();
      final host = {...?all[_host]};
      final existing = host[list];
      final merged = {...?existing, ...ids}.toList()..sort();
      if (existing != null && merged.length == existing.length) return;

      host[list] = merged;
      all[_host] = host;
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(jsonEncode({'hosts': all}), flush: true);
      await temp.rename(_file.path);
    } catch (_) {
      // ראו למעלה.
    }
  }

  Future<Map<String, Map<String, List<String>>>> _loadAll() async {
    try {
      if (!await _file.exists()) return {};
      final json = jsonDecode(await _file.readAsString());
      final hosts = json is Map ? json['hosts'] : null;
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
    } catch (_) {
      return {};
    }
  }

  /// שם המחשב, ובכל מצב שאין כזה — מפתח קבוע. עדיף מפתח משותף על פני
  /// אי-רישום: בלעדיו ההודעה הייתה חוזרת בכל הרצה.
  static String _resolveHost(String? given) {
    try {
      final host = given ?? Platform.localHostname;
      return host.isEmpty ? _unknownHost : host;
    } catch (_) {
      return _unknownHost;
    }
  }
}
