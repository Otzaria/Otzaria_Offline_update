import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/library_module_controller.dart';
import '../services/byte_size.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'home_screen.dart';

/// מסך עדכון הספרייה — מציג את ה-DB שזוהה בפועל ומחיל עליו עדכון מהתיקייה
/// שלצד התוכנה. אין כאן בחירת מקור: המקור תמיד אותה תיקייה.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.otzariaIsRunning,
    required this.isDownloading,
    required this.onProcessStateChanged,
  });

  final LibraryModuleController library;
  final bool otzariaIsRunning;
  final bool isDownloading;
  final Future<void> Function() onProcessStateChanged;

  bool get _isBusy =>
      library.status == LibraryModuleStatus.updating || isDownloading;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.libraryScreen;

    return ScreenBody(
      title: t.title,
      description: t.description,
      children: [
        _stateCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב המסד ──────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = library;
    final t = context.strings.libraryScreen;

    return SettingsCard(
      title: t.stateCardTitle,
      children: [
        InfoStatusRow(
          icon: FluentIcons.database_24_regular,
          title: t.stateRowTitle,
          kind: libraryStatusKind(c.status),
          label: libraryStatusLabel(context, c),
        ),
        SettingsActionTile.path(
          icon: FluentIcons.document_24_regular,
          title: t.dbFileTitle,
          path: c.dbPath,
          placeholder: t.dbFileMissing,
          actions: [
            ActionButton.neutral(
              text: t.pickDbButton,
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickDbFile(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.number_symbol_24_regular,
          title: t.localVersionTitle,
          subtitle:
              c.localVersion?.toString() ?? context.strings.common.unknownValue,
          subtitleLtr: c.localVersion != null,
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: t.targetVersionTitle,
          subtitle: c.targetVersion?.toString() ??
              (c.status == LibraryModuleStatus.needsDownload
                  ? t.targetVersionNothingDownloaded
                  : t.targetVersionUnknown),
          subtitleLtr: c.targetVersion != null,
        ),
        if (otzariaIsRunning)
          SettingsActionTile.text(
            icon: FluentIcons.warning_24_regular,
            title: t.otzariaRunningTitle,
            subtitle: t.otzariaRunningSubtitle,
          ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == LibraryModuleStatus.updating)
          InfoProgressRow(
            stage: c.stageText ?? t.updatingProgress,
            progress: c.applyProgress,
            detail: formatBytesProgress(
              c.applyReceivedBytes,
              c.applyTotalBytes,
            ),
          ),
        CardActionsRow(
          actions: [
            RecheckButton(onPressed: _isBusy ? null : c.checkForUpdate),
            ActionButton.recommended(
              text: t.installUpdateButton,
              icon: FluentIcons.database_arrow_right_24_regular,
              isLoading: c.status == LibraryModuleStatus.updating,
              onPressed: c.status == LibraryModuleStatus.updateAvailable
                  ? () => _confirmUpdate(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDbFile(BuildContext context) async {
    final t = context.strings.libraryScreen;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: t.pickDbDialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await library.setCustomDbPath(path);
    UiSnack.showSuccess(t.dbPathUpdatedSnack);
  }

  Future<void> _confirmUpdate(BuildContext context) async {
    await onProcessStateChanged();
    if (!context.mounted) return;
    final home = context.strings.home;
    if (otzariaIsRunning) {
      UiSnack.showError(home.otzariaOpenSnack);
      return;
    }

    final c = library;
    final approved = await showTwoActionsDialog(
      context: context,
      title: context.strings.libraryScreen.updateDialogTitle,
      content: c.isFreshInstall
          ? home.libraryFreshInstallPrompt('${c.targetVersion}')
          : home.libraryUpdatePrompt('${c.localVersion}', '${c.targetVersion}'),
      confirmText: home.libraryUpdateConfirm,
    );
    if (!approved) return;

    await c.update();
    if (c.status == LibraryModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.libraryUpdatedSnack('${c.localVersion}'),
      );
    }
  }

  // ── התיקייה שממנה מעדכנים ─────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = library;
    final t = context.strings.libraryScreen;

    return SettingsCard(
      title: t.sourceCardTitle,
      subtitle: t.sourceCardSubtitle,
      children: [
        SettingsActionTile.path(
          icon: FluentIcons.folder_24_regular,
          title: t.sourceDirTitle,
          path: c.mirrorDir,
          placeholder: context.strings.common.emptyValue,
        ),
        InfoStatusRow(
          icon: FluentIcons.arrow_download_24_regular,
          title: t.mirrorContentTitle,
          kind: switch (c.status) {
            LibraryModuleStatus.needsDownload => StatusKind.needsAction,
            LibraryModuleStatus.error => StatusKind.error,
            _ => StatusKind.ok,
          },
          label: switch (c.status) {
            LibraryModuleStatus.needsDownload => t.mirrorEmpty,
            LibraryModuleStatus.error => t.mirrorUnreadable,
            _ => c.targetVersion != null
                ? t.mirrorHasVersion('${c.targetVersion}')
                : t.mirrorPresent,
          },
        ),
        if (c.lastDownloadedAt != null)
          SettingsActionTile.text(
            icon: FluentIcons.history_24_regular,
            title: context.strings.common.lastDownloaded,
            subtitle: c.lastDownloadedAt!.toLocal().toString().split('.').first,
          ),
      ],
    );
  }
}
