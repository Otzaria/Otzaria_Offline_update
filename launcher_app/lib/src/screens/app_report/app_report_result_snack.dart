import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../widgets/widgets_exports.dart';

/// הודעת הסיום של שליחת דיווח — משותפת לטופס, להצעה אחרי קריסה ולניהול.
void showAppReportResultSnack(AppReportDeliveryResult result) {
  final t = AppL10n.strings.appReports;
  switch (result.status) {
    case AppReportDeliveryStatus.sent:
      UiSnack.showSuccess(
        result.merged
            ? t.mergedSnack(result.issueNumber)
            : t.sentSnack(result.issueNumber),
      );
    case AppReportDeliveryStatus.queued:
      UiSnack.show(t.queuedSnack);
    case AppReportDeliveryStatus.failed:
      if (result.failureReason == AppReportFailureReason.notPending) {
        UiSnack.show(t.notPendingSnack);
      } else {
        UiSnack.showError(t.rejectedSnack(result.rejectedField));
      }
  }
}

/// הודעת הכישלון של בדיקת התקינות המקומית, לפי השדה שהוחזר מ-`validate`.
String appReportInvalidFieldMessage(String field, {required bool emailEmpty}) {
  final t = AppL10n.strings.appReports;
  return switch (field) {
    'title' => t.titleRequiredSnack,
    'description' => t.descriptionRequiredSnack,
    'reporterEmail' => emailEmpty ? t.emailRequiredSnack : t.invalidEmailSnack,
    _ => t.sendFailedSnack,
  };
}

/// תוויות סוגי הדיווח.
String appReportTypeLabel(AppReportsStrings t, AppReportType type) =>
    switch (type) {
      AppReportType.bug => t.typeBug,
      AppReportType.crash => t.typeCrash,
      AppReportType.performance => t.typePerformance,
      AppReportType.suggestion => t.typeSuggestion,
    };
