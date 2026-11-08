import 'package:http/http.dart' as http;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// Indexes of [edges] the offline planner picks for any local version; `null`
/// = all of them, or dropping the rest would change some plan's kind or target.
Set<int>? pickedEdges({
  required List<({int from, int to, int bytes})> edges,
  required int fullDbBytes,
  required int fullDbVersion,
  ApplyTimeEstimate applyTime = const ApplyTimeEstimate(),
}) {
  if (edges.isEmpty || fullDbBytes <= 0) return null;
  final patchEdges = [
    for (final (i, e) in edges.indexed)
      PatchEdge(
        manifest: DeltaManifest(
          fromVersion: e.from,
          toVersion: e.to,
          fromSchemaVersion: kSupportedDbSchemaVersion,
          toSchemaVersion: kSupportedDbSchemaVersion,
          fromContentHash: '',
          toContentHash: '',
          patchFiles: [
            PatchFileEntry(
              file: '$i',
              compression: 'zstd',
              sha256: '',
              size: e.bytes,
              uncompressedSha256: '',
              uncompressedSize: 0,
            ),
          ],
        ),
        patchFileUrls: const {},
        manifestUrl: '$i',
      ),
  ];
  var latest = fullDbVersion;
  var lowest = fullDbVersion;
  for (final e in edges) {
    if (e.to > latest) latest = e.to;
    if (e.from < lowest) lowest = e.from;
  }
  final full = ReleaseAsset(name: 'full', downloadUrl: '', size: fullDbBytes);
  final planner = OfflineLibraryUpdatePlanner(applyTime: applyTime);
  LibraryUpdatePlan planFor(int v, bool meta, List<PatchEdge> available) =>
      planner.plan(
        localVersion: v,
        hasLocalVersionMeta: meta,
        latestVersion: latest,
        edges: available,
        latestFullDbAsset: full,
        fullDbReleaseTag: 'full',
        latestFullDbVersion: fullDbVersion,
      );
  List<LibraryUpdatePlan> plansWith(List<PatchEdge> available) => [
    for (var v = lowest > 0 ? lowest - 1 : 0; v < latest; v++)
      planFor(v, true, available),
    planFor(0, false, available),
  ];

  final before = plansWith(patchEdges);
  final picked = <PatchEdge>{};
  void collect(LibraryUpdatePlan? plan) {
    if (plan == null) return;
    picked.addAll(plan.deltaSteps);
    collect(plan.fullDownloadFallback);
    collect(plan.followUpDelta);
  }

  before.forEach(collect);
  if (picked.length == patchEdges.length) return null;

  String outcome(LibraryUpdatePlan p) =>
      '${p.kind.name}>${p.targetVersion}'
      '+${p.followUpDelta?.targetVersion}'
      '|${p.fullDownloadFallback?.targetVersion}';
  final after = plansWith(patchEdges.where(picked.contains).toList());
  for (var i = 0; i < before.length; i++) {
    if (outcome(before[i]) != outcome(after[i])) return null;
  }
  return {
    for (final (i, e) in patchEdges.indexed)
      if (picked.contains(e)) i,
  };
}

bool isAppliableManifest(DeltaManifest manifest) {
  final format = manifest.patchFormatVersion;
  return !manifest.fullRebase &&
      isSupportedSchemaVersion(manifest.fromSchemaVersion) &&
      isSupportedSchemaVersion(manifest.toSchemaVersion) &&
      (format == null || isSupportedPatchFormatVersion(format)) &&
      manifest.hasSupportedCompression;
}

/// [releases] minus the patches no machine would pick beside the newest full
/// DB, and how many assets went; anything uncertain returns them unchanged.
Future<({List<LibraryRelease> releases, int dropped})> pruneUnpickedPatches({
  required List<LibraryRelease> releases,
  required List<LibraryRelease> Function(List<LibraryRelease>) relevantOf,
  required Future<DeltaManifest> Function(String url) fetchManifest,
  required bool Function(LibraryRelease release, ReleaseAsset full) onDrive,
  ApplyTimeEstimate applyTime = const ApplyTimeEstimate(),
}) async {
  final unchanged = (releases: releases, dropped: 0);
  final relevant = relevantOf(releases);
  ReleaseAsset? fullOf(LibraryRelease r) =>
      r.fullDbAssetFor(maxSchemaVersion: kSupportedDbSchemaVersion);
  final carriers = relevant.where((r) => fullOf(r) != null).toList()
    ..sort(
      (a, b) => LibraryUpdateDiscovery.releaseVersionOf(
        b,
      ).compareTo(LibraryUpdateDiscovery.releaseVersionOf(a)),
    );
  if (carriers.isEmpty) return unchanged;
  final newest = carriers.first;
  final full = fullOf(newest)!;
  final newestVersion = LibraryUpdateDiscovery.releaseVersionOf(newest);
  if (full.isSplitFullDbManifest || full.size <= 0) return unchanged;
  // An older full DB already on the drive may be the one the exporter keeps.
  if (!onDrive(newest, full) &&
      carriers.skip(1).any((r) => onDrive(r, fullOf(r)!))) {
    return unchanged;
  }

  final found =
      <
        ({
          LibraryRelease release,
          List<String> names,
          int from,
          int to,
          int bytes,
        })
      >[];
  final listed = [
    for (final release in relevant)
      for (final manifestAsset in release.deltaManifestAssets)
        (release, manifestAsset),
  ];
  final manifests = await Future.wait([
    for (final (_, asset) in listed) fetchManifest(asset.downloadUrl),
  ]);
  final claimed = <(String, String)>{};
  for (final (i, (release, manifestAsset)) in listed.indexed) {
    final manifest = manifests[i];
    if (!isAppliableManifest(manifest)) continue;
    final files = [for (final f in manifest.patchFiles) f.file];
    if (files.any((f) => release.assetByName(f) == null)) continue;
    // A file two edges share would follow whichever the exporter keeps.
    if (!files.every((f) => claimed.add((release.tag, f)))) return unchanged;
    // The exporter drops an edge slower alone than the swap, without credit,
    // once the newest full DB is the carrier; the planner never sees it.
    final assetBytes = [manifestAsset.name, ...files]
        .map((n) => release.assetByName(n)!.size)
        .fold(0, (sum, size) => sum + (size > 0 ? size : 0));
    if (manifest.toVersion <= newestVersion &&
        applyTime.isOutOfRange(
          applyTime.deltaRouteSeconds([assetBytes]),
          applyTime.fullRouteSeconds(full.size),
          savedDownloadBytes: 0,
        )) {
      continue;
    }
    found.add((
      release: release,
      names: [manifestAsset.name, ...files],
      from: manifest.fromVersion,
      to: manifest.toVersion,
      bytes: manifest.totalCompressedSize,
    ));
  }
  final picked = pickedEdges(
    edges: [for (final e in found) (from: e.from, to: e.to, bytes: e.bytes)],
    fullDbBytes: full.size,
    fullDbVersion: newestVersion,
    applyTime: applyTime,
  );
  if (picked == null) return unchanged;

  final keep = {
    for (final (i, e) in found.indexed)
      if (picked.contains(i)) ...e.names.map((n) => (e.release.tag, n)),
  };
  final drop = {
    for (final (i, e) in found.indexed)
      if (!picked.contains(i))
        ...e.names
            .map((n) => (e.release.tag, n))
            .where((k) => !keep.contains(k)),
  };
  final pruned = [
    for (final r in releases)
      LibraryRelease(
        tag: r.tag,
        isPrerelease: r.isPrerelease,
        isDraft: r.isDraft,
        publishedAt: r.publishedAt,
        assets: [
          for (final a in r.assets)
            if (!drop.contains((r.tag, a.name))) a,
        ],
      ),
  ];
  // A release left without content would shift the exporter's selection.
  final before = [for (final r in relevant) r.tag];
  final after = [for (final r in relevantOf(pruned)) r.tag];
  if (before.join('\n') != after.join('\n')) return unchanged;
  return (releases: pruned, dropped: drop.length);
}

class _UnusedHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('PrunedReleasesClient sends through its source');
}

/// A full-mirror export's releases without patches no machine would pick
/// ([pruneUnpickedPatches]); manifests are fetched once and shared.
class PrunedReleasesClient extends GithubLibraryReleaseClient {
  PrunedReleasesClient(
    this._source, {
    required this.allowPrerelease,
    required this.onDrive,
    this.onPruned,
    this.isCancelled,
  }) : super(httpClient: _unused);

  // Every request goes through [_source]; this one only fills the base class.
  static final http.Client _unused = _UnusedHttpClient();

  final GithubLibraryReleaseClient _source;
  final bool allowPrerelease;
  final bool Function(LibraryRelease release, ReleaseAsset full) onDrive;
  final void Function(int assets)? onPruned;
  final bool Function()? isCancelled;

  /// The exporter whose release selection the pruning must keep; set it
  /// before the export starts.
  LibraryMirrorExporter? exporter;

  final Map<String, Future<DeltaManifest>> _manifests = {};
  Future<List<LibraryRelease>>? _releases;

  @override
  Future<List<LibraryRelease>> fetchReleases() => _releases ??= _prune();

  // Only successes stay cached, so the exporter's own retries still retry.
  @override
  Future<DeltaManifest> fetchManifest(String url) => _manifests[url] ??= _source
      .fetchManifest(url)
      .catchError((Object e, StackTrace s) {
        _manifests.remove(url);
        Error.throwWithStackTrace(e, s);
      });

  @override
  Future<ReleaseAsset> resolveSplitAsset(
    LibraryRelease release,
    ReleaseAsset manifestAsset,
  ) => _source.resolveSplitAsset(release, manifestAsset);

  Future<List<LibraryRelease>> _prune() async {
    final releases = await _source.fetchReleases();
    final selector = exporter;
    if (selector == null || (isCancelled?.call() ?? false)) return releases;
    try {
      final result = await pruneUnpickedPatches(
        releases: releases,
        relevantOf: (all) => selector.recentReleases(
          LibraryUpdateDiscovery.eligibleReleases(
            all,
            allowPrerelease: allowPrerelease,
          ),
        ),
        fetchManifest: fetchManifest,
        onDrive: onDrive,
        applyTime: selector.applyTime,
      );
      if (result.dropped > 0) onPruned?.call(result.dropped);
      return result.releases;
    } catch (_) {
      // A manifest that failed is the exporter's to retry and report.
      return releases;
    }
  }
}
