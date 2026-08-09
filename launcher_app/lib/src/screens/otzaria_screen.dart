import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/otzaria_module_controller.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// נוסח דיאלוג ההתקנה — משותף למסך הזה ולאריח בדף הבית, כדי שהאזהרה על
/// גרסה לא-יציבה תופיע בשניהם.
String appInstallPrompt(BuildContext context, OtzariaModuleController c) =>
    context.strings.appScreen.installPrompt(
      latestVersion: c.latestVersion,
      currentVersion: c.currentVersion,
      prereleaseNote: c.hasChannelChoice && c.preferPrerelease,
    );

/// מסך עדכון תוכנת אוצריא — מקביל במבנה ל-[LibraryScreen]: מצב, מה
/// התחדש בגרסה האחרונה, והתיקייה שממנה מותקנים.
class OtzariaScreen extends StatelessWidget {
  const OtzariaScreen({
    super.key,
    required this.otzaria,
    required this.settings,
    required this.otzariaIsRunning,
  });

  final OtzariaModuleController otzaria;

  /// בחירת ערוץ הגרסה נשמרת בהגדרות, כדי שתישאר בין הפעלות.
  final SettingsController settings;
  final bool otzariaIsRunning;

  /// **לא** תלוי בהורדה גלובלית: הורדה של רכיב אחר (למשל הספרייה) לא
  /// אמורה לחסום פעולות מקומיות כאן (בחירת מיקום, בדיקה מחדש).
  bool get _isBusy => otzaria.status == OtzariaModuleStatus.installing;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.appScreen;

    return ScreenBody(
      title: t.title,
      description: t.description,
      children: [
        _stateCard(context),
        _whatsNewCard(context),
        _sourceCard(context),
      ],
    );
  }

  // ── מצב ההתקנה ────────────────────────────────────────────────────────────

  Widget _stateCard(BuildContext context) {
    final c = otzaria;
    final t = context.strings.appScreen;
    final common = context.strings.common;

    return SettingsCard(
      title: t.stateCardTitle,
      children: [
        InfoStatusRow(
          icon: FluentIcons.desktop_24_regular,
          title: t.stateRowTitle,
          kind: switch (c.status) {
            OtzariaModuleStatus.idle => StatusKind.unknown,
            OtzariaModuleStatus.checking => StatusKind.working,
            OtzariaModuleStatus.upToDate => StatusKind.ok,
            OtzariaModuleStatus.updateAvailable => StatusKind.updateAvailable,
            OtzariaModuleStatus.installing => StatusKind.working,
            OtzariaModuleStatus.needsDownload => StatusKind.needsAction,
            OtzariaModuleStatus.error => StatusKind.error,
          },
          label: switch (c.status) {
            OtzariaModuleStatus.idle => common.notCheckedYet,
            OtzariaModuleStatus.checking => common.checking,
            OtzariaModuleStatus.upToDate => common.upToDate,
            OtzariaModuleStatus.updateAvailable => t.readyToInstall,
            OtzariaModuleStatus.installing => common.installing,
            OtzariaModuleStatus.needsDownload => t.nothingDownloadedYet,
            OtzariaModuleStatus.error => common.error,
          },
        ),
        SettingsActionTile.text(
          icon: FluentIcons.tag_24_regular,
          title: t.installedVersion,
          subtitle: c.currentVersion ?? t.noInstallDetected,
          subtitleLtr: c.currentVersion != null,
          actions: [
            ActionButton.ghost(
              text: t.pickInstallDirButton,
              icon: FluentIcons.folder_open_24_regular,
              onPressed: _isBusy ? null : () => _pickInstallDir(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.folder_24_regular,
          title: t.mirrorVersionTitle,
          // כששתיהן בתיקייה מוצגות שתיהן — הפקד שמתחת קובע איזו תותקן.
          subtitle: c.hasChannelChoice
              ? t.channelPair('${c.stableVersion}', '${c.prereleaseVersion}')
              : c.latestVersion ?? t.mirrorEmpty,
          subtitleLtr: c.latestVersion != null && !c.hasChannelChoice,
        ),
        // מוצג רק כשבתיקייה יושבות שתי גרסאות — כלומר כשה-pre-release חדש
        // מהיציבה. אחרת אין בחירה אמיתית, ואין טעם להציג פקד.
        if (c.hasChannelChoice)
          SettingsActionTile.segmentedTile<bool>(
            icon: FluentIcons.branch_24_regular,
            title: t.channelTileTitle,
            subtitle: c.preferPrerelease
                ? t.prereleaseSubtitle('${c.prereleaseVersion}')
                : t.stableSubtitle('${c.stableVersion}'),
            options: [
              SegmentOption(value: false, label: t.channelStable),
              SegmentOption(value: true, label: t.channelPrerelease),
            ],
            currentValue: c.preferPrerelease,
            onChanged: _setChannel,
          ),
        SettingsActionTile.text(
          icon: FluentIcons.play_24_regular,
          title: t.processTitle,
          subtitle: otzariaIsRunning ? t.processRunning : t.processStopped,
        ),
        if (c.errorMessage != null)
          InfoErrorRow(message: c.errorMessage!, onRetry: c.checkForUpdate),
        if (c.status == OtzariaModuleStatus.installing)
          InfoProgressRow(stage: t.installingProgress),
        CardActionsRow(
          actions: [
            ActionButton.neutral(
              text: common.recheck,
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _isBusy ? null : c.checkForUpdate,
            ),
            ActionButton.recommended(
              text: t.launchButton,
              icon: FluentIcons.play_24_regular,
              onPressed: c.canLaunch ? c.launch : null,
            ),
            ActionButton.neutral(
              text: t.installUpdateButton,
              icon: FluentIcons.desktop_arrow_right_24_regular,
              isLoading: c.status == OtzariaModuleStatus.installing,
              onPressed: c.status == OtzariaModuleStatus.updateAvailable
                  ? () => _confirmInstall(context)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  /// שומר את הבחירה בהגדרות; `AppShell` מזליג אותה לקונטרולר, שמריץ בדיקה
  /// מחדש מהתיקייה המקומית. אין כאן רשת — שתי הגרסאות כבר בדיסק.
  void _setChannel(bool preferPrerelease) {
    settings.update(
      settings.settings.copyWith(preferAppPrerelease: preferPrerelease),
    );
  }

  Future<void> _pickInstallDir(BuildContext context) async {
    final t = context.strings.appScreen;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    final adopted = await otzaria.adoptInstallDir(dir);
    if (adopted) {
      UiSnack.showSuccess(t.installAdoptedSnack);
    } else {
      UiSnack.showError(t.installNotFoundSnack);
    }
  }

  Future<void> _confirmInstall(BuildContext context) async {
    final approved = await showTwoActionsDialog(
      context: context,
      title: context.strings.home.appInstallDialogTitle,
      content: appInstallPrompt(context, otzaria),
      confirmText: context.strings.home.appInstallConfirm,
    );
    if (!approved) return;
    await otzaria.install();
    if (otzaria.status == OtzariaModuleStatus.upToDate) {
      UiSnack.showSuccess(
        AppL10n.strings.home.appInstalledSnack('${otzaria.currentVersion}'),
      );
    }
  }

  // ── מה התחדש ──────────────────────────────────────────────────────────────

  Widget _whatsNewCard(BuildContext context) {
    final notes = otzaria.latestReleaseNotes?.trim();
    final t = context.strings.appScreen;

    return SettingsCard(
      title: t.whatsNewTitle,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: (notes == null || notes.isEmpty)
              ? Text(
                  t.whatsNewEmpty,
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : MarkdownBody(
                  data: notes,
                  styleSheet: _whatsNewStyleSheet(context),
                ),
        ),
      ],
    );
  }

  /// גיליון סגנון ל"מה התחדש" — מבוסס על עיצוב הערכה (`fromTheme`) עם
  /// דריסות לפי טוקני העיצוב של אוצריא (צבע/פונט כותרות כמו כותרת
  /// [SettingsCard], והזחת בלט/מסגרת ציטוט לפי כיוון הכתיבה).
  MarkdownStyleSheet _whatsNewStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRtl = context.isRtl;
    final headingStyle =
        TextStyle(color: cs.primary, fontWeight: FontWeight.bold);

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      h1: theme.textTheme.headlineSmall?.merge(headingStyle),
      h2: theme.textTheme.titleLarge?.merge(headingStyle),
      h3: theme.textTheme.titleMedium?.merge(headingStyle),
      blockSpacing: AppTokens.spaceSM,
      listIndent: AppTokens.spaceLG,
      // ה-bullet הוא הילד הראשון ב-Row של הפריט; הריווח צריך להיות בצד
      // שאליו זורם הטקסט — שמאל ב-RTL, ימין ב-LTR.
      listBulletPadding: EdgeInsets.only(
        left: isRtl ? AppTokens.spaceXS : 0,
        right: isRtl ? 0 : AppTokens.spaceXS,
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceXS,
      ),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppTokens.borderRadiusAll,
        border: BorderDirectional(
          start: BorderSide(color: cs.primary, width: 3),
        ),
      ),
      codeblockDecoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
    );
  }

  // ── התיקייה שממנה מתקינים ─────────────────────────────────────────────────

  Widget _sourceCard(BuildContext context) {
    final c = otzaria;
    final t = context.strings.appScreen;

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
