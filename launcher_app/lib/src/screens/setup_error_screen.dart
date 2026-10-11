import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/app_paths.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';

class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen(
      {super.key, required this.error, this.showWindowButtons});

  final AppPathsException error;
  final bool? showWindowButtons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.setupError;
    final title = switch (error.kind) {
      AppPathsFailure.cannotWrite => t.title,
      AppPathsFailure.driveFull => t.driveFullTitle,
      AppPathsFailure.appTranslocated => t.appTranslocatedTitle,
    };
    final generic = error.kind == AppPathsFailure.cannotWrite;

    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      body: Column(
        children: [
          AppTitleBar(screenTitle: '', showWindowButtons: showWindowButtons),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTokens.spaceLG),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppTokens.spaceLG),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              FluentIcons.folder_prohibited_24_regular,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: AppTokens.spaceSM),
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.spaceMD),
                        if (generic) ...[
                          Text(t.explanation,
                              style: theme.textTheme.bodyMedium),
                          const SizedBox(height: AppTokens.spaceMD),
                          Text(t.whatToDo, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: AppTokens.spaceMD),
                          InfoErrorRow(message: error.message),
                        ] else ...[
                          SelectableText(error.message,
                              style: theme.textTheme.bodyMedium),
                          const SizedBox(height: AppTokens.spaceMD),
                        ],
                        SettingsActionTile.path(
                          icon: FluentIcons.folder_24_regular,
                          title: t.attemptedDirTitle,
                          path: error.attemptedDir,
                          placeholder: context.strings.common.emptyValue,
                          actions: [
                            CopyPathButton(path: error.attemptedDir),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
