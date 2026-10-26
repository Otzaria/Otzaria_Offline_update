import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/app_paths.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'tasks/task_parts.dart';

/// התוכנה לא יכולה לכתוב לתיקיית הנתונים — במבנה של מסך כישלון במשימה,
/// בלי "המשך בכל זאת".
class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen(
      {super.key, required this.error, this.showWindowButtons});

  final AppPathsException error;
  final bool? showWindowButtons;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.setupError;
    final title = switch (error.kind) {
      AppPathsFailure.cannotWrite => t.title,
      AppPathsFailure.driveFull => t.driveFullTitle,
      AppPathsFailure.appTranslocated => t.appTranslocatedTitle,
      AppPathsFailure.runningFromTemp => t.runningFromTempTitle,
      AppPathsFailure.systemDrive => t.systemDriveTitle,
    };
    final generic = error.kind == AppPathsFailure.cannotWrite;
    final muted = AppTextStyles.body.copyWith(color: cs.onSurfaceVariant);

    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      body: Column(
        children: [
          AppTitleBar(showTitle: false, showWindowButtons: showWindowButtons),
          Expanded(
            child: TaskResult(
              badge: const ResultBadge(
                kind: ResultBadgeKind.error,
                icon: FluentIcons.folder_prohibited_24_regular,
              ),
              title: title,
              body: generic ? t.explanation : error.message,
              extra: [
                if (generic) ...[
                  const SizedBox(height: 10),
                  Text(t.whatToDo, textAlign: TextAlign.center, style: muted),
                  const SizedBox(height: 16),
                  InfoErrorRow(message: error.message),
                ],
                const SizedBox(height: 12),
                Text(
                  t.attemptedDirTitle,
                  style: AppTextStyles.meta.copyWith(color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                PathText(error.attemptedDir),
              ],
              actions: [
                ActionButton.recommended(
                  text: context.strings.common.copyPathButton,
                  icon: FluentIcons.copy_24_regular,
                  size: ActionButtonSize.lg,
                  expand: true,
                  autofocus: true,
                  onPressed: () => copyPath(error.attemptedDir),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
