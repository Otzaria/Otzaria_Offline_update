import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:plugins_manager/plugins_manager.dart';

import '../../controllers/plugins_module_controller.dart';
import '../../services/app_logger.dart';
import '../../services/byte_size.dart';
import '../../services/file_reveal.dart';
import '../../services/hebrew_date.dart';
import '../../services/native_file_dialogs.dart';
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
  const StoreAppExportButton({super.key, required this.controller});

  final PluginsModuleController controller;

  /// הפלטפורמות שיש להן מה לעשות עם קובץ ההרצה. מוחזק כאן כדי ששורת
  /// הסנכרון תוכל להשמיט את הכפתור לגמרי במקום להציג אותו מושבת לנצח.
  static bool get isSupported => Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.plugins;
    final enabled = controller.canExportStoreApp && !controller.isExporting;

    // כפתור מושבת בלי מילה נקרא כתקלה — ולכן לכל סיבה יש נוסח משלה.
    final tooltip = controller.storeApp == null
        ? t.storeAppUnavailableTooltip
        : (controller.plugins.isEmpty ? t.storeAppNoPluginsTooltip : null);

    final button = ActionButton.neutral(
      text: t.storeAppButton,
      icon: FluentIcons.desktop_arrow_down_24_regular,
      isLoading: controller.isExporting,
      onPressed: enabled ? () => runStoreAppExport(context, controller) : null,
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

  if (!await _showIntroDialog(context, release)) return;
  if (!context.mounted) return;

  final t = context.strings.plugins;
  final destination = await NativeFileDialogs.pickDirectory(
    dialogTitle: t.storeAppPickFolderTitle,
  );
  if (destination == null || !context.mounted) return;

  // דריסה מאושרת מראש: בתיקייה עשויים לשבת `state.json` ויומנים של החנות
  // הקיימת, והם **אינם** נמחקים — רק נדרסים הקבצים שאנחנו כותבים.
  if (await StoreAppExporter.hasExistingStore(destination)) {
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
  } catch (e, st) {
    AppLogger.instance.error('העתקת חנות התוספים נכשלה', e, st);
    UiSnack.show(t.storeAppFailedSnack('$e'));
    return;
  }

  AppLogger.instance.info('חנות התוספים הועתקה אל $destination: '
      '${outcome.plugins} תוספים, ${formatBytes(outcome.bytes)}');
  if (outcome.skipped.isNotEmpty) {
    AppLogger.instance.info('הושמטו: ${outcome.skipped.join(', ')}');
  }
  if (!context.mounted) return;
  await _showDoneDialog(context, outcome);
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
        if (updated != null)
          t.storeAppChipUpdated(HebrewDate.format(updated.toIso8601String())),
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

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(t.storeAppDoneTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.storeAppDoneContent(
            outcome.plugins,
            formatBytes(outcome.bytes),
          )),
          if (outcome.skipped.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              t.storeAppDoneSkipped(outcome.skipped.length),
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceSM),
          CopyPathButton(path: outcome.destinationDir),
        ],
      ),
      actions: [
        ActionButton.ghost(
          text: context.strings.common.close,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        ActionButton.neutral(
          text: t.storeAppOpenFolder,
          icon: FluentIcons.folder_open_24_regular,
          onPressed: () {
            Navigator.of(dialogContext).pop();
            FileReveal.revealDirectory(outcome.destinationDir);
          },
        ),
        ActionButton.recommended(
          text: t.storeAppLaunch,
          icon: FluentIcons.play_24_regular,
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _launch(outcome.appPath);
          },
        ),
      ],
    ),
  );
}

/// שכבת חסימה בזמן ההעתקה. נפרדת מ-`PluginSyncOverlay` בכוונה: שם יש
/// אזהרות מצטברות ושם מדובר ברשת, וכאן דווקא חשוב לומר שאין.
class StoreAppExportOverlay extends StatelessWidget {
  const StoreAppExportOverlay({super.key, required this.controller});

  final PluginsModuleController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = context.strings.plugins;
    final progress = controller.exportProgress;

    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: cs.surface,
            borderRadius: AppTokens.borderRadiusAll,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLG),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.storeAppCopyingTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppTokens.spaceXS),
                  Text(
                    t.storeAppCopyingSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    controller.exportMessage ?? '',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  ClipRRect(
                    borderRadius: AppTokens.borderRadiusAll,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: AppTokens.spaceXS),
                    Text(
                      '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// מנותק מהלאנצ'ר בכוונה: החנות היא תוכנה נפרדת, וסגירת הלאנצ'ר אינה
/// אמורה לסגור אותה. כשל כאן נכתב ליומן — הקובץ נמצא בתיקייה שנפתחה.
void _launch(String appPath) {
  try {
    Process.start(appPath, const [], mode: ProcessStartMode.detached);
  } catch (e) {
    AppLogger.instance.info('הפעלת חנות התוספים נכשלה: $e');
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
