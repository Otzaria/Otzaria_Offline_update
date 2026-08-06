import 'dart:convert';
import 'dart:io';

/// שומר/טוען הגדרות מתמשכות של מודול הספרייה: נתיב DB מותאם אישית (למקרה
/// שהמשתמש הצביע ידנית על תיקיית ספרייה שאינה ברירת המחדל של אוצריא), וכן
/// נתיב "מראה מקומית" (offline) אם המשתמש בחר לעדכן מתיקייה מקומית/USB
/// במקום מהענן. קובץ state נפרד מזה של [OtzariaStateStore] — שני מודולים
/// שונים, שני קבצים.
class LibraryStateStore {
  const LibraryStateStore(this.stateFilePath);

  final String stateFilePath;

  Future<Map<String, dynamic>> _readAll() async {
    final file = File(stateFilePath);
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> json) async {
    final file = File(stateFilePath);
    await file.parent.create(recursive: true);
    final tmp = File('$stateFilePath.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(stateFilePath);
  }

  /// מחזיר null אם לא הוגדר נתיב מותאם אישית (או שהקובץ פגום/לא קריא —
  /// מתייחסים לזה כ"לא הוגדר" ולא זורקים).
  Future<String?> loadCustomDbPath() async {
    final json = await _readAll();
    return json['customDbPath'] as String?;
  }

  Future<void> saveCustomDbPath(String dbPath) async {
    final json = await _readAll();
    json['customDbPath'] = dbPath;
    await _writeAll(json);
  }

  /// ה-release שממנו הגיע תוכן ה-DB המותקן כרגע, או null אם ה-DB לא הותקן
  /// דרך הלאנצ'ר הזה. מאפשר לזהות מסד שפורסם מחדש באותו `db_version` —
  /// ראו `LibraryUpdatePlanner`.
  Future<String?> loadAppliedReleaseTag() async {
    final json = await _readAll();
    final tag = json['appliedReleaseTag'];
    return tag is String && tag.isNotEmpty ? tag : null;
  }

  Future<void> saveAppliedReleaseTag(String tag) async {
    final json = await _readAll();
    json['appliedReleaseTag'] = tag;
    await _writeAll(json);
  }
}
