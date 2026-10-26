import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../controllers/launcher_update_controller.dart';
import '../../self_update/launcher_changelog.dart';
import '../../services/byte_size.dart';
import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/widgets_exports.dart';

/// "עדכון הכלי הזה": הגרסה הפתוחה מול החדשה, מה חדש ופעולה אחת לפי המצב.
/// גם "אודות" בהגדרות מוביל לכאן.
class LauncherUpdatePage extends StatelessWidget {
  const LauncherUpdatePage({
    super.key,
    required this.controller,
    required this.onDownload,
    required this.onInstall,
    required this.onOpenFolder,
    this.onRestartElevated,
    this.readOnly = false,
    this.busy = false,
    this.onCheck,
    this.checking = false,
  });

  final LauncherUpdateController controller;
  final VoidCallback onDownload;
  final VoidCallback onInstall;

  /// התיקייה בכונן שבה יושבת הגרסה שהורדה — להחלפה ידנית.
  final VoidCallback onOpenFolder;

  /// `null` — אין הפעלה כמנהל (לא Windows, או שהיציאה כבר ממתינה).
  final VoidCallback? onRestartElevated;

  /// כונן מוגן: אין לאן להוריד.
  final bool readOnly;

  /// משימה ארוכה רצה — ההתקנה סוגרת את הכלי, ולכן היא ממתינה לסופה.
  final bool busy;

  /// "בדוק עכשיו" של הבית — כשעוד לא נבדק. `null` — חסום בזמן משימה.
  final VoidCallback? onCheck;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.pages;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final ready = c.hasUpdateReady;
        final version = ready ? c.downloadedVersion : c.onlineUpdateVersion;
        final notes = ready ? c.downloadedWhatsNew : c.onlineWhatsNew;
        return ScreenBody(
          title: t.selfTitle,
          description: t.selfDescription,
          children: [
            _statusCard(context),
            if (version != null && ReleaseNotesCard.hasNotes(notes)) ...[
              SectionLabel(t.selfWhatsNew(version)),
              ReleaseNotesCard(markdown: notes),
            ],
          ],
        );
      },
    );
  }

  Widget _statusCard(BuildContext context) {
    final c = controller;
    final t = context.strings.pages;
    final g = context.strings.guide;
    final u = context.strings.launcherUpdate;
    final cs = Theme.of(context).colorScheme;
    final sub = AppTextStyles.rowSub.copyWith(color: cs.onSurfaceVariant);
    final ready = c.hasUpdateReady;
    final online = !ready && c.hasOnlineUpdate;
    final version = ready ? c.downloadedVersion : c.onlineUpdateVersion;
    final error = c.errorMessage;
    final manual = ready && !c.canInstall;
    final size = online ? c.onlineRelease?.sizeBytes : null;

    final (kind, label) = switch (c.status) {
      // מה שקורה נאמר בשורת ההתקדמות; השבב אומר מה יש.
      LauncherUpdateStatus.downloading when version != null => (
          StatusKind.updateAvailable,
          t.selfChipOnline(version),
        ),
      LauncherUpdateStatus.downloading => (
          StatusKind.working,
          g.launcherDownloading,
        ),
      LauncherUpdateStatus.installing => (StatusKind.working, t.selfInstalling),
      _ when ready && version != null => (
          StatusKind.updateAvailable,
          t.selfChipOnDrive(version),
        ),
      _ when online && version != null => (
          StatusKind.updateAvailable,
          t.selfChipOnline(version),
        ),
      LauncherUpdateStatus.error => (StatusKind.error, g.chipAttention),
      LauncherUpdateStatus.idle => (
          StatusKind.unknown,
          context.strings.common.notCheckedYet,
        ),
      _ => (StatusKind.ok, t.selfChipUpToDate),
    };

    final Widget? primary;
    if (c.needsElevation && onRestartElevated != null) {
      primary = ActionButton.recommended(
        key: ShellKeys.statusPrimary,
        text: context.strings.elevation.bannerConfirm,
        icon: FluentIcons.shield_checkmark_24_regular,
        onPressed: onRestartElevated,
      );
    } else if (manual) {
      primary = ActionButton.recommended(
        key: ShellKeys.statusPrimary,
        text: t.selfOpenFolder,
        icon: FluentIcons.folder_open_24_regular,
        onPressed: onOpenFolder,
      );
    } else if (ready) {
      primary = ActionButton.recommended(
        key: ShellKeys.statusPrimary,
        text: error == null ? u.installButton : context.strings.common.retry,
        onPressed: busy || c.isInstalling ? null : onInstall,
      );
    } else if (online && !c.isDownloading) {
      primary = ActionButton.recommended(
        key: ShellKeys.statusPrimary,
        text:
            error == null ? t.selfDownloadButton : context.strings.common.retry,
        onPressed: busy || readOnly ? null : onDownload,
      );
    } else if (c.status == LauncherUpdateStatus.idle) {
      primary = ActionButton.neutral(
        key: ShellKeys.statusPrimary,
        text: g.checkNowLink,
        icon: FluentIcons.arrow_sync_24_regular,
        spinning: checking,
        onPressed: checking ? null : onCheck,
      );
    } else {
      primary = null;
    }

    return StatusCard(
      logo: Image.asset(
        'assets/images/otzaria_logo.png',
        width: 28,
        height: 28,
        semanticLabel: context.strings.shell.otzariaLogoLabel,
      ),
      title: context.strings.shell.appTitle,
      chip: StatusChip(
        kind: kind,
        label: label,
        icon: kind == StatusKind.updateAvailable
            ? FluentIcons.sparkle_16_regular
            : null,
      ),
      values: [
        StatusValue(
          label: t.selfCurrentVersion,
          value: c.currentVersion,
          ltr: true,
        ),
        if (version != null)
          StatusValue(
            label: t.selfNewVersion,
            value: version,
            ltr: true,
            meta: size == null || size <= 0 ? null : formatBytes(size),
          ),
      ],
      extra: [
        if (c.isDownloading)
          ListenableBuilder(
            listenable: c.progress,
            builder: (context, _) {
              final received = c.downloadReceived;
              final total = c.downloadTotal;
              final fraction = received != null && total != null && total > 0
                  ? (received / total).clamp(0.0, 1.0)
                  : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fraction == null
                        ? g.launcherDownloading
                        : t.selfDownloading((fraction * 100).floor()),
                    style: sub,
                  ),
                  const SizedBox(height: 8),
                  AppProgressBar(thin: true, value: fraction),
                ],
              );
            },
          ),
        if (c.isInstalling)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.selfInstalling, style: sub),
              const SizedBox(height: 8),
              const AppProgressBar(thin: true),
            ],
          ),
        if (c.needsElevation)
          NoticeBanner(
            leading: const IconTile(
              icon: FluentIcons.shield_checkmark_24_regular,
              size: IconTileSize.sm,
            ),
            title: t.selfAdminTitle,
            body: t.selfAdminBody,
          )
        else if (error != null)
          NoticeBanner(
            kind: NoticeKind.warning,
            leading: const IconTile(
              icon: FluentIcons.warning_24_regular,
              size: IconTileSize.sm,
              tone: IconTileTone.error,
            ),
            title: t.selfErrorTitle,
            // הסיבה הטכנית (סטטוס, חריג) נשארת בפרטים וביומן.
            body: '${switch (c.failure) {
              LauncherUpdateFailure.install => t.selfInstallFailed,
              LauncherUpdateFailure.check => t.selfCheckFailed,
              _ => t.selfDownloadFailed,
            }}\n'
                '${t.selfErrorKeepsWorking}',
            actions: [
              ActionButton.ghost(
                text: context.strings.common.errorDetailsButton,
                size: ActionButtonSize.sm,
                onPressed: () => showSingleActionDialog(
                  context: context,
                  title: context.strings.common.errorDetailsTitle,
                  content: error,
                  confirmText: context.strings.common.close,
                ),
              ),
            ],
          ),
        if (manual)
          NoticeBanner(
            kind: NoticeKind.inCard,
            leading: const IconTile(
              icon: FluentIcons.info_24_regular,
              size: IconTileSize.sm,
            ),
            title: t.selfManualTitle,
            body: u.installUnavailableNotice,
            below: PathText(c.mirrorDir),
          ),
        if (online && readOnly) Text(t.selfReadOnly, style: sub),
        if (busy && (ready || online)) Text(u.busyNotice, style: sub),
      ],
      actions: [if (primary != null) primary],
      endActions: [
        ActionButton.ghost(
          key: const ValueKey('launcher.changelog'),
          text: u.changelogButton,
          icon: FluentIcons.history_24_regular,
          onPressed: () => unawaited(_showChangelog(context)),
        ),
      ],
    );
  }

  /// יומן השינויים המלא, מהעותק שנארז בתוכנה — בלי רשת.
  Future<void> _showChangelog(BuildContext context) async {
    String? changelog;
    try {
      changelog = await rootBundle.loadString(launcherChangelogAsset);
    } catch (_) {
      changelog = null;
    }
    if (!context.mounted) return;
    final t = context.strings.launcherUpdate;
    await showSingleActionDialog(
      context: context,
      title: t.changelogDialogTitle,
      confirmText: context.strings.common.close,
      customContent: WhatsNewView(
        markdown: changelog,
        emptyText: t.changelogNotFound,
      ),
    );
  }
}
