import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/error_reports_controller.dart';
import '../services/notices_seen_store.dart';
import '../widgets/widgets_exports.dart';

Future<bool> showErrorReportsIntroOnce(
  BuildContext context,
  NoticesSeenStore store, {
  bool readOnly = false,
  bool driveFull = false,
  Future<bool> Function()? waitUntilFree,
}) async {
  if (await store.hasSeen(NoticesSeenStore.errorReportsIntro)) return false;
  if (waitUntilFree != null && !await waitUntilFree()) return false;
  if (!context.mounted) return false;

  final t = context.strings.errorReports;
  await showSingleActionDialog(
    context: context,
    title: t.introDialogTitle,
    content: !readOnly
        ? t.introDialogContent
        : driveFull
            ? t.introDialogContentReadOnlyDriveFull
            : t.introDialogContentReadOnly,
    confirmText: t.introDialogConfirm,
  );
  await store.markSeen(NoticesSeenStore.errorReportsIntro);
  return true;
}

enum ReportOfferOutcome { notOffered, declined, otzariaOpened, collected }

Future<ReportOfferOutcome> offerErrorReportCollection(
  BuildContext context,
  ErrorReportsController controller, {
  bool readOnly = false,
  required Future<bool> Function() isOtzariaRunning,
  NoticesSeenStore? notices,
}) async {
  if (readOnly) return ReportOfferOutcome.notOffered;
  if (await isOtzariaRunning()) return ReportOfferOutcome.notOffered;
  final count = await controller.pendingToOffer();
  if (!context.mounted) return ReportOfferOutcome.notOffered;
  final t = context.strings.errorReports;
  const legacyKey = NoticesSeenStore.legacyReportsNotice;
  if (controller.unmigratedLegacy.isNotEmpty &&
      notices != null &&
      !await notices.hasSeen(legacyKey) &&
      context.mounted) {
    await showSingleActionDialog(
      context: context,
      title: t.legacyReportsDialogTitle,
      content: t.legacyReportsDialogContent,
      confirmText: t.introDialogConfirm,
    );
    await notices.markSeen(legacyKey);
    if (!context.mounted) return ReportOfferOutcome.notOffered;
  }
  if (count <= 0) return ReportOfferOutcome.notOffered;

  final approved = await showTwoActionsDialog(
    context: context,
    title: t.collectDialogTitle,
    content: t.collectDialogContent(count),
    cancelText: t.collectLater,
    confirmText: t.collectConfirm,
  );
  if (!approved) {
    controller.markDeclined(count);
    return ReportOfferOutcome.declined;
  }

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
