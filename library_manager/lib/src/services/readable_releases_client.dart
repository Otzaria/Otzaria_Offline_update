import 'package:http/http.dart' as http;
import 'package:seforim_library_updater/seforim_library_updater.dart';

class _UnusedHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw StateError('ReadableReleasesClient sends through its source');
}

/// Releases cut to what [readableSchema] reads, before the exporter plans:
/// its own `supportedDbSchemaVersion` limits full DBs only, never patches.
class ReadableReleasesClient extends GithubLibraryReleaseClient {
  ReadableReleasesClient(
    this._source, {
    required this.readableSchema,
    required this.allowPrerelease,
    this.fromVersion,
    this.historyDepth = LibraryMirrorExporter.defaultHistoryDepth,
    DownloadScheduler? scheduler,
    bool Function()? isCancelled,
  }) : _scheduler = scheduler ?? DownloadScheduler(),
       _isCancelled = isCancelled,
       super(httpClient: _unused);

  final DownloadScheduler _scheduler;
  final bool Function()? _isCancelled;

  // Every request goes through [_source]; this one only fills the base class.
  static final http.Client _unused = _UnusedHttpClient();

  final GithubLibraryReleaseClient _source;
  final int readableSchema;
  final bool allowPrerelease;
  final int? fromVersion;
  final int historyDepth;

  final Map<String, Future<DeltaManifest>> _manifests = {};
  Future<List<LibraryRelease>>? _filtered;

  ({int version, LibraryRelease release})? _newestReadable;
  int? _newestUnreadable;
  final Set<String> _unreadable = {};

  /// The newest version a readable full DB or patch delivers, `null` before
  /// [fetchReleases] or when nothing readable is published.
  int? get newestReadableVersion => _newestReadable?.version;

  /// The release carrying [newestReadableVersion]; of a re-publish, the latest.
  String? get newestReadableTag => _newestReadable?.release.tag;

  /// Manifests that could not be parsed: their schema, so whether anything
  /// newer is readable, is unknown.
  Set<String> get unreadableManifests => Set.unmodifiable(_unreadable);

  /// The newest version the launcher could apply but [readableSchema] cannot
  /// read, when it is newer than [newestReadableVersion].
  int? get newerUnreadableVersion {
    final unreadable = _newestUnreadable;
    if (unreadable == null) return null;
    return unreadable > (newestReadableVersion ?? 0) ? unreadable : null;
  }

  @override
  Future<List<LibraryRelease>> fetchReleases() => _filtered ??= _filter();

  @override
  Future<DeltaManifest> fetchManifest(String url) =>
      _manifests[url] ??= _fetchManifest(url);

  @override
  Future<ReleaseAsset> resolveSplitAsset(
    LibraryRelease release,
    ReleaseAsset manifestAsset,
  ) => _source.resolveSplitAsset(release, manifestAsset);

  static const int _manifestAttempts = 3;

  Future<DeltaManifest> _fetchManifest(String url) async {
    for (var attempt = 1; ; attempt++) {
      // Queued tasks and retries start after a cancel too; neither may.
      if (_isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
      try {
        return await _source.fetchManifest(url);
      } on FormatException {
        rethrow;
      } catch (error) {
        if (error is LibraryHttpException && error.isBlockedByFilter) rethrow;
        if (attempt >= _manifestAttempts || (_isCancelled?.call() ?? false)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  Future<DeltaManifest?> _readManifest(ReleaseAsset asset) async {
    try {
      return await fetchManifest(asset.downloadUrl);
    } on FormatException {
      return null;
    }
  }

  List<LibraryRelease> _online = const [];

  /// The unfiltered list [fetchReleases] was cut from.
  List<LibraryRelease> get onlineReleases => _online;

  Future<List<LibraryRelease>> _filter() async {
    final all = _online = await _source.fetchReleases();
    final eligible = OfflineLibraryUpdateDiscovery.eligibleReleases(
      all,
      allowPrerelease: allowPrerelease,
    ).toList()..sort((a, b) => _version(b).compareTo(_version(a)));

    // The exporter keeps [historyDepth] releases (personal: everything above
    // [fromVersion]), so only those need their manifests read.
    final filtered = <LibraryRelease, LibraryRelease>{};
    var withContent = 0;
    var next = 0;
    while (next < eligible.length) {
      if (_isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
      final batch = eligible.sublist(
        next,
        (next + historyDepth).clamp(0, eligible.length),
      );
      next += batch.length;
      final manifests = <ReleaseAsset, DeltaManifest?>{};
      final assets = [for (final r in batch) ...r.deltaManifestAssets];
      final read = await _scheduler.run<DeltaManifest?>([
        for (final asset in assets) () => _readManifest(asset),
      ]);
      for (final (i, asset) in assets.indexed) {
        manifests[asset] = read[i];
      }
      for (final release in batch) {
        final readable = _readable(release, manifests);
        filtered[release] = readable;
        if (_hasContent(readable)) withContent++;
      }
      final last = _version(batch.last);
      if (withContent >= historyDepth &&
          (fromVersion == null || last <= fromVersion!) &&
          (next >= eligible.length || _version(eligible[next]) < last)) {
        break;
      }
    }
    for (final release in eligible.skip(next)) {
      filtered[release] = _readable(release, const {});
    }

    // A release emptied above the newest readable one would still count as
    // "latest" in the exporter's personal mode.
    final newest = newestReadableVersion ?? 0;
    // Newest re-publish first: the exporter keeps the first carrier of a tied
    // version, and the corrected one is what the drive must get.
    return [
      for (final release in all)
        if (filtered[release] case final readable?) ...[
          if (_hasContent(readable) || _version(readable) <= newest) readable,
        ] else
          release,
    ]..sort((a, b) {
      final byVersion = _version(b).compareTo(_version(a));
      if (byVersion != 0) return byVersion;
      return _publishedAfter(a, b) ? -1 : (_publishedAfter(b, a) ? 1 : 0);
    });
  }

  /// [manifests] maps each manifest read to its content, or to `null` when it
  /// could not be parsed; a manifest not read has an unknown schema.
  LibraryRelease _readable(
    LibraryRelease release,
    Map<ReleaseAsset, DeltaManifest?> manifests,
  ) {
    final version = _version(release);
    final kept = <ReleaseAsset>[];
    var progress = false;
    for (final asset in release.assets) {
      if (asset.isFullDbArchive || asset.isSplitFullDbManifest) {
        final schema = ReleaseAsset.fullDbSchemaOfName(
          asset.splitArchiveName ?? asset.name,
        )!;
        if (schema <= readableSchema) {
          kept.add(asset);
          progress |= asset.size > 0;
        } else if (asset.size > 0 && isSupportedSchemaVersion(schema)) {
          _sawUnreadable(version);
        }
        continue;
      }
      if (asset.isDeltaManifest) {
        if (!manifests.containsKey(asset)) continue;
        final manifest = manifests[asset];
        // Kept as the exporter keeps it, so the version is not lost; it
        // proves nothing either way, which the outcome must say.
        if (manifest == null) {
          kept.add(asset);
          _unreadable.add(asset.name);
          continue;
        }
        if (manifest.fromSchemaVersion <= readableSchema &&
            manifest.toSchemaVersion <= readableSchema) {
          kept.add(asset);
          // A barrier stays for the planner but leads nowhere by itself.
          progress |= !manifest.fullRebase;
        } else if (!manifest.fullRebase &&
            isSupportedSchemaVersion(manifest.fromSchemaVersion) &&
            isSupportedSchemaVersion(manifest.toSchemaVersion)) {
          _sawUnreadable(manifest.toVersion);
        }
        continue;
      }
      kept.add(asset);
    }
    final readable = LibraryRelease(
      tag: release.tag,
      isPrerelease: release.isPrerelease,
      isDraft: release.isDraft,
      publishedAt: release.publishedAt,
      assets: kept,
    );
    if (progress) {
      final newest = _newestReadable;
      if (newest == null ||
          version > newest.version ||
          (version == newest.version &&
              _publishedAfter(release, newest.release))) {
        _newestReadable = (version: version, release: release);
      }
    }
    return readable;
  }

  static bool _publishedAfter(LibraryRelease a, LibraryRelease b) {
    final at = a.publishedAt;
    final bt = b.publishedAt;
    return at != null && (bt == null || at.isAfter(bt));
  }

  void _sawUnreadable(int version) {
    if (version > (_newestUnreadable ?? 0)) _newestUnreadable = version;
  }

  bool _hasContent(LibraryRelease release) =>
      release.deltaManifestAssets.isNotEmpty ||
      release.fullDbAssetFor(maxSchemaVersion: readableSchema) != null;

  static int _version(LibraryRelease release) =>
      OfflineLibraryUpdateDiscovery.releaseVersionOf(release);
}
