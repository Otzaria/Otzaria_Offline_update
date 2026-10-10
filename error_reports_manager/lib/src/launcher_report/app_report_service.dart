import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../port/app_report.dart';

enum AppReportDeliveryStatus { sent, queued, failed }

/// סיבת כשל קבוע במסירה.
enum AppReportFailureReason {
  /// השרת דחה את התוכן (400/413/422) — אין טעם לנסות שוב.
  rejected,

  /// השרת החזיק תוכן אחר באותו מזהה גם אחרי החלפת המזהה.
  idConflict,

  /// הדיווח כבר אינו בתור (נשלח ברקע, או הועבר ל-`.bad`) — לא נשלח דבר.
  notPending,
}

/// תוצאת שליחת דיווח על התוכנה.
class AppReportDeliveryResult {
  const AppReportDeliveryResult({
    required this.status,
    required this.report,
    this.failureReason,
    this.httpStatus,
    this.rejectedField,
  });

  final AppReportDeliveryStatus status;

  /// הרשומה כפי שנשמרה (עם מזהה חדש אחרי 409, ומספר ה-issue אחרי שליחה).
  final AppReport report;
  final AppReportFailureReason? failureReason;
  final int? httpStatus;

  /// שם השדה שהשרת דחה ב-422, אם החזיר.
  final String? rejectedField;

  bool get isSent => status == AppReportDeliveryStatus.sent;
  bool get isQueued => status == AppReportDeliveryStatus.queued;
  bool get isFailed => status == AppReportDeliveryStatus.failed;

  int? get issueNumber => report.issueNumber;
  String? get issueUrl => report.issueUrl;

  /// נוסף כתגובה ל-issue פתוח עם אותה חתימה.
  bool get merged => report.merged;

  /// נשמר בשרת, ה-issue ייפתח מאוחר יותר.
  bool get issuePending => report.issuePending;
}

/// תוצאת סבב שליחה של התור.
class FlushOutcome {
  const FlushOutcome({
    this.sent = 0,
    this.stoppedOnTransientFailure = false,
    this.capped = false,
    this.failed = 0,
    this.dropped = 0,
    this.skipped = 0,
  });

  final int sent;

  /// רשומות שנכשלו בגלל שגיאה מקומית (דיסק, תור לא קריא) — נשארו בתור.
  final int failed;

  /// רשומות שהשרת דחה (400/413/422) או ש-409 חזר עליהן, והוסרו מהתור.
  final int dropped;

  /// רשומות שטופלו בלי תוצאה שנספרת: 409 ראשון (נכתבה מחדש במזהה חדש),
  /// דיווח שכבר בהיסטוריה, וקובץ חסר או פגום שהועבר ל-`.bad`.
  final int skipped;

  /// הסבב נעצר בכשל זמני (רשת, 429, 5xx) — מה שנשאר ייענה בסבב הבא.
  final bool stoppedOnTransientFailure;

  /// הסבב הגיע לתקרת הבקשות שלו ויש עוד בתור. זה אינו כשל.
  final bool capped;
}

/// שליחת הדיווחים של הלאנצ'ר על עצמו לאתר, שפותח מהם issue בריפו שלו.
///
/// פורט של `AppReportService` של אוצריא; הפרטים ב-README.
class AppReportService {
  AppReportService({
    required this.directory,
    http.Client? client,
    DateTime Function()? clock,
    this.log,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _clock = clock ?? DateTime.now;

  /// הנתיב המקובל בתוך תיקיית המצב — ליד תיבת היציאה, לא תחת `mirror/`.
  static String dirIn(String stateDir) =>
      p.join(stateDir, 'reports', 'launcher');

  static final Uri endpoint = Uri.parse('https://otzaria.org/api/app-reports');

  static const int maxSentReportsToKeep = 100;
  static const Duration timeout = Duration(seconds: 10);

  /// צילומי מסך הם מגה-בתים רבים; בחיבור איטי 10 שניות לא מספיקות.
  static const Duration timeoutWithImages = Duration(minutes: 2);
  static const Duration flushInterval = Duration(minutes: 5);

  /// השרת מאפשר 8 בדקה לכתובת, ומעלה הדיווחים של אוצריא חולק איתו את המכסה.
  static const int maxBackgroundFlushPerRun = 4;
  static const int maxManualFlushPerRun = 8;

  /// אחרי כמה החלפות מזהה ב-409 דיווח נחשב נדחה, ולא מחליפים עוד לנצח.
  static const int maxIdChanges = 3;

  final String directory;

  /// שורות ליומן — החבילה אינה מכירה את `AppLogger`.
  final void Function(String message)? log;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;

  Timer? _flushTimer;
  Future<FlushOutcome>? _flushing;
  bool _disposed = false;
  final Map<String, Future<void>> _reportOperationTails = {};
  Future<void> _sentTail = Future<void>.value();
  int _lastQueuedAt = 0;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// כל שינוי בתור או בהיסטוריה — גם משליחה ברקע.
  Stream<void> get changes => _changes.stream;

  String get _pendingDir => p.join(directory, 'pending');
  String get _sentPath => p.join(directory, 'sent.json');

  /// שולח דיווח; בכשל זמני שומר אותו בתור.
  Future<AppReportDeliveryResult> send(AppReport report) => _withReportLock(
        report.reportId,
        () => _send(report, queued: false, idChanges: 0),
      );

  /// שולח דיווח מהתור, עם הצרופות שבקובץ. הקובץ נמחק רק אחרי תוצאה סופית —
  /// סגירת חלון באמצע בקשה ארוכה אינה מאבדת דיווח.
  Future<AppReportDeliveryResult> submitPendingReport(AppReport report) =>
      _withReportLock(report.reportId, () async {
        final meta = await _findPending(report.reportId);
        final read = meta == null ? null : await _readPending(meta, true);
        if (read == null) {
          // נשלח ברקע או הועבר ל-.bad: הרשומה שבידי הקורא בלי צרופות, ושליחתה
          // הייתה שולחת דיווח חסר.
          return AppReportDeliveryResult(
            status: AppReportDeliveryStatus.failed,
            report: report,
            failureReason: AppReportFailureReason.notPending,
          );
        }
        return _send(read.report, queued: true, idChanges: read.idChanges);
      });

  Future<AppReportDeliveryResult> _send(
    AppReport report, {
    required bool queued,
    required int idChanges,
  }) async {
    final originalId = report.reportId;
    final alreadySent = await _sentReport(originalId);
    if (alreadySent != null) {
      await _deletePendingFile(originalId);
      return AppReportDeliveryResult(
        status: AppReportDeliveryStatus.sent,
        report: alreadySent,
      );
    }

    var current = report;
    var attempt = await _trySend(current);
    // 409: התוכן הזה לא נקלט תחת המזהה — הגשה חדשה במזהה חדש.
    if (attempt.kind == _AttemptKind.idConflict) {
      idChanges++;
      current = current.copyWith(reportId: AppReport.generateReportId());
      attempt = await _trySend(current);
    }

    switch (attempt.kind) {
      case _AttemptKind.success:
        final sent = _sentRecord(current, attempt);
        try {
          await _saveSentReport(sent);
          await _deletePendingFile(originalId);
        } catch (error) {
          // נשלח אבל לא נרשם: נשאר בתור, והשרת יענה duplicate בסבב הבא.
          log?.call('App report sent but history write failed: $error');
          await _keepQueued(originalId, current, idChanges);
        }
        unawaited(_safeFlush());
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.sent,
          report: sent,
          httpStatus: attempt.httpStatus,
        );
      case _AttemptKind.permanent:
      case _AttemptKind.idConflict:
        await _deletePendingFile(originalId);
        _notify();
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.failed,
          report: current,
          failureReason: attempt.kind == _AttemptKind.idConflict
              ? AppReportFailureReason.idConflict
              : AppReportFailureReason.rejected,
          httpStatus: attempt.httpStatus,
          rejectedField: attempt.rejectedField,
        );
      case _AttemptKind.transient:
        await _keepQueued(originalId, current, idChanges);
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.queued,
          report: current,
          httpStatus: attempt.httpStatus,
        );
    }
  }

  /// שומר [report] בתור: ברשומה הקיימת של [originalId] (עם מזהה חדש, אם
  /// הוחלף), או כרשומה חדשה.
  Future<void> _keepQueued(
    String originalId,
    AppReport report,
    int idChanges,
  ) async {
    final existing = await _findPending(originalId);
    if (existing != null && report.reportId == originalId) return;
    if (existing != null) await _deletePendingFile(originalId);
    await _writePending(
      report,
      queuedAt: existing?.stamp,
      idChanges: idChanges,
    );
    _notify();
  }

  /// שומר דיווח בתור בלי לנסות לשלוח.
  Future<void> queueReport(AppReport report) => _withReportLock(
        report.reportId,
        () => _keepQueued(report.reportId, report, 0),
      );

  Future<int> getPendingReportsCount() async =>
      (await _listPendingMeta()).length;

  /// התור, מהישן לחדש, בלי צרופות: הרשימה בחלון הניהול אינה מפענחת תמונות.
  Future<List<AppReport>> getPendingReports() async {
    final metas = await _listPendingMeta();
    final decoded = await _decodeManyInIsolate(
      [for (final meta in metas) meta.path],
      false,
    );
    final reports = <AppReport>[];
    for (var i = 0; i < metas.length; i++) {
      final read = await _resolveDecoded(metas[i], decoded[i]);
      if (read != null) reports.add(read.report);
    }
    return reports;
  }

  /// היסטוריית הנשלחים, מהחדש לישן.
  Future<List<AppReport>> getSentReports() async =>
      (await _readSent()).reports.reversed.toList();

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() async {
    final sent = await _readSent();
    return sent.total > sent.reports.length ? sent.total : sent.reports.length;
  }

  Future<void> deletePendingReport(String reportId) => _withReportLock(
        reportId,
        () async {
          await _deletePendingFile(reportId);
          _notify();
        },
      );

  Future<void> deleteSentReport(String reportId) => _withReportLock(
        reportId,
        () => _mutateSent((sent) {
          sent.reports.removeWhere((r) => r.reportId == reportId);
        }),
      );

  Future<void> clearPendingReports() async {
    for (final meta in await _listPendingMeta()) {
      await _deleteQuietly(File(meta.path));
    }
    _notify();
  }

  Future<void> clearSentReports() => _mutateSent((sent) {
        sent.reports.clear();
        sent.total = 0;
      });

  /// כמו [flush], ומחזיר רק כמה נשלחו.
  Future<int> flushPendingReports({
    int maxRequests = maxBackgroundFlushPerRun,
  }) async =>
      (await flush(maxRequests: maxRequests)).sent;

  /// שולח את התור; עוצר בכשל זמני ראשון ומסיר דיווחים שנדחו סופית. קריאה
  /// בזמן סבב רץ מצטרפת אליו ומקבלת את תוצאתו.
  Future<FlushOutcome> flush({int maxRequests = maxBackgroundFlushPerRun}) {
    if (_disposed) return Future.value(const FlushOutcome());
    final running = _flushing;
    if (running != null) return running;
    final run = _runFlush(maxRequests).whenComplete(() {
      _flushing = null;
      _notify();
    });
    return _flushing = run;
  }

  Future<FlushOutcome> _runFlush(int maxRequests) async {
    var sent = 0;
    var requests = 0;
    var failed = 0;
    var dropped = 0;
    var skipped = 0;
    var transient = false;
    var capped = false;
    final List<_PendingMeta> metas;
    try {
      metas = await _listPendingMeta();
    } catch (error) {
      log?.call('App report queue unreadable: $error');
      return const FlushOutcome(failed: 1);
    }
    for (final meta in metas) {
      if (_disposed) break;
      if (requests >= maxRequests) {
        capped = true;
        break;
      }
      try {
        final step = await _withReportLock(
          meta.key,
          () => _flushOne(meta, onRequest: () => requests++),
        );
        if (step == _FlushStep.sent) sent++;
        if (step == _FlushStep.dropped) dropped++;
        if (step == _FlushStep.skipped) skipped++;
        if (step == _FlushStep.transient) {
          transient = true;
          break;
        }
      } catch (error) {
        // כשל בדיסק אינו נרשם כשגיאה שלא נתפסה: זו ראיה לקריסה (§5.10).
        log?.call('App report flush failed for ${meta.key}: $error');
        failed++;
      }
    }
    return FlushOutcome(
      sent: sent,
      stoppedOnTransientFailure: transient,
      capped: capped,
      failed: failed,
      dropped: dropped,
      skipped: skipped,
    );
  }

  Future<_FlushStep> _flushOne(
    _PendingMeta meta, {
    required void Function() onRequest,
  }) async {
    final read = await _readPending(meta, true);
    if (read == null) return _FlushStep.skipped;
    final queued = read.report;
    if (await _sentReport(queued.reportId) != null) {
      await _deleteQuietly(File(meta.path));
      return _FlushStep.skipped;
    }
    onRequest();
    final attempt = await _trySend(queued);
    switch (attempt.kind) {
      case _AttemptKind.success:
        // קודם ההיסטוריה: אם הכתיבה נכשלת הרשומה נשארת בתור, ואינה אובדת.
        await _saveSentReport(_sentRecord(queued, attempt));
        await _deleteQuietly(File(meta.path));
        return _FlushStep.sent;
      case _AttemptKind.idConflict:
        if (read.idChanges + 1 >= maxIdChanges) {
          log?.call('App report id conflict kept recurring, removed');
          await _deleteQuietly(File(meta.path));
          return _FlushStep.dropped;
        }
        await _writePending(
          queued.copyWith(reportId: AppReport.generateReportId()),
          queuedAt: meta.stamp,
          idChanges: read.idChanges + 1,
        );
        await _deleteQuietly(File(meta.path));
        return _FlushStep.skipped;
      case _AttemptKind.permanent:
        log?.call('App report rejected, removed: ${attempt.httpStatus}');
        await _deleteQuietly(File(meta.path));
        return _FlushStep.dropped;
      case _AttemptKind.transient:
        return _FlushStep.transient;
    }
  }

  Future<void> _safeFlush() async {
    try {
      await flush();
    } catch (error) {
      log?.call('App report flush failed: $error');
    }
  }

  /// שליחה מיידית ואחת לחמש דקות. קריאה חוזרת אינה יוצרת טיימר נוסף.
  void startAutomaticFlush() {
    if (_flushTimer != null || _disposed) return;
    unawaited(cleanupStaleTemp().then((_) => _safeFlush()));
    _flushTimer = Timer.periodic(flushInterval, (_) {
      unawaited(_safeFlush());
    });
  }

  /// קבצי `.tmp` שנשארו מכתיבה שנקטעה; הקובץ המקורי שלמים, כי ה-rename אטומי.
  Future<void> cleanupStaleTemp() async {
    try {
      final dirs = [Directory(directory), Directory(_pendingDir)];
      for (final dir in dirs) {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            await _deleteQuietly(entity);
          }
        }
      }
    } catch (error) {
      log?.call('App report temp cleanup failed: $error');
    }
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_ownsClient) _client.close();
    unawaited(_changes.close());
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // ── הדיסק ─────────────────────────────────────────────────────────────

  /// שם הקובץ: המזהה עצמו כשהוא בטוח לנתיב, ואחרת hash שלו.
  static String _fileKey(String reportId) =>
      RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(reportId)
          ? reportId
          : sha256.convert(utf8.encode(reportId)).toString();

  /// הקבצים בתור: `<queuedAt>.<key>.json`. הסדר נקבע משם הקובץ, כך שהרשימה
  /// והספירה אינן קוראות ואינן מפענחות דבר.
  Future<List<_PendingMeta>> _listPendingMeta() async {
    final dir = Directory(_pendingDir);
    if (!await dir.exists()) return const [];
    final metas = <_PendingMeta>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final meta = _PendingMeta.tryParse(entity.path);
      if (meta != null) metas.add(meta);
    }
    metas.sort((a, b) {
      final byStamp = a.stamp.compareTo(b.stamp);
      return byStamp != 0 ? byStamp : a.key.compareTo(b.key);
    });
    return metas;
  }

  Future<_PendingMeta?> _findPending(String reportId) async {
    final key = _fileKey(reportId);
    for (final meta in await _listPendingMeta()) {
      if (meta.key == key) return meta;
    }
    return null;
  }

  /// פענוח בתוך isolate: JSON ו-base64 של תמונות מקפיאים את הממשק.
  /// קובץ פגום מועבר הצידה — הוא לא יישלח לעולם, ואסור שיתקע את התור.
  Future<_PendingRead?> _readPending(
    _PendingMeta meta,
    bool withAttachments,
  ) async {
    final result =
        (await _decodeManyInIsolate([meta.path], withAttachments)).single;
    return _resolveDecoded(meta, result);
  }

  Future<_PendingRead?> _resolveDecoded(
    _PendingMeta meta,
    _PendingDecoded result,
  ) async {
    if (result.missing) return null;
    final error = result.error;
    if (error != null) {
      log?.call('App report queue file unreadable, set aside: $error');
      try {
        await File(meta.path).rename('${meta.path}.bad');
      } catch (_) {}
      return null;
    }
    return result.read;
  }

  /// סטטית: סגירה בתוך מתודת מופע עלולה ללכוד את `this` שאינו ניתן להעברה.
  static Future<List<_PendingDecoded>> _decodeManyInIsolate(
    List<String> paths,
    bool withAttachments,
  ) =>
      Isolate.run(
        () => [
          for (final path in paths) _decodePendingFile(path, withAttachments)
        ],
      );

  Future<void> _writePending(
    AppReport report, {
    int? queuedAt,
    required int idChanges,
  }) async {
    var stamp = queuedAt ?? _clock().microsecondsSinceEpoch;
    // רצף עולה גם בשתי הוספות באותה מיקרו-שנייה — הסדר בתור הוא סדר ההוספה.
    if (queuedAt == null) {
      if (stamp <= _lastQueuedAt) stamp = _lastQueuedAt + 1;
      _lastQueuedAt = stamp;
    }
    final text = await _encodePending(stamp, idChanges, report);
    final meta = _PendingMeta(
      stamp: stamp,
      key: _fileKey(report.reportId),
      directory: _pendingDir,
    );
    await _writeAtomic(File(meta.path), text);
  }

  /// סטטית: סגירה בתוך מתודת מופע עלולה ללכוד את `this` שאינו ניתן להעברה.
  static Future<String> _encodePending(
    int stamp,
    int idChanges,
    AppReport report,
  ) =>
      Isolate.run(
        () => jsonEncode({
          'queuedAt': stamp,
          'idChanges': idChanges,
          'report': report.toJson(),
        }),
      );

  Future<void> _deletePendingFile(String reportId) async {
    final meta = await _findPending(reportId);
    if (meta != null) await _deleteQuietly(File(meta.path));
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // כבר נמחק.
    }
  }

  /// קובץ זמני ואז `rename`, כדי שכשל באמצע לא ישאיר JSON חתוך.
  static Future<void> _writeAtomic(File file, String content) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(file.path);
  }

  /// קריאת ההיסטוריה לתצוגה: אינה מסודרת ב-`_sentTail`, ולכן **אינה נוגעת
  /// בקובץ** — קובץ פגום או כשל קריאה מחזירים ריק, וההעברה ל-`.bad` נעשית רק
  /// בכתיבה (אחרת היא עלולה להעביר קובץ תקין שהכתיבה זה עתה החליפה).
  Future<_SentHistory> _readSent() async {
    try {
      return await _readSentOrThrow(setAside: false);
    } catch (error) {
      log?.call('App report history unreadable: $error');
      return _SentHistory(0, []);
    }
  }

  /// חסר או פגום — היסטוריה ריקה (פגום מועבר ל-`.bad`); כשל קריאה זמני
  /// (למשל אנטי-וירוס שמחזיק את הקובץ) מנוסה שוב וזורק, כדי שכתיבה לא תמחק
  /// את ההיסטוריה והמונה.
  Future<_SentHistory> _readSentOrThrow({required bool setAside}) async {
    final file = File(_sentPath);
    for (var attempt = 0;; attempt++) {
      try {
        if (!await file.exists()) return _SentHistory(0, []);
        return _parseSent(await file.readAsString());
      } on FileSystemException {
        if (attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      } catch (error) {
        // כל שגיאת פענוח (גם TypeError משדה בסוג שגוי) היא קובץ פגום — אחרת
        // כל כתיבה נכשלת, ודיווחים שנשלחו נשלחים שוב כשכפילויות.
        log?.call('App report history corrupt: $error');
        if (setAside) {
          try {
            await file.rename('${file.path}.bad');
          } catch (_) {}
        }
        return _SentHistory(0, []);
      }
    }
  }

  static _SentHistory _parseSent(String text) {
    final json = jsonDecode(text);
    if (json is! Map) throw const FormatException('not a history object');
    final total = json['total'];
    final reports = json['reports'];
    return _SentHistory(
      total is int ? total : 0,
      [
        if (reports is List)
          for (final r in reports)
            if (r is Map) AppReport.fromJson(Map<String, dynamic>.from(r)),
      ],
    );
  }

  /// קריאה-שינוי-כתיבה של ההיסטוריה בטור: שני דיווחים שונים נשמרים במקביל.
  Future<void> _mutateSent(void Function(_SentHistory sent) change) {
    final run = _sentTail.then((_) async {
      final sent = await _readSentOrThrow(setAside: true);
      change(sent);
      await _writeAtomic(
        File(_sentPath),
        jsonEncode({
          'total': sent.total,
          'reports': [for (final r in sent.reports) r.toJson()],
        }),
      );
      _notify();
    });
    _sentTail = run.catchError((Object _) {});
    return run;
  }

  Future<AppReport?> _sentReport(String reportId) async {
    for (final report in (await _readSent()).reports) {
      if (report.reportId == reportId) return report;
    }
    return null;
  }

  Future<void> _saveSentReport(AppReport report) => _mutateSent((sent) {
        final before = sent.reports.length;
        sent.reports.removeWhere((r) => r.reportId == report.reportId);
        final existed = sent.reports.length != before;
        sent.reports.add(report);
        if (sent.reports.length > maxSentReportsToKeep) {
          sent.reports.removeRange(
            0,
            sent.reports.length - maxSentReportsToKeep,
          );
        }
        // המונה לא יורד מתחת למה שכבר נשמר, כמו `SentReportsCounter`.
        if (!existed) {
          sent.total = (sent.total < before ? before : sent.total) + 1;
        }
      });

  /// נעילה לפי המפתח של הקובץ, כך שמזהה ארוך ו-hash שלו נעולים יחד.
  Future<T> _withReportLock<T>(
    String reportIdOrKey,
    Future<T> Function() action,
  ) async {
    final lockKey = _fileKey(reportIdOrKey);
    final previous = _reportOperationTails[lockKey];
    final release = Completer<void>();
    final tail = release.future;
    _reportOperationTails[lockKey] = tail;
    await previous;
    try {
      return await action();
    } finally {
      if (identical(_reportOperationTails[lockKey], tail)) {
        _reportOperationTails.remove(lockKey)?.ignore();
      }
      release.complete();
    }
  }

  AppReport _sentRecord(AppReport report, _Attempt attempt) {
    return report.withoutAttachments().copyWith(
          issueNumber: attempt.issueNumber,
          issueUrl: attempt.issueUrl,
          merged: attempt.merged,
          duplicate: attempt.duplicate,
          issuePending: attempt.issuePending,
          sentAt: _clock(),
        );
  }

  // ── הרשת ──────────────────────────────────────────────────────────────

  Future<_Attempt> _trySend(AppReport report) async {
    final Uint8List body;
    try {
      body = await _encodeBody(report);
    } catch (e) {
      log?.call('App report payload invalid: $e');
      return const _Attempt(_AttemptKind.permanent);
    }
    if (body.length > AppReport.maxRequestBytes) {
      return const _Attempt(
        _AttemptKind.permanent,
        httpStatus: HttpStatus.requestEntityTooLarge,
      );
    }

    try {
      // לא דרך post(): הוא עוטף רשימה ב-cast ומעתיק את הגוף בית-בית.
      final request = http.Request('POST', endpoint)
        ..headers.addAll(const {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        })
        ..bodyBytes = body;
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(report.images.isEmpty ? timeout : timeoutWithImages);
      final status = response.statusCode;
      final decoded = _decodeBody(response.bodyBytes);

      if (status >= 200 && status < 300) {
        final issueNumber = decoded?['issueNumber'];
        final issueUrl = decoded?['issueUrl'];
        return _Attempt(
          _AttemptKind.success,
          httpStatus: status,
          issueNumber: issueNumber is int ? issueNumber : null,
          issueUrl: issueUrl is String ? issueUrl : null,
          merged: decoded?['merged'] == true,
          duplicate: decoded?['duplicate'] == true,
          issuePending: decoded?['issuePending'] == true,
        );
      }
      if (status == HttpStatus.conflict) {
        return _Attempt(_AttemptKind.idConflict, httpStatus: status);
      }
      if (status == HttpStatus.badRequest ||
          status == HttpStatus.requestEntityTooLarge ||
          status == 422) {
        final field = decoded?['field'];
        return _Attempt(
          _AttemptKind.permanent,
          httpStatus: status,
          rejectedField: field is String ? field : null,
        );
      }
      return _Attempt(_AttemptKind.transient, httpStatus: status);
    } on TimeoutException {
      return const _Attempt(_AttemptKind.transient);
    } catch (e) {
      // SocketException / ClientException ודומיהם — כשל רשת זמני.
      log?.call('App report send error: $e');
      return const _Attempt(_AttemptKind.transient);
    }
  }

  /// צילומי מסך מקפיאים את החלון בקידוד; `product` נחתם כאן, בכל שליחה.
  static Future<Uint8List> _encodeBody(AppReport report) {
    final stamped = report.copyWith(product: AppReport.offlineUpdateProduct);
    return Isolate.run(() => utf8.encode(jsonEncode(stamped.toApiPayload())));
  }

  static Map<String, dynamic>? _decodeBody(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// קובץ בתור לפי שמו בלבד.
class _PendingMeta {
  const _PendingMeta({
    required this.stamp,
    required this.key,
    required this.directory,
  });

  final int stamp;
  final String key;
  final String directory;

  String get path =>
      p.join(directory, '${stamp.toString().padLeft(19, '0')}.$key.json');

  /// `null` לכל מה שאינו קובץ תור: `.tmp`, `.bad` וזרים.
  static _PendingMeta? tryParse(String path) {
    final name = p.basename(path);
    if (!name.endsWith('.json')) return null;
    final parts = name.substring(0, name.length - 5).split('.');
    if (parts.length != 2) return null;
    final stamp = int.tryParse(parts[0]);
    if (stamp == null || parts[1].isEmpty) return null;
    return _PendingMeta(
      stamp: stamp,
      key: parts[1],
      directory: p.dirname(path),
    );
  }
}

class _PendingRead {
  const _PendingRead(this.report, this.idChanges);

  final AppReport report;
  final int idChanges;
}

/// תוצאת הפענוח ב-isolate: ערכים פשוטים בלבד, בלי חריגים לחצות את הגבול.
class _PendingDecoded {
  const _PendingDecoded({this.read, this.error, this.missing = false});

  final _PendingRead? read;
  final String? error;
  final bool missing;
}

_PendingDecoded _decodePendingFile(String path, bool withAttachments) {
  try {
    final file = File(path);
    if (!file.existsSync()) return const _PendingDecoded(missing: true);
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map || json['report'] is! Map) {
      throw const FormatException('not a pending report');
    }
    var report = AppReport.fromJson(
      Map<String, dynamic>.from(json['report'] as Map),
    );
    if (!withAttachments) report = report.withoutAttachments();
    final changes = json['idChanges'];
    return _PendingDecoded(
      read: _PendingRead(report, changes is int ? changes : 0),
    );
  } on FileSystemException {
    return const _PendingDecoded(missing: true);
  } catch (error) {
    return _PendingDecoded(error: '$path: $error');
  }
}

enum _FlushStep { sent, skipped, dropped, transient }

class _SentHistory {
  _SentHistory(this.total, this.reports);

  int total;

  /// מהישן לחדש, כמו בקובץ.
  final List<AppReport> reports;
}

enum _AttemptKind { success, transient, permanent, idConflict }

class _Attempt {
  const _Attempt(
    this.kind, {
    this.httpStatus,
    this.rejectedField,
    this.issueNumber,
    this.issueUrl,
    this.merged = false,
    this.duplicate = false,
    this.issuePending = false,
  });

  final _AttemptKind kind;
  final int? httpStatus;
  final String? rejectedField;
  final int? issueNumber;
  final String? issueUrl;
  final bool merged;
  final bool duplicate;
  final bool issuePending;
}
