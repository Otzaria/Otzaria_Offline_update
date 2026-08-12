import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/launcher_update_controller.dart';
import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../services/byte_size.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'otzaria_screen.dart';

/// דף הבית — שני אריחים בלבד: עדכון/התקנת תוכנת אוצריא, ועדכון הספרייה.
/// כל פרט טכני נוסף (סנכרון, נתיבים, מספרי גרסה) נמצא במסכים המפורטים
/// ("תוכנה"/"ספרייה") או בהגדרות — כאן רק "יש עדכון? לחצו."
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.otzaria,
    required this.library,
    required this.plugins,
    required this.launcherUpdate,
    required this.settings,
    required this.otzariaIsRunning,
    required this.isDownloading,
    required this.isCheckingOnline,
    required this.onProcessStateChanged,
    required this.onCheckOnline,
    required this.onDownloadAll,
    required this.onDownloadLauncherUpdate,
    required this.onInstallLauncherUpdate,
    required this.onRequestReindex,
    required this.onGoToOtzaria,
    required this.onGoToLibrary,
  });

  final OtzariaModuleController otzaria;
  final LibraryModuleController library;
  final PluginsModuleController plugins;
  final LauncherUpdateController launcherUpdate;
  final SettingsController settings;
  final bool otzariaIsRunning;
  final bool isDownloading;
  final bool isCheckingOnline;

  /// בודקת מחדש אם אוצריא פתוחה ומחזירה את התוצאה הטרייה — [otzariaIsRunning]
  /// כאן הוא הערך מרגע הבנייה, וייתכן שאוצריא נסגרה מאז.
  final Future<bool> Function() onProcessStateChanged;
  final Future<void> Function() onCheckOnline;
  final Future<void> Function() onDownloadAll;

  /// שתי הפעולות של עדכון הלאנצ'ר עצמו. מיושמות ב-`AppShell` (הדיאלוגים
  /// שלהן קופצים גם מהבדיקה האוטומטית בעלייה), וכאן רק נקראות.
  final Future<void> Function() onDownloadLauncherUpdate;
  final Future<void> Function() onInstallLauncherUpdate;

  /// מציעה ומוסרת לאוצריא את בקשת עדכון אינדקס החיפוש, כשעדכון מסד השאיר
  /// אותה ממתינה. גם היא מיושמת ב-`AppShell`, מאותו טעם.
  final Future<void> Function() onRequestReindex;

  final VoidCallback onGoToOtzaria;
  final VoidCallback onGoToLibrary;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.home;

    return ScreenBody(
      title: t.title,
      description: t.description,
      children: [
        if (otzariaIsRunning)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: AppCard(
              child: SettingsActionTile.text(
                icon: FluentIcons.warning_24_regular,
                title: t.otzariaRunningTitle,
                subtitle: t.otzariaRunningSubtitle,
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final otzariaTile = _otzariaTile(context);
            final libraryTile = _libraryTile(context);

            if (constraints.maxWidth < 560) {
              return Column(
                children: [
                  otzariaTile,
                  const SizedBox(height: AppTokens.spaceMD),
                  libraryTile,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: otzariaTile),
                const SizedBox(width: AppTokens.spaceMD),
                Expanded(child: libraryTile),
              ],
            );
          },
        ),
        const SizedBox(height: AppTokens.spaceLG),
        _onlineCheckCard(context),
        if (_showLauncherUpdateCard) ...[
          const SizedBox(height: AppTokens.spaceLG),
          _launcherUpdateCard(context),
        ],
      ],
    );
  }

  // ── אריח תוכנת אוצריא ────────────────────────────────────────────────────

  Widget _otzariaTile(BuildContext context) {
    final c = otzaria;
    final isBusy = c.status == OtzariaModuleStatus.installing;
    final t = context.strings.home;
    final common = context.strings.common;

    return _HomeTile(
      icon: FluentIcons.desktop_24_regular,
      title: t.appTileTitle,
      statusKind: switch (c.status) {
        OtzariaModuleStatus.idle => StatusKind.unknown,
        OtzariaModuleStatus.checking => StatusKind.working,
        OtzariaModuleStatus.upToDate => StatusKind.ok,
        OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
        OtzariaModuleStatus.installing => StatusKind.working,
        OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
        OtzariaModuleStatus.error => StatusKind.error,
      },
      statusLabel: switch (c.status) {
        OtzariaModuleStatus.idle => common.notCheckedYet,
        OtzariaModuleStatus.checking => common.checking,
        OtzariaModuleStatus.upToDate => common.upToDate,
        OtzariaModuleStatus.updateAvailable => common.updateAvailable,
        OtzariaModuleStatus.installing => common.installing,
        OtzariaModuleStatus.needsDownload => c.currentVersion == null
            ? t.appNoInstallFound
            : t.appNothingDownloaded,
        OtzariaModuleStatus.error => common.error,
      },
      primaryActionText: switch (c.status) {
        OtzariaModuleStatus.updateAvailable => common.install,
        _ => c.canLaunch ? common.launch : null,
      },
      primaryActionIcon: switch (c.status) {
        OtzariaModuleStatus.updateAvailable =>
          FluentIcons.desktop_arrow_right_24_regular,
        _ => FluentIcons.play_24_regular,
      },
      primaryActionLoading: isBusy,
      onPrimaryAction: switch (c.status) {
        OtzariaModuleStatus.updateAvailable => () => _confirmAppInstall(
              context,
            ),
        _ => c.canLaunch ? c.launch : null,
      },
      onDetails: onGoToOtzaria,
    );
  }

  Future<void> _confirmAppInstall(BuildContext context) async {
    final t = context.strings.home;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.appInstallDialogTitle,
      content: appInstallPrompt(context, otzaria),
      confirmText: t.appInstallConfirm,
    );
    if (!approved) return;
    await otzaria.install();
    if (otzaria.status == OtzariaModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.appInstalledSnack('${otzaria.currentVersion}'),
      );
    }
  }

  // ── אריח הספרייה ──────────────────────────────────────────────────────────

  Widget _libraryTile(BuildContext context) {
    final c = library;
    final isBusy = c.status == LibraryModuleStatus.updating;
    final common = context.strings.common;

    return _HomeTile(
      icon: FluentIcons.library_24_regular,
      title: context.strings.home.libraryTileTitle,
      statusKind: libraryStatusKind(c.status),
      statusLabel: libraryStatusLabel(context, c),
      primaryActionText: c.status == LibraryModuleStatus.updateAvailable
          ? (c.isFreshInstall ? common.install : common.update)
          : null,
      primaryActionIcon: FluentIcons.database_arrow_right_24_regular,
      primaryActionLoading: isBusy,
      onPrimaryAction: c.status == LibraryModuleStatus.updateAvailable
          ? () => _confirmLibraryUpdate(context)
          : null,
      onDetails: onGoToLibrary,
    );
  }

  Future<void> _confirmLibraryUpdate(BuildContext context) async {
    // בודקים עכשיו ולא מסתמכים על [otzariaIsRunning]: אם אוצריא נסגרה מאז
    // הבדיקה האחרונה, ההסתמכות על הערך הלכוד הייתה חוסמת את העדכון עד
    // להפעלה מחדש של הלאנצ'ר.
    if (await onProcessStateChanged()) {
      UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
      return;
    }
    if (!context.mounted) return;
    final t = context.strings.home;

    final c = library;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.libraryUpdateDialogTitle,
      content: c.isFreshInstall
          ? t.libraryFreshInstallPrompt('${c.targetVersion}')
          : t.libraryUpdatePrompt('${c.localVersion}', '${c.targetVersion}'),
      confirmText: t.libraryUpdateConfirm,
    );
    if (!approved) return;

    await c.update();
    if (c.status == LibraryModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.libraryUpdatedSnack('${c.localVersion}'),
      );
    }
    // המסד התחלף, ולכן אינדקס החיפוש של אוצריא מיושן — מציעים לתקן מיד.
    await onRequestReindex();
  }

  // ── בדיקת עדכונים ברשת (צדדי) ────────────────────────────────────────────

  Widget _onlineCheckCard(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.home;
    final otzariaChecked = otzaria.onlineCheckedAt != null;
    final libraryChecked = library.onlineCheckedAt != null;
    final everChecked = otzariaChecked || libraryChecked;
    final otzariaOnline = otzariaChecked && otzaria.onlineCheckError == null;
    final libraryOnline = libraryChecked && library.onlineCheckError == null;
    final isOnline = otzariaOnline || libraryOnline;
    final hasUpdate = otzaria.hasOnlineUpdate || library.hasOnlineUpdate;

    final StatusKind kind;
    final String label;
    if (isCheckingOnline) {
      kind = StatusKind.working;
      label = t.onlineChecking;
    } else if (!everChecked) {
      kind = StatusKind.unknown;
      label = t.onlineNeverChecked;
    } else if (!isOnline) {
      kind = StatusKind.unknown;
      label = t.onlineOffline;
    } else if (hasUpdate) {
      kind = StatusKind.updateAvailable;
      label = t.onlineHasUpdates;
    } else {
      kind = StatusKind.ok;
      label = t.onlineNoUpdates;
    }

    return SettingsCard(
      title: t.onlineCardTitle,
      subtitle: t.onlineCardSubtitle,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusChip(kind: kind, label: label),
                  const Spacer(),
                  ActionButton.neutral(
                    text: t.checkForUpdatesButton,
                    icon: FluentIcons.arrow_sync_24_regular,
                    isLoading: isCheckingOnline,
                    onPressed: isCheckingOnline ? null : () => onCheckOnline(),
                  ),
                ],
              ),
              if (isOnline && hasUpdate) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ActionButton.recommended(
                  text: t.downloadNowButton,
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: isDownloading,
                  onPressed:
                      settings.settings.hasSyncSelection && !isDownloading
                          ? () => onDownloadAll()
                          : null,
                ),
              ],
              if (isDownloading) ...[
                const SizedBox(height: AppTokens.spaceMD),
                _downloadProgress(context),
              ],
              if (otzaria.onlineCheckedAt != null ||
                  library.onlineCheckedAt != null) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text(
                  t.lastCheckedAt(
                    _formatTime(
                      otzaria.onlineCheckedAt ?? library.onlineCheckedAt!,
                    ),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// שורת התקדמות אחת לרכיב שמוריד כרגע — ההורדות רצות בטור, ולכן לכל
  /// היותר אחת מהן פעילה.
  Widget _downloadProgress(BuildContext context) {
    final t = context.strings.home;

    if (otzaria.downloadStatus == OtzariaDownloadStatus.downloading) {
      final received = otzaria.downloadReceived;
      final total = otzaria.downloadTotal;
      return InfoProgressRow(
        stage: otzaria.downloadStage ?? t.downloadingApp,
        progress: (received != null && total != null && total > 0)
            ? received / total
            : null,
        detail: formatBytesProgress(received, total),
      );
    }
    if (library.downloadStatus == MirrorDownloadStatus.downloading) {
      return InfoProgressRow(
        stage: library.downloadStage ?? t.downloadingLibrary,
        progress: library.downloadProgress,
        detail: formatBytesProgress(
          library.downloadReceivedBytes,
          library.downloadTotalBytes,
        ),
      );
    }
    if (plugins.status == PluginsModuleStatus.syncing) {
      return InfoProgressRow(
        stage: plugins.syncMessage ?? t.downloadingPlugins,
        progress: plugins.syncProgress,
      );
    }
    return InfoProgressRow(stage: t.downloadStarting);
  }

  // ── עדכון הלאנצ'ר עצמו ───────────────────────────────────────────────────

  /// הכרטיס מוצג רק כשיש בו מה לומר. בשגרה — כשהתוכנה מעודכנת — הוא נעדר,
  /// ומספר הגרסה נמצא בהגדרות; דף הבית הוא "יש עדכון? לחצו", לא לוח מכשירים.
  bool get _showLauncherUpdateCard {
    final c = launcherUpdate;
    return c.hasOnlineUpdate ||
        c.hasUpdateReady ||
        c.isDownloading ||
        c.isInstalling ||
        c.status == LauncherUpdateStatus.error;
  }

  Widget _launcherUpdateCard(BuildContext context) {
    final theme = Theme.of(context);
    final c = launcherUpdate;
    final t = context.strings.launcherUpdate;

    final (StatusKind kind, String label) = switch (c.status) {
      LauncherUpdateStatus.downloading => (
          StatusKind.working,
          t.statusDownloading
        ),
      LauncherUpdateStatus.installing => (
          StatusKind.working,
          t.statusInstalling
        ),
      LauncherUpdateStatus.error => (
          StatusKind.error,
          context.strings.common.error
        ),
      LauncherUpdateStatus.readyToInstall => (
          StatusKind.updateAvailable,
          t.statusReadyToInstall
        ),
      _ when c.hasOnlineUpdate => (
          StatusKind.updateAvailable,
          t.statusUpdateAvailable
        ),
      _ => (StatusKind.ok, t.statusUpToDate),
    };

    final newest = c.newestKnownVersion;
    final detail = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return SettingsCard(
      title: t.cardTitle,
      subtitle: t.cardSubtitle,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(kind: kind, label: label),
              const SizedBox(height: AppTokens.spaceMD),
              Text(t.installedVersion(c.currentVersion), style: detail),
              if (newest != null) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(
                  c.hasUpdateReady
                      ? t.downloadedVersion(newest)
                      : t.onlineVersion(newest),
                  style: detail,
                ),
              ],
              if (c.isDownloading) ...[
                const SizedBox(height: AppTokens.spaceMD),
                InfoProgressRow(
                  stage: t.statusDownloading,
                  progress: (c.downloadTotal ?? 0) > 0
                      ? (c.downloadReceived ?? 0) / c.downloadTotal!
                      : null,
                  detail:
                      formatBytesProgress(c.downloadReceived, c.downloadTotal),
                ),
              ],
              // ההתקנה זמינה גם בלי רשת, ולכן היא מוצגת לפני ההורדה: במחשב
              // המנותק זו הפעולה היחידה שאפשר בכלל ללחוץ עליה.
              if (c.hasUpdateReady && c.canInstall) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ActionButton.recommended(
                  text: t.installButton,
                  icon: FluentIcons.arrow_sync_24_regular,
                  isLoading: c.isInstalling,
                  onPressed: c.isInstalling ? null : onInstallLauncherUpdate,
                ),
              ],
              if (c.hasOnlineUpdate) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ActionButton.neutral(
                  text: t.downloadButton,
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: c.isDownloading,
                  onPressed: c.isDownloading || isDownloading
                      ? null
                      : onDownloadLauncherUpdate,
                ),
              ],
              // גם כשהמצב חזר ל"מוכן להתקנה" אחרי כשל התקנה — ההודעה היא מה
              // שמסביר למה הכפתור עדיין שם.
              if (c.errorMessage != null) ...[
                const SizedBox(height: AppTokens.spaceSM),
                InfoErrorRow(message: c.errorMessage!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _formatTime(DateTime time) {
    final t = time.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

// ── תרגום מצב הספרייה לתצוגה — משותף לדף הבית ולמסך הספרייה ──────────────────

StatusKind libraryStatusKind(LibraryModuleStatus status) => switch (status) {
      LibraryModuleStatus.idle => StatusKind.unknown,
      LibraryModuleStatus.checking => StatusKind.working,
      LibraryModuleStatus.upToDate => StatusKind.ok,
      LibraryModuleStatus.updateAvailable => StatusKind.updateAvailable,
      LibraryModuleStatus.updating => StatusKind.working,
      LibraryModuleStatus.error => StatusKind.error,
      LibraryModuleStatus.needsDownload => StatusKind.needsAction,
      LibraryModuleStatus.needsManualPath => StatusKind.needsAction,
    };

String libraryStatusLabel(BuildContext context, LibraryModuleController c) {
  final common = context.strings.common;
  final t = context.strings.home;

  return switch (c.status) {
    LibraryModuleStatus.idle => common.notCheckedYet,
    LibraryModuleStatus.checking => common.checking,
    LibraryModuleStatus.upToDate => common.upToDate,
    LibraryModuleStatus.updateAvailable =>
      c.isFreshInstall ? t.libraryNotInstalledYet : common.updateAvailable,
    LibraryModuleStatus.updating => t.libraryUpdating,
    LibraryModuleStatus.error => common.error,
    LibraryModuleStatus.needsDownload => t.libraryNothingDownloaded,
    LibraryModuleStatus.needsManualPath => t.libraryNeedsManualPath,
  };
}

// ── אריח בית — עיצוב אחיד לשני הרכיבים ────────────────────────────────────────

/// אריח גדול אחד בדף הבית: אייקון, כותרת, מצב, פעולה עיקרית (אם יש), וקישור
/// למסך המפורט. הפעולה העיקרית תמיד ברורה מאליה (הפעלה/התקנה/עדכון) —
/// כל שאר הפרטים (גרסאות, נתיבים) נמצאים מעבר לקישור "פרטים נוספים".
class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.title,
    required this.statusKind,
    required this.statusLabel,
    required this.primaryActionText,
    required this.primaryActionIcon,
    required this.primaryActionLoading,
    required this.onPrimaryAction,
    required this.onDetails,
  });

  final IconData icon;
  final String title;
  final StatusKind statusKind;
  final String statusLabel;
  final String? primaryActionText;
  final IconData primaryActionIcon;
  final bool primaryActionLoading;
  final VoidCallback? onPrimaryAction;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Icon(icon, color: cs.onSecondaryContainer, size: 26),
              ),
              const SizedBox(width: AppTokens.spaceMD),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          StatusChip(kind: statusKind, label: statusLabel),
          const SizedBox(height: AppTokens.spaceMD),
          if (primaryActionText != null)
            ActionButton.recommended(
              text: primaryActionText!,
              icon: primaryActionIcon,
              isLoading: primaryActionLoading,
              onPressed: onPrimaryAction,
            )
          else
            Text(
              context.strings.home.noActionAvailable,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: AppTokens.spaceSM),
          ActionButton.ghost(
            text: context.strings.home.moreDetails,
            icon: context.forwardArrowIcon,
            onPressed: onDetails,
          ),
        ],
      ),
    );
  }
}
