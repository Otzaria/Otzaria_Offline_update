import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_apps_screen.dart';

/// הכניסה להוספת התוכנה **הראשונה**.
///
/// היא קיימת בדיוק בגלל שפריט הניווט "תוכנות נוספות" מופיע רק אחרי שיש
/// תוכנה אחת — בלי הכרטיס הזה לא הייתה שום דרך להגיע לשם בפעם הראשונה.
/// מרגע שנוספה תוכנה, המקום הטבעי לעבוד בו הוא המסך.
class CustomAppsSettingsCard extends StatelessWidget {
  const CustomAppsSettingsCard({super.key, required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return SettingsCard(
      title: t.settingsCardTitle,
      subtitle: t.settingsCardSubtitle,
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.box_24_regular,
          title: t.settingsCardTitle,
          subtitle: controller.hasApps
              ? controller.apps.map((a) => a.descriptor.name).join(', ')
              : t.emptyHint,
          actions: [
            ActionButton.recommended(
              text: t.addButton,
              icon: FluentIcons.add_24_regular,
              onPressed: controller.isBusy
                  ? null
                  : () => openAddCustomApp(context, controller),
            ),
          ],
        ),
      ],
    );
  }
}
