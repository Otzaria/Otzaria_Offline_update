import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings_scope.dart';
import '../theme/theme_exports.dart';
import 'action_buttons.dart';
import 'copy_path_button.dart';

/// נתיב (`.path`): Consolas 12 על surfaceContainer, LTR, שורה אחת ומקוצר;
/// הנתיב המלא ב-Tooltip. [copyable] — עם "העתקת הנתיב" לצידו.
class PathText extends StatelessWidget {
  const PathText(this.path, {super.key, this.copyable = false});

  final String path;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Tooltip(
      // הריחוף יורש RTL, ובלי בידוד הנתיב מתהפך.
      message: '\u2066$path\u2069',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontFamilyFallback: const ['Cascadia Mono', 'monospace'],
            fontSize: AppTokens.fontSM,
            color: cs.onSurface,
          ),
        ),
      ),
    );
    if (!copyable) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        const SizedBox(width: AppTokens.spaceXS),
        AppIconButton(
          icon: FluentIcons.copy_24_regular,
          tooltip: context.strings.common.copyPathButton,
          small: true,
          onPressed: () => copyPath(path),
        ),
      ],
    );
  }
}
