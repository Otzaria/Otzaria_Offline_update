import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../services/app_paths.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';

/// מסך ההגדרות — שפה ומראה, אוטומציה, הורדה ותמיכה.
///
/// **אין כאן הגדרות רשת בכוונה.** הזמן הקצוב לכל פנייה נקבע בלקוחות עצמם
/// (ראו `OtzariaReleaseClient`, `GithubLibraryReleaseClient`) — ערך שהמשתמש
/// אינו יכול לכוון נכון, וכשל הורדה נפתר בניסיון חוזר ולא בהארכת timeout.
///
/// **אין כאן נתיבים בכוונה.** תיקיית הנתונים צמודה לקובץ ההרצה (ראו
/// [AppPaths]) ומיקום אוצריא מתגלה לבד — שינוי נתיב היה שובר את הרעיון של
/// כונן נייד שנוסע בין מחשבים.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onOpenLog,
    required this.launcherVersion,
  });

  final SettingsController controller;
  final VoidCallback onOpenLog;

  /// גרסת הלאנצ'ר עצמו. מוצגת כאן ולא בדף הבית: הכרטיס בדף הבית מופיע רק
  /// כשיש עדכון, וכשאין — עדיין צריך לדעת איזו גרסה רצה (למשל לתמיכה).
  final String launcherVersion;

  AppSettings get _s => controller.settings;

  Future<void> _set(AppSettings next) => controller.update(next);

  @override
  Widget build(BuildContext context) {
    final t = context.strings.settings;

    return ScreenBody(
      title: t.title,
      description: t.description,
      children: [
        // שפה ומראה ראשונים: מי שפותח בפעם הראשונה צריך קודם להבין את המסך.
        _appearanceCard(context),
        _automationCard(context),
        _downloadCard(context),
        _supportCard(context),
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
        SettingsActionTile.switchTile(
          icon: FluentIcons.person_24_regular,
          title: t.personalModeTitle,
          subtitle: t.personalModeSubtitle,
          value: _s.personalUpdateMode,
          onChanged: (v) => _confirmPersonalMode(context, enabled: v),
        ),
      ],
    );
  }

  /// הפעלה דורשת אישור: מכאן והלאה הכונן אינו מתקין ספרייה במחשב אחר, וגם
  /// מסלול ההתאוששות (מסד מלא כשקובץ עדכון אינו מתאים) נעלם ממנו.
  Future<void> _confirmPersonalMode(
    BuildContext context, {
    required bool enabled,
  }) async {
    if (!enabled) {
      await _set(_s.copyWith(personalUpdateMode: false));
      return;
    }

    final t = context.strings.settings;
    final approved = await showWarningDialog(
      context: context,
      title: t.personalModeDialogTitle,
      content: t.personalModeDialogContent,
      subtitle: t.personalModeDialogWarning,
      confirmText: t.personalModeDialogConfirm,
    );
    if (!approved) return;
    await _set(_s.copyWith(personalUpdateMode: true));
  }

  // ── שפה ומראה ─────────────────────────────────────────────────────────────

  /// רוחב קבוע לשלוש השורות בכרטיס — כך שתיבות ערכת הנושא, שהתווית הארוכה
  /// ביניהן ("לפי המערכת") הייתה מגדילה אותן יותר מהשורה השנייה, יושבות
  /// באותו גודל בדיוק כמו תיבות השפה וגודל הטקסט.
  static const double _uiSegmentWidth = 300;

  Widget _appearanceCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.appearanceCardTitle,
      subtitle: t.appearanceCardSubtitle,
      children: [
        SettingsActionTile.segmentedTile<AppLanguagePreference>(
          icon: FluentIcons.local_language_24_regular,
          title: t.languageTitle,
          subtitle: t.languageSubtitle,
          currentValue: _s.languagePreference,
          onChanged: (v) => _set(_s.copyWith(languagePreference: v)),
          width: _uiSegmentWidth,
          options: [
            SegmentOption(
              value: AppLanguagePreference.system,
              label: t.languageSystem,
            ),
            SegmentOption(
              value: AppLanguagePreference.hebrew,
              label: t.languageHebrew,
            ),
            SegmentOption(
              value: AppLanguagePreference.english,
              label: t.languageEnglish,
            ),
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
        _colorPickerTile(context),
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
      ],
    );
  }

  /// בורר צבע הבסיס. כמו באוצריא, הבחירה חלה על הערכה שמוצגת כרגע — ולכן
  /// המפתח מכריח בנייה מחדש כשהבהירות מתחלפת, אחרת הצבע של הערכה הקודמת
  /// היה נשאר על המסך.
  Widget _colorPickerTile(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ColorPickerTile(
      key: ValueKey('seed-color-${isDark ? 'dark' : 'light'}'),
      currentColor: isDark ? _s.darkSeedColor : _s.seedColor,
      defaultColor:
          isDark ? AppSeedColors.defaultDark : AppSeedColors.defaultLight,
      onChanged: (color) => _set(
        isDark
            ? _s.copyWith(darkSeedColor: color)
            : _s.copyWith(seedColor: color),
      ),
    );
  }

  // ── תמיכה ─────────────────────────────────────────────────────────────────

  Widget _supportCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.supportCardTitle,
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.info_24_regular,
          title: context.strings.launcherUpdate.versionTileTitle,
          subtitle:
              context.strings.launcherUpdate.installedVersion(launcherVersion),
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
