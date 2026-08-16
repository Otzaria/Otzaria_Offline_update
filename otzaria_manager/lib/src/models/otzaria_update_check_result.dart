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
    this.mirroredFullPackage,
    this.fullPackageKnown = false,
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

  /// חבילת ה-FULL של הערוץ היציב, כשקובץ ההתקנה שלה יושב על הכונן. `null`
  /// כשלא הורדה (וזו ברירת המחדל: היא יורדת רק אם ביקשו זאת בהגדרות).
  final OtzariaFullPackage? mirroredFullPackage;

  /// האם ידוע בכלל אם ל-release היציב שבמראה יש חבילת FULL — ראו
  /// [MirroredOtzariaRelease.fullPackageKnown]. `false` גם כשאין מראה.
  final bool fullPackageKnown;

  /// ל-release היציב שבמראה **יש** חבילת FULL להורדה.
  bool get fullPackageOffered => stableRelease?.fullPackage != null;

  /// **אין במחשב אוצריא בכלל, ועל הכונן יש חבילת FULL.** רק אז הלאנצ'ר
  /// ממליץ עליה: היא מביאה תוכנה **וספרייה** בצעד אחד, וזה בדיוק מה שחסר
  /// למחשב ריק. במחשב שכבר יש בו אוצריא היא 2GB מיותרים, ולכן לא מוצעת שם.
  bool get fullPackageRecommended =>
      currentState == null && mirroredFullPackage != null;

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
  /// תג שונה מהמותקן מספיק — למעט [installedIsNewer]: מעבר מהערוץ הלא-יציב
  /// חזרה ליציב הוא בדרך כלל *ירידה* בגרסה, וגם אותו צריך להציע כשהמשתמש
  /// ביקש אותו במפורש, אבל נסיגה שהמשתמש לא ביקש אינה "עדכון".
  bool get updateAvailable {
    final latest = latestRelease;
    if (latest == null) return false;
    final current = currentState;
    if (current == null) return true;
    if (sameVersion(current.installedTagName, latest.tagName)) return false;
    return !installedIsNewer;
  }

  /// המותקן **חדש** ממה שיושב במראה — אין מה להתקין, והצעת התקנה הייתה
  /// נסיגת גרסה.
  ///
  /// דיווח משתמש: אוצריא 0.9.97+90970 מותקנת מול 0.9.96+736 במראה, והלאנצ'ר
  /// הכריז "מוכן להתקנה" והציע להחזיר אותו ל-0.9.96. הבדיקה השוותה תגים
  /// בשוויון בלבד, בלי סדר.
  ///
  /// מעבר ערוץ יזום אינו נסיגה כזאת: כשהמותקן הוא בדיוק התג של הערוץ השני
  /// שבמראה, המשתמש בחר את הערוץ הנבחר במפורש — וזה כן מוצע.
  bool get installedIsNewer {
    final latest = latestRelease;
    final current = currentState;
    if (latest == null || current == null) return false;

    final installed = current.installedTagName;
    if (sameVersion(installed, latest.tagName)) return false;

    final other = selectedChannel == OtzariaReleaseChannel.stable
        ? prereleaseRelease
        : stableRelease;
    if (other != null && sameVersion(installed, other.tagName)) return false;

    return compareVersions(installed, latest.tagName) > 0;
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

  /// סדר בין שתי גרסאות: שלילי אם [a] ותיקה מ-[b], חיובי אם חדשה ממנה,
  /// ואפס כשהן שקולות או שאין הכרעה.
  ///
  /// חלקי הבסיס מושווים כמספרים ולא כטקסט (חלק חסר = 0) — `0.9.97` חדשה
  /// מ-`0.9.96` וגם מ-`0.9.9`. סיומת ה-pre-release מכריעה רק בתיקו, והצד
  /// שנושא אותה ותיק מהצד שבלעדיה (`1.0.0-beta` < `1.0.0`). שתי סיומות
  /// שונות על אותו בסיס אינן ברות השוואה ומחזירות אפס.
  static int compareVersions(String a, String b) {
    final left = normalizeVersion(a);
    final right = normalizeVersion(b);
    final leftBase = _baseVersion(left);
    final rightBase = _baseVersion(right);

    final leftParts = _numericParts(leftBase);
    final rightParts = _numericParts(rightBase);
    final count = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < count; i++) {
      final leftPart = i < leftParts.length ? leftParts[i] : 0;
      final rightPart = i < rightParts.length ? rightParts[i] : 0;
      if (leftPart != rightPart) return leftPart < rightPart ? -1 : 1;
    }

    final leftHasSuffix = left != leftBase;
    final rightHasSuffix = right != rightBase;
    if (leftHasSuffix == rightHasSuffix) return 0;
    return leftHasSuffix ? -1 : 1;
  }

  /// חלקי הבסיס כמספרים; חלק שאינו מספר נחשב 0 (במקום להפיל את ההשוואה).
  static List<int> _numericParts(String base) => base
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: false);

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
