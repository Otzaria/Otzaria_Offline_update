import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/custom_apps_controller.dart';
import '../services/app_logger.dart';
import '../services/app_paths.dart';
import '../settings/app_settings.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'custom_apps/custom_apps_settings_card.dart';

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
    this.customApps,
    this.readOnly = false,
    this.saferMode,
  });

  final SettingsController controller;
  final VoidCallback onOpenLog;

  /// גרסת הלאנצ'ר עצמו. מוצגת כאן ולא בדף הבית: הכרטיס בדף הבית מופיע רק
  /// כשיש עדכון, וכשאין — עדיין צריך לדעת איזו גרסה רצה (למשל לתמיכה).
  final String launcherVersion;

  /// ניהול התוכנות המותאמות. `null` בבדיקות שאינן נוגעות בהן.
  final CustomAppsController? customApps;

  /// הכונן מוגן מפני כתיבה — ראו `AppPaths.readOnly`. כל ניהול המרשם כותב
  /// אליו, ולכן כרטיס התוכנות הנוספות כולו אינו מוצג.
  final bool readOnly;

  /// שומר הסף של מצב הסייפר — נדרש כדי לסמן אימות אחרי בחירת סיסמה. `null`
  /// בבדיקות שאינן נוגעות בנעילה.
  final SaferModeGate? saferMode;

  AppSettings get _s => controller.settings;

  Future<void> _set(AppSettings next) => controller.update(next);

  @override
  Widget build(BuildContext context) {
    final t = context.strings.settings;

    return ScreenBody(
      title: t.title,
      children: [
        // שפה ומראה ראשונים: מי שפותח בפעם הראשונה צריך קודם להבין את המסך.
        _appearanceCard(context),
        _automationCard(context),
        _downloadCard(context),
        if (customApps case final controller? when !readOnly)
          CustomAppsSettingsCard(controller: controller),
        _saferModeCard(context),
        _supportCard(context),
      ],
    );
  }

  // ── אוטומציה ──────────────────────────────────────────────────────────────

  Widget _automationCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.automationCardTitle,
      hint: t.automationCardHint,
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
          hint: t.autoOnlineCheckHint,
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
      hint: t.downloadCardHint,
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
          icon: FluentIcons.box_24_regular,
          title: t.syncFullPackageTitle,
          subtitle: t.syncFullPackageSubtitle,
          hint: t.syncFullPackageHint,
          value: _s.syncFullPackage,
          onChanged: (v) => _set(_s.copyWith(syncFullPackage: v)),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.person_24_regular,
          title: t.personalModeTitle,
          subtitle: t.personalModeSubtitle,
          hint: t.personalModeHint,
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

  /// רוחב קבוע לשורות הכרטיס — כך שתיבת ערכת הנושא, שהתווית הארוכה שבה
  /// הייתה מגדילה אותה, יושבת באותו גודל בדיוק כמו בורר השפה.
  static const double _uiSegmentWidth = 300;

  Widget _appearanceCard(BuildContext context) {
    final t = context.strings.settings;

    return SettingsCard(
      title: t.appearanceCardTitle,
      children: [
        // תפריט נפתח ולא סגמנטד — כמו בורר השפה של אוצריא.
        SettingsActionTile.dropdownTile<AppLanguagePreference>(
          icon: FluentIcons.local_language_24_regular,
          title: t.languageTitle,
          subtitle: t.languageSubtitle,
          currentValue: _s.languagePreference,
          onSelected: (v) => _set(_s.copyWith(languagePreference: v)),
          entries: [
            AppMenuEntry(
              value: AppLanguagePreference.system,
              label: t.languageSystem,
            ),
            AppMenuEntry(
              value: AppLanguagePreference.hebrew,
              label: t.languageHebrew,
            ),
            AppMenuEntry(
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
        SettingsActionTile.switchTile(
          icon: FluentIcons.question_circle_24_regular,
          title: t.showFaqTitle,
          subtitle: t.showFaqSubtitle,
          value: _s.showFaqButton,
          onChanged: (v) => _set(_s.copyWith(showFaqButton: v)),
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

  // ── מצב סייפר ─────────────────────────────────────────────────────────────

  /// נעילת ההגדרות בסיסמה. הכרטיס עצמו יושב **בתוך** המסך הנעול: מי שהגיע
  /// לכאן כבר עבר את השער, ולכן כאן די באימות לפני כל שינוי של הנעילה
  /// עצמה — הפעלה, כיבוי, החלפת סיסמה או מחיקתה.
  Widget _saferModeCard(BuildContext context) {
    final t = context.strings.saferMode;
    final hasPassword = _s.hasSaferModePassword;

    return SettingsCard(
      title: t.cardTitle,
      hint: t.cardHint,
      children: [
        if (hasPassword)
          SettingsActionTile.switchTile(
            icon: _s.saferModeEnabled
                ? FluentIcons.shield_lock_24_filled
                : FluentIcons.shield_lock_24_regular,
            title: t.toggleTitle,
            subtitle:
                _s.saferModeEnabled ? t.toggleOnSubtitle : t.toggleOffSubtitle,
            value: _s.saferModeEnabled,
            onChanged: (v) => _toggleSaferMode(context, enabled: v),
          )
        else
          SettingsActionTile.text(
            icon: FluentIcons.shield_lock_24_regular,
            title: t.toggleTitle,
            subtitle: t.needsPasswordSubtitle,
            actions: [
              ActionButton.recommended(
                icon: FluentIcons.key_24_regular,
                text: t.setPasswordButton,
                onPressed: () => _setSaferModePassword(context),
              ),
            ],
          ),
        if (hasPassword)
          SettingsActionTile.text(
            icon: FluentIcons.key_24_regular,
            title: t.passwordTileTitle,
            subtitle: t.passwordTileSubtitle,
            actions: [
              ActionButton.neutral(
                icon: FluentIcons.key_24_regular,
                text: t.passwordOptionsButton,
                onPressed: () => _setSaferModePassword(context),
              ),
              // מחיקה כשהמצב פעיל הייתה דלת אחורית מתוך הנעילה — הכפתור
              // מושבת ומסביר, במקום להיעלם בלי סיבה נראית.
              ActionButton.warning(
                text:
                    _s.saferModeEnabled ? t.clearBlockedButton : t.clearButton,
                onPressed: _s.saferModeEnabled
                    ? null
                    : () => _clearSaferModePassword(context),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _toggleSaferMode(
    BuildContext context, {
    required bool enabled,
  }) async {
    final t = context.strings.saferMode;
    final verified = await showSaferModePasswordDialog(
      context,
      storedPassword: _s.saferModePassword,
      hint: enabled ? t.verifyEnableHint : t.verifyDisableHint,
    );
    if (!verified) return;
    // מי שהפעיל את המצב הרגע הוכיח את הסיסמה — ולא יישאל שוב עד הסגירה.
    saferMode?.unlock();
    await _set(_s.copyWith(saferModeEnabled: enabled));
    UiSnack.show(enabled ? t.enabledSnack : t.disabledSnack);
  }

  Future<void> _setSaferModePassword(BuildContext context) async {
    final t = context.strings.saferMode;
    final hadPassword = _s.hasSaferModePassword;

    if (hadPassword) {
      final verified = await showSaferModePasswordDialog(
        context,
        storedPassword: _s.saferModePassword,
        hint: t.verifyChangeHint,
      );
      if (!verified || !context.mounted) return;
    }

    final encoded = await showSaferModeSetPasswordDialog(context);
    if (encoded == null) return;
    await _set(_s.copyWith(saferModePassword: encoded));
    saferMode?.unlock();
    UiSnack.showSuccess(t.passwordSavedSnack);

    // סיסמה ראשונה אינה נועלת דבר בלי המתג, ומי שבחר אותה מתכוון לנעול.
    if (hadPassword || _s.saferModeEnabled || !context.mounted) return;
    final activate = await showTwoActionsDialog(
      context: context,
      title: t.activateNowTitle,
      content: t.activateNowContent,
      confirmText: t.activateNowConfirm,
    );
    if (!activate) return;
    await _set(_s.copyWith(saferModeEnabled: true));
    UiSnack.show(t.enabledSnack);
  }

  Future<void> _clearSaferModePassword(BuildContext context) async {
    final t = context.strings.saferMode;
    final verified = await showSaferModePasswordDialog(
      context,
      storedPassword: _s.saferModePassword,
      hint: t.verifyChangeHint,
    );
    if (!verified || !context.mounted) return;

    final approved = await showWarningDialog(
      context: context,
      title: t.clearDialogTitle,
      content: t.clearDialogContent,
      confirmText: t.clearDialogConfirm,
    );
    if (!approved) return;
    await _set(_s.copyWith(saferModePassword: '', saferModeEnabled: false));
    // בלי זה, סיסמה שתיבחר מיד אחר כך הייתה נכנסת לתוקף רק בהרצה הבאה.
    saferMode?.lock();
    UiSnack.show(t.passwordRemovedSnack);
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
          // הנתיב עצמו, ולא רק הסבר: הלוג עובר לתיקיית המחשב כשהכונן מוגן
          // מכתיבה, ובלי זה מי שמתבקש "שלח את הלוג" הולך לכונן ומביא קובץ
          // שקפא לפני חודשיים.
          subtitle:
              '${t.logSubtitle}\n${AppLogger.maybeInstance?.filePath ?? ''}',
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
    // הנעילה שורדת אותו בכוונה: "החזר הגדרות לברירת המחדל" אינו אמור
    // לפתוח בשקט את מה שנועל את ההגדרות עצמן.
    await _set(
      const AppSettings().copyWith(
        saferModeEnabled: _s.saferModeEnabled,
        saferModePassword: _s.saferModePassword,
      ),
    );
    UiSnack.showSuccess(AppL10n.strings.settings.resetDoneSnack);
  }
}
