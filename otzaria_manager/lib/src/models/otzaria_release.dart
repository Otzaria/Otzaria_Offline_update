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
/// **ערוצים:** release רגיל = יציב, pre-release = לא יציב. שים לב שהריפו
/// הזה כמעט ואינו מפרסם releases יציבים — רוב הפעילות היא preview builds
/// עם `prerelease=true`. לכן ערוץ "יציב בלבד" עלול לא למצוא כלום, ובמקרה
/// כזה [OtzariaReleaseClient] אומר זאת במפורש ולא בוחר pre-release בשקט.
///
/// [toJson]/[fromJson] משמשים את `OtzariaAppMirror` כדי לשמור את המטא־דאטה
/// לצד קובץ ההתקנה — כך שבדיקת גרסה עובדת גם בלי רשת בכלל.
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
    this.releaseNotes,
  });

  final String tagName;
  final String name;
  final bool isPrerelease;
  final bool isDraft;
  final DateTime? publishedAt;

  /// תיאור ה-release כפי שנכתב ב-GitHub ("מה התחדש") — טקסט חופשי
  /// (Markdown גולמי, לא מרונדר), או `null` אם ה-release לא כלל תיאור.
  /// נשמר לצד שאר המטא-דאטה במראה המקומית כדי שיהיה קריא גם בלי רשת.
  final String? releaseNotes;

  /// איך להתקין את [installerAssetName] — ראו [OtzariaInstallerKind].
  final OtzariaInstallerKind installerKind;

  /// שם הקובץ, לדוגמה `otzaria-0.9.96-windows.exe` בווינדוס או
  /// `otzaria-macos.zip` ב-macOS.
  final String installerAssetName;
  final String installerDownloadUrl;
  final int installerSizeBytes;

  /// עותק עם [releaseNotes] מוחלף — משמש להעדיף פסקה מיומן השינויים
  /// המרוכז (ראו `OtzariaChangelogClient`) על פני תיאור ה-release הגולמי.
  OtzariaRelease copyWithReleaseNotes(String? releaseNotes) => OtzariaRelease(
        tagName: tagName,
        name: name,
        isPrerelease: isPrerelease,
        isDraft: isDraft,
        publishedAt: publishedAt,
        installerKind: installerKind,
        installerAssetName: installerAssetName,
        installerDownloadUrl: installerDownloadUrl,
        installerSizeBytes: installerSizeBytes,
        releaseNotes: releaseNotes,
      );

  Map<String, dynamic> toJson() => {
        'tagName': tagName,
        'name': name,
        'isPrerelease': isPrerelease,
        'isDraft': isDraft,
        'publishedAt': publishedAt?.toIso8601String(),
        'installerKind': installerKind.name,
        'installerAssetName': installerAssetName,
        'installerDownloadUrl': installerDownloadUrl,
        'installerSizeBytes': installerSizeBytes,
        'releaseNotes': releaseNotes,
      };

  /// זורק [FormatException] על JSON חסר/פגום — הקורא מתייחס לזה כ"אין מראה
  /// תקינה" ומבקש הורדה מחדש.
  factory OtzariaRelease.fromJson(Map<String, dynamic> json) {
    final kindName = json['installerKind'];
    final kind = OtzariaInstallerKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (json['tagName'] is! String ||
        json['installerAssetName'] is! String ||
        json['installerSizeBytes'] is! int ||
        kind == null) {
      throw const FormatException('מטא־דאטה פגומה של גרסת אוצריא');
    }

    final publishedAt = json['publishedAt'];
    return OtzariaRelease(
      tagName: json['tagName'] as String,
      name: (json['name'] as String?) ?? json['tagName'] as String,
      isPrerelease: json['isPrerelease'] as bool? ?? false,
      isDraft: json['isDraft'] as bool? ?? false,
      publishedAt:
          publishedAt is String ? DateTime.tryParse(publishedAt) : null,
      installerKind: kind,
      installerAssetName: json['installerAssetName'] as String,
      installerDownloadUrl: (json['installerDownloadUrl'] as String?) ?? '',
      installerSizeBytes: json['installerSizeBytes'] as int,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }

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
        releaseNotes,
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
