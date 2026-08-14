import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_app_form_dialog.dart';

/// פותח את טופס ההוספה. משותף למסך הזה ולכרטיס שבהגדרות — שניהם מוסיפים
/// אותו דבר, ורק הכניסה שונה.
Future<void> openAddCustomApp(
  BuildContext context,
  CustomAppsController controller,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => CustomAppFormDialog(controller: controller),
    );

/// פותח את אותו טופס עצמו על רשומה קיימת. אותו טופס בכוונה: מה שאפשר
/// למלא בהוספה חייב להיות גם מה שאפשר לתקן אחריה.
Future<void> openEditCustomApp(
  BuildContext context,
  CustomAppsController controller,
  CustomAppEntry entry,
) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          CustomAppFormDialog(controller: controller, existing: entry),
    );

/// מסך "תוכנות נוספות" — כרטיס לכל תוכנה שהמשתמש הוסיף.
///
/// הפריט בסרגל הניווט מופיע **רק אחרי שנוספה תוכנה ראשונה** (ראו
/// `AppShell`), ולכן מי שלא משתמש בתכונה הזו לא פוגש אותה בכלל.
class CustomAppsScreen extends StatelessWidget {
  const CustomAppsScreen({super.key, required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return ScreenBody(
      title: t.screenTitle,
      description: t.screenDescription,
      children: [
        for (final app in controller.apps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: _CustomAppCard(controller: controller, app: app),
          ),
        ActionButton.recommended(
          text: t.addButton,
          icon: FluentIcons.add_24_regular,
          onPressed: controller.isBusy
              ? null
              : () => openAddCustomApp(context, controller),
        ),
      ],
    );
  }
}

class _CustomAppCard extends StatelessWidget {
  const _CustomAppCard({required this.controller, required this.app});

  final CustomAppsController controller;
  final CustomAppView app;

  bool get _isDownloading => controller.downloadingId == app.descriptor.id;
  bool get _isFromGithub => app.descriptor.sourceKind == AppSourceKind.github;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final common = context.strings.common;
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
                    Text(
                      app.descriptor.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (app.descriptor.description case final text?)
                      Text(
                        text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.edit_24_regular),
                tooltip: t.editTooltip,
                onPressed: controller.isBusy
                    ? null
                    : () => openEditCustomApp(context, controller, app.entry),
              ),
              IconButton(
                icon: const Icon(FluentIcons.delete_24_regular),
                tooltip: t.removeTooltip,
                onPressed:
                    controller.isBusy ? null : () => _confirmRemove(context),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          StatusChip(kind: _statusKind, label: _installedLabel(context)),
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            _storedLabel(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_onlineLabel(context) case final label?) ...[
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
                  ? (controller.downloadReceived ?? 0) /
                      controller.downloadTotal!
                  : null,
              detail: formatBytesProgress(
                controller.downloadReceived,
                controller.downloadTotal,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              if (app.canInstall)
                ActionButton.recommended(
                  text: common.install,
                  icon: FluentIcons.desktop_arrow_right_24_regular,
                  onPressed: controller.isBusy ? null : () => _install(context),
                ),
              if (app.canLaunch)
                ActionButton.neutral(
                  text: common.launch,
                  icon: FluentIcons.play_24_regular,
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.launch(app.installed!),
                ),
              // הנפילה חזרה כשהזיהוי לא מצא — בדיוק כמו "בחירת מיקום
              // ידנית" של אוצריא. מוצגת רק כשיש מה לחפש.
              if (app.canDetect && !app.canLaunch)
                ActionButton.ghost(
                  text: t.pickLocationButton,
                  icon: FluentIcons.folder_open_24_regular,
                  onPressed:
                      controller.isBusy ? null : () => _pickLocation(context),
                ),
              if (_isFromGithub) ...[
                ActionButton.neutral(
                  text: t.downloadButton,
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: _isDownloading,
                  onPressed: controller.downloadingId != null
                      ? null
                      : () => _download(context),
                ),
                ActionButton.ghost(
                  text: t.checkOnlineButton,
                  icon: FluentIcons.arrow_sync_24_regular,
                  onPressed: () => controller.checkOnline(app.descriptor),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  StatusKind get _statusKind {
    if (!app.canDetect) return StatusKind.unknown;
    if (app.installed == null) return StatusKind.needsAction;
    return StatusKind.ok;
  }

  /// "אינה מותקנת" נאמר **רק** כשבאמת חיפשנו. בלי שם קובץ הרצה התשובה
  /// הנכונה היא "לא ניתן לדעת", וזה לא אותו דבר.
  String _installedLabel(BuildContext context) {
    final t = context.strings.customApps;
    if (!app.canDetect) return t.noDetectRules;

    final installed = app.installed;
    if (installed == null) return t.notInstalled;
    final version = installed.version;
    return version == null
        ? t.installedUnknownVersion
        : t.installedVersion(version);
  }

  String _storedLabel(BuildContext context) {
    final t = context.strings.customApps;
    final stored = app.storedInstaller;
    return stored == null
        ? t.noStoredInstaller
        : t.storedInstaller(stored.version);
  }

  /// מה שנמצא ברשת, כשנבדק. `null` כשלא נבדק — לא ממציאים מצב.
  String? _onlineLabel(BuildContext context) {
    if (!_isFromGithub) return null;
    final t = context.strings.customApps;
    final id = app.descriptor.id;

    if (controller.onlineUnavailable.contains(id)) return t.onlineUnavailable;
    final online = controller.onlineVersions[id];
    if (online == null) return null;
    return online == app.storedInstaller?.version
        ? t.onlineUpToDate
        : t.onlineVersionAvailable(online);
  }

  Future<void> _download(BuildContext context) async {
    final stored = await controller.download(app.descriptor.id);
    if (stored == null) {
      UiSnack.showError(controller.errorMessage ?? '');
      return;
    }
    UiSnack.showSuccess(
      AppL10n.strings.customApps.downloadedSnack(stored.version),
    );
  }

  Future<void> _install(BuildContext context) async {
    final result = await controller.install(app.descriptor.id);
    if (!result.ok) {
      UiSnack.showError(controller.errorMessage ?? '');
      return;
    }
    // ארכיון אינו מותקן — הוא מונח בתיקיית ההורדות, וצריך לומר איפה.
    if (result.archivePath case final path?) {
      UiSnack.showSuccess(
        AppL10n.strings.customApps.archiveInDownloadsSnack(path),
      );
      return;
    }
    UiSnack.showSuccess(
      AppL10n.strings.customApps.installedSnack(app.descriptor.name),
    );
    // מה שנלמד נאמר במפורש: מכאן והלאה הכרטיס יפסיק לומר "לא ניתן לזהות",
    // וזה שינוי שהמשתמש כדאי שיבין מאיפה בא.
    if (result.learnedExeName case final exeName?) {
      UiSnack.show(AppL10n.strings.customApps.learnedDetectionSnack(exeName));
    }
  }

  Future<void> _pickLocation(BuildContext context) async {
    final t = context.strings.customApps;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    if (await controller.adoptInstallDir(app.descriptor, dir)) {
      UiSnack.showSuccess(AppL10n.strings.customApps.locationAdoptedSnack(dir));
      return;
    }
    UiSnack.showError(AppL10n.strings.customApps.locationNotFoundSnack);
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final t = context.strings.customApps;
    final approved = await showWarningDialog(
      context: context,
      title: t.removeDialogTitle,
      content: t.removeDialogContent(app.descriptor.name),
      confirmText: t.removeDialogConfirm,
    );
    if (!approved) return;

    if (await controller.remove(app.descriptor.id)) {
      UiSnack.show(
        AppL10n.strings.customApps.removedSnack(app.descriptor.name),
      );
      return;
    }
    UiSnack.showError(controller.errorMessage ?? '');
  }
}
