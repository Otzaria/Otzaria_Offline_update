import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../services/app_paths.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';

/// מוצג במקום האפליקציה כשלא ניתן להשתמש בתיקייה שצמודה לתוכנה. אין כאן
/// "המשך בכל זאת": התוכנה מיועדת לכונן נייד, ומיקום שאי אפשר לכתוב בו הוא
/// התקנה במקום הלא נכון (ראו [AppPaths]).
class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen(
      {super.key, required this.error, this.showWindowButtons});

  final AppPathsException error;

  /// ראו [AppTitleBar.showWindowButtons] — מוזרק `false` בבדיקות widget.
  final bool? showWindowButtons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.setupError;

    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      // שורת הכותרת חובה גם כאן: מסגרת החלון של המערכת כבר הוסתרה ב-`main`,
      // ובלעדיה המסך הזה הוא חלון בלי סגירה, בלי מזעור ובלי גרירה.
      body: Column(
        children: [
          // בלי שם מסך: אין כאן ניווט, והכותרת עצמה מופיעה בכרטיס שמתחת.
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
                                t.title,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.spaceMD),
                        Text(t.explanation, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: AppTokens.spaceMD),
                        Text(t.whatToDo, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: AppTokens.spaceMD),
                        InfoErrorRow(message: error.message),
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
