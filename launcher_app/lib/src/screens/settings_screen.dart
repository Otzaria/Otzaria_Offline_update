import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../services/app_paths.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// מסך ההגדרות — אוטומציה, אחסון, רשת וממשק.
///
/// **אין כאן נתיבים בכוונה.** תיקיית הנתונים צמודה לקובץ ההרצה (ראו
/// [AppPaths]) ומיקום אוצריא מתגלה לבד — שינוי נתיב היה שובר את הרעיון של
/// כונן נייד שנוסע בין מחשבים.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onOpenLog,
  });

  final SettingsController controller;
  final VoidCallback onOpenLog;

  AppSettings get _s => controller.settings;

  Future<void> _set(AppSettings next) => controller.update(next);

  @override
  Widget build(BuildContext context) {
    final t = context.strings.settings;

    return ScreenBody(
      title: t.title,
      description: t.description,
      children: [
        _automationCard(context),
        _downloadCard(context),
        _storageCard(context),
        _networkCard(context),
        _uiCard(context),
      ],
    );
  }

  // ── אוטומציה ──────────────────────────────────────────────────────────────

  Widget _automationCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.automationCardTitle,
      subtitle: t.automationCardSubtitle,
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.search_info_24_regular,
          title: t.autoCheckTitle,
          subtitle: t.autoCheckSubtitle,
          value: _s.autoMetadataCheck,
          onChanged: (v) => _set(_s.copyWith(autoMetadataCheck: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.cloud_24_regular,
          title: t.autoOnlineCheckTitle,
          subtitle: t.autoOnlineCheckSubtitle,
          value: _s.autoCheckOnlineUpdates,
          onChanged: (v) => _set(_s.copyWith(autoCheckOnlineUpdates: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.desktop_arrow_right_24_regular,
          title: t.autoInstallAppTitle,
          subtitle: t.autoInstallAppSubtitle,
          value: _s.autoInstallApp,
          onChanged: (v) => _confirmAutoInstall(
            context,
            enabled: v,
            what: t.autoInstallSubjectApp,
            apply: (on) => _set(_s.copyWith(autoInstallApp: on)),
          ),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.database_arrow_right_24_regular,
          title: t.autoInstallLibraryTitle,
          subtitle: t.autoInstallLibrarySubtitle,
          value: _s.autoInstallLibrary,
          onChanged: (v) => _confirmAutoInstall(
            context,
            enabled: v,
            what: t.autoInstallSubjectLibrary,
            apply: (on) => _set(_s.copyWith(autoInstallLibrary: on)),
          ),
        ),
      ],
    );
  }

  /// התקנה אוטומטית היא הסיכון האמיתי כאן — היא מחליפה קבצים בלי לשאול —
  /// ולכן היא דורשת אישור מפורש והסבר.
  Future<void> _confirmAutoInstall(
    BuildContext context, {
    required bool enabled,
    required String what,
    required Future<void> Function(bool) apply,
  }) async {
    if (!enabled) {
      await apply(false);
      return;
    }

    final t = context.strings.settings;
    final approved = await showWarningDialog(
      context: context,
      title: t.autoInstallDialogTitle(what),
      content: t.autoInstallDialogContent(what),
      subtitle: t.autoInstallDialogWarning,
      confirmText: t.autoInstallDialogConfirm,
    );
    if (!approved) return;
    await apply(true);
  }

  // ── הורדה ─────────────────────────────────────────────────────────────────

  Widget _downloadCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.downloadCardTitle,
      subtitle: t.downloadCardSubtitle,
      children: [
        SettingsActionTile.switchTile(
          icon: FluentIcons.desktop_24_regular,
          title: t.syncAppTitle,
          subtitle: t.syncAppSubtitle,
          value: _s.syncApp,
          onChanged: (v) => _set(_s.copyWith(syncApp: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.library_24_regular,
          title: t.syncLibraryTitle,
          subtitle: t.syncLibrarySubtitle,
          value: _s.syncLibrary,
          onChanged: (v) => _set(_s.copyWith(syncLibrary: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.puzzle_piece_24_regular,
          title: t.syncPluginsTitle,
          subtitle: t.syncPluginsSubtitle,
          value: _s.syncPlugins,
          onChanged: (v) => _set(_s.copyWith(syncPlugins: v)),
        ),
      ],
    );
  }

  // ── אחסון ─────────────────────────────────────────────────────────────────

  Widget _storageCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.storageCardTitle,
      subtitle: t.storageCardSubtitle,
      children: [
        SettingsActionTile.segmentedTile<int>(
          icon: FluentIcons.history_24_regular,
          title: t.backupTitle,
          subtitle: t.backupSubtitle,
          currentValue: _s.backupsToKeep,
          onChanged: (v) => _set(_s.copyWith(backupsToKeep: v)),
          options: [
            SegmentOption(value: 0, label: t.backupOff),
            SegmentOption(value: 1, label: t.backupOn),
          ],
        ),
      ],
    );
  }

  // ── רשת ───────────────────────────────────────────────────────────────────

  Widget _networkCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.networkCardTitle,
      subtitle: t.networkCardSubtitle,
      children: [
        SettingsActionTile.segmentedTile<int>(
          icon: FluentIcons.timer_24_regular,
          title: t.timeoutTitle,
          subtitle: t.timeoutSubtitle,
          currentValue: _s.networkTimeoutSeconds,
          onChanged: (v) => _set(_s.copyWith(networkTimeoutSeconds: v)),
          options: const [
            SegmentOption(value: 10, label: '10'),
            SegmentOption(value: 20, label: '20'),
            SegmentOption(value: 45, label: '45'),
          ],
        ),
      ],
    );
  }

  // ── ממשק ותמיכה ───────────────────────────────────────────────────────────

  /// רוחב קבוע לשלוש השורות למטה — כך שתיבות ערכת הנושא, שהתווית הארוכה
  /// ביניהן ("לפי המערכת") הייתה מגדילה אותן יותר מהשורה השנייה, יושבות
  /// באותו גודל בדיוק כמו תיבות השפה וגודל הטקסט.
  static const double _uiSegmentWidth = 300;

  Widget _uiCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.uiCardTitle,
      children: [
        SettingsActionTile.segmentedTile<AppLanguage>(
          icon: FluentIcons.local_language_24_regular,
          title: t.languageTitle,
          subtitle: t.languageSubtitle,
          currentValue: _s.language,
          onChanged: (v) => _set(_s.copyWith(language: v)),
          width: _uiSegmentWidth,
          options: [
            SegmentOption(value: AppLanguage.hebrew, label: t.languageHebrew),
            SegmentOption(value: AppLanguage.english, label: t.languageEnglish),
          ],
        ),
        SettingsActionTile.segmentedTile<AppThemeMode>(
          icon: FluentIcons.dark_theme_24_regular,
          title: t.themeTitle,
          currentValue: _s.themeMode,
          onChanged: (v) => _set(_s.copyWith(themeMode: v)),
          width: _uiSegmentWidth,
          options: [
            SegmentOption(value: AppThemeMode.system, label: t.themeSystem),
            SegmentOption(value: AppThemeMode.light, label: t.themeLight),
            SegmentOption(value: AppThemeMode.dark, label: t.themeDark),
          ],
        ),
        SettingsActionTile.segmentedTile<double>(
          icon: FluentIcons.text_font_size_24_regular,
          title: t.textSizeTitle,
          currentValue: _s.textScale,
          onChanged: (v) => _set(_s.copyWith(textScale: v)),
          width: _uiSegmentWidth,
          options: [
            SegmentOption(value: 0.9, label: t.textSizeSmall),
            SegmentOption(value: 1.0, label: t.textSizeNormal),
            SegmentOption(value: 1.15, label: t.textSizeLarge),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.document_bullet_list_24_regular,
          title: t.logTitle,
          subtitle: t.logSubtitle,
          actions: [
            ActionButton.neutral(
              text: t.openLogFolderButton,
              icon: FluentIcons.folder_open_24_regular,
              onPressed: onOpenLog,
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.arrow_reset_24_regular,
          title: t.resetTitle,
          subtitle: t.resetSubtitle,
          actions: [
            ActionButton.warning(
              text: t.resetButton,
              onPressed: () => _confirmReset(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final t = context.strings.settings;
    final approved = await showWarningDialog(
      context: context,
      title: t.resetDialogTitle,
      content: t.resetDialogContent,
      subtitle: t.resetDialogWarning,
      confirmText: t.resetDialogConfirm,
    );
    if (!approved) return;
    // איפוס מחזיר גם את השפה לעברית — ולכן ההודעה נקראת אחרי ההחלה.
    await _set(const AppSettings());
    UiSnack.showSuccess(AppL10n.strings.settings.resetDoneSnack);
  }
}
