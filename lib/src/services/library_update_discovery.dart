import '../models/library_release.dart';
import '../models/library_update_plan.dart';
import '../models/patch_table_spec.dart';
import 'library_release_source.dart';

/// תוצאת סריקת ה-releases: הגרסה האחרונה, ה-edges הזמינים, וה-DB המלא
/// ל-fallback.
class LibraryDiscoveryResult {
  final int latestVersion;
  final List<PatchEdge> edges;
  final ReleaseAsset? latestFullDbAsset;

  /// ה-tag של ה-release ש-[latestFullDbAsset] יורד ממנו — **לא** ה-release
  /// החדש ביותר. ראו [latestContentTag].
  final String? fullDbReleaseTag;

  /// ה-tag של ה-release החדש ביותר, כלומר זה שהתוכן העדכני מגיע ממנו.
  /// נפרד מ-[fullDbReleaseTag] בכוונה: release שמכיל patches בלבד הוא החדש
  /// ביותר, בעוד המסד המלא נשאר של גרסה קודמת.
  final String? latestContentTag;

  /// גרסת ה-DB ש-[latestFullDbAsset] באמת מביא. **אינה בהכרח**
  /// [latestVersion]: כש-release חדש מכיל patches בלבד, ה-DB המלא האחרון
  /// הוא של גרסה קודמת. בלי ההבחנה הזו תוכנית ההורדה המלאה מכריזה על יעד
  /// שהנכס אינו מגיע אליו, והאימות שאחרי החילוץ דוחה ~1.1GB שהורדו זה עתה.
  final int? latestFullDbVersion;

  /// גרסות הסכמה שנראו ב-releases ואין לנו סדר hash להן — ראו
  /// [isSupportedSchemaVersion]. לא ריק פירושו שקשתות סוננו מ-[edges],
  /// והמסלול לגרסה האחרונה הוא מסד מלא ולא קובצי עדכון.
  final Set<int> unsupportedSchemaVersions;

  /// גרסאות פורמט ה-`patch.db` שנראו ואיננו יודעים להחיל — הציר השני של
  /// אותה פסילה, ראו [isSupportedPatchFormatVersion].
  final Set<int> unsupportedPatchFormatVersions;

  final List<String> unreadableManifests;

  final String? newestReleaseTag;

  /// גרסת הסכמה הגבוהה שנראתה ואינה נתמכת, או null כשהכל נתמך. זו הגרסה
  /// שמוצגת למשתמש כהסבר למה מורידים מסד שלם.
  int? get blockingSchemaVersion => _highest(unsupportedSchemaVersions);

  /// אותו דבר לציר הפורמט. הסכמה נבדקת ראשונה בהודעות: היא מה שמשתנה בפועל
  /// בין גרסאות הספרייה.
  int? get blockingPatchFormatVersion =>
      _highest(unsupportedPatchFormatVersions);

  static int? _highest(Set<int> versions) =>
      versions.isEmpty ? null : versions.reduce((a, b) => a > b ? a : b);

  const LibraryDiscoveryResult({
    required this.latestVersion,
    required this.edges,
    required this.latestFullDbAsset,
    required this.fullDbReleaseTag,
    required this.latestContentTag,
    this.latestFullDbVersion,
    this.unsupportedSchemaVersions = const {},
    this.unsupportedPatchFormatVersions = const {},
    this.unreadableManifests = const [],
    this.newestReleaseTag,
  });
}

/// סורק את ה-releases של GitHub, בונה את גרף ה-patches ומזהה את הגרסה
/// האחרונה. ה-edges וה-DB המלא מוזנים אחר כך ל-[LibraryUpdatePlanner].
class LibraryUpdateDiscovery {
  final LibraryReleaseSource client;

  const LibraryUpdateDiscovery({required this.client});

  static final RegExp _manifestVersionPattern =
      RegExp(r'^patch-v(\d+)-v(\d+)\.db\.zst\.manifest\.json$');

  /// מסנן releases לפי הערוץ: תמיד מתעלם מ-draft; prerelease מותר רק כש-
  /// [allowPrerelease] פעיל.
  static List<LibraryRelease> eligibleReleases(
    List<LibraryRelease> releases, {
    required bool allowPrerelease,
  }) {
    return releases
        .where((r) => !r.isDraft && (allowPrerelease || !r.isPrerelease))
        .toList(growable: false);
  }

  static ({String tag, int version})? latestOnlineRelease(
    List<LibraryRelease> releases, {
    required bool allowPrerelease,
  }) {
    ({String tag, int version})? latest;
    for (final release
        in eligibleReleases(releases, allowPrerelease: allowPrerelease)) {
      if (release.deltaManifestAssets.isEmpty && release.fullDbAsset == null) {
        continue;
      }
      final version = releaseVersionOf(release);
      if (version > (latest?.version ?? 0)) {
        latest = (tag: release.tag, version: version);
      }
    }
    return latest;
  }

  /// מחלץ מספר גרסה מ-tag כמו `v20-20260807110905`, `v3` או `3`. מעוגן
  /// לתחילת ה-tag בכוונה: המאגר מפרסם גם תגים ממוזערי-תוכן כמו
  /// `lines-snapshot-sha256-<hex>`, ורצף הספרות **הראשון** שם הוא ה-`256`
  /// שבתוך "sha256" — כלומר גרסה שגבוהה מכל גרסה אמיתית, לנצח.
  static int? parseVersionFromTag(String tag) {
    final match = RegExp(r'^v?(\d+)').firstMatch(tag);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  Future<LibraryDiscoveryResult> discover({
    required bool allowPrerelease,
  }) async {
    final releases = eligibleReleases(
      await client.fetchReleases(),
      allowPrerelease: allowPrerelease,
    );

    final allEdges = <PatchEdge>[];
    final edgeRelease = <PatchEdge, LibraryRelease>{};
    final unreadableManifests = <String>[];
    final contributed = <LibraryRelease, int>{};
    void contribute(LibraryRelease release, int version) {
      if (version > (contributed[release] ?? -1)) {
        contributed[release] = version;
      }
    }

    var maxManifestVersion = 0;
    for (final release in releases) {
      for (final manifestAsset in release.deltaManifestAssets) {
        final PatchEdge? edge;
        try {
          edge = await _buildEdge(release, manifestAsset);
        } catch (_) {
          unreadableManifests.add(manifestAsset.name);
          final version = _manifestToVersion(manifestAsset.name) ??
              releaseVersionOf(release);
          if (version > maxManifestVersion) maxManifestVersion = version;
          continue;
        }
        if (edge == null) continue;
        allEdges.add(edge);
        edgeRelease[edge] = release;
        contribute(release, edge.toVersion);
        if (edge.toVersion > maxManifestVersion) {
          maxManifestVersion = edge.toVersion;
        }
      }
    }

    final unsupportedSchemas = <int>{};
    final unsupportedFormats = <int>{};
    final edges = <PatchEdge>[];
    for (final edge in allEdges) {
      if (edge.isApplicable) {
        edges.add(edge);
        continue;
      }
      if (edge.manifest.fullRebase) {
        final target = edge.manifest.toSchemaVersion;
        if (!isSupportedSchemaVersion(target) &&
            edgeRelease[edge]?.fullDbAsset == null) {
          unsupportedSchemas.add(target);
        }
        continue;
      }
      for (final schema in [
        edge.manifest.fromSchemaVersion,
        edge.manifest.toSchemaVersion,
      ]) {
        if (!isSupportedSchemaVersion(schema)) unsupportedSchemas.add(schema);
      }
      final format = edge.manifest.patchFormatVersion;
      if (format != null && !isSupportedPatchFormatVersion(format)) {
        unsupportedFormats.add(format);
      }
    }

    LibraryRelease? fullRelease;
    var bestFullVersion = -1;
    for (final release in releases) {
      if (release.fullDbAsset == null) continue;
      final version = releaseVersionOf(release);
      contribute(release, version);
      if (version > bestFullVersion ||
          (version == bestFullVersion &&
              _publishedAfter(release, fullRelease))) {
        bestFullVersion = version;
        fullRelease = release;
      }
    }
    final latestFull = fullRelease?.fullDbAsset;
    final latestTag = fullRelease?.tag;

    var latestVersion = maxManifestVersion > bestFullVersion
        ? maxManifestVersion
        : bestFullVersion;

    for (final release in releases) {
      final schema = release.unsupportedFullDbSchema;
      if (schema == null) continue;
      final version = releaseVersionOf(release);
      if (version < latestVersion) continue;
      latestVersion = version;
      unsupportedSchemas.add(schema);
      contribute(release, version);
    }

    return LibraryDiscoveryResult(
      latestVersion: latestVersion,
      edges: edges,
      latestFullDbAsset: latestFull,
      fullDbReleaseTag: latestTag,
      latestContentTag: _newestReleaseTag(
        releases.where((r) => contributed[r] == latestVersion),
      ),
      latestFullDbVersion: latestFull == null ? null : bestFullVersion,
      unsupportedSchemaVersions: unsupportedSchemas,
      unsupportedPatchFormatVersions: unsupportedFormats,
      unreadableManifests: unreadableManifests,
      newestReleaseTag: _newestContentRelease(releases)?.tag,
    );
  }

  static LibraryRelease? _newestContentRelease(List<LibraryRelease> releases) {
    LibraryRelease? newest;
    var newestVersion = -1;
    for (final release in releases) {
      if (release.deltaManifestAssets.isEmpty && release.fullDbAsset == null) {
        continue;
      }
      final version = releaseVersionOf(release);
      if (version > newestVersion ||
          (version == newestVersion && _publishedAfter(release, newest))) {
        newestVersion = version;
        newest = release;
      }
    }
    return newest;
  }

  static String? _newestReleaseTag(Iterable<LibraryRelease> candidates) {
    LibraryRelease? newest;
    for (final release in candidates) {
      if (_publishedAfter(release, newest)) newest = release;
    }
    return newest?.tag;
  }

  static bool _publishedAfter(LibraryRelease candidate, LibraryRelease? best) {
    if (best == null) return true;
    final bestDate = best.publishedAt;
    if (bestDate == null) return true;
    final own = candidate.publishedAt;
    return own != null && own.isAfter(bestDate);
  }

  static int? _manifestToVersion(String name) {
    final match = _manifestVersionPattern.firstMatch(name);
    return match == null ? null : int.parse(match.group(2)!);
  }

  Future<PatchEdge?> _buildEdge(
    LibraryRelease release,
    ReleaseAsset manifestAsset,
  ) async {
    final manifest = await client.fetchManifest(manifestAsset.downloadUrl);
    final urls = <String, String>{};
    var missingFile = false;
    for (final patchFile in manifest.patchFiles) {
      final asset = release.assetByName(patchFile.file);
      if (asset == null) {
        missingFile = true;
      } else {
        urls[patchFile.file] = asset.downloadUrl;
      }
    }
    final edge = PatchEdge(
      manifest: manifest,
      patchFileUrls: urls,
      manifestUrl: manifestAsset.downloadUrl,
    );
    if (missingFile && edge.isApplicable) return null;
    return edge;
  }

  /// גרסת ה-release לפי שמות ה-manifest assets, או לפי ה-tag כ-fallback.
  /// static כדי ש-[LibraryMirrorExporter] יבחר את ה-release האחרון לפי
  /// אותו כלל בדיוק שהתכנון משתמש בו.
  static int releaseVersionOf(LibraryRelease release) {
    var version = 0;
    for (final asset in release.deltaManifestAssets) {
      final match = _manifestVersionPattern.firstMatch(asset.name);
      if (match != null) {
        final to = int.parse(match.group(2)!);
        if (to > version) version = to;
      }
    }
    if (version == 0) {
      version = parseVersionFromTag(release.tag) ?? 0;
    }
    return version;
  }
}
