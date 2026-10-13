import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/error_reports_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../services/app_logger.dart';
import '../widgets/widgets_exports.dart';

Future<bool> _confirmUploads(
  BuildContext context, {
  required ErrorReportsController? errorReports,
  required int reportCount,
  required int feedbackCount,
}) async {
  if (errorReports != null && reportCount > errorReports.batchSize) {
    final t = context.strings.errorReports;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.uploadLongDialogTitle,
      content: t.uploadLongDialogContent(
        reportCount,
        errorReports.batchSize,
        errorReports.estimateMinutes(reportCount),
      ),
      confirmText: t.uploadLongDialogConfirm,
    );
    if (!approved || !context.mounted) return false;
  }
  if (feedbackCount > 0) {
    final t = context.strings.libraryDomain;
    return showTwoActionsDialog(
      context: context,
      title: t.semanticFeedbackUploadTitle,
      content: t.semanticFeedbackUploadBody(feedbackCount),
      confirmText: t.semanticFeedbackUploadAction,
    );
  }
  return true;
}

enum ReportsUploadSeverity { error, info, success }

class ReportsUploadOutcome {
  const ReportsUploadOutcome(this.message, this.severity);

  final String message;
  final ReportsUploadSeverity severity;

  void show() => switch (severity) {
        ReportsUploadSeverity.error => UiSnack.showError(message),
        ReportsUploadSeverity.info => UiSnack.show(message),
        ReportsUploadSeverity.success => UiSnack.showSuccess(message),
      };
}

Future<ReportsUploadOutcome?> uploadAllReports(
  BuildContext context, {
  ErrorReportsController? errorReports,
  SearchFeedbackController? searchFeedback,
  void Function(bool active)? onActiveChanged,
  void Function(bool uploading)? onUploadingChanged,
  bool Function()? isCancelled,
}) async {
  if ((errorReports?.isUploading ?? false) ||
      (searchFeedback?.isUploading ?? false)) {
    return null;
  }
  if ((errorReports?.isCollecting ?? false) ||
      (searchFeedback?.isCollecting ?? false)) {
    UiSnack.show(AppL10n.strings.errorReports.uploadCollectingBusy);
    return null;
  }
  var announced = false;
  onActiveChanged?.call(true);
  try {
    await searchFeedback?.refreshOutbox();
    final reportCount = errorReports?.outboxCount ?? 0;
    final feedbackCount = searchFeedback?.outboxCount ?? 0;
    if (reportCount + feedbackCount <= 0 || !context.mounted) return null;
    if (!await _confirmUploads(
      context,
      errorReports: errorReports,
      reportCount: reportCount,
      feedbackCount: feedbackCount,
    )) {
      return null;
    }

    onUploadingChanged?.call(true);
    announced = true;
    final lines = <String>[];
    var failed = false;
    var remaining = 0;
    final s = AppL10n.strings.errorReports;
    final libraryStrings = AppL10n.strings.libraryDomain;

    var reportsHalted = false;
    if (errorReports != null && reportCount > 0) {
      final result = await errorReports.upload();
      if (result == null) {
        lines.add(s.uploadCollectingBusy);
        remaining += reportCount;
        reportsHalted = true;
      } else {
        final error = result.error;
        if (error != null) lines.add(s.uploadFailedSnack(error));
        if (error == null || result.total > 0) {
          lines.add(
            s.uploadSummary(result.sent, result.rejected, result.remaining),
          );
        }
        failed = error != null;
        remaining += result.remaining;
        reportsHalted = result.cancelled || failed;
      }
    }

    if (searchFeedback != null &&
        feedbackCount > 0 &&
        !reportsHalted &&
        !(isCancelled?.call() ?? false)) {
      try {
        final result = await searchFeedback.upload();
        if (result == null) {
          lines.add(s.uploadCollectingBusy);
          remaining += feedbackCount;
        } else {
          lines.add(
            libraryStrings.semanticFeedbackUploaded(
              result.sent,
              result.remaining,
            ),
          );
          remaining += result.remaining;
        }
      } catch (error) {
        AppLogger.maybeInstance?.error('העלאת משוב החיפוש נכשלה', error);
        lines.add(libraryStrings.semanticFeedbackFailed);
        failed = true;
      }
    } else if (searchFeedback != null && feedbackCount > 0) {
      lines.add(libraryStrings.semanticFeedbackUploaded(0, feedbackCount));
      remaining += feedbackCount;
    }

    if (lines.isEmpty) return null;
    final outcome = ReportsUploadOutcome(
      lines.join('\n'),
      failed
          ? ReportsUploadSeverity.error
          : remaining > 0
              ? ReportsUploadSeverity.info
              : ReportsUploadSeverity.success,
    );
    outcome.show();
    return outcome;
  } catch (error) {
    AppLogger.maybeInstance?.error('העלאת הדיווחים נכשלה', error);
    final outcome = ReportsUploadOutcome(
      AppL10n.strings.errorReports.uploadUnexpectedFailure,
      ReportsUploadSeverity.error,
    );
    outcome.show();
    return outcome;
  } finally {
    if (announced) onUploadingChanged?.call(false);
    onActiveChanged?.call(false);
  }
}
