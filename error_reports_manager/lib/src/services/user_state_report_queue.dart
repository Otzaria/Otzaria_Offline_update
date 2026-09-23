import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../models/outbox_report.dart';
import '../port/direct_error_report.dart';
import 'report_outbox.dart';

/// `user_state.db` כמו `AppPaths.resolveNotesDbPath` של אוצריא. `null` = אין
/// מסד שהיא הייתה פותחת — ולעולם לא יוצרים אחד.
Future<String?> locateUserStateDb({
  required String dataRoot,
  String? databasesPathSetting,
  String? libraryPathSetting,
  Future<bool> Function(String dir)? isWritable,
}) async {
  final internal = p.join(dataRoot, 'databases');
  final String preferred;
  if (databasesPathSetting != null && databasesPathSetting.isNotEmpty) {
    preferred = databasesPathSetting;
  } else if (await Directory(internal).exists()) {
    preferred = internal;
  } else if (libraryPathSetting != null && libraryPathSetting.isNotEmpty) {
    preferred = p.join(p.dirname(libraryPathSetting), 'databases');
  } else {
    // בלי הגדרה אוצריא נופלת ל-`<dataRoot>/books`, כלומר לאותה `databases`.
    preferred = internal;
  }
  // `_writableDatabasesDirectory`: המועדפת רק כשאפשר לכתוב בה (גם אם תיווצר).
  final writable = p.equals(preferred, internal) ||
      await (isWritable ?? _canWriteIn)(preferred);
  final file = File(
      p.join(writable ? preferred : internal, UserStateReportQueue.fileName));
  return await file.exists() ? file.path : null;
}

/// כמו `_isDirectoryWritable` של אוצריא, בלי ליצור את התיקייה: תיקייה חסרה
/// נבדקת באב הקיים הקרוב, שבו אוצריא הייתה יוצרת אותה.
Future<bool> _canWriteIn(String dir) async {
  var target = Directory(dir);
  while (!await target.exists()) {
    final parent = target.parent;
    if (parent.path == target.path) return false;
    target = parent;
  }
  final probe = File(p.join(target.path, '.otzaria_launcher_write_probe'));
  try {
    await probe.writeAsString('', flush: true);
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      if (await probe.exists()) await probe.delete();
    } catch (_) {}
  }
}

/// תוצאת איסוף: כמה שורות הועברו בפועל, ושגיאה אם חלק לא הועברו.
typedef QueueCollectResult = ({int collected, String? error});

/// תור הדיווחים של אוצריא. ממשק, כדי שבדיקות הלאנצ'ר ירוצו בלי מסד.
abstract interface class OtzariaReportQueue {
  /// כמה דיווחים ממתינים שאפשר לשלוח.
  Future<int> countSendable();

  /// מעביר כל דיווח ניתן לשליחה ל-[outbox] ומסמן אותו באוצריא כנשלח.
  Future<QueueCollectResult> collectTo(ReportOutbox outbox);
}

/// מריץ חישוב ב-isolate נפרד; מוזרק כדי שבדיקה תראה שהעבודה עוברת בו.
typedef IsolateRunner = Future<R> Function<R>(
  FutureOr<R> Function() computation,
);

/// הקריאה והכתיבה הישירה ל-`user_state.db`, **רק כשאוצריא סגורה**. כל עבודת
/// ה-SQLite (FFI סינכרוני) רצה ב-[IsolateRunner] — ראו AGENTS §5.9.
class UserStateReportQueue implements OtzariaReportQueue {
  UserStateReportQueue(
    this.dbPath, {
    DateTime Function()? clock,
    IsolateRunner? runIsolated,
  })  : _clock = clock ?? DateTime.now,
        _run = runIsolated ?? Isolate.run;

  static const String fileName = 'user_state.db';

  /// ה-`user_version` שאוצריא כותבת (`UserStateDatabase._schemaVersion`). מסד
  /// חדש ממנו — לא נוגעים בו בכלל.
  static const int knownSchemaVersion = 1;

  // שמות מ-`DirectErrorReportService` ו-`SentReportsCounter` באוצריא.
  static const String pendingKind = 'error_reports_queue/pending_reports';
  static const String sentKind = 'error_reports_queue/sent_reports';
  static const String counterBox = 'error_reports_queue';
  static const String counterKey = 'sent_reports_total';
  static const int maxSentReportsToKeep = 100;

  final String dbPath;
  final DateTime Function() _clock;
  final IsolateRunner _run;

  @override
  Future<int> countSendable() {
    // משתנה מקומי: סגירה שנוגעת בשדה הייתה לוכדת את `this` אל ה-isolate.
    final path = dbPath;
    return _run(() => _readSendable(path)?.length ?? 0);
  }

  @override
  Future<QueueCollectResult> collectTo(ReportOutbox outbox) async {
    final path = dbPath;
    final rows = await _run(() => _readSendable(path));
    if (rows == null || rows.isEmpty) return (collected: 0, error: null);

    String? error;
    // הקבצים קודם: קריסה לפני הסימון משאירה דיווח שעדיין ממתין באוצריא,
    // ובאיסוף הבא הוא נכתב שוב באותו שם — לעולם לא דיווח שאבד.
    final written = <_PendingRow>[];
    for (final row in rows) {
      try {
        await outbox.write(
          row.reportId,
          OutboxReport.fileJson(
            reportId: row.reportId,
            bookTitle: row.bookTitle,
            createdAt: row.createdAt,
            body: row.body,
          ),
        );
        written.add(row);
      } catch (e) {
        error ??= '$e';
        await _discardQuietly(outbox, row.reportId);
      }
    }
    if (written.isEmpty) return (collected: 0, error: error);

    final nowMs = _clock().millisecondsSinceEpoch;
    final List<({bool moved, String? error})> marks;
    try {
      marks = await _run(() => _markAllIn(path, written, nowMs));
    } catch (_) {
      // שום שורה לא סומנה — ולכן אף קובץ לא נשאר, אחרת הדיווח נשלח פעמיים.
      for (final row in written) {
        await _discardQuietly(outbox, row.reportId);
      }
      rethrow;
    }

    // מזהה שהועבר בריצה הזו — הקובץ שלו לעולם אינו נמחק.
    final moved = {
      for (var i = 0; i < written.length; i++)
        if (marks[i].moved) written[i].reportId,
    };
    for (var i = 0; i < written.length; i++) {
      if (marks[i].moved) continue;
      // התיבה משקפת את אוצריא: מה שלא סומן שם אינו נשאר כאן.
      error ??= marks[i].error;
      if (!moved.contains(written[i].reportId)) {
        await _discardQuietly(outbox, written[i].reportId);
      }
    }
    return (collected: moved.length, error: error);
  }

  static Future<void> _discardQuietly(ReportOutbox outbox, String id) async {
    try {
      await outbox.discard(id);
    } catch (_) {}
  }

  // ── מכאן — רק בתוך ה-isolate ────────────────────────────────────────────

  /// `null` = אין מה לגעת בו: אין קובץ, סכמה חדשה מהמוכרת, או בלי הטבלה.
  static Database? _open(String dbPath) {
    if (!File(dbPath).existsSync()) return null;
    final db = sqlite3.open(dbPath, mode: OpenMode.readWrite);
    try {
      db.execute('PRAGMA busy_timeout=5000');
      final version = db.select('PRAGMA user_version').first.values.first;
      final table = db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' "
        "AND name='pending_reports'",
      );
      if (version is! int || version > knownSchemaVersion || table.isEmpty) {
        db.close();
        return null;
      }
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// הממתינים שאפשר לשלוח, אחד לכל מזהה (הראשון): הסימון מוחק את כל השורות
  /// באותו מזהה, ושורה שנייה הייתה מוחקת את הקובץ שהראשונה כתבה.
  static List<_PendingRow>? _readSendable(String dbPath) {
    final db = _open(dbPath);
    if (db == null) return null;
    try {
      final out = <_PendingRow>[];
      final seen = <String>{};
      final rows = db.select(
        'SELECT id, payload_json FROM pending_reports WHERE kind = ? '
        'ORDER BY id',
        [pendingKind],
      );
      for (final row in rows) {
        final json = row['payload_json'] as String;
        try {
          final decoded = jsonDecode(json);
          if (decoded is! Map<String, dynamic>) continue;
          final report = DirectErrorReport.fromJson(decoded);
          if (!report.isSendable || !seen.add(report.id)) continue;
          out.add(_PendingRow(
            rowId: row['id'] as int,
            payloadJson: json,
            reportId: report.id,
            bookTitle: report.bookTitle,
            createdAt: decoded['createdAt'] as String,
            body: report.toApiPayload(),
          ));
        } catch (_) {
          // רשומה שאוצריא עצמה לא הייתה מפענחת — נשארת בתור, לעריכה שם.
        }
      }
      return out;
    } finally {
      db.close();
    }
  }

  /// כל שורה בטרנזקציה משלה. `moved: false` בלי `error` = השורה השתנתה מאז
  /// הקריאה; עם `error` = הסימון נכשל (הטקסט ליומן).
  static List<({bool moved, String? error})> _markAllIn(
    String dbPath,
    List<_PendingRow> rows,
    int nowMs,
  ) {
    final db = _open(dbPath);
    if (db == null) {
      const gone = 'user_state.db unusable when marking';
      return [for (final _ in rows) (moved: false, error: gone)];
    }
    try {
      return [
        for (final row in rows)
          () {
            try {
              return (moved: _markAsSent(db, row, nowMs), error: null);
            } catch (e) {
              return (moved: false, error: '$e');
            }
          }(),
      ];
    } finally {
      // אחרי COMMIT-ים: כשל בסגירה אסור שייראה כ"לא סומן", אחרת הקבצים נמחקים.
      try {
        db.close();
      } catch (_) {}
    }
  }

  /// שדה מתוך `payload_json` ב-SQL; `CASE` כדי ש-JSON פגום לא יפיל את השאילתה.
  static String _field(String fn, String path) =>
      "(CASE WHEN json_valid(payload_json) THEN $fn(payload_json, '$path') END)";

  /// `markPendingReportAsSent` של אוצריא, בטרנזקציה אחת. `false` = השורה
  /// השתנתה או נעלמה מאז שנקראה, ואז לא נוגעים בכלום.
  static bool _markAsSent(Database db, _PendingRow row, int now) {
    final idOf = _field('json_extract', r'$.id');
    final rejection = _field('json_type', r'$.rejectionReason');
    db.execute('BEGIN IMMEDIATE');
    try {
      final current = db.select(
        'SELECT payload_json FROM pending_reports WHERE id = ? AND kind = ?',
        [row.rowId, pendingKind],
      );
      if (current.isEmpty || current.first['payload_json'] != row.payloadJson) {
        db.execute('ROLLBACK');
        return false;
      }
      final reportId = row.reportId;
      int count(String where, List<Object?> args) => db
          .select('SELECT COUNT(*) FROM pending_reports WHERE $where', args)
          .first
          .values
          .first as int;

      // `_saveSentReport`: `kept` = נשלחו (בלי `rejectionReason`) לפני ההוספה;
      // רשומה קיימת באותו מזהה מוחלפת, ואז חיתוך ל-100.
      final kept = count(
        "kind = ? AND ($rejection IS NULL OR $rejection = 'null')",
        [sentKind],
      );
      final existing = count('kind = ? AND $idOf = ?', [sentKind, reportId]);
      db.execute(
        'DELETE FROM pending_reports WHERE kind = ? AND $idOf = ?',
        [sentKind, reportId],
      );
      db.execute(
        'INSERT INTO pending_reports (kind, payload_json, created_at) '
        'VALUES (?, ?, ?)',
        [sentKind, row.payloadJson, now],
      );
      db.execute(
        'DELETE FROM pending_reports WHERE kind = ? AND id NOT IN ('
        'SELECT id FROM pending_reports WHERE kind = ? '
        'ORDER BY id DESC LIMIT ?)',
        [sentKind, sentKind, maxSentReportsToKeep],
      );
      if (existing == 0) _incrementCounter(db, floor: kept, now: now);

      // `deletePendingReport`: כל השורות הממתינות באותו מזהה.
      db.execute(
        'DELETE FROM pending_reports WHERE kind = ? AND $idOf = ?',
        [pendingKind, reportId],
      );
      db.execute('COMMIT');
      return true;
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  /// `SentReportsCounter.increment`: `max(current, floor) + 1` ברשימה `[N]`.
  static void _incrementCounter(
    Database db, {
    required int floor,
    required int now,
  }) {
    final rows = db.select(
      'SELECT payload_json FROM lists WHERE box = ? AND key = ?',
      [counterBox, counterKey],
    );
    var current = 0;
    if (rows.isNotEmpty) {
      final list = jsonDecode(rows.first['payload_json'] as String);
      if (list is List && list.isNotEmpty && list.first is int) {
        current = list.first as int;
      }
    }
    final next = (current > floor ? current : floor) + 1;
    db.execute(
      'INSERT INTO lists (box, key, payload_json, updated_at) '
      'VALUES (?, ?, ?, ?) ON CONFLICT(box, key) DO UPDATE SET '
      'payload_json = excluded.payload_json, updated_at = excluded.updated_at',
      [
        counterBox,
        counterKey,
        jsonEncode([next]),
        now
      ],
    );
  }
}

/// שורה ממתינה, כנתונים פשוטים בלבד — היא עוברת בין isolates.
class _PendingRow {
  const _PendingRow({
    required this.rowId,
    required this.payloadJson,
    required this.reportId,
    required this.bookTitle,
    required this.createdAt,
    required this.body,
  });

  final int rowId;

  /// הטקסט המקורי — גם כדי לזהות שינוי, וגם כדי לשמור בהיסטוריה כמות שהוא.
  final String payloadJson;
  final String reportId;
  final String bookTitle;
  final String createdAt;
  final Map<String, dynamic> body;
}
