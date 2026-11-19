import 'package:path/path.dart' as p;

import 'json_state_store.dart';

/// הודעה חד-פעמית נזכרת לפי מחשב; מחשב אחר שאליו מגיע הכונן מציג אותה שוב.
class NoticesSeenStore {
  NoticesSeenStore(String dir, {String? hostName})
      : _store = JsonStateStore(p.join(dir, 'notices_seen.json')),
        _host = stateHostName(hostName);

  /// מפתח ההסבר על דיווחי הטעויות (גרסה 0.24 ואילך).
  static const String errorReportsIntro = 'error_reports_intro';

  /// דיווחים ממתינים בקובץ Hive ישן שאוצריא כבר אינה מעבירה.
  static const String legacyReportsNotice = 'legacy_reports_notice';

  /// החלון על החיפוש החכם לפני "עדכון המחשב הזה" נענה — בכל תשובה.
  static const String semanticConsentAnswered = 'semantic_consent_answered';

  final JsonStateStore _store;
  final String _host;

  /// קובץ חסר או פגום = "עוד לא הוצג כלום".
  Future<bool> hasSeen(String key) async =>
      (_parseAll(await _store.load())[_host] ?? const <String>[]).contains(key);

  Future<void> markSeen(String key) => _store.update((json) {
        final all = _parseAll(json);
        final existing = all[_host] ?? const <String>[];
        if (existing.contains(key)) return null;
        all[_host] = [...existing, key]..sort();
        return {'seen': all};
      });

  static Map<String, List<String>> _parseAll(Map<String, dynamic> json) {
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
  }
}
