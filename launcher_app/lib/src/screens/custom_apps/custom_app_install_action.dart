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
    UiSnack.showError(controller.errorMessage ?? '');
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
