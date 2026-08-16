import 'package:equatable/equatable.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'otzaria_release_channel.dart';

/// הגרסאות שנמצאו ברשת, לפי ערוץ — ראו [OtzariaChannelPair].
typedef OtzariaChannelReleases = OtzariaChannelPair<OtzariaRelease>;

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
          AppL10n.strings.appDomain.unsupportedPlatform(operatingSystem),
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

/// חבילת ה-FULL של release — אותו מתקין, אבל עם **הספרייה בתוכו**
/// (`otzaria-<ver>-windows-full.exe`, ~2GB). קיימת רק כשה-release פרסם
/// אותה, ולכן היא שדה אופציונלי ולא חלק מ-[OtzariaRelease] הרגיל.
///
/// **למי היא נועדה:** מחשב שאין בו אוצריא בכלל. הוא מקבל בצעד אחד תוכנה
/// וספרייה, במקום התקנה ואז פריסת מסד. למחשב שכבר יש בו אוצריא היא סתם
/// 2GB — ולכן הלאנצ'ר אינו מציע אותה שם.
class OtzariaFullPackage extends Equatable {
  const OtzariaFullPackage({
    required this.assetName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.installerKind,
  });

  final String assetName;
  final String downloadUrl;
  final int sizeBytes;
  final OtzariaInstallerKind installerKind;

  Map<String, dynamic> toJson() => {
        'assetName': assetName,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'installerKind': installerKind.name,
      };

  /// `null` על רשומה חסרה או פגומה — חבילת FULL אינה חובה, וקובץ מטא־דאטה
  /// שנכתב בגרסה קודמת של הלאנצ'ר פשוט אינו מכיל אותה.
  static OtzariaFullPackage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = OtzariaInstallerKind.values
        .where((k) => k.name == json['installerKind'])
        .firstOrNull;
    if (json['assetName'] is! String ||
        json['sizeBytes'] is! int ||
        kind == null) {
      return null;
    }
    return OtzariaFullPackage(
      assetName: json['assetName'] as String,
      downloadUrl: (json['downloadUrl'] as String?) ?? '',
      sizeBytes: json['sizeBytes'] as int,
      installerKind: kind,
    );
  }

  @override
  List<Object?> get props => [assetName, downloadUrl, sizeBytes, installerKind];
}

/// Release אחד מתוך github.com/Otzaria/otzaria/releases, מצומצם לשדות
/// שרלוונטיים להתקנה: תג הגרסה וקובץ ההתקנה לפלטפורמה הנוכחית.
///
/// **ערוצים:** release רגיל = יציב, pre-release = לא יציב. ההורדה מביאה את
/// שניהם (ראו `OtzariaReleaseClient.fetchChannelReleases`), והמשתמש בוחר
/// איזה מהם להתקין — אבל רק כשה-pre-release חדש מהיציב; אחרת אין בחירה
/// אמיתית ומורידים את היציב בלבד.
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
    this.fullPackage,
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

  /// חבילת ה-FULL של אותו release, כשקיימת — ראו [OtzariaFullPackage].
  /// היא **אינה** יורדת אלא אם המשתמש ביקש זאת במפורש בהגדרות.
  final OtzariaFullPackage? fullPackage;

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
        fullPackage: fullPackage,
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
        'fullPackage': fullPackage?.toJson(),
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
      throw FormatException(AppL10n.strings.appDomain.corruptReleaseMetadata);
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
      fullPackage: OtzariaFullPackage.fromJson(json['fullPackage']),
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
        fullPackage,
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
  String toString() => AppL10n.strings.appDomain.noAssetForPlatform(
        tagName,
        platform.label,
        expectedSuffixes,
      );
}
