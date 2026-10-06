import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
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

  /// מוריד בזרימה ומחזיר SHA-256; חלקי נשמר בנפרד כדי לא להיראות מוכן להתקנה.
  /// digest שגיטהאב פרסם נבדק כאן, כי במחשב המנותק אין מאיפה להוריד שוב.
  Future<String> download(
    GithubAsset asset,
    String destinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final result = await downloadFile(
      client: _http,
      url: asset.downloadUrl,
      destinationPath: destinationPath,
      expectedSize: asset.sizeBytes,
      connectTimeout: timeout,
      stallTimeout: stallTimeout,
      onProgress: onProgress,
      calculateSha256: true,
      statusError: (status) => AppDescriptorException(
          AppL10n.strings.customAppsDomain.downloadFailed(status)),
      sizeError: (actual, expected) => AppDescriptorException(
          AppL10n.strings.appDomain.installerSizeMismatch(actual, expected)),
    );
    final file = File(destinationPath);
    final actual = result.sha256!;
    if (asset.sha256 case final expected? when expected != actual) {
      await file.delete();
      throw AppDescriptorException(
          AppL10n.strings.customAppsDomain.downloadDigestMismatch(asset.name));
    }
    return actual;
  }

  void dispose() => _http.close();
}
