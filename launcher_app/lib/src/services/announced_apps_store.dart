import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// זוכר על אילו תוכנות נוספות כבר קפצה הודעת "ממתינות על הכונן"
/// **במחשב הזה**, כדי שהיא תיאמר פעם אחת בלבד ולא בכל הרצה.
///
/// המפתח הוא שם המחשב, בדיוק כמו ב-`KnownLocationsStore`: הקובץ נוסע על
/// הכונן, ולכן "כבר הוצג" הוא תכונה של המחשב ולא של הכונן — כונן שעבר
/// למחשב חדש מציג בו את ההודעה מחדש.
class AnnouncedAppsStore {
  AnnouncedAppsStore(String dir, {String? hostName})
      : _file = File(p.join(dir, 'custom_apps_announced.json')),
        _host = _resolveHost(hostName);

  static const String _unknownHost = 'unknown';

  final File _file;
  final String _host;

  /// המזהים שכבר הוצגו במחשב הזה. קובץ חסר או פגום = "עוד לא הוצג כלום",
  /// וזו גם התשובה הנכונה: הודעה כפולה עדיפה על הודעה שלא נאמרה מעולם.
  Future<Set<String>> load() async {
    try {
      if (!await _file.exists()) return {};
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return {};
      final byHost = json['announced'];
      if (byHost is! Map) return {};
      final ids = byHost[_host];
      if (ids is! List) return {};
      return {
        for (final id in ids)
          if (id is String) id
      };
    } catch (_) {
      return {};
    }
  }

  /// מוסיף מזהים לרשימת המוצגים של המחשב הזה. כשל כתיבה אינו שגיאה שמוצגת
  /// למשתמש — לכל היותר ההודעה תחזור בהרצה הבאה.
  Future<void> record(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final all = await _loadAll();
      final existing = all[_host] ?? const <String>[];
      final merged = {...existing, ...ids}.toList()..sort();
      if (merged.length == existing.length) return;

      all[_host] = merged;
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(jsonEncode({'announced': all}), flush: true);
      await temp.rename(_file.path);
    } catch (_) {
      // ראו למעלה.
    }
  }

  Future<Map<String, List<String>>> _loadAll() async {
    try {
      if (!await _file.exists()) return {};
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return {};
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
