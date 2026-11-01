import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../controllers/otzaria_module_controller.dart';
import '../services/native_file_dialogs.dart';
import '../services/timestamps.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../shell/shell_keys.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'home/home_view_model.dart' show displayVersion;

class OtzariaAdvancedPage extends StatelessWidget {
  const OtzariaAdvancedPage({
    super.key,
    required this.otzaria,
    required this.settings,
    this.onInstallAdopted,
    this.saferMode,
    this.onReinstall,
    this.busy = false,
  });

  final OtzariaModuleController otzaria;

  final SettingsController settings;

  final Future<void> Function()? onInstallAdopted;

  final SaferModeGate? saferMode;

  final VoidCallback? onReinstall;

  final bool busy;

  bool get _installing => otzaria.status == OtzariaModuleStatus.installing;

  bool get _installed => otzaria.currentVersion != null;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: otzaria,
        builder: (context, _) => ScreenBody(children: [_rows(context)]),
      );

  Widget _rows(BuildContext context) {
    final c = otzaria;
    final t = context.strings.pages;
    final a = context.strings.appScreen;
    final installed = c.currentVersion;
    final canReinstall = c.status == OtzariaModuleStatus.upToDate;
    final launchPath = c.launchPath;
    final downloadedAt = c.lastDownloadedAt;

    return RowsCard(
      key: ShellKeys.appAdvanced,
      children: [
        AppRow(
          key: ShellKeys.appReinstall,
          title: t.appReinstallTitle,
          subtitle: busy && !_installing
              ? t.pageBusyNote
              : canReinstall && installed != null
                  ? t.appReinstallBody(displayVersion(installed))
                  : !_installed
                      ? t.appChipNotInstalled
                      : t.appReinstallUnavailable,
          trailing: ActionButton.neutral(
            text: a.reinstallButton,
            onPressed:
                canReinstall && !busy && !_installing ? onReinstall : null,
          ),
        ),
        AppRow(
          title: t.appLocationTitle,
          subtitle: launchPath == null ? a.noInstallDetected : null,
          trailing: ActionButton.ghost(
            text: a.pickInstallDirButton,
            icon: FluentIcons.folder_open_24_regular,
            onPressed: _installing ? null : () => _pickInstallDir(context),
          ),
          below: launchPath == null
              ? null
              : PathText(p.dirname(launchPath), copyable: true),
        ),
        AppRow(
          title: t.appSourceTitle,
          subtitle: downloadedAt == null
              ? null
              : '${context.strings.common.lastDownloaded}: '
                  '${formatDate(downloadedAt)}',
          below: PathText(c.mirrorDir),
          trailing: CopyPathButton(path: c.mirrorDir),
        ),
      ],
    );
  }

  Future<void> _pickInstallDir(BuildContext context) async {
    final t = context.strings.appScreen;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    final adopted = await otzaria.adoptInstallDir(dir);
    if (adopted) {
      await onInstallAdopted?.call();
      UiSnack.showSuccess(t.installAdoptedSnack);
    } else {
      UiSnack.showError(t.installNotFoundSnack);
    }
  }
}
