import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/search_feedback_controller.dart';
import '../services/app_logger.dart';
import '../widgets/widgets_exports.dart';

/// אוסף רק אחרי אישור המשתמש; בקר האיסוף בודק מחדש הסכמה ותהליך פעיל.
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
    if (!approved) return;
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

/// גם לחיצה על הורדת הספרייה דורשת אישור נפרד לשליחת נתוני האימון.
Future<SearchFeedbackUploadResult?> uploadSearchFeedback(
  BuildContext context,
  SearchFeedbackController controller, {
  bool readOnly = false,
}) async {
  if (readOnly || controller.isUploading) return null;
  try {
    await controller.refreshOutbox();
    final count = controller.outboxCount;
    if (count <= 0 || !context.mounted) return null;
    final t = context.strings.libraryDomain;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.semanticFeedbackUploadTitle,
      content: t.semanticFeedbackUploadBody(count),
      confirmText: t.semanticFeedbackUploadAction,
    );
    if (!approved) return null;
    final result = await controller.upload();
    if (result != null) {
      UiSnack.show(AppL10n.strings.libraryDomain
          .semanticFeedbackUploaded(result.sent, result.remaining));
    }
    return result;
  } catch (error) {
    AppLogger.maybeInstance?.error('העלאת משוב החיפוש נכשלה', error);
    UiSnack.showError(AppL10n.strings.libraryDomain.semanticFeedbackFailed);
    return null;
  }
}
