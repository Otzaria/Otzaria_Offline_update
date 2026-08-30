import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_form_dialog.dart';

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

/// **כל ניהול התוכנות הנוספות יושב כאן** — הוספה, עריכה והסרה.
///
/// המרשם הוא הגדרה ולא שימוש: הוא נקבע פעם אחת במחשב המקוון ואחר כך נוסע
/// על הכונן. מסך "תוכנות נוספות" נשאר למה שעושים איתו כל יום — הורדה,
/// התקנה והפעלה — וגם נכנסים אליו רק אחרי שנוספה תוכנה ראשונה מכאן.
class CustomAppsSettingsCard extends StatelessWidget {
  const CustomAppsSettingsCard({super.key, required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return SettingsCard(
      title: t.settingsCardTitle,
      hint: t.settingsCardHint,
      actions: [
        ActionButton.recommended(
          text: t.addButton,
          icon: FluentIcons.add_24_regular,
          onPressed: controller.isBusy
              ? null
              : () => openAddCustomApp(context, controller),
        ),
      ],
      children: [
        if (!controller.hasApps)
          SettingsActionTile.text(
            icon: FluentIcons.box_24_regular,
            title: t.settingsCardTitle,
            subtitle: t.emptyHint,
          )
        else
          for (final app in controller.apps)
            _ManagedAppTile(controller: controller, app: app),
      ],
    );
  }
}

/// שורת תוכנה אחת במרשם — מה שהמשתמש רשם, ושני הכפתורים שמשנים אותו.
class _ManagedAppTile extends StatelessWidget {
  const _ManagedAppTile({required this.controller, required this.app});

  final CustomAppsController controller;
  final CustomAppView app;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return SettingsActionTile.text(
      icon: FluentIcons.box_24_regular,
      // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
      title: app.descriptor.name,
      subtitle: app.descriptor.description,
      actions: [
        SecondaryIconButton(
          icon: FluentIcons.edit_24_regular,
          tooltip: t.editTooltip,
          onPressed: controller.isBusy
              ? null
              : () => openEditCustomApp(context, controller, app.entry),
        ),
        SecondaryIconButton(
          icon: FluentIcons.delete_24_regular,
          tooltip: t.removeTooltip,
          onPressed: controller.isBusy ? null : () => _confirmRemove(context),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final t = context.strings.customApps;
    final approved = await showWarningDialog(
      context: context,
      title: t.removeDialogTitle,
      content: t.removeDialogContent(app.descriptor.name),
      confirmText: t.removeDialogConfirm,
    );
    if (!approved) return;

    if (await controller.remove(app.descriptor.id)) {
      UiSnack.show(
        AppL10n.strings.customApps.removedSnack(app.descriptor.name),
      );
      return;
    }
    UiSnack.showError(controller.errorMessage ?? '');
  }
}
