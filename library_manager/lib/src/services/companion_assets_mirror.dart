import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'companion_assets.dart';
import 'zstd_decompressor.dart';

/// מוריד למראה את שלושת הקבצים הנלווים שאוצריא מרעננת בכל עדכון ספרייה,
/// כדי שהמחשב הלא-מקוון יקבל אותם יחד עם המסד.
///
/// שלושת המקורות זהים לאלה של `CompanionAssetsService` באוצריא — אותם
/// מאגרים, אותם שמות נכסים, אותם כללי בחירה. כל פריט הוא best-effort: כשל
/// באחד (אין נכס ב-release, שגיאת רשת) לא מפיל את השניים האחרים, בדיוק כמו
/// שם.
class CompanionAssetsMirror {
  CompanionAssetsMirror({
    http.Client? httpClient,
    DownloadScheduler? scheduler,
  })  : _scheduler = scheduler ?? DownloadScheduler(),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null {
    _downloader = PatchDownloader(
      httpClient: _httpClient,
      // רק מוריד לדיסק; החילוץ קורה בהתקנה, לא כאן.
      decompress: const ZstdDecompressor().call,
    );
  }

  /// המאגרים שאוצריא מושכת מהם — ראו `CompanionAssetsService`,
  /// `ExternalCatalogRepository` ו-`MagicDictionaryDownloader`.
  static const String talmudReleaseApi =
      'https://api.github.com/repos/Otzaria/otzaria-library/releases/latest';
  static const String catalogReleaseApi =
      'https://api.github.com/repos/Otzaria/otzar-HB_catalog/releases/latest';
  static const String dictionaryReleaseApi =
      'https://api.github.com/repos/Otzaria/SeforimMagicIndexer/releases/latest';

  static const String talmudArchiveFileName = 'talmud_bavli_latest.tar.zst';
  static const String catalogArchiveFileName = 'otzar-HB_catalog.db.zst';
  static const String catalogDatabaseFileName = 'otzar-HB_catalog.db';
  static const String catalogVersionFileName = 'version.txt';
  static const String dictionaryFileName = 'lexical.db';

  /// GitHub מחזיר 403 לכל בקשה בלי `User-Agent` — ראו
  /// `GithubLibraryReleaseClient._apiHeaders`.
  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'otzaria-launcher',
  };

  final http.Client _httpClient;
  final bool _ownsClient;
  late final PatchDownloader _downloader;

  /// שלושת הפריטים אינם תלויים זה בזה, ולכן הם יורדים במקביל — התלמוד לבדו
  /// הוא ~450MB, והמילון והקטלוג היו מחכים לו בתור בלי סיבה. מוזרק מבחוץ
  /// כדי שהם יחלקו תקרת חיבורים אחת עם הורדת המסד שרצה במקביל.
  final DownloadScheduler _scheduler;

  Duration timeout = const Duration(seconds: 30);

  set connectTimeout(Duration value) => _downloader.connectTimeout = value;

  /// ממלא את [destDir] בשלושת הקבצים וכותב `companions.json`. מחזיר את
  /// המניפסט שנכתב. פריט שנכשל פשוט לא ייכלל בו — ובמחשב הלא-מקוון פשוט לא
  /// יותקן, בלי להכשיל את השאר.
  Future<CompanionMirrorManifest> sync({
    required String destDir,
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String assetName, Object error)? onWarning,
    bool Function()? isCancelled,
  }) async {
    await Directory(destDir).create(recursive: true);
    final strings = AppL10n.strings.libraryDomain;
    // מה שכבר יושב במראה: פריט שנכשל עכשיו שומר את רשומתו הקודמת כל עוד
    // הקובץ שלה עדיין שם. בלי זה סנכרון חוזר שנכשל (רשת/rate limit) היה
    // כותב `companions.json` ריק ומעלים קבצים שכבר נסעו לכונן.
    final previous = await CompanionMirrorManifest.load(destDir);
    final entries = <CompanionAsset, CompanionMirrorEntry>{};

    Future<void> run(
      CompanionAsset asset,
      String name,
      Future<CompanionMirrorEntry?> Function() body,
    ) async {
      _throwIfCancelled(isCancelled);
      onStage?.call(strings.companionChecking(name));
      try {
        final entry = await body();
        if (entry != null) entries[asset] = entry;
      } catch (error) {
        if (_isCancellation(error)) rethrow;
        final kept = previous?.entries[asset];
        if (kept != null &&
            kept.fileName.isNotEmpty &&
            await File(p.join(destDir, kept.fileName)).exists()) {
          entries[asset] = kept;
        }
        onWarning?.call(name, error);
      }
    }

    // מונה בייטים אחד לשלושתם: כל פריט מדווח למשבצת משלו, והמד מתאר את
    // הסכום. בלי זה שלוש הורדות מקבילות היו דורסות זו את דיווחי זו.
    final bytes = ByteProgressAggregator(onProgress: onBytesProgress);

    // במקביל, לא בטור: התלמוד (~450MB) לבדו ארוך פי כמה מהשניים האחרים.
    // הביטול הוא מה שכן עוצר את כולם — `run` מפיץ אותו הלאה בלבד.
    await _scheduler.run<void>([
      () => run(CompanionAsset.talmud, strings.companionTalmudName,
          () => _syncTalmud(destDir, onStage, bytes.slot(), isCancelled)),
      () => run(CompanionAsset.catalog, strings.companionCatalogName,
          () => _syncCatalog(destDir, onStage, bytes.slot(), isCancelled)),
      () => run(CompanionAsset.dictionary, strings.companionDictionaryName,
          () => _syncDictionary(destDir, onStage, bytes.slot(), isCancelled)),
    ]);

    final manifest = CompanionMirrorManifest(entries: entries);
    await File(p.join(destDir, CompanionMirrorManifest.fileName)).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
    return manifest;
  }

  Future<CompanionMirrorEntry?> _syncTalmud(
    String destDir,
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  ) async {
    final strings = AppL10n.strings.libraryDomain;
    final release = await _findTalmudRelease();
    onStage?.call(strings.companionDownloading(strings.companionTalmudName));
    await _download(
      url: release.downloadUrl,
      destPath: p.join(destDir, talmudArchiveFileName),
      size: release.size,
      sha256: release.sha256,
      identity: release.identity,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
    return CompanionMirrorEntry(
      fileName: talmudArchiveFileName,
      size: release.size,
      tag: release.tag,
      sha256: release.sha256,
      compressed: true,
    );
  }

  Future<CompanionMirrorEntry?> _syncCatalog(
    String destDir,
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  ) async {
    final strings = AppL10n.strings.libraryDomain;
    final json = await _getJson(catalogReleaseApi);
    final assets = _assetsOf(json);

    // מעדיפים את הארכיון הדחוס, ונופלים ל-DB הלא-דחוס — בדיוק כמו
    // `ExternalCatalogRepository.parseLatestDatabaseAsset`.
    final compressed = assets[catalogArchiveFileName];
    final plain = assets[catalogDatabaseFileName];
    final chosen = compressed ?? plain;
    if (chosen == null) {
      throw StateError(
          strings.companionAssetMissingInRelease(strings.companionCatalogName));
    }

    final versionAsset = assets[catalogVersionFileName];
    if (versionAsset == null) {
      throw StateError(
          strings.companionAssetMissingInRelease(strings.companionCatalogName));
    }
    final version = _parseVersionText(await _getText(versionAsset.downloadUrl));
    if (version == null) {
      throw StateError(
          strings.companionAssetMissingInRelease(strings.companionCatalogName));
    }

    onStage?.call(strings.companionDownloading(strings.companionCatalogName));
    await _download(
      url: chosen.downloadUrl,
      destPath: p.join(destDir, chosen.name),
      size: chosen.size,
      sha256: chosen.sha256,
      identity: chosen.identity,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
    return CompanionMirrorEntry(
      fileName: chosen.name,
      size: chosen.size,
      sha256: chosen.sha256,
      version: version,
      compressed: chosen.name == catalogArchiveFileName,
    );
  }

  Future<CompanionMirrorEntry?> _syncDictionary(
    String destDir,
    void Function(String stage)? onStage,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  ) async {
    final strings = AppL10n.strings.libraryDomain;
    final json = await _getJson(dictionaryReleaseApi);
    final tag = (json['tag_name'] as String?)?.trim();
    // אוצריא מזהה את הנכס לפי סיומת ה-URL ולא לפי שמו.
    final asset = _assetList(json).where((a) {
      return a.downloadUrl.endsWith('/$dictionaryFileName');
    }).firstOrNull;
    if (tag == null || tag.isEmpty || asset == null) {
      throw StateError(strings
          .companionAssetMissingInRelease(strings.companionDictionaryName));
    }

    onStage
        ?.call(strings.companionDownloading(strings.companionDictionaryName));
    await _download(
      url: asset.downloadUrl,
      destPath: p.join(destDir, dictionaryFileName),
      size: asset.size,
      sha256: asset.sha256,
      identity: asset.identity,
      onBytesProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
    return CompanionMirrorEntry(
      fileName: dictionaryFileName,
      size: asset.size,
      tag: tag,
      sha256: asset.sha256,
    );
  }

  Future<void> _download({
    required String url,
    required String destPath,
    required int size,
    required String? sha256,
    required String identity,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  }) {
    return _downloader.downloadToFile(
      url: url,
      destPath: destPath,
      expectedSize: size > 0 ? size : null,
      expectedSha256: sha256,
      resumeToken: identity,
      onProgress: onBytesProgress,
      isCancelled: isCancelled,
    );
  }

  /// ה-release העדכני שמכיל את נכס התלמוד: קודם `releases/latest`, ואם הנכס
  /// חסר בו — סריקה של עד שלושה עמודים, כמו
  /// `CompanionAssetsService.findLatestTalmudRelease`.
  Future<_GithubAssetRef> _findTalmudRelease() async {
    final latest = await _getJson(talmudReleaseApi);
    final fromLatest = _talmudAssetOf(latest);
    if (fromLatest != null) return fromLatest;

    for (var page = 1; page <= 3; page++) {
      final list = await _getJsonList(
        talmudReleaseApi.replaceFirst(
          '/releases/latest',
          '/releases?per_page=100&page=$page',
        ),
      );
      if (list.isEmpty) break;
      for (final release in list) {
        if (release['prerelease'] == true) continue;
        final asset = _talmudAssetOf(release);
        if (asset != null) return asset;
      }
    }
    throw StateError(
      AppL10n.strings.libraryDomain.companionAssetMissingInRelease(
        AppL10n.strings.libraryDomain.companionTalmudName,
      ),
    );
  }

  _GithubAssetRef? _talmudAssetOf(Map<String, dynamic> release) {
    final tag = (release['tag_name'] as String?)?.trim();
    if (tag == null || tag.isEmpty) return null;
    final asset = _assetsOf(release)[talmudArchiveFileName];
    return asset?.withTag(tag);
  }

  /// `version.txt` הוא קובץ של בייטים בודדים — קריאה ישירה, בלי המסלול
  /// המאומת של [PatchDownloader] שנועד לנכסים גדולים.
  Future<String> _getText(String url) async {
    final response = await _httpClient.get(Uri.parse(url),
        headers: const {'User-Agent': 'otzaria-launcher'}).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        AppL10n.strings.libraryDomain.releasesRequestFailed(
          response.statusCode,
        ),
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _httpClient
        .get(Uri.parse(url), headers: _apiHeaders)
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        AppL10n.strings.libraryDomain.releasesRequestFailed(
          response.statusCode,
        ),
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        AppL10n.strings.libraryDomain.releasesResponseNotList,
      );
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> _getJsonList(String url) async {
    final response = await _httpClient
        .get(Uri.parse(url), headers: _apiHeaders)
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception(
        AppL10n.strings.libraryDomain.releasesRequestFailed(
          response.statusCode,
        ),
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Map<String, _GithubAssetRef> _assetsOf(Map<String, dynamic> release) => {
        for (final asset in _assetList(release)) asset.name: asset,
      };

  List<_GithubAssetRef> _assetList(Map<String, dynamic> release) {
    final raw = release['assets'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final digest = json['digest'] as String?;
          return _GithubAssetRef(
            name: (json['name'] as String?) ?? '',
            downloadUrl: (json['browser_download_url'] as String?) ?? '',
            size: (json['size'] as num?)?.toInt() ?? 0,
            sha256: digest != null && digest.startsWith('sha256:')
                ? digest.substring('sha256:'.length)
                : null,
            id: json['id']?.toString() ?? '',
            updatedAt: json['updated_at']?.toString() ?? '',
          );
        })
        .where((a) => a.downloadUrl.isNotEmpty)
        .toList(growable: false);
  }

  static int? _parseVersionText(String raw) => int.tryParse(raw.trim());

  bool _isCancellation(Object error) => error is PatchDownloadCancelled;

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
  }

  void dispose() {
    _downloader.dispose();
    if (_ownsClient) _httpClient.close();
  }
}

/// נכס בודד מתוך JSON של release, בצורה שנוחה להורדה מאומתת.
class _GithubAssetRef {
  const _GithubAssetRef({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.id,
    required this.updatedAt,
    this.sha256,
    this.tag,
  });

  final String name;
  final String downloadUrl;
  final int size;
  final String? sha256;
  final String id;
  final String updatedAt;
  final String? tag;

  /// זהות שקושרת קובץ חלקי ל-release מסוים — העלאה-מחדש תחת אותו תג משנה
  /// את ה-id/updated_at, כך ששריד ישן לא ייחשב עדכני.
  String get identity => '$tag|$size|$id|$updatedAt';

  _GithubAssetRef withTag(String value) => _GithubAssetRef(
        name: name,
        downloadUrl: downloadUrl,
        size: size,
        id: id,
        updatedAt: updatedAt,
        sha256: sha256,
        tag: value,
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
