import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// טוקני העיצוב של הלאנצ'ר.
///
/// כיוון: "חדר עיון" — דיו כהה על גבי קלף בהיר, כמו כריכת ספר עתיקה,
/// עם מבטא זהב מושחז שנשמר **חסכני בהחלט** (רק לסימון "עדכון זמין").
/// הכותרות בגופן סריף עברי קלאסי (Frank Ruhl Libre, כמו טיפוגרפיה של
/// דפוס ספרים ישן), הגוף בגופן סאנס עברי נקי (Assistant) לקריאות טובה
/// במסכי סטטוס.
class AppColors {
  AppColors._();

  static const ink = Color(0xFF1E3A3A);
  static const inkDark = Color(0xFF12302F);
  static const parchment = Color(0xFFF5F1E8);
  static const parchmentAlt = Color(0xFFE9E1CE);
  static const gold = Color(0xFF9C7A2E);
  static const success = Color(0xFF3F7859);
  static const danger = Color(0xFF8B3A3A);
  static const textPrimary = Color(0xFF2A2A24);
  static const textSecondary = Color(0xFF6B6558);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final displayFont = GoogleFonts.frankRuhlLibreTextTheme();
    final bodyFont = GoogleFonts.assistantTextTheme();

    final textTheme = bodyFont.copyWith(
      headlineMedium: displayFont.headlineMedium?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: displayFont.headlineSmall?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: displayFont.titleLarge?.copyWith(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      titleMedium: bodyFont.titleMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: bodyFont.bodyMedium?.copyWith(color: AppColors.textPrimary),
      bodySmall: bodyFont.bodySmall?.copyWith(color: AppColors.textSecondary),
      labelLarge: bodyFont.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.parchment,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.ink,
        secondary: AppColors.gold,
        surface: AppColors.parchmentAlt,
        error: AppColors.danger,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.parchment,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.parchmentAlt,
          disabledForegroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: textTheme.labelLarge,
        ),
      ),
    );
  }
}
