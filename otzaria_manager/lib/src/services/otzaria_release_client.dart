import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/otzaria_release.dart';
import '../otzaria_user_error.dart';
import 'otzaria_asset_selector.dart';
import 'windows_arch.dart';

/// שולף מידע על releases של github.com/Otzaria/otzaria (אפליקציית אוצריא
/// עצמה — לא SeforimLibrary/ה-DB).
class OtzariaReleaseClient {
  OtzariaReleaseClient({
    http.Client? httpClient,
    OtzariaTargetPlatform? platform,
    this.timeout = const Duration(seconds: 20),
  })  : _httpClient = httpClient ?? http.Client(),
        _platform =
            platform ?? OtzariaTargetPlatform.detect(Platform.operatingSystem);

  /// זמן קצוב לבקשה. חובה שיהיה כזה: בלעדיו, מחשב שמחובר לרשת אך בלי מסלול
  /// לאינטרנט (למשל captive portal) היה תולה את בדיקת העדכונים ללא הגבלה.
  /// ניתן לשינוי בזמן ריצה מהגדרות הלאנצ'ר.
  Duration timeout;

  // ⚠️ Otzaria/otzaria (ה-fork, לא Sivan22/otzaria המקורי) — זה הריפו
  // שממנו בפועל מפיצים releases ושהמשתמשים מורידים ממנו. תוקן אחרי
  // דיווח משתמש: הקוד דיווח 0.9.93 כשגרסה 0.9.95 כבר הייתה קיימת
  // ב-Otzaria/otzaria.
  static const _owner = 'Otzaria';
  static const _repo = 'otzaria';
  static const _apiBase = 'https://api.github.com';

  final http.Client _httpClient;

  /// פלטפורמת היעד שעבורה בוחרים אסט. ברירת המחדל היא הפלטפורמה שהלאנצ'ר
  /// רץ עליה; ניתן לדרוס אותה בבדיקות.
  final OtzariaTargetPlatform _platform;

  static const _assetSelector = OtzariaAssetSelector();

  /// כמה releases להביא כדי שיהיה מה לסנן. חיפוש ה-release היציב צריך
  /// לדלג על שרשרת ארוכה של preview builds לפני שהוא מגיע אליו.
  static const int _pageSize = 50;

  /// מחזיר את **שתי** הגרסאות שהלאנצ'ר מוריד: ה-release היציב האחרון
  /// (`prerelease=false`), ובנוסף ה-pre-release האחרון — אך ורק כשהוא חדש
  /// מהיציב. GitHub מחזיר את /releases מהחדש לישן, ולכן "חדש יותר" = מופיע
  /// לפניו ברשימה. draft נפסל תמיד.
  ///
  /// release שאין לו אסט התקנה לפלטפורמה הנוכחית מדולג במקום להפיל את כל
  /// הבדיקה — הערוץ ממשיך לגרסה הוותיקה יותר. אם אף גרסה לא ניתנת להתקנה,
  /// נזרקת [NoInstallerAssetException] של החדשה ביותר שנפסלה.
  Future<OtzariaChannelReleases> fetchChannelReleases() async {
    final candidates = await _fetchReleasesJson();

    OtzariaRelease? stable;
    OtzariaRelease? prerelease;
    NoInstallerAssetException? firstRejection;

    for (final json in candidates) {
      final isPrerelease = json['prerelease'] as bool? ?? false;
      // כבר יש pre-release חדש יותר; ותיקים ממנו אינם מעניינים.
      if (isPrerelease && prerelease != null) continue;

      final OtzariaRelease release;
      try {
        release = _withArm64Variant(_parseRelease(json), json);
      } on NoInstallerAssetException catch (e) {
        firstRejection ??= e;
        continue;
      }

      if (!isPrerelease) {
        // הגענו ליציב: כל מה שמתחתיו ברשימה ותיק ממנו.
        stable = release;
        break;
      }
      prerelease = release;
    }

    if (stable == null && prerelease == null && firstRejection != null) {
      throw firstRejection;
    }
    return OtzariaChannelReleases(stable: stable, prerelease: prerelease);
  }

  Future<List<Map<String, dynamic>>> _fetchReleasesJson() async {
    final uri = Uri.parse(
      '$_apiBase/repos/$_owner/$_repo/releases?per_page=$_pageSize',
    );
    final decoded = await githubGetJson(
      _httpClient,
      uri,
      timeout: timeout,
      statusError: (status) => isFilterBlockStatus(status)
          ? NetworkBlockedException(uri: uri, statusCode: status)
          : GithubApiException(
              AppL10n.strings.appDomain.githubStatus(status, '$uri'),
            ),
    ) as List<dynamic>;
    if (decoded.isEmpty) {
      throw OtzariaUserError(
        AppL10n.strings.appDomain.noReleasesAtAll('$_owner/$_repo'),
      );
    }

    return decoded
        .cast<Map<String, dynamic>>()
        .where((r) => !(r['draft'] as bool? ?? false))
        .toList(growable: false);
  }

  OtzariaRelease _withArm64Variant(
    OtzariaRelease release,
    Map<String, dynamic> json,
  ) {
    if (_platform != OtzariaTargetPlatform.windows) return release;
    try {
      return release.withArm64Variant(
        _parseRelease(json, arch: OtzariaArch.arm64),
      );
    } on NoInstallerAssetException {
      return release;
    }
  }

  OtzariaRelease _parseRelease(
    Map<String, dynamic> json, {
    OtzariaArch arch = OtzariaArch.x64,
  }) {
    final tagName = json['tag_name'] as String;
    final assets = [
      for (final raw in json['assets'] as List<dynamic>)
        if (GithubReleaseAsset.tryParse(raw) case final asset?
            when asset.isReady)
          asset,
    ];

    final selected = _assetSelector.select(
      platform: _platform,
      assets: assets,
      nameOf: (asset) => asset.name,
      arch: arch,
    );

    if (selected == null) {
      throw NoInstallerAssetException(
        tagName: tagName,
        platform: _platform,
        expectedSuffixes: OtzariaAssetSelector.expectedSuffixesFor(
          _platform,
          arch: arch,
        ),
      );
    }

    final (asset, installerKind) = selected;

    return OtzariaRelease(
      tagName: tagName,
      name: (json['name'] as String?) ?? tagName,
      isPrerelease: json['prerelease'] as bool? ?? false,
      isDraft: json['draft'] as bool? ?? false,
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.tryParse(json['published_at'] as String),
      installerKind: installerKind,
      installerAssetName: asset.name,
      installerDownloadUrl: asset.downloadUrl,
      installerSizeBytes: asset.size,
      installerSha256: OtzariaRelease.normalizedSha256(asset.sha256),
      releaseNotes: json['body'] as String?,
      installerArch: arch,
    );
  }

  void dispose() => _httpClient.close();
}

/// שגיאת תגובה לא תקינה מ-GitHub API. שם ייעודי (לא HttpException) כדי לא
/// להתנגש עם dart:io.HttpException אם הצרכן מייבא גם את dart:io ישירות.
class GithubApiException implements Exception {
  const GithubApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
