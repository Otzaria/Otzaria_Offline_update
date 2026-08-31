import 'dart:async';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../../controllers/custom_apps_controller.dart';
import '../../services/byte_size.dart';
import '../../services/native_file_dialogs.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/widgets_exports.dart';
import 'custom_apps_pending_dialog.dart';

/// מסך "תוכנות נוספות" — כרטיס לכל תוכנה שהמשתמש הוסיף.
///
/// הפריט בסרגל הניווט מופיע **רק אחרי שנוספה תוכנה ראשונה** (ראו
/// `AppShell`), ולכן מי שלא משתמש בתכונה הזו לא פוגש אותה בכלל.
///
/// **אין כאן ניהול.** הוספה, עריכה והסרה יושבות כולן בכרטיס שבהגדרות
/// (`CustomAppsSettingsCard`); כאן רק מה שעושים עם התוכנות עצמן — הורדה,
/// התקנה והפעלה.
class CustomAppsScreen extends StatefulWidget {
  const CustomAppsScreen({
    super.key,
    required this.controller,
    this.readOnly = false,
  });

  final CustomAppsController controller;

  /// הכונן מוגן מפני כתיבה — ראו `AppPaths.readOnly`. תוכנה שכבר יושבת על
  /// הכונן מותקנת ומופעלת כרגיל; הורדה כותבת אליו, ולכן אינה קיימת.
  final bool readOnly;

  @override
  State<CustomAppsScreen> createState() => _CustomAppsScreenState();
}

class _CustomAppsScreenState extends State<CustomAppsScreen> {
  /// ההודעה נאמרת פעם אחת בכל הרצה, ולא בכל רענון של הרשימה.
  bool _pendingDialogShown = false;

  @override
  void initState() {
    super.initState();
    _announcePendingIfNeeded();
  }

  /// המסך אינו מאזין לקונטרולר בעצמו — `AppShell` הוא שמאזין ובונה אותו
  /// מחדש. לכן גם רשימה שהגיעה מאוחר מגיעה לכאן, ולא רק זו שהייתה בכניסה.
  @override
  void didUpdateWidget(CustomAppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _announcePendingIfNeeded();
  }

  /// **המסך הוא התנאי.** הוא נבנה רק כשנכנסים ללשונית (ראו
  /// `AppShell._builtScreens`), ולכן מי שלא נכנס אליה אינו רואה את ההודעה.
  void _announcePendingIfNeeded() {
    if (_pendingDialogShown) return;
    final pending = widget.controller.pendingApps;
    if (pending.isEmpty) return;

    _pendingDialogShown = true;
    // אחרי סיום הפריים: פתיחת דיאלוג בתוך build/initState אסורה.
    unawaited(WidgetsBinding.instance.endOfFrame.then((_) async {
      if (!mounted) return;
      await showCustomAppsPendingDialog(context: context, pending: pending);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final controller = widget.controller;

    return ScreenBody(
      title: t.screenTitle,
      children: [
        // בדיקה אחת לכל התוכנות, במקום לחיצה על כל כרטיס בנפרד. כמו
        // ההורדה — היא נוגעת ברשת וכותבת רק לזיכרון, ולכן אינה במצב קריאה.
        if (controller.hasOnlineSources && !widget.readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: _CheckAllCard(controller: controller),
          ),
        for (final app in controller.apps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
            child: _CustomAppCard(
              controller: controller,
              app: app,
              readOnly: widget.readOnly,
            ),
          ),
      ],
    );
  }
}

/// "בדיקה ברשת לכל התוכנות" — הבקשה שחזרה מהפורום: לא ללחוץ על כל כרטיס
/// בנפרד. יושב כאן ולא בדף הבית בכוונה: הבדיקה המרוכזת שם נוגעת ברכיבי
/// הליבה בלבד, והתוכנות הנוספות הן תוספת שלא כולם מפעילים.
class _CheckAllCard extends StatelessWidget {
  const _CheckAllCard({required this.controller});

  final CustomAppsController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActionButton.neutral(
            text: t.checkAllOnlineButton,
            icon: FluentIcons.arrow_sync_24_regular,
            isLoading: controller.isCheckingAll,
            onPressed: controller.isCheckingAll ? null : () => _run(),
          ),
          if (controller.isCheckingAll) ...[
            const SizedBox(height: AppTokens.spaceSM),
            InfoProgressRow(
              stage: t.checkingAllOnlineLabel(
                controller.checkAllDone ?? 0,
                controller.checkAllTotal ?? 0,
              ),
              progress: (controller.checkAllTotal ?? 0) > 0
                  ? (controller.checkAllDone ?? 0) / controller.checkAllTotal!
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run() async {
    final result = await controller.checkAllOnline();
    if (result.checked == 0) return;
    final t = AppL10n.strings.customApps;

    // כולן נכשלו = אין רשת. זו התשובה השלמה, ואין מה להוסיף עליה.
    if (result.failed == result.checked) {
      UiSnack.showError(t.checkAllOnlineAllFailed);
      return;
    }
    final summary = result.updates > 0
        ? t.checkAllOnlineSummary(result.updates, result.checked)
        : t.checkAllOnlineNoUpdates(result.checked);
    // בדיקה שנכשלה לחלק מהן אינה שגיאה, אבל אסור לבלוע אותה: "אין עדכונים"
    // על תוכנות שכלל לא נבדקו הוא בדיוק מה שמטעה.
    final text = result.failed > 0
        ? '$summary ${t.checkAllOnlineSomeFailed(result.failed)}'
        : summary;
    if (result.updates > 0) {
      UiSnack.show(text);
    } else {
      UiSnack.showSuccess(text);
    }
  }
}

class _CustomAppCard extends StatelessWidget {
  const _CustomAppCard({
    required this.controller,
    required this.app,
    required this.readOnly,
  });

  /// ראו [CustomAppsScreen.readOnly].
  final bool readOnly;

  final CustomAppsController controller;
  final CustomAppView app;

  bool get _isDownloading => controller.downloadingId == app.descriptor.id;
  bool get _isFromGithub => app.descriptor.sourceKind == AppSourceKind.github;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.customApps;
    final common = context.strings.common;
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // שם ותיאור הם תוכן שהמשתמש כתב — לא מתורגמים.
          Text(
            app.descriptor.name,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (app.descriptor.description case final text?)
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: AppTokens.spaceMD),
          StatusChip(kind: _statusKind, label: _installedLabel(context)),
          const SizedBox(height: AppTokens.spaceXS),
          Text(
            _storedLabel(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_onlineLabel(context) case final label?) ...[
            const SizedBox(height: AppTokens.spaceXS),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          // הלמידה שאחרי ההתקנה יכולה להימשך עד דקה — ראו `InstallLearner`.
          // בלי השורה הזו זה נראה כתקיעה.
          if (controller.isLearning) ...[
            const SizedBox(height: AppTokens.spaceMD),
            InfoProgressRow(stage: t.learningLabel),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: AppTokens.spaceMD),
            InfoProgressRow(
              stage: t.downloadingLabel,
              progress: (controller.downloadTotal ?? 0) > 0
                  ? (controller.downloadReceived ?? 0) /
                      controller.downloadTotal!
                  : null,
              detail: formatBytesProgress(
                controller.downloadReceived,
                controller.downloadTotal,
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMD),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: [
              if (app.canInstall)
                ActionButton.recommended(
                  text: common.install,
                  icon: FluentIcons.desktop_arrow_right_24_regular,
                  onPressed: controller.isBusy ? null : () => _install(context),
                ),
              if (app.canLaunch)
                ActionButton.neutral(
                  text: common.launch,
                  icon: FluentIcons.play_24_regular,
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.launch(app.installed!),
                ),
              // הנפילה חזרה כשהזיהוי לא מצא — בדיוק כמו "בחירת מיקום
              // ידנית" של אוצריא. מוצגת רק כשיש מה לחפש.
              if (app.canDetect && !app.canLaunch)
                ActionButton.ghost(
                  text: t.pickLocationButton,
                  icon: FluentIcons.folder_open_24_regular,
                  onPressed:
                      controller.isBusy ? null : () => _pickLocation(context),
                ),
              // שתיהן מורידות אל הכונן, או שואלות עליו — לא במצב קריאה.
              if (_isFromGithub && !readOnly) ...[
                ActionButton.neutral(
                  text: t.downloadButton,
                  icon: FluentIcons.arrow_download_24_regular,
                  isLoading: _isDownloading,
                  onPressed: controller.downloadingId != null
                      ? null
                      : () => _download(context),
                ),
                ActionButton.ghost(
                  text: t.checkOnlineButton,
                  icon: FluentIcons.arrow_sync_24_regular,
                  onPressed: () => controller.checkOnline(app.descriptor),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  StatusKind get _statusKind {
    if (!app.canDetect) return StatusKind.unknown;
    if (app.installed == null) return StatusKind.needsAction;
    return StatusKind.ok;
  }

  /// "אינה מותקנת" נאמר **רק** כשבאמת חיפשנו. בלי שם קובץ הרצה התשובה
  /// הנכונה היא "לא ניתן לדעת", וזה לא אותו דבר.
  String _installedLabel(BuildContext context) {
    final t = context.strings.customApps;
    if (!app.canDetect) return t.noDetectRules;

    final installed = app.installed;
    if (installed == null) return t.notInstalled;
    final version = installed.version;
    return version == null
        ? t.installedUnknownVersion
        : t.installedVersion(version);
  }

  String _storedLabel(BuildContext context) {
    final t = context.strings.customApps;
    final stored = app.storedInstaller;
    return stored == null
        ? t.noStoredInstaller
        : t.storedInstaller(stored.version);
  }

  /// מה שנמצא ברשת, כשנבדק. `null` כשלא נבדק — לא ממציאים מצב.
  String? _onlineLabel(BuildContext context) {
    if (!_isFromGithub) return null;
    final t = context.strings.customApps;
    final id = app.descriptor.id;

    if (controller.onlineUnavailable.contains(id)) return t.onlineUnavailable;
    final online = controller.onlineVersions[id];
    if (online == null) return null;
    return online == app.storedInstaller?.version
        ? t.onlineUpToDate
        : t.onlineVersionAvailable(online);
  }

  Future<void> _download(BuildContext context) async {
    final stored = await controller.download(app.descriptor.id);
    if (stored == null) {
      UiSnack.showError(controller.errorMessage ?? '');
      return;
    }
    UiSnack.showSuccess(
      AppL10n.strings.customApps.downloadedSnack(stored.version),
    );
  }

  Future<void> _install(BuildContext context) async {
    final t = context.strings.customApps;

    // כשהקובץ הוא התוכנה עצמה אין מה להתקין — רק להעתיק, והמשתמש הוא זה
    // שיודע לאן. ביטול הבחירה אינו שגיאה: פשוט לא קורה כלום.
    String? copyToDir;
    if (app.descriptor.portableFile) {
      copyToDir = await NativeFileDialogs.pickDirectory(
        dialogTitle: t.pickCopyTargetDialogTitle,
      );
      if (copyToDir == null) return;
    }

    final result = await controller.install(
      app.descriptor.id,
      copyToDir: copyToDir,
    );
    if (!result.ok) {
      UiSnack.showError(controller.errorMessage ?? '');
      return;
    }
    // שום דבר לא הותקן — הקובץ רק הועתק, וצריך לומר לאן.
    if (result.copiedPath case final path?) {
      final strings = AppL10n.strings.customApps;
      UiSnack.showSuccess(
        app.descriptor.portableFile
            ? strings.copiedFileSnack(path)
            : strings.archiveInDownloadsSnack(path),
      );
      return;
    }
    UiSnack.showSuccess(
      AppL10n.strings.customApps.installedSnack(app.descriptor.name),
    );
    // מה שנלמד נאמר במפורש: מכאן והלאה הכרטיס יפסיק לומר "לא ניתן לזהות",
    // וזה שינוי שהמשתמש כדאי שיבין מאיפה בא.
    if (result.learnedExeName case final exeName?) {
      UiSnack.show(AppL10n.strings.customApps.learnedDetectionSnack(exeName));
    }
  }

  Future<void> _pickLocation(BuildContext context) async {
    final t = context.strings.customApps;
    final dir = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.pickInstallDirDialogTitle,
    );
    if (dir == null) return;

    if (await controller.adoptInstallDir(app.descriptor, dir)) {
      UiSnack.showSuccess(AppL10n.strings.customApps.locationAdoptedSnack(dir));
      return;
    }
    UiSnack.showError(AppL10n.strings.customApps.locationNotFoundSnack);
  }
}
