import 'package:flutter/material.dart';

/// [Switch] תואם M3 — פורט מאוצריא, לפי
/// https://m3.material.io/components/switch/specs
class CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final FocusNode? focusNode;

  const CustomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Switch(
      value: value,
      onChanged: onChanged,
      focusNode: focusNode,
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.38);
        }
        if (s.contains(WidgetState.selected)) return cs.onPrimary;
        return cs.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.surfaceContainerHighest.withValues(alpha: 0.12);
        }
        if (s.contains(WidgetState.selected)) return cs.primary;
        return cs.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.transparent;
        return cs.outline;
      }),
    );
  }
}
