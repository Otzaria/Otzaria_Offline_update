import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../models/delta_manifest.dart';
import '../models/patch_table_spec.dart';
import 'logical_content_hasher.dart';

/// הטבלאות ששינוי בהן ממופה למזהי ספרים ב-[PatchApplyResult.booksTouched].
/// חייב להישאר תואם ל-queries ב-`PatchApplier._collectBooksTouched`.
const Set<String> kBooksTouchedTables = {
  'book',
  'line',
  'tocEntry',
  'line_toc',
  'tocText',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'book_author',
  'book_base_text',
  'book_topic',
  'book_acronym',
};

/// תוצאת החלת patch מוצלחת.
class PatchApplyResult {
  final int migrations;
  final Map<String, int> upserts;
  final Map<String, int> deletes;
  final String resultHash;

  /// מזהי הספרים שתוכן האינדקס שלהם הושפע מה-patch — שינויים בטבלאות
  /// [kBooksTouchedTables] בלבד (book/line/TOC כולל tocText ו-alt-TOC,
  /// ושיוכי מחבר/נושא/ראשי-תיבות). מאפשר רענון אינדקס לספרים שהשתנו בלבד.
  ///
  /// זו לא רשימת "כל מה שמשפיע על חיפוש": שינוי בטבלה שאינה מכוסה (למשל
  /// שינוי שם ב-author/topic/category) לא ממופה לספרים, ו-[upserts]/[deletes]
  /// נותנים ספירות בלבד — אי אפשר לגזור מהם מזהים. צרכן שהאינדקס שלו תלוי
  /// בטבלאות כאלה צריך להתייחס ל-[hasChangesOutsideBooksTouched] כ-trigger
  /// לרענון מלא.
  final Set<int> booksTouched;

  /// האם ה-patch שינה טבלאות שאינן מכוסות ב-[booksTouched] (מלבד schema_meta,
  /// שמתעדכן בכל patch). כש-true, צרכן שהאינדקס שלו תלוי בטבלאות האלה צריך
  /// רענון מלא — אין דרך לגזור מהן מזהי ספרים מדויקים.
  bool get hasChangesOutsideBooksTouched {
    bool changed(MapEntry<String, int> e) =>
        e.value > 0 &&
        e.key != 'schema_meta' &&
        !kBooksTouchedTables.contains(e.key);
    return upserts.entries.any(changed) || deletes.entries.any(changed);
  }

  const PatchApplyResult({
    required this.migrations,
    required this.upserts,
    required this.deletes,
    required this.resultHash,
    this.booksTouched = const {},
  });
}

/// נזרק כאשר preflight או אימות נכשלים — ה-DB לא שונה (לא בוצע commit).
class PatchApplyException implements Exception {
  final String message;
  const PatchApplyException(this.message);
  @override
  String toString() => 'PatchApplyException: $message';
}

/// בוחר את סדר ה-hash לפי גרסת הסכמה: 1 → [kHashTableOrderSchema1] (33 הישן),
/// 2 → [kHashTableOrder] (34 הנוכחי). כל ערך אחר → זריקה (fail loudly).
List<String> hashTableOrderForSchemaVersion(int schemaVersion) {
  switch (schemaVersion) {
    case 1:
      return kHashTableOrderSchema1;
    case 2:
      return kHashTableOrder;
    default:
      throw PatchApplyException(
        'גרסת סכמה $schemaVersion אינה נתמכת לבחירת סדר hash',
      );
  }
}

/// מחיל patch DB דלתאי על `seforim.db` בצורה אטומית, ומשכפל את
/// `PatchApplier.kt` בצד הייצור.
///
/// הזרימה: preflight (גרסה/סכמה/hash) → ATTACH → migrations → upserts (סדר FK)
/// → deletes (סדר FK הפוך) → foreign_key_check → אימות `toContentHash` →
/// COMMIT. כל כשל גורם ל-ROLLBACK וזריקה, וה-DB נשאר ללא שינוי.
///
/// המתודה סינכרונית וחוסמת — יש להריצה ב-Isolate או אחרי
/// `closeForExternalWrite`.
class PatchApplier {
  final LogicalContentHasher hasher;

  /// גרסת הסכמה הגבוהה ביותר שהאפליקציה יודעת להחיל.
  final int supportedSchemaVersion;

  const PatchApplier({
    this.hasher = const LogicalContentHasher(),
    this.supportedSchemaVersion = 2,
  });

  /// מחיל את ה-patch שב-[patchPath] על ה-DB שב-[dbPath] לפי [manifest].
  ///
  /// [verifyFromHash] — אם פעיל, מחשב את ה-hash המקומי לפני apply ומשווה ל-
  /// `fromContentHash` (יקר אך מזהה DB ששונה ידנית/corruption).
  /// [checkForeignKeys] — אם פעיל, מוודא ש-`foreign_key_check` לא גדל.
  PatchApplyResult apply({
    required String dbPath,
    required String patchPath,
    required DeltaManifest manifest,
    bool verifyFromHash = true,
    bool checkForeignKeys = true,
    void Function(String stage)? onStage,
    void Function(int hashedBytes, int totalBytes)? onVerifyProgress,
    int? verifyTotalBytesHint,
  }) {
    // ── preflight: שני סדרי ה-hash נפתרים לפני כל פתיחה/כתיבה — גרסת סכמה
    // לא מוכרת (from או to) זורקת כאן, גם כש-verifyFromHash כבוי.
    final fromOrder =
        hashTableOrderForSchemaVersion(manifest.fromSchemaVersion);
    final toOrder = hashTableOrderForSchemaVersion(manifest.toSchemaVersion);

    // עם hint (סך-הבתים מריצה קודמת) ה-total מדויק; בלעדיו נופלים לגודל
    // הקובץ — הערכת-יתר (אינדקסים ודפים לא נכנסים ל-hash), שנמדדת מחדש לפני
    // כל אימות כי ה-patch משנה את הגודל. בשני המסלולים זו הערכה למד בלבד.
    var totalBytes = 0;
    int refreshTotal() =>
        totalBytes = verifyTotalBytesHint ?? File(dbPath).lengthSync();
    final void Function(int)? verifyProgress = onVerifyProgress == null
        ? null
        : (bytes) => onVerifyProgress(bytes, totalBytes);

    final db = sqlite3.sqlite3.open(dbPath);
    var attached = false;
    var inTransaction = false;
    try {
      db.execute('PRAGMA busy_timeout = 5000');
      // אכיפת FK פעילה (כמו צד הייצור). מחוץ ל-transaction — לא ניתן לשינוי
      // בתוך transaction. בתוך ה-transaction מוסיפים defer_foreign_keys.
      db.execute('PRAGMA foreign_keys = ON');

      // ── preflight: גרסה וסכמה מקומיות ──
      onStage?.call('preflight');
      final localVersion = _readSchemaMetaInt(db, 'db_version', schema: 'main');
      final localSchema =
          _readSchemaMetaInt(db, 'db_schema_version', schema: 'main');
      if (localVersion != manifest.fromVersion) {
        throw PatchApplyException(
          'גרסת ה-DB המקומי ($localVersion) אינה תואמת ל-patch '
          '(${manifest.fromVersion})',
        );
      }
      if (localSchema != null && localSchema != manifest.fromSchemaVersion) {
        throw PatchApplyException(
          'סכמת ה-DB המקומי ($localSchema) אינה תואמת ל-patch '
          '(${manifest.fromSchemaVersion})',
        );
      }

      // ── preflight: hash מקומי מול fromContentHash ──
      if (verifyFromHash) {
        onStage?.call('verifyFromHash');
        if (verifyProgress != null) refreshTotal();
        // ה-DB *לפני* apply הוא בסכמת המקור — הסדר נבחר לפי fromSchemaVersion.
        final localHash = hasher.compute(
          db,
          tableOrder: fromOrder,
          onProgress: verifyProgress,
        );
        if (localHash != manifest.fromContentHash) {
          throw PatchApplyException(
            'ה-DB המקומי שונה מהצפוי — hash לא תואם ל-fromContentHash. '
            'נדרשת הורדה מלאה.',
          );
        }
      }

      // ── ATTACH (חייב להיות מחוץ ל-transaction) ──
      onStage?.call('attach');
      db.execute('ATTACH DATABASE ? AS patch', [patchPath]);
      attached = true;
      _assertPatchCompatible(db, manifest);

      final preFk = checkForeignKeys ? _countFkViolations(db) : 0;

      // ── transaction ──
      db.execute('BEGIN');
      inTransaction = true;
      db.execute('PRAGMA defer_foreign_keys = ON');

      onStage?.call('migrations');
      final migrations = _runMigrations(db);

      onStage?.call('upserts');
      final upserts = _runUpserts(db);

      // חייב לרוץ אחרי ה-upserts (שורות חדשות כבר ב-main עבור ה-JOINs)
      // ולפני ה-deletes (שורות שיימחקו עדיין קיימות למיפוי bookId).
      final booksTouched = _collectBooksTouched(db);

      onStage?.call('deletes');
      final deletes = _runDeletes(db);

      if (checkForeignKeys) {
        onStage?.call('foreignKeyCheck');
        final postFk = _countFkViolations(db);
        if (postFk > preFk) {
          throw PatchApplyException(
            'מספר הפרות מפתח זר גדל ($preFk→$postFk) — ה-patch אינו תקין',
          );
        }
      }

      onStage?.call('verifyToHash');
      if (verifyProgress != null) refreshTotal();
      // ה-DB *אחרי* apply הוא בסכמת היעד — הסדר נבחר לפי toSchemaVersion.
      final resultHash = hasher.compute(
        db,
        tableOrder: toOrder,
        onProgress: verifyProgress,
      );
      if (resultHash != manifest.toContentHash) {
        throw PatchApplyException(
          'ה-hash אחרי apply ($resultHash) אינו תואם ל-toContentHash '
          '(${manifest.toContentHash})',
        );
      }

      onStage?.call('commit');
      db.execute('COMMIT');
      inTransaction = false;

      db.execute('DETACH DATABASE patch');
      attached = false;

      return PatchApplyResult(
        migrations: migrations,
        upserts: upserts,
        deletes: deletes,
        resultHash: resultHash,
        booksTouched: booksTouched,
      );
    } catch (_) {
      if (inTransaction) {
        try {
          db.execute('ROLLBACK');
        } catch (_) {}
      }
      if (attached) {
        try {
          db.execute('DETACH DATABASE patch');
        } catch (_) {}
      }
      rethrow;
    } finally {
      db.close();
    }
  }

  void _assertPatchCompatible(sqlite3.Database db, DeltaManifest manifest) {
    final schemaVersion = _readPatchMetaInt(db, 'schema_version');
    if (schemaVersion == null) {
      throw const PatchApplyException('patch_meta.schema_version חסר ב-patch');
    }
    if (schemaVersion > supportedSchemaVersion) {
      throw PatchApplyException(
        'גרסת סכמת ה-patch ($schemaVersion) חדשה מהנתמך '
        '($supportedSchemaVersion) — נדרש עדכון תוכנה',
      );
    }
    final from = _readPatchMetaInt(db, 'from_version');
    final to = _readPatchMetaInt(db, 'to_version');
    if (from != manifest.fromVersion || to != manifest.toVersion) {
      throw PatchApplyException(
        'גרסאות ה-patch ($from→$to) אינן תואמות ל-manifest '
        '(${manifest.fromVersion}→${manifest.toVersion})',
      );
    }
  }

  int _runMigrations(sqlite3.Database db) {
    final result =
        db.select('SELECT sql FROM patch.migrations ORDER BY version ASC');
    var count = 0;
    for (final row in result) {
      db.execute(row['sql'] as String);
      count++;
    }
    return count;
  }

  Map<String, int> _runUpserts(sqlite3.Database db) {
    final counts = <String, int>{};
    for (final table in kPatchTablesInFkOrder) {
      final patchTable = 'upsert_${table.name}';
      if (!_hasTable(db, 'patch', patchTable)) continue;
      final cols = _patchTableColumns(db, patchTable);
      if (cols.isEmpty) continue;

      final colsCsv = cols.map((c) => '"$c"').join(',');
      final pkCsv = table.primaryKey.map((c) => '"$c"').join(',');
      final nonPkCols =
          cols.where((c) => !table.primaryKey.contains(c)).toList();

      final String conflictClause;
      if (!table.updatable || nonPkCols.isEmpty) {
        conflictClause = 'ON CONFLICT($pkCsv) DO NOTHING';
      } else {
        final assignments =
            nonPkCols.map((c) => '"$c" = excluded."$c"').join(',');
        conflictClause = 'ON CONFLICT($pkCsv) DO UPDATE SET $assignments';
      }

      // `WHERE true` נדרש כדי שה-parser ישייך את ON CONFLICT ל-INSERT ולא ל-SELECT.
      db.execute(
        'INSERT INTO "${table.name}" ($colsCsv) '
        'SELECT $colsCsv FROM patch."$patchTable" WHERE true $conflictClause',
      );
      counts[table.name] = db.updatedRows;
    }
    return counts;
  }

  Map<String, int> _runDeletes(sqlite3.Database db) {
    final counts = <String, int>{};
    for (final table in kPatchTablesInFkOrder.reversed) {
      final patchTable = 'delete_${table.name}';
      if (!_hasTable(db, 'patch', patchTable)) continue;
      if (table.primaryKey.isEmpty) continue;

      final pkCsv = table.primaryKey.map((c) => '"$c"').join(',');
      final String sql;
      if (table.primaryKey.length == 1) {
        final k = '"${table.primaryKey.first}"';
        sql = 'DELETE FROM "${table.name}" WHERE $k IN '
            '(SELECT $k FROM patch."$patchTable")';
      } else {
        sql = 'DELETE FROM "${table.name}" WHERE ($pkCsv) IN '
            '(SELECT $pkCsv FROM patch."$patchTable")';
      }
      db.execute(sql);
      counts[table.name] = db.updatedRows;
    }
    return counts;
  }

  /// אוסף את מזהי הספרים שתוכן האינדקס שלהם (כותרת/טקסט/הפניות TOC/מטא-דאטה)
  /// הושפע מה-patch.
  ///
  /// רץ אחרי ה-upserts ולפני ה-deletes, כך ששורות חדשות כבר ב-main ושורות
  /// שיימחקו עדיין בו — וכל מיפוי JOIN דרך main רואה את כולן. המיפוי נשען
  /// רק על עמודות ה-PK של טבלת ה-patch: עמודות אחרות (כמו bookId ב-line)
  /// אינן מובטחות ב-patch שמעדכן רק תת-קבוצה של עמודות.
  Set<int> _collectBooksTouched(sqlite3.Database db) {
    final touched = <int>{};
    // [joins] — טבלאות main שה-SQL עושה אליהן JOIN; אם אחת חסרה (סכמה ישנה
    // או DB חלקי בבדיקות) מדלגים במקום להפיל את ה-apply.
    void collect(String patchTable, String bookIdSql,
        {List<String> joins = const []}) {
      if (!_hasTable(db, 'patch', patchTable)) return;
      if (joins.any((t) => !_hasTable(db, 'main', t))) return;
      for (final row in db.select(bookIdSql)) {
        final id = row.values.first;
        if (id is int) touched.add(id);
      }
    }

    collect('upsert_book', 'SELECT DISTINCT id FROM patch.upsert_book');
    collect('delete_book', 'SELECT DISTINCT id FROM patch.delete_book');

    for (final op in const ['upsert', 'delete']) {
      collect(
          '${op}_line',
          'SELECT DISTINCT l.bookId FROM patch.${op}_line p '
              'JOIN main.line l ON l.id = p.id',
          joins: const ['line']);
      collect(
          '${op}_tocEntry',
          'SELECT DISTINCT t.bookId FROM patch.${op}_tocEntry p '
              'JOIN main.tocEntry t ON t.id = p.id',
          joins: const ['tocEntry']);
      collect(
          '${op}_line_toc',
          'SELECT DISTINCT l.bookId FROM patch.${op}_line_toc p '
              'JOIN main.line l ON l.id = p.lineId',
          joins: const ['line']);
      // טקסט TOC משותף בין ספרים — ממופה לכל מי שמפנה אליו, גם דרך alt-TOC
      collect(
          '${op}_tocText',
          'SELECT DISTINCT t.bookId FROM patch.${op}_tocText p '
              'JOIN main.tocEntry t ON t.textId = p.id',
          joins: const ['tocEntry']);
      collect(
          '${op}_tocText',
          'SELECT DISTINCT s.bookId FROM patch.${op}_tocText p '
              'JOIN main.alt_toc_entry a ON a.textId = p.id '
              'JOIN main.alt_toc_structure s ON s.id = a.structureId',
          joins: const ['alt_toc_entry', 'alt_toc_structure']);
      collect(
          '${op}_alt_toc_structure',
          'SELECT DISTINCT s.bookId FROM patch.${op}_alt_toc_structure p '
              'JOIN main.alt_toc_structure s ON s.id = p.id',
          joins: const ['alt_toc_structure']);
      collect(
          '${op}_alt_toc_entry',
          'SELECT DISTINCT s.bookId FROM patch.${op}_alt_toc_entry p '
              'JOIN main.alt_toc_entry a ON a.id = p.id '
              'JOIN main.alt_toc_structure s ON s.id = a.structureId',
          joins: const ['alt_toc_entry', 'alt_toc_structure']);
      collect(
          '${op}_line_alt_toc',
          'SELECT DISTINCT l.bookId FROM patch.${op}_line_alt_toc p '
              'JOIN main.line l ON l.id = p.lineId',
          joins: const ['line']);
      // כאן bookId הוא חלק מה-PK — מובטח בשורות ה-patch, אפשר לקרוא ישירות
      for (final t in const ['book_author', 'book_topic', 'book_acronym']) {
        collect('${op}_$t', 'SELECT DISTINCT bookId FROM patch.${op}_$t');
      }
      // book_base_text — שני הצדדים (bookId וגם baseBookId) הם מזהי ספרים
      // שחלק מה-PK, ושינוי בכל אחד מהם נוגע לספר המתאים.
      collect('${op}_book_base_text',
          'SELECT DISTINCT bookId FROM patch.${op}_book_base_text');
      collect('${op}_book_base_text',
          'SELECT DISTINCT baseBookId FROM patch.${op}_book_base_text');
    }
    return touched;
  }

  int _countFkViolations(sqlite3.Database db) {
    return db.select('PRAGMA foreign_key_check').length;
  }

  bool _hasTable(sqlite3.Database db, String schema, String name) {
    final result = db.select(
      "SELECT 1 FROM $schema.sqlite_master WHERE type='table' AND name=? "
      'LIMIT 1',
      [name],
    );
    return result.isNotEmpty;
  }

  List<String> _patchTableColumns(sqlite3.Database db, String name) {
    final result = db.select('PRAGMA patch.table_info("$name")');
    return result.map((r) => r['name'] as String).toList();
  }

  int? _readPatchMetaInt(sqlite3.Database db, String key) {
    try {
      final result = db.select(
        'SELECT value FROM patch.patch_meta WHERE key = ? LIMIT 1',
        [key],
      );
      if (result.isEmpty) return null;
      return int.tryParse(result.first['value']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  int? _readSchemaMetaInt(sqlite3.Database db, String key,
      {required String schema}) {
    try {
      final result = db.select(
        'SELECT value FROM $schema.schema_meta WHERE key = ? LIMIT 1',
        [key],
      );
      if (result.isEmpty) return null;
      return int.tryParse(result.first['value']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}
