import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../self_update/payload_check.dart';
import '../theme/theme_exports.dart';
import '../widgets/widgets_exports.dart';
import 'tasks/task_parts.dart';

/// קובץ ההרצה והקבצים שלצידו משתי גרסאות ([PayloadCheck]). אין "המשך":
/// זה המצב שמסתיים בקריסה, וסגירה ופתיחה מחדש משלימות את החילוץ.
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
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.payloadMismatch;

    Widget version(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$label: '),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: AppTextStyles.semibold,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
          ),
        );

    return Scaffold(
      backgroundColor: AppSurfaces.panelBackground(context),
      body: Column(
        children: [
          AppTitleBar(showTitle: false, showWindowButtons: showWindowButtons),
          Expanded(
            child: TaskResult(
              badge: const ResultBadge(
                kind: ResultBadgeKind.error,
                icon: FluentIcons.warning_24_regular,
              ),
              title: t.title,
              body: t.explanation,
              extra: [
                const SizedBox(height: 10),
                Text(
                  t.whatToDo,
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.body.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                version(t.runningVersionTitle, mismatch.runningVersion),
                version(t.expectedVersionTitle, mismatch.stubVersion),
              ],
              actions: [
                ActionButton.recommended(
                  text: t.closeButton,
                  icon: FluentIcons.dismiss_24_regular,
                  size: ActionButtonSize.lg,
                  expand: true,
                  autofocus: true,
                  onPressed: onClose ?? () => exit(0),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
