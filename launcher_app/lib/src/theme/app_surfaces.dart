import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'focus_visibility.dart';

ColorScheme _cs(BuildContext context) => Theme.of(context).colorScheme;

/// רקעי מסך ושכבות מצב. זו נקודת ה-override היחידה לשקיפויות ולגוני רקע;
/// אין להגדיר `.withValues(alpha:)` מחוץ ל-`theme/`.
class AppSurfaces {
  AppSurfaces._();

  /// ריחוף ולחיצה: 8% ו-12% מצבע הבסיס, מעל המשטח שמתחתיו.
  static const double hoverAlpha = 0.08;
  static const double pressedAlpha = 0.12;

  /// רקע החלון וכל הדפים.
  static Color panelBackground(BuildContext context) =>
      AppPalette.of(context).page;

  /// רקע שורת הכותרת.
  static Color topBarBackground(BuildContext context) =>
      _cs(context).surfaceContainerHigh;

  /// הקו שמתחת לשורת הכותרת.
  static Color shellDivider(BuildContext context) =>
      AppPalette.of(context).titleBarBorder;

  /// כרטיס תוכן: שטוח, בלי מסגרת ובלי צל.
  static Color card(BuildContext context) => _cs(context).surface;

  /// הרצועה בין שורות בכרטיס — רקע הדף עצמו.
  static Color cardRowDivider(BuildContext context) => panelBackground(context);

  /// כרטיס נבחר.
  static Color cardSelected(BuildContext context) =>
      AppPalette.of(context).cardSelected;

  /// רקע קטע-משנה ניטרלי בתוך כרטיס.
  static Color panelSection(BuildContext context) =>
      _cs(context).surfaceContainer;

  /// שכבת המצב (hover/pressed) בצבע [base] — ל-`overlayColor` של כפתור או
  /// `InkWell`. מיקוד לבדו אינו צובע: הוא טבעת ([focusRingSide], `FocusRing`).
  static WidgetStateProperty<Color?> stateLayer(Color base) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return null;
        if (states.contains(WidgetState.pressed)) {
          return base.withValues(alpha: pressedAlpha);
        }
        if (states.contains(WidgetState.hovered)) {
          return base.withValues(alpha: hoverAlpha);
        }
        // שקוף ולא null: null נופל לברירת המחדל של הכפתור, שצובעת מיקוד.
        if (states.contains(WidgetState.focused)) return Colors.transparent;
        return null;
      });

  /// כמו [stateLayer], לפקד שאין לו מקום לטבעת: מיקוד מהמקלדת מקבל את שכבת
  /// הלחיצה.
  static WidgetStateProperty<Color?> stateLayerWithFocus(Color base) =>
      WidgetStateProperty.resolveWith((states) {
        // נקרא לפני הבדיקה כדי שההאזנה תתחיל בבנייה הראשונה, לפני כל מקש.
        final keyboard = FocusVisibility.isKeyboard;
        if (!states.contains(WidgetState.disabled) &&
            states.contains(WidgetState.focused) &&
            keyboard) {
          return base.withValues(alpha: pressedAlpha);
        }
        return stateLayer(base).resolve(states);
      });

  /// טבעת המיקוד ל-`side` של כפתור: 2px ב-[ring], במרחק 2 מחוץ לצורה, רק
  /// כשהמיקוד הגיע מהמקלדת. אחרת — [base].
  static WidgetStateProperty<BorderSide?> focusRingSide(
    Color ring, [
    WidgetStateProperty<BorderSide?>? base,
  ]) =>
      WidgetStateProperty.resolveWith((states) {
        final keyboard = FocusVisibility.isKeyboard;
        if (states.contains(WidgetState.focused) && keyboard) {
          return BorderSide(color: ring, width: 2, strokeAlign: 3);
        }
        return base?.resolve(states);
      });

  /// [base] בריחוף מעל [surface] — כצבע אטום, למשטח שמצייר את עצמו.
  static Color hovered(Color surface, Color base) =>
      Color.alphaBlend(base.withValues(alpha: hoverAlpha), surface);

  /// [base] בלחיצה מעל [surface].
  static Color pressed(Color surface, Color base) =>
      Color.alphaBlend(base.withValues(alpha: pressedAlpha), surface);

  /// רקע ההודעה בבית: secondaryContainer ב-45% מעל רקע הדף.
  static Color banner(BuildContext context) => Color.alphaBlend(
        _cs(context).secondaryContainer.withValues(alpha: 0.45),
        panelBackground(context),
      );

  /// הודעת אזהרה: errorContainer ב-45% מעל הכרטיס.
  static Color warningNotice(BuildContext context) => Color.alphaBlend(
        _cs(context).errorContainer.withValues(alpha: 0.45),
        card(context),
      );

  /// "אל תנתקו את הכונן": secondaryContainer ב-50% מעל רקע הדף.
  static Color keepNotice(BuildContext context) => Color.alphaBlend(
        _cs(context).secondaryContainer.withValues(alpha: 0.5),
        panelBackground(context),
      );

  /// הטבעת שמסביב לתג תוצאה — צבע התג ב-11%.
  static Color badgeRing(Color base) => base.withValues(alpha: 0.11);

  /// הטבעת שמסביב לסמל הגיבור — secondaryContainer ב-45%.
  static Color emblemRing(Color base) => base.withValues(alpha: 0.45);

  /// [base] שקוף לגמרי — קצה של מעבר צבע.
  static Color transparent(Color base) => base.withValues(alpha: 0);

  /// טבעת התג הרגוע: onSurfaceVariant ב-9%.
  static Color calmBadgeRing(ColorScheme cs) =>
      cs.onSurfaceVariant.withValues(alpha: 0.09);

  /// מסגרת סמל התוסף: outlineVariant ב-70%.
  static Color iconFrame(ColorScheme cs) =>
      cs.outlineVariant.withValues(alpha: 0.7);

  /// טקסט של פקד מושבת.
  static Color disabledForeground(BuildContext context) =>
      AppPalette.of(context).disabledText;

  /// רקע של פקד מושבת.
  static Color disabledBackground(BuildContext context) =>
      AppPalette.of(context).disabledContainer;
}
