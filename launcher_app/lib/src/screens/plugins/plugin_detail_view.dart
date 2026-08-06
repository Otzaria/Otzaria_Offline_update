import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/hebrew_date.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'plugin_screenshot_lightbox.dart';
import 'plugin_store_body.dart';
import 'plugin_visuals.dart';

/// עמוד פרטי התוסף — hero, מידע כללי, תגיות וגלריית צילומי מסך.
class PluginDetailView extends StatelessWidget {
  const PluginDetailView({
    super.key,
    required this.plugin,
    required this.controller,
    required this.onBack,
    required this.onSave,
    required this.onInstall,
    required this.onTagSelected,
    this.busy = false,
  });

  final StorePlugin plugin;
  final PluginsModuleController controller;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onInstall;
  final ValueChanged<String> onTagSelected;
  final bool busy;

  /// מעל הרוחב הזה "מידע כללי" ו"תגיות" יושבים זה לצד זה.
  static const double _twoColumnWidth = 900;

  @override
  Widget build(BuildContext context) {
    return PluginStoreBody(
      header: _backHeader(context),
      children: [
        _heroPanel(context),
        const SizedBox(height: AppTokens.spaceLG),
        LayoutBuilder(
          builder: (context, constraints) {
            final info = _infoPanel(context);
            final tags = plugin.tags.isEmpty ? null : _tagsPanel(context);
            if (tags == null) return info;

            if (constraints.maxWidth < _twoColumnWidth) {
              return Column(
                children: [
                  info,
                  const SizedBox(height: AppTokens.spaceLG),
                  tags,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: AppTokens.spaceLG),
                Expanded(child: tags),
              ],
            );
          },
        ),
        if (plugin.screenshotPaths.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceLG),
          _screenshotsPanel(context),
        ],
      ],
    );
  }

  Widget _backHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PluginStoreBody.horizontalPadding,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        children: [
          ActionButton.ghost(
            text: 'חזרה לחנות',
            icon: FluentIcons.arrow_right_24_regular,
            onPressed: onBack,
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Text(
              plugin.name,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, String title, Widget child) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SettingsCard.titleStyleOf(context)),
            const SizedBox(height: AppTokens.spaceMD),
            child,
          ],
        ),
      ),
    );
  }

  Widget _heroPanel(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLG),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < LayoutBreakpoints.medium;
            final image = SizedBox(
              width: narrow ? double.infinity : 340,
              child: PluginThumbnail(
                imagePath: controller.assetPath(plugin.imagePath),
                aspectRatio: 4 / 3,
              ),
            );
            final details = _heroDetails(context);

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  image,
                  const SizedBox(height: AppTokens.spaceMD),
                  details,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                image,
                const SizedBox(width: AppTokens.spaceXL),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _heroDetails(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plugin.name,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: AppTokens.spaceSM),
        Text(
          plugin.description,
          style: theme.textTheme.bodyMedium,
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
              label: '${plugin.downloadCount} הורדות',
              icon: FluentIcons.arrow_download_24_regular,
            ),
            if (plugin.isPinned)
              const PluginBadge(
                label: 'מומלץ',
                icon: FluentIcons.pin_24_regular,
              ),
            PluginInstallChip(
              status: controller.statusOf(plugin),
              installedVersion: controller.installedVersionOf(plugin),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMD),
        Wrap(
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: [
            if (plugin.supportsDirectInstall)
              ActionButton.recommended(
                text: 'התקנה ישירה לאוצריא',
                icon: FluentIcons.arrow_download_24_regular,
                isLoading: busy,
                onPressed: onInstall,
              ),
            ActionButton.neutral(
              text: 'שמירת הקובץ',
              icon: FluentIcons.save_24_regular,
              isLoading: busy,
              onPressed: plugin.localFile == null ? null : onSave,
            ),
            if (plugin.homepage.isNotEmpty)
              ActionButton.ghost(
                text: 'עמוד המקור',
                icon: FluentIcons.open_24_regular,
                onPressed: () => controller.openHomepage(plugin.homepage),
              ),
          ],
        ),
      ],
    );
  }

  Widget _infoPanel(BuildContext context) {
    final localFile = plugin.localFile;

    return _panel(
      context,
      'מידע כללי',
      LayoutBuilder(
        builder: (context, constraints) {
          final cells = <({String label, String value, bool wide})>[
            (
              label: 'גרסה',
              value: plugin.version.isEmpty ? 'לא צוינה' : plugin.version,
              wide: false,
            ),
            (
              label: 'סטטוס',
              value: pluginStatusLabel(plugin.status),
              wide: false,
            ),
            (
              label: 'מפתח',
              value: plugin.author.isEmpty ? 'לא צוין' : plugin.author,
              wide: false,
            ),
            (
              label: 'עודכן',
              value: HebrewDate.format(
                plugin.originalDate.isNotEmpty
                    ? plugin.originalDate
                    : plugin.updatedAt,
              ),
              wide: false,
            ),
            (
              label: 'חיבור אינטרנט בזמן שימוש',
              value: plugin.requiresNetwork ? 'נדרש' : 'לא נדרש',
              wide: false,
            ),
            (
              label: 'תאימות',
              value: plugin.compatibleWith.isEmpty
                  ? 'לא צוינה'
                  : plugin.maxAppVersion == null
                      ? plugin.compatibleWith
                      : '${plugin.compatibleWith} — עד ${plugin.maxAppVersion}',
              wide: true,
            ),
            (
              label: 'קובץ התוסף במראה',
              value: localFile == null
                  ? 'טרם ירד — יש לבצע סנכרון'
                  : '${localFile.fileName} (${_formatSize(localFile.size)})',
              wide: true,
            ),
          ];

          final columns = constraints.maxWidth < 420 ? 1 : 2;
          final cellWidth =
              (constraints.maxWidth - AppTokens.spaceSM * (columns - 1)) /
                  columns;

          return Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              for (final cell in cells)
                SizedBox(
                  width: cell.wide || columns == 1
                      ? constraints.maxWidth
                      : cellWidth,
                  child: _InfoCell(label: cell.label, value: cell.value),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _tagsPanel(BuildContext context) {
    return _panel(
      context,
      'תגיות',
      Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (final tag in plugin.tags)
            PluginTagPill(label: tag, onTap: () => onTagSelected(tag)),
        ],
      ),
    );
  }

  Widget _screenshotsPanel(BuildContext context) {
    final paths = [
      for (final relative in plugin.screenshotPaths)
        if (controller.assetPath(relative) case final path?) path,
    ];
    if (paths.isEmpty) return const SizedBox.shrink();

    return _panel(
      context,
      'צילומי מסך',
      Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (var i = 0; i < paths.length; i++)
            SizedBox(
              width: 200,
              child: AppCard(
                onTap: () => showPluginScreenshots(
                  context,
                  paths: paths,
                  initialIndex: i,
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    File(paths[i]),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => const Center(
                      child: Icon(FluentIcons.image_off_24_regular),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return 'גודל לא ידוע';
    if (bytes < 1024) return '$bytes בייט';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// תא מידע — תווית קטנה מעל ערך מודגש, על רקע ניטרלי.
class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM + 2,
      ),
      decoration: BoxDecoration(
        color: AppSurfaces.panelSection(context),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppTokens.fontSM,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTokens.fontMD,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
