import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/app_logger.dart';
import '../../services/byte_size.dart';
import '../../services/file_reveal.dart';
import '../../services/native_file_dialogs.dart';
import '../../services/timestamps.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// "העתקת החנות למחשב" — הכפתור, ההסבר והזרימה שאחריו.
///
/// מקביל לכפתור שבאתר (`Otzaria_Website#171`), עם הבדל אחד: שם ההורדה
/// מביאה מגיטהאב את החבילה המלאה, וכאן מועתקת **התוכנה הבסיסית מהכונן**
/// ו-`Data\` נארזת מהמראה שכבר יש. לכן אין כאן שום נגיעה ברשת, וזו כל
/// הנקודה — המחשב שמעתיקים בו הוא בדרך כלל המנותק.
///
/// **ווינדוס בלבד**: הנכס היחיד שמפורסם הוא `.exe`, ומק אינו יכול להריץ
/// אותו. ראו [StoreAppExportButton.isSupported].
class StoreAppExportButton extends StatelessWidget {
  const StoreAppExportButton({
    super.key,
    required this.controller,
    required this.onExport,
    this.busyElsewhere = false,
  });

  final PluginsModuleController controller;

  /// הזרימה רצה על ה-context של המסך: הכפתור יושב ב"מתקדם", ויוצא מהעץ
  /// כשמקפלים אותו או נכנסים לדף תוסף באמצע ההעתקה.
  final VoidCallback onExport;
  final bool busyElsewhere;

  /// הפלטפורמות שיש להן מה לעשות עם קובץ ההרצה — בשאר השורה מושמטת.
  static bool get isSupported => Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;
    final enabled = controller.canExportStoreApp &&
        !controller.isExporting &&
        !controller.isSyncing &&
        !busyElsewhere;

    // כפתור מושבת בלי מילה נקרא כתקלה — ולכן לכל סיבה יש נוסח משלה.
    final tooltip = controller.storeApp == null
        ? t.storeAppUnavailableTooltip
        : (controller.plugins.isEmpty ? t.storeAppNoPluginsTooltip : null);

    final button = ActionButton.neutral(
      text: controller.storeAppUpdatePending
          ? t.storeAppUpdateButton
          : t.storeAppCopyButton,
      icon: FluentIcons.desktop_arrow_down_20_regular,
      isLoading: controller.isExporting,
      onPressed: enabled ? onExport : null,
    );

    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// ההסבר, בחירת התיקייה, ההעתקה וההודעה שבסוף — הכול בזרימה אחת.
Future<void> runStoreAppExport(
  BuildContext context,
  PluginsModuleController controller,
) async {
  final release = controller.storeApp?.release;
  if (release == null) return;

  final t = context.strings.plugins;
  // עדכון באותה תיקייה: בלי הסבר ובלי בחירה מחדש, והדריסה כבר מאושרת.
  String? destination;
  final remembered = controller.rememberedStoreDir;
  if (controller.storeAppUpdatePending && remembered != null) {
    final updateHere = await showTwoActionsDialog(
      context: context,
      title: t.storeAppUpdateHereTitle,
      content: t.storeAppUpdateHereContent(remembered),
      cancelText: t.storeAppChooseOtherFolder,
      confirmText: t.storeAppOverwriteConfirm,
    );
    if (!context.mounted) return;
    if (updateHere) destination = remembered;
  }
  final updatingHere = destination != null;

  if (!updatingHere) {
    if (!await _showIntroDialog(context, release)) return;
    if (!context.mounted) return;
    destination = await NativeFileDialogs.pickDirectory(
      dialogTitle: t.storeAppPickFolderTitle,
    );
    if (destination == null || !context.mounted) return;
  }

  // דריסה מאושרת מראש: בתיקייה עשויים לשבת `state.json` ויומנים של החנות
  // הקיימת, והם **אינם** נמחקים — רק נדרסים הקבצים שאנחנו כותבים.
  if (!updatingHere && await StoreAppExporter.hasExistingStore(destination)) {
    if (!context.mounted) return;
    final approved = await showTwoActionsDialog(
      context: context,
      title: t.storeAppOverwriteTitle,
      content: t.storeAppOverwriteContent(destination),
      confirmText: t.storeAppOverwriteConfirm,
    );
    if (!approved || !context.mounted) return;
  }

  final StoreAppExportOutcome outcome;
  try {
    outcome = await controller.exportStoreApp(destination);
  } on PluginMirrorBusy catch (e) {
    UiSnack.show(e.message);
    return;
  } catch (e, st) {
    AppLogger.instance.error('העתקת חנות התוספים נכשלה', e, st);
    // 32 = קובץ בשימוש: החנות רצה ולא ניתן לדרוס את קובץ ההרצה שלה.
    final busy = e is FileSystemException && e.osError?.errorCode == 32;
    UiSnack.show(busy ? t.storeAppInUseSnack : t.storeAppFailedSnack('$e'));
    return;
  }

  AppLogger.instance.info('חנות התוספים הועתקה אל $destination: '
      '${outcome.plugins} תוספים, ${formatBytes(outcome.bytes)}');
  if (outcome.skipped.isNotEmpty) {
    AppLogger.instance.info('הושמטו: ${outcome.skipped.join(', ')}');
  }
  // המסך עצמו עשוי להתחלף בזמן ההעתקה; אז הסיום עולה מעל המסגרת כולה.
  final host = context.mounted ? context : navigatorKey.currentContext;
  if (host == null || !host.mounted) return;
  await _showDoneDialog(host, outcome);
}

/// ההסבר לפני שנוגעים בכלום — אותם שלושה יתרונות ואותם שבבים שבאתר.
Future<bool> _showIntroDialog(
  BuildContext context,
  StoreAppRelease release,
) async {
  final t = context.strings.plugins;
  final updated = release.publishedAt;

  return showTwoActionsDialog(
    context: context,
    title: t.storeAppDialogTitle,
    confirmText: t.storeAppChooseFolder,
    customContent: _IntroContent(
      body: t.storeAppDialogBody,
      highlights: [
        (FluentIcons.puzzle_piece_24_regular, t.storeAppHighlightBundled),
        (FluentIcons.wifi_off_24_regular, t.storeAppHighlightOffline),
        (FluentIcons.arrow_download_24_regular, t.storeAppHighlightDirect),
      ],
      chips: [
        t.storeAppChipWindows,
        t.storeAppChipSize(formatBytes(release.sizeBytes)),
        if (updated != null) t.storeAppChipUpdated(formatStoreDate(updated)),
      ],
    ),
  );
}

/// סיום: מה נכתב, ומה אפשר לעשות עכשיו. שני הכפתורים אינם "אישור" —
/// פתיחת התיקייה והפעלת החנות הן הצעדים הטבעיים הבאים, וסגירה רגילה
/// מסיימת בלעדיהם.
Future<void> _showDoneDialog(
  BuildContext context,
  StoreAppExportOutcome outcome,
) async {
  final t = context.strings.plugins;
  final launch = await showTwoActionsDialog(
    context: context,
    title: t.storeAppDoneTitle,
    cancelText: context.strings.common.close,
    confirmText: t.storeAppLaunch,
    customContent: Builder(
      builder: (dialogContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.storeAppDoneContent(
              outcome.plugins, formatBytes(outcome.bytes))),
          if (outcome.skipped.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Text(t.storeAppDoneSkipped(outcome.skipped.length)),
          ],
          const SizedBox(height: AppTokens.spaceSM),
          PathText(outcome.destinationDir),
          const SizedBox(height: AppTokens.spaceXS),
          Wrap(
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceXS,
            children: [
              ActionButton.ghost(
                text: t.storeAppOpenFolder,
                icon: FluentIcons.folder_open_20_regular,
                size: ActionButtonSize.sm,
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                  unawaited(FileReveal.revealDirectory(outcome.destinationDir));
                },
              ),
              CopyPathButton(
                path: outcome.destinationDir,
                size: ActionButtonSize.sm,
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (launch && context.mounted) unawaited(_launch(outcome.appPath));
}

/// ההתקדמות בשורת ההעתקה — לא שכבה מעל הדף.
class StoreAppCopyProgress extends StatelessWidget {
  const StoreAppCopyProgress({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller.progress,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: InfoProgressRow(
            stage: controller.exportMessage ??
                context.strings.plugins.storeAppCopyingTitle,
            progress: controller.exportProgress,
          ),
        ),
      );
}

/// מנותק מהלאנצ'ר בכוונה: החנות היא תוכנה נפרדת, וסגירת הלאנצ'ר אינה
/// אמורה לסגור אותה.
///
/// ⚠️ **`await` ולא "שגר ושכח".** `Process.start` מחזיר `Future`, וקובץ
/// חסר נכשל בתוכו ולא בזריקה סינכרונית — ה-`try` לא תפס אותו, השגיאה
/// נבלעה כחריג אסינכרוני בלי מטפל, והכפתור פשוט לא עשה כלום.
Future<void> _launch(String appPath) async {
  // הקובץ נבדק לפני ההפעלה, כי הוא עלול להיעלם **אחרי** שההעתקה הסתיימה:
  // Defender מחק אותו שנייה אחת אחרי סיום ייצוא מוצלח (22/09/2026,
  // `Trojan:Win32/Wacatac.B!ml`). בלי הבדיקה המשתמש קיבל
  // `ProcessException: The system cannot find the file specified` —
  // נכון טכנית, ולא אומר דבר על מה שבאמת קרה.
  if (!await File(appPath).exists()) {
    AppLogger.instance.info('קובץ ההרצה של החנות נעלם מ-$appPath');
    UiSnack.show(AppL10n.strings.pluginsDomain.exportAppVanished(appPath));
    return;
  }

  try {
    await Process.start(appPath, const [], mode: ProcessStartMode.detached);
  } catch (e) {
    AppLogger.instance.info('הפעלת חנות התוספים נכשלה: $e');
    UiSnack.show(AppL10n.strings.plugins.storeAppLaunchFailedSnack('$e'));
  }
}

class _IntroContent extends StatelessWidget {
  const _IntroContent({
    required this.body,
    required this.highlights,
    required this.chips,
  });

  final String body;
  final List<(IconData, String)> highlights;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(body),
        const SizedBox(height: AppTokens.spaceMD),
        for (final (icon, text) in highlights)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RtlIcon(icon, size: 18, color: cs.primary),
                const SizedBox(width: AppTokens.spaceSM),
                Expanded(child: Text(text)),
              ],
            ),
          ),
        const SizedBox(height: AppTokens.spaceXS),
        Wrap(
          spacing: AppTokens.spaceXS,
          runSpacing: AppTokens.spaceXS,
          children: [
            for (final chip in chips)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceSM,
                  vertical: AppTokens.spaceXS,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Text(
                  chip,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
