import 'package:flutter/material.dart';

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

  /// רקע שורת הכותרת המותאמת — אותו רקע כמו הלוח, כך שהיא נקראת כהמשך של
  /// המסך ולא כסרגל נפרד (כמו באוצריא).
  static Color topBarBackground(BuildContext context) =>
      panelBackground(context);

  /// רקע סרגל הניווט הצדי — גם הוא רקע הלוח, בלי תפר מול התוכן.
  static Color navRailBackground(BuildContext context) =>
      panelBackground(context);

  /// קו ההפרדה של המסגרת — מתחת לשורת הכותרת ובין סרגל הניווט לתוכן.
  /// שלושת המשטחים באותו צבע, ולכן הקו הזה הוא כל מה שמפריד ביניהם (כמו
  /// ה-`VerticalDivider` וגבול ה-`CustomTitleBar` באוצריא).
  static Color shellDivider(BuildContext context) =>
      _cs(context).outlineVariant.withValues(alpha: 0.6);

  /// צבע ברירת המחדל לכרטיסי תוכן
  static Color card(BuildContext context) => _cs(context).isDark
      ? _cs(context).surfaceContainer
      : _cs(context).surface;

  /// צל רך לכרטיסי תוכן — עומק עדין שמפריד את הכרטיס מרקע הלוח. במצב כהה
  /// הרקע שחור ממילא, וצל עליו רק מלכלך את הפינות; שם אין צל.
  static List<BoxShadow> cardShadow(BuildContext context) => _cs(context).isDark
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ];

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
