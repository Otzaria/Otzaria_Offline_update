// NavRailItem — כפתור ניווט אנכי בסגנון M3, פורט מאוצריא
// (`otzaria/lib/widgets/navigation/nav_rail_item.dart`).

import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'rtl_icon.dart';

class NavRailItem extends StatelessWidget {
  /// רוחב הפריט. ה-SizedBox העוטף את הסרגל חייב להשתמש באותו ערך, אחרת
  /// ייווצר overflow בין רוחב הסרגל לרוחב הפריטים.
  static const double width = 74;
  static const double compactWidth = 60;

  static const double _indicatorWidth = 56;
  static const double _compactIndicatorWidth = 44;

  final IconData icon;
  final IconData? iconFilled;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? tooltip;
  final bool compact;

  const NavRailItem({
    super.key,
    required this.icon,
    this.iconFilled,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor =
        isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    Widget iconWidget = AnimatedSwitcher(
      duration: AppTokens.animNormal,
      switchInCurve: Curves.easeInOutCubicEmphasized,
      switchOutCurve: Curves.easeInOutCubicEmphasized,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: RtlIcon(
        isSelected && iconFilled != null ? iconFilled! : icon,
        key: ValueKey<bool>(isSelected),
        size: 24,
        color: iconColor,
      ),
    );

    if (tooltip != null) {
      iconWidget = Tooltip(
        preferBelow: false,
        message: tooltip!,
        child: iconWidget,
      );
    }

    return SizedBox(
      width: compact ? compactWidth : width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Active Indicator ────────────────────────────────────────
            AnimatedScale(
              scale: isSelected ? 1.0 : 0.95,
              duration: AppTokens.animNormal,
              curve: Curves.easeInOutCubicEmphasized,
              child: AnimatedContainer(
                duration: AppTokens.animNormal,
                curve: Curves.easeInOutCubicEmphasized,
                decoration: BoxDecoration(
                  color:
                      isSelected ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: IconButton(
                  onPressed: onTap,
                  icon: iconWidget,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    minimumSize: Size(
                      compact ? _compactIndicatorWidth : _indicatorWidth,
                      25,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: AppTokens.animNormal,
              curve: Curves.easeInOutCubicEmphasized,
              style: TextStyle(
                fontSize: 11,
                color:
                    isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
