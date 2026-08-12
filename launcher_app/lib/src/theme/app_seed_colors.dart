import 'package:flutter/material.dart';

/// מזהה כל צבע בפלטה. באוצריא הרשימה נושאת את השם העברי עצמו; כאן המלל
/// חייב לבוא מ-`otzaria_l10n` (AGENTS §4), ו-enum הוא מה שמכריח את הבורר
/// לתרגם כל צבע — הוספת צבע בלי שם נופלת ב-switch, לא בזמן ריצה.
enum SeedColorLabel {
  red,
  orange,
  amber,
  green,
  teal,
  blue,
  blueGrey,
  navy,
  purple,
  brown,
  parchment,
  grey,
  darkBrown,
}

/// צבעי הבסיס לבחירת ערכת הצבעים — מועתק מאוצריא, כולל ברירות המחדל,
/// כדי ששתי האפליקציות יפתחו באותם גוונים.
class AppSeedColors {
  AppSeedColors._();

  // ── ברירות מחדל ————————————————————————————————
  static const Color defaultLight = darkBrown;
  static const Color defaultDark = purple;

  // ── צבעי ספקטרום ————————————————————————————————
  static const Color red = Color(0xFFF44336);
  static const Color orange = Color(0xFFFF9800);
  static const Color amber = Color(0xFFFFC107);
  static const Color green = Color(0xFF4CAF50);
  static const Color teal = Color(0xFF009688);
  static const Color blue = Color(0xFF2196F3);
  static const Color blueGrey = Color(0xFF607D8B);
  static const Color navy = Color(0xFF001A33);
  static const Color purple = Color(0xFF9C27B0);

  // ── צבעים נייטרלים ————————————————————————————
  static const Color brown = Color(0xFF795548);
  static const Color parchment = Color(0xFFD7CCC8);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color darkBrown = Color(0xFF2C1B02);

  /// כל הצבעים, בסדר שבו הם מוצגים בבורר — סדר האוצריא.
  static const List<({Color color, SeedColorLabel label})> options = [
    (color: red, label: SeedColorLabel.red),
    (color: orange, label: SeedColorLabel.orange),
    (color: amber, label: SeedColorLabel.amber),
    (color: green, label: SeedColorLabel.green),
    (color: teal, label: SeedColorLabel.teal),
    (color: blue, label: SeedColorLabel.blue),
    (color: blueGrey, label: SeedColorLabel.blueGrey),
    (color: navy, label: SeedColorLabel.navy),
    (color: purple, label: SeedColorLabel.purple),
    (color: brown, label: SeedColorLabel.brown),
    (color: parchment, label: SeedColorLabel.parchment),
    (color: grey, label: SeedColorLabel.grey),
    (color: darkBrown, label: SeedColorLabel.darkBrown),
  ];

  /// המזהה של צבע, או `null` אם אינו אחד מצבעי הפלטה (קובץ הגדרות שנערך ביד).
  static SeedColorLabel? labelOf(Color color) {
    for (final entry in options) {
      if (entry.color.toARGB32() == color.toARGB32()) return entry.label;
    }
    return null;
  }
}
