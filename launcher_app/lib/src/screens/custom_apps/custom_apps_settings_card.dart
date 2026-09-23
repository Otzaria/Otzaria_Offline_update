import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_apps_manage_dialog.dart';

/// שורה אחת במסך ההגדרות, וכל תפקידה לפתוח את מסך הניהול.
///
/// הניהול עצמו — הוספה, עריכה, הסרה, קטגוריות וסדר — יושב כולו ב-
/// [showCustomAppsManageDialog]. מסך ההגדרות הוא רשימת הגדרות, ומרשם
/// שגדל עם כל תוכנה שנוספת הפך אותו למסך של תוכנות נוספות.
class CustomAppsSettingsCard extends StatelessWidget {
  const CustomAppsSettingsCard({super.key, required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    // מאזין בעצמו: מספר התוכנות שבשורה משתנה בזמן שמסך הניהול פתוח מעליה.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SettingsCard(
        title: t.settingsCardTitle,
        hint: t.settingsCardHint,
        children: [
          SettingsActionTile.text(
            icon: FluentIcons.box_24_regular,
            title: t.settingsCardTitle,
            subtitle: controller.hasApps
                ? t.registeredAppCount(controller.apps.length)
                : t.emptyHint,
            actions: [
              ActionButton.recommended(
                text: t.openManagerButton,
                icon: FluentIcons.settings_24_regular,
                onPressed: () => showCustomAppsManageDialog(
                  context: context,
                  controller: controller,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
