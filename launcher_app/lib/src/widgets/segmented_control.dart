import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'rtl_icon.dart';

/// אפשרות יחידה ב-[AppSegmentedControl] — פורט מאוצריא.
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final IconData? rtlIcon;
  final String? subtitle;

  /// `false` = מוצג אך אינו לחיץ. נתמך כרגע רק ב-[AppMultiSegmentedControl].
  final bool enabled;

  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.rtlIcon,
    this.subtitle,
    this.enabled = true,
  }) : assert(
          icon == null || rtlIcon == null,
          'העבר icon או rtlIcon — לא שניהם יחד',
        );
}

/// פקד סגמנטד לבחירה מרובה — כמה אפשרויות סימון בשורה אחת, במקום מתג
/// לכל אחת. [onToggled] מקבל את האפשרות שנלחצה בלבד, כך שכל אחת יכולה
/// לדרוש אישור משלה בלי שהשאר ישתנו.
class AppMultiSegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final Set<T> selected;
  final ValueChanged<T> onToggled;
  final bool expandToFillWidth;
  final double? height;

  const AppMultiSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggled,
    this.expandToFillWidth = false,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SegmentedButton<T>(
      multiSelectionEnabled: true,
      // בלי זה הפקד מסרב לרוקן את הבחירה האחרונה — וכאן "שום דבר" היא
      // בחירה לגיטימית, שרק מכבה את כפתור ההורדה.
      emptySelectionAllowed: true,
      segments: [
        for (final o in options)
          ButtonSegment<T>(
            value: o.value,
            enabled: o.enabled,
            label: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(o.label, style: AppTextStyles.settingTitle),
              ),
            ),
          ),
      ],
      selected: selected,
      expandedInsets: expandToFillWidth ? EdgeInsets.zero : null,
      // הפקד מחזיר את הקבוצה כולה; ההפרש מול הקיים הוא בדיוק מה שנלחץ.
      onSelectionChanged: (next) {
        final changed = selected.difference(next).followedBy(
              next.difference(selected),
            );
        for (final value in changed) {
          onToggled(value);
        }
      },
      showSelectedIcon: false,
      style: height != null
          ? AppSegmentedControl._fixedHeightStyle(cs, height!)
          : AppSegmentedControl._buttonStyle(cs)
              .copyWith(visualDensity: VisualDensity.compact),
    );
  }
}

/// פקד סגמנטד גנרי — החלופה היחידה לקבוצת RadioButton בין 2–4 אפשרויות.
class AppSegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;
  final bool expandToFillWidth;
  final double? height;

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.currentValue,
    required this.onChanged,
    this.expandToFillWidth = false,
    this.height,
  });

  List<ButtonSegment<T>> _segments() {
    final hasIcons = options.any((o) => o.icon != null || o.rtlIcon != null);
    return options
        .map(
          (o) => ButtonSegment<T>(
            value: o.value,
            // FittedBox ולא Text חשוף: תווית ארוכה בסגמנט צר גלשה במקום
            // להצטמצם, ובעברית זה קרה כבר בשלוש-ארבע מילים.
            label: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  o.label,
                  style: AppTextStyles.settingTitle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            icon: hasIcons ? _buildOptionIcon(o) : null,
          ),
        )
        .toList();
  }

  Widget _buildOptionIcon(SegmentOption<T> o) {
    if (o.rtlIcon != null) return RtlIcon(o.rtlIcon!, size: 18);
    if (o.icon != null) return Icon(o.icon, size: 18);
    return const SizedBox(width: 18);
  }

  static ButtonStyle _buttonStyle(ColorScheme cs) => ButtonStyle(
        alignment: Alignment.center,
        // מושבת נבדק ראשון: אחרת סגמנט נעול ומסומן נראה לחיץ כמו כל השאר.
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppSurfaces.disabledForeground(cs);
          }
          if (states.contains(WidgetState.selected)) {
            return cs.onSecondaryContainer;
          }
          return cs.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return states.contains(WidgetState.selected)
                ? AppSurfaces.disabledSelectedBackground(cs)
                : cs.surface;
          }
          if (states.contains(WidgetState.selected)) {
            return cs.secondaryContainer;
          }
          return cs.surface;
        }),
        shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
      );

  /// גובה הכפתור בברירת המחדל של M3 — ראו [_fixedHeightStyle].
  static const double _defaultSegmentHeight = 40;

  /// `SegmentedButton` מעתיק לסגמנטים רק חלק מהסגנון ומשמיט ממנו את
  /// `minimumSize`/`maximumSize` (`segmentStyleFor` שלו), ולכן הדרך היחידה
  /// לקבוע להם גובה אחר מ-40 היא צפיפות: כל יחידה שווה 4px.
  static ButtonStyle _fixedHeightStyle(ColorScheme cs, double height) =>
      _buttonStyle(cs).copyWith(
        visualDensity: VisualDensity(
          horizontal: -2,
          vertical: ((height - _defaultSegmentHeight) / 4).clamp(
            VisualDensity.minimumDensity,
            VisualDensity.maximumDensity,
          ),
        ),
        // בלי זה נוסף ריפוד שטח-מגע עד 48px, שגם הוא מגביה את הכפתור מעל
        // התיבה ומוריד את התווית מתחת למרכזה.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFixed = height != null;

    return SegmentedButton<T>(
      segments: _segments(),
      selected: {currentValue},
      expandedInsets: expandToFillWidth ? EdgeInsets.zero : null,
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      // בלי סימן וי על הנבחר: הוא הכריח ריפוד אנכי משלו (16px) שהגובה הקבוע
      // לא מכסה, כך שהכפתור יצא גבוה מהתיבה והתווית ירדה מתחת למרכזה. הרקע
      // המלא כבר מסמן איזו אפשרות נבחרה.
      showSelectedIcon: false,
      style: isFixed
          ? _fixedHeightStyle(cs, height!)
          : _buttonStyle(cs).copyWith(visualDensity: VisualDensity.compact),
    );
  }
}
