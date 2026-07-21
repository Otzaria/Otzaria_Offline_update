import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/delta_manifest.dart';
import '../models/library_release.dart';

/// לקוח לקריאת ה-releases וה-assets של ספריית הספרים מ-GitHub.
///
/// משתמש ב-`GET /releases` (ולא ב-`/releases/latest`), כי ה-latest אינו
/// מספיק כאשר הספרייה מפורסמת כ-prerelease.
class GithubLibraryReleaseClient {
  final String owner;
  final String repository;
  final http.Client _httpClient;
  final bool _ownsClient;
  final Duration timeout;

  GithubLibraryReleaseClient({
    this.owner = 'Otzaria',
    this.repository = 'SeforimLibrary',
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static const int _perPage = 100;
  static const int _maxPages = 20; // backstop: עד 2000 releases

  /// שולף את כל ה-releases של המאגר עם pagination, כדי שמשתמשים בגרסאות
  /// ישנות לא יאבדו chains כשמספר ה-releases עולה על עמוד אחד. זורק
  /// [Exception] בכשל רשת/HTTP.
  Future<List<LibraryRelease>> fetchReleases() async {
    final all = <LibraryRelease>[];
    for (var page = 1; page <= _maxPages; page++) {
      final url = Uri.parse(
        'https://api.github.com/repos/$owner/$repository/releases'
        '?per_page=$_perPage&page=$page',
      );
      final response =
          await _httpClient.get(url, headers: _apiHeaders).timeout(timeout);
      if (response.statusCode != 200) {
        throw Exception(
          'שגיאה בקבלת רשימת ה-releases: ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw const FormatException('תשובת ה-releases מ-GitHub אינה רשימה');
      }
      all.addAll(decoded
          .whereType<Map<String, dynamic>>()
          .map(LibraryRelease.fromJson));
      if (decoded.length < _perPage) break; // העמוד האחרון
    }
    return all;
  }

  /// מוריד ומפענח manifest דלתאי מכתובת [url]. זורק בכשל רשת או parse.
  Future<DeltaManifest> fetchManifest(String url) async {
    final response = await _httpClient.get(
      Uri.parse(url),
      headers: const {'Accept': 'application/json'},
    ).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('שגיאה בהורדת manifest ($url): ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('manifest אינו אובייקט JSON תקין: $url');
    }
    return DeltaManifest.fromJson(decoded);
  }

  /// סוגר את לקוח ה-HTTP אם הוא נוצר פנימית.
  void dispose() {
    if (_ownsClient) _httpClient.close();
  }
}
