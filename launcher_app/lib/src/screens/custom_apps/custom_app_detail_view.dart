import 'dart:async';

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
import 'custom_app_store_card.dart';

/// דף תוכנה — כמו דף תוסף: ראש עם הפעולה לפי המצב, מידע וצילומי מסך.
class CustomAppDetailView extends StatelessWidget {
  const CustomAppDetailView({
    super.key,
    required this.controller,
    required this.app,
    required this.readOnly,
    required this.onInstall,
    required this.onLaunch,
    required this.onDownload,
    required this.onPickLocation,
    required this.onCategorySelected,
    this.online = true,
  });

  final CustomAppsController controller;
  final CustomAppView app;
  final bool readOnly;

  /// `false` — אין אינטרנט: אין בדיקה ואין הורדה ברשת.
  final bool online;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;
  final VoidCallback onPickLocation;
  final ValueChanged<String> onCategorySelected;

  AppDescriptor get _descriptor => app.descriptor;
  bool get _isFromGithub => _descriptor.sourceKind == AppSourceKind.github;
  bool get _canFetch => _isFromGithub && !readOnly && online;
  bool get _isDownloading => controller.downloadingId == _descriptor.id;

  @override
  Widget build(BuildContext context) {
    return StoreBody(slivers: [StoreBody.block(_body(context))]);
  }

  Widget _body(BuildContext context) {
    final t = context.strings.customApps;
    final cs = Theme.of(context).colorScheme;
    final screenshots = controller.shownScreenshotPathsOf(_descriptor);
    final primary = CustomAppAction(
      controller: controller,
      app: app,
      readOnly: readOnly,
      onInstall: onInstall,
      onLaunch: onLaunch,
      onDownload: onDownload,
      primary: true,
      online: online,
    );
    // ההורדה היא הפעולה הראשית רק כשאין מה להתקין; אחרת — כפתור משני, ורק
    // כשמה שבכונן חסר או ישן מזה שברשת.
    final downloadIsPrimary = !app.canInstall && !app.canLaunch && _canFetch;
    final stored = app.storedInstaller;
    final onlineVersion = controller.onlineVersions[_descriptor.id];
    final driveOutdated = stored == null ||
        (onlineVersion != null &&
            customAppOnlineIsNewer(onlineVersion, stored.version));
    final checking = controller.checkingIds.contains(_descriptor.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoreDetailHero(
          icon: StoreIcon(
            imagePath: controller.iconPathOf(_descriptor),
            placeholderIcon: FluentIcons.box_24_regular,
            size: 96,
          ),
          title: _descriptor.name,
          meta: StoreMetaLine(
            items: [
              for (final item in customAppMeta(context, app))
                StoreMetaItem(item),
            ],
          ),
          summary: _descriptor.description,
          actions: [
            primary,
            if (app.canInstall &&
                app.canLaunch &&
                app.knownInstalledVersion == null)
              ActionButton.neutral(
                text: t.reinstallButton,
                onPressed: controller.isBusy ? null : onInstall,
              ),
            if (app.canDetect && !app.canLaunch)
              ActionButton.neutral(
                text: t.pickLocationButton,
                icon: FluentIcons.folder_open_20_regular,
                onPressed: controller.isBusy ? null : onPickLocation,
              ),
            if (_canFetch && !downloadIsPrimary && driveOutdated)
              ActionButton.neutral(
                text: t.downloadButton,
                icon: FluentIcons.arrow_download_20_regular,
                isLoading: _isDownloading,
                onPressed: controller.downloadingId != null ||
                        controller.isDownloadingAll
                    ? null
                    : onDownload,
              ),
            if (_canFetch)
              ActionButton.ghost(
                text: t.checkOnlineButton,
                icon: FluentIcons.arrow_sync_20_regular,
                spinning: checking,
                onPressed: checking || controller.isCheckingAll
                    ? null
                    : () => unawaited(_checkOnline(context)),
              ),
          ],
          note: customAppNoteOf(context, app),
          below: _progress(context),
        ),
        StoreDetailColumns(
          start: [
            if (screenshots.isNotEmpty) ...[
              StoreSectionTitle(t.screenshotsPanelTitle),
              StoreScreenshots(paths: screenshots),
            ],
            if (_descriptor.longDescription case final text?) ...[
              StoreSectionTitle(t.aboutPanelTitle),
              Text(
                text,
                style: AppTextStyles.dialogBody.copyWith(color: cs.onSurface),
              ),
            ],
          ],
          end: [
            StoreSectionTitle(t.infoPanelTitle),
            StoreInfoRows(entries: _info(context)),
            if (_descriptor.categorySlugs.isNotEmpty) ...[
              StoreSectionTitle(t.categoriesTitle),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final slug in _descriptor.categorySlugs)
                    StoreTagPill(
                      label: controller.categoryName(slug),
                      tonal: true,
                      onTap: () => onCategorySelected(slug),
                    ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// "בדיקה ברשת" אומרת מה נמצא — לא רק מעדכנת שורה בדף.
  Future<void> _checkOnline(BuildContext context) async {
    await controller.checkOnline(_descriptor);
    if (!context.mounted) return;
    final label = customAppOnlineLabel(context, controller, app);
    if (label != null) UiSnack.show(label);
  }

  Widget? _progress(BuildContext context) {
    final t = context.strings.customApps;
    if (controller.isLearning) return InfoProgressRow(stage: t.learningLabel);
    if (!_isDownloading) return null;
    return ListenableBuilder(
      listenable: controller.progress,
      builder: (context, _) => InfoProgressRow(
        stage: t.downloadingLabel,
        progress: (controller.downloadTotal ?? 0) > 0
            ? (controller.downloadReceived ?? 0) / controller.downloadTotal!
            : null,
        detail: formatBytesProgress(
          controller.downloadReceived,
          controller.downloadTotal,
        ),
      ),
    );
  }

  List<StoreInfoEntry> _info(BuildContext context) {
    final t = context.strings.customApps;
    final stored = app.storedInstaller;
    final online = customAppOnlineLabel(context, controller, app);
    final installedValue = customAppInstalledValue(context, app);
    final storedValue = customAppStoredValue(context, app);
    return [
      StoreInfoEntry(
        label: t.infoInstalled,
        value: installedValue.text,
        ltr: installedValue.ltr,
      ),
      StoreInfoEntry(
        label: t.infoStored,
        value: storedValue.text,
        ltr: storedValue.ltr,
      ),
      if (_isFromGithub)
        StoreInfoEntry(
          label: t.infoOnline,
          value: online ?? t.onlineNotChecked,
        ),
      StoreInfoEntry(
        label: t.infoSource,
        value: switch (_descriptor.github) {
          final source? => source.webUrl,
          null => t.infoSourceFile,
        },
        mono: _descriptor.github != null,
      ),
      if (stored != null) ...[
        StoreInfoEntry(
          label: t.infoStoredSize,
          value: stored.sizeBytes > 0
              ? formatBytes(stored.sizeBytes)
              : t.valueUnknown,
        ),
        StoreInfoEntry(
          label: t.infoStoredAdded,
          value: formatStoreLocalDate(stored.addedAt),
        ),
      ],
    ];
  }
}
