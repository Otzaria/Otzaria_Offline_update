import 'package:http/http.dart' as http;
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import '../models/store_app_release.dart';
import 'plugin_store_client.dart';

/// שולף את ה-releases של **תוכנת החנות** — `Otzaria/otzaria-plugin-store`.
/// מטא-דאטה בלבד; ההורדה עצמה היא של `StoreAppMirror`.
class StoreAppReleaseClient {
  StoreAppReleaseClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client();

  /// זמן קצוב לבקשה — חובה, כמו בכל לקוח גיטהאב כאן: בלעדיו מחשב שמחובר
  /// לרשת בלי מסלול לאינטרנט היה תולה את הבדיקה בלי הגבלה.
  Duration timeout;

  static const String owner = 'Otzaria';
  static const String repo = 'otzaria-plugin-store';
  static const String _apiBase = 'https://api.github.com';

  /// דף ה-releases, לתצוגה כשאין release ספציפי להצביע עליו.
  static const String releasesPageUrl =
      'https://github.com/$owner/$repo/releases';

  /// דף אחד מספיק: מחפשים את הגרסה היציבה הגבוהה, לא את כל ההיסטוריה.
  static const int _pageSize = 30;

  final http.Client _httpClient;

  /// הגרסה היציבה **הגבוהה ביותר** שיש בה קובץ הרצה בסיסי, או `null` אם
  /// אין כזו בדף הראשון.
  ///
  /// הבחירה היא לפי המספר שבתג ולא לפי הסדר שגיטהאב החזיר — סדר הפרסום
  /// אינו סדר הגרסאות. `bundle` (החבילה המלאה) נופל כבר על צורת התג.
  Future<StoreAppRelease?> fetchLatestStable() async {
    final uri = Uri.parse(
      '$_apiBase/repos/$owner/$repo/releases?per_page=$_pageSize',
    );

    final http.Response response;
    try {
      response = await githubGet(_httpClient, uri, timeout: timeout);
    } on GithubRateLimitException {
      rethrow;
    } catch (e) {
      throw PluginStoreException(
        AppL10n.strings.pluginsDomain
            .siteUnreachable(PluginStoreClient.describeError(e)),
      );
    }

    if (response.statusCode != 200) {
      throw PluginStoreException(
        AppL10n.strings.appDomain.githubStatus(response.statusCode, '$uri'),
      );
    }

    final decoded = decodeGithubJson(response);
    if (decoded is! List) {
      throw PluginStoreException(
        AppL10n.strings.appDomain.noReleasesAtAll('$owner/$repo'),
      );
    }

    StoreAppRelease? best;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      if (entry['draft'] == true || entry['prerelease'] == true) continue;

      final release = parse(Map<String, dynamic>.from(entry));
      if (release == null) continue;
      if (best == null || release.version > best.version) best = release;
    }
    return best;
  }

  static StoreAppRelease? parse(Map<String, dynamic> json) {
    final tagName = json['tag_name'];
    if (tagName is! String) return null;
    final version = storeAppVersionOf(tagName);
    if (version == null) return null;

    final assets = json['assets'];
    if (assets is! List) return null;

    for (final raw in assets) {
      final asset = GithubReleaseAsset.tryParse(raw);
      if (asset == null || !asset.isReady) continue;
      if (!isBasicAppAsset(asset.name)) continue;

      return StoreAppRelease(
        tagName: tagName,
        version: version,
        assetName: asset.name,
        downloadUrl: asset.downloadUrl,
        sizeBytes: asset.size,
        sha256: asset.sha256,
        publishedAt: json['published_at'] is String
            ? DateTime.tryParse(json['published_at'] as String)
            : null,
        pageUrl: json['html_url'] is String &&
                (json['html_url'] as String).isNotEmpty
            ? json['html_url'] as String
            : releasesPageUrl,
      );
    }
    return null;
  }

  /// קובץ ההרצה **הבסיסי** בלבד: `.exe` שאינו חבילת ה-`Full` (109MB של
  /// תוספים ארוזים). את התוספים אנחנו אורזים מהמראה שכבר על הכונן, ולכן
  /// הורדת החבילה המלאה הייתה מביאה פעמיים את אותו דבר — פעם אחת ישן.
  static bool isBasicAppAsset(String assetName) {
    final name = assetName.toLowerCase();
    return name.endsWith('.exe') && !name.contains('-full');
  }

  void dispose() => _httpClient.close();
}
