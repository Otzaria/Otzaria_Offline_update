import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../services/timestamps.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import '../store_kit/store_kit.dart';
import 'custom_app_status.dart';

class CustomAppDetailView extends StatelessWidget {
  const CustomAppDetailView({
    super.key,
    required this.controller,
    required this.app,
    required this.readOnly,
    required this.onBack,
    required this.onInstall,
    required this.onLaunch,
    required this.onDownload,
    required this.onPickLocation,
    required this.onCategorySelected,
  });

  final CustomAppsController controller;
  final CustomAppView app;

  final bool readOnly;

  final VoidCallback onBack;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;
  final VoidCallback onPickLocation;

  final ValueChanged<String> onCategorySelected;

  AppDescriptor get _descriptor => app.descriptor;
  bool get _isFromGithub => _descriptor.sourceKind == AppSourceKind.github;
  bool get _isDownloading => controller.downloadingId == _descriptor.id;

  @override
  Widget build(BuildContext context) {
    return StoreDetailPage(
      backLabel: context.strings.customApps.backToApps,
      title: _descriptor.name,
      onBack: onBack,
      panels: _panels(context),
    );
  }

  List<Widget> _panels(BuildContext context) {
    final t = context.strings.customApps;
    final screenshots = controller.shownScreenshotPathsOf(_descriptor);

    return [
      StoreDetailHero(
        image: StoreThumbnail.icon(
          imagePath: controller.iconPathOf(_descriptor),
          placeholderIcon: FluentIcons.box_24_regular,
        ),
        imageWidth: 300,
        imageMaxWidth: 360,
        details: _heroDetails(context),
      ),
      if (_descriptor.longDescription case final text?) ...[
        const SizedBox(height: AppTokens.spaceLG),
        StoreDetailPanel(
          title: t.aboutPanelTitle,
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
      const SizedBox(height: AppTokens.spaceLG),
      _infoPanel(context),
      if (screenshots.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceLG),
        StoreScreenshotsPanel(
          title: t.screenshotsPanelTitle,
          paths: screenshots,
        ),
      ],
    ];
  }

  Widget _heroDetails(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.customApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_descriptor.name, style: theme.textTheme.headlineMedium),
        if (_descriptor.description case final text?) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: AppTokens.spaceMD),
        Wrap(
          spacing: AppTokens.spaceXS,
          runSpacing: AppTokens.spaceXS,
          children: [
            StatusChip(
              kind: customAppStatusKind(app),
              label: customAppInstalledLabel(context, app),
            ),
            StoreBadge(label: customAppStoredLabel(context, app)),
            if (customAppOnlineLabel(context, controller, app)
                case final label?)
              StoreBadge(label: label),
          ],
        ),
        if (_descriptor.categorySlugs.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              for (final slug in _descriptor.categorySlugs)
                StoreTagPill(
                  label: controller.categoryName(slug),
                  onTap: () => onCategorySelected(slug),
                ),
            ],
          ),
        ],
        if (controller.isLearning) ...[
          const SizedBox(height: AppTokens.spaceMD),
          InfoProgressRow(stage: t.learningLabel),
        ],
        if (_isDownloading) ...[
          const SizedBox(height: AppTokens.spaceMD),
          ListenableBuilder(
            listenable: controller.progress,
            builder: (context, _) => InfoProgressRow(
              stage: t.downloadingLabel,
              progress: (controller.downloadTotal ?? 0) > 0
                  ? (controller.downloadReceived ?? 0) /
                      controller.downloadTotal!
                  : null,
              detail: formatBytesProgress(
                controller.downloadReceived,
                controller.downloadTotal,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppTokens.spaceMD),
        _actions(context),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final t = context.strings.customApps;
    final common = context.strings.common;

    return Wrap(
      spacing: AppTokens.spaceSM,
      runSpacing: AppTokens.spaceSM,
      children: [
        if (app.canInstall)
          ActionButton.recommended(
            text: common.install,
            icon: FluentIcons.desktop_arrow_right_24_regular,
            onPressed: controller.isBusy ? null : onInstall,
          ),
        if (app.canLaunch)
          ActionButton.neutral(
            text: common.launch,
            icon: FluentIcons.play_24_regular,
            onPressed: controller.isBusy ? null : onLaunch,
          ),
        if (app.canDetect && !app.canLaunch)
          ActionButton.ghost(
            text: t.pickLocationButton,
            icon: FluentIcons.folder_open_24_regular,
            onPressed: controller.isBusy ? null : onPickLocation,
          ),
        if (_isFromGithub && !readOnly) ...[
          ActionButton.neutral(
            text: t.downloadButton,
            icon: FluentIcons.arrow_download_24_regular,
            isLoading: _isDownloading,
            onPressed:
                controller.downloadingId != null || controller.isDownloadingAll
                    ? null
                    : onDownload,
          ),
          ActionButton.ghost(
            text: t.checkOnlineButton,
            icon: FluentIcons.arrow_sync_24_regular,
            onPressed: () => controller.checkOnline(_descriptor),
          ),
        ],
      ],
    );
  }

  Widget _infoPanel(BuildContext context) {
    final t = context.strings.customApps;
    final stored = app.storedInstaller;

    return StoreDetailPanel(
      title: t.infoPanelTitle,
      child: StoreInfoGrid(
        entries: [
          StoreInfoEntry(
            label: t.infoSource,
            value: _isFromGithub ? t.infoSourceGithub : t.infoSourceFile,
          ),
          StoreInfoEntry(
            label: t.infoInstalled,
            value: customAppInstalledLabel(context, app),
          ),
          StoreInfoEntry(
            label: t.infoStored,
            value: customAppStoredLabel(context, app),
          ),
          if (customAppOnlineLabel(context, controller, app) case final online?)
            StoreInfoEntry(label: t.infoOnline, value: online),
          if (stored != null) ...[
            StoreInfoEntry(
              label: t.infoStoredSize,
              value: stored.sizeBytes > 0
                  ? formatBytes(stored.sizeBytes)
                  : t.valueUnknown,
            ),
            StoreInfoEntry(
              label: t.infoStoredAdded,
              value: formatTimestamp(stored.addedAt),
            ),
          ],
        ],
      ),
    );
  }
}
