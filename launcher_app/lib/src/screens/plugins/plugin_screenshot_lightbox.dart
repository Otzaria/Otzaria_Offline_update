import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/theme_exports.dart';

/// גלריית צילומי המסך במסך מלא. ניווט בחצים, בלחיצה על הצדדים, וסגירה
/// ב-Esc או בלחיצה על הרקע — כמו ה-lightbox בחנות המקורית.
///
/// ב-RTL החץ "הבא" נמצא בצד שמאל, ולכן ← מקדם ו-→ מחזיר.
Future<void> showPluginScreenshots(
  BuildContext context, {
  required List<String> paths,
  required int initialIndex,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
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
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _step(-1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMany = widget.paths.length > 1;

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
                padding: const EdgeInsets.all(AppTokens.spaceXL),
                child: Image.file(
                  File(widget.paths[_index]),
                  fit: BoxFit.contain,
                  errorBuilder: (context, _, __) => const Icon(
                    FluentIcons.image_off_24_regular,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (hasMany) ...[
              _NavButton(
                alignment: AlignmentDirectional.centerEnd,
                icon: FluentIcons.chevron_right_24_regular,
                tooltip: 'הקודם',
                onPressed: () => _step(-1),
              ),
              _NavButton(
                alignment: AlignmentDirectional.centerStart,
                icon: FluentIcons.chevron_left_24_regular,
                tooltip: 'הבא',
                onPressed: () => _step(1),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceLG),
                  child: Text(
                    '${_index + 1} / ${widget.paths.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
            Align(
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceMD),
                child: IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  color: Colors.white,
                  tooltip: 'סגירה',
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

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final AlignmentDirectional alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: IconButton.filledTonal(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
