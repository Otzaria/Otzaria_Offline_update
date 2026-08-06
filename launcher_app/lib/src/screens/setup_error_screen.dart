import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_paths.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';

/// מוצג במקום האפליקציה כשלא ניתן להשתמש בתיקייה שצמודה לתוכנה. אין כאן
/// "המשך בכל זאת": התוכנה מיועדת לכונן נייד, ומיקום שאי אפשר לכתוב בו הוא
/// התקנה במקום הלא נכון (ראו [AppPaths]).
class SetupErrorScreen extends StatelessWidget {
  const SetupErrorScreen({super.key, required this.error});

  final AppPathsException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      body: Center(
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
                          'התוכנה נמצאת במקום שאינו מתאים',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    'הלאנצ׳ר שומר את כל הנתונים — הספרייה, התוספים וגרסת '
                    'אוצריא — בתיקייה שצמודה לו, כדי שהכול ייסע יחד על הכונן. '
                    'בתיקייה הנוכחית אין הרשאת כתיבה, ולכן אין לאן לשמור.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    'מה לעשות: להעביר את תיקיית התוכנה כולה לכונן הנייד '
                    '(או לכל תיקייה בדיסק שאינה תחת Program Files), '
                    'ולהפעיל אותה משם.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  InfoErrorRow(message: error.message),
                  SettingsActionTile.path(
                    icon: FluentIcons.folder_24_regular,
                    title: 'התיקייה שנוסתה',
                    path: error.attemptedDir,
                    placeholder: '—',
                    actions: [
                      ActionButton.neutral(
                        text: 'העתקת הנתיב',
                        icon: FluentIcons.copy_24_regular,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: error.attemptedDir),
                          );
                          UiSnack.showSuccess('הנתיב הועתק');
                        },
                      ),
                    ],
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
