import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      // כתובת אסורה אינה בקשה לשרת — ולכן אינה ממתינה לחלון ואינה נספרת בו.
      if (!item.isAllowedEndpoint) {
        await _removeQuietly(outbox, item);
        rejected++;
        final reason = 'endpoint not allowed: ${item.endpoint}';
        rejections.add(_rejection(item, reason));
        report(null);
        continue;
      }

      var retries = 0;
      while (true) {
        if (!await _waitForWindow(report, cancellation)) {
          return finish(cancelled: true);
        }
        report(null);

        final _Attempt? attempt;
        try {
          attempt = await raceCancellation(_post(item), cancellation);
        } on TimeoutException {
          _requestFinished();
          return finish(
              error: AppL10n.strings.errorReportsDomain.uploadTimedOut);
        } on Object catch (e) {
          _requestFinished();
          return finish(
            error: AppL10n.strings.errorReportsDomain.uploadNetworkError(
              e is SocketException ? e.message : '$e',
            ),
          );
        }
        _requestFinished();
        // נעצר באמצע בקשה: הקובץ נשאר, ושליחה חוזרת תחזור `duplicate`.
        if (attempt == null) return finish(cancelled: true);

        final status = attempt.statusCode;
        if (status == 429 && retries < maxRateLimitRetries) {
          // השרת אומר "יותר מדי" — חלון שלם של המתנה, ואז אותו דיווח שוב.
          retries++;
          _windowCount = batchSize;
          continue;
        }
        if (status >= 200 && status < 300) {
          await _removeQuietly(outbox, item);
          sent++;
        } else if (_rejectStatuses.contains(status)) {
          await _removeQuietly(outbox, item);
          rejected++;
          rejections.add(_rejection(item, '$status ${attempt.excerpt}'));
        } else {
          return finish(
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

  Future<_Attempt> _post(OutboxReport report) async {
    final response = await _http
        .post(report.endpoint, headers: _headers, body: jsonEncode(report.body))
        .timeout(requestTimeout);
    final body = response.body;
    return _Attempt(
      response.statusCode,
      body.length > 200 ? body.substring(0, 200) : body,
    );
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
  const _Attempt(this.statusCode, this.excerpt);

  final int statusCode;
  final String excerpt;
}
