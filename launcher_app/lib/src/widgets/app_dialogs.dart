// דיאלוגים גנריים M3 — פורט מאוצריא (`otzaria/lib/widgets/dialogs/`).
// אין להשתמש ב-showDialog עם AlertDialog מותאם ישירות; רק דרך העוזרים כאן.
//
// כללי הסגנון (זהים לאוצריא):
//  • singleAction — כפתור אישור אחד (recommended)
//  • twoActions   — ביטול (neutral/tonal) + אישור (recommended)
//  • warning      — ביטול (recommended — הבחירה הבטוחה) + אישור (warning/error)

import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../theme/theme_exports.dart';
import 'action_buttons.dart';

enum _DialogVariant { singleAction, twoActions, warning }

class AppDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? customContent;
  final String confirmText;
  final String cancelText;

  /// טקסט אזהרה בצבע error, מתחת לתוכן — רק בוריאנט warning.
  final String? subtitle;
  final _DialogVariant _variant;

  AppDialog.singleAction({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    String? confirmText,
  })  : _variant = _DialogVariant.singleAction,
        confirmText = confirmText ?? AppL10n.strings.common.confirm,
        cancelText = '',
        subtitle = null;

  AppDialog.twoActions({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    String? cancelText,
    String? confirmText,
  })  : _variant = _DialogVariant.twoActions,
        cancelText = cancelText ?? AppL10n.strings.common.cancel,
        confirmText = confirmText ?? AppL10n.strings.common.confirm,
        subtitle = null;

  AppDialog.warning({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    String? cancelText,
    String? confirmText,
    this.subtitle,
  })  : _variant = _DialogVariant.warning,
        cancelText = cancelText ?? AppL10n.strings.common.cancel,
        confirmText = confirmText ?? AppL10n.strings.common.continueAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title, style: theme.textTheme.titleLarge),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (content != null) Text(content!),
          if (customContent != null) customContent!,
          if (subtitle != null) ...[
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: _actions(context),
    );
  }

  List<Widget> _actions(BuildContext context) {
    void close(bool result) => Navigator.of(context).pop(result);

    return switch (_variant) {
      _DialogVariant.singleAction => [
          ActionButton.recommended(
            text: confirmText,
            onPressed: () => close(true),
          ),
        ],
      _DialogVariant.twoActions => [
          ActionButton.neutral(text: cancelText, onPressed: () => close(false)),
          ActionButton.recommended(
            text: confirmText,
            onPressed: () => close(true),
          ),
        ],
      // באזהרה הכפתור המומלץ הוא דווקא הביטול — הבחירה הבטוחה.
      _DialogVariant.warning => [
          ActionButton.warning(
            text: confirmText,
            onPressed: () => close(true),
          ),
          ActionButton.recommended(
            text: cancelText,
            onPressed: () => close(false),
          ),
        ],
    };
  }
}

Future<void> showSingleActionDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  String? confirmText,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => AppDialog.singleAction(
        title: title,
        content: content,
        customContent: customContent,
        confirmText: confirmText,
      ),
    );

Future<bool> showTwoActionsDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  String? cancelText,
  String? confirmText,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog.twoActions(
        title: title,
        content: content,
        customContent: customContent,
        cancelText: cancelText,
        confirmText: confirmText,
      ),
    ) ??
    false;

Future<bool> showWarningDialog({
  required BuildContext context,
  required String title,
  String? content,
  Widget? customContent,
  String? subtitle,
  String? cancelText,
  String? confirmText,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog.warning(
        title: title,
        content: content,
        customContent: customContent,
        subtitle: subtitle,
        cancelText: cancelText,
        confirmText: confirmText,
      ),
    ) ??
    false;
