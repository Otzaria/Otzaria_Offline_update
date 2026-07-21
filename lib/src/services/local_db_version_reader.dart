import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// גרסת ה-DB המקומי כפי שנקראה מטבלת `schema_meta`.
class LocalDbVersion {
  /// `schema_meta.db_version`. 0 אם השדה או הטבלה חסרים (DB ישן מאוד).
  final int dbVersion;

  /// `schema_meta.db_schema_version`. null אם חסר.
  final int? schemaVersion;

  /// `false` כאשר `schema_meta.db_version` לא נמצא — סימן שה-DB ישן מדי
  /// מכדי להחיל עליו patch, ויש לעבור למסלול הורדה מלאה.
  final bool hasVersionMeta;

  const LocalDbVersion({
    required this.dbVersion,
    required this.schemaVersion,
    required this.hasVersionMeta,
  });
}

/// קורא את גרסת הספרייה המקומית מטבלת `schema_meta` שב-`seforim.db`.
///
/// הפתיחה היא read-only ואינה משנה את ה-DB. אין להשתמש יותר
/// ב-`db_meta.content_version_int` הישן.
class LocalDbVersionReader {
  const LocalDbVersionReader();

  /// קורא את הגרסה והסכמה מ-DB שב-[dbPath].
  ///
  /// מחזיר [LocalDbVersion] עם `hasVersionMeta=false` אם השדה חסר.
  /// זורק אם הקובץ עצמו אינו ניתן לפתיחה.
  LocalDbVersion read(String dbPath) {
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      final dbVersion = _readIntMeta(db, 'db_version');
      final schemaVersion = _readIntMeta(db, 'db_schema_version');
      return LocalDbVersion(
        dbVersion: dbVersion ?? 0,
        schemaVersion: schemaVersion,
        hasVersionMeta: dbVersion != null,
      );
    } finally {
      db?.close();
    }
  }

  int? _readIntMeta(sqlite3.Database db, String key) {
    try {
      final result = db.select(
        'SELECT value FROM schema_meta WHERE key = ? LIMIT 1',
        [key],
      );
      if (result.isEmpty) return null;
      return int.tryParse(result.first['value']?.toString() ?? '');
    } catch (_) {
      // הטבלה schema_meta לא קיימת — DB ישן מלפני המערכת החדשה.
      return null;
    }
  }
}
