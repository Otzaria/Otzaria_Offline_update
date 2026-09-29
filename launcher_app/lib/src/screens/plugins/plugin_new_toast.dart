import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';

/// הטוסט "תוסף חדש בחנות!" — כמו בחנות הרשמית: פס בצבע הראשי בתחתית
/// המסך, אייקון, טקסט, "צפה" ו-✕.
///
/// המספר [count] הוא מה שעוד ממתין בתור; הרכיב אינו מחזיק תור בעצמו.
class PluginNewToast extends StatelessWidget {
  const PluginNewToast({
    super.key,
    required this.count,
    required this.onView,
    required this.onClose,
  });

  final int count;
  final VoidCallback onView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.strings.plugins;

    return Positioned(
      left: 0,
      right: 0,
      bottom: AppTokens.spaceLG,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 24),
              child: child,
            ),
          ),
          child: Material(
            color: cs.primary,
            elevation: 8,
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppTokens.spaceMD,
                end: AppTokens.spaceSM,
                top: AppTokens.spaceSM,
                bottom: AppTokens.spaceSM,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.wand_24_regular,
                    size: 22,
                    color: cs.onPrimary,
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Text(
                    count == 1 ? t.newToastOne : t.newToastMany(count),
                    style: TextStyle(
                      fontSize: AppTokens.fontMD,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimary,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMD),
                  ActionButton.neutral(text: t.newToastView, onPressed: onView),
                  IconButton(
                    tooltip: t.newToastClose,
                    icon: Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 18,
                      color: cs.onPrimary,
                    ),
                    onPressed: onClose,
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
