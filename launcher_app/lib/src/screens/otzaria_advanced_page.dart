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

/// "אוצריא — מתקדם": הגרסה, התקנה מחדש, מיקום ההתקנה והתיקייה שבכונן. המצב,
/// "מה חדש" וההתקנה עצמה בבית. הדף אינו נעול; רק שינוי הגרסה מבקש סיסמה.
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

  /// בחירת ערוץ הגרסה נשמרת בהגדרות, כדי שתישאר בין הפעלות.
  final SettingsController settings;

  /// נקרא אחרי שהמשתמש הצביע ידנית על תיקיית ההתקנה — תיקיית התוספים
  /// נגזרת מהנתיב הזה, ולכן צריך לסרוק אותה מחדש.
  final Future<void> Function()? onInstallAdopted;

  /// בורר הערוץ הוא הגדרה שמחוץ למסך ההגדרות, ולכן הוא צריך שער משלו.
  final SaferModeGate? saferMode;

  /// התקנה מחדש של אותה גרסה, במסך המשימה.
  final VoidCallback? onReinstall;

  /// משימה ארוכה רצה במקום אחר — אין התקנה עכשיו.
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
        if (c.hasChannelChoice)
          AppRow(
            key: ShellKeys.appChannel,
            title: t.appChannelTitle,
            subtitle: '${t.appChannelBody}\n'
                '${a.channelPair('${c.stableVersion}', '${c.prereleaseVersion}')}',
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (saferMode?.isLocked ?? false)
                  StatusChip(kind: StatusKind.locked, label: t.lockedChip),
                AppSegmentedControl<bool>(
                  options: [
                    SegmentOption(value: false, label: a.channelStable),
                    SegmentOption(value: true, label: a.channelPrerelease),
                  ],
                  currentValue: c.preferPrerelease,
                  onChanged:
                      _installing ? null : (v) => _setChannel(context, v),
                ),
              ],
            ),
          ),
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

  /// נשמר בהגדרות; `AppSession` מזליג לקונטרולר, שבודק מחדש מהכונן.
  Future<void> _setChannel(BuildContext context, bool preferPrerelease) async {
    final gate = saferMode;
    if (gate != null && gate.isLocked) {
      final unlocked = await showSaferModePasswordDialog(
        context,
        storedPassword: gate.settings.settings.saferModePassword,
        hint: context.strings.saferMode.verifySettingsHint,
      );
      if (!unlocked) return;
      gate.unlock();
    }
    await settings.update(
      settings.settings.copyWith(preferAppPrerelease: preferPrerelease),
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
