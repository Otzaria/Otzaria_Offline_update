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

  /// נתיב תיקיית "מראה מקומית" (offline) שנבחרה על-ידי המשתמש, אם קיימת.
  /// null = מצב ברירת מחדל, עדכון מהענן (GitHub) כרגיל.
  Future<String?> loadLocalMirrorPath() async {
    final json = await _readAll();
    return json['localMirrorPath'] as String?;
  }

  /// שומר בחירת מראה מקומית. `null` מנקה את הבחירה וחוזר לעדכון מהענן.
  Future<void> saveLocalMirrorPath(String? mirrorPath) async {
    final json = await _readAll();
    if (mirrorPath == null) {
      json.remove('localMirrorPath');
    } else {
      json['localMirrorPath'] = mirrorPath;
    }
    await _writeAll(json);
  }
}
