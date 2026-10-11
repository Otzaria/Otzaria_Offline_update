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

  Future<GithubRelease?> fetchLatest(GithubSource source) async {
    final releases = await fetchReleases(source);
    final pattern = source.assetPattern;
    if (pattern.isEmpty) return _newest(releases);
    final usable = [
      for (final release in releases)
        if (selectAsset(release, pattern) != null) release,
    ];
    return _newest(usable) ?? _newest(releases);
  }

  static GithubRelease? _newest(List<GithubRelease> releases) {
    final stable = [
      for (final release in releases)
        if (!release.isPrerelease) release,
    ];
    final pool = stable.isEmpty ? releases : stable;
    if (pool.isEmpty) return null;
    final numbers = [
      for (final release in pool) _numericVersion(release.version),
    ];
    if (numbers.contains(null)) return pool.first;
    var best = 0;
    for (var i = 1; i < pool.length; i++) {
      if (_compareNumeric(numbers[i]!, numbers[best]!) > 0) best = i;
    }
    return pool[best];
  }

  static List<int>? _numericVersion(String version) {
    final numbers = <int>[];
    for (final part in version.split('.')) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || part.startsWith('+')) return null;
      numbers.add(number);
    }
    return numbers;
  }

  static int _compareNumeric(List<int> a, List<int> b) {
    final count = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < count; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left < right ? -1 : 1;
    }
    return 0;
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
