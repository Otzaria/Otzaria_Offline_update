import 'package:equatable/equatable.dart';

/// Release אחד מתוך github.com/Otzaria/otzaria/releases, מצומצם לשדות
/// שרלוונטיים להתקנה: תג הגרסה וקובץ ה-installer לווינדוס.
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
    required this.windowsInstallerAssetName,
    required this.windowsInstallerDownloadUrl,
    required this.windowsInstallerSizeBytes,
  });

  final String tagName;
  final String name;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;

  /// שם הקובץ, לדוגמה otzaria-0.9.53-windows.exe.
  final String windowsInstallerAssetName;
  final String windowsInstallerDownloadUrl;
  final int windowsInstallerSizeBytes;

  @override
  List<Object?> get props => [
        tagName,
        name,
        isPrerelease,
        isDraft,
        publishedAt,
        windowsInstallerAssetName,
        windowsInstallerDownloadUrl,
        windowsInstallerSizeBytes,
      ];
}

/// נזרקת כשל-release אין אסט מתאים לווינדוס (למשל release עם אנדרואיד/
/// macOS/לינוקס בלבד, או אסט עם שם לא צפוי).
class NoWindowsAssetException implements Exception {
  const NoWindowsAssetException(this.tagName);
  final String tagName;

  @override
  String toString() =>
      'ל-release "$tagName" אין קובץ installer מתאים לווינדוס (מצפים לשם '
      'שמסתיים ב-"windows.exe").';
}
