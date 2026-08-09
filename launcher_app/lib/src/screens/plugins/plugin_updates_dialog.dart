import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// הודעת "יש עדכונים זמינים" שנפתחת בכניסה למסך, כמו בחנות המקורית.
///
/// מחזיר את ה-id של התוסף שהמשתמש בחר לפתוח, או `null` אם רק סגר. הבחירה
/// נאספת למשתנה מקומי כי `showSingleActionDialog` (הרכיב המותר לדיאלוגים)
/// אינו מחזיר ערך משלו.
Future<String?> showPluginUpdatesDialog({
  required BuildContext context,
  required PluginsModuleController controller,
  required List<StorePlugin> updatable,
}) async {
  String? selected;
  final t = context.strings.plugins;

  await showSingleActionDialog(
    context: context,
    title: t.updatesDialogTitle(updatable.length),
    confirmText: context.strings.common.close,
    customContent: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
              child: Text(
                t.updatesDialogIntro,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final plugin in updatable)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
                child: AppCard(
                  onTap: () {
                    selected = plugin.id;
                    Navigator.of(context).pop();
                  },
                  padding: const EdgeInsets.all(AppTokens.spaceSM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppTokens.spaceXS),
                      Text(
                        t.updatesDialogRow(
                          controller.installedVersionOf(plugin) ?? '?',
                          plugin.version,
                        ),
                        style: TextStyle(
                          fontSize: AppTokens.fontSM,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  return selected;
}
