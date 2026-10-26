import 'package:flutter/material.dart';

/// צבעים קבועים שאינם חלק מה-ColorScheme. השאר נגזר מ-[ColorScheme.fromSeed]
/// או יושב ב-`AppPalette`.
class AppColors {
  AppColors._();

  /// השכבה מאחורי דו-שיח: שחור ב-13.3%.
  static const Color dialogBarrier = Color(0x22000000);

  /// כוכב הדירוג בחנות. המקור היחיד — `AppPalette.rating` מפנה לכאן.
  static const Color ratingStar = Color(0xFF9C6E28);
}
