import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// טבעת המיקוד של המוקאפ (`outline: 2px primary; outline-offset: 2px`) סביב
/// פקד שאינו `ButtonStyleButton` — רק כשהמיקוד הגיע מהמקלדת.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.borderRadius = AppTokens.borderRadiusAll,
    this.offset = 2,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// המרחק מהקצה. שלילי — בתוך הפקד, למשל בשורה שהכרטיס שלה חותך.
  final double offset;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  // רק כשהפקד העוטף עצמו ממוקד: פקד פנימי (מתג בשורה) מצייר טבעת משלו.
  // מאזינים למנהל המיקוד כי מעבר בין צאצאים אינו משנה את hasFocus כאן.
  final FocusNode _node = FocusNode(
    debugLabel: 'FocusRing',
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    FocusVisibility.ensureInstalled();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    final visible = FocusManager.instance.primaryFocus?.parent == _node &&
        FocusVisibility.isKeyboard;
    if (visible != _visible) setState(() => _visible = visible);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      child: CustomPaint(
        foregroundPainter: _visible
            ? _RingPainter(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: widget.borderRadius,
                offset: widget.offset,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.color,
    required this.borderRadius,
    required this.offset,
  });

  static const double width = 2;

  final Color color;
  final BorderRadius borderRadius;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final inflate = offset + width / 2;
    Radius grow(Radius r) => Radius.circular(
          (r.x + inflate).clamp(0, double.infinity).toDouble(),
        );
    final r = borderRadius.resolve(TextDirection.ltr);
    final rect = RRect.fromRectAndCorners(
      (Offset.zero & size).inflate(inflate),
      topLeft: grow(r.topLeft),
      topRight: grow(r.topRight),
      bottomLeft: grow(r.bottomLeft),
      bottomRight: grow(r.bottomRight),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color ||
      old.borderRadius != borderRadius ||
      old.offset != offset;
}
