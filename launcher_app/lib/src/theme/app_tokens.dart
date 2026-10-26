import 'package:flutter/material.dart';

/// טוקני מרווח, רדיוס, מידות וטיפוגרפיה — ערכי המוקאפ של שפת העיצוב.
class AppTokens {
  // ── Spacing ————————————————————————————————
  static const double spaceXS = 4;
  static const double spaceSM = 8;
  static const double spaceMD = 16;
  static const double spaceLG = 24;
  static const double spaceXL = 32;

  // ── Border Radius — מקור אמת יחיד: כל הפינות 8 ——————————————
  static const double radius = 8;
  static const BorderRadius borderRadiusAll = BorderRadius.all(
    Radius.circular(radius),
  );
  static const RoundedRectangleBorder roundedShape = RoundedRectangleBorder(
    borderRadius: borderRadiusAll,
  );

  /// גלולה — שבבים ופסי התקדמות.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));

  // ── Sizes ——————————————————————————————————
  static const double titleBarHeight = 36;
  static const double captionButtonWidth = 46;
  static const double buttonHeightSm = 32;
  static const double buttonHeight = 40;
  static const double buttonHeightLg = 44;
  static const double fieldHeight = 44;
  static const double chipHeight = 24;
  static const double rowMinHeight = 56;
  static const double taskFooterHeight = 68;
  static const double dialogWidth = 336;
  static const double dialogFormWidth = 440;

  /// טופס הדיווח — סוג, שדות ותמונות בשורה.
  static const double dialogWideWidth = 560;

  // ── Typography Scale ——————————————————————
  static const double fontSM = 12;
  static const double fontMD = 14;
  static const double fontLG = 16;
  static const double fontXL = 18;

  // ── Elevation — הממשק שטוח ————————————————
  static const double elevation0 = 0;
  static const double elevation1 = 0;
  static const double elevation2 = 0;

  // ── Animation Durations ————————————————————
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);
}

/// סגנונות הטקסט של המוקאפ (סולם 12/13/14/16/18/20/24/40). הצבע נקבע במקום
/// השימוש; w600 נפתר ל-Segoe UI Semibold.
class AppTextStyles {
  AppTextStyles._();

  static const FontWeight semibold = FontWeight.w600;

  /// גם כאן ולא רק ב-theme: סגנון של כפתור מחליף את סגנון ברירת המחדל כולו.
  static const String _family = 'Segoe UI';

  /// כותרת דף (`.h-page`).
  static const TextStyle pageTitle = TextStyle(
    fontFamily: _family,
    fontSize: 20,
    fontWeight: semibold,
    height: 1.3,
  );

  /// כותרת הגיבור בבית ובדף פרטים.
  static const TextStyle heroTitle = TextStyle(
    fontFamily: _family,
    fontSize: 24,
    fontWeight: semibold,
    height: 1.25,
  );

  /// תיאור תחת כותרת (`.t-desc`) וגוף רגיל.
  static const TextStyle body =
      TextStyle(fontFamily: _family, fontSize: AppTokens.fontMD);

  /// טקסט בשדה קלט: 14 בשורה של 20, כך ששדה עם ריפוד 12 הוא 44.
  static const TextStyle field = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontMD,
    height: 20 / 14,
  );

  /// טקסט משני קטן (`.t-13`).
  static const TextStyle small = TextStyle(fontFamily: _family, fontSize: 13);

  /// מטא (`.t-meta`, `.row-label`).
  static const TextStyle meta =
      TextStyle(fontFamily: _family, fontSize: AppTokens.fontSM);

  /// כותרת מקטע (`.sec-label`).
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: semibold,
  );

  /// כותרת שורה ותת-כותרת שלה (`.row-title`, `.row-sub`).
  static const TextStyle rowTitle = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontMD,
    fontWeight: semibold,
  );
  static const TextStyle rowSub = TextStyle(fontFamily: _family, fontSize: 13);

  /// ערך בשורת סיכום (`.row-value`) וכותרת כרטיס אפשרות (`.ot`).
  static const TextStyle rowValue =
      TextStyle(fontFamily: _family, fontSize: AppTokens.fontLG);

  /// כותרת כרטיס בולטת (`.name`, `.consent h3`).
  static const TextStyle cardTitle = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontLG,
    fontWeight: semibold,
  );

  /// אחוז ההתקדמות (`.pct`).
  static const TextStyle percent = TextStyle(
    fontFamily: _family,
    fontSize: 40,
    fontWeight: semibold,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// כותרת דו-שיח וגוף שלו.
  static const TextStyle dialogTitle = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontXL,
    fontWeight: semibold,
  );
  static const TextStyle dialogBody = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontMD,
    height: 1.55,
  );

  /// תווית כפתור (`.btn`), ו-13 בכפתור קטן.
  static const TextStyle button = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontMD,
    fontWeight: semibold,
  );
  static const TextStyle buttonSm = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: semibold,
  );

  /// שבב מצב.
  static const TextStyle chip = TextStyle(
    fontFamily: _family,
    fontSize: AppTokens.fontSM,
    fontWeight: semibold,
  );

  /// כותרת שורת הגדרה — שורה ברשימה.
  static const TextStyle settingTitle = rowTitle;

  /// תת-כותרת שורת הגדרה.
  static const TextStyle settingSubtitle = rowSub;
}
