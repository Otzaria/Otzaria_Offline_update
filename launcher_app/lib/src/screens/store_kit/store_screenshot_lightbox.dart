import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/widgets_exports.dart';
import 'store_visuals.dart' show decodeWidthFor;

/// גלריית צילומי המסך במסך מלא. ניווט בחצים, בלחיצה על הצדדים, וסגירה
/// ב-Esc או בלחיצה על הרקע — כמו ה-lightbox בחנות המקורית.
///
/// הכיווניות נגזרת מהשפה: ב-RTL ← מקדם ו-→ מחזיר, וב-LTR להפך.
Future<void> showStoreScreenshots(
  BuildContext context, {
  required List<String> paths,
  required int initialIndex,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .8),
    builder: (context) => _Lightbox(paths: paths, initialIndex: initialIndex),
  );
}

class _Lightbox extends StatefulWidget {
  const _Lightbox({required this.paths, required this.initialIndex});

  final List<String> paths;
  final int initialIndex;

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late int _index = widget.initialIndex;

  void _step(int delta) {
    setState(() {
      _index = (_index + delta) % widget.paths.length;
      if (_index < 0) _index += widget.paths.length;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // הכיוון "קדימה" הוא לכיוון שאליו זורם הטקסט: שמאלה ב-RTL, ימינה ב-LTR.
    final forward = context.isRtl ? -1 : 1;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _step(-forward);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _step(forward);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMany = widget.paths.length > 1;
    final t = context.strings.plugins;
    final cs = Theme.of(context).colorScheme;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // לחיצה על הרקע סוגרת; לחיצה על התמונה עצמה לא.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  88,
                  AppTokens.titleBarHeight + 56,
                  88,
                  56,
                ),
                child: ClipRRect(
                  borderRadius: AppTokens.borderRadiusAll,
                  child: Image(
                    image: screenBoundImage(context, widget.paths[_index]),
                    fit: BoxFit.contain,
                    errorBuilder: (context, _, __) => Icon(
                      FluentIcons.image_off_24_regular,
                      size: 64,
                      color: cs.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ),
            if (hasMany) ...[
              // "הקודם" בצד שממנו באים — ימין בעברית, כמו החץ → במקלדת.
              _NavButton(
                alignment: AlignmentDirectional.centerStart,
                icon: FluentIcons.chevron_left_24_regular,
                tooltip: t.screenshotPrevious,
                onPressed: () => _step(-1),
              ),
              _NavButton(
                alignment: AlignmentDirectional.centerEnd,
                icon: FluentIcons.chevron_right_24_regular,
                tooltip: t.screenshotNext,
                onPressed: () => _step(1),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t.screenshotNumber(_index + 1, widget.paths.length),
                    style: AppTextStyles.small.copyWith(
                      color: cs.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ],
            // שורת הכותרת מצוירת מעל הדו-שיח, ולכן הכפתור יורד מתחתיה.
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  AppTokens.titleBarHeight + 16,
                  16,
                  16,
                ),
                child: _NavButton.plain(
                  icon: FluentIcons.dismiss_24_regular,
                  tooltip: context.strings.common.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// כפתור סמל על הרקע הכהה: inverseSurface ב-70%.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required AlignmentDirectional this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  const _NavButton.plain({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : alignment = null;

  final AlignmentDirectional? alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final button = Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.inverseSurface.withValues(alpha: .7),
          foregroundColor: cs.onInverseSurface,
          fixedSize: const Size(40, 40),
          minimumSize: const Size(40, 40),
          shape: AppTokens.roundedShape,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
    final at = alignment;
    if (at == null) return button;
    return Align(
      alignment: at,
      child: Padding(padding: const EdgeInsets.all(16), child: button),
    );
  }
}

ImageProvider screenBoundImage(BuildContext context, String path) {
  final file = FileImage(File(path));
  final screen = MediaQuery.sizeOf(context);
  final width = decodeWidthFor(context, screen.width);
  final height = decodeWidthFor(context, screen.height);
  if (width == null || height == null) return file;
  return ResizeImage(
    file,
    width: width,
    height: height,
    policy: ResizeImagePolicy.fit,
  );
}
