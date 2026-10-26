import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'focus_ring.dart';

/// קישור בתוך טקסט (`.link`): primary ו-600, קו תחתון בריחוף, בלי רקע.
class TextLink extends StatefulWidget {
  const TextLink({
    super.key,
    required this.text,
    required this.onTap,
    this.style,
  });

  final String text;
  final VoidCallback? onTap;

  /// הגודל של הטקסט שסביבו; הצבע והמשקל נקבעים כאן.
  final TextStyle? style;

  @override
  State<TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<TextLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(4));
    final enabled = widget.onTap != null;
    // Material שקוף: הקישור יושב גם בתוך טקסט שאין מעליו משטח Material.
    return FocusRing(
      borderRadius: radius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) => setState(() => _hovered = hovered),
          borderRadius: radius,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Text(
            widget.text,
            style: (widget.style ?? AppTextStyles.small).copyWith(
              color: enabled
                  ? cs.primary
                  : AppSurfaces.disabledForeground(context),
              fontWeight: AppTextStyles.semibold,
              decoration: _hovered && enabled ? TextDecoration.underline : null,
              decorationColor: cs.primary,
            ),
          ),
        ),
      ),
    );
  }
}
