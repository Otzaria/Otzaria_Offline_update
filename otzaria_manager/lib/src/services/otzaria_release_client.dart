import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import '../models/otzaria_release.dart';
import 'otzaria_asset_selector.dart';

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
        release = _parseRelease(json);
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

  /// ה-releases הגולמיים, מהחדש לישן, בלי draft.
  Future<List<Map<String, dynamic>>> _fetchReleasesJson() async {
    final uri = Uri.parse(
      '$_apiBase/repos/$_owner/$_repo/releases?per_page=$_pageSize',
    );
    final response = await _httpClient.get(
      uri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        // ⚠️ חובה: GitHub API מחזיר 403 "forbidden by administrative
        // rules" לכל בקשה בלי User-Agent — ללא קשר ל-rate limit.
        'User-Agent': 'otzaria-launcher',
      },
    ).timeout(timeout);

    if (response.statusCode != 200) {
      throw GithubApiException(
        'GitHub API החזיר סטטוס ${response.statusCode} עבור $uri',
      );
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    if (decoded.isEmpty) {
      throw StateError('לא נמצאו releases בכלל ב-$_owner/$_repo.');
    }

    return decoded
        .cast<Map<String, dynamic>>()
        .where((r) => !(r['draft'] as bool? ?? false))
        .toList(growable: false);
  }

  OtzariaRelease _parseRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String;
    final assets =
        (json['assets'] as List<dynamic>).cast<Map<String, dynamic>>();

    // בחירת האסט לפי פלטפורמת היעד — ראו [OtzariaAssetSelector] להסבר על
    // כללי ההתאמה (ולמה חבילות ה-FULL של 2GB נפסלות מעצמן).
    final selected = _assetSelector.select(
      platform: _platform,
      assets: assets,
      nameOf: (asset) => asset['name'] as String,
    );

    if (selected == null) {
      throw NoInstallerAssetException(
        tagName: tagName,
        platform: _platform,
        expectedSuffixes: OtzariaAssetSelector.expectedSuffixesFor(_platform),
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
      installerAssetName: asset['name'] as String,
      installerDownloadUrl: asset['browser_download_url'] as String,
      installerSizeBytes: asset['size'] as int,
      releaseNotes: json['body'] as String?,
    );
  }

  void close() => _httpClient.close();
}

/// שגיאת תגובה לא תקינה מ-GitHub API. שם ייעודי (לא HttpException) כדי לא
/// להתנגש עם dart:io.HttpException אם הצרכן מייבא גם את dart:io ישירות.
class GithubApiException implements Exception {
  const GithubApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
