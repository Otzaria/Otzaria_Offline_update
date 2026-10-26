import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/error_reports_controller.dart';
import '../widgets/ui_snack.dart';

enum DriveCollectOutcome {
  /// כונן מוגן — אין לאן לאסוף.
  blocked,
  otzariaOpen,

  /// באוצריא יש סוג שהגילוי בדף לא הציג — סופרים מחדש, ולוחצים שוב.
  disclosureStale,
  nothing,
  collected,
}

/// "איסוף לכונן" מדף הדיווחים. הלחיצה היא האישור, ולכן אוספים רק מה שהגילוי
/// שמעל הכפתור הציג: [disclosedReports].
Future<DriveCollectOutcome> collectReportsToDrive(
  ErrorReportsController controller, {
  bool readOnly = false,
  required Future<bool> Function() isOtzariaRunning,
  required int disclosedReports,
}) async {
  if (readOnly) return DriveCollectOutcome.blocked;
  final s = AppL10n.strings.errorReports;
  if (await isOtzariaRunning()) {
    UiSnack.show(s.collectOtzariaOpenSnack);
    return DriveCollectOutcome.otzariaOpen;
  }
  final count = await controller.pendingToOffer();
  if (count > 0 && disclosedReports <= 0) {
    UiSnack.show(s.collectDisclosureRefreshedSnack);
    return DriveCollectOutcome.disclosureStale;
  }
  if (count <= 0) return DriveCollectOutcome.nothing;
  if (await isOtzariaRunning()) {
    UiSnack.show(s.collectOtzariaOpenSnack);
    return DriveCollectOutcome.otzariaOpen;
  }

  final outcome = await controller.collect();
  final error = outcome.error;
  if (error == null) {
    UiSnack.showSuccess(s.collectedSnack(outcome.collected));
  } else {
    UiSnack.showError(outcome.collected > 0
        ? s.collectPartialSnack(outcome.collected, error)
        : s.collectFailedSnack(error));
  }
  return DriveCollectOutcome.collected;
}
