// UiSnack — טוסט ממורכז בתחתית, בלי תור ובלי פעולות. אין להשתמש
// ב-ScaffoldMessenger/SnackBar ישירות.

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../theme/theme_exports.dart';

/// מפתח גלובלי לניווט — חובה לחבר ל-MaterialApp כדי ש-[UiSnack] יעבוד.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

abstract class _ToastTokens {
  static const double maxWidth = 540;
  static const int maxLines = 3;
}

enum _SnackVariant { standard, success, error }

class UiSnack {
  UiSnack._();

  static OverlayEntry? _currentOverlay;
  static Timer? _dismissTimer;

  static void show(String message) =>
      _show(message, _SnackVariant.standard, FluentIcons.info_24_regular);

  static void showSuccess(String message) => _show(
        message,
        _SnackVariant.success,
        FluentIcons.checkmark_circle_24_regular,
      );

  static void showError(String message) => _show(
        message,
        _SnackVariant.error,
        FluentIcons.error_circle_24_regular,
      );

  static void showFailure(String? message) => showError(
        message == null || message.isEmpty
            ? AppL10n.strings.common.error
            : message,
      );

  static void _show(String message, _SnackVariant variant, IconData icon) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('UiSnack ללא overlay: $message');
      return;
    }

    _dismiss();

    final entry = OverlayEntry(
      builder: (context) => _SnackView(
        message: message,
        variant: variant,
        icon: icon,
      ),
    );
    _currentOverlay = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(const Duration(seconds: 6), _dismiss);
  }

  static void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}

class _SnackView extends StatelessWidget {
  final String message;
  final _SnackVariant variant;
  final IconData icon;

  const _SnackView({
    required this.message,
    required this.variant,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = switch (variant) {
      _SnackVariant.error => cs.errorContainer,
      _ => AppPalette.of(context).glow,
    };

    return Positioned(
      left: AppTokens.spaceMD,
      right: AppTokens.spaceMD,
      bottom: 20,
      // ההודעה יושבת ב-Overlay מעל ה-Navigator ולא יורשת ממנו כיווניות,
      // ולכן היא נגזרת ישירות מהשפה הפעילה.
      child: Directionality(
        textDirection:
            AppL10n.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _ToastTokens.maxWidth),
            child: Material(
              color: cs.inverseSurface,
              borderRadius: AppTokens.borderRadiusAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMD,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: accent),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        message,
                        // הטוסט הוא שורה; הפירוט יושב בכרטיס וביומן הפעילות.
                        maxLines: _ToastTokens.maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: cs.onInverseSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
