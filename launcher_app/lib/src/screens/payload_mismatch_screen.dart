import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../self_update/payload_check.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';

/// מוצג במקום האפליקציה כשקובץ ההרצה וערמת הקבצים שלצידו הם משתי גרסאות
/// שונות (ראו [PayloadCheck]). כמו [SetupErrorScreen] אין כאן "המשך בכל
/// זאת": זה בדיוק המצב שמסתיים בקריסה, והפעולה שמתקנת אותו היא סגירה
/// ופתיחה מחדש — ה-stub משלים אז את החילוץ בעצמו.
class PayloadMismatchScreen extends StatelessWidget {
  const PayloadMismatchScreen({
    super.key,
    required this.mismatch,
    this.showWindowButtons,
    this.onClose,
  });

  final PayloadMismatch mismatch;

  /// ראו [AppTitleBar.showWindowButtons] — מוזרק `false` בבדיקות widget.
  final bool? showWindowButtons;

  /// מוזרק בבדיקות; בהרצה אמיתית זו סגירת התהליך.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.strings.payloadMismatch;

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
                              FluentIcons.warning_24_regular,
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
                        SettingsActionTile.text(
                          icon: FluentIcons.box_24_regular,
                          title: t.runningVersionTitle,
                          subtitle: mismatch.runningVersion,
                          subtitleLtr: true,
                        ),
                        SettingsActionTile.text(
                          icon: FluentIcons.document_24_regular,
                          title: t.expectedVersionTitle,
                          subtitle: mismatch.stubVersion,
                          subtitleLtr: true,
                        ),
                        const SizedBox(height: AppTokens.spaceMD),
                        CardActionsRow(
                          actions: [
                            ActionButton.recommended(
                              text: t.closeButton,
                              icon: FluentIcons.dismiss_24_regular,
                              onPressed: onClose ?? () => exit(0),
                            ),
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
