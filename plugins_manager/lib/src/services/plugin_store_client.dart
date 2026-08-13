import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
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
  PluginStoreClient({
    String baseUrl = defaultBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  })  : baseUrl = _trimTrailingSlash(baseUrl),
        _client = client ?? http.Client();

  static const String defaultBaseUrl = 'https://otzaria.org';

  final String baseUrl;
  final http.Client _client;

  /// זמן קצוב לקבלת כותרות התשובה (ולקריאות ה-JSON הקטנות במלואן). בלעדיו
  /// סנכרון של עשרות נכסים היה יכול להיתקע לנצח על נכס בודד.
  Duration timeout;

  /// זמן קצוב ל**חוסר התקדמות** בגוף התשובה — מתאפס בכל מנת בייטים. קובץ
  /// תוסף שוקל עשרות MB, ודדליין יחיד על ההורדה כולה נכשל עליו בכל חיבור
  /// איטי גם כשהיא התקדמה יפה.
  Duration stallTimeout;

  /// שולף את רשימת התוספים המאושרים. זורק [PluginStoreException] על כל כשל
  /// — זה הכשל היחיד שכן צריך לעצור סנכרון (בלי רשימה אין מה לסנכרן).
  ///
  /// הרשימה מגיעה כשהיא כבר ממוינת: התוספים הנבחרים (`isPinned`) ראשונים
  /// בסדר האצירה של האתר, ואחריהם השאר מהחדש לישן. הסדר נשמר כמות שהוא.
  Future<List<Map<String, dynamic>>> fetchCatalog() async {
    final strings = AppL10n.strings.pluginsDomain;
    final decoded = await _getJson('/api/plugins', strings.whatPluginList);
    if (decoded is! List) {
      throw PluginStoreException(strings.responseNotPluginList);
    }
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// שולף את דף הבית האצור של החנות — טקסטים, תוספים נבחרים וסיכומי
  /// הקטגוריות, הכול בקריאה אחת.
  Future<Map<String, dynamic>> fetchStoreHome() async => _asMap(
        await _getJson(
          '/api/plugins/store-home',
          AppL10n.strings.pluginsDomain.whatStoreStructure,
        ),
      );

  /// שולף דף קטגוריה שלם — כל התוספים המשובצים בה, בסדר שנקבע באתר.
  /// בלי `limit` האתר מחזיר את כל הרשימה, וזה מה שנדרש למראה.
  Future<Map<String, dynamic>> fetchCategory(String slug) async => _asMap(
        await _getJson(
          '/api/plugins/categories/${Uri.encodeComponent(slug)}',
          AppL10n.strings.pluginsDomain.whatCategory(slug),
        ),
      );

  /// GET + פענוח JSON עם הודעות שגיאה למשתמש. [what] נכנס להודעה.
  Future<Object?> _getJson(String path, String what) async {
    final strings = AppL10n.strings.pluginsDomain;
    late final http.Response response;
    try {
      response = await _client.get(Uri.parse('$baseUrl$path')).timeout(timeout);
    } catch (e) {
      throw PluginStoreException(strings.siteUnreachable(describeError(e)));
    }
    if (response.statusCode != 200) {
      throw PluginStoreException(
        strings.loadFailed(what, response.statusCode),
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw PluginStoreException(strings.responseNotJson(what));
    }
  }

  static Map<String, dynamic> _asMap(Object? decoded) => decoded is Map
      ? Map<String, dynamic>.from(decoded)
      : throw PluginStoreException(
          AppL10n.strings.pluginsDomain.responseUnexpectedShape,
        );

  /// מוריד נכס יחיד אל [destPathNoExt] + הסיומת שהוסקה. סדר ההסקה זהה
  /// למקור: `Content-Disposition`, אחר כך `Content-Type`, ולבסוף
  /// [preferredExt].
  ///
  /// יורד בזרימה ולא לזיכרון: הזמן הקצוב חל על חוסר התקדמות ([stallTimeout])
  /// ולא על משך ההורדה, ותוסף של עשרות MB אינו יושב כולו ב-RAM.
  Future<DownloadedAsset> downloadAsset(
    String url,
    String destPathNoExt, {
    String? preferredExt,
  }) async {
    final response = await _client
        .send(http.Request('GET', Uri.parse(absolute(url))))
        .timeout(timeout);
    if (response.statusCode != 200) {
      await _abandonBody(response);
      throw PluginStoreException(
        AppL10n.strings.pluginsDomain.httpStatusFor(response.statusCode, url),
      );
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
    return DownloadedAsset(
      path: destPath,
      ext: ext,
      size: await _streamToFile(response, File(destPath)),
      originalName: originalName,
    );
  }

  /// כותב את גוף התשובה ל-`.part` ומחליף בו את היעד רק אחרי שנסגר בהצלחה:
  /// הורדה שנקטעה באמצע לא תשאיר קובץ חלקי שנראה כתוסף תקין, והקובץ הקודם
  /// שבמראה נשאר שלם עד הרגע האחרון. מחזיר את מספר הבייטים שנכתבו.
  Future<int> _streamToFile(http.StreamedResponse response, File dest) async {
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    var size = 0;
    try {
      // ה-timeout על הזרם מתאפס בכל מנה — נחתך רק כשאין התקדמות.
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        size += chunk.length;
      }
      await sink.flush();
      await sink.close();
      // ב-Windows handle פתוח חוסם את ההחלפה, ולכן השינוי אחרי הסגירה.
      await part.rename(dest.path);
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await part.delete();
      } catch (_) {}
      rethrow;
    }
    return size;
  }

  /// נוטש את גוף התשובה במסלול שגיאה בלי לרוקן אותו — אחרת שרת שממשיך לשדר
  /// היה מזרים נכס שלם רק כדי שנדווח כשל.
  Future<void> _abandonBody(http.StreamedResponse response) async {
    try {
      await response.stream.listen((_) {}).cancel();
    } catch (_) {}
  }

  /// מתרגמת כשל רשת להודעה למשתמש. `TimeoutException` הוא המקרה השכיח
  /// ביותר, והטקסט הגולמי שלו ("Future not completed") אינו אומר דבר.
  static String describeError(Object error) => error is TimeoutException
      ? AppL10n.strings.pluginsDomain.networkTimedOut
      : '$error';

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
