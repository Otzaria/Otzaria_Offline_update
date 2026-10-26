import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/theme_exports.dart';
import '../../widgets/sub_page_header.dart';

/// גוף החנות: התוכן slivers בלבד, בלי גליל מקונן — כך `SliverGrid` בונה
/// רק את הכרטיסים שליד החלון ולא מפענח את כל התמונות מיד.
class StoreBody extends StatelessWidget {
  const StoreBody({super.key, required this.slivers, this.maxWidth});

  final List<Widget> slivers;

  /// `null` — רוחב החנות (960); דף ניהול צר משתמש ב-720.
  final double? maxWidth;

  /// עוטף widget רגיל כ-sliver עם מרווח אנכי — לכותרות ולכרטיסי מצב.
  static Widget block(Widget child, {double top = 0, double bottom = 0}) =>
      SliverPadding(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        sliver: SliverToBoxAdapter(child: child),
      );

  @override
  Widget build(BuildContext context) {
    const page = LayoutConstraints.pagePadding;
    final contentMax = maxWidth ?? LayoutConstraints.wideContentMaxWidth;
    final header = SubPageHeaderScope.maybeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
          page.left,
          (constraints.maxWidth - contentMax) / 2,
        );
        // שכבת Material שקופה: שדה החיפוש והכרטיסים צריכים אותה לדיו,
        // גם כשהדף אינו יושב בתוך Scaffold.
        return Material(
          type: MaterialType.transparency,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, page.top, side, page.bottom),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    if (header != null) SliverToBoxAdapter(child: header),
                    ...slivers,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
