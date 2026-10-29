import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/outbox_report.dart';
import '../models/upload_result.dart';
import '../port/app_report.dart';
import 'report_outbox.dart';

typedef ReportDelay = Future<void> Function(Duration duration);

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

  final int maxRateLimitRetries;

  final Map<String, int> _unconfirmed = {};
  final Map<String, int> _unconfirmedStatus = {};
  final Map<String, DateTime> _unconfirmedUntil = {};

  static const maxUnconfirmedAnswers = 3;

  int _windowCount = 0;
  DateTime? _lastRequestEnd;

  static const _rejectStatuses = {400, 409, 413, 422};
  static const _headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
    'User-Agent': 'otzaria-launcher',
  };

  int estimateMinutes(int count) {
    if (count <= batchSize) return 1;
    final waits = (count - 1) ~/ batchSize;
    final seconds = waits * batchInterval.inSeconds;
    return (seconds / 60).ceil().clamp(1, 1 << 30);
  }

  void close() => _http.close();

  Future<ReportUploadResult> upload(
    ReportOutbox outbox, {
    void Function(ReportUploadProgress progress)? onProgress,
    ReportUploadCancellation? cancellation,
    bool Function(OutboxReport report)? where,
  }) async {
    final reports = (await outbox.list())
        .where((report) => where?.call(report) ?? true)
        .toList();
    final total = reports.length;
    var sent = 0;
    var rejected = 0;
    final rejections = <ReportRejection>[];
    int? stuckStatus;

    ReportUploadResult finish({String? error, bool cancelled = false}) =>
        ReportUploadResult(
          total: total,
          sent: sent,
          rejected: rejected,
          remaining: total - sent - rejected,
          rejections: rejections,
          error: error ??
              (stuckStatus == null
                  ? null
                  : AppL10n.strings.errorReportsDomain
                      .uploadHttpStatus(stuckStatus)),
          cancelled: cancelled,
        );

    void report(Duration? wait) => onProgress?.call(ReportUploadProgress(
          total: total,
          done: sent + rejected,
          waitRemaining: wait,
        ));

    for (var item in reports) {
      if ((_unconfirmed[item.reportId] ?? 0) >= maxUnconfirmedAnswers &&
          _clock().isBefore(_unconfirmedUntil[item.reportId]!)) {
        stuckStatus = _unconfirmedStatus[item.reportId];
        report(null);
        continue;
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

      Map<String, dynamic>? strippedBody;
      Future<ReportUploadResult> stop({
        String? error,
        bool cancelled = false,
      }) async {
        final stripped = strippedBody;
        if (stripped != null) {
          await _rewriteWithoutMinidump(outbox, item, stripped);
        }
        return finish(error: error, cancelled: cancelled);
      }

      var retries = 0;
      var renewedId = false;
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
          final sentBody = body;
          final stripped = await Isolate.run(() {
            final withoutMinidump = _withoutMinidump(sentBody);
            return withoutMinidump == null
                ? null
                : (
                    body: withoutMinidump,
                    bytes: Uint8List.fromList(
                      utf8.encode(jsonEncode(withoutMinidump)),
                    ),
                  );
          });
          if (stripped != null) {
            strippedBody = stripped.body;
            body = stripped.bytes;
            continue;
          }
        }
        if (status == 409 && !renewedId) {
          final sentBody = body;
          final conflicted = item;
          final renewed =
              await Isolate.run(() => _withNewReportId(conflicted, sentBody));
          if (renewed != null) {
            try {
              await outbox.write(renewed.report.reportId, renewed.fileBytes);
            } on Object catch (e) {
              return stop(
                error:
                    AppL10n.strings.errorReportsDomain.outboxUnreadable('$e'),
              );
            }
            await _removeQuietly(outbox, item);
            renewedId = true;
            item = renewed.report;
            body = renewed.bodyBytes;
            continue;
          }
        }
        if (status >= 200 && status < 300 && attempt.accepted) {
          _unconfirmed.remove(item.reportId);
          _unconfirmedStatus.remove(item.reportId);
          _unconfirmedUntil.remove(item.reportId);
          await _removeQuietly(outbox, item);
          sent++;
        } else if (_rejectStatuses.contains(status)) {
          await _removeQuietly(outbox, item);
          rejected++;
          rejections.add(_rejection(item, '$status ${attempt.excerpt}'));
        } else if (status >= 200 && status < 300) {
          final strikes = (_unconfirmed[item.reportId] ?? 0) + 1;
          _unconfirmed[item.reportId] = strikes;
          _unconfirmedStatus[item.reportId] = status;
          if (strikes < maxUnconfirmedAnswers) {
            return stop(
              error:
                  AppL10n.strings.errorReportsDomain.uploadHttpStatus(status),
            );
          }
          _unconfirmedUntil[item.reportId] = _clock().add(batchInterval);
          stuckStatus = status;
        } else {
          return stop(
            error: attempt.shabbat
                ? AppL10n.strings.errorReportsDomain.uploadShabbat
                : AppL10n.strings.errorReportsDomain.uploadHttpStatus(status),
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

  Future<bool> _waitForWindow(
    void Function(Duration? wait) report,
    ReportUploadCancellation? cancellation,
  ) async {
    if (cancellation?.isCancelled ?? false) return false;
    final last = _lastRequestEnd;
    if (last == null) return true;
    final opensAt = last.add(batchInterval);
    if (!_clock().isBefore(opensAt)) {
      _windowCount = 0;
      return true;
    }
    if (_windowCount < batchSize) return true;

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
      responseBody.length > 200 ? responseBody.substring(0, 200) : responseBody,
      accepted: _isProtocolSuccess(responseBody),
      rejectedField: status == 422 ? _rejectedField(responseBody) : null,
      shabbat: status == 503 && _isShabbat(responseBody),
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

  static bool _isShabbat(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map && json['error'] == 'shabbat';
    } on FormatException {
      return false;
    }
  }

  static bool _minidumpRejection(_Attempt attempt) =>
      attempt.statusCode == 413 ||
      (attempt.statusCode == 422 &&
          attempt.rejectedField == 'attachments.minidump');

  static Map<String, dynamic>? _withoutMinidump(Uint8List bytes) {
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
    return updated;
  }

  static Future<void> _rewriteWithoutMinidump(
    ReportOutbox outbox,
    OutboxReport report,
    Map<String, dynamic> body,
  ) async {
    try {
      await outbox.write(
        report.reportId,
        OutboxReport.encodeFile(OutboxReport.fileJson(
          reportId: report.reportId,
          bookTitle: report.bookTitle,
          createdAt: report.createdAt?.toUtc().toIso8601String() ?? '',
          endpoint: report.endpoint.toString(),
          autoUpload: report.autoUpload,
          body: body,
        )),
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

  static ({OutboxReport report, Uint8List fileBytes, Uint8List bodyBytes})?
      _withNewReportId(OutboxReport item, Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return null;
    final isBookReport = decoded.containsKey('report_id');
    final key = isBookReport ? 'report_id' : 'reportId';
    if (decoded[key] is! String) return null;
    final newId = isBookReport
        ? '${DateTime.now().microsecondsSinceEpoch}-${item.reportId.hashCode.abs()}'
        : AppReport.generateReportId();
    final body = Map<String, dynamic>.of(decoded)..[key] = newId;
    final outboxId = '${OutboxReport.idPrefixFor(item.endpoint)}$newId';
    return (
      report: OutboxReport(
        reportId: outboxId,
        endpoint: item.endpoint,
        bookTitle: item.bookTitle,
        createdAt: item.createdAt,
        filePath: p.join(
          p.dirname(item.filePath),
          DirectoryReportOutbox.fileNameFor(outboxId),
        ),
        hasImages: item.hasImages,
        hasMinidump: item.hasMinidump,
        autoUpload: item.autoUpload,
      ),
      fileBytes: OutboxReport.encodeFile(OutboxReport.fileJson(
        reportId: outboxId,
        bookTitle: item.bookTitle,
        createdAt: item.createdAt?.toUtc().toIso8601String() ?? '',
        endpoint: item.endpoint.toString(),
        autoUpload: item.autoUpload,
        body: body,
      )),
      bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );
  }

  static Future<void> _removeQuietly(
    ReportOutbox outbox,
    OutboxReport report,
  ) async {
    try {
      await outbox.remove(report);
    } catch (_) {
      return;
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
      {required this.accepted, this.rejectedField, this.shabbat = false});

  final int statusCode;
  final String excerpt;
  final bool accepted;
  final String? rejectedField;
  final bool shabbat;
}
