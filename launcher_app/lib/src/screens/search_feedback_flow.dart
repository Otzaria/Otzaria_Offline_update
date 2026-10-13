import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/search_feedback_controller.dart';
import '../services/app_logger.dart';
import '../widgets/widgets_exports.dart';

Future<void> offerSearchFeedbackCollection(
  BuildContext context,
  SearchFeedbackController controller, {
  bool readOnly = false,
}) async {
  if (readOnly) return;
  try {
    final count = await controller.pendingToOffer();
    if (count <= 0 || !context.mounted) return;
    final t = context.strings.libraryDomain;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.semanticFeedbackCollectTitle,
      content: t.semanticFeedbackCollectBody(count),
      confirmText: context.strings.errorReports.collectConfirm,
      cancelText: context.strings.errorReports.collectLater,
    );
    if (!approved) {
      controller.markDeclined(count);
      return;
    }
    final collected = await controller.collect();
    if (collected > 0) {
      UiSnack.showSuccess(
        AppL10n.strings.libraryDomain.semanticFeedbackCollected(collected),
      );
    } else {
      UiSnack.show(AppL10n.strings.libraryDomain.semanticFeedbackNotCollected);
    }
  } catch (error) {
    AppLogger.maybeInstance?.error('איסוף משוב החיפוש נכשל', error);
    UiSnack.showError(AppL10n.strings.libraryDomain.semanticFeedbackFailed);
  }
}
