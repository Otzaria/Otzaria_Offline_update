import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/app_descriptor.dart';
import '../models/github_release.dart';
import '../models/github_source.dart';

/// מדבר עם GitHub עבור תוכנה נוספת: מביא את הגרסה האחרונה, ומוריד ממנה
/// קובץ.
///
/// **זו הפעולה היחידה בחבילה שנוגעת ברשת**, והיא רצה על המחשב המקוון
/// בלבד. כל השאר — התקנה, זיהוי, הפעלה — קורא מהמראה שעל הכונן.
class GithubAppClient {
  GithubAppClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// בלי זמן קצוב, מחשב שמחובר לרשת אך בלי מסלול לאינטרנט (captive portal)
  /// היה תולה את הבדיקה ללא הגבלה — אותו לקח מ-`OtzariaReleaseClient`.
  Duration timeout;
  Duration stallTimeout;

  static const int _pageSize = 20;
  static const int _writeBufferBytes = 4 << 20;

  /// הגרסה האחרונה שאינה טיוטה. pre-release נבחר רק אם אין שום גרסה
  /// יציבה — GitHub מחזיר מהחדש לישן, ולכן "יציבה ראשונה ברשימה" היא
  /// היציבה האחרונה.
  ///
  /// זורק חריג רשת/HTTP רגיל בכשל; הקורא מתייחס אליו כ"אין חיבור כרגע".
  Future<GithubRelease?> fetchLatest(GithubSource source) async {
    final releases = await fetchReleases(source);
    for (final release in releases) {
      if (!release.isPrerelease) return release;
    }
    return releases.isEmpty ? null : releases.first;
  }

  /// כל ה-releases האחרונים, מהחדש לישן, בלי טיוטות. משמש את בורר הקבצים
  /// בטופס — הוא מציג את הקבצים של הגרסה האחרונה.
  Future<List<GithubRelease>> fetchReleases(GithubSource source) async {
    final uri = Uri.parse('${source.releasesApiUrl}?per_page=$_pageSize');
    final response = await _http.get(
      uri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        // ⚠️ חובה: בלי User-Agent ‏GitHub מחזיר 403 לכל בקשה, בלי קשר
        // ל-rate limit.
        'User-Agent': 'otzaria-launcher',
      },
    ).timeout(timeout);

    if (response.statusCode != 200) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain
            .githubStatus(response.statusCode, '$uri'),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.githubBadResponse,
      );
    }

    return decoded
        .cast<Map<String, dynamic>>()
        .where((json) => !(json['draft'] as bool? ?? false))
        .map(GithubRelease.fromJson)
        .toList(growable: false);
  }

  /// הקובץ שתואם לתבנית שנשמרה, או `null` כשאין כזה בגרסה הזאת.
  static GithubAsset? selectAsset(GithubRelease release, String pattern) {
    for (final asset in release.assets) {
      if (GithubAssetPattern.matches(pattern, asset.name)) return asset;
    }
    return null;
  }

  /// מוריד קובץ אל [destinationPath]. הקובץ החלקי נמחק בכשל, כדי שהריצה
  /// הבאה לא תראה אותו כהורדה שהסתיימה.
  Future<void> download(
    GithubAsset asset,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(asset.downloadUrl));
    final response = await _http.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      throw AppDescriptorException(
        AppL10n.strings.customAppsDomain.downloadFailed(response.statusCode),
      );
    }

    final file = File(destinationPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    var buffered = 0;

    try {
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        buffered += chunk.length;
        onProgress?.call(received, asset.sizeBytes);
        // `IOSink.add` אינו מפעיל לחץ-נגד: בלי ההמתנה הזו קובץ שיורד מהר
        // יותר משהכונן הנייד כותב נערם ב-RAM.
        if (buffered >= _writeBufferBytes) {
          buffered = 0;
          await sink.flush();
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  void dispose() => _http.close();
}
