import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../l10n/app_strings_scope.dart';
import 'action_buttons.dart';
import 'ui_snack.dart';

/// כפתור "העתקת הנתיב" לשורת הגדרה שמחזיקה נתיב. הנתיב עצמו אינו מוצג:
/// הוא ארוך, נשבר בעברית, ומה שבאמת עושים איתו הוא להדביק אותו במקום אחר.
class CopyPathButton extends StatelessWidget {
  const CopyPathButton({super.key, required this.path, this.enabled = true});

  final String path;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ActionButton.ghost(
        text: context.strings.common.copyPathButton,
        icon: FluentIcons.copy_24_regular,
        onPressed: enabled ? _copy : null,
      );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: path));
    UiSnack.showSuccess(AppL10n.strings.common.pathCopiedSnack);
  }
}
