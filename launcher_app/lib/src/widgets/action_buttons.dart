// כפתורי פעולה גנריים בסגנון M3 — פורט מאוצריא.
// אין להשתמש ב-ElevatedButton/TextButton/OutlinedButton ישירות.

import 'package:flutter/material.dart';

import 'rtl_icon.dart';

enum _Variant { recommended, neutral, ghost, warning }

/// כפתור פעולה גנרי בסגנון M3. השתמש בבנאים הממוינים:
/// - [ActionButton.recommended] — FilledButton לפעולה מומלצת
/// - [ActionButton.neutral] — FilledButton.tonal לפעולה ניטרלית
/// - [ActionButton.ghost] — TextButton שקוף וניטרלי
/// - [ActionButton.warning] — TextButton עם טקסט cs.error לפעולות הרסניות
class ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final _Variant _variant;

  const ActionButton.recommended({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : _variant = _Variant.recommended;

  const ActionButton.neutral({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : _variant = _Variant.neutral;

  const ActionButton.ghost({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : _variant = _Variant.ghost;

  const ActionButton.warning({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : _variant = _Variant.warning;

  Color _loadingColor(ColorScheme cs) => switch (_variant) {
        _Variant.recommended => cs.onPrimary,
        _Variant.neutral => cs.onSecondaryContainer,
        _Variant.ghost => cs.primary,
        _Variant.warning => cs.error,
      };

  ButtonStyle? _buttonStyle(ColorScheme cs) => _variant == _Variant.warning
      ? TextButton.styleFrom(foregroundColor: cs.error)
      : null;

  Widget _plain({
    required VoidCallback? onPressed,
    required Widget child,
    required ButtonStyle? style,
  }) =>
      switch (_variant) {
        _Variant.recommended => FilledButton(
            onPressed: onPressed,
            child: child,
          ),
        _Variant.neutral => FilledButton.tonal(
            onPressed: onPressed,
            child: child,
          ),
        _Variant.ghost || _Variant.warning => TextButton(
            onPressed: onPressed,
            style: style,
            child: child,
          ),
      };

  Widget _withIcon({required Widget leading, required ButtonStyle? style}) {
    final label = Text(text);
    return switch (_variant) {
      _Variant.recommended => FilledButton.icon(
          onPressed: onPressed,
          icon: leading,
          label: label,
        ),
      _Variant.neutral => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: leading,
          label: label,
        ),
      _Variant.ghost || _Variant.warning => TextButton.icon(
          onPressed: onPressed,
          icon: leading,
          label: label,
          style: style,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = _buttonStyle(cs);

    if (isLoading) {
      return _plain(
        onPressed: null,
        style: style,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _loadingColor(cs),
          ),
        ),
      );
    }
    if (icon != null) {
      return _withIcon(leading: RtlIcon(icon!, size: 18), style: style);
    }
    return _plain(
      onPressed: onPressed,
      style: style,
      child: Text(text),
    );
  }
}

/// כפתור אייקון ניטרלי (secondaryContainer) — לפעולות משניות בשורה.
class SecondaryIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;

  const SecondaryIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: RtlIcon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
