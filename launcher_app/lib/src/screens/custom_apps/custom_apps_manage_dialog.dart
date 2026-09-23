import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_form_dialog.dart';
import 'custom_apps_screen.dart';

/// פותח את טופס ההוספה.
Future<void> openAddCustomApp(
  BuildContext context,
  CustomAppsController controller,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => CustomAppFormDialog(controller: controller),
    );

/// פותח את אותו טופס עצמו על רשומה קיימת. אותו טופס בכוונה: מה שאפשר
/// למלא בהוספה חייב להיות גם מה שאפשר לתקן אחריה.
Future<void> openEditCustomApp(
  BuildContext context,
  CustomAppsController controller,
  CustomAppEntry entry,
) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          CustomAppFormDialog(controller: controller, existing: entry),
    );

/// שואל, ורק אז מסיר את התוכנה מהמרשם.
Future<void> confirmRemoveCustomApp(
  BuildContext context,
  CustomAppsController controller,
  CustomAppView app,
) async {
  final t = context.strings.customApps;
  final approved = await showWarningDialog(
    context: context,
    title: t.removeDialogTitle,
    content: t.removeDialogContent(app.descriptor.name),
    confirmText: t.removeDialogConfirm,
  );
  if (!approved) return;

  if (await controller.remove(app.descriptor.id)) {
    UiSnack.show(AppL10n.strings.customApps.removedSnack(app.descriptor.name));
    return;
  }
  UiSnack.showError(controller.errorMessage ?? '');
}

/// **כל ניהול התוכנות הנוספות יושב כאן** — הוספה, עריכה, הסרה, קטגוריות
/// וסדר התצוגה.
///
/// זה מסך "תוכנות נוספות" עצמו במצב ניהול (`CustomAppsScreen.manage`):
/// אותה רשת ואותו סדר, כך שרואים את התוצאה בזמן העריכה. בהגדרות נשארה
/// שורה אחת בלבד שפותחת אותו — ראו `CustomAppsSettingsCard`.
Future<void> showCustomAppsManageDialog({
  required BuildContext context,
  required CustomAppsController controller,
}) {
  // הקטגוריה הפתוחה משותפת ללשונית; הניהול מתחיל תמיד מהמרשם כולו.
  controller.showAllApps();
  // `Dialog` גולמי: אין עוזר `show*Dialog` שמארח מסך שלם.
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(AppTokens.spaceXL),
      clipBehavior: Clip.antiAlias,
      child: SizedBox.expand(
        child: CustomAppsScreen(
          controller: controller,
          manage: true,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}
