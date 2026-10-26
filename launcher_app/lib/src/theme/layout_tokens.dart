import 'package:flutter/painting.dart';

class LayoutBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;
}

/// קבועי מידות לפריסת ממשק
class LayoutConstraints {
  LayoutConstraints._();

  /// רוחב התוכן המרבי של דף (`.page` במוקאפ: 768 פחות ריפוד 24 מכל צד).
  static const double panelContentMaxWidth = 720.0;

  /// רוחב התוכן של דף רחב — חנות התוספים.
  static const double wideContentMaxWidth = 960.0;

  /// הריפוד של הדף: 24 בצדדים, 28 למעלה ו-40 למטה.
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(24, 28, 24, 40);
}
