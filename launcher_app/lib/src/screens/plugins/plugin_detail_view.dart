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
    required this.onCategorySelected,
    this.busy = false,
  });

  final StorePlugin plugin;
  final PluginsModuleController controller;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onInstall;
  final ValueChanged<String> onTagSelected;

  /// בחירת קטגוריה מחזירה לרשימה כשהיא מסוננת לאותה קטגוריה, כמו הקישור
  /// מדף התוסף אל דף הקטגוריה באתר.
  final ValueChanged<String> onCategorySelected;

  final bool busy;

  /// מעל הרוחב הזה "מידע כללי" ו"תגיות" יושבים זה לצד זה.
  static const double _twoColumnWidth = 900;

  /// רוחב אריח צילום מסך בגלריה — קבוע, ולכן גם רוחב הפענוח קבוע.
  static const double _screenshotThumbWidth = 200;

  @override
  Widget build(BuildContext context) {
    return PluginStoreBody(
      header: _backHeader(context),
      slivers: [
        PluginStoreBody.padded(
          SliverList.list(children: _panels(context)),
          top: AppTokens.spaceMD,
        ),
      ],
    );
  }

  List<Widget> _panels(BuildContext context) {
    return [
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
    ];
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
            text: context.strings.plugins.backToStore,
            icon: context.backArrowIcon,
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
    final t = context.strings.plugins;

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
            PluginBadge(label: t.pluginVersionBadge(plugin.version)),
            PluginBadge(
              label: t.downloadsBadge(plugin.downloadCount),
              icon: FluentIcons.arrow_download_24_regular,
            ),
            if (plugin.isFeatured)
              PluginBadge(
                label: t.badgeFeatured,
                icon: FluentIcons.star_24_regular,
              ),
            PluginInstallChip(
              status: controller.statusOf(plugin),
              installedVersion: controller.installedVersionOf(plugin),
            ),
          ],
        ),
        if (plugin.categorySlugs.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              for (final slug in plugin.categorySlugs)
                PluginTagPill(
                  label: controller.categoryName(slug),
                  onTap: () => onCategorySelected(slug),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppTokens.spaceMD),
        Wrap(
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: [
            if (plugin.supportsDirectInstall)
              ActionButton.recommended(
                text: t.directInstallButton,
                icon: FluentIcons.arrow_download_24_regular,
                isLoading: busy,
                onPressed: onInstall,
              ),
            ActionButton.neutral(
              text: t.saveButton,
              icon: FluentIcons.save_24_regular,
              isLoading: busy,
              onPressed: plugin.localFile == null ? null : onSave,
            ),
            if (plugin.homepage.isNotEmpty)
              ActionButton.ghost(
                text: t.sourcePageButton,
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
    final t = context.strings.plugins;

    return _panel(
      context,
      t.infoPanelTitle,
      LayoutBuilder(
        builder: (context, constraints) {
          final cells = <({String label, String value, bool wide})>[
            (
              label: t.infoVersion,
              value: plugin.version.isEmpty
                  ? t.valueUnspecifiedFeminine
                  : plugin.version,
              wide: false,
            ),
            (
              label: t.infoStatus,
              value: pluginStatusLabel(plugin.status),
              wide: false,
            ),
            (
              label: t.infoAuthor,
              value: plugin.author.isEmpty
                  ? t.valueUnspecifiedMasculine
                  : plugin.author,
              wide: false,
            ),
            (
              label: t.infoUpdated,
              value: HebrewDate.format(
                plugin.originalDate.isNotEmpty
                    ? plugin.originalDate
                    : plugin.updatedAt,
              ),
              wide: false,
            ),
            (
              label: t.infoNetwork,
              value: plugin.requiresNetwork
                  ? t.infoNetworkRequired
                  : t.infoNetworkNotRequired,
              wide: false,
            ),
            (
              label: t.infoCompatibility,
              value: plugin.compatibleWith.isEmpty
                  ? t.valueUnspecifiedFeminine
                  : plugin.maxAppVersion == null
                      ? plugin.compatibleWith
                      : t.compatibilityRange(
                          plugin.compatibleWith,
                          plugin.maxAppVersion!,
                        ),
              wide: true,
            ),
            (
              label: t.infoLocalFile,
              value: localFile == null
                  ? t.infoLocalFileMissing
                  : t.localFileDescription(
                      localFile.fileName,
                      _formatSize(context, localFile.size),
                    ),
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
      context.strings.plugins.tagsPanelTitle,
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
      context.strings.plugins.screenshotsPanelTitle,
      Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (var i = 0; i < paths.length; i++)
            SizedBox(
              width: _screenshotThumbWidth,
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
                    // תמונה מוקטנת נשארת מוקטנת גם בזיכרון — ה-lightbox
                    // פותח את הקובץ במלוא הרזולוציה בנפרד.
                    cacheWidth: decodeWidthFor(context, _screenshotThumbWidth),
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

  static String _formatSize(BuildContext context, int bytes) {
    if (bytes <= 0) return context.strings.plugins.sizeUnknown;
    if (bytes < 1024) return context.strings.units.bytes(bytes);
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
