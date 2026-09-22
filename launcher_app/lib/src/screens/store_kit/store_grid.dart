import 'dart:math' as math;

// SliverConstraints ו-SliverGridLayout מגיעים מ-rendering, לא מ-material.
import 'package:flutter/rendering.dart';

import '../../theme/theme_exports.dart';

/// פריסת רשת הכרטיסים של מסך חנות — מספר העמודות וגובה האריח נגזרים
/// מרוחב הרשת.
///
/// ⚠️ החישוב יושב ב-delegate ולא ב-`SliverLayoutBuilder`, כי ה-scrollOffset
/// הוא חלק מ-`SliverConstraints`: שם הרשת נבנתה מחדש בכל פריים של גלילה —
/// עם כל הכרטיסים הגלויים — ומכאן הגלילה התקועה.
class StoreGridDelegate extends SliverGridDelegate {
  const StoreGridDelegate({
    required this.textScale,
    required this.minCardWidth,
    required this.contentHeight,
    this.imageAspectRatio = 16 / 11,
    this.imagePadding = AppTokens.spaceMD * 2,
    this.imageMaxWidth,
  });

  /// הגדלת הטקסט של המשתמש; תוכן הכרטיס גדל איתה, ולכן גם גובה האריח.
  final double textScale;

  /// הרוחב המינימלי של כרטיס; ממנו נגזר מספר העמודות, כמו auto-fill ב-CSS.
  final double minCardWidth;

  /// גובה כל מה שאינו התמונה בכרטיס. **מוכפל ב-[textScale]**.
  final double contentHeight;

  /// יחס התמונה שבראש הכרטיס, או `null` לכרטיס בלי תמונה.
  final double? imageAspectRatio;

  /// הריפוד האופקי סביב התמונה בתוך הכרטיס.
  final double imagePadding;

  /// חסם על רוחב התמונה, לכרטיס שהתמונה בו אינה נמתחת לכל רוחבו.
  ///
  /// ⚠️ מי שמציב אותו חייב להצר את התמונה גם בכרטיס עצמו, באותו מספר —
  /// כאן נקבע רק הגובה שהאריח מקבל, ושתי הצורות חייבות להסכים.
  final double? imageMaxWidth;

  static const double _spacing = AppTokens.spaceLG;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final columns =
        ((width + _spacing) / (minCardWidth + _spacing)).floor().clamp(1, 6);

    // גובה הכרטיס נגזר ולא קבוע: התמונה תופסת יחס קבוע מרוחב הכרטיס,
    // ולכן כרטיס רחב הוא גם גבוה יותר. שאר התוכן מקבל גובה קבוע שמוכפל
    // בהגדלת הטקסט של המשתמש — אחרת טקסט מוגדל היה גולש.
    final tileWidth = (width - _spacing * (columns - 1)) / columns;
    final aspect = imageAspectRatio;
    final imageWidth =
        math.min(tileWidth - imagePadding, imageMaxWidth ?? double.infinity);
    final imageHeight = aspect == null ? 0.0 : imageWidth / aspect;

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: _spacing,
      mainAxisSpacing: _spacing,
      mainAxisExtent: imageHeight + contentHeight * textScale,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(StoreGridDelegate oldDelegate) =>
      oldDelegate.textScale != textScale ||
      oldDelegate.minCardWidth != minCardWidth ||
      oldDelegate.contentHeight != contentHeight ||
      oldDelegate.imageAspectRatio != imageAspectRatio ||
      oldDelegate.imageMaxWidth != imageMaxWidth;
}
