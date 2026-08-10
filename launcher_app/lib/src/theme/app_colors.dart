import 'package:flutter/material.dart';

/// צבעים קבועים שאינם חלק מה-ColorScheme הדינמי — מועתק מאוצריא.
/// כל השאר (primary/surface/error…) נגזר מ-[ColorScheme.fromSeed].
class AppColors {
  AppColors._();

  /// צבע מחסום הדיאלוג (barrier) — חצי שקוף
  static const Color dialogBarrier = Color(0x22000000);
}
