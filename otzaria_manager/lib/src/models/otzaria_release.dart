import 'package:equatable/equatable.dart';

/// הפלטפורמה שעבורה בוחרים אסט להתקנה. **לא** נגזר ישירות מ-`Platform`
/// בכל מקום שצריך אותו, כדי שבחירת האסט תישאר פונקציה טהורה שאפשר לבדוק
/// עבור שתי הפלטפורמות מאותה מכונה.
enum OtzariaTargetPlatform {
  windows,
  macos;

  /// הפלטפורמה שהלאנצ'ר רץ עליה בפועל. זורק [UnsupportedError] בפלטפורמה
  /// שאין לה מסלול התקנה (לינוקס/מובייל) — הלאנצ'ר עצמו נבנה רק ל-Windows
  /// ול-macOS.
  static OtzariaTargetPlatform detect(String operatingSystem) {
    return switch (operatingSystem) {
      'windows' => OtzariaTargetPlatform.windows,
      'macos' => OtzariaTargetPlatform.macos,
      _ => throw UnsupportedError(
          "הלאנצ'ר תומך בהתקנת אוצריא ב-Windows וב-macOS בלבד "
          '(זוהה: $operatingSystem).',
        ),
    };
  }

  /// תווית לשימוש בהודעות שגיאה למשתמש.
  String get label => switch (this) {
        OtzariaTargetPlatform.windows => 'Windows',
        OtzariaTargetPlatform.macos => 'macOS',
      };
}

/// סוג האסט שממנו מתקינים — קובע איזה מסלול התקנה [OtzariaInstaller] מריץ.
enum OtzariaInstallerKind {
  /// installer של Inno Setup לווינדוס (`otzaria-<ver>-windows.exe`) — מורץ
  /// בשקט עם דגלי `/VERYSILENT`.
  windowsSetupExe,

  /// ארכיון zip שבתוכו bundle של `.app` ל-macOS (`otzaria-macos.zip`) —
  /// מחולץ עם `ditto` לתיקיית ההתקנה.
  macAppZip,

  /// דמות דיסק ל-macOS (`otzaria-macos.dmg`) — מורכבת עם `hdiutil`,
  /// ה-`.app` מועתק ממנה, והדמות מנותקת. מסלול גיבוי למקרה שאין zip.
  macAppDmg;

  bool get isMac =>
      this == OtzariaInstallerKind.macAppZip ||
      this == OtzariaInstallerKind.macAppDmg;
}

/// Release אחד מתוך github.com/Otzaria/otzaria/releases, מצומצם לשדות
/// שרלוונטיים להתקנה: תג הגרסה וקובץ ההתקנה לפלטפורמה הנוכחית.
///
/// שים לב: הריפו הזה כרגע (יולי 2026) כמעט ואינו מפרסם releases "יציבים"
/// (prerelease=false) — רוב הפעילות היא PR-preview builds עם
/// prerelease=true. לפי החלטת המשתמש, [OtzariaReleaseClient] מחזיר את ה-
/// release הראשון ברשימה (העדכני ביותר, כרונולוגית) בלי לסנן prerelease,
/// כדי לא להיתקע על גרסה ישנה. isPrerelease נשמר כאן למידע/UI בלבד.
class OtzariaRelease extends Equatable {
  const OtzariaRelease({
    required this.tagName,
    required this.name,
    required this.isPrerelease,
    required this.isDraft,
    required this.publishedAt,
    required this.installerKind,
    required this.installerAssetName,
    required this.installerDownloadUrl,
    required this.installerSizeBytes,
  });

  final String tagName;
  final String name;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;

  /// איך להתקין את [installerAssetName] — ראו [OtzariaInstallerKind].
  final OtzariaInstallerKind installerKind;

  /// שם הקובץ, לדוגמה `otzaria-0.9.96-windows.exe` בווינדוס או
  /// `otzaria-macos.zip` ב-macOS.
  final String installerAssetName;
  final String installerDownloadUrl;
  final int installerSizeBytes;

  @override
  List<Object?> get props => [
        tagName,
        name,
        isPrerelease,
        isDraft,
        publishedAt,
        installerKind,
        installerAssetName,
        installerDownloadUrl,
        installerSizeBytes,
      ];
}

/// נזרקת כשל-release אין אסט התקנה מתאים לפלטפורמה הנוכחית (למשל release
/// עם אנדרואיד/לינוקס בלבד, או אסט עם שם לא צפוי).
class NoInstallerAssetException implements Exception {
  const NoInstallerAssetException({
    required this.tagName,
    required this.platform,
    required this.expectedSuffixes,
  });

  final String tagName;
  final OtzariaTargetPlatform platform;

  /// הסיומות שחיפשנו — נכנס להודעה כדי שיהיה ברור מה בדיוק לא נמצא.
  final List<String> expectedSuffixes;

  @override
  String toString() =>
      'ל-release "$tagName" אין קובץ התקנה מתאים ל-${platform.label} '
      '(מצפים לשם שמסתיים ב-${expectedSuffixes.map((s) => '"$s"').join(' או ')}).';
}
