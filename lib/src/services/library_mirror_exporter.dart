import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import '../models/library_release.dart';
import 'github_library_release_client.dart';
import 'library_update_discovery.dart';
import 'local_mirror_library_release_client.dart';
import 'patch_downloader.dart';

/// בונה "מראה" (mirror) מקומית מלאה של כל עדכוני הספרייה מ-GitHub,
/// לתיקייה על הדיסק (USB / תיקייה משותפת) — כדי שמחשבים **בלי אינטרנט
/// בכלל** יוכלו לעדכן את ה-DB אחר-כך דרך [LocalMirrorLibraryReleaseClient],
/// בלי לגעת ב-GitHub בכלל.
///
/// מריצים את [export] פעם אחת במחשב **עם** אינטרנט; אחר-כך מעתיקים את
/// התיקייה שנוצרה (USB וכו') ופותחים אותה במחשבים האחרים דרך "עדכן מתיקייה
/// מקומית" בלאנצ'ר.
///
/// **הערה על גודל:** מראה מלאה כוללת את כל ה-patches ההיסטוריים וגם את
/// ה-DB המלא (~1.1GB דחוס) — יכולה להגיע לכמה ג'יגה-בייט. זה מחיר סביר
/// עבור "עובד לגמרי אופליין"; אין כרגע אופציה לייצא רק טווח גרסאות חלקי.
class LibraryMirrorExporter {
  LibraryMirrorExporter({
    GithubLibraryReleaseClient? client,
    http.Client? httpClient,
  })  : _client = client ?? GithubLibraryReleaseClient(),
        _ownsClient = client == null,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    _downloader = PatchDownloader(
      httpClient: _httpClient,
      // הייצוא רק מוריד לדיסק ואינו מחלץ דבר — `downloadAndExtract` לא נקרא
      // כאן, ולכן אין למי לספק פונקציית חילוץ.
      decompress: _neverDecompress,
    );
  }

  final GithubLibraryReleaseClient _client;
  final bool _ownsClient;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  /// ההורדה עוברת דרך [PatchDownloader] ולא דרך `http` ישר. זה לא ניקיון קוד:
  /// המוריד הזה כבר מביא זמן קצוב, אימות גודל ו-sha256, חידוש הורדה (Range +
  /// If-Range) ומחיקה של קובץ חלקי שאינו ניתן לחידוש. בלעדיו הורדת ה-DB המלא
  /// (~1GB) על חיבור שנפל התחילה מאפס בכל פעם, ושרת שנשתק תלה את הייצוא בלי
  /// גבול — וזה בדיוק המסלול שהמשתמש מריץ פעם אחת על מחשב מקוון.
  late final PatchDownloader _downloader;

  /// בונה מראה מלאה תחת [destDir] (נוצרת אם חסרה). מוריד את כל ה-releases
  /// הרלוונטיים (כאלה עם delta manifests ו/או DB מלא), כולל כל קובצי ה-patch
  /// שכל manifest מצביע עליהם, וכותב `releases.json` בסוף.
  Future<void> export({
    required String destDir,
    bool allowPrerelease = true,
    void Function(String stage)? onStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    final root = Directory(destDir);
    await root.create(recursive: true);
    final assetsRoot = Directory(p.join(destDir, 'assets'));
    await assetsRoot.create(recursive: true);

    final strings = AppL10n.strings.libraryDomain;

    onStage?.call(strings.exportLoadingReleases);
    final all = await _client.fetchReleases();
    final eligible = LibraryUpdateDiscovery.eligibleReleases(
      all,
      allowPrerelease: allowPrerelease,
    );
    final relevant = _latestOnly(eligible);

    if (relevant.isEmpty) {
      throw StateError(strings.exportNoReleases);
    }

    // עבור כל release: אילו assets בפועל נדרשים — ה-manifests עצמם, קובצי
    // ה-patch שהם מצביעים עליהם, וה-DB המלא אם קיים. משתמשים ב-Map לפי שם
    // כדי לא להוריד את אותו asset פעמיים אם כמה manifests מצביעים עליו.
    final plannedByRelease = <LibraryRelease, List<ReleaseAsset>>{};
    for (final release in relevant) {
      _throwIfCancelled(isCancelled);
      final needed = <String, ReleaseAsset>{};
      for (final manifestAsset in release.deltaManifestAssets) {
        needed[manifestAsset.name] = manifestAsset;
        try {
          final manifest =
              await _client.fetchManifest(manifestAsset.downloadUrl);
          for (final patchFile in manifest.patchFiles) {
            final asset = release.assetByName(patchFile.file);
            if (asset != null) needed[asset.name] = asset;
          }
        } catch (_) {
          // manifest פגום/חסר — מתעלמים מה-edge הזה, בדיוק כמו
          // LibraryUpdateDiscovery._buildEdge בזרימה הרגילה.
        }
      }
      final full = release.fullDbAsset;
      if (full != null) needed[full.name] = full;
      plannedByRelease[release] = needed.values.toList(growable: false);
    }

    final totalAssets =
        plannedByRelease.values.fold<int>(0, (n, l) => n + l.length);
    var doneAssets = 0;
    // מדווחים את היעד עוד לפני הנכס הראשון: אחרת מד ההתקדמות אינו יודע לכמה
    // נכסים לחכות עד שהראשון (המסד המלא, ~1GB) מסתיים.
    onAssetProgress?.call(0, totalAssets);

    final mirroredReleases = <LibraryRelease>[];
    for (final entry in plannedByRelease.entries) {
      final release = entry.key;
      final tagDir =
          Directory(p.join(assetsRoot.path, _safeDirName(release.tag)));
      await tagDir.create(recursive: true);

      final mirroredAssets = <ReleaseAsset>[];
      for (final asset in entry.value) {
        _throwIfCancelled(isCancelled);
        onStage?.call(strings.exportDownloading(release.tag, asset.name));
        final destFile = File(p.join(tagDir.path, asset.name));
        // נכס שכבר יושב שלם על הדיסק מדלג על ההורדה ורק מאומת — אימות sha256
        // של 1.1GB מכונן נייד לוקח דקה, וללא הכרזה הוא נראה כמו תקיעה.
        var announcedVerify = false;
        await _downloader.downloadToFile(
          url: asset.downloadUrl,
          destPath: destFile.path,
          // ה-manifests נכתבים ע"י GitHub ללא `size` אמין בכל המקרים; `size`
          // של asset אמיתי כן מדויק, ואי-התאמה שלו היא הורדה שנקטעה.
          expectedSize: asset.size > 0 ? asset.size : null,
          expectedSha256: _sha256FromDigest(asset.digest),
          // מזהה ה-asset הוא הזהות היציבה שמאפשרת לחדש הורדה שנקטעה במקום
          // להתחיל מאפס — ראו PatchDownloader.downloadToFile.
          resumeToken: asset.id?.toString(),
          onProgress: onBytesProgress,
          onVerifyProgress: (verified, total) {
            if (!announcedVerify) {
              announcedVerify = true;
              onStage?.call(strings.exportVerifying(release.tag, asset.name));
            }
            onBytesProgress?.call(verified, total);
          },
          isCancelled: isCancelled,
        );
        final relativePath = p.relative(destFile.path, from: destDir);
        mirroredAssets.add(ReleaseAsset(
          name: asset.name,
          downloadUrl: relativePath,
          size: asset.size,
          id: asset.id,
          updatedAt: asset.updatedAt,
          digest: asset.digest,
        ));
        doneAssets++;
        onAssetProgress?.call(doneAssets, totalAssets);
      }

      mirroredReleases.add(LibraryRelease(
        tag: release.tag,
        isPrerelease: release.isPrerelease,
        isDraft: release.isDraft,
        publishedAt: release.publishedAt,
        assets: mirroredAssets,
      ));
    }

    onStage?.call(
      strings.exportWritingManifest(
        LocalMirrorLibraryReleaseClient.manifestFileName,
      ),
    );
    final manifestFile = File(
      p.join(destDir, LocalMirrorLibraryReleaseClient.manifestFileName),
    );
    await manifestFile.writeAsString(jsonEncode({
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'releases': mirroredReleases.map((r) => r.toMirrorJson()).toList(),
    }));

    onStage?.call(strings.exportDone);
  }

  /// ה-release האחרון בלבד, ואיתו — אם הוא עצמו לא נושא `seforim.db.zst` —
  /// ה-release האחרון שכן נושא כזה, כדי שתמיד יהיה מסלול הורדה מלאה במראה.
  ///
  /// היסטוריית ה-patches הישנה **לא** נכללת: היעד הוא כונן נייד, והמראה
  /// המלאה הגיעה לכמה ג'יגה-בייט. מחשב שנמצא כמה גרסאות מאחור ייפול
  /// למסלול ההורדה המלאה, שקיים במראה תמיד.
  List<LibraryRelease> _latestOnly(List<LibraryRelease> eligible) {
    final withDbContent = eligible
        .where((r) => r.deltaManifestAssets.isNotEmpty || r.fullDbAsset != null)
        .toList(growable: false);
    if (withDbContent.isEmpty) return const [];

    LibraryRelease? latest;
    LibraryRelease? latestWithFullDb;
    for (final release in withDbContent) {
      final version = LibraryUpdateDiscovery.releaseVersionOf(release);
      if (latest == null ||
          version > LibraryUpdateDiscovery.releaseVersionOf(latest)) {
        latest = release;
      }
      if (release.fullDbAsset == null) continue;
      if (latestWithFullDb == null ||
          version > LibraryUpdateDiscovery.releaseVersionOf(latestWithFullDb)) {
        latestWithFullDb = release;
      }
    }

    return <LibraryRelease>{
      if (latest != null) latest,
      if (latestWithFullDb != null) latestWithFullDb,
    }.toList(growable: false);
  }

  String _safeDirName(String tag) =>
      tag.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  /// ה-`digest` שמגיע מ-GitHub הוא בצורת `sha256:<hex>`; פורמט אחר (או היעדר
  /// שדה) פירושו "אין hash לאמת מולו", ולא כשל.
  String? _sha256FromDigest(String? digest) {
    const prefix = 'sha256:';
    if (digest == null || !digest.startsWith(prefix)) return null;
    return digest.substring(prefix.length);
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw StateError(AppL10n.strings.libraryDomain.exportCancelled);
    }
  }

  /// סוגר משאבי HTTP פנימיים אם נוצרו על-ידי המחלקה עצמה. ה-[_downloader]
  /// אינו הבעלים של ה-client (הוא הוזרק אליו), ולכן אין לסגור אותו כאן.
  void dispose() {
    if (_ownsClient) _client.dispose();
    if (_ownsHttpClient) _httpClient.close();
  }
}

/// ה-`decompress` ש-[PatchDownloader] דורש. הייצוא מוריד בלבד ואינו מחלץ,
/// ולכן אם מישהו יקרא בעתיד ל-`downloadAndExtract` מכאן — מוטב שייכשל בקול
/// מלהחזיר `null` שיתפרש כ"חילוץ נכשל".
Future<Uint8List?> _neverDecompress(Uint8List _) => throw UnsupportedError(
      AppL10n.strings.libraryDomain.exporterDoesNotExtract,
    );
