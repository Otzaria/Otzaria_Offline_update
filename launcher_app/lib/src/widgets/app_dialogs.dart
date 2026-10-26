// כל דו-שיח עובר כאן (לא AlertDialog ישיר): רוחב 336, 440 עם שדות, ריפוד 24.
// warning — הביטול הוא הכפתור המומלץ, והפעולה יושבת בקצה.

import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../theme/theme_exports.dart';
import 'action_buttons.dart';

enum _DialogVariant { singleAction, twoActions, warning, custom }

class AppDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? customContent;
  final String confirmText;
  final String cancelText;

  /// טקסט אזהרה בצבע error, מתחת לתוכן — בוריאנטים warning ו-twoActions.
  final String? subtitle;

  /// `null` = 336 לדו-שיח טקסט, 440 כשיש [customContent].
  final double? width;
  final _DialogVariant _variant;
  final List<Widget> _customActions;

  AppDialog.singleAction({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    String? confirmText,
    this.width,
  })  : _variant = _DialogVariant.singleAction,
        confirmText = confirmText ?? AppL10n.strings.common.confirm,
        cancelText = '',
        subtitle = null,
        _customActions = const [];

  /// טופס עם פעולות משלו (שליחה עם מחוון, למשל) — אותה מסגרת ואותה טיפוגרפיה.
  /// [customContent] גולל בעצמו: `Flexible` + `SingleChildScrollView`.
  const AppDialog.custom({
    super.key,
    required this.title,
    required Widget this.customContent,
    required List<Widget> actions,
    this.width,
  })  : _variant = _DialogVariant.custom,
        _customActions = actions,
        content = null,
        confirmText = '',
        cancelText = '',
        subtitle = null;

  AppDialog.twoActions({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    String? cancelText,
    String? confirmText,
    this.subtitle,
    this.width,
  })  : _variant = _DialogVariant.twoActions,
        cancelText = cancelText ?? AppL10n.strings.common.cancel,
        confirmText = confirmText ?? AppL10n.strings.common.confirm,
        _customActions = const [];

  AppDialog.warning({
    super.key,
    required this.title,
    this.content,
    this.customContent,
    String? cancelText,
    String? confirmText,
    this.subtitle,
    this.width,
  })  : _variant = _DialogVariant.warning,
        cancelText = cancelText ?? AppL10n.strings.common.cancel,
        confirmText = confirmText ?? AppL10n.strings.common.continueAction,
        _customActions = const [];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outer = width ??
        (customContent == null
            ? AppTokens.dialogWidth
            : AppTokens.dialogFormWidth);
    const pad = AppTokens.spaceLG;

    return AlertDialog(
      // תוכן טקסט ארוך גולל במקום לגלוש. ל-`customContent` זה **אסור**: הוא
      // מביא גליל משלו, ו-`Flexible` בתוך גליל חיצוני נופל.
      scrollable: customContent == null,
      insetPadding: const EdgeInsets.all(pad),
      titlePadding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      contentPadding: const EdgeInsets.fromLTRB(pad, 10, pad, 0),
      actionsPadding: const EdgeInsets.fromLTRB(pad, pad, pad, pad),
      actionsAlignment: MainAxisAlignment.end,
      buttonPadding: EdgeInsets.zero,
      title: Text(title),
      content: SizedBox(
        width: outer - 2 * pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (content != null) Text(content!),
            if (customContent != null) customContent!,
            if (subtitle != null) ...[
              const SizedBox(height: AppTokens.spaceMD),
              Text(
                subtitle!,
                style: AppTextStyles.dialogBody.copyWith(color: cs.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppTokens.spaceSM,
          runSpacing: AppTokens.spaceSM,
          children: [
            for (final action in _actions(context))
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 104),
                child: action,
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    void close(bool result) => Navigator.of(context).pop(result);

    // הכפתור המומלץ מקבל את המיקוד, ולכן Enter מפעיל אותו בלי לגעת בעכבר.
    // רק כשהתוכן הוא טקסט: ל-`customContent` יש שדות משלו, והמיקוד שלהם.
    final defaultAction = customContent == null;

    return switch (_variant) {
      _DialogVariant.custom => _customActions,
      _DialogVariant.singleAction => [
          ActionButton.recommended(
            text: confirmText,
            onPressed: () => close(true),
            autofocus: defaultAction,
          ),
        ],
      _DialogVariant.twoActions => [
          ActionButton.ghost(text: cancelText, onPressed: () => close(false)),
          ActionButton.recommended(
            text: confirmText,
            onPressed: () => close(true),
            autofocus: defaultAction,
          ),
        ],
      // באזהרה הכפתור המומלץ הוא דווקא הביטול — הבחירה הבטוחה, ולכן גם זו
      // ש-Enter בוחר. הפעולה ההרסנית יושבת בקצה, כמו במוקאפ.
      _DialogVariant.warning => [
          ActionButton.recommended(
            text: cancelText,
            onPressed: () => close(false),
            autofocus: defaultAction,
          ),
          ActionButton.warning(
            text: confirmText,
            onPressed: () => close(true),
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
  String? subtitle,
  String? cancelText,
  String? confirmText,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog.twoActions(
        title: title,
        content: content,
        customContent: customContent,
        subtitle: subtitle,
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
