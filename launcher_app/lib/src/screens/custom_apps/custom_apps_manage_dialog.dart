import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_categories_dialog.dart';
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

/// **כל ניהול התוכנות הנוספות יושב כאן** — הוספה, עריכה, הסרה, קטגוריות
/// וסדר התצוגה.
///
/// המרשם הוא הגדרה ולא שימוש: הוא נקבע פעם אחת במחשב המקוון ואחר כך נוסע
/// על הכונן. מסך "תוכנות נוספות" נשאר למה שעושים איתו כל יום — הורדה,
/// התקנה והפעלה. בהגדרות נשארה שורה אחת בלבד, שכל תפקידה לפתוח את החלון
/// הזה — ראו `CustomAppsSettingsCard`.
Future<void> showCustomAppsManageDialog({
  required BuildContext context,
  required CustomAppsController controller,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ManageDialog(controller: controller),
    );

class _ManageDialog extends StatelessWidget {
  const _ManageDialog({required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final theme = Theme.of(context);

    // החלון מאזין בעצמו: הוספה, הסרה ושינוי סדר משנים את הרשימה בזמן
    // שהוא פתוח, ואיש אינו בונה אותו מחדש מבחוץ.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AlertDialog(
        title: Text(t.manageDialogTitle, style: theme.textTheme.titleLarge),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t.manageDialogHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMD),
                Wrap(
                  spacing: AppTokens.spaceSM,
                  runSpacing: AppTokens.spaceSM,
                  children: [
                    ActionButton.recommended(
                      text: t.addButton,
                      icon: FluentIcons.add_24_regular,
                      onPressed: controller.isBusy
                          ? null
                          : () => openAddCustomApp(context, controller),
                    ),
                    // הקטגוריות הן חלק מאותו מרשם, ולכן הניהול שלהן יושב
                    // כאן ולא במסך — שם רואים אותן כסרגל צד ואי אפשר לשנותן.
                    ActionButton.neutral(
                      text: t.manageCategoriesButton,
                      icon: FluentIcons.tag_24_regular,
                      onPressed: controller.isBusy
                          ? null
                          : () => showCustomAppCategoriesDialog(
                                context: context,
                                controller: controller,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceLG),
                ..._appRows(context),
              ],
            ),
          ),
        ),
        actions: [
          ActionButton.neutral(
            text: context.strings.common.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  List<Widget> _appRows(BuildContext context) {
    final t = context.strings.customApps;
    if (!controller.hasApps) {
      return [
        SettingsActionTile.text(
          icon: FluentIcons.box_24_regular,
          title: t.settingsCardTitle,
          subtitle: t.emptyHint,
        ),
      ];
    }

    final apps = controller.apps;
    return [
      for (var i = 0; i < apps.length; i++)
        _ManagedAppTile(
          controller: controller,
          app: apps[i],
          index: i,
          total: apps.length,
        ),
      // מוצג רק כשיש מה לסדר — על תוכנה אחת החיצים ממילא כבויים.
      if (apps.length > 1) ...[
        const SizedBox(height: AppTokens.spaceSM),
        Text(
          t.orderHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    ];
  }
}

/// שורת תוכנה אחת במרשם — מה שהמשתמש רשם, והכפתורים שמשנים אותו.
class _ManagedAppTile extends StatelessWidget {
  const _ManagedAppTile({
    required this.controller,
    required this.app,
    required this.index,
    required this.total,
  });

  final CustomAppsController controller;
  final CustomAppView app;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final busy = controller.isBusy;

    return SettingsActionTile.text(
      icon: FluentIcons.box_24_regular,
      // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
      title: app.descriptor.name,
      subtitle: app.descriptor.description,
      actions: [
        // ⚠️ חיצי מעלה/מטה ולא `context.backArrowIcon`: אלה חיצי סדר
        // ברשימה אנכית, ו-RTL אינו הופך "למעלה" ו"למטה".
        SecondaryIconButton(
          icon: FluentIcons.arrow_up_24_regular,
          tooltip: t.moveAppUpTooltip,
          onPressed: busy || index == 0
              ? null
              : () => controller.moveApp(index, index - 1),
        ),
        SecondaryIconButton(
          icon: FluentIcons.arrow_down_24_regular,
          tooltip: t.moveAppDownTooltip,
          onPressed: busy || index == total - 1
              ? null
              : () => controller.moveApp(index, index + 1),
        ),
        SecondaryIconButton(
          icon: FluentIcons.edit_24_regular,
          tooltip: t.editTooltip,
          onPressed: busy
              ? null
              : () => openEditCustomApp(context, controller, app.entry),
        ),
        SecondaryIconButton(
          icon: FluentIcons.delete_24_regular,
          tooltip: t.removeTooltip,
          onPressed: busy ? null : () => _confirmRemove(context),
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
