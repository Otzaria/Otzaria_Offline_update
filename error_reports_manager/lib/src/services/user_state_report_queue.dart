import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../models/outbox_report.dart';
import '../port/app_report.dart';
import '../port/direct_error_report.dart';
import '../port/plugin_report_record.dart';
import 'report_outbox.dart';

Future<String?> locateUserStateDb({
  required String dataRoot,
  String? databasesPathSetting,
  String? libraryPathSetting,
  Future<bool> Function(String dir)? isWritable,
  String fileName = UserStateReportQueue.fileName,
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
    preferred = internal;
  }
  final writable = p.equals(preferred, internal) ||
      await (isWritable ?? _canWriteIn)(preferred);
  final file = File(p.join(writable ? preferred : internal, fileName));
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

const List<String> legacyReportBoxes = [
  'error_reports_queue',
  'app_reports_queue',
  'plugin_reports_queue',
];

/// תורי Hive שלא הועברו: ב-`.hive` יש דיווחים **ממתינים**, ואין לתור אף שורה
/// ב-`user_state.db`. אוצריא הנוכחית כבר אינה מעבירה אותם, ולכן אינם חוסמים.
Future<List<String>> findUnmigratedReportBoxes({
  required String dataRoot,
  String? userStateDb,
}) async {
  final candidates = <String>[];
  for (final box in legacyReportBoxes) {
    final file = File(p.join(dataRoot, '$box.hive'));
    if (!await file.exists()) continue;
    final bytes = await file.readAsBytes();
    if ((await Isolate.run(() => hivePendingReportCount(bytes)) ?? 0) > 0) {
      candidates.add(box);
    }
  }
  if (candidates.isEmpty || userStateDb == null) return candidates;
  return Isolate.run(() => _boxesWithoutRows(userStateDb, candidates));
}

/// מספר הפריטים ברשימה `pending_reports` בקובץ box של hive_ce (המסגרת האחרונה
/// של המפתח קובעת). `null` כשהקובץ אינו בפורמט המוכר.
int? hivePendingReportCount(Uint8List bytes) {
  const key = 'pending_reports';
  final data = ByteData.sublistView(bytes);
  int? count;
  var offset = 0;
  while (offset + 4 <= bytes.length) {
    final length = data.getUint32(offset, Endian.little);
    if (length < 10 || offset + length > bytes.length) return null;
    final frameEnd = offset + length - 4;
    var pos = offset + 4;
    final keyType = bytes[pos++];
    String? name;
    if (keyType == 1) {
      final keyLength = bytes[pos++];
      if (pos + keyLength > frameEnd) return null;
      name = utf8.decode(bytes.sublist(pos, pos + keyLength),
          allowMalformed: true);
      pos += keyLength;
    } else if (keyType == 0) {
      pos += 4;
    } else {
      return null;
    }
    if (name == key) {
      if (pos >= frameEnd) {
        count = 0;
      } else {
        final type = bytes[pos];
        count = (type == 9 || type == 10) && pos + 5 <= frameEnd
            ? data.getUint32(pos + 1, Endian.little)
            : 0;
      }
    }
    offset += length;
  }
  return count;
}

List<String> _boxesWithoutRows(String dbPath, List<String> boxes) {
  if (!File(dbPath).existsSync()) return boxes;
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final table = db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' "
      "AND name='pending_reports'",
    );
    if (table.isEmpty) return boxes;
    return [
      for (final box in boxes)
        if (db.select(
          'SELECT 1 FROM pending_reports WHERE kind IN (?, ?) LIMIT 1',
          ['$box/pending_reports', '$box/sent_reports'],
        ).isEmpty)
          box,
    ];
  } finally {
    db.close();
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
    this.reportsQueueFormat,
    DateTime Function()? clock,
    IsolateRunner? runIsolated,
  })  : _clock = clock ?? DateTime.now,
        _run = runIsolated ?? Isolate.run;

  static const String fileName = 'user_state.db';

  /// ה-`user_version` שאוצריא כותבת (`UserStateDatabase._schemaVersion`). מסד
  /// חדש ממנו — לא נוגעים בו בכלל.
  static const int knownSchemaVersion = 2;

  static const int knownQueueFormat = 2;

  static const String carriedBy = 'offline-update';

  // שמות מ-`DirectErrorReportService` ו-`SentReportsCounter` באוצריא.
  static const String pendingKind = 'error_reports_queue/pending_reports';
  static const String sentKind = 'error_reports_queue/sent_reports';
  static const String appPendingKind = 'app_reports_queue/pending_reports';
  static const String appPendingKindV2 = 'app_reports_queue/pending_reports_v2';
  static const String pluginPendingKind =
      'plugin_reports_queue/pending_reports';
  static const String counterBox = 'error_reports_queue';
  static const String counterKey = 'sent_reports_total';
  static const int maxSentReportsToKeep = 100;

  final String dbPath;

  /// `reportsQueueFormat` מ-`otzaria_capabilities.json`; `null` = הקובץ חסר.
  /// גם כשהוא מוכר, `PRAGMA user_version` חייב להיות מוכר.
  final int? reportsQueueFormat;
  final DateTime Function() _clock;
  final IsolateRunner _run;

  @override
  Future<int> countSendable() {
    final path = dbPath;
    final format = reportsQueueFormat;
    return _run(() => _readSendable(path, format).length);
  }

  @override
  Future<QueueCollectResult> collectTo(ReportOutbox outbox) async {
    final path = dbPath;
    final format = reportsQueueFormat;
    final rows = await _run(() => _readSendable(path, format));
    if (rows.isEmpty) return (collected: 0, error: null);

    String? error;
    final written = <_MarkRow>[];
    for (final row in rows) {
      try {
        final bytes = await _run(() => _encodeRow(path, format, row));
        if (bytes == null) continue;
        await outbox.write(row.outboxId, bytes);
        written.add(row);
      } catch (e) {
        error ??= '$e';
        await _discardQuietly(outbox, row.outboxId);
      }
    }
    if (written.isEmpty) return (collected: 0, error: error);

    final nowMs = _clock().millisecondsSinceEpoch;
    final List<({bool moved, String? error})> marks;
    try {
      marks = await _markIsolated(_run, path, format, written, nowMs);
    } catch (_) {
      for (final row in written) {
        await _discardQuietly(outbox, row.outboxId);
      }
      rethrow;
    }

    final moved = {
      for (var i = 0; i < written.length; i++)
        if (marks[i].moved) written[i].outboxId,
    };
    for (var i = 0; i < written.length; i++) {
      if (marks[i].moved) continue;
      error ??= marks[i].error;
      if (!moved.contains(written[i].outboxId)) {
        await _discardQuietly(outbox, written[i].outboxId);
      }
    }
    return (collected: moved.length, error: error);
  }

  static Future<List<({bool moved, String? error})>> _markIsolated(
    IsolateRunner run,
    String path,
    int? format,
    List<_MarkRow> rows,
    int nowMs,
  ) =>
      run(() => _markAllIn(path, format, rows, nowMs));

  static Future<void> _discardQuietly(ReportOutbox outbox, String id) async {
    try {
      await outbox.discard(id);
    } catch (_) {}
  }

  // ── מכאן — רק בתוך ה-isolate ────────────────────────────────────────────

  /// `null` = אין מה לגעת בו: אין קובץ, פורמט תור לא מוכר, או בלי הטבלה.
  static Database? _open(String dbPath, int? queueFormat) {
    if (!File(dbPath).existsSync()) return null;
    if (queueFormat != null &&
        queueFormat != 1 &&
        queueFormat != knownQueueFormat) {
      return null;
    }
    final db = sqlite3.open(dbPath, mode: OpenMode.readWrite);
    try {
      db.execute('PRAGMA busy_timeout=5000');
      final version = db.select('PRAGMA user_version').first.values.first;
      final table = db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' "
        "AND name='pending_reports'",
      );
      final knownLayout = version is int && version <= knownSchemaVersion;
      if (!knownLayout || table.isEmpty) {
        db.close();
        return null;
      }
      return db;
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static List<_MarkRow> _readSendable(String dbPath, int? queueFormat) {
    final db = _open(dbPath, queueFormat);
    if (db == null) return const [];
    try {
      final out = <_MarkRow>[];
      final seen = <String>{};
      final statement = db.prepare(
        'SELECT id, kind, payload_json FROM pending_reports '
        'WHERE kind IN (?, ?, ?, ?) ORDER BY id',
      );
      try {
        final cursor = statement.selectCursor(
          [pendingKind, appPendingKind, appPendingKindV2, pluginPendingKind],
        );
        while (cursor.moveNext()) {
          final built = _build(cursor.current);
          if (built == null || !seen.add(built.mark.outboxId)) continue;
          out.add(built.mark);
        }
      } finally {
        statement.close();
      }
      return out;
    } finally {
      db.close();
    }
  }

  static Uint8List? _encodeRow(String dbPath, int? queueFormat, _MarkRow mark) {
    final db = _open(dbPath, queueFormat);
    if (db == null) return null;
    try {
      final rows = db.select(
        'SELECT id, kind, payload_json FROM pending_reports '
        'WHERE id = ? AND kind = ?',
        [mark.rowId, mark.pendingKind],
      );
      if (rows.isEmpty) return null;
      final built = _build(rows.first);
      if (built == null || built.mark.payloadDigest != mark.payloadDigest) {
        return null;
      }
      return OutboxReport.encodeFile(built.fileJson);
    } finally {
      db.close();
    }
  }

  static ({_MarkRow mark, Map<String, dynamic> fileJson})? _build(Row row) {
    final json = row['payload_json'] as String;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      final pendingKind = row['kind'] as String;
      final kind = pendingKind == appPendingKindV2
          ? _ReportKind.app
          : _ReportKind.values
              .firstWhere((kind) => kind.pendingKind == pendingKind);
      final String id;
      final String title;
      final String createdAt;
      final Map<String, dynamic> body;
      switch (kind) {
        case _ReportKind.book:
          final report = DirectErrorReport.fromJson(decoded);
          if (!report.isSendable) return null;
          id = report.id;
          title = report.bookTitle;
          createdAt = decoded['createdAt'] as String;
          body = report.toApiPayload();
        case _ReportKind.app:
          // דיווח מהתור של אוצריא הוא על אוצריא — `product` לעולם לא עובר.
          final report = AppReport.fromJson(decoded).copyWith(product: null);
          if (report.validate() != null) return null;
          id = report.reportId;
          title = report.title;
          createdAt = report.createdAt.toUtc().toIso8601String();
          body = report.toApiPayload();
          if (utf8.encode(jsonEncode(body)).length >
              AppReport.maxRequestBytes) {
            return null;
          }
        case _ReportKind.plugin:
          final report = PluginReportRecord.fromJson(decoded);
          if (report.reportId.isEmpty ||
              report.pluginUid.isEmpty ||
              report.details.trim().isEmpty) {
            return null;
          }
          id = report.reportId;
          title = report.pluginName;
          createdAt = report.createdAt.toIso8601String();
          body = report.toApiPayload();
      }
      final mark = _MarkRow(
        rowId: row['id'] as int,
        payloadDigest: _digest(json),
        kind: kind,
        pendingKind: pendingKind,
        reportId: id,
      );
      return (
        mark: mark,
        fileJson: OutboxReport.fileJson(
          reportId: mark.outboxId,
          bookTitle: title,
          createdAt: createdAt,
          body: body,
          endpoint: kind.endpoint,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static String _digest(String payloadJson) =>
      sha256.convert(utf8.encode(payloadJson)).toString();

  static List<({bool moved, String? error})> _markAllIn(
    String dbPath,
    int? queueFormat,
    List<_MarkRow> rows,
    int nowMs,
  ) {
    final db = _open(dbPath, queueFormat);
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

  static bool _markAsSent(Database db, _MarkRow row, int now) {
    final kind = row.kind;
    final pendingKind = row.pendingKind;
    final sentKind = '${kind.box}/sent_reports';
    final idOf = _field('json_extract', '\$.${kind.idField}');
    final rejection = _field('json_type', r'$.rejectionReason');
    db.execute('BEGIN IMMEDIATE');
    try {
      final current = db.select(
        'SELECT payload_json FROM pending_reports WHERE id = ? AND kind = ?',
        [row.rowId, pendingKind],
      );
      final currentJson =
          current.isEmpty ? null : current.first['payload_json'] as String;
      if (currentJson == null || _digest(currentJson) != row.payloadDigest) {
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
        [sentKind, row.historyJson(currentJson, now), now],
      );
      db.execute(
        'DELETE FROM pending_reports WHERE kind = ? AND id NOT IN ('
        'SELECT id FROM pending_reports WHERE kind = ? '
        'ORDER BY id DESC LIMIT ?)',
        [sentKind, sentKind, maxSentReportsToKeep],
      );
      if (existing == 0) {
        _incrementCounter(db, box: kind.box, floor: kept, now: now);
      }

      // `deletePendingReport`: כל השורות הממתינות באותו מזהה.
      if (kind == _ReportKind.app) {
        db.execute(
          'DELETE FROM pending_reports WHERE kind IN (?, ?) AND $idOf = ?',
          [appPendingKind, appPendingKindV2, reportId],
        );
      } else {
        db.execute(
          'DELETE FROM pending_reports WHERE kind = ? AND $idOf = ?',
          [pendingKind, reportId],
        );
      }
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
    required String box,
  }) {
    final rows = db.select(
      'SELECT payload_json FROM lists WHERE box = ? AND key = ?',
      [box, counterKey],
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
        box,
        counterKey,
        jsonEncode([next]),
        now
      ],
    );
  }
}

class _MarkRow {
  const _MarkRow({
    required this.rowId,
    required this.payloadDigest,
    required this.reportId,
    required this.kind,
    required this.pendingKind,
  });

  final int rowId;
  final _ReportKind kind;
  final String pendingKind;
  final String payloadDigest;
  final String reportId;

  String get outboxId =>
      kind == _ReportKind.book ? reportId : '${kind.name}-$reportId';

  String historyJson(String payloadJson, int now) {
    final json = jsonDecode(payloadJson) as Map<String, dynamic>;
    final at =
        DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String();
    if (kind == _ReportKind.app) {
      json.remove('diagnostics');
      json.remove('errorLog');
      json.remove('images');
      json.remove('minidump');
      json['sentAt'] = at;
    }
    json['carriedBy'] = UserStateReportQueue.carriedBy;
    json['carriedAt'] = at;
    return jsonEncode(json);
  }
}

enum _ReportKind {
  book('error_reports_queue', 'id', OutboxReport.reportingEndpoint),
  app('app_reports_queue', 'reportId', OutboxReport.appReportingEndpoint),
  plugin(
      'plugin_reports_queue', 'reportId', OutboxReport.pluginReportingEndpoint);

  const _ReportKind(this.box, this.idField, this.endpoint);
  final String box;
  final String idField;
  final String endpoint;
  String get pendingKind => '$box/pending_reports';
}
