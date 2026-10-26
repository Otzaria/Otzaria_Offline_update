import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';
import 'app_surfaces.dart';
import 'app_tokens.dart';

/// ערכת הנושא היחידה: בהירה, מ-seed קבוע — אותה פלטה כמו מסייע ההורדות של
/// אוצריא. אין מצב כהה ואין בחירת צבע.
class AppThemeData {
  AppThemeData._();

  static const Color seed = Color(0xFF2C1B02);
  static const String fontFamily = 'Segoe UI';

  /// `_kFinalLabelScale` של InputDecorator.
  static const double _floatingLabelScale = 0.75;

  static final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );

  static ThemeData light() {
    final cs = colorScheme;
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: fontFamily,
      colorScheme: cs,
      scaffoldBackgroundColor: AppPalette.light.page,
      extensions: const [AppPalette.light],
      cardTheme: CardThemeData(
        color: cs.surface,
        shape: AppTokens.roundedShape,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      iconButtonTheme: _iconButtonTheme(cs),
      filledButtonTheme: _filledButtonTheme(cs),
      textButtonTheme: _textButtonTheme(cs),
      outlinedButtonTheme: _outlinedButtonTheme(cs),
      tooltipTheme: _tooltipTheme(cs),
      popupMenuTheme: _popupMenuTheme(cs),
      menuTheme: _menuTheme(cs),
      listTileTheme: _listTileTheme(cs),
      inputDecorationTheme: _inputDecorationTheme(cs),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(2),
        thumbColor: WidgetStatePropertyAll(cs.outlineVariant),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        borderRadius: AppTokens.borderRadiusAll,
        color: cs.primary,
        linearTrackColor: cs.secondaryContainer,
        linearMinHeight: 8,
      ),
    ).copyWith(
      dialogTheme: DialogThemeData(
        barrierColor: AppColors.dialogBarrier,
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: AppTokens.roundedShape,
        titleTextStyle: AppTextStyles.dialogTitle.copyWith(
          color: cs.onSurface,
        ),
        contentTextStyle: AppTextStyles.dialogBody.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  /// מסגרת במקום צל: הממשק שטוח.
  static BorderSide _menuBorder(ColorScheme cs) =>
      BorderSide(color: cs.outlineVariant);

  static PopupMenuThemeData _popupMenuTheme(ColorScheme cs) {
    return PopupMenuThemeData(
      color: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
        side: _menuBorder(cs),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      textStyle: TextStyle(
        fontFamily: fontFamily,
        color: cs.onSurface,
        fontSize: AppTokens.fontMD,
      ),
    );
  }

  static MenuThemeData _menuTheme(ColorScheme cs) {
    return MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerLowest),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
            side: _menuBorder(cs),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  static TooltipThemeData _tooltipTheme(ColorScheme cs) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      textStyle: TextStyle(
        fontFamily: fontFamily,
        color: cs.onInverseSurface,
        fontSize: AppTokens.fontSM,
      ),
    );
  }

  /// שורה ברשימה (`.row` במוקאפ): ריפוד 12/16, רווח 14, גובה לפחות 56.
  static ListTileThemeData _listTileTheme(ColorScheme cs) => ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 12,
        horizontalTitleGap: 14,
        minTileHeight: 56,
        minLeadingWidth: 32,
        iconColor: cs.onSurfaceVariant,
        titleTextStyle: AppTextStyles.rowTitle.copyWith(color: cs.onSurface),
        subtitleTextStyle: AppTextStyles.rowSub.copyWith(
          color: cs.onSurfaceVariant,
        ),
      );

  /// שדה קלט (`.field input`): 44, מסגרת outline, רקע לבן, רדיוס 8; בפוקוס
  /// מסגרת primary ברוחב 2.
  static InputDecorationThemeData _inputDecorationTheme(ColorScheme cs) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: AppTokens.borderRadiusAll,
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecorationThemeData(
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      // dense: אחרת M3 כופה גובה 48 מעל ה-44 של המוקאפ.
      isDense: true,
      constraints: const BoxConstraints(minHeight: AppTokens.fieldHeight),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(cs.outline),
      enabledBorder: border(cs.outline),
      focusedBorder: border(cs.primary, 2),
      errorBorder: border(cs.error),
      focusedErrorBorder: border(cs.error, 2),
      disabledBorder: border(AppPalette.light.disabledContainer),
      // במנוחה התווית בסגנון שורת הטקסט. צפה היא 13/600: InputDecorator מקטין
      // אותה פי 0.75, ולכן הגודל המוגדר מחולק בו.
      labelStyle: AppTextStyles.field.copyWith(color: cs.onSurfaceVariant),
      floatingLabelStyle: AppTextStyles.sectionLabel.copyWith(
        fontSize: AppTextStyles.sectionLabel.fontSize! / _floatingLabelScale,
        color: cs.onSurfaceVariant,
      ),
      hintStyle: AppTextStyles.field.copyWith(color: cs.onSurfaceVariant),
      helperStyle: AppTextStyles.meta.copyWith(color: cs.onSurfaceVariant),
      errorStyle: AppTextStyles.small.copyWith(color: cs.error),
      prefixIconColor: cs.onSurfaceVariant,
      suffixIconColor: cs.onSurfaceVariant,
      // ברירת המחדל של M3 היא 48, והיא הייתה מגביהה שדה עם סמל מעל 44.
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }

  // ── Button Themes — hover 8%, pressed 12%, טבעת מיקוד מהמקלדת ──

  static IconButtonThemeData _iconButtonTheme(ColorScheme cs) =>
      IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: AppSurfaces.stateLayer(cs.primary),
          side: AppSurfaces.focusRingSide(cs.primary),
        ),
      );

  static FilledButtonThemeData _filledButtonTheme(ColorScheme cs) =>
      FilledButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: AppSurfaces.stateLayer(cs.onPrimary),
          side: AppSurfaces.focusRingSide(cs.primary),
        ),
      );

  static TextButtonThemeData _textButtonTheme(ColorScheme cs) =>
      TextButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: AppSurfaces.stateLayer(cs.primary),
          side: AppSurfaces.focusRingSide(cs.primary),
        ),
      );

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme cs) =>
      OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppTokens.roundedShape),
          overlayColor: AppSurfaces.stateLayer(cs.primary),
          side: AppSurfaces.focusRingSide(cs.primary),
        ),
      );
}
