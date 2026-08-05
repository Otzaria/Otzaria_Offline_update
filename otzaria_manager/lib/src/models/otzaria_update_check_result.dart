import 'otzaria_install_state.dart';
import 'otzaria_release.dart';

/// תוצאת בדיקת עדכון: מה מותקן כרגע (אם בכלל) מול מה זמין ב-GitHub.
class OtzariaUpdateCheckResult {
  const OtzariaUpdateCheckResult({
    required this.latestRelease,
    required this.currentState,
  });

  final OtzariaRelease latestRelease;

  /// null אם עדיין לא בוצעה אף התקנה על ידי הלאנצ'ר הזה.
  final OtzariaInstallState? currentState;

  /// true גם כשאין התקנה קודמת בכלל (currentState == null) — אז "צריך
  /// עדכון" פשוט אומר "צריך התקנה ראשונית".
  bool get updateAvailable {
    final current = currentState;
    if (current == null) return true;
    return normalizeVersion(current.installedTagName) !=
        normalizeVersion(latestRelease.tagName);
  }

  /// מנרמל תג/גרסה להשוואה: מוריד `v` מוביל ואת סיומת ה-build שאחרי `+`.
  ///
  /// **למה זה נחוץ:** כשההתקנה בוצעה על ידי הלאנצ'ר, [OtzariaInstallState.
  /// installedTagName] הוא תג ה-release המלא (`0.9.96+736`). אבל כשמזהים
  /// התקנה קיימת שלא נעשתה דרך הלאנצ'ר, הגרסה נקראת מתוך ההתקנה עצמה —
  /// ושם היא **בלי** ה-build: `ProductVersion` בווינדוס ו-
  /// `CFBundleShortVersionString` ב-macOS מחזירים שניהם `0.9.96`. בלי
  /// הנרמול הזה, כל זיהוי של התקנה קיימת היה נראה כמו "יש עדכון" ומוריד
  /// שוב את אותה גרסה בדיוק (ב-macOS: 73MB, בווינדוס installer מלא).
  static String normalizeVersion(String raw) {
    var version = raw.trim();
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    final buildSeparator = version.indexOf('+');
    return buildSeparator >= 0 ? version.substring(0, buildSeparator) : version;
  }
}
