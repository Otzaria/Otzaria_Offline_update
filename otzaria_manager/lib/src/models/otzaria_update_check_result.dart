import 'otzaria_install_state.dart';
import 'otzaria_release.dart';
import 'otzaria_release_channel.dart';

/// תוצאת בדיקת עדכון: מה מותקן כרגע (אם בכלל) מול מה שיושב **במראה
/// המקומית**. הבדיקה עצמה אינה נוגעת ברשת.
///
/// המראה מחזיקה עד שתי גרסאות — יציבה ולא-יציבה. [preferPrerelease] הוא
/// מה שהמשתמש בחר בהגדרות, והוא זה שקובע איזו מהן [latestRelease] מחזיר.
class OtzariaUpdateCheckResult {
  const OtzariaUpdateCheckResult({
    required this.currentState,
    this.stableRelease,
    this.prereleaseRelease,
    this.preferPrerelease = false,
    this.isOtzariaRunning = false,
  });

  /// הגרסה היציבה שבמראה, או null אם לא הורדה כזו.
  final OtzariaRelease? stableRelease;

  /// ה-pre-release שבמראה — קיים רק כשהוא חדש מהיציבה (ראו
  /// `OtzariaReleaseClient.fetchChannelReleases`).
  final OtzariaRelease? prereleaseRelease;

  /// בחירת המשתמש בין השתיים. חסרת משמעות כשאין [hasChannelChoice].
  final bool preferPrerelease;

  /// null אם עדיין לא בוצעה אף התקנה על ידי הלאנצ'ר הזה.
  final OtzariaInstallState? currentState;

  /// האם אוצריא פתוחה כרגע, כפי שנצפה **באותה בדיקת תהליך** ששימשה לזיהוי
  /// ההתקנה. מוחזר כאן כדי שהממשק לא יריץ בדיקת תהליך שנייה משלו.
  final bool isOtzariaRunning;

  /// הגרסה שתותקן בפועל — לפי הערוץ שנבחר, עם נפילה לערוץ השני כשהנבחר
  /// ריק. null אם עדיין לא הורדה שום גרסה. ראו [needsDownload].
  OtzariaRelease? get latestRelease =>
      _mirrored.select(preferPrerelease: preferPrerelease);

  /// הערוץ שאליו שייכת [latestRelease] בפועל.
  OtzariaReleaseChannel? get selectedChannel =>
      _mirrored.selectedChannel(preferPrerelease: preferPrerelease);

  /// שתי הגרסאות יושבות במראה — רק אז יש למשתמש מה לבחור.
  bool get hasChannelChoice => _mirrored.hasChoice;

  OtzariaChannelReleases get _mirrored => OtzariaChannelReleases(
        stable: stableRelease,
        prerelease: prereleaseRelease,
      );

  /// אין מה להשוות מולו — צריך קודם להריץ הורדה במחשב עם אינטרנט.
  bool get needsDownload => latestRelease == null;

  /// true גם כשאין התקנה קודמת בכלל (currentState == null) — אז "צריך
  /// עדכון" פשוט אומר "צריך התקנה ראשונית". false כשאין מראה: בלי גרסה
  /// זמינה בדיסק אין שום דבר להתקין.
  ///
  /// מספיק שהתג שונה מהמותקן: מעבר מהערוץ הלא-יציב חזרה ליציב הוא בדרך
  /// כלל *ירידה* בגרסה, וגם אותו צריך להציע כשהמשתמש ביקש אותו במפורש.
  bool get updateAvailable {
    final latest = latestRelease;
    if (latest == null) return false;
    final current = currentState;
    if (current == null) return true;
    return !sameVersion(current.installedTagName, latest.tagName);
  }

  /// האם המותקן והתג הם אותה גרסה בפועל.
  ///
  /// סיומת pre-release (`-pr-715-146`) מושמטת **רק כשהיא קיימת בצד אחד
  /// בלבד** — הצד שבלעדיה נקרא מתוך ההתקנה עצמה, ושם היא לעולם לא מופיעה.
  /// השמטה דו-צדדית הייתה משתקת את המעבר בין הערוצים: `1.0.0-beta` מותקן
  /// מול `1.0.0` יציב היה נראה "מעודכן" ולא ניתן היה לחזור ליציב.
  static bool sameVersion(String installedVersion, String tagName) {
    final installed = normalizeVersion(installedVersion);
    final tag = normalizeVersion(tagName);
    if (installed == tag) return true;

    final installedBase = _baseVersion(installed);
    final tagBase = _baseVersion(tag);
    if (installedBase != tagBase) return false;
    // בסיס זהה נחשב לאותה גרסה רק כשבדיוק אחד מהם נושא סיומת.
    return (installedBase == installed) != (tagBase == tag);
  }

  /// החלק שלפני סיומת ה-pre-release.
  static String _baseVersion(String version) {
    final separator = version.indexOf('-');
    return separator >= 0 ? version.substring(0, separator) : version;
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
