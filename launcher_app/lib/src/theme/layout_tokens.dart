class LayoutBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;
}

/// קבועי מידות לפריסת ממשק
class LayoutConstraints {
  LayoutConstraints._();

  /// רוחב מקסימלי לתוכן בתוך מסך — מונע כרטיסים רחבים מדי בדסקטופ (תכנון §14)
  static const double panelContentMaxWidth = 860.0;
}
