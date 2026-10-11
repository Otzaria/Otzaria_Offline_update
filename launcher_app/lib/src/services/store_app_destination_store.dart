import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// זוכר לאן הועתקה חנות התוספים העצמאית **במחשב הזה** ואיזו גרסה הועתקה,
/// כדי להציע עדכון באותה תיקייה בלי לבחור אותה מחדש.
///
/// המפתח הוא שם המחשב, כמו ב-`KnownPluginsStore`: נתיב הוא נתון של מחשב.
class StoreAppDestinationStore {
  StoreAppDestinationStore(String dir, {String? hostName})
      : _file = File(p.join(dir, 'store_app_destination.json')),
        _host = _resolveHost(hostName);

  final File _file;
  final String _host;

  Future<({String dir, String tag})?> load() async {
    final entry = (await _loadAll())[_host];
    final dir = entry?['dir'];
    final tag = entry?['tag'];
    return dir is String && tag is String && dir.isNotEmpty
        ? (dir: dir, tag: tag)
        : null;
  }

  /// כשל כתיבה אינו שגיאה: לכל היותר המשתמש יבחר תיקייה שוב.
  Future<void> record({required String dir, required String tag}) async {
    try {
      final all = await _loadAll();
      all[_host] = {'dir': dir, 'tag': tag};
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(jsonEncode({'hosts': all}), flush: true);
      await temp.rename(_file.path);
    } catch (_) {
      // ראו למעלה.
    }
  }

  Future<Map<String, Map<String, Object?>>> _loadAll() async {
    try {
      if (!await _file.exists()) return {};
      final json = jsonDecode(await _file.readAsString());
      final hosts = json is Map ? json['hosts'] : null;
      if (hosts is! Map) return {};
      return {
        for (final entry in hosts.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: Map<String, Object?>.from(entry.value as Map),
      };
    } catch (_) {
      return {};
    }
  }

  static String _resolveHost(String? given) {
    try {
      final host = given ?? Platform.localHostname;
      return host.isEmpty ? 'unknown' : host;
    } catch (_) {
      return 'unknown';
    }
  }
}
