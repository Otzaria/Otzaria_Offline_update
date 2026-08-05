import 'package:flutter/material.dart';

/// צבעים קבועים שאינם חלק מה-ColorScheme הדינמי — מועתק מאוצריא.
/// כל השאר (primary/surface/error…) נגזר מ-[ColorScheme.fromSeed].
class AppColors {
  AppColors._();

  /// רקע ה-Scaffold במצב כהה
  static const Color darkScaffold = Color(0xFF242424);

  /// צבע מחסום הדיאלוג (barrier) — חצי שקוף
  static const Color dialogBarrier = Color(0x22000000);
}
