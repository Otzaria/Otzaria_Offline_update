import 'dart:io';

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

/// דף התוכנה — התיאור המלא, המידע, הקטגוריות וצילומי המסך, **וכל
/// הפעולות**. הכרטיס שברשת נושא פעולה אחת בלבד, וכאן יושבות כולן.
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

  /// ראו `CustomAppsScreen.readOnly`.
  final bool readOnly;

  final VoidCallback onBack;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onDownload;
  final VoidCallback onPickLocation;

  /// בחירת קטגוריה מחזירה לרשימה כשהיא מסוננת לאותה קטגוריה.
  final ValueChanged<String> onCategorySelected;

  /// רוחב אריח צילום מסך בגלריה — קבוע, ולכן גם רוחב הפענוח קבוע.
  static const double _screenshotThumbWidth = 200;

  AppDescriptor get _descriptor => app.descriptor;
  bool get _isFromGithub => _descriptor.sourceKind == AppSourceKind.github;
  bool get _isDownloading => controller.downloadingId == _descriptor.id;

  @override
  Widget build(BuildContext context) {
    return StoreBody(
      header: _backHeader(context),
      slivers: [
        StoreBody.padded(
          SliverList.list(children: _panels(context)),
          top: AppTokens.spaceMD,
        ),
      ],
    );
  }

  List<Widget> _panels(BuildContext context) {
    final t = context.strings.customApps;
    // קובץ שנמחק מהכונן אינו מוצג כאריח שבור — הגלריה פשוט מתקצרת.
    final screenshots = [
      for (final path in controller.screenshotPathsOf(_descriptor))
        if (File(path).existsSync()) path,
    ];

    return [
      _heroPanel(context),
      if (_descriptor.longDescription case final text?) ...[
        const SizedBox(height: AppTokens.spaceLG),
        // תוכן שהמשתמש כתב — מוצג כמות שהוא, בלי תרגום.
        _panel(
          context,
          t.aboutPanelTitle,
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
      const SizedBox(height: AppTokens.spaceLG),
      _infoPanel(context),
      if (screenshots.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceLG),
        _screenshotsPanel(context, screenshots),
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
        horizontal: StoreBody.horizontalPadding,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        children: [
          ActionButton.ghost(
            text: context.strings.customApps.backToApps,
            icon: context.backArrowIcon,
            onPressed: onBack,
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Text(
              _descriptor.name,
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
              child: StoreThumbnail.icon(
                imagePath: controller.iconPathOf(_descriptor),
                placeholderIcon: FluentIcons.box_24_regular,
                aspectRatio: 4 / 3,
                // אייקון של ווינדוס הוא 256×256 לכל היותר; מתיחה שלו
                // לרוחב המסגרת רק מטשטשת אותו.
                maxImageSize: 192,
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
    final t = context.strings.customApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
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
        // הלמידה שאחרי ההתקנה יכולה להימשך עד דקה — ראו `InstallLearner`.
        // בלי השורה הזו זה נראה כתקיעה.
        if (controller.isLearning) ...[
          const SizedBox(height: AppTokens.spaceMD),
          InfoProgressRow(stage: t.learningLabel),
        ],
        if (_isDownloading) ...[
          const SizedBox(height: AppTokens.spaceMD),
          InfoProgressRow(
            stage: t.downloadingLabel,
            progress: (controller.downloadTotal ?? 0) > 0
                ? (controller.downloadReceived ?? 0) / controller.downloadTotal!
                : null,
            detail: formatBytesProgress(
              controller.downloadReceived,
              controller.downloadTotal,
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
        // הנפילה חזרה כשהזיהוי לא מצא — בדיוק כמו "בחירת מיקום ידנית"
        // של אוצריא. מוצגת רק כשיש מה לחפש.
        if (app.canDetect && !app.canLaunch)
          ActionButton.ghost(
            text: t.pickLocationButton,
            icon: FluentIcons.folder_open_24_regular,
            onPressed: controller.isBusy ? null : onPickLocation,
          ),
        // שתיהן נוגעות ברשת, וההורדה כותבת לכונן — לא במצב קריאה.
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

    return _panel(
      context,
      t.infoPanelTitle,
      LayoutBuilder(
        builder: (context, constraints) {
          final cells = <({String label, String value})>[
            (
              label: t.infoSource,
              value: _isFromGithub ? t.infoSourceGithub : t.infoSourceFile,
            ),
            (
              label: t.infoInstalled,
              value: customAppInstalledLabel(context, app),
            ),
            (label: t.infoStored, value: customAppStoredLabel(context, app)),
            if (customAppOnlineLabel(context, controller, app)
                case final online?)
              (label: t.infoOnline, value: online),
            if (stored != null) ...[
              (
                label: t.infoStoredSize,
                value: stored.sizeBytes > 0
                    ? formatBytes(stored.sizeBytes)
                    : t.valueUnknown,
              ),
              (
                label: t.infoStoredAdded,
                value: formatTimestamp(stored.addedAt),
              ),
            ],
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
                  width: columns == 1 ? constraints.maxWidth : cellWidth,
                  child: _InfoCell(label: cell.label, value: cell.value),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _screenshotsPanel(BuildContext context, List<String> paths) {
    return _panel(
      context,
      context.strings.customApps.screenshotsPanelTitle,
      Wrap(
        spacing: AppTokens.spaceSM,
        runSpacing: AppTokens.spaceSM,
        children: [
          for (var i = 0; i < paths.length; i++)
            SizedBox(
              width: _screenshotThumbWidth,
              child: AppCard(
                onTap: () => showStoreScreenshots(
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
}

/// תא מידע — תווית קטנה מעל ערך מודגש, על רקע ניטרלי. תאום של זה שבדף
/// התוסף; שניהם קצרים מכדי להצדיק רכיב משותף.
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
