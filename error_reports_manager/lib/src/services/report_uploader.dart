import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/outbox_report.dart';
import '../models/upload_result.dart';
import 'report_outbox.dart';

/// המתנה מוזרקת — בבדיקות היא מיידית או נשלטת.
typedef ReportDelay = Future<void> Function(Duration duration);

/// שולח את תיבת היציאה לשרת של אוצריא — הפעולה היחידה בחבילה שנוגעת ברשת.
/// השרת מקבל [batchSize] דיווחים לדקה, ולכן בין מנה למנה ממתינים [batchInterval].
class ErrorReportUploader {
  ErrorReportUploader({
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 30),
    this.requestTimeoutWithImages = const Duration(minutes: 2),
    this.batchSize = 8,
    this.batchInterval = const Duration(seconds: 65),
    this.maxRateLimitRetries = 3,
    ReportDelay? delay,
    DateTime Function()? clock,
  })  : _http = httpClient ?? http.Client(),
        _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final http.Client _http;
  final ReportDelay _delay;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  final Duration requestTimeoutWithImages;
  final int batchSize;
  final Duration batchInterval;

  /// כמה פעמים מנסים שוב אותו דיווח אחרי 429 לפני שעוצרים את הריצה.
  final int maxRateLimitRetries;

  /// בקשות בחלון, ומתי הסתיימה האחרונה — ממנה נמדד החלון הבא (בקשה איטית לא
  /// מקצרת אותו). נשמר במופע, כך שהמשך מיד אחרי עצירה עדיין ממתין.
  int _windowCount = 0;
  DateTime? _lastRequestEnd;

  static const _rejectStatuses = {400, 409, 413, 422};
  static const _headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
    'User-Agent': 'otzaria-launcher',
  };

  /// כמה דקות תיקח העלאה של [count] דיווחים — לדיאלוג שלפני ההתחלה.
  int estimateMinutes(int count) {
    if (count <= batchSize) return 1;
    final waits = (count - 1) ~/ batchSize;
    final seconds = waits * batchInterval.inSeconds;
    return (seconds / 60).ceil().clamp(1, 1 << 30);
  }

  /// סוגר את ה-`http.Client`. אחרי זה המופע אינו שמיש.
  void close() => _http.close();

  Future<ReportUploadResult> upload(
    ReportOutbox outbox, {
    void Function(ReportUploadProgress progress)? onProgress,
    ReportUploadCancellation? cancellation,
  }) async {
    final reports = await outbox.list();
    final total = reports.length;
    var sent = 0;
    var rejected = 0;
    final rejections = <ReportRejection>[];

    ReportUploadResult finish({String? error, bool cancelled = false}) =>
        ReportUploadResult(
          total: total,
          sent: sent,
          rejected: rejected,
          remaining: total - sent - rejected,
          rejections: rejections,
          error: error,
          cancelled: cancelled,
        );

    void report(Duration? wait) => onProgress?.call(ReportUploadProgress(
          total: total,
          done: sent + rejected,
          waitRemaining: wait,
        ));

    for (final item in reports) {
      var bodyChanged = false;
      Future<ReportUploadResult> stop({
        String? error,
        bool cancelled = false,
      }) async {
        if (bodyChanged) await _rewriteWithoutMinidump(outbox, item);
        return finish(error: error, cancelled: cancelled);
      }
      if (!item.isAllowedEndpoint) {
        await _removeQuietly(outbox, item);
        rejected++;
        final reason = 'endpoint not allowed: ${item.endpoint}';
        rejections.add(_rejection(item, reason));
        report(null);
        continue;
      }

      Uint8List body;
      try {
        body = await outbox.requestBody(item);
      } on Object catch (e) {
        return finish(
          error: AppL10n.strings.errorReportsDomain.outboxUnreadable('$e'),
        );
      }

      var retries = 0;
      while (true) {
        if (!await _waitForWindow(report, cancellation)) {
          return stop(cancelled: true);
        }
        report(null);

        final _Attempt? attempt;
        final abort = Completer<void>();
        try {
          attempt = await raceCancellation(
            _post(item, body, abort),
            cancellation,
            abort: abort,
          );
        } on TimeoutException {
          _requestFinished();
          return stop(error: AppL10n.strings.errorReportsDomain.uploadTimedOut);
        } on Object catch (e) {
          _requestFinished();
          return stop(
            error: AppL10n.strings.errorReportsDomain.uploadNetworkError(
              e is SocketException ? e.message : '$e',
            ),
          );
        }
        _requestFinished();
        if (attempt == null) return stop(cancelled: true);

        final status = attempt.statusCode;
        if (status == 429 && retries < maxRateLimitRetries) {
          retries++;
          _windowCount = batchSize;
          continue;
        }
        if (_minidumpRejection(attempt)) {
          final withoutMinidump = _withoutMinidump(body);
          if (withoutMinidump != null) {
            body = withoutMinidump;
            bodyChanged = true;
            continue;
          }
        }
        if (status >= 200 && status < 300 && attempt.accepted) {
          await _removeQuietly(outbox, item);
          sent++;
        } else if (_rejectStatuses.contains(status)) {
          await _removeQuietly(outbox, item);
          rejected++;
          rejections.add(_rejection(item, '$status ${attempt.excerpt}'));
        } else {
          return stop(
            error: AppL10n.strings.errorReportsDomain.uploadHttpStatus(status),
          );
        }
        break;
      }
    }
    report(null);
    return finish();
  }

  void _requestFinished() {
    _windowCount++;
    _lastRequestEnd = _clock();
  }

  /// ממתין אם החלון מלא. `false` = נעצר בזמן ההמתנה.
  Future<bool> _waitForWindow(
    void Function(Duration? wait) report,
    ReportUploadCancellation? cancellation,
  ) async {
    if (cancellation?.isCancelled ?? false) return false;
    final last = _lastRequestEnd;
    if (last == null) return true;
    final opensAt = last.add(batchInterval);
    // שקט של חלון שלם מאפס את המונה גם בלי המתנה.
    if (!_clock().isBefore(opensAt)) {
      _windowCount = 0;
      return true;
    }
    if (_windowCount < batchSize) return true;

    // המתנה בצעדים של שנייה — כך הספירה לאחור מתעדכנת במסך.
    while (true) {
      final remaining = opensAt.difference(_clock());
      if (remaining <= Duration.zero) break;
      report(remaining);
      const second = Duration(seconds: 1);
      final step = remaining < second ? remaining : second;
      final waited = await raceCancellation(
        _delay(step).then((_) => true),
        cancellation,
      );
      if (waited == null) return false;
    }
    _windowCount = 0;
    return true;
  }

  Future<_Attempt> _post(
    OutboxReport report,
    Uint8List body,
    Completer<void> abort,
  ) async {
    final timeout = report.endpoint.path == '/api/app-reports' &&
            (report.hasImages || report.hasMinidump)
        ? requestTimeoutWithImages
        : requestTimeout;
    final request = http.AbortableRequest(
      'POST',
      report.endpoint,
      abortTrigger: abort.future,
    )
      ..headers.addAll(_headers)
      ..bodyBytes = body;
    final http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    }
    final responseBody = response.body;
    final status = response.statusCode;
    return _Attempt(
      status,
      responseBody.length > 200
          ? responseBody.substring(0, 200)
          : responseBody,
      accepted: _isProtocolSuccess(responseBody),
      rejectedField: status == 422 ? _rejectedField(responseBody) : null,
    );
  }

  static bool _isProtocolSuccess(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map && json['success'] == true;
    } on FormatException {
      return false;
    }
  }

  static bool _minidumpRejection(_Attempt attempt) =>
      attempt.statusCode == 413 ||
      (attempt.statusCode == 422 &&
          attempt.rejectedField == 'attachments.minidump');

  static Uint8List? _withoutMinidump(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return null;
    final attachments = decoded['attachments'];
    if (attachments is! Map || attachments['minidump'] == null) return null;
    final updatedAttachments = Map<String, dynamic>.from(attachments)
      ..remove('minidump');
    final updated = Map<String, dynamic>.of(decoded);
    if (updatedAttachments.isEmpty) {
      updated.remove('attachments');
    } else {
      updated['attachments'] = updatedAttachments;
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(updated)));
  }

  static Future<void> _rewriteWithoutMinidump(
    ReportOutbox outbox,
    OutboxReport report,
  ) async {
    try {
      final file = File(report.filePath);
      final decodedFile = jsonDecode(await file.readAsString());
      if (decodedFile is! Map<String, dynamic>) return;
      final queuedBody = decodedFile['body'];
      if (queuedBody is! Map<String, dynamic>) return;
      final attachments = queuedBody['attachments'];
      if (attachments is! Map || attachments['minidump'] == null) return;
      final updatedAttachments = Map<String, dynamic>.from(attachments)
        ..remove('minidump');
      if (updatedAttachments.isEmpty) {
        queuedBody.remove('attachments');
      } else {
        queuedBody['attachments'] = updatedAttachments;
      }
      await outbox.write(
        report.reportId,
        Uint8List.fromList(utf8.encode(jsonEncode(decodedFile))),
      );
    } catch (_) {
      return;
    }
  }

  static String? _rejectedField(String body) {
    try {
      final decoded = jsonDecode(body);
      final field = decoded is Map ? decoded['field'] : null;
      return field is String ? field : null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> _removeQuietly(
    ReportOutbox outbox,
    OutboxReport report,
  ) async {
    try {
      await outbox.remove(report);
    } catch (_) {
      // קובץ נעול יישלח שוב בפעם הבאה, והשרת יענה `duplicate`.
    }
  }

  static ReportRejection _rejection(OutboxReport report, String reason) =>
      ReportRejection(
        reportId: report.reportId,
        bookTitle: report.bookTitle,
        reason: reason,
      );
}

class _Attempt {
  const _Attempt(this.statusCode, this.excerpt,
      {required this.accepted, this.rejectedField});

  final int statusCode;
  final String excerpt;
  final bool accepted;
  final String? rejectedField;
}
