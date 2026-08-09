import 'package:flutter/material.dart';

import 'app_colors.dart';

ColorScheme _cs(BuildContext context) => Theme.of(context).colorScheme;

extension on ColorScheme {
  bool get isDark => brightness == Brightness.dark;
}

/// רקעי מסך — מועתק מאוצריא. זו נקודת ה-override היחידה לשקיפויות ולגוני
/// רקע; אין להגדיר `.withValues(alpha:)` מחוץ ל-`theme/`.
class AppSurfaces {
  AppSurfaces._();

  /// רקע מסכי לוח — כל מסכי הלאנצ'ר
  static Color panelBackground(BuildContext context) {
    final cs = _cs(context);
    return cs.isDark
        ? Colors.black
        : Color.alphaBlend(
            cs.surfaceContainerHighest.withValues(alpha: 0.475),
            cs.surface,
          );
  }

  /// רקע סרגל עליון
  static Color topBarBackground(BuildContext context) =>
      _cs(context).surfaceContainerHigh;

  /// רקע סרגל הניווט הצדי
  static Color navRailBackground(BuildContext context) =>
      _cs(context).isDark ? AppColors.darkScaffold : _cs(context).surface;

  /// צבע ברירת המחדל לכרטיסי תוכן
  static Color card(BuildContext context) => _cs(context).isDark
      ? _cs(context).surfaceContainer
      : _cs(context).surface;

  /// צבע מפריד פנימי בין שורות בתוך כרטיס תוכן
  static Color cardRowDivider(BuildContext context) => panelBackground(context);

  /// שכבת בחירה לכרטיסי תוכן
  static Color cardSelectionOverlay(BuildContext context) =>
      _cs(context).secondaryContainer.withValues(alpha: 0.3);

  /// רקע קטע-משנה ניטרלי בתוך כרטיס
  static Color panelSection(BuildContext context) =>
      _cs(context).surfaceContainerHighest.withValues(alpha: 0.5);

  /// רקע שבב חיווי מצב — נגזר מצבע החיווי עצמו, בשקיפות אחידה
  static Color statusChip(Color base) => base.withValues(alpha: 0.12);
}
