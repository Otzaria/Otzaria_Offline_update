import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
//  app_theme_data.dart
//  פורט מ-`otzaria/lib/theme/app_theme_data.dart` — אותה בניית ColorScheme,
//  אותם hover/overlay בצבע primary, אותו רדיוס 8 ואותם תפריטים.
// ════════════════════════════════════════════════════════════════════════════

class AppThemeData {
  AppThemeData._();

  /// בונה [ColorScheme] מצבע seed ובהירות. צבע ניטרלי (רוויה נמוכה) מקבל
  /// וריאנט monochrome כדי שלא יקבל גוון צבעוני לא רצוי.
  static ColorScheme createColorScheme(Color seedColor, Brightness brightness) {
    final isNeutral = HSLColor.fromColor(seedColor).saturation < 0.1;
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: isNeutral
          ? DynamicSchemeVariant.monochrome
          : DynamicSchemeVariant.tonalSpot,
    );
  }

  static ThemeData light(ColorScheme cs) => _build(cs);

  static ThemeData dark(ColorScheme cs) => _build(cs);

  static ThemeData _build(ColorScheme cs) {
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Roboto',
      colorScheme: cs,
      textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 18.0)),
      cardTheme: const CardThemeData(shape: AppTokens.roundedShape),
      iconButtonTheme: _iconButtonTheme(cs),
      filledButtonTheme: _filledButtonTheme(cs),
      textButtonTheme: _textButtonTheme(cs),
      outlinedButtonTheme: _outlinedButtonTheme(cs),
      tooltipTheme: _tooltipTheme(cs),
      popupMenuTheme: _popupMenuTheme(cs),
      menuTheme: _menuTheme(cs),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        borderRadius: AppTokens.borderRadiusAll,
        color: cs.primary,
      ),
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: cs.surfaceContainerHigh,
        shape: AppTokens.roundedShape,
      ),
    );
  }

  static PopupMenuThemeData _popupMenuTheme(ColorScheme cs) {
    return PopupMenuThemeData(
      color: cs.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      elevation: AppTokens.elevation2,
      shape: AppTokens.roundedShape,
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: TextStyle(
        fontFamily: 'Roboto',
        color: cs.onSurface,
        fontSize: AppTokens.fontMD,
      ),
    );
  }

  static MenuThemeData _menuTheme(ColorScheme cs) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.22),
        ),
        elevation: const WidgetStatePropertyAll(AppTokens.elevation2),
        shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  static TooltipThemeData _tooltipTheme(ColorScheme cs) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: TextStyle(color: cs.onSurface),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Button Themes — hover בצבע primary (8%) ו-pressed/focused (12%)
  // ══════════════════════════════════════════════════════════════════════════

  static WidgetStateProperty<Color?> _overlay(Color color) =>
      WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) {
          return color.withValues(alpha: 0.08);
        }
        if (s.contains(WidgetState.pressed) ||
            s.contains(WidgetState.focused)) {
          return color.withValues(alpha: 0.12);
        }
        return null;
      });

  static IconButtonThemeData _iconButtonTheme(ColorScheme cs) =>
      IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: _overlay(cs.primary),
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(ColorScheme cs) =>
      FilledButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: _overlay(cs.onPrimary),
        ),
      );

  static TextButtonThemeData _textButtonTheme(ColorScheme cs) =>
      TextButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: _overlay(cs.primary),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
      OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: _overlay(cs.primary),
        ),
      );
}
