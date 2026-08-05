import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.rtlIcon,
    this.subtitle,
  }) : assert(
          icon == null || rtlIcon == null,
          'העבר icon או rtlIcon — לא שניהם יחד',
        );
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
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(o.label, style: AppTextStyles.settingTitle),
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
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.onSecondaryContainer;
          }
          return cs.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.secondaryContainer;
          }
          return cs.surface;
        }),
        shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
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
      selectedIcon: const Icon(FluentIcons.checkmark_24_regular, size: 16),
      style: isFixed
          ? _buttonStyle(cs).copyWith(
              minimumSize: WidgetStateProperty.all(Size(0, height!)),
              maximumSize: WidgetStateProperty.all(
                Size(double.infinity, height!),
              ),
            )
          : _buttonStyle(cs).copyWith(visualDensity: VisualDensity.compact),
    );
  }
}
