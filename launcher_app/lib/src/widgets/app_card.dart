import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'focus_ring.dart';

/// כרטיס שטוח (`.card`). [AppCard.section] — שורות עם רצועה בצבע הדף
/// ביניהן (`.rows`).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin,
    this.padding,
    this.selected = false,
  }) : children = null;

  const AppCard.section({
    super.key,
    required this.children,
    this.margin,
    this.padding,
    this.selected = false,
  })  : child = null,
        onTap = null;

  /// הרצועה בין שורות במקטע כרטיס.
  static const double sectionSpacing = 2;

  final Widget? child;
  final List<Widget>? children;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    Widget card =
        children != null ? _buildSection(context) : _buildSingle(context);
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
  }

  Color _color(BuildContext context) =>
      selected ? AppSurfaces.cardSelected(context) : AppSurfaces.card(context);

  Widget _buildSingle(BuildContext context) {
    Widget content = child!;
    if (padding != null) content = Padding(padding: padding!, child: content);

    final card = Material(
      color: _color(context),
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              overlayColor: AppSurfaces.stateLayer(
                Theme.of(context).colorScheme.primary,
              ),
              child: content,
            ),
    );
    return onTap == null ? card : FocusRing(child: card);
  }

  Widget _buildSection(BuildContext context) {
    final cardColor = _color(context);

    // Material לכל שורה כדי ש-ink/hover של ListTile ייצבעו נכון. הרצועה ביניהן
    // בצבע הדף גם בתוך דו-שיח.
    final last = children!.length - 1;
    Widget wrapChild(int i) {
      var w = children![i];
      if (padding != null) w = Padding(padding: padding!, child: w);
      if (i == 0 || i == last) {
        w = Padding(
          padding: EdgeInsets.only(
            top: i == 0 ? 4 : 0,
            bottom: i == last ? 4 : 0,
          ),
          child: w,
        );
      }
      return Material(color: cardColor, child: w);
    }

    return ClipRRect(
      borderRadius: AppTokens.borderRadiusAll,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children!.length; i++) ...[
            wrapChild(i),
            if (i < last)
              ColoredBox(
                color: AppSurfaces.cardRowDivider(context),
                child: const SizedBox(
                  height: sectionSpacing,
                  width: double.infinity,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
