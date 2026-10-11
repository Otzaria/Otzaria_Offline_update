import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/library_module_controller.dart';
import '../services/byte_size.dart';
import '../widgets/widgets_exports.dart';

StatusKind libraryStatusKind(LibraryModuleStatus status) => switch (status) {
      LibraryModuleStatus.idle => StatusKind.unknown,
      LibraryModuleStatus.checking => StatusKind.working,
      LibraryModuleStatus.upToDate => StatusKind.ok,
      LibraryModuleStatus.updateAvailable => StatusKind.updateAvailable,
      LibraryModuleStatus.updating => StatusKind.working,
      LibraryModuleStatus.error => StatusKind.error,
      LibraryModuleStatus.needsDownload => StatusKind.needsAction,
      LibraryModuleStatus.needsManualPath => StatusKind.needsAction,
      LibraryModuleStatus.personalTargetElsewhere => StatusKind.needsAction,
    };

String libraryStatusLabel(BuildContext context, LibraryModuleController c) {
  final common = context.strings.common;
  final t = context.strings.home;

  return switch (c.status) {
    LibraryModuleStatus.idle => common.notCheckedYet,
    LibraryModuleStatus.checking => common.checking,
    LibraryModuleStatus.upToDate => common.upToDate,
    LibraryModuleStatus.updateAvailable => switch (c) {
        _ when c.isFreshInstall => t.libraryNotInstalledYet,
        _ when c.companionsOnly =>
          AppL10n.strings.libraryDomain.companionsOnlyPending(
            c.pendingCompanionNames,
          ),
        _ => common.updateAvailable,
      },
    LibraryModuleStatus.updating => t.libraryUpdating,
    LibraryModuleStatus.error => common.error,
    LibraryModuleStatus.needsDownload => t.libraryNothingDownloaded,
    LibraryModuleStatus.needsManualPath => t.libraryNeedsManualPath,
    LibraryModuleStatus.personalTargetElsewhere =>
      t.libraryPersonalOtherMachine,
  };
}

Widget libraryApplyProgressRow(
  BuildContext context,
  LibraryModuleController c,
) =>
    ListenableBuilder(
      listenable: c.progress,
      builder: (context, _) => InfoProgressRow(
        stage: c.stageText ?? context.strings.libraryScreen.updatingProgress,
        progress: c.applyProgress,
        detail: formatBytesProgress(c.applyReceivedBytes, c.applyTotalBytes),
        warning: context.strings.home.doNotRemoveDriveWarning,
      ),
    );

Future<bool> _blockedByRunningOtzaria(
  Future<bool> Function() isOtzariaRunning,
) async {
  if (!await isOtzariaRunning()) return false;
  UiSnack.showError(AppL10n.strings.home.otzariaOpenSnack);
  return true;
}

Future<void> applyLibraryAndReport(
  LibraryModuleController library,
  Future<void> Function() apply, {
  required Future<void> Function() onRequestReindex,
}) async {
  await apply();
  if (library.status == LibraryModuleStatus.upToDate) {
    UiSnack.showSuccess(
      AppL10n.strings.home.libraryUpdatedSnack('${library.localVersion}'),
    );
  }
  await onRequestReindex();
}

Future<void> confirmLibraryUpdate(
  BuildContext context, {
  required LibraryModuleController library,
  required String Function(AppStrings strings) dialogTitle,
  required Future<bool> Function() isOtzariaRunning,
  required Future<void> Function() onRequestReindex,
}) async {
  if (await _blockedByRunningOtzaria(isOtzariaRunning)) return;
  if (!context.mounted) return;
  final home = context.strings.home;

  final c = library;
  final approved = await showTwoActionsDialog(
    context: context,
    title: dialogTitle(context.strings),
    content: switch (c) {
      _ when c.isFreshInstall =>
        home.libraryFreshInstallPrompt('${c.targetVersion}'),
      _ when c.companionsOnly => AppL10n.strings.libraryDomain
          .companionsOnlyPrompt(c.pendingCompanionNames),
      _ => home.libraryUpdatePrompt('${c.localVersion}', '${c.targetVersion}'),
    },
    subtitle: home.doNotRemoveDriveWarning,
    confirmText: home.libraryUpdateConfirm,
  );
  if (!approved) return;

  await applyLibraryAndReport(
    c,
    c.update,
    onRequestReindex: onRequestReindex,
  );
}

Future<void> confirmLibraryFullDownload(
  BuildContext context, {
  required LibraryModuleController library,
  required Future<bool> Function() isOtzariaRunning,
  required Future<void> Function() onRequestReindex,
}) async {
  if (await _blockedByRunningOtzaria(isOtzariaRunning)) return;
  if (!context.mounted) return;
  final t = context.strings.libraryScreen;

  final c = library;
  final size = c.fullDownloadFallbackSize;
  final approved = await showTwoActionsDialog(
    context: context,
    title: t.fullDownloadInsteadDialogTitle,
    content: t.fullDownloadInsteadPrompt(
      size != null && size > 0
          ? formatBytes(size)
          : context.strings.common.unknownValue,
    ),
    subtitle: context.strings.home.doNotRemoveDriveWarning,
    confirmText: context.strings.common.install,
  );
  if (!approved) return;

  await applyLibraryAndReport(
    c,
    c.updateWithFullDownload,
    onRequestReindex: onRequestReindex,
  );
}
