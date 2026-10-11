import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../controllers/error_reports_controller.dart';
import '../controllers/launcher_update_controller.dart';
import '../controllers/library_module_controller.dart';
import '../controllers/otzaria_module_controller.dart';
import '../controllers/plugins_module_controller.dart';
import '../controllers/search_feedback_controller.dart';
import '../flows/library_flows.dart';
import '../flows/otzaria_flows.dart';
import '../services/byte_size.dart';
import '../services/timestamps.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'error_reports_upload_section.dart';

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
    required this.isCancellingDownload,
    required this.isCheckingOnline,
    required this.longTaskRunning,
    required this.onProcessStateChanged,
    required this.onCloseOtzaria,
    required this.onCheckOnline,
    required this.onDownloadAll,
    required this.onCancelDownload,
    required this.onDownloadLauncherUpdate,
    required this.onInstallLauncherUpdate,
    required this.onRequestReindex,
    required this.onGoToOtzaria,
    required this.onGoToLibrary,
    this.readOnly = false,
    this.driveFull = false,
    this.errorReports,
    this.onUploadErrorReports,
    this.searchFeedback,
    this.onUploadSearchFeedback,
  });

  final OtzariaModuleController otzaria;
  final LibraryModuleController library;
  final PluginsModuleController plugins;
  final LauncherUpdateController launcherUpdate;
  final SettingsController settings;
  final bool otzariaIsRunning;
  final bool isDownloading;

  /// המשתמש כבר ביקש לבטל, וההורדה בדרך לצאת — הכפתור אומר "מבטל..." ואינו
  /// מאפשר לחיצה שנייה.
  final bool isCancellingDownload;
  final bool isCheckingOnline;

  /// רצה כרגע הורדה או התקנה. החלפת קובץ ההרצה של הלאנצ'ר מסתיימת ב-`exit(0)`
  /// ולכן אינה מוצעת אז — ראו `AppShell._longTaskRunning`.
  final bool longTaskRunning;

  /// בודקת מחדש אם אוצריא פתוחה ומחזירה את התוצאה הטרייה — [otzariaIsRunning]
  /// כאן הוא הערך מרגע הבנייה, וייתכן שאוצריא נסגרה מאז.
  final Future<bool> Function() onProcessStateChanged;

  /// מבקשת מאוצריא הפתוחה להיסגר ומחזירה אם היא אכן נסגרה — הכפתור שלצד
  /// האזהרה. יושבת ב-`AppShell` כי היא נוגעת בתהליך שמודול האפליקציה מכיר.
  final Future<bool> Function() onCloseOtzaria;
  final Future<void> Function() onCheckOnline;
  final Future<void> Function() onDownloadAll;

  /// מבטל את ההורדה שרצה ומוחק את מה שהיא הביאה — מאשר קודם בדיאלוג.
  final Future<void> Function() onCancelDownload;

  /// שתי הפעולות של עדכון הלאנצ'ר עצמו. מיושמות ב-`AppShell` (הדיאלוגים
  /// שלהן קופצים גם מהבדיקה האוטומטית בעלייה), וכאן רק נקראות.
  final Future<void> Function() onDownloadLauncherUpdate;
  final Future<void> Function() onInstallLauncherUpdate;

  /// מציעה ומוסרת לאוצריא את בקשת עדכון אינדקס החיפוש, כשעדכון מסד השאיר
  /// אותה ממתינה. גם היא מיושמת ב-`AppShell`, מאותו טעם.
  final Future<void> Function() onRequestReindex;

  final VoidCallback onGoToOtzaria;
  final VoidCallback onGoToLibrary;

  final bool readOnly;
  final bool driveFull;

  /// דיווחי טעויות שנאספו לכונן. כפתור ההעלאה יושב בכרטיס ההורדות — המקום
  /// היחיד שבו הלאנצ'ר פונה לרשת.
  final ErrorReportsController? errorReports;
  final Future<void> Function()? onUploadErrorReports;
  final SearchFeedbackController? searchFeedback;
  final Future<void> Function()? onUploadSearchFeedback;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.home;

    return ScreenBody(
      title: t.title,
      children: [
        if (otzariaIsRunning)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: AppCard(
              child: SettingsActionTile.text(
                icon: FluentIcons.warning_24_regular,
                title: t.otzariaRunningTitle,
                subtitle: t.otzariaRunningSubtitle,
                actions: [CloseOtzariaButton(onClose: onCloseOtzaria)],
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
        // כרטיס ההורדה ועדכון הלאנצ'ר מוחלפים בהסבר: שניהם כותבים לכונן.
        if (readOnly)
          _readOnlyNoticeCard(context)
        else
          _onlineCheckCard(context),
        if (!readOnly && _showLauncherUpdateCard) ...[
          const SizedBox(height: AppTokens.spaceLG),
          _launcherUpdateCard(context),
        ],
      ],
    );
  }

  // ── כונן מוגן-כתיבה ──────────────────────────────────────────────────────

  Widget _readOnlyNoticeCard(BuildContext context) {
    final t = context.strings.readOnlyDrive;

    return AppCard(
      child: SettingsActionTile.text(
        icon: FluentIcons.lock_closed_24_regular,
        title: driveFull ? t.bannerTitleDriveFull : t.bannerTitle,
        subtitle: driveFull ? t.bannerSubtitleDriveFull : t.bannerSubtitle,
      ),
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
      statusKind: otzariaStatusKind(c.status),
      statusLabel: otzariaStatusLabel(
        context,
        c.status,
        updateAvailable: common.updateAvailable,
        needsDownload: c.currentVersion == null
            ? t.appNoInstallFound
            : t.appNothingDownloaded,
      ),
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

  bool get _offersLibraryToo =>
      otzaria.currentVersion == null &&
      library.isFreshInstall &&
      library.status == LibraryModuleStatus.updateAvailable;

  Future<void> _confirmAppInstall(BuildContext context) async {
    final t = context.strings.home;
    final withLibrary = _offersLibraryToo;
    final installed = await confirmOtzariaInstall(
      context,
      otzaria: otzaria,
      title: withLibrary ? t.firstInstallDialogTitle : t.appInstallDialogTitle,
      content: withLibrary
          ? t.firstInstallPrompt(
              '${otzaria.latestVersion}',
              '${library.targetVersion}',
            )
          : appInstallPrompt(context, otzaria),
      confirmText: withLibrary ? t.firstInstallConfirm : t.appInstallConfirm,
    );
    if (!withLibrary || !context.mounted) return;
    if (!installed) {
      if (otzaria.currentVersion != null) await library.checkForUpdate();
      return;
    }

    await library.checkForUpdate();
    if (!context.mounted) return;
    await _installLibraryAfterApp(context);
  }

  Future<void> _installLibraryAfterApp(BuildContext context) async {
    final t = context.strings.home;
    while (await onProcessStateChanged()) {
      if (await onCloseOtzaria()) break;
      if (!context.mounted) return;
      final retry = await showTwoActionsDialog(
        context: context,
        title: t.closeOtzariaForLibraryDialogTitle,
        content: t.closeOtzariaForLibraryPrompt,
        confirmText: context.strings.common.retry,
      );
      if (!retry) return;
    }
    if (!context.mounted) return;
    if (library.status != LibraryModuleStatus.updateAvailable) return;

    await applyLibraryAndReport(
      library,
      library.update,
      onRequestReindex: onRequestReindex,
    );
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
      statusLabel: c.semanticConsentRequired
          ? context.strings.libraryDomain.semanticConsentRequired
          : libraryStatusLabel(context, c),
      // עדכון מסד אורך דקות ארוכות; בלי המד כאן האריח אמר "מעדכן" בלבד לכל
      // אורכו, והמשתמש שהתחיל את העדכון מדף הבית לא ידע אם הוא בכלל מתקדם.
      progress: isBusy ? libraryApplyProgressRow(context, c) : null,
      primaryActionText: c.status == LibraryModuleStatus.updateAvailable
          ? (c.isFreshInstall ? common.install : common.update)
          : c.semanticConsentRequired
              ? context.strings.libraryDomain.companionSemanticName
              : null,
      primaryActionIcon: FluentIcons.database_arrow_right_24_regular,
      primaryActionLoading: isBusy,
      onPrimaryAction: c.status == LibraryModuleStatus.updateAvailable
          ? (isDownloading ? null : () => _confirmLibraryUpdate(context))
          : c.semanticConsentRequired
              ? onGoToLibrary
              : null,
      onDetails: onGoToLibrary,
    );
  }

  Future<void> _confirmLibraryUpdate(BuildContext context) =>
      confirmLibraryUpdate(
        context,
        library: library,
        dialogTitle: (strings) => strings.home.libraryUpdateDialogTitle,
        isOtzariaRunning: onProcessStateChanged,
        onRequestReindex: onRequestReindex,
      );

  // ── בדיקת עדכונים ברשת (צדדי) ────────────────────────────────────────────

  Widget _onlineCheckCard(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.home;
    final otzariaChecked = otzaria.onlineCheckedAt != null;
    final libraryChecked = library.onlineCheckedAt != null;
    final pluginsChecked = plugins.onlineCheckedAt != null;
    final everChecked = otzariaChecked || libraryChecked || pluginsChecked;
    // המאוחרת מבין השלוש. קודם הוצג תמיד זמן הבדיקה של אוצריא, גם כשבדיקת
    // הספרייה רצה אחריה — "נבדק לאחרונה" הראה אז זמן מוקדם מהאמת.
    final lastChecked = [
      if (otzariaChecked) otzaria.onlineCheckedAt!,
      if (libraryChecked) library.onlineCheckedAt!,
      if (pluginsChecked) plugins.onlineCheckedAt!,
    ].fold<DateTime?>(
      null,
      (latest, at) => latest == null || at.isAfter(latest) ? at : latest,
    );
    final otzariaOnline = otzariaChecked && otzaria.onlineCheckError == null;
    final libraryOnline = libraryChecked && library.onlineCheckError == null;
    final pluginsOnline = pluginsChecked && plugins.onlineCheckError == null;
    final isOnline = otzariaOnline || libraryOnline || pluginsOnline;
    final hasUpdate = otzaria.hasOnlineUpdate ||
        library.hasOnlineUpdate ||
        plugins.hasOnlineUpdate;

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
      hint: t.onlineCardHint,
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
              // פירוט לכל רכיב שהתחדש. קודם פורטו כאן התוספים בלבד, ולכן
              // עדכון תוכנה או ספרייה נראה בכרטיס כאילו רק תוספים התחדשו.
              ..._onlineDetail(
                context,
                otzariaOnline: otzariaOnline,
                libraryOnline: libraryOnline,
                pluginsOnline: pluginsOnline,
              ),
              if (library.downloadNeedsRetry && !isDownloading)
                InfoErrorRow(
                  message: t.downloadFailedSnack(t.libraryTileTitle),
                  onRetry: settings.settings.downloadsLibrary &&
                          !longTaskRunning &&
                          !isCheckingOnline
                      ? onDownloadAll
                      : null,
                ),
              if (isOnline && hasUpdate) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ActionButton.recommended(
                  text: t.downloadNowButton,
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: isDownloading,
                  onPressed: settings.settings.hasSyncSelection &&
                          !longTaskRunning &&
                          !isCheckingOnline
                      ? () => onDownloadAll()
                      : null,
                ),
              ],
              if (isDownloading) ...[
                const SizedBox(height: AppTokens.spaceMD),
                _downloadProgress(context),
                const SizedBox(height: AppTokens.spaceSM),
                // מוצג אך ורק בזמן שההורדה רצה: היא אורכת דקות ארוכות, וזו
                // הדרך היחידה לעצור אותה בלי לסגור את התוכנה.
                ActionButton.warning(
                  text: isCancellingDownload
                      ? t.cancelDownloadPending
                      : t.cancelDownloadButton,
                  icon: FluentIcons.dismiss_circle_24_regular,
                  onPressed: isCancellingDownload ? null : onCancelDownload,
                ),
              ],
              if (errorReports != null && !readOnly)
                ErrorReportsUploadSection(
                  controller: errorReports!,
                  onUpload: onUploadErrorReports,
                ),
              if (searchFeedback case final feedback? when !readOnly)
                AnimatedBuilder(
                  animation: feedback,
                  builder: (context, _) => feedback.outboxCount == 0
                      ? const SizedBox.shrink()
                      : SettingsActionTile.text(
                          icon: FluentIcons.arrow_upload_24_regular,
                          title: context.strings.libraryDomain
                              .semanticFeedbackUploadTitle,
                          subtitle: context.strings.libraryDomain
                              .semanticFeedbackUploadBody(feedback.outboxCount),
                          actions: [
                            if (feedback.isUploading)
                              ActionButton.warning(
                                text: context.strings.common.cancel,
                                onPressed: feedback.stop,
                              ),
                            ActionButton.neutral(
                              text: context.strings.libraryDomain
                                  .semanticFeedbackUploadAction,
                              isLoading: feedback.isUploading,
                              onPressed: longTaskRunning || feedback.isUploading
                                  ? null
                                  : onUploadSearchFeedback,
                            ),
                          ],
                        ),
                ),
              if (lastChecked != null) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text(
                  t.lastCheckedAt(formatClock(lastChecked)),
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

  /// שורת פירוט לכל רכיב שהתחדש ברשת — גרסה לתוכנה ולספרייה, מניין
  /// לתוספים (אין להם מספר גרסה אחד).
  ///
  /// ואם הורדת הרכיב כבויה בהגדרות — נאמר כאן. בלי זה "הורד עכשיו" מדלג
  /// עליו בשקט, והמשתמש נשאר עם אותה הודעה בדיוק גם אחרי ההורדה.
  List<Widget> _onlineDetail(
    BuildContext context, {
    required bool otzariaOnline,
    required bool libraryOnline,
    required bool pluginsOnline,
  }) {
    final theme = Theme.of(context);
    final t = context.strings.home;
    final s = settings.settings;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final warnStyle = style?.copyWith(color: theme.colorScheme.error);

    final widgets = <Widget>[];
    void line(String text, {bool warn = false}) {
      widgets
        ..add(const SizedBox(height: AppTokens.spaceXS))
        ..add(Text(text, style: warn ? warnStyle : style));
    }

    if (otzariaOnline && otzaria.hasOnlineUpdate) {
      final version = otzaria.onlineUpdateVersion;
      if (version != null) line(t.onlineAppUpdate(version));
      if (!s.syncApp) line(t.onlineAppSyncOff, warn: true);
    }

    if (libraryOnline && library.hasOnlineUpdate) {
      final version = library.onlineUpdateVersion;
      if (version != null) line(t.onlineLibraryUpdate('$version'));
      if (library.onlinePendingCompanions.isNotEmpty ||
          library.onlineSemanticPending) {
        line(t.onlineLibraryCompanions(library.onlinePendingCompanionNames));
      }
      if (!s.downloadsLibrary) line(t.onlineLibrarySyncOff, warn: true);
    }

    final status = plugins.onlineStatus;
    final storeApp = plugins.storeAppOnline;
    if (pluginsOnline && plugins.hasCatalogOnlineUpdate && status != null) {
      if (status.newCount > 0) line(t.onlineNewPlugins(status.newCount));
      if (status.updatedCount > 0) {
        line(t.onlineUpdatedPlugins(status.updatedCount));
      }
      if (status.missingCount > 0) {
        line(t.onlineMissingPlugins(status.missingCount));
      }
      if (status.removedCount > 0) {
        line(t.onlineRemovedPlugins(status.removedCount));
      }
    }
    // תנאי משלה: היא נבדקת מול גיטהאב, ולכן אתר שאינו עונה אינו מעלים
    // אותה — ובלי השורה הזאת "נמצאו עדכונים" היה מופיע בלי שום פירוט.
    if (storeApp != null) line(t.onlineStoreAppUpdate(storeApp.tagName));
    if (plugins.hasOnlineUpdate && !s.syncPlugins) {
      line(t.onlinePluginsSyncOff, warn: true);
    }

    return widgets;
  }

  Widget _downloadProgress(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          otzaria.progress,
          library.progress,
          plugins.progress,
        ]),
        builder: (context, _) => _downloadProgressRow(context),
      );

  Widget _downloadProgressRow(BuildContext context) {
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
        secondaryStage: library.downloadCompanionStage,
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
          t.statusDownloading,
        ),
      LauncherUpdateStatus.installing => (
          StatusKind.working,
          t.statusInstalling,
        ),
      LauncherUpdateStatus.error => (
          StatusKind.error,
          context.strings.common.error,
        ),
      LauncherUpdateStatus.readyToInstall => (
          StatusKind.updateAvailable,
          t.statusReadyToInstall,
        ),
      _ when c.hasOnlineUpdate => (
          StatusKind.updateAvailable,
          t.statusUpdateAvailable,
        ),
      _ => (StatusKind.ok, t.statusUpToDate),
    };

    final detail = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SettingsCard(
      title: t.cardTitle,
      hint: t.cardHint,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(kind: kind, label: label),
              const SizedBox(height: AppTokens.spaceMD),
              Text(t.installedVersion(c.currentVersion), style: detail),
              if (c.hasUpdateReady && c.downloadedVersion != null) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(t.downloadedVersion(c.downloadedVersion!), style: detail),
              ],
              if (c.onlineUpdateVersion case final online?) ...[
                const SizedBox(height: AppTokens.spaceXS),
                Text(t.onlineVersion(online), style: detail),
              ],
              if (c.isDownloading) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ListenableBuilder(
                  listenable: c.progress,
                  builder: (context, _) => InfoProgressRow(
                    stage: t.statusDownloading,
                    progress: (c.downloadTotal ?? 0) > 0
                        ? (c.downloadReceived ?? 0) / c.downloadTotal!
                        : null,
                    detail: formatBytesProgress(
                      c.downloadReceived,
                      c.downloadTotal,
                    ),
                  ),
                ),
              ],
              if (c.hasUpdateReady && c.canInstall) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ActionButton.recommended(
                  text: t.installButton,
                  icon: FluentIcons.arrow_sync_24_regular,
                  isLoading: c.isInstalling,
                  onPressed: c.isInstalling || longTaskRunning
                      ? null
                      : onInstallLauncherUpdate,
                ),
              ],
              if (c.hasUpdateReady && !c.canInstall) ...[
                const SizedBox(height: AppTokens.spaceSM),
                Text(t.installUnavailableNotice, style: detail),
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
    this.progress,
  });

  final IconData icon;
  final String title;
  final StatusKind statusKind;
  final String statusLabel;

  /// מד התקדמות לפעולה ארוכה שרצה כרגע, או `null` כשאין כזו.
  final Widget? progress;
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          StatusChip(kind: statusKind, label: statusLabel),
          if (progress != null) progress!,
          const SizedBox(height: AppTokens.spaceMD),
          if (primaryActionText != null)
            ActionButton.recommended(
              text: primaryActionText!,
              icon: primaryActionIcon,
              isLoading: primaryActionLoading,
              onPressed: onPrimaryAction,
            )
          // "אין פעולה זמינה" נאמר רק כשבאמת אין מה לראות; בזמן שהמד רץ הוא
          // התשובה לשאלה "מה קורה עכשיו".
          else if (progress == null)
            Text(
              context.strings.home.noActionAvailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
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
