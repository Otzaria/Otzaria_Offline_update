import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/hebrew_date.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_visuals.dart';

/// כרטיס תוסף בודד ברשת החנות.
class PluginStoreCard extends StatelessWidget {
  const PluginStoreCard({
    super.key,
    required this.plugin,
    required this.controller,
    required this.onOpenDetail,
    required this.onSave,
    required this.onInstall,
    this.busy = false,
  });

  final StorePlugin plugin;
  final PluginsModuleController controller;
  final VoidCallback onOpenDetail;
  final VoidCallback onSave;
  final VoidCallback onInstall;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installStatus = controller.statusOf(plugin);

    return AppCard(
      onTap: onOpenDetail,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                PluginThumbnail(
                    imagePath: controller.assetPath(plugin.imagePath)),
                if (plugin.isPinned)
                  const Positioned(
                    top: AppTokens.spaceSM,
                    right: AppTokens.spaceSM,
                    child: PluginBadge(
                      label: 'מומלץ',
                      icon: FluentIcons.pin_24_regular,
                      emphasized: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMD),
            Wrap(
              spacing: AppTokens.spaceXS,
              runSpacing: AppTokens.spaceXS,
              children: [
                PluginBadge(
                  label: pluginStatusLabel(plugin.status),
                  emphasized: true,
                ),
                PluginBadge(label: 'גרסה ${plugin.version}'),
                PluginBadge(
                  label: '${plugin.downloadCount}',
                  icon: FluentIcons.arrow_download_24_regular,
                ),
                PluginInstallChip(
                  status: installStatus,
                  installedVersion: controller.installedVersionOf(plugin),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              plugin.name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              plugin.shortDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (plugin.tags.isNotEmpty) ...[
              const SizedBox(height: AppTokens.spaceSM),
              Wrap(
                spacing: AppTokens.spaceXS,
                runSpacing: AppTokens.spaceXS,
                children: [
                  for (final tag in plugin.tags.take(4))
                    PluginTagPill(label: tag),
                ],
              ),
            ],
            const Spacer(),
            const SizedBox(height: AppTokens.spaceSM),
            Row(
              children: [
                Expanded(
                  child: ActionButton.neutral(
                    text: 'שמירה',
                    icon: FluentIcons.save_24_regular,
                    isLoading: busy,
                    onPressed: plugin.localFile == null ? null : onSave,
                  ),
                ),
                if (plugin.supportsDirectInstall) ...[
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: ActionButton.recommended(
                      text: 'התקנה',
                      icon: FluentIcons.arrow_download_24_regular,
                      isLoading: busy,
                      onPressed: onInstall,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              'עודכן ב־${HebrewDate.format(plugin.originalDate.isNotEmpty ? plugin.originalDate : plugin.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
