import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/otzaria_update_check_result.dart';

/// שולף את "יומן השינויים" המרוכז של אוצריא — קובץ Markdown יחיד עם כל
/// הגרסאות ב-`Otzaria/otzaria` — ומחלץ ממנו את הפסקה של גרסה ספציפית.
///
/// זה מקור מלא ומתוחזק יותר מתיאור ה-release הבודד ב-GitHub, שלא תמיד
/// נכתב. [OtzariaReleaseClient] וה-sync להתקנה משתמשים בזה כדי להעדיף את
/// הפסקה מכאן על פני `release.body`, ונופלים חזרה לזה אם הגרסה לא נמצאה
/// כאן או שאין רשת.
class OtzariaChangelogClient {
  OtzariaChangelogClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client();

  /// זמן קצוב לבקשה — ראו [OtzariaReleaseClient.timeout]. בלעדיו בדיקת
  /// העדכונים בפתיחה הייתה יכולה להיתקע גם כשה-release עצמו כבר נקרא.
  Duration timeout;

  // הקובץ חי בענף dev ולא בתג ה-release — הוא ה"מקור האחד" שמתעדכן עם כל
  // גרסה, בניגוד לתיאור ה-release שלעיתים נשאר ריק.
  static const String url = 'https://raw.githubusercontent.com/Otzaria/'
      'otzaria/dev/assets/%D7%99%D7%95%D7%9E%D7%9F%20%D7%A9%D7%99%D7%A0%D7%95'
      '%D7%99%D7%99%D7%9D.md';

  /// כותרת גרסה בקובץ, לדוגמה `* **0.9.96**`.
  static final RegExp _versionHeader =
      RegExp(r'^\*\s*\*\*([0-9][0-9.]*)\*\*\s*$');

  final http.Client _httpClient;

  /// מחזיר `null` בכל כשל — רשת, סטטוס לא תקין, או שהגרסה עדיין לא מופיעה
  /// בקובץ. זה תמיד נתיב-רשת קל ואופציונלי; הקורא נופל אז חזרה לתיאור
  /// ה-release הגולמי.
  Future<String?> notesFor(String tagName) async {
    try {
      final response = await _httpClient.get(
        Uri.parse(url),
        headers: const {'User-Agent': 'otzaria-launcher'},
      ).timeout(timeout);
      if (response.statusCode != 200) return null;
      return _extract(response.body, tagName);
    } catch (_) {
      return null;
    }
  }

  String? _extract(String markdown, String tagName) {
    final target = OtzariaUpdateCheckResult.normalizeVersion(tagName);
    final lines = const LineSplitter().convert(markdown);
    final collected = <String>[];
    var inSection = false;

    for (final line in lines) {
      final header = _versionHeader.firstMatch(line);
      if (header != null) {
        // כותרת הגרסה הבאה — אם כבר היינו בפסקה שלנו, זה הסוף שלה.
        if (inSection) break;
        inSection = header.group(1) == target;
        continue;
      }
      // כל שורות הפסקה מוזחות באותם שני רווחים תחת כותרת הגרסה (רשימה
      // שטוחה) — יורדים ברמת הזחה אחת כדי שהתוצאה תהיה רשימת Markdown
      // תקנית ולא נראית כמו רשימה מקוננת.
      if (inSection) collected.add(_dedent(line));
    }

    // מסירים שורות ריקות רק מהקצוות, לא מהאמצע — כדי לא לפרק את הרשימה.
    while (collected.isNotEmpty && collected.first.trim().isEmpty) {
      collected.removeAt(0);
    }
    while (collected.isNotEmpty && collected.last.trim().isEmpty) {
      collected.removeLast();
    }

    return collected.isEmpty ? null : collected.join('\n');
  }

  static String _dedent(String line) =>
      line.startsWith('  ') ? line.substring(2) : line;

  void close() => _httpClient.close();
}
