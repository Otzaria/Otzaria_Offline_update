import 'dart:convert';
import 'dart:io';

/// שומר/טוען נתיב DB מותאם אישית, למקרה שהמשתמש הצביע ידנית על תיקיית
/// ספרייה שאינה ברירת המחדל של אוצריא (`C:/אוצריא/seforim.db`). קובץ
/// state נפרד מזה של [OtzariaStateStore] — שני מודולים שונים, שני קבצים.
class LibraryStateStore {
  const LibraryStateStore(this.stateFilePath);

  final String stateFilePath;

  /// מחזיר null אם לא הוגדר נתיב מותאם אישית (או שהקובץ פגום/לא קריא —
  /// מתייחסים לזה כ"לא הוגדר" ולא זורקים).
  Future<String?> loadCustomDbPath() async {
    final file = File(stateFilePath);
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['customDbPath'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCustomDbPath(String dbPath) async {
    final file = File(stateFilePath);
    await file.parent.create(recursive: true);
    final tmp = File('$stateFilePath.tmp');
    await tmp.writeAsString(jsonEncode({'customDbPath': dbPath}));
    await tmp.rename(stateFilePath);
  }
}
