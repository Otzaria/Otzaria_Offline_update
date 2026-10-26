import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:library_manager/library_manager.dart' show RegisteredMachine;
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../controllers/app_reports_controller.dart';
import '../controllers/custom_apps_controller.dart';
import '../controllers/launcher_update_controller.dart';
import '../settings/app_settings.dart';
import '../settings/safer_mode.dart';
import '../settings/settings_controller.dart';
import '../shell/shell_keys.dart';
import '../theme/theme_exports.dart';
import '../widgets/screen_body.dart';
import '../widgets/widgets_exports.dart';
import 'app_report/app_reports_settings_card.dart';
import 'custom_apps/custom_apps_settings_card.dart';
import 'home/home_view_model.dart' show launcherLineOf, LauncherLineKind;
import 'home/personal_scope_dialog.dart' show confirmPersonalModeDialog;
import 'store_kit/store_visuals.dart' show StoreFilterChip;

/// אין כאן בכוונה הגדרות רשת (הזמן הקצוב בלקוחות), נתיבים (צמודים לקובץ
/// ההרצה, כדי שהכונן יישאר נייד) או ערוץ גרסאות — הוא ב"אוצריא — מתקדם",
/// שאינו נעול כמו ההגדרות; כאן רק קישור אליו.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onOpenLog,
    required this.launcherVersion,
    this.customApps,
    this.onManageCustomApps,
    this.readOnly = false,
    this.driveFull = false,
    this.saferMode,
    this.appReports,
    this.onOpenReports,
    this.launcherUpdate,
    this.onOpenLauncherUpdate,
    this.onEditFaq,
    this.onOpenOtzariaAdvanced,
    this.otzariaChannelChoice = false,
    this.semanticConsentGranted,
    this.onEnableSemanticSearch,
    this.personalMachines = const [],
    this.onChoosePersonal,
    this.onRemoveMachine,
    this.onRegisterHere,
  });

  final SettingsController controller;
  final VoidCallback onOpenLog;

  /// גרסת הכלי עצמו — בשורת "אודות", גם כשאין עדכון (למשל לתמיכה).
  final String launcherVersion;

  /// ניהול התוכנות המותאמות. `null` בבדיקות שאינן נוגעות בהן.
  final CustomAppsController? customApps;

  /// דף ניהול התוכנות הנוספות (`CustomAppsManageRoute`).
  final VoidCallback? onManageCustomApps;

  final bool readOnly;
  final bool driveFull;

  /// שומר הסף של מצב הסייפר — נדרש כדי לסמן אימות אחרי קביעת סיסמה.
  final SaferModeGate? saferMode;

  /// הדיווחים של הכלי על עצמו. `null` בבדיקות שאינן נוגעות בהם.
  final AppReportsController? appReports;

  /// דף הדיווחים — התור וההיסטוריה.
  final VoidCallback? onOpenReports;

  /// מצב העדכון של הכלי — לשורת "אודות". `null` בבדיקות.
  final LauncherUpdateController? launcherUpdate;

  /// דף "עדכון הכלי הזה".
  final VoidCallback? onOpenLauncherUpdate;

  /// דף העזרה במצב עריכה.
  final VoidCallback? onEditFaq;

  /// "אוצריא — מתקדם". `null` בבדיקות שאינן נוגעות בו.
  final VoidCallback? onOpenOtzariaAdvanced;

  /// בכונן שתי גרסאות — הקישור מזכיר את בחירת הגרסה.
  final bool otzariaChannelChoice;

  /// ההסכמה לחיפוש החכם באוצריא שבמחשב הזה; `null` — אין חיפוש חכם בכונן
  /// או שאוצריא אינה מותקנת, והשורה מוסתרת.
  final bool? semanticConsentGranted;

  /// אותו אישור כמו בדף הספרייה; `null` בזמן משימה ארוכה.
  final VoidCallback? onEnableSemanticSearch;

  /// המחשבים שנרשמו, מהגרסה הנמוכה — `LibraryModuleController.registeredMachines`.
  final List<RegisteredMachine> personalMachines;

  /// הבחירה בקבוצה — `AppSession.choosePersonalScope`, שגם רושם את המחשב
  /// הזה. `null` בבדיקות: נשמרת ההגדרה בלבד.
  final Future<void> Function(bool personal)? onChoosePersonal;

  /// `null` בזמן משימה ארוכה.
  final void Function(String machineKey)? onRemoveMachine;

  /// "רישום המחשב הזה" כשהוא לא ברשימה. `null` — בלי הכפתור.
  final VoidCallback? onRegisterHere;

  AppSettings get _s => controller.settings;

  Future<void> _set(AppSettings next) => controller.update(next);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final t = context.strings.settings;
        return ScreenBody(
          title: t.title,
          children: [
            // כותרת דף בלי הסבר: הרווח שלה (20) לפני התווית הראשונה.
            const SizedBox(height: 20),
            SectionLabel(t.groupGeneral, first: true),
            _general(context),
            SectionLabel(t.personalGroupTitle),
            ..._personalGroup(context),
            if (onOpenOtzariaAdvanced case final open?) ...[
              SectionLabel(context.strings.guide.tileApp),
              RowsCard(
                children: [
                  AppRow(
                    key: const ValueKey('settings.otzariaAdvanced'),
                    leading: const IconTile(
                      size: _tile,
                      tone: _quiet,
                      child: OtzariaLogo(size: 18),
                    ),
                    title: context.strings.pages.appAdvancedPageTitle,
                    subtitle: context.strings.pages.appAdvancedSummary(
                      channel: otzariaChannelChoice,
                    ),
                    onTap: open,
                  ),
                ],
              ),
            ],
            if (customApps case final apps?) ...[
              SectionLabel(context.strings.customApps.settingsCardTitle),
              CustomAppsSettingsCard(
                controller: apps,
                onOpenManager: onManageCustomApps ?? () {},
                readOnly: readOnly,
                driveFull: driveFull,
              ),
            ],
            if (appReports != null || semanticConsentGranted != null)
              SectionLabel(t.groupPrivacy),
            if (appReports case final reports?)
              AppReportsSettingsCard(
                reports: reports,
                onOpenReports: onOpenReports,
              ),
            if (semanticConsentGranted case final granted?) ...[
              if (appReports != null) const SizedBox(height: AppTokens.spaceSM),
              _semanticConsentRow(context, granted: granted),
            ],
            AdvancedSection(
              key: ShellKeys.pageAdvanced,
              title: context.strings.pages.advancedTitle,
              summary: t.advancedSummary,
              child: _advanced(context),
            ),
            SectionLabel(t.groupAbout),
            _about(context),
          ],
        );
      },
    );
  }

  static const _tile = IconTileSize.sm;
  static const _quiet = IconTileTone.quiet;

  // ── כללי ──────────────────────────────────────────────────────────────────

  Widget _general(BuildContext context) {
    final t = context.strings.settings;
    return RowsCard(
      children: [
        AppRow(
          leading: const IconTile(
            icon: FluentIcons.globe_24_regular,
            size: _tile,
            tone: _quiet,
          ),
          title: t.languageTitle,
          trailing: _LanguageButton(
            key: const ValueKey('settings.language'),
            label: _languageLabel(t, _s.languagePreference),
            onPressed: () => unawaited(_chooseLanguage(context)),
          ),
        ),
        AppSwitchRow(
          leading: const IconTile(
            icon: FluentIcons.arrow_sync_24_regular,
            size: _tile,
            tone: _quiet,
          ),
          title: t.autoCheckTitle,
          subtitle: t.autoCheckSubtitle,
          value: _s.autoCheckUpdates,
          onChanged: (v) => _set(_s.copyWith(autoCheckUpdates: v)),
        ),
        AppSwitchRow(
          leading: const IconTile(
            icon: FluentIcons.flash_24_regular,
            size: _tile,
            tone: _quiet,
          ),
          title: t.autoInstallTitle,
          subtitle: t.autoInstallSubtitle,
          value: _s.autoInstall,
          onChanged: (v) => _confirmAutoInstall(context, enabled: v),
        ),
        _syncTargetsRow(context),
        _semanticDownloadRow(context),
      ],
    );
  }

  static String _languageLabel(
    SettingsScreenStrings t,
    AppLanguagePreference preference,
  ) =>
      switch (preference) {
        AppLanguagePreference.system => t.languageSystem,
        AppLanguagePreference.hebrew => t.languageHebrew,
        AppLanguagePreference.english => t.languageEnglish,
      };

  /// בחירה סוגרת את הדו-שיח — השפה מתחלפת מיד, גם מאחוריו.
  Future<void> _chooseLanguage(BuildContext context) {
    final t = context.strings.settings;
    final current = _s.languagePreference;
    return showSingleActionDialog(
      context: context,
      title: t.languageTitle,
      confirmText: context.strings.common.close,
      customContent: Builder(
        builder: (dialogContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, icon) in const [
              (AppLanguagePreference.system, FluentIcons.desktop_24_regular),
              (
                AppLanguagePreference.hebrew,
                FluentIcons.local_language_24_regular
              ),
              (AppLanguagePreference.english, FluentIcons.globe_24_regular),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OptionCard(
                  icon: icon,
                  title: value == AppLanguagePreference.system
                      ? t.languageSystemAs(
                          _languageLabel(
                            t,
                            AppLanguagePreference.system.resolve().isRtl
                                ? AppLanguagePreference.hebrew
                                : AppLanguagePreference.english,
                          ),
                        )
                      : _languageLabel(t, value),
                  selected: value == current,
                  onSelected: () {
                    Navigator.of(dialogContext).pop();
                    unawaited(_set(_s.copyWith(languagePreference: value)));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// התקנה אוטומטית מחליפה קבצים בלי לשאול — ולכן ההפעלה דורשת אישור,
  /// באזהרה: הביטול ממוקד, ו-Enter אינו מפעיל.
  Future<void> _confirmAutoInstall(
    BuildContext context, {
    required bool enabled,
  }) async {
    if (!enabled) {
      await _set(_s.copyWith(autoInstall: false));
      return;
    }

    final t = context.strings.settings;
    final approved = await showWarningDialog(
      context: context,
      title: t.autoInstallDialogTitle,
      content: t.autoInstallDialogContent,
      confirmText: t.autoInstallDialogConfirm,
    );
    if (!approved) return;
    await _set(_s.copyWith(autoInstall: true));
  }

  Set<_SyncTarget> get _selectedSyncTargets => {
        if (_s.syncApp) _SyncTarget.app,
        if (_s.downloadsLibrary) _SyncTarget.library,
        if (_s.syncPlugins) _SyncTarget.plugins,
      };

  Future<void> _toggleSyncTarget(_SyncTarget target) {
    final on = !_selectedSyncTargets.contains(target);
    return _set(
      switch (target) {
        _SyncTarget.app => _s.copyWith(syncApp: on),
        _SyncTarget.library => _s.copyWith(syncLibrary: on),
        _SyncTarget.plugins => _s.copyWith(syncPlugins: on),
      },
    );
  }

  Widget _syncTargetsRow(BuildContext context) {
    final t = context.strings.settings;
    final selected = _selectedSyncTargets;
    final personal = _s.personalUpdateMode;
    return AppRow(
      key: const ValueKey('settings.syncTargets'),
      alignTop: true,
      leading: const IconTile(
        icon: FluentIcons.arrow_download_24_regular,
        size: _tile,
        tone: _quiet,
      ),
      title: t.syncTargetsTitle,
      subtitle: personal
          ? '${t.syncTargetsSubtitle} ${t.syncLibraryLockedSubtitle}'
          : t.syncTargetsSubtitle,
      below: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (target, label) in [
              (_SyncTarget.app, t.syncTargetApp),
              (_SyncTarget.library, t.syncTargetLibrary),
              (_SyncTarget.plugins, t.syncTargetPlugins),
            ])
              if (personal && target == _SyncTarget.library)
                Tooltip(
                  message: t.syncLibraryLockedSubtitle,
                  child: StoreFilterChip(
                    label: label,
                    selected: selected.contains(target),
                    locked: true,
                    onTap: null,
                  ),
                )
              else
                StoreFilterChip(
                  label: label,
                  selected: selected.contains(target),
                  onTap: () => unawaited(_toggleSyncTarget(target)),
                ),
          ],
        ),
      ),
    );
  }

  Widget _semanticDownloadRow(BuildContext context) {
    final t = context.strings.settings;
    return AppRow(
      key: const ValueKey('settings.semanticDownload'),
      alignTop: true,
      leading: const IconTile(
        icon: FluentIcons.sparkle_24_regular,
        size: _tile,
        tone: _quiet,
      ),
      title: t.semanticDownloadTitle,
      subtitle: t.semanticDownloadSubtitle,
      below: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppSegmentedControl<SemanticDownloadPreference>(
            options: [
              SegmentOption(
                value: SemanticDownloadPreference.ask,
                label: t.semanticDownloadAsk,
              ),
              SegmentOption(
                value: SemanticDownloadPreference.always,
                label: t.semanticDownloadAlways,
              ),
              SegmentOption(
                value: SemanticDownloadPreference.never,
                label: t.semanticDownloadNever,
              ),
            ],
            currentValue: _s.semanticDownload,
            onChanged: (v) => unawaited(_set(_s.copyWith(semanticDownload: v))),
          ),
        ),
      ),
    );
  }

  /// ביטול ההסכמה רק באוצריא: הביטול שלה גם מוחק את מה שטרם נשלח.
  Widget _semanticConsentRow(BuildContext context, {required bool granted}) {
    final t = context.strings.settings;
    return RowsCard(
      children: [
        AppRow(
          key: ShellKeys.settingsSemanticConsent,
          alignTop: true,
          leading: const IconTile(
            icon: FluentIcons.sparkle_24_regular,
            size: _tile,
            tone: _quiet,
          ),
          title: t.semanticConsentRowTitle,
          subtitle: granted ? t.semanticConsentRowOn : t.semanticConsentRowOff,
          trailing: granted
              ? StatusChip(
                  kind: StatusKind.ok,
                  label: context.strings.pages.libSemanticActive,
                )
              : ActionButton.neutral(
                  text: t.semanticConsentRowEnable,
                  onPressed: onEnableSemanticSearch,
                ),
        ),
      ],
    );
  }

  // ── מתקדם ─────────────────────────────────────────────────────────────────

  Widget _advanced(BuildContext context) {
    final t = context.strings.settings;
    return RowsCard(
      children: [
        ..._lockRows(context),
        if (onEditFaq case final edit?)
          AppRow(
            key: const ValueKey('settings.faqEdit'),
            title: t.faqEditTitle,
            subtitle: t.faqEditSubtitle,
            onTap: edit,
          ),
        AppRow(
          title: t.logTitle,
          subtitle: t.logSubtitle,
          trailing: ActionButton.ghost(
            text: t.openLogFolderButton,
            icon: FluentIcons.folder_open_24_regular,
            onPressed: onOpenLog,
          ),
        ),
        AppRow(
          title: t.resetTitle,
          subtitle: t.resetSubtitle,
          trailing: ActionButton.warning(
            key: const ValueKey('settings.reset'),
            text: t.resetButton,
            icon: FluentIcons.arrow_reset_24_regular,
            onPressed: () => unawaited(_confirmReset(context)),
          ),
        ),
      ],
    );
  }

  // ── בשביל איזה מחשב מורידים ──────────────────────────────────────────────

  List<Widget> _personalGroup(BuildContext context) {
    final t = context.strings.libraryScreen;
    final personal = _s.personalUpdateMode;
    return [
      OptionCard(
        key: ShellKeys.settingsPersonalMultiple,
        icon: FluentIcons.laptop_multiple_24_regular,
        title: t.personalAskMultiple,
        description: t.personalAskMultipleBody,
        selected: !personal,
        onSelected: () => unawaited(_choosePersonal(context, personal: false)),
      ),
      const SizedBox(height: AppTokens.spaceSM),
      OptionCard(
        key: ShellKeys.settingsPersonalMine,
        icon: FluentIcons.person_24_regular,
        title: t.personalAskMine,
        description: t.personalAskMineBody,
        selected: personal,
        onSelected: () => unawaited(_choosePersonal(context, personal: true)),
      ),
      if (personal) ...[
        const SizedBox(height: AppTokens.spaceSM),
        _machinesCard(context),
      ],
    ];
  }

  Widget _machinesCard(BuildContext context) {
    final t = context.strings.settings;
    final machines = personalMachines;
    const icon = IconTile(
      icon: FluentIcons.desktop_24_regular,
      size: _tile,
      tone: _quiet,
    );
    final floor = machines.isEmpty ? null : machines.first.version;
    final here = machines.any((m) => m.isThisMachine);
    return RowsCard(
      children: [
        if (machines.isEmpty)
          AppRow(leading: icon, title: t.personalMachinesNone),
        for (final machine in machines)
          AppRow(
            leading: icon,
            title: machine.isThisMachine
                ? t.personalMachineThis
                : machine.name == null
                    ? t.personalMachineUnnamed
                    : t.personalMachineName(machine.name!),
            subtitle: machines.length > 1 && machine.version == floor
                ? t.personalMachineFloor('${machine.version}')
                : machine.isThisMachine && machine.name != null
                    ? t.personalMachineThisSubtitle(
                        machine.name!,
                        '${machine.version}',
                      )
                    : t.personalMachineVersion('${machine.version}'),
            trailing: ActionButton.ghost(
              key: ShellKeys.personalMachineRemove(machine.key),
              text: t.personalMachineRemove,
              onPressed: readOnly || onRemoveMachine == null
                  ? null
                  : () => unawaited(_confirmRemove(context, machine)),
            ),
          ),
        if (!here && onRegisterHere != null)
          AppRow(
            leading: icon,
            title: t.personalMachineNotHere,
            trailing: ActionButton.neutral(
              key: ShellKeys.settingsPersonalRegisterHere,
              text: context.strings.libraryScreen.personalVersionButton,
              onPressed: readOnly ? null : onRegisterHere,
            ),
          ),
        if (readOnly) AppRow(title: t.personalMachinesReadOnly),
      ],
    );
  }

  /// ההסרה משנה מאיזו גרסה מורידים, ולכן באישור; למחשב הזה — בנוסח משלו.
  Future<void> _confirmRemove(
    BuildContext context,
    RegisteredMachine machine,
  ) async {
    final t = context.strings.settings;
    final approved = await showWarningDialog(
      context: context,
      title: t.personalRemoveTitle,
      content: machine.isThisMachine
          ? t.personalRemoveThisBody
          : t.personalRemoveBody,
      confirmText: t.personalMachineRemove,
    );
    if (approved) onRemoveMachine?.call(machine.key);
  }

  /// "רק המחשב שלי" דורש אישור באזהרה: הספרייה המלאה שבכונן נמחקת בהורדה
  /// הבאה. החזרה ל"מחשבים מרובים" אינה מוחקת דבר.
  Future<void> _choosePersonal(
    BuildContext context, {
    required bool personal,
  }) async {
    if (personal == _s.personalUpdateMode) return;
    if (personal && !await confirmPersonalModeDialog(context)) return;
    final choose = onChoosePersonal;
    if (choose != null) return choose(personal);
    await _set(
      _s.copyWith(personalUpdateMode: personal, personalModeAsked: true),
    );
  }

  /// הנעילה בסיסמה. השורות יושבות **בתוך** המסך הנעול: מי שהגיע לכאן כבר
  /// עבר את השער, ולכן די באימות לפני כל שינוי של הנעילה עצמה.
  List<Widget> _lockRows(BuildContext context) {
    final t = context.strings.saferMode;
    if (!_s.hasSaferModePassword) {
      return [
        AppRow(
          key: const ValueKey('settings.lock'),
          title: t.lockTitle,
          subtitle: t.noPasswordSubtitle,
          trailing: ActionButton.neutral(
            icon: FluentIcons.key_24_regular,
            text: t.setPasswordButton,
            onPressed: () => unawaited(_setPassword(context)),
          ),
        ),
      ];
    }
    final on = _s.saferModeEnabled;
    return [
      AppSwitchRow(
        key: const ValueKey('settings.lock'),
        title: t.lockTitle,
        subtitle: on ? t.lockOnSubtitle : t.lockOffSubtitle,
        value: on,
        onChanged: (v) => unawaited(_toggleLock(context, enabled: v)),
      ),
      AppRow(
        title: t.passwordRowTitle,
        // מחיקה כשהנעילה פעילה הייתה דלת אחורית מתוך הנעילה — מושבת ומוסבר.
        subtitle: on ? t.passwordRowLockedSubtitle : t.passwordRowSubtitle,
        trailing: Wrap(
          spacing: 8,
          children: [
            ActionButton.ghost(
              text: t.changeButton,
              onPressed: () => unawaited(_changePassword(context)),
            ),
            ActionButton.warning(
              key: const ValueKey('settings.lock.clear'),
              text: t.clearButton,
              onPressed: on ? null : () => unawaited(_clearPassword(context)),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _toggleLock(BuildContext context,
      {required bool enabled}) async {
    final t = context.strings.saferMode;
    final verified = await showSaferModePasswordDialog(
      context,
      storedPassword: _s.saferModePassword,
      hint: enabled ? t.verifyEnableHint : t.verifyDisableHint,
    );
    if (!verified) return;
    // מי שהפעיל את הנעילה הרגע הוכיח את הסיסמה — ולא יישאל שוב עד הסגירה.
    saferMode?.unlock();
    await _set(_s.copyWith(saferModeEnabled: enabled));
    UiSnack.show(enabled ? t.enabledSnack : t.disabledSnack);
  }

  /// סיסמה ראשונה נשמרת ומפעילה את הנעילה — מי שבחר אותה מתכוון לנעול.
  Future<void> _setPassword(BuildContext context) async {
    final t = context.strings.saferMode;
    final encoded = await showSaferModeSetPasswordDialog(
      context,
      onThisComputer: readOnly,
    );
    if (encoded == null) return;
    // לפני השמירה: הנעילה נכנסת לתוקף בשמירה, ומי שקבע אותה לא יישאל עליה.
    saferMode?.unlock();
    await _set(
      _s.copyWith(saferModePassword: encoded, saferModeEnabled: true),
    );
    UiSnack.showSuccess(t.passwordSetSnack);
  }

  Future<void> _changePassword(BuildContext context) async {
    final t = context.strings.saferMode;
    final encoded = await showSaferModeChangePasswordDialog(
      context,
      storedPassword: _s.saferModePassword,
    );
    if (encoded == null) return;
    saferMode?.unlock();
    await _set(_s.copyWith(saferModePassword: encoded));
    UiSnack.showSuccess(t.passwordChangedSnack);
  }

  Future<void> _clearPassword(BuildContext context) async {
    final t = context.strings.saferMode;
    final approved = await showSaferModeClearPasswordDialog(
      context,
      storedPassword: _s.saferModePassword,
    );
    if (!approved) return;
    await _set(_s.copyWith(saferModePassword: '', saferModeEnabled: false));
    // בלי זה, סיסמה שתיקבע מיד אחר כך הייתה נכנסת לתוקף רק בהרצה הבאה.
    saferMode?.lock();
    UiSnack.show(t.passwordRemovedSnack);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final t = context.strings.settings;
    final approved = await showWarningDialog(
      context: context,
      title: t.resetDialogTitle,
      content: t.resetDialogContent,
      confirmText: t.resetDialogConfirm,
    );
    if (!approved) return;
    // הנעילה שורדת את האיפוס בכוונה: "ברירת מחדל" אינה אמורה לפתוח בשקט
    // את מה שנועל את ההגדרות עצמן. ההודעה נקראת אחרי ההחלה (השפה חוזרת).
    await _set(
      const AppSettings().copyWith(
        saferModeEnabled: _s.saferModeEnabled,
        saferModePassword: _s.saferModePassword,
      ),
    );
    UiSnack.showSuccess(AppL10n.strings.settings.resetDoneSnack);
  }

  // ── אודות ─────────────────────────────────────────────────────────────────

  Widget _about(BuildContext context) {
    final t = context.strings.settings;
    Widget versionRow() {
      final line =
          launcherUpdate == null ? null : launcherLineOf(launcherUpdate!);
      final newer =
          line?.kind == LauncherLineKind.downloading ? null : line?.version;
      return AppRow(
        key: const ValueKey('settings.about'),
        leading: IconTile(
          child: Image.asset(
            'assets/images/otzaria_logo.png',
            width: 22,
            height: 22,
            semanticLabel: context.strings.shell.otzariaLogoLabel,
          ),
        ),
        title: t.aboutTitle(launcherVersion),
        subtitle: newer == null ? t.aboutSubtitle : t.aboutNewVersion(newer),
        onTap: onOpenLauncherUpdate,
      );
    }

    return RowsCard(
      children: [
        if (launcherUpdate case final c?)
          ListenableBuilder(listenable: c, builder: (_, __) => versionRow())
        else
          versionRow(),
      ],
    );
  }
}

/// אפשרויות שבבי ההורדה.
enum _SyncTarget { app, library, plugins }

/// כפתור בורר (`.dd`): 40, לבן עם מסגרת outline, התווית והחץ בקצוות.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FocusRing(
      child: Material(
        color: cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: cs.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          overlayColor: AppSurfaces.stateLayer(cs.primary),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 150),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    FluentIcons.chevron_down_16_regular,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
