import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/otzaria_release.dart';

/// שולף מידע על releases של github.com/Sivan22/otzaria (אפליקציית אוצריא
/// עצמה — לא SeforimLibrary/ה-DB).
class OtzariaReleaseClient {
  OtzariaReleaseClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const _owner = 'Sivan22';
  static const _repo = 'otzaria';
  static const _apiBase = 'https://api.github.com';

  final http.Client _httpClient;

  /// מחזיר את ה-release העדכני ביותר כרונולוגית (GitHub ממיין את
  /// /releases כך כברירת מחדל) — כולל prerelease, בכוונה. ראו הערה ב-
  /// [OtzariaRelease] לגבי הסיבה.
  ///
  /// זורק [NoWindowsAssetException] אם ל-release שנמצא אין אסט
  /// windows.exe מתאים.
  Future<OtzariaRelease> fetchLatestRelease() async {
    final uri = Uri.parse('$_apiBase/repos/$_owner/$_repo/releases?per_page=1');
    final response = await _httpClient.get(
      uri,
      headers: const {'Accept': 'application/vnd.github+json'},
    );

    if (response.statusCode != 200) {
      throw GithubApiException(
        'GitHub API החזיר סטטוס ${response.statusCode} עבור $uri',
      );
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    if (decoded.isEmpty) {
      throw StateError('לא נמצאו releases בכלל ב-$_owner/$_repo.');
    }

    return _parseRelease(decoded.first as Map<String, dynamic>);
  }

  OtzariaRelease _parseRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String;
    final assets = (json['assets'] as List<dynamic>).cast<Map<String, dynamic>>();

    // מוצאים את אסט ה-installer לווינדוס: בכל הדגימות שנבדקו השם מסתיים
    // תמיד ב-"windows.exe" (למשל otzaria-0.9.53-windows.exe). לא בוחרים
    // לפי שם קבוע מלא כי מספר הגרסה משובץ בתוך השם.
    Map<String, dynamic>? windowsAsset;
    for (final asset in assets) {
      final name = asset['name'] as String;
      if (name.toLowerCase().endsWith('windows.exe')) {
        windowsAsset = asset;
        break;
      }
    }

    if (windowsAsset == null) {
      throw NoWindowsAssetException(tagName);
    }

    return OtzariaRelease(
      tagName: tagName,
      name: (json['name'] as String?) ?? tagName,
      isPrerelease: json['prerelease'] as bool? ?? false,
      isDraft: json['draft'] as bool? ?? false,
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.tryParse(json['published_at'] as String),
      windowsInstallerAssetName: windowsAsset['name'] as String,
      windowsInstallerDownloadUrl: windowsAsset['browser_download_url'] as String,
      windowsInstallerSizeBytes: windowsAsset['size'] as int,
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
