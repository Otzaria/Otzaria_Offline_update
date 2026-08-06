import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// שם ותוסף שהוסקו לנכס שירד.
class DownloadedAsset {
  const DownloadedAsset({
    required this.path,
    required this.ext,
    required this.size,
    this.originalName,
  });

  final String path;
  final String ext;
  final int size;
  final String? originalName;
}

/// לקוח ה-API הציבורי של חנות התוספים באתר אוצריא.
class PluginStoreClient {
  PluginStoreClient({String baseUrl = defaultBaseUrl, http.Client? client})
      : baseUrl = _trimTrailingSlash(baseUrl),
        _client = client ?? http.Client();

  static const String defaultBaseUrl = 'https://otzaria.org';

  final String baseUrl;
  final http.Client _client;

  /// שולף את רשימת התוספים המאושרים. זורק [PluginStoreException] על כל כשל
  /// — זה הכשל היחיד שכן צריך לעצור סנכרון (בלי רשימה אין מה לסנכרן).
  Future<List<Map<String, dynamic>>> fetchCatalog() async {
    final uri = Uri.parse('$baseUrl/api/plugins');
    late final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (e) {
      throw PluginStoreException('לא ניתן להתחבר לאתר אוצריא: $e');
    }
    if (response.statusCode != 200) {
      throw PluginStoreException(
        'לא ניתן לטעון את רשימת התוספים (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const PluginStoreException('תשובת האתר אינה רשימת תוספים תקינה');
    }
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// מוריד נכס יחיד אל [destPathNoExt] + הסיומת שהוסקה. סדר ההסקה זהה
  /// למקור: `Content-Disposition`, אחר כך `Content-Type`, ולבסוף
  /// [preferredExt].
  Future<DownloadedAsset> downloadAsset(
    String url,
    String destPathNoExt, {
    String? preferredExt,
  }) async {
    final response = await _client.get(Uri.parse(absolute(url)));
    if (response.statusCode != 200) {
      throw PluginStoreException('HTTP ${response.statusCode} עבור $url');
    }

    final fromDisposition =
        parseContentDisposition(response.headers['content-disposition']);
    final contentType =
        (response.headers['content-type'] ?? '').split(';').first.trim();

    var ext = preferredExt ?? '';
    String? originalName;
    if (fromDisposition != null) {
      if (fromDisposition.ext.isNotEmpty) ext = fromDisposition.ext;
      originalName = fromDisposition.name;
    } else if (extByContentType.containsKey(contentType)) {
      ext = extByContentType[contentType]!;
    }

    final destPath = destPathNoExt + ext;
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes);

    return DownloadedAsset(
      path: destPath,
      ext: ext,
      size: response.bodyBytes.length,
      originalName: originalName,
    );
  }

  String absolute(String url) =>
      (url.startsWith('http://') || url.startsWith('https://'))
          ? url
          : '$baseUrl$url';

  void dispose() => _client.close();

  static const Map<String, String> extByContentType = {
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/jpg': '.jpg',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'image/svg+xml': '.svg',
  };

  /// מפרק כותרת `Content-Disposition` לשם קובץ וסיומת. תומך גם בצורת
  /// `filename*=UTF-8''` (שמות עבריים מגיעים כך) וגם ב-`filename="..."`.
  static ContentDispositionName? parseContentDisposition(String? header) {
    if (header == null || header.isEmpty) return null;

    final utf8Match = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(header);
    if (utf8Match != null) {
      try {
        final name = Uri.decodeComponent(utf8Match.group(1)!);
        return ContentDispositionName(name, p.extension(name));
      } catch (_) {
        // כתובת מקודדת פגומה — ננסה את הצורה הפשוטה למטה.
      }
    }

    final plainMatch = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(header);
    if (plainMatch != null) {
      final name = plainMatch.group(1)!;
      return ContentDispositionName(name, p.extension(name));
    }
    return null;
  }

  static String _trimTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

class ContentDispositionName {
  const ContentDispositionName(this.name, this.ext);
  final String name;
  final String ext;
}

class PluginStoreException implements Exception {
  const PluginStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}
