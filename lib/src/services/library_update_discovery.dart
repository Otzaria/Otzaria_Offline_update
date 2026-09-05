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

  /// מחלץ מספר גרסה מ-tag כמו `v20-20260807110905`, `v3` או `3`. מעוגן
  /// לתחילת ה-tag בכוונה: המאגר מפרסם גם תגים ממוזערי-תוכן כמו
  /// `lines-snapshot-sha256-<hex>`, ורצף הספרות **הראשון** שם הוא ה-`256`
  /// שבתוך "sha256" — כלומר גרסה שגבוהה מכל גרסה אמיתית, לנצח.
  static int? parseVersionFromTag(String tag) {
    final match = RegExp(r'^v?(\d+)').firstMatch(tag);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// סורק את כל ה-releases ומחזיר את ה-edges, הגרסה האחרונה וה-DB המלא.
  Future<LibraryDiscoveryResult> discover({
    required bool allowPrerelease,
  }) async {
    final releases = eligibleReleases(
      await client.fetchReleases(),
      allowPrerelease: allowPrerelease,
    );

    // כל הקשתות שנבנו, כולל כאלה שאיננו יודעים להחיל: הן קובעות מהי הגרסה
    // האחרונה שקיימת בכלל, גם כשהמסלול אליה אינו patches.
    final allEdges = <PatchEdge>[];
    for (final release in releases) {
      for (final manifestAsset in release.deltaManifestAssets) {
        final edge = await _buildEdge(release, manifestAsset);
        if (edge != null) allEdges.add(edge);
      }
    }

    var maxEdgeVersion = 0;
    for (final edge in allEdges) {
      if (edge.toVersion > maxEdgeVersion) maxEdgeVersion = edge.toVersion;
    }

    // **הסינון המרכזי:** patch שסכמתו או שפורמטו אינם מוכרים ייכשל
    // ב-preflight של `PatchApplier` — אחרי הורדה, חילוץ, והחלפת המסד החי
    // במסלול המלא. לכן הוא יוצא מהגרף כאן, וה-planner בונה תוכנית רק ממה
    // שאפשר להחיל.
    final unsupportedSchemas = <int>{};
    final unsupportedFormats = <int>{};
    final edges = <PatchEdge>[];
    for (final edge in allEdges) {
      if (edge.isApplicable) {
        edges.add(edge);
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

    // ה-DB המלא ל-fallback: מה-release בעל הגרסה הגבוהה ביותר שיש לו
    // seforim.db.zst.
    ReleaseAsset? latestFull;
    String? latestTag;
    var bestFullVersion = -1;
    for (final release in releases) {
      final full = release.fullDbAsset;
      if (full == null) continue;
      final version = releaseVersionOf(release);
      if (version > bestFullVersion) {
        bestFullVersion = version;
        latestFull = full;
        latestTag = release.tag;
      }
    }

    // ה-latest הוא הגבוה מבין ה-edges וה-DB המלא — כך release חדש שיצא עם DB
    // מלא בלבד (טרם נוצרו לו patches) עדיין נחשב latest, ויפעיל full fallback.
    final latestVersion =
        maxEdgeVersion > bestFullVersion ? maxEdgeVersion : bestFullVersion;

    return LibraryDiscoveryResult(
      latestVersion: latestVersion,
      edges: edges,
      latestFullDbAsset: latestFull,
      fullDbReleaseTag: latestTag,
      latestContentTag: _newestReleaseTag(releases),
      latestFullDbVersion: latestFull == null ? null : bestFullVersion,
      unsupportedSchemaVersions: unsupportedSchemas,
      unsupportedPatchFormatVersions: unsupportedFormats,
    );
  }

  /// ה-tag של ה-release בעל הגרסה הגבוהה ביותר; שוויון נשבר לפי תאריך
  /// הפרסום. זה ה-release שמסד מעודכן "מגיע ממנו" — ולכן זה מה שנרשם אחרי
  /// החלה מוצלחת, ולא נושא המסד המלא.
  static String? _newestReleaseTag(List<LibraryRelease> releases) {
    LibraryRelease? newest;
    var newestVersion = -1;
    for (final release in releases) {
      final version = releaseVersionOf(release);
      if (version > newestVersion ||
          (version == newestVersion && _publishedAfter(release, newest))) {
        newestVersion = version;
        newest = release;
      }
    }
    return newest?.tag;
  }

  static bool _publishedAfter(LibraryRelease candidate, LibraryRelease? best) {
    final bestDate = best?.publishedAt;
    if (bestDate == null) return true;
    final own = candidate.publishedAt;
    return own != null && own.isAfter(bestDate);
  }

  /// בונה [PatchEdge] מ-manifest asset. מחזיר null אם ה-manifest פגום או אם
  /// קובץ patch הנדרש חסר ב-release — מתעלמים מ-edge כזה בלי להכשיל הכל.
  Future<PatchEdge?> _buildEdge(
    LibraryRelease release,
    ReleaseAsset manifestAsset,
  ) async {
    try {
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
      // קובץ patch חסר ⇒ הקשת אינה שמישה, ומתעלמים ממנה בלי להכשיל הכל.
      // היוצא היחיד: יכולת שאיננו מכירים (סכמה או פורמט), שממנה המראה שומרת
      // את ה-manifest בלבד (`LibraryMirrorExporter`). שם הקשת נשמרת כמטא-דאטה
      // כדי שהגרסה החדשה תישאר ידועה ומנומקת ולא תיראה כ"מעודכן" — היא
      // מסוננת מיד ב-[discover] ולעולם אינה מגיעה לתוכנית.
      if (missingFile && edge.isApplicable) return null;
      return edge;
    } catch (_) {
      return null;
    }
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
