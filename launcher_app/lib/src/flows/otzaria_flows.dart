import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/otzaria_module_controller.dart';
import '../widgets/widgets_exports.dart';

String appInstallPrompt(BuildContext context, OtzariaModuleController c) =>
    context.strings.appScreen.installPrompt(
      latestVersion: c.latestVersion,
      currentVersion: c.currentVersion,
      prereleaseNote: c.hasChannelChoice && c.preferPrerelease,
    );

StatusKind otzariaStatusKind(OtzariaModuleStatus status) => switch (status) {
      OtzariaModuleStatus.idle => StatusKind.unknown,
      OtzariaModuleStatus.checking => StatusKind.working,
      OtzariaModuleStatus.upToDate => StatusKind.ok,
      OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
      OtzariaModuleStatus.installing => StatusKind.working,
      OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
      OtzariaModuleStatus.installedIsNewer => StatusKind.ok,
      OtzariaModuleStatus.error => StatusKind.error,
    };

String otzariaStatusLabel(
  BuildContext context,
  OtzariaModuleStatus status, {
  required String updateAvailable,
  required String needsDownload,
}) {
  final common = context.strings.common;

  return switch (status) {
    OtzariaModuleStatus.idle => common.notCheckedYet,
    OtzariaModuleStatus.checking => common.checking,
    OtzariaModuleStatus.upToDate => common.upToDate,
    OtzariaModuleStatus.updateAvailable => updateAvailable,
    OtzariaModuleStatus.installing => common.installing,
    OtzariaModuleStatus.needsDownload => needsDownload,
    OtzariaModuleStatus.installedIsNewer => common.installedIsNewer,
    OtzariaModuleStatus.error => common.error,
  };
}

Future<bool> confirmOtzariaInstall(
  BuildContext context, {
  required OtzariaModuleController otzaria,
  required String title,
  required String content,
  required String confirmText,
}) async {
  final approved = await showTwoActionsDialog(
    context: context,
    title: title,
    content: content,
    confirmText: confirmText,
  );
  if (!approved) return false;
  await otzaria.install();
  final notice = otzaria.noticeMessage;
  if (notice != null) {
    UiSnack.show(notice);
    return false;
  }
  if (otzaria.status != OtzariaModuleStatus.upToDate) return false;
  UiSnack.showSuccess(
    AppL10n.strings.home.appInstalledSnack('${otzaria.currentVersion}'),
  );
  return true;
}
