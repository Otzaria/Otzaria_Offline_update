import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';

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

    // מושבת = אותו מתג ב-38% (`.sw:disabled`), ולכן הצבעים אינם תלויים בו.
    final control = Switch(
      value: value,
      onChanged: onChanged,
      focusNode: focusNode,
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? cs.onPrimary : cs.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? cs.primary
            : cs.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? cs.primary : cs.outline,
      ),
      overlayColor: AppSurfaces.stateLayerWithFocus(cs.primary),
    );
    return onChanged == null ? Opacity(opacity: 0.38, child: control) : control;
  }
}
