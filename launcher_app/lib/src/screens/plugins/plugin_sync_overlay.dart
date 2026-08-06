import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../theme/theme_exports.dart';

/// שכבת חסימה בזמן סנכרון — הודעת שלב, מד התקדמות ורשימת אזהרות.
/// כשל בקובץ בודד אינו עוצר את הסנכרון, ולכן האזהרות נאספות לרשימה
/// במקום להפיל את הפעולה.
class PluginSyncOverlay extends StatelessWidget {
  const PluginSyncOverlay({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: cs.surface,
            borderRadius: AppTokens.borderRadiusAll,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLG),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'מסנכרן את חנות התוספים',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    controller.syncMessage ?? 'מתחיל...',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  ClipRRect(
                    borderRadius: AppTokens.borderRadiusAll,
                    child: LinearProgressIndicator(
                      value: controller.syncProgress,
                      minHeight: 8,
                    ),
                  ),
                  if (controller.syncWarnings.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceMD),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final warning in controller.syncWarnings)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppTokens.spaceXS,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      FluentIcons.warning_24_regular,
                                      size: 14,
                                      color: cs.tertiary,
                                    ),
                                    const SizedBox(width: AppTokens.spaceXS),
                                    Expanded(
                                      child: Text(
                                        warning,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: cs.tertiary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
