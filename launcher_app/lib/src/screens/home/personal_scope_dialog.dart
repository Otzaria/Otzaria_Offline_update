import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../shell/session_prompts.dart' show PersonalScopeAnswer;
import '../../shell/shell_keys.dart';
import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// השאלה של ההפעלה הראשונה בכונן. `null` — נסגר בלי תשובה (Esc, מחוץ לחלון).
Future<PersonalScopeAnswer?> showPersonalScopeDialog(BuildContext context) =>
    showDialog<PersonalScopeAnswer>(
      context: context,
      builder: (_) => const _PersonalScopeDialog(),
    );

class _PersonalScopeDialog extends StatefulWidget {
  const _PersonalScopeDialog();

  @override
  State<_PersonalScopeDialog> createState() => _PersonalScopeDialogState();
}

class _PersonalScopeDialogState extends State<_PersonalScopeDialog> {
  /// בלי בחירה מראש: זו שאלה, לא ברירת מחדל שמאשרים ב-Enter.
  bool? _mine;
  bool _android = false;

  @override
  Widget build(BuildContext context) {
    final t = context.strings.libraryScreen;
    final cs = Theme.of(context).colorScheme;
    return AppDialog.custom(
      key: ShellKeys.personalAskDialog,
      title: t.personalAskTitle,
      width: AppTokens.dialogWideWidth,
      customContent: Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTokens.spaceSM),
              OptionCard(
                key: ShellKeys.personalAskMultiple,
                icon: FluentIcons.laptop_multiple_24_regular,
                title: t.personalAskMultiple,
                description: t.personalAskMultipleBody,
                selected: _mine == false,
                onSelected: () => setState(() => _mine = false),
              ),
              const SizedBox(height: 10),
              OptionCard(
                key: ShellKeys.personalAskMine,
                icon: FluentIcons.person_24_regular,
                title: t.personalAskMine,
                description: t.personalAskMineBody,
                selected: _mine == true,
                onSelected: () => setState(() => _mine = true),
              ),
              const SizedBox(height: AppTokens.spaceMD),
              FormCheckRow(
                key: ShellKeys.personalAskAndroid,
                label: t.personalAskAndroid,
                help: t.personalAskAndroidBody,
                value: _android,
                onChanged: (v) => setState(() => _android = v),
              ),
              Text(
                t.personalAskLater,
                style: AppTextStyles.small.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        ActionButton.recommended(
          key: ShellKeys.personalAskConfirm,
          text: context.strings.common.continueAction,
          onPressed: switch (_mine) {
            final mine? => () => Navigator.of(context).pop(
                  PersonalScopeAnswer(personal: mine, showAndroid: _android),
                ),
            null => null,
          },
        ),
      ],
    );
  }
}

/// "רק המחשב שלי" כשבכונן ספרייה מלאה: היא תימחק בהורדה הבאה. אזהרה — הביטול
/// הוא הבחירה הבטוחה. אותו דו-שיח בשאלה של ההפעלה הראשונה ובהגדרות.
Future<bool> confirmPersonalModeDialog(BuildContext context) {
  final t = context.strings.settings;
  return showWarningDialog(
    context: context,
    title: t.personalModeDialogTitle,
    content: t.personalModeDialogContent,
    confirmText: t.personalModeDialogConfirm,
  );
}
