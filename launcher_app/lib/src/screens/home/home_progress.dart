import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../controllers/launcher_update_controller.dart';
import '../../controllers/library_module_controller.dart';
import '../../controllers/otzaria_module_controller.dart';
import '../../controllers/plugins_module_controller.dart';
import '../../flows/library_flows.dart';
import '../../services/byte_size.dart';
import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'home_view_model.dart';

/// מד המשימה שבגיבור. כל מה שנכתב לפני `notifyProgress` נקרא כאן בתוך
/// `ListenableBuilder` על ה-progress — אחרת הוא קופא עד שינוי המצב הבא.
class HomeTaskProgress extends StatelessWidget {
  const HomeTaskProgress({
    super.key,
    required this.task,
    required this.otzaria,
    required this.library,
    required this.plugins,
  });

  final HomeTask task;
  final OtzariaModuleController otzaria;
  final LibraryModuleController library;
  final PluginsModuleController plugins;

  @override
  Widget build(BuildContext context) => switch (task) {
        HomeTask.downloading => ListenableBuilder(
            listenable: Listenable.merge([
              otzaria.progress,
              library.progress,
              plugins.progress,
            ]),
            builder: (context, _) => _downloadRow(context),
          ),
        HomeTask.updatingLibrary => libraryApplyProgressRow(context, library),
        HomeTask.installingApp => ListenableBuilder(
            listenable: Listenable.merge([otzaria, otzaria.progress]),
            builder: (context, _) => _installRow(context),
          ),
        // השאר — "הצג התקדמות" פותח את הדף שבו הן רצות.
        _ => const SizedBox.shrink(),
      };

  /// "הפסק להמתין" רק כשהאשף ממשיך בחלון משלו — אז ההמתנה לו היא שנעצרת.
  Widget _installRow(BuildContext context) {
    final stage = otzaria.installStage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoProgressRow(stage: stage ?? context.strings.common.installing),
        if (stage != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppTokens.spaceMD),
            child: ActionButton.ghost(
              key: ShellKeys.heroStopWaiting,
              text: context.strings.task.stopWaiting,
              icon: FluentIcons.dismiss_circle_24_regular,
              size: ActionButtonSize.sm,
              onPressed: otzaria.stopWaitingForSetup,
            ),
          ),
      ],
    );
  }

  /// ההורדה עוברת בין התוכנה, הספרייה והתוספים — מד אחד למה שרץ עכשיו.
  Widget _downloadRow(BuildContext context) {
    final t = context.strings.home;
    if (otzaria.downloadStatus == OtzariaDownloadStatus.downloading) {
      final received = otzaria.downloadReceived;
      final total = otzaria.downloadTotal;
      return InfoProgressRow(
        stage: otzaria.downloadStage ?? t.downloadingApp,
        progress: (received != null && total != null && total > 0)
            ? received / total
            : null,
        detail: formatBytesProgress(received, total),
      );
    }
    if (library.downloadStatus == MirrorDownloadStatus.downloading) {
      return InfoProgressRow(
        stage: library.downloadStage ?? t.downloadingLibrary,
        progress: library.downloadProgress,
        secondaryStage: library.downloadCompanionStage,
        detail: formatBytesProgress(
          library.downloadReceivedBytes,
          library.downloadTotalBytes,
        ),
      );
    }
    if (plugins.status == PluginsModuleStatus.syncing) {
      return InfoProgressRow(
        stage: plugins.syncMessage ?? t.downloadingPlugins,
        progress: plugins.syncProgress,
      );
    }
    return InfoProgressRow(stage: t.downloadStarting);
  }
}

/// האחוז שליד "מוריד את הגרסה החדשה של הכלי" בתחתית הבית.
class LauncherDownloadPercent extends StatelessWidget {
  const LauncherDownloadPercent({super.key, required this.controller});

  final LauncherUpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller.progress,
        builder: (context, _) {
          final total = controller.downloadTotal ?? 0;
          final received = controller.downloadReceived ?? 0;
          if (total <= 0) return const SizedBox.shrink();
          return Text(
            '${(received * 100 / total).floor()}%',
            textDirection: TextDirection.ltr,
            style: AppTextStyles.meta.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        },
      );
}
