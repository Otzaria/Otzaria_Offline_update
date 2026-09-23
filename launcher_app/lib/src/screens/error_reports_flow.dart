import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/error_reports_controller.dart';
import '../widgets/widgets_exports.dart';

/// מה קרה להצעה לאסוף — בעיקר לבדיקות.
enum ReportOfferOutcome { notOffered, declined, otzariaOpened, collected }

/// "נמצאו N דיווחים — לאסוף?", פעם אחת בהרצה; לא בכונן לקריאה בלבד, ולא כשאוצריא
/// פתוחה — [isOtzariaRunning] נבדק שוב אחרי האישור, כי הדיאלוג עשוי לחכות.
Future<ReportOfferOutcome> offerErrorReportCollection(
  BuildContext context,
  ErrorReportsController controller, {
  bool readOnly = false,
  required Future<bool> Function() isOtzariaRunning,
}) async {
  if (readOnly) return ReportOfferOutcome.notOffered;
  // לפני `pendingToOffer`: אוצריא פתוחה אינה "מנצלת" את ההצעה של ההרצה.
  if (await isOtzariaRunning()) return ReportOfferOutcome.notOffered;
  final count = await controller.pendingToOffer();
  if (count <= 0 || !context.mounted) return ReportOfferOutcome.notOffered;

  final t = context.strings.errorReports;
  final approved = await showTwoActionsDialog(
    context: context,
    title: t.collectDialogTitle,
    content: t.collectDialogContent(count),
    cancelText: t.collectLater,
    confirmText: t.collectConfirm,
  );
  if (!approved) return ReportOfferOutcome.declined;

  final s = AppL10n.strings.errorReports;
  if (await isOtzariaRunning()) {
    UiSnack.show(s.collectOtzariaOpenSnack);
    return ReportOfferOutcome.otzariaOpened;
  }

  final outcome = await controller.collect();
  final error = outcome.error;
  if (error == null) {
    UiSnack.showSuccess(s.collectedSnack(outcome.collected));
  } else if (outcome.collected > 0) {
    UiSnack.show(s.collectPartialSnack(outcome.collected, error));
  } else {
    UiSnack.showError(s.collectFailedSnack(error));
  }
  return ReportOfferOutcome.collected;
}

/// הכפתור בכרטיס ההורדות. מעל מנה אחת מסבירים קודם כמה זמן זה ייקח.
Future<ReportUploadResult?> uploadErrorReports(
  BuildContext context,
  ErrorReportsController controller,
) async {
  final count = controller.outboxCount;
  if (count <= 0 || controller.isUploading) return null;

  if (count > controller.batchSize) {
    final t = context.strings.errorReports;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.uploadLongDialogTitle,
      content: t.uploadLongDialogContent(
        count,
        controller.batchSize,
        controller.estimateMinutes(count),
      ),
      confirmText: t.uploadLongDialogConfirm,
    );
    if (!approved) return null;
  }

  final result = await controller.upload();
  if (result == null) return null;
  final s = AppL10n.strings.errorReports;
  final summary =
      s.uploadSummary(result.sent, result.rejected, result.remaining);
  final error = result.error;
  if (error != null && result.total == 0) {
    UiSnack.showError(s.uploadFailedSnack(error));
  } else if (error != null) {
    UiSnack.showError('${s.uploadFailedSnack(error)}\n$summary');
  } else if (result.remaining > 0) {
    UiSnack.show(summary);
  } else {
    UiSnack.showSuccess(summary);
  }
  return result;
}
