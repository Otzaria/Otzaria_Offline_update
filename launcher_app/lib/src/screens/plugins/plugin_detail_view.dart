import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/byte_size.dart';
import '../../services/hebrew_date.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'plugin_rating_panel.dart';
import 'plugin_visuals.dart';

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
  final ValueChanged<String> onCategorySelected;

  final bool busy;

  static const double _twoColumnWidth = 900;

  @override
  Widget build(BuildContext context) {
    return StoreDetailPage(
      backLabel: context.strings.plugins.backToStore,
      title: plugin.name,
      onBack: onBack,
      panels: _panels(context),
    );
  }

  List<Widget> _panels(BuildContext context) {
    return [
      StoreDetailHero(
        image: StoreThumbnail(
          imagePath: controller.assetPath(plugin.imagePath),
          aspectRatio: 4 / 3,
        ),
        imageWidth: 340,
        details: _heroDetails(context),
      ),
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
      const SizedBox(height: AppTokens.spaceLG),
      StoreDetailPanel(
        title: context.strings.plugins.ratingPanelTitle,
        child: PluginRatingSummary(plugin: plugin),
      ),
      if (plugin.screenshotPaths.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceLG),
        _screenshotsPanel(context),
      ],
    ];
  }

  Widget _heroDetails(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.plugins;
    final target = controller.targetOf(plugin);

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
            StoreBadge(
              label: pluginStatusLabel(target?.status ?? plugin.status),
              emphasized: true,
            ),
            StoreBadge(
              label: t.pluginVersionBadge(controller.versionOf(plugin)),
            ),
            StoreBadge(
              label: t.downloadsBadge(plugin.downloadCount),
              icon: FluentIcons.arrow_download_24_regular,
            ),
            if (plugin.ratingCount > 0) PluginRatingBadge(plugin: plugin),
            if (plugin.isFeatured)
              StoreBadge(
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
                StoreTagPill(
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
            if (controller.canDirectInstall(plugin))
              ActionButton.recommended(
                text: t.directInstallButton,
                icon: FluentIcons.arrow_download_24_regular,
                isLoading: busy,
                onPressed: target == null ? null : onInstall,
              ),
            ActionButton.neutral(
              text: t.saveButton,
              icon: FluentIcons.save_24_regular,
              isLoading: busy,
              onPressed: controller.hasFileFor(plugin) ? onSave : null,
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

  String _compatibilityValue(BuildContext context, PluginVersionEntry? target) {
    final t = context.strings.plugins;
    final from = target?.compatibleWith ?? plugin.compatibleWith;
    final to = target?.maxAppVersion ?? plugin.maxAppVersion;
    if (from.isEmpty) return t.valueUnspecifiedFeminine;
    return to == null ? from : t.compatibilityRange(from, to);
  }

  Widget _infoPanel(BuildContext context) {
    final target = controller.targetOf(plugin);
    final localFile = plugin.localFileFor(target?.version);
    final t = context.strings.plugins;

    return StoreDetailPanel(
      title: t.infoPanelTitle,
      child: StoreInfoGrid(
        entries: [
          StoreInfoEntry(
            label: t.infoVersion,
            value: controller.versionOf(plugin).isEmpty
                ? t.valueUnspecifiedFeminine
                : controller.versionOf(plugin),
          ),
          StoreInfoEntry(
            label: t.infoStatus,
            value: pluginStatusLabel(target?.status ?? plugin.status),
          ),
          StoreInfoEntry(
            label: t.infoAuthor,
            value: plugin.author.isEmpty
                ? t.valueUnspecifiedMasculine
                : plugin.author,
          ),
          StoreInfoEntry(
            label: t.infoUpdated,
            value: HebrewDate.format(
              plugin.originalDate.isNotEmpty
                  ? plugin.originalDate
                  : plugin.updatedAt,
            ),
          ),
          StoreInfoEntry(
            label: t.infoNetwork,
            value: (target?.requiresNetwork ?? plugin.requiresNetwork)
                ? t.infoNetworkRequired
                : t.infoNetworkNotRequired,
          ),
          StoreInfoEntry(
            label: t.infoCompatibility,
            value: _compatibilityValue(context, target),
            wide: true,
          ),
          StoreInfoEntry(
            label: t.infoLocalFile,
            value: localFile == null
                ? t.infoLocalFileMissing
                : t.localFileDescription(
                    localFile.fileName,
                    _formatSize(context, localFile.size),
                  ),
            wide: true,
          ),
        ],
      ),
    );
  }

  Widget _tagsPanel(BuildContext context) {
    return StoreDetailPanel(
      title: context.strings.plugins.tagsPanelTitle,
      child: Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (final tag in plugin.tags)
            StoreTagPill(label: tag, onTap: () => onTagSelected(tag)),
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

    return StoreScreenshotsPanel(
      title: context.strings.plugins.screenshotsPanelTitle,
      paths: paths,
    );
  }

  static String _formatSize(BuildContext context, int bytes) =>
      bytes <= 0 ? context.strings.plugins.sizeUnknown : formatBytes(bytes);
}
