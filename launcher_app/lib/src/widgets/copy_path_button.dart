import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../l10n/app_strings_scope.dart';
import 'action_buttons.dart';
import 'ui_snack.dart';

/// "העתקת הנתיב" ליד `PathText`, שמקצר נתיב ארוך לשורה אחת.
class CopyPathButton extends StatelessWidget {
  const CopyPathButton({
    super.key,
    required this.path,
    this.enabled = true,
    this.size = ActionButtonSize.md,
  });

  final String path;
  final bool enabled;
  final ActionButtonSize size;

  @override
  Widget build(BuildContext context) => ActionButton.ghost(
        text: context.strings.common.copyPathButton,
        icon: FluentIcons.copy_24_regular,
        size: size,
        onPressed: enabled ? () => copyPath(path) : null,
      );
}

Future<void> copyPath(String path) async {
  await Clipboard.setData(ClipboardData(text: path));
  UiSnack.showSuccess(AppL10n.strings.common.pathCopiedSnack);
}
