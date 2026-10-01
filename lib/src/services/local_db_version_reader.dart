import 'dart:isolate';

import 'package:otzaria_l10n/otzaria_l10n.dart';
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
  const LocalDbVersionReader({this.busyTimeout = const Duration(seconds: 2)});

  /// How long a read waits on a lock held by another connection (Otzaria
  /// running, or an apply in progress) before reporting it.
  final Duration busyTimeout;

  /// [read] in an isolate, so the busy timeout never blocks the UI.
  /// The error's `toString` is localized on the caller's side, after the hop.
  Future<LocalDbVersion> readInIsolate(String dbPath) =>
      _runReadIsolate(dbPath, busyTimeout.inMilliseconds);

  static Future<LocalDbVersion> _runReadIsolate(String dbPath, int timeoutMs) =>
      Isolate.run(() => LocalDbVersionReader(
            busyTimeout: Duration(milliseconds: timeoutMs),
          ).read(dbPath));

  /// קורא את הגרסה והסכמה מ-DB שב-[dbPath].
  ///
  /// מחזיר [LocalDbVersion] עם `hasVersionMeta=false` אם השדה חסר.
  /// זורק אם הקובץ עצמו אינו ניתן לפתיחה.
  LocalDbVersion read(String dbPath) {
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
      db.execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}');
      if (!_hasSchemaMetaColumns(db)) return _noVersion;
      final dbVersion = _readIntMeta(db, 'db_version');
      final schemaVersion = _readIntMeta(db, 'db_schema_version');
      return LocalDbVersion(
        dbVersion: dbVersion ?? 0,
        schemaVersion: schemaVersion,
        hasVersionMeta: dbVersion != null,
      );
    } on sqlite3.SqliteException catch (e) {
      // A broken file has no trustworthy version (AGENTS.md 5.1); a lock or a
      // hot journal is transient and must not open the no-downgrade guard.
      if (isPermanentlyUnreadable(e.extendedResultCode)) return _noVersion;
      final reason =
          unreadableReasonFor(e.extendedResultCode, opened: db != null);
      if (reason != null) {
        throw LocalDbUnreadableException(
            reason, e.extendedResultCode, e.message);
      }
      rethrow;
    } finally {
      db?.close();
    }
  }

  static const _noVersion =
      LocalDbVersion(dbVersion: 0, schemaVersion: null, hasVersionMeta: false);

  /// SQLITE_CORRUPT or SQLITE_NOTADB: the file itself is broken, for good.
  static bool isPermanentlyUnreadable(int extendedResultCode) =>
      const {11, 26}.contains(extendedResultCode & 0xFF);

  /// Why a transient SQLite error left the version unknown, or `null` when
  /// the error is not one of these and should propagate as is. CANTOPEN after
  /// a successful [opened] is the WAL side file a read-only folder denies
  /// (that is how Windows reports it); before it, the DB itself is missing.
  static LocalDbUnreadableReason? unreadableReasonFor(
    int extendedResultCode, {
    bool opened = false,
  }) =>
      switch (extendedResultCode) {
        _ when const {5, 6}.contains(extendedResultCode & 0xFF) =>
          LocalDbUnreadableReason.locked,
        264 || 776 => LocalDbUnreadableReason.interruptedWrite,
        // READONLY_CANTLOCK, READONLY_CANTINIT, READONLY_DIRECTORY.
        520 || 1288 || 1544 => LocalDbUnreadableReason.readOnlyLocation,
        14 when opened => LocalDbUnreadableReason.readOnlyLocation,
        _ => null,
      };

  /// A `schema_meta` without `key`/`value` columns is not the table we know.
  bool _hasSchemaMetaColumns(sqlite3.Database db) {
    final columns = db
        .select("SELECT name FROM pragma_table_info('schema_meta')")
        .map((row) => row['name'].toString().toLowerCase())
        .toSet();
    return columns.containsAll(const {'key', 'value'});
  }

  int? _readIntMeta(sqlite3.Database db, String key) {
    final result = db.select(
      'SELECT value FROM schema_meta WHERE key = ? LIMIT 1',
      [key],
    );
    if (result.isEmpty) return null;
    return int.tryParse(result.first['value']?.toString() ?? '');
  }
}

/// Why [LocalDbVersionReader] could not read the local DB right now.
enum LocalDbUnreadableReason {
  /// SQLITE_BUSY / SQLITE_LOCKED: another connection holds the DB.
  locked,

  /// SQLITE_READONLY_ROLLBACK / _RECOVERY: a hot journal or WAL left by an
  /// interrupted write, which a read-only open cannot roll back.
  interruptedWrite,

  /// SQLITE_READONLY_DIRECTORY/_CANTLOCK/_CANTINIT (or CANTOPEN on Windows):
  /// a WAL DB in a folder we cannot write to.
  readOnlyLocation,
}

/// The local DB exists but its version is unknown for now, so no plan may be
/// built on it. Holds only primitives so it survives the isolate hop.
class LocalDbUnreadableException implements Exception {
  const LocalDbUnreadableException(
    this.reason,
    this.extendedResultCode,
    this.detail,
  );

  final LocalDbUnreadableReason reason;
  final int extendedResultCode;
  final String detail;

  @override
  String toString() {
    final strings = AppL10n.strings.libraryDomain;
    return switch (reason) {
      LocalDbUnreadableReason.locked => strings.localDbLocked,
      LocalDbUnreadableReason.interruptedWrite =>
        strings.localDbInterruptedWrite,
      LocalDbUnreadableReason.readOnlyLocation =>
        strings.localDbReadOnlyLocation,
    };
  }
}
