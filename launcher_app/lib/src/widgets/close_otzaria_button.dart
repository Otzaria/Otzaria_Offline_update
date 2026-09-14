import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../l10n/app_strings_scope.dart';
import 'action_buttons.dart';
import 'ui_snack.dart';

/// הכפתור שלצד האזהרה "אוצריא פתוחה", בשלושת המסכים שמציגים אותה.
///
/// מחזיק בעצמו את מצב ההמתנה ואת הודעת הכישלון: האזהרה מוצגת גם במסכים
/// שאינם מכירים את קונטרולר האפליקציה, וכך כולם מקבלים אותו כפתור בדיוק.
class CloseOtzariaButton extends StatefulWidget {
  const CloseOtzariaButton({super.key, required this.onClose});

  /// מבקשת מאוצריא להיסגר ומחזירה אם היא אכן נסגרה.
  final Future<bool> Function() onClose;

  @override
  State<CloseOtzariaButton> createState() => _CloseOtzariaButtonState();
}

class _CloseOtzariaButtonState extends State<CloseOtzariaButton> {
  bool _isClosing = false;

  Future<void> _close() async {
    setState(() => _isClosing = true);
    try {
      final closed = await widget.onClose();
      // אוצריא שנסגרה מסירה את האזהרה כולה — זו כל ההודעה שצריך. רק כשלון
      // שקט הוא שמבלבל, כי הכפתור פשוט חוזר לעצמו.
      if (closed) return;
      UiSnack.showError(AppL10n.strings.common.closeOtzariaFailedSnack);
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ActionButton.neutral(
        text: context.strings.common.closeOtzariaButton,
        icon: FluentIcons.dismiss_circle_24_regular,
        spinning: _isClosing,
        onPressed: _isClosing ? null : _close,
      );
}
