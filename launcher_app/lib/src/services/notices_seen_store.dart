import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// זוכר אילו הודעות חד-פעמיות כבר הוצגו **במחשב הזה**, כדי שכל הודעה תיאמר
/// פעם אחת בלבד ולא בכל הרצה. הודעה חדשה = מפתח חדש, בלי קובץ חדש.
///
/// המבנה זהה ל-`AnnouncedAppsStore`: המפתח הוא שם המחשב, כי הקובץ נוסע על
/// הכונן ו"כבר הוצג" הוא תכונה של המחשב — כונן שעבר למחשב אחר מציג מחדש.
class NoticesSeenStore {
  NoticesSeenStore(String dir, {String? hostName})
      : _file = File(p.join(dir, 'notices_seen.json')),
        _host = _resolveHost(hostName);

  static const String _unknownHost = 'unknown';

  /// מפתח ההסבר על דיווחי הטעויות (גרסה 0.24 ואילך).
  static const String errorReportsIntro = 'error_reports_intro';

  final File _file;
  final String _host;

  /// קובץ חסר או פגום = "עוד לא הוצג כלום": הודעה כפולה עדיפה על הודעה
  /// שלא נאמרה מעולם.
  Future<bool> hasSeen(String key) async =>
      ((await _loadAll())[_host] ?? const <String>[]).contains(key);

  /// כשל כתיבה אינו שגיאה שמוצגת למשתמש — לכל היותר ההודעה תחזור בהרצה הבאה.
  Future<void> markSeen(String key) async {
    try {
      final all = await _loadAll();
      final existing = all[_host] ?? const <String>[];
      if (existing.contains(key)) return;

      all[_host] = [...existing, key]..sort();
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(jsonEncode({'seen': all}), flush: true);
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
      final byHost = json['seen'];
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
