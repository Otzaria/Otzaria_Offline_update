// כפתורי פעולה גנריים בסגנון M3 — פורט מאוצריא.
// אין להשתמש ב-ElevatedButton/TextButton/OutlinedButton ישירות.

import 'package:flutter/material.dart';

import '../theme/theme_exports.dart';
import 'rtl_icon.dart';

enum _Variant { recommended, neutral, outlined, ghost, warning }

/// גובה הכפתור: 32 / 40 / 44, כמו `.btn.sm` / `.btn` / `.btn.lg` במוקאפ.
enum ActionButtonSize { sm, md, lg }

/// כפתור פעולה: recommended (מלא), neutral (tonal), ghost (שקוף), warning
/// (הרסני). outlined אינו במוקאפ — לא במסכים חדשים.
class ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// מסובב את הסמל במקום להחליף את התוכן במד טעינה — לפעולות קצרות
  /// שהכפתור צריך להישאר קריא בזמנן.
  final bool spinning;
  final IconData? icon;

  /// לוקח את המיקוד בהופעה, ואז Enter מפעיל אותו — כפתור ברירת המחדל של
  /// דיאלוג. ראו `AppDialog`.
  final bool autofocus;

  /// למיקוד יזום — למשל "ביטול" אחרי Enter בשדה של דו-שיח הרסני.
  final FocusNode? focusNode;

  final ActionButtonSize size;

  /// ממלא את רוחב ההורה — ערימת פעולות בדף תוצאה.
  final bool expand;
  final _Variant _variant;

  const ActionButton.recommended({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.spinning = false,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.size = ActionButtonSize.md,
    this.expand = false,
  }) : _variant = _Variant.recommended;

  const ActionButton.neutral({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.spinning = false,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.size = ActionButtonSize.md,
    this.expand = false,
  }) : _variant = _Variant.neutral;

  const ActionButton.outlined({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.spinning = false,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.size = ActionButtonSize.md,
    this.expand = false,
  }) : _variant = _Variant.outlined;

  const ActionButton.ghost({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.spinning = false,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.size = ActionButtonSize.md,
    this.expand = false,
  }) : _variant = _Variant.ghost;

  const ActionButton.warning({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.spinning = false,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.size = ActionButtonSize.md,
    this.expand = false,
  }) : _variant = _Variant.warning;

  Color _loadingColor(ColorScheme cs) => switch (_variant) {
        _Variant.recommended => cs.onPrimary,
        _Variant.neutral => cs.onSecondaryContainer,
        _Variant.outlined || _Variant.ghost => cs.primary,
        _Variant.warning => cs.error,
      };

  double get _height => switch (size) {
        ActionButtonSize.sm => AppTokens.buttonHeightSm,
        ActionButtonSize.md => AppTokens.buttonHeight,
        ActionButtonSize.lg => AppTokens.buttonHeightLg,
      };

  double get _hPadding => switch (size) {
        ActionButtonSize.sm => 12,
        ActionButtonSize.lg => 24,
        ActionButtonSize.md =>
          _variant == _Variant.ghost || _variant == _Variant.warning ? 14 : 20,
      };

  /// המידות והצבעים של המוקאפ. ריחוף ולחיצה 8%/12%; ה-tonal מתבהר בלבן.
  /// מיקוד אינו צובע — טבעת, ורק מהמקלדת (`:focus-visible`).
  ButtonStyle _buttonStyle(BuildContext context, ColorScheme cs) {
    final palette = AppPalette.of(context);
    final (Color? background, Color foreground) = switch (_variant) {
      _Variant.recommended => (cs.primary, cs.onPrimary),
      _Variant.neutral => (cs.secondaryContainer, cs.onSecondaryContainer),
      _Variant.outlined || _Variant.ghost => (null, cs.primary),
      _Variant.warning => (null, cs.error),
    };
    final filled = background != null;
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, _height)),
      maximumSize: WidgetStatePropertyAll(Size(double.infinity, _height)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: _hPadding),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      elevation: const WidgetStatePropertyAll(0),
      shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
      side: AppSurfaces.focusRingSide(
        cs.primary,
        _variant == _Variant.outlined
            ? WidgetStateProperty.resolveWith(
                (s) => BorderSide(
                  color: s.contains(WidgetState.disabled)
                      ? palette.disabledContainer
                      : cs.outline,
                ),
              )
            : null,
      ),
      iconSize: const WidgetStatePropertyAll(20),
      textStyle: WidgetStatePropertyAll(
        size == ActionButtonSize.sm
            ? AppTextStyles.buttonSm
            : AppTextStyles.button,
      ),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (!filled) return Colors.transparent;
        if (s.contains(WidgetState.disabled)) return palette.disabledContainer;
        return background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? palette.disabledText
            : foreground,
      ),
      iconColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? palette.disabledText
            : foreground,
      ),
      overlayColor: AppSurfaces.stateLayer(switch (_variant) {
        _Variant.recommended => cs.onPrimary,
        _Variant.neutral => Colors.white,
        _Variant.warning => cs.error,
        _ => cs.primary,
      }),
    );
  }

  Widget _plain({
    required VoidCallback? onPressed,
    required Widget child,
    required ButtonStyle style,
  }) =>
      switch (_variant) {
        _Variant.recommended => FilledButton(
            onPressed: onPressed,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
            child: child,
          ),
        _Variant.neutral => FilledButton.tonal(
            onPressed: onPressed,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
            child: child,
          ),
        _Variant.outlined => OutlinedButton(
            onPressed: onPressed,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
            child: child,
          ),
        _Variant.ghost || _Variant.warning => TextButton(
            onPressed: onPressed,
            style: style,
            autofocus: autofocus,
            focusNode: focusNode,
            child: child,
          ),
      };

  Widget _withIcon({required Widget leading, required ButtonStyle style}) {
    final label = Text(text);
    return switch (_variant) {
      _Variant.recommended => FilledButton.icon(
          onPressed: onPressed,
          style: style,
          autofocus: autofocus,
          focusNode: focusNode,
          icon: leading,
          label: label,
        ),
      _Variant.neutral => FilledButton.tonalIcon(
          onPressed: onPressed,
          style: style,
          autofocus: autofocus,
          focusNode: focusNode,
          icon: leading,
          label: label,
        ),
      _Variant.outlined => OutlinedButton.icon(
          onPressed: onPressed,
          autofocus: autofocus,
          focusNode: focusNode,
          icon: leading,
          label: label,
          style: style,
        ),
      _Variant.ghost || _Variant.warning => TextButton.icon(
          onPressed: onPressed,
          icon: leading,
          label: label,
          style: style,
          autofocus: autofocus,
          focusNode: focusNode,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = _buttonStyle(context, cs);
    final button = _build(cs, style);
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _build(ColorScheme cs, ButtonStyle style) {
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
      return _withIcon(
        leading: spinning
            ? _SpinningIcon(icon!, size: 20)
            : RtlIcon(icon!, size: 20),
        style: style,
      );
    }
    return _plain(
      onPressed: onPressed,
      style: style,
      child: Text(text),
    );
  }
}

/// סמל שמסתובב ברציפות — סימן חיים לפעולה קצרה שאין לה מד התקדמות.
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon(this.icon, {this.size});

  final IconData icon;
  final double? size;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _turns,
        child: RtlIcon(widget.icon, size: widget.size),
      );
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

/// כפתור סמל שקוף (`.ibtn`): 40, או 32 ב-[small]. [danger] — מחיקה.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.small = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool small;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final extent = small ? 32.0 : 40.0;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: RtlIcon(icon, size: small ? 18 : 20),
        style: IconButton.styleFrom(
          foregroundColor: danger ? cs.error : cs.onSurfaceVariant,
          disabledForegroundColor: AppPalette.of(context).disabledText,
          fixedSize: Size(extent, extent),
          minimumSize: Size(extent, extent),
          padding: EdgeInsets.zero,
          shape: AppTokens.roundedShape,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).copyWith(overlayColor: AppSurfaces.stateLayer(cs.primary)),
      ),
    );
  }
}
