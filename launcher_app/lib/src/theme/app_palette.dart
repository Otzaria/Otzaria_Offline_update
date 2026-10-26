import 'package:flutter/material.dart';

import 'app_colors.dart';

/// הצבעים של שפת העיצוב שאינם תפקידי [ColorScheme] — ערכי ה-`:root` של
/// המוקאפ. ערכת הנושא בהירה וקבועה, ולכן כולם קבועים ולא נגזרים בזמן ריצה.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.page,
    required this.titleBarBorder,
    required this.captionHover,
    required this.captionGlyph,
    required this.closeHover,
    required this.closeGlyph,
    required this.cardSelected,
    required this.primaryHover,
    required this.primaryPressed,
    required this.tonalHover,
    required this.tonalPressed,
    required this.disabledContainer,
    required this.disabledText,
    required this.dotDone,
    required this.ornament,
    required this.glow,
    required this.rating,
  });

  static const AppPalette light = AppPalette(
    page: Color(0xFFF6EDE5),
    titleBarBorder: Color(0xFFE1D4C8),
    captionHover: Color(0xFFEDE4DC),
    captionGlyph: Color(0xFF1A1918),
    closeHover: Color(0xFFC42B1C),
    closeGlyph: Color(0xFFFFFFFF),
    cardSelected: Color(0xFFFEF0E3),
    primaryHover: Color(0xFF8A6423),
    primaryPressed: Color(0xFF8F6A2D),
    tonalHover: Color(0xFFFBE1C1),
    tonalPressed: Color(0xFFFBE2C4),
    disabledContainer: Color(0xFFDDD3CC),
    disabledText: Color(0xFFA59D95),
    dotDone: Color(0xFFBBA27A),
    ornament: Color(0xFFB2883E),
    glow: Color(0xFFE9B96A),
    rating: AppColors.ratingStar,
  );

  /// רקע החלון והעמוד (`panelBackground`).
  final Color page;
  final Color titleBarBorder;
  final Color captionHover;
  final Color captionGlyph;

  /// ריחוף על כפתור הסגירה — המוסכמה של Windows 11, עם סמל לבן.
  final Color closeHover;

  /// הסמל על [closeHover] — לבן קבוע, כמו ב-Windows.
  final Color closeGlyph;
  final Color cardSelected;
  final Color primaryHover;
  final Color primaryPressed;
  final Color tonalHover;
  final Color tonalPressed;
  final Color disabledContainer;
  final Color disabledText;
  final Color dotDone;
  final Color ornament;
  final Color glow;

  /// כוכבי הדירוג בחנות.
  final Color rating;

  /// בלי ערכת נושא (בדיקה שבונה `MaterialApp` משלה) — אותם ערכים.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? light;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) => this;
}
