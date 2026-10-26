import 'package:flutter/material.dart';

/// פס התקדמות (`.bar`): גלולה בגובה 8 (או 4 ב-[thin]), מסילה tonal ומילוי
/// primary של לפחות 8. בלי [value] — מקטע של 30% שנע בכיוון הקריאה.
class AppProgressBar extends StatefulWidget {
  const AppProgressBar({
    super.key,
    this.value,
    this.thin = false,
    this.color,
    this.semanticsLabel,
  });

  /// 0..1, או `null` לפס בלי ערך.
  final double? value;
  final bool thin;

  /// צבע המילוי — למשל הדירוג בחנות.
  final Color? color;
  final String? semanticsLabel;

  @override
  State<AppProgressBar> createState() => _AppProgressBarState();
}

class _AppProgressBarState extends State<AppProgressBar>
    with SingleTickerProviderStateMixin {
  AnimationController? _sweep;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AppProgressBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      _sweep ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat();
    } else {
      _sweep?.dispose();
      _sweep = null;
    }
  }

  @override
  void dispose() {
    _sweep?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = widget.thin ? 4.0 : 8.0;
    final fill = widget.color ?? cs.primary;
    final radius = BorderRadius.circular(height / 2);
    final value = widget.value;

    return Semantics(
      label: widget.semanticsLabel,
      value: value == null ? null : '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: cs.secondaryContainer,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (value != null) {
                  final w = (width * value.clamp(0.0, 1.0))
                      .clamp(height, width)
                      .toDouble();
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      width: w,
                      decoration:
                          BoxDecoration(color: fill, borderRadius: radius),
                    ),
                  );
                }
                return AnimatedBuilder(
                  animation: _sweep!,
                  builder: (context, _) {
                    final segment = width * 0.3;
                    final travel = (width + segment) * _sweep!.value;
                    return Stack(
                      children: [
                        PositionedDirectional(
                          start: travel - segment,
                          top: 0,
                          bottom: 0,
                          width: segment,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: radius,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
