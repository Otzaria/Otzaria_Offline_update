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

  /// כמה releases להביא כדי שיהיה מה לסנן. ערוץ "יציב בלבד" צריך לדלג על
  /// שרשרת ארוכה של preview builds לפני שהוא מגיע ל-release רגיל.
  static const int _pageSize = 50;

  /// מחזיר את ה-release העדכני ביותר כרונולוגית (GitHub ממיין את
  /// /releases כך כברירת מחדל) **בערוץ המבוקש**: `allowPrerelease: false`
  /// לוקח רק release רגיל, `true` לוקח גם pre-release. draft נפסל תמיד.
  ///
  /// זורק [NoStableReleaseException] אם בערוץ היציב אין כלום — במקום ליפול
  /// בשקט ל-pre-release, שזו בדיוק ההתנהגות שהמשתמש ביקש להפריד.
  /// זורק [NoInstallerAssetException] אם ל-release שנמצא אין אסט התקנה
  /// מתאים לפלטפורמה הנוכחית.
  Future<OtzariaRelease> fetchLatestRelease({
    bool allowPrerelease = true,
  }) async {
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

    final eligible = decoded
        .cast<Map<String, dynamic>>()
        .where((r) => !(r['draft'] as bool? ?? false))
        .where((r) => allowPrerelease || !(r['prerelease'] as bool? ?? false))
        .toList(growable: false);

    if (eligible.isEmpty) {
      throw NoStableReleaseException(checked: decoded.length);
    }

    return _parseRelease(eligible.first);
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

/// נזרקת כשערוץ "יציב בלבד" לא מצא אף release רגיל. הריפו של אוצריא מפרסם
/// כמעט רק pre-release, ולכן זה מצב מציאותי — והמשתמש צריך לדעת שהפתרון
/// הוא להחליף ערוץ, לא שמשהו נשבר.
class NoStableReleaseException implements Exception {
  const NoStableReleaseException({required this.checked});

  final int checked;

  @override
  String toString() =>
      'לא נמצאה גרסה יציבה של אוצריא ב-$checked ה-releases האחרונים — '
      'כל הפרסומים שם מסומנים כ-pre-release. יש לעבור בהגדרות לערוץ '
      '"כולל pre-release" כדי לעדכן.';
}

/// שגיאת תגובה לא תקינה מ-GitHub API. שם ייעודי (לא HttpException) כדי לא
/// להתנגש עם dart:io.HttpException אם הצרכן מייבא גם את dart:io ישירות.
class GithubApiException implements Exception {
  const GithubApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
