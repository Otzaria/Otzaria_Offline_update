import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/library_release.dart';
import 'github_library_release_client.dart';
import 'library_update_discovery.dart';
import 'local_mirror_library_release_client.dart';

/// בונה "מראה" (mirror) מקומית מלאה של כל עדכוני ספריית הספרים מ-GitHub,
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
        _ownsHttpClient = httpClient == null;

  final GithubLibraryReleaseClient _client;
  final bool _ownsClient;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

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

    onStage?.call('טוען רשימת גרסאות מ-GitHub');
    final all = await _client.fetchReleases();
    final eligible = LibraryUpdateDiscovery.eligibleReleases(
      all,
      allowPrerelease: allowPrerelease,
    );
    final relevant = _latestOnly(eligible);

    if (relevant.isEmpty) {
      throw StateError('לא נמצאו releases עם עדכוני DB להורדה.');
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

    final mirroredReleases = <LibraryRelease>[];
    for (final entry in plannedByRelease.entries) {
      final release = entry.key;
      final tagDir =
          Directory(p.join(assetsRoot.path, _safeDirName(release.tag)));
      await tagDir.create(recursive: true);

      final mirroredAssets = <ReleaseAsset>[];
      for (final asset in entry.value) {
        _throwIfCancelled(isCancelled);
        onStage?.call('מוריד ${release.tag} / ${asset.name}');
        final destFile = File(p.join(tagDir.path, asset.name));
        await _downloadToFile(
          asset.downloadUrl,
          destFile,
          onProgress: onBytesProgress,
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

    onStage?.call('כותב ${LocalMirrorLibraryReleaseClient.manifestFileName}');
    final manifestFile = File(
      p.join(destDir, LocalMirrorLibraryReleaseClient.manifestFileName),
    );
    await manifestFile.writeAsString(jsonEncode({
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'releases': mirroredReleases.map((r) => r.toMirrorJson()).toList(),
    }));

    onStage?.call('הושלם');
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

  Future<void> _downloadToFile(
    String url,
    File dest, {
    void Function(int downloaded, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _httpClient.send(request);
    if (response.statusCode != 200) {
      throw StateError('שגיאה בהורדת $url: ${response.statusCode}');
    }
    final total = response.contentLength;
    var downloaded = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in response.stream) {
        _throwIfCancelled(isCancelled);
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress?.call(downloaded, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw StateError('הייצוא בוטל');
    }
  }

  /// סוגר משאבי HTTP פנימיים אם נוצרו על-ידי המחלקה עצמה.
  void dispose() {
    if (_ownsClient) _client.dispose();
    if (_ownsHttpClient) _httpClient.close();
  }
}
