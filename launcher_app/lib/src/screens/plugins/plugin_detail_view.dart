import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/byte_size.dart';
import '../../services/timestamps.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'plugin_rating_panel.dart';
import 'plugin_visuals.dart';

/// דף התוסף — כמו `/plugins/[id]` באתר: ראש עם הפעולה לפי המצב, רצועת
/// נתונים, צילומים, תיאור, דירוג, מידע, תגיות וגרסאות.
class PluginDetailView extends StatelessWidget {
  const PluginDetailView({
    super.key,
    required this.plugin,
    required this.controller,
    required this.onSave,
    required this.onInstall,
    required this.onTagSelected,
    required this.onCategorySelected,
    this.busy = false,
    this.blockedReason,
    this.otzariaInstalled = true,
    this.online,
  });

  final StorePlugin plugin;
  final PluginsModuleController controller;
  final VoidCallback onSave;
  final VoidCallback onInstall;
  final ValueChanged<String> onTagSelected;
  final ValueChanged<String> onCategorySelected;
  final bool busy;

  /// למה הפעולות מושבתות כרגע (סנכרון, ייצוא, "עדכון הכול"), או `null`.
  final String? blockedReason;
  final bool otzariaInstalled;
  final bool? online;

  bool get _blocked => blockedReason != null;

  @override
  Widget build(BuildContext context) {
    final state = pluginCardStateOf(
      controller,
      plugin,
      busy: busy,
      otzariaInstalled: otzariaInstalled,
      online: online,
    );
    return StoreBody(
      slivers: [
        StoreBody.block(_body(context, state)),
      ],
    );
  }

  Widget _body(BuildContext context, PluginCardState state) {
    final t = context.strings.plugins;
    final banner = _banner(context, state);
    final screenshots = [
      for (final relative in plugin.screenshotPaths)
        if (controller.assetPath(relative) case final path?) path,
    ];
    final note =
        pluginNoteOf(context, controller, plugin, state, online: online);
    final canSave = controller.hasFileFor(plugin) &&
        state != PluginCardState.saveOnly &&
        state != PluginCardState.development;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (banner != null) banner,
        StoreDetailHero(
          icon: StoreIcon(
            imagePath: controller.assetPath(plugin.imagePath),
            size: 96,
          ),
          title: plugin.name,
          meta: PluginMeta(controller: controller, plugin: plugin),
          summary: plugin.shortDescription,
          actions: [
            PluginAction(
              controller: controller,
              plugin: plugin,
              state: state,
              onInstall: onInstall,
              onSave: onSave,
              primary: true,
              blocked: _blocked,
            ),
            if (canSave)
              ActionButton.neutral(
                text: t.saveFileButton,
                icon: FluentIcons.save_20_regular,
                onPressed: busy || _blocked ? null : onSave,
              ),
          ],
          // ההסבר של "לא מתאים" ושל קובץ חסר כבר בבאנר שמעל.
          note: blockedReason ??
              (state == PluginCardState.incompatible ||
                      state == PluginCardState.missingOffline
                  ? null
                  : note),
        ),
        const SizedBox(height: 22),
        StoreFacts(facts: _facts(context)),
        const SizedBox(height: 6),
        StoreDetailColumns(
          start: [
            if (screenshots.isNotEmpty) ...[
              StoreSectionTitle(t.screenshotsPanelTitle),
              StoreScreenshots(paths: screenshots),
            ],
            if (plugin.description.isNotEmpty) ...[
              StoreSectionTitle(t.descriptionTitle),
              Text(
                plugin.description,
                style: AppTextStyles.dialogBody.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
            StoreSectionTitle(t.ratingPanelTitle),
            PluginRatingSummary(plugin: plugin, asOf: controller.lastSync),
          ],
          end: [
            StoreSectionTitle(t.infoPanelTitle),
            StoreInfoRows(entries: _info(context)),
            if (plugin.categorySlugs.isNotEmpty || plugin.tags.isNotEmpty) ...[
              StoreSectionTitle(t.tagsPanelTitle),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final slug in plugin.categorySlugs)
                    StoreTagPill(
                      label: controller.categoryName(slug),
                      tonal: true,
                      onTap: () => onCategorySelected(slug),
                    ),
                  for (final tag in plugin.tags)
                    StoreTagPill(label: tag, onTap: () => onTagSelected(tag)),
                ],
              ),
            ],
            if (plugin.versions.isNotEmpty) ...[
              StoreSectionTitle(t.versionsTitle),
              _Versions(controller: controller, plugin: plugin),
            ],
          ],
        ),
      ],
    );
  }

  Widget? _banner(BuildContext context, PluginCardState state) {
    final t = context.strings.plugins;
    final missing = !controller.hasFileFor(plugin) &&
        (state == PluginCardState.install ||
            state == PluginCardState.update ||
            state == PluginCardState.missingOffline);
    return switch (state) {
      PluginCardState.incompatible => NoticeBanner(
          kind: NoticeKind.warning,
          leading: const IconTile(
            icon: FluentIcons.warning_24_regular,
            tone: IconTileTone.error,
          ),
          title: t.incompatibleTitle,
          body: switch ((
            pluginRequiredAppVersion(plugin),
            controller.appVersion
          )) {
            (final needs?, final here?) =>
              t.incompatibleBodyVersions(needs, here),
            (final needs?, null) => t.noteNeedsApp(needs),
            _ => t.incompatibleBody,
          },
        ),
      PluginCardState.disabled ||
      PluginCardState.update when controller.isDisabledInOtzaria(plugin) =>
        NoticeBanner(
          leading: const IconTile(
            icon: FluentIcons.eye_off_24_regular,
            tone: IconTileTone.quiet,
          ),
          title: t.disabledTitle,
          body: state == PluginCardState.update
              ? '${t.disabledBody} ${t.disabledUpdateBody}'
              : t.disabledBody,
        ),
      PluginCardState.development => NoticeBanner(
          leading: const IconTile(
            icon: FluentIcons.wrench_24_regular,
            tone: IconTileTone.quiet,
          ),
          title: t.developmentTitle,
          body: t.developmentBody,
        ),
      _ when missing => NoticeBanner(
          leading: const IconTile(
            icon: FluentIcons.arrow_download_24_regular,
            tone: IconTileTone.quiet,
          ),
          title: t.fileMissingTitle,
          body: t.fileMissingBody,
        ),
      _ => null,
    };
  }

  List<StoreFact> _facts(BuildContext context) {
    final t = context.strings.plugins;
    final target = controller.targetOf(plugin);
    final installed = controller.installedVersionOf(plugin);
    final compatible = target != null;
    final network = target?.requiresNetwork ?? plugin.requiresNetwork;
    final size = _fileSize();
    final needs = pluginRequiredAppVersion(plugin);
    final here = controller.appVersion;

    return [
      StoreFact(
        label: t.factRating,
        value: plugin.ratingCount > 0 ? formatRating(plugin.ratingAvg) : '—',
        icon: plugin.ratingCount > 0 ? FluentIcons.star_16_filled : null,
        caption: plugin.ratingCount > 0
            ? t.ratingCountLabel(plugin.ratingCount)
            : t.ratingEmpty,
        wideOnly: true,
      ),
      StoreFact(
        label: t.infoVersion,
        value: controller.versionOf(plugin),
        ltr: true,
        caption: installed == null
            ? t.factVersionLatest
            : installed == controller.versionOf(plugin)
                ? t.factVersionInstalled
                : t.factVersionInstalledAt(installed),
      ),
      StoreFact(
        label: t.factCompatible,
        value: compatible ? t.factYes : t.factNo,
        icon: compatible
            ? FluentIcons.checkmark_circle_16_regular
            : FluentIcons.warning_16_regular,
        caption: compatible
            ? (here == null ? null : t.factOtzariaVersion(here))
            : (needs == null ? null : t.noteNeedsApp(needs)),
      ),
      StoreFact(
        label: t.infoNetwork,
        value: network ? t.infoNetworkRequired : t.infoNetworkNotRequired,
        icon: network
            ? FluentIcons.globe_16_regular
            : FluentIcons.wifi_off_20_regular,
        caption: network ? t.factNetworkSome : t.factNetworkAny,
      ),
      StoreFact(
        label: t.factSize,
        value: size == null ? '—' : formatBytes(size),
        caption:
            controller.hasFileFor(plugin) ? t.factOnDrive : t.factNotOnDrive,
        wideOnly: true,
      ),
    ];
  }

  int? _fileSize() {
    final target = controller.targetOf(plugin);
    final local = plugin.localFileFor(target?.version);
    final bytes = local?.size ?? target?.fileSize ?? 0;
    return bytes > 0 ? bytes : null;
  }

  List<StoreInfoEntry> _info(BuildContext context) {
    final t = context.strings.plugins;
    final target = controller.targetOf(plugin);
    final homepage = plugin.homepage;
    return [
      StoreInfoEntry(
        label: t.infoAuthor,
        value:
            plugin.author.isEmpty ? t.valueUnspecifiedMasculine : plugin.author,
      ),
      StoreInfoEntry(
        label: t.infoUpdated,
        value: formatStoreDateRaw(
          plugin.displayUpdatedDate,
        ),
      ),
      StoreInfoEntry(
        label: t.infoStatus,
        value: pluginStatusLabel(target?.status ?? plugin.status),
      ),
      StoreInfoEntry(
        label: t.infoDownloads,
        value: formatCount(plugin.downloadCount),
      ),
      if (homepage.isNotEmpty)
        StoreInfoEntry(
          label: t.infoSource,
          value: homepage,
          mono: true,
          trailing: [
            AppIconButton(
              icon: FluentIcons.copy_20_regular,
              tooltip: t.copyAddressTooltip,
              small: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: homepage));
                UiSnack.showSuccess(t.addressCopiedSnack);
              },
            ),
            AppIconButton(
              icon: FluentIcons.open_20_regular,
              tooltip: t.sourcePageButton,
              small: true,
              onPressed: () => controller.openHomepage(homepage),
            ),
          ],
        ),
    ];
  }
}

/// היסטוריית הגרסאות: גרסה, "העדכנית"/"מותקנת אצלך", תאריך וגודל.
class _Versions extends StatelessWidget {
  const _Versions({required this.controller, required this.plugin});

  final PluginsModuleController controller;
  final StorePlugin plugin;

  static const int _shown = 4;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;
    final cs = Theme.of(context).colorScheme;
    final installed = controller.installedVersionOf(plugin);
    final meta = AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant);
    return RowsCard(
      children: [
        for (final entry in plugin.versions.take(_shown))
          AppRow(
            title: entry.version,
            titleDirection: TextDirection.ltr,
            subtitle: [
              if (entry.isLatest) t.versionLatestTag,
              if (entry.version == installed) t.versionInstalledTag,
              if (entry.releasedAt.isNotEmpty)
                formatStoreDateRaw(entry.releasedAt),
            ].join(' · '),
            trailing: entry.fileSize > 0
                ? Text(formatBytes(entry.fileSize), style: meta)
                : null,
          ),
      ],
    );
  }
}
