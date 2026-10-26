import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../widgets/widgets_exports.dart';

/// "תוכנות נוספות" בהגדרות: שורה אחת, שכל תפקידה לפתוח את דף הניהול
/// (`CustomAppsManagePage`) — ההוספה, העריכה, הקטגוריות והסדר יושבים שם.
class CustomAppsSettingsCard extends StatelessWidget {
  const CustomAppsSettingsCard({
    super.key,
    required this.controller,
    required this.onOpenManager,
    this.readOnly = false,
    this.driveFull = false,
  });

  final CustomAppsController controller;

  /// נכנס לדף הניהול בנווט — דרך שער הסייפר.
  final VoidCallback onOpenManager;

  final bool readOnly;
  final bool driveFull;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final ro = context.strings.readOnlyDrive;

    // מאזין בעצמו: מספר התוכנות משתנה בזמן שדף הניהול פתוח.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RowsCard(
        children: [
          AppRow(
            key: const ValueKey('settings.customApps.manage'),
            leading: const IconTile(
              icon: FluentIcons.apps_24_regular,
              size: IconTileSize.sm,
              tone: IconTileTone.quiet,
            ),
            title: t.manageRowTitle,
            // כונן מוגן: כל פעולת ניהול כותבת לכונן — מושבת, והפירוט אומר למה.
            subtitle: readOnly
                ? driveFull
                    ? ro.customAppsManageDisabledDriveFull
                    : ro.customAppsManageDisabled
                : controller.hasApps
                    ? t.manageRowSubtitle(controller.apps.length)
                    : t.emptyHint,
            onTap: readOnly ? null : onOpenManager,
          ),
        ],
      ),
    );
  }
}
