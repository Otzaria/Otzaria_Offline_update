import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import 'action_buttons.dart';

/// כפתור "בדיקה מחדש" משותף למסכים. הבדיקה מקומית ונגמרת לרוב בתוך פריים,
/// ולכן הסמל מסתובב לפחות [_minSpin] — בלי זה הלחיצה נראית כאילו לא קרה כלום.
class RecheckButton extends StatefulWidget {
  const RecheckButton({super.key, required this.onPressed});

  /// `null` = מושבת, כשפעולה כבדה יותר (התקנה/עדכון) כבר רצה.
  final Future<void> Function()? onPressed;

  @override
  State<RecheckButton> createState() => _RecheckButtonState();
}

class _RecheckButtonState extends State<RecheckButton> {
  static const _minSpin = Duration(milliseconds: 900);

  bool _spinning = false;

  Future<void> _run() async {
    final action = widget.onPressed;
    if (_spinning || action == null) return;

    setState(() => _spinning = true);
    // מתחיל לרוץ יחד עם הפעולה, ונאסף בסוף — כך גם כישלון מהיר מסתובב.
    final minimum = Future<void>.delayed(_minSpin);
    try {
      await action();
    } finally {
      await minimum;
      if (mounted) setState(() => _spinning = false);
    }
  }

  @override
  Widget build(BuildContext context) => ActionButton.neutral(
        text: context.strings.common.recheck,
        icon: FluentIcons.arrow_sync_24_regular,
        spinning: _spinning,
        onPressed: widget.onPressed == null ? null : _run,
      );
}
