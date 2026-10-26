import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/native_file_dialogs.dart';
import '../../widgets/widgets_exports.dart';

/// ההתקנה של תוכנה נוספת, על כל מה שנלווה אליה: שאלת יעד ההעתקה לקובץ
/// נייד, וההודעות שאחריה.
///
/// יושבת כאן ולא בכרטיס כי שני מקומות מריצים אותה — הכרטיס שבמסך והחלון
/// הקופץ של "ממתינות על הכונן". מחזירה האם התקנה אכן רצה והצליחה.
Future<bool> installCustomApp({
  required BuildContext context,
  required CustomAppsController controller,
  required CustomAppView app,
}) async {
  final t = context.strings.customApps;

  // כשהקובץ הוא התוכנה עצמה אין מה להתקין — רק להעתיק, והמשתמש הוא זה
  // שיודע לאן. ביטול הבחירה אינו שגיאה: פשוט לא קורה כלום.
  if (!await _confirmTrust(context, controller, app)) return false;

  String? copyToDir;
  if (app.descriptor.portableFile) {
    copyToDir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickCopyTargetDialogTitle,
    );
    if (copyToDir == null) return false;
  }

  final result = await controller.install(
    app.descriptor.id,
    copyToDir: copyToDir,
  );
  if (!result.ok) {
    UiSnack.showFailure(controller.errorMessage);
    return false;
  }

  final strings = AppL10n.strings.customApps;
  // שום דבר לא הותקן — הקובץ רק הועתק, וצריך לומר לאן.
  if (result.copiedPath case final path?) {
    UiSnack.showSuccess(
      app.descriptor.portableFile
          ? strings.copiedFileSnack(path)
          : strings.archiveInDownloadsSnack(path),
    );
    return true;
  }
  UiSnack.showSuccess(strings.installedSnack(app.descriptor.name));
  // מה שנלמד נאמר במפורש: מכאן והלאה הכרטיס יפסיק לומר "לא ניתן לזהות",
  // וזה שינוי שהמשתמש כדאי שיבין מאיפה בא.
  if (result.learnedExeName case final exeName?) {
    UiSnack.show(strings.learnedDetectionSnack(exeName));
  }
  return true;
}

/// רשומה שלא אושרה במחשב הזה מאושרת קודם — המנהל מסרב להפעיל אותה.
Future<bool> launchCustomApp({
  required BuildContext context,
  required CustomAppsController controller,
  required CustomAppView app,
}) async {
  final installed = app.installed;
  if (installed == null) return false;
  final id = app.descriptor.id;
  final needsTrust = await controller.launchNeedsTrust(id);
  if (needsTrust == null) {
    UiSnack.showFailure(controller.errorMessage);
    return false;
  }
  if (needsTrust) {
    if (!context.mounted) return false;
    final approved = await showCustomAppTrustDialog(context, app);
    if (!approved || !await controller.trustHere(id)) return false;
  }
  return controller.launch(id, installed);
}

/// תוכן שלא אושר במחשב הזה, או קובץ בלי sha256 שמור, מאושר כאן קודם —
/// אחרת המנהל מסרב להריץ אותו. אישור של קובץ בלי sha256 מאשר גם את התוכן.
Future<bool> _confirmTrust(
  BuildContext context,
  CustomAppsController controller,
  CustomAppView app,
) async {
  final t = context.strings.customApps;
  final id = app.descriptor.id;
  final preflight = await controller.installPreflight(id);
  if (preflight == null) {
    UiSnack.showFailure(controller.errorMessage);
    return false;
  }
  if (preflight.needsHash) {
    if (!context.mounted) return false;
    final approved = await showWarningDialog(
      context: context,
      title: t.unverifiedDialogTitle,
      content: t.unverifiedDialogContent(app.storedInstaller?.fileName ?? ''),
      confirmText: t.unverifiedDialogConfirm,
    );
    if (!approved) return false;
    if (!await controller.recordInstallerHash(id)) {
      UiSnack.showFailure(controller.errorMessage);
      return false;
    }
  } else if (preflight.needsTrust) {
    if (!context.mounted) return false;
    final approved = await showCustomAppTrustDialog(context, app);
    if (!approved || !await controller.trustHere(id)) return false;
  }
  return context.mounted;
}

/// "להתקין תוכנה שלא נבדקה?" — תוכנה שנוספה במחשב אחר. הבטוח (ביטול) ראשי.
Future<bool> showCustomAppTrustDialog(BuildContext context, CustomAppView app) {
  final t = context.strings.customApps;
  return showWarningDialog(
    context: context,
    title: t.trustDialogTitle,
    content: t.trustDialogContent(
      app.descriptor.name,
      app.descriptor.github?.webUrl ?? app.descriptor.name,
    ),
    confirmText: t.trustDialogConfirm,
  );
}
