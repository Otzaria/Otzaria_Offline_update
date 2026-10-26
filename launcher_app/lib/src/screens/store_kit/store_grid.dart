import 'dart:math' as math;

// SliverConstraints ו-SliverGridLayout מגיעים מ-rendering, לא מ-material.
import 'package:flutter/rendering.dart';

/// מרוחב התוכן הזה הרשת בשתי עמודות, והכרטיס עובר מ"שורה" ל"כרטיס" —
/// כמו `@container body (min-width: 820px)` במוקאפ, פחות ריפוד הדף.
const double kStoreTwoColumnWidth = 772;

/// מחוץ לרשת (בלי גובה קבוע): מהרוחב הזה הכרטיס מוצג כשורה.
const double kStoreRowCardWidth = 480;

/// גובה הכרטיס קבוע (התיאור תמיד בשתי שורות שמורות), כדי שהרשת לא
/// תצטרך למדוד אף כרטיס.
double storeRowCardExtent(double textScale) => 32 + 100 * textScale;

/// באריח, בהגדלה גדולה הסמל והכפתור כבר אינם הגבוהים: שם בשתי שורות, מטא,
/// תיאור והערה בשתי שורות — כולם טקסט, ולכן הגובה גדל מהר יותר מ-1.4 ומעלה.
double storeTileCardExtent(double textScale) =>
    math.max(112 + 104 * textScale, 52 + 146 * textScale);

/// החישוב ב-delegate ולא ב-`SliverLayoutBuilder`: שם הרשת הייתה נבנית
/// מחדש בכל פריים של גלילה.
class StoreGridDelegate extends SliverGridDelegate {
  const StoreGridDelegate({required this.textScale});

  /// הגדלת הטקסט של המשתמש; תוכן הכרטיס גדל איתה, ולכן גם הגובה.
  final double textScale;

  static bool twoColumns(double width) => width >= kStoreTwoColumnWidth;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final two = twoColumns(constraints.crossAxisExtent);
    final spacing = two ? 12.0 : 10.0;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: two ? 2 : 1,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      mainAxisExtent:
          two ? storeTileCardExtent(textScale) : storeRowCardExtent(textScale),
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(StoreGridDelegate oldDelegate) =>
      oldDelegate.textScale != textScale;
}
