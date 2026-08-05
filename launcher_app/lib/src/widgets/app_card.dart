import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

/// כרטיס תוכן מרכזי עם צבע ופינות מעוגלות אחידים — פורט מאוצריא.
///
/// - [AppCard] — כרטיס עם ילד יחיד; תומך ב-[onTap] וב-[selected].
/// - [AppCard.section] — מקטע עם מספר שורות; רווח 1.5px ביניהן.
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

  /// הרווח הקבוע בין שורות במקטע כרטיס.
  static const double sectionSpacing = 1.5;

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

  Widget _buildSingle(BuildContext context) {
    Widget content = child!;
    if (padding != null) content = Padding(padding: padding!, child: content);
    if (selected) content = _withSelected(context, content);

    if (onTap != null) {
      return Material(
        color: AppSurfaces.card(context),
        surfaceTintColor: Colors.transparent,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          hoverDuration: Durations.medium1,
          child: content,
        ),
      );
    }

    return Material(
      color: AppSurfaces.card(context),
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _buildSection(BuildContext context) {
    final cardColor = AppSurfaces.card(context);

    // Material לכל שורה כדי ש-ink/hover של ListTile ייצבעו נכון, והרווח
    // השקוף ביניהן חושף את רקע המסך מאחורי הכרטיס.
    Widget wrapChild(Widget w) {
      if (padding != null) w = Padding(padding: padding!, child: w);
      return Material(color: cardColor, child: w);
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children!.length; i++) ...[
          wrapChild(children![i]),
          if (i < children!.length - 1) const SizedBox(height: sectionSpacing),
        ],
      ],
    );

    if (selected) content = _withSelected(context, content);

    return ClipRRect(
      borderRadius: AppTokens.borderRadiusAll,
      child: content,
    );
  }

  Widget _withSelected(BuildContext context, Widget w) => ColoredBox(
        color: AppSurfaces.cardSelectionOverlay(context),
        child: w,
      );
}
