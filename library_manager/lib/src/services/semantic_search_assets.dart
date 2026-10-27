import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'atomic_file.dart' show writeStringAtomically;
import 'download_connections.dart';
import 'github_fetch.dart';
import 'semantic_vectors_plan.dart';

export 'semantic_vectors_plan.dart';

typedef SemanticAsset = ({String name, int size, String sha256});

/// The installed set is not where the drive's delta chain continues from;
/// only a full smart-search download on the online machine helps.
class SemanticChainNotApplicableException implements Exception {
  const SemanticChainNotApplicableException();

  @override
  String toString() => AppL10n.strings.libraryDomain.semanticFullDownloadNeeded;
}

/// A vector set as its `CURRENT`/`PREVIOUS` pointer files describe it.
class SemanticInstalledSet {
  const SemanticInstalledSet({
    required this.libraryVersion,
    required this.libraryReleaseTag,
    required this.identityDigest,
    required this.windows,
  });

  final int libraryVersion;
  final String libraryReleaseTag;
  final String identityDigest;

  /// `.otzaria-windows-identity` names this set, as Otzaria requires.
  final bool windows;
}

typedef SemanticEngineInfo = ({
  bool present,
  int libraryVersion,
  String identityDigest,
});

/// The engine calls an install needs; a seam so tests run without the
/// native library.
abstract interface class SemanticVectorsEngine {
  Future<SemanticEngineInfo> info(String vectorsDir);

  Future<({int libraryVersion, bool alreadyApplied})> install(
    SemanticVectorsInstallInput input, {
    bool Function()? isCancelled,
  });

  Future<void> compact(String vectorsDir, {bool Function()? isCancelled});

  void dispose();
}

typedef SemanticEngineFactory =
    Future<SemanticVectorsEngine> Function(String workDir);

class _HttpFailure extends FormatException {
  const _HttpFailure(super.message);
}

/// A published release that cannot be installed: re-fetching will not help.
typedef _Release = ({
  String releaseTag,
  Map<String, Map> assets,
  Map manifest,
  String digest,
});

class _Unusable extends FormatException {
  const _Unusable(super.message);
}

class _Remote {
  _Remote({
    required this.releaseTag,
    required this.libraryTag,
    required this.from,
    required this.to,
    required this.manifestName,
    required this.manifestBytes,
    required this.manifestSha256,
    required this.files,
    required this.urls,
    required this.identityDigest,
  });

  final String releaseTag;
  final String libraryTag;
  final int from;
  final int to;
  final String manifestName;
  final List<int> manifestBytes;
  final String manifestSha256;
  final List<SemanticAsset> files;
  final Map<String, String> urls;
  final String identityDigest;

  int get downloadSize => files.fold(0, (sum, file) => sum + file.size);

  SemanticAsset get manifest =>
      (name: manifestName, size: manifestBytes.length, sha256: manifestSha256);
}

class _Step {
  const _Step({
    required this.releaseTag,
    required this.libraryTag,
    required this.from,
    required this.to,
    required this.manifest,
  });

  final String releaseTag;
  final String libraryTag;
  final int from;
  final int to;
  final SemanticAsset manifest;

  Map<String, Object?> toJson() => {
    'releaseTag': releaseTag,
    'libraryTag': libraryTag,
    'from': from,
    'to': to,
    'name': manifest.name,
    'size': manifest.size,
    'sha256': manifest.sha256,
  };
}

/// `semantic.json`: what the mirror holds for one library tag.
class _Meta {
  const _Meta({
    required this.family,
    required this.chain,
    required this.libraryTag,
    required this.libraryVersion,
    required this.base,
    this.identityDigest = '',
    this.steps = const [],
    this.rejectedWindowsManifest,
  });

  final SemanticVectorsFamily family;

  /// Only the [steps] are mirrored; [base] is the target base they lead to.
  final bool chain;
  final String libraryTag;
  final int libraryVersion;
  final SemanticAsset base;
  final String identityDigest;
  final List<_Step> steps;

  /// The digest of a windows manifest found unusable, so the light check does
  /// not keep asking for it.
  final String? rejectedWindowsManifest;

  bool get windows => family == SemanticVectorsFamily.windows;

  List<({int from, int to})> get stepRange => [
    for (final step in steps) (from: step.from, to: step.to),
  ];

  List<_Step> get units => chain
      ? steps
      : [
          _Step(
            releaseTag: '${family.releaseTagPrefix}$libraryTag',
            libraryTag: libraryTag,
            from: 0,
            to: libraryVersion,
            manifest: base,
          ),
        ];

  // Old launchers read only the top-level legacy fields, so a windows mirror
  // omits them and stays invisible to a launcher that cannot install it.
  Map<String, Object?> toJson() => windows
      ? {
          'family': family.id,
          'kind': chain ? 'chain' : 'base',
          'libraryTag': libraryTag,
          'libraryVersion': libraryVersion,
          'identityDigest': identityDigest,
          'base': {'name': base.name, 'size': base.size, 'sha256': base.sha256},
          'steps': [for (final step in steps) step.toJson()],
        }
      : {
          'family': family.id,
          'kind': 'base',
          'libraryTag': libraryTag,
          'libraryVersion': libraryVersion,
          'manifestName': base.name,
          'manifestSize': base.size,
          'manifestSha256': base.sha256,
          'rejectedWindowsManifest': ?rejectedWindowsManifest,
        };
}

class _LoadedUnit {
  const _LoadedUnit({
    required this.step,
    required this.files,
    required this.segmentSize,
  });

  final _Step step;
  final List<SemanticAsset> files;
  final int segmentSize;

  bool get isDelta => step.from > 0;
}

class SemanticSearchAssets {
  SemanticSearchAssets({
    http.Client? httpClient,
    ExternalLibrary? nativeLibrary,
    DownloadScheduler? scheduler,
    int? Function(String)? freeBytesFor,
    SemanticEngineFactory? engineFactory,
    @visibleForTesting List<SemanticAsset>? models,
  }) : _injectedClient = httpClient,
       _nativeLibrary = nativeLibrary,
       _scheduler = scheduler ?? DownloadScheduler(),
       _freeBytesFor = freeBytesFor ?? DiskSpaceProbe.freeBytesFor,
       _engineFactory = engineFactory,
       _models = models ?? modelFiles,
       _ownsClient = httpClient == null;

  final http.Client? _injectedClient;
  http.Client? _createdClient;
  http.Client get _client =>
      _injectedClient ?? (_createdClient ??= http.Client());
  Duration timeout = const Duration(seconds: 30);
  Duration stallTimeout = const Duration(minutes: 5);
  final DownloadScheduler _scheduler;
  final int? Function(String) _freeBytesFor;
  final bool _ownsClient;
  final ExternalLibrary? _nativeLibrary;
  final SemanticEngineFactory? _engineFactory;
  final List<SemanticAsset> _models;
  static const manifestFileName = 'semantic.json';
  static const modelFolder = 'meivin-round2-onnx';
  static const windowsIdentityFileName = '.otzaria-windows-identity';
  static const modelBaseUrl =
      'https://github.com/Otzaria/otzaria-semantic-search/releases/download/model-meivin-round2-int8-v1';
  static const modelFiles = <SemanticAsset>[
    (
      name: 'seforim-embed-round2-int8.onnx',
      size: 42489219,
      sha256:
          '659226865abd3a1bc833565ae6b2e2f48abdd7136285824a12966d4d3294cbf8',
    ),
    (
      name: 'tokenizer.json',
      size: 2191362,
      sha256:
          '0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9',
    ),
    (
      name: 'model.json',
      size: 656,
      sha256:
          'a27b103ea5dc50be674e6e6696d8f8ea09639ac3808cd1a48dcf2d70a0b47d1c',
    ),
    (
      name: 'LICENSE',
      size: 3992,
      sha256:
          '92267258dabd9077849cc5ab63a5b0b0b3ca9849e1112fd0d13d9691df7e0739',
    ),
  ];
  static const tokenizerZip = (
    name: 'tokenizer.json.zip',
    size: 445252,
    sha256: '07353eea8a9e5036f5a50691424b7818fa7768a3f5220a8daf8505f4b8bd3da0',
  );

  String get _name => AppL10n.strings.libraryDomain.companionSemanticName;
  Never _invalid() => throw FormatException(
    AppL10n.strings.libraryDomain.companionAssetMissingInRelease(_name),
  );

  Never _httpFailure(int status) => throw _HttpFailure(
    AppL10n.strings.libraryDomain.companionAssetHttpFailure(_name, status),
  );

  void dispose() {
    if (_ownsClient) _createdClient?.close();
  }

  static void _cancel(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
  }

  static bool _plain(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(name);

  static bool _sha(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static final _deltaManifest = RegExp(r'-v(\d+)-v(\d+)\.manifest\.json$');

  Uri _url(Object? value, String releaseTag) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.pathSegments.length != 6 ||
        uri.pathSegments.take(5).join('/') !=
            'Otzaria/SeforimLibrary/releases/download/$releaseTag' ||
        !_plain(uri.pathSegments.last)) {
      _invalid();
    }
    return uri;
  }

  String _publishedManifestSha(Map asset, Object? releaseBody) {
    final name = asset['name'] as String;
    final body = releaseBody is String ? releaseBody.toLowerCase() : '';
    final at = body.indexOf(name.toLowerCase());
    final hashes = RegExp(r'\b[0-9a-f]{64}\b');
    final all = hashes.allMatches(body).map((match) => match.group(0)!).toSet();
    final after = at >= 0
        ? hashes.firstMatch(body.substring(at + name.length))?.group(0)
        : null;
    final notes = after ?? (all.length == 1 ? all.single : null);
    final assetDigest = asset['digest'];
    final digest = assetDigest is String && assetDigest.startsWith('sha256:')
        ? assetDigest.substring(7).toLowerCase()
        : null;
    if ((notes == null && digest == null) ||
        (digest != null && !_sha(digest)) ||
        (notes != null && digest != null && notes != digest)) {
      _invalid();
    }
    return notes ?? digest!;
  }

  int _version(String libraryTag) => _tagVersion(libraryTag) ?? _invalid();

  Future<_Release?> _fetchRelease(
    String releaseTag, {
    bool delta = false,
  }) async {
    final response = await githubGet(
      _client,
      Uri.parse(
        'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/tags/$releaseTag',
      ),
      timeout: timeout,
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      _httpFailure(response.statusCode);
    }
    final Object? release;
    try {
      release = decodeGithubJson(response);
    } on FormatException {
      // A cut-off API reply is a transfer fault, not an unpublished release.
      throw _HttpFailure(
        AppL10n.strings.libraryDomain.companionAssetMissingInRelease(_name),
      );
    }
    if (release is! Map ||
        release['tag_name'] != releaseTag ||
        release['assets'] is! List) {
      _invalid();
    }
    final manifests = <Map>[];
    final assets = <String, Map>{};
    for (final asset in release['assets'] as List) {
      if (asset is! Map ||
          asset['name'] is! String ||
          !_plain(asset['name'] as String) ||
          asset['size'] is! int ||
          (asset['size'] as int) < 0 ||
          assets.containsKey(asset['name'])) {
        _invalid();
      }
      final name = asset['name'] as String;
      assets[name] = asset;
      if (name.startsWith('otzaria-vectors-') &&
          name.endsWith('.manifest.json')) {
        manifests.add(asset);
      }
    }
    if (manifests.length != 1 ||
        (delta &&
            !_deltaManifest.hasMatch(manifests.single['name'] as String))) {
      _invalid();
    }
    final manifest = manifests.single;
    return (
      releaseTag: releaseTag,
      assets: assets,
      manifest: manifest,
      digest: _publishedManifestSha(manifest, release['body']),
    );
  }

  Map _publishedAsset(Map<String, Map> assets, SemanticAsset file) {
    final asset = assets[file.name];
    if (asset == null || asset['size'] != file.size) {
      _invalid();
    }
    final published = asset['digest'];
    if (published is String &&
        published.startsWith('sha256:') &&
        published.substring(7).toLowerCase() != file.sha256) {
      _invalid();
    }
    return asset;
  }

  /// Downloads and verifies the manifest of [release].
  Future<_Remote> _remote(
    _Release release, {
    required String libraryTag,
    required int version,
    required SemanticVectorsFamily family,
    bool delta = false,
    bool Function()? isCancelled,
  }) async {
    _cancel(isCancelled);
    final manifestAsset = release.manifest;
    final response = await githubGet(
      _client,
      _url(manifestAsset['browser_download_url'], release.releaseTag),
      timeout: timeout,
      headers: githubUserAgentHeaders,
    );
    if (response.statusCode != 200) {
      _httpFailure(response.statusCode);
    }
    final bytes = response.bodyBytes;
    if (manifestAsset['size'] != bytes.length) {
      // A short body is a transfer fault: retrying beats a multi-GB base.
      throw _HttpFailure(
        AppL10n.strings.libraryDomain.companionAssetMissingInRelease(_name),
      );
    }
    final digest = Sha256Stream.ofBytes(bytes);
    if (release.digest != digest) {
      _invalid();
    }
    // The bytes are the published ones now, so any fault below is the release's.
    try {
      return _remoteOf(
        release,
        bytes,
        digest,
        libraryTag,
        version,
        family,
        delta,
      );
    } on FormatException catch (error) {
      throw _Unusable(error.message);
    }
  }

  _Remote _remoteOf(
    _Release release,
    List<int> bytes,
    String digest,
    String libraryTag,
    int version,
    SemanticVectorsFamily family,
    bool delta,
  ) {
    final manifestName = release.manifest['name'] as String;
    final Object? manifest;
    try {
      manifest = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      _invalid();
    }
    final parsed = _vectors(
      manifest,
      tag: libraryTag,
      version: version,
      family: family,
      deltaName: delta ? manifestName : null,
    );
    return _Remote(
      releaseTag: release.releaseTag,
      libraryTag: libraryTag,
      from: parsed.from,
      to: version,
      manifestName: manifestName,
      manifestBytes: bytes,
      manifestSha256: digest,
      files: parsed.files,
      urls: {
        for (final file in parsed.files)
          file.name: _url(
            _publishedAsset(release.assets, file)['browser_download_url'],
            release.releaseTag,
          ).toString(),
      },
      identityDigest: parsed.identityDigest,
    );
  }

  /// The deltas from [start] up to [target], oldest first; `null` when the
  /// base is the better download. Network failures are thrown, not hidden.
  Future<List<_Remote>?> _deltaChain(
    _Remote target,
    int start,
    String? Function(int version) libraryTagFor,
    bool Function()? isCancelled,
  ) async {
    const family = SemanticVectorsFamily.windows;
    final maxBytes =
        target.downloadSize * kSemanticDeltaChainLimits.maxBaseSizeRatio;
    final chain = <_Remote>[];
    String? tag = target.libraryTag;
    var to = target.to;
    var bytes = 0;
    try {
      while (to > start) {
        if (tag == null || chain.length >= kSemanticDeltaChainLimits.maxSteps) {
          return null;
        }
        final release = await _fetchRelease(
          '${family.deltaReleaseTagPrefix}$tag',
          delta: true,
        );
        if (release == null) return null;
        final step = await _remote(
          release,
          libraryTag: tag,
          version: to,
          family: family,
          isCancelled: isCancelled,
          delta: true,
        );
        if (step.identityDigest != target.identityDigest || step.from < start) {
          return null;
        }
        bytes += step.downloadSize;
        if (bytes > maxBytes) return null;
        chain.insert(0, step);
        to = step.from;
        if (to > start) tag = libraryTagFor(to);
      }
      return chain;
    } on _HttpFailure {
      rethrow;
    } on FormatException {
      return null;
    }
  }

  /// What to mirror for [libraryTag]: `null` when no vectors were published.
  Future<({_Meta meta, List<_Remote> remotes})?> _plan(
    String libraryTag,
    int version,
    SemanticFleet fleet,
    String? Function(int version) libraryTagFor,
    bool Function()? isCancelled,
  ) async {
    String? rejectedWindows;
    _Unusable? windowsFault;
    if (fleet.family == SemanticVectorsFamily.windows) {
      const family = SemanticVectorsFamily.windows;
      final release = await _windowsRelease(libraryTag);
      _Remote? base;
      if (release != null) {
        try {
          base = await _remote(
            release,
            libraryTag: libraryTag,
            version: version,
            family: family,
            isCancelled: isCancelled,
          );
        } on _Unusable catch (fault) {
          rejectedWindows = _rejectionKey(release);
          windowsFault = fault;
        }
      }
      if (base != null) {
        final start = fleet.chainStartFor(base.identityDigest);
        if (start != null) {
          final chain = start >= version
              ? <_Remote>[]
              : await _deltaChain(base, start, libraryTagFor, isCancelled);
          if (chain != null) {
            final meta = _metaOf(family, base, chain: chain);
            if (fleet.canApply(meta.stepRange, version)) {
              return (meta: meta, remotes: chain);
            }
          }
        }
        return (meta: _metaOf(family, base), remotes: [base]);
      }
    }
    const family = SemanticVectorsFamily.legacy;
    final release = await _fetchRelease(
      '${family.releaseTagPrefix}$libraryTag',
    );
    if (release == null) {
      if (windowsFault != null) throw windowsFault;
      return null;
    }
    final base = await _remote(
      release,
      libraryTag: libraryTag,
      version: version,
      family: family,
      isCancelled: isCancelled,
    );
    return (
      meta: _metaOf(family, base, rejectedWindows: rejectedWindows),
      remotes: [base],
    );
  }

  /// Names a release's manifest and assets, so a release whose upload
  /// finished later is judged again.
  static String _rejectionKey(_Release release) => Sha256Stream.ofBytes(
    utf8.encode(
      [
        release.digest,
        for (final MapEntry(:key, :value) in release.assets.entries)
          '$key:${value['size']}:${value['state']}',
      ].join('|'),
    ),
  );

  /// The windows base release; an unusable one counts as unpublished.
  Future<_Release?> _windowsRelease(String libraryTag) async {
    try {
      return await _fetchRelease(
        '${SemanticVectorsFamily.windows.releaseTagPrefix}$libraryTag',
      );
    } on _HttpFailure {
      rethrow;
    } on FormatException {
      return null;
    }
  }

  _Meta _metaOf(
    SemanticVectorsFamily family,
    _Remote base, {
    List<_Remote>? chain,
    String? rejectedWindows,
  }) => _Meta(
    family: family,
    chain: chain != null,
    libraryTag: base.libraryTag,
    libraryVersion: base.to,
    base: base.manifest,
    rejectedWindowsManifest: rejectedWindows,
    identityDigest: base.identityDigest,
    steps: [
      for (final step in chain ?? const <_Remote>[])
        _Step(
          releaseTag: step.releaseTag,
          libraryTag: step.libraryTag,
          from: step.from,
          to: step.to,
          manifest: step.manifest,
        ),
    ],
  );

  /// חסם עליון למה ש-[sync] יוריד לפי [peekPending] האחרון: כל נכסי ה-release
  /// וכל קובצי המודל. `null` כשההצצה לא הצליחה.
  int? get peekedPendingBytes => _peekedPendingBytes;
  int? _peekedPendingBytes;

  static final int _modelDownloadBytes = [
    for (final file in modelFiles)
      file.name == 'tokenizer.json' ? tokenizerZip : file,
  ].fold<int>(0, (sum, file) => sum + file.size);

  Future<bool> peekPending({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
  }) async {
    _peekedPendingBytes = null;
    for (final group in fleet.groups) {
      if (await _peekPending(mirrorDir, libraryTag, group)) {
        if (fleet.groups.length != 1) _peekedPendingBytes = null;
        return true;
      }
    }
    _peekedPendingBytes = 0;
    return false;
  }

  Future<bool> _peekPending(
    String mirrorDir,
    String libraryTag,
    SemanticFleet fleet,
  ) async {
    final version = _version(libraryTag);
    if (fleet.family == SemanticVectorsFamily.windows) {
      final release = await _windowsRelease(libraryTag);
      final local = await _metadata(mirrorDir);
      final rejected =
          local != null &&
          !local.windows &&
          local.libraryTag == libraryTag &&
          release != null &&
          local.rejectedWindowsManifest == _rejectionKey(release);
      if (release != null && !rejected) {
        return !await _windowsMirrorServes(
          mirrorDir,
          libraryTag,
          version,
          release,
          fleet,
        );
      }
    }
    final fetched = await _fetchRelease(
      '${SemanticVectorsFamily.legacy.releaseTagPrefix}$libraryTag',
    );
    if (fetched == null) return false;
    final remote = fetched.manifest;
    final local = await _load(mirrorDir, version);
    if (local == null ||
        local.meta.windows ||
        local.meta.libraryTag != libraryTag ||
        local.meta.base.name != remote['name'] ||
        local.meta.base.size != remote['size'] ||
        local.meta.base.sha256 != fetched.digest) {
      _peekedPendingBytes = fetched.assets.values.fold<int>(
        _modelDownloadBytes,
        (sum, asset) => sum + (asset['size'] as int),
      );
      return true;
    }
    for (final file in local.units.single.files) {
      _publishedAsset(fetched.assets, file);
    }
    _peekedPendingBytes = 0;
    return false;
  }

  Future<bool> _windowsMirrorServes(
    String mirrorDir,
    String libraryTag,
    int version,
    _Release release,
    SemanticFleet fleet,
  ) async {
    final local = await _load(mirrorDir, version, preferWindows: true);
    final meta = local?.meta;
    if (local == null ||
        meta == null ||
        !meta.windows ||
        meta.libraryTag != libraryTag ||
        meta.base.name != release.manifest['name'] ||
        meta.base.size != release.manifest['size'] ||
        meta.base.sha256 != release.digest) {
      return false;
    }
    if (!meta.chain) {
      for (final file in local.units.single.files) {
        _publishedAsset(release.assets, file);
      }
      return true;
    }
    return fleet.chainStartFor(meta.identityDigest) != null &&
        fleet.canApply(meta.stepRange, version);
  }

  Future<void> sync({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
    String? Function(int version)? libraryTagFor,
    void Function(String)? onStage,
    void Function(int, int?)? onBytesProgress,
    bool Function()? isCancelled,
  }) async {
    _cancel(isCancelled);
    final version = _version(libraryTag);
    onStage?.call(AppL10n.strings.libraryDomain.semanticDownloading);
    final plans = <SemanticVectorsFamily, _Meta>{};
    final remotes = <String, _Remote>{};
    for (final group in fleet.groups) {
      final plan = await _plan(
        libraryTag,
        version,
        group,
        libraryTagFor ?? (_) => null,
        isCancelled,
      );
      _cancel(isCancelled);
      if (plan == null) _httpFailure(HttpStatus.notFound);
      plans[plan.meta.family] = plan.meta;
      for (final remote in plan.remotes) {
        remotes[remote.releaseTag] = remote;
      }
    }
    final metadata = plans.values.first.toJson();
    // Older launchers must still find the legacy fields at the top level.
    if (plans.length > 1) {
      metadata['windows'] = plans[SemanticVectorsFamily.windows]!.toJson();
    }
    final generation = p.join(mirrorDir, libraryTag);
    final reused = <String, String>{};
    for (final file in _models) {
      final source = await reusableModelSource(
        mirrorDir: mirrorDir,
        libraryTag: libraryTag,
        file: file,
        isCancelled: isCancelled,
      );
      if (source != null) reused[file.name] = source;
    }
    final downloadModels = [
      for (final file in _models)
        if (!reused.containsKey(file.name))
          file.name == 'tokenizer.json' ? tokenizerZip : file,
    ];
    final vectorFiles = [
      for (final remote in remotes.values)
        for (final file in remote.files)
          (file: file, url: remote.urls[file.name]!),
    ];
    final progress = ByteProgressAggregator(
      totalBytes: [
        ...downloadModels,
        for (final vector in vectorFiles) vector.file,
      ].fold<int>(0, (sum, file) => sum + file.size),
      onProgress: onBytesProgress,
    );
    final jobs = <({SemanticAsset file, String url, String dest})>[
      for (final file in downloadModels)
        (
          file: file,
          url: '$modelBaseUrl/${file.name}',
          dest: p.join(generation, modelFolder, file.name),
        ),
      for (final vector in vectorFiles)
        (
          file: vector.file,
          url: vector.url,
          dest: p.join(generation, 'vectors', vector.file.name),
        ),
    ]..sort((a, b) => b.file.size.compareTo(a.file.size));
    final slots = <ByteProgressSlot>[];
    for (final job in jobs) {
      final existing = await _completeLength(job.dest, job.file.size);
      slots.add(progress.slot(existingBytes: existing));
    }
    progress.announce();
    final downloader = newDownloader();
    try {
      _cancel(isCancelled);
      await Directory(p.join(generation, modelFolder)).create(recursive: true);
      await Directory(p.join(generation, 'vectors')).create(recursive: true);
      for (final entry in reused.entries) {
        final target = p.join(generation, modelFolder, entry.key);
        if (p.equals(entry.value, target)) continue;
        _cancel(isCancelled);
        final temporary = '$target.tmp';
        await File(entry.value).copy(temporary);
        await File(temporary).rename(target);
      }
      await _scheduler.run<void>([
        for (final (index, job) in jobs.indexed)
          () async {
            _cancel(isCancelled);
            final slot = slots[index];
            await downloader.downloadToFile(
              url: job.url,
              destPath: job.dest,
              expectedSize: job.file.size,
              expectedSha256: job.file.sha256,
              resumeToken: job.file.sha256,
              onProgress: slot.report,
              onExistingBytes: slot.markExisting,
              isCancelled: isCancelled,
            );
            if (job.file.name == tokenizerZip.name) {
              await _extractTokenizer(job.dest, isCancelled);
            }
          },
      ]);
      for (final remote in remotes.values) {
        _cancel(isCancelled);
        await File(
          p.join(generation, 'vectors', remote.manifestName),
        ).writeAsBytes(remote.manifestBytes, flush: true);
      }
      _cancel(isCancelled);
      await writeStringAtomically(
        p.join(mirrorDir, manifestFileName),
        jsonEncode(metadata),
      );
      await pruneOldGenerations(mirrorDir, libraryTag);
      await _pruneUnplanned(p.join(generation, 'vectors'), {
        for (final remote in remotes.values) ...[
          remote.manifestName,
          for (final file in remote.files) file.name,
        ],
      });
    } finally {
      downloader.dispose();
    }
  }

  /// Deletes what a previous plan for the same tag left in [dir]; the files
  /// of [keep], their download sidecars and every `.lock` stay.
  static final _sidecar = RegExp(r'^(resume|segments|seg-\d+)$');

  Future<void> _pruneUnplanned(String dir, Set<String> keep) async {
    try {
      await for (final entry in Directory(dir).list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (entry is! File ||
            p.extension(name).toLowerCase() == '.lock' ||
            keep.any(
              (k) =>
                  name == k ||
                  (name.startsWith('$k.') &&
                      _sidecar.hasMatch(name.substring(k.length + 1))),
            )) {
          continue;
        }
        try {
          await entry.delete();
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return;
    }
  }

  @visibleForTesting
  PatchDownloader newDownloader() => PatchDownloader(
    httpClient: _client,
    decompress: (_) async => null,
    stallTimeout: stallTimeout,
    maxConnections: connectionsPerFile(_scheduler),
  );

  Future<int> _completeLength(String path, int expectedSize) async {
    try {
      final file = File(path);
      if (!await file.exists()) return 0;
      return await file.length() >= expectedSize ? expectedSize : 0;
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> _extractTokenizer(
    String zipPath,
    bool Function()? isCancelled,
  ) async {
    _cancel(isCancelled);
    final zipped = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    if (zipped.files.length != 1 ||
        zipped.files.single.name != 'tokenizer.json' ||
        !zipped.files.single.isFile ||
        zipped.files.single.size != modelFiles[1].size) {
      _invalid();
    }
    final bytes = zipped.files.single.content;
    if (Sha256Stream.ofBytes(bytes) != modelFiles[1].sha256) {
      _invalid();
    }
    final target = File(p.join(p.dirname(zipPath), 'tokenizer.json'));
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    _cancel(isCancelled);
    await temporary.rename(target.path);
  }

  static final _generationName = _libraryTag;
  Future<String?> reusableModelSource({
    required String mirrorDir,
    required String libraryTag,
    required SemanticAsset file,
    bool Function()? isCancelled,
  }) async {
    final root = Directory(mirrorDir);
    if (!await root.exists()) return null;
    final names = <String>[libraryTag];
    await for (final entry in root.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is Directory &&
          name != libraryTag &&
          _generationName.hasMatch(name)) {
        names.add(name);
      }
    }
    for (final name in names) {
      final path = p.join(mirrorDir, name, modelFolder, file.name);
      if (await _matches(path, file, isCancelled)) return path;
    }
    return null;
  }

  Future<void> pruneOldGenerations(String mirrorDir, String keepTag) async {
    try {
      await for (final entry in Directory(mirrorDir).list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (entry is! Directory ||
            name == keepTag ||
            !_generationName.hasMatch(name)) {
          continue;
        }
        try {
          await _pruneGeneration(entry);
        } on FileSystemException {
          continue;
        }
      }
    } on FileSystemException {
      return;
    }
  }

  // Retain lock inodes even after their generation leaves the manifest.
  Future<void> _pruneGeneration(Directory dir) async {
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is Directory) {
        await _pruneGeneration(entry);
      } else if (p.extension(entry.path).toLowerCase() != '.lock') {
        await entry.delete();
      }
    }
    if (await dir.list(followLinks: false).isEmpty) await dir.delete();
  }

  ({
    List<SemanticAsset> files,
    int segmentSize,
    int from,
    String identityDigest,
  })
  _vectors(
    Object? manifest, {
    required String tag,
    required int version,
    required SemanticVectorsFamily family,
    String? deltaName,
  }) {
    if (manifest is! Map ||
        manifest['kind'] != (deltaName == null ? 'base' : 'delta') ||
        manifest['toLibraryVersion'] != version ||
        manifest['libraryReleaseTag'] != tag ||
        manifest['files'] is! List ||
        manifest['segment'] is! Map ||
        (manifest['segment'] as Map)['size'] is! int ||
        ((manifest['segment'] as Map)['size'] as int) < 0) {
      _invalid();
    }
    var from = 0;
    if (deltaName != null) {
      final named = _deltaManifest.firstMatch(deltaName);
      final declared = manifest['fromLibraryVersion'];
      if (named == null ||
          declared is! int ||
          declared <= 0 ||
          declared >= version ||
          int.parse(named.group(1)!) != declared ||
          int.parse(named.group(2)!) != version) {
        _invalid();
      }
      from = declared;
    }
    final files = <SemanticAsset>[];
    for (final entry in manifest['files'] as List) {
      if (entry is! Map ||
          entry['file'] is! String ||
          entry['size'] is! int ||
          entry['sha256'] is! String) {
        _invalid();
      }
      final name = entry['file'] as String;
      final size = entry['size'] as int;
      final sha = (entry['sha256'] as String).toLowerCase();
      if (!_plain(name) ||
          size < 0 ||
          !_sha(sha) ||
          files.any((f) => f.name == name)) {
        _invalid();
      }
      files.add((name: name, size: size, sha256: sha));
    }
    if (files.isEmpty) {
      _invalid();
    }
    final identity = manifest['identity'];
    final model = identity is Map ? identity['model'] : null;
    final text = identity is Map ? identity['text'] : null;
    final lineText = text is Map ? text['line_text_version'] : null;
    if (model is! Map ||
        (lineText != null && lineText != kSemanticLineTextVersion) ||
        model['family_id'] !=
            'ArieLLL123/judaic-semantic-round2-onnx-zayit@1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca' ||
        model['tokenizer_checksum'] != modelFiles[1].sha256) {
      _invalid();
    }
    final digest = manifest['identityDigest'];
    if (family == SemanticVectorsFamily.windows &&
        (model['chunking_identity'] != kWindowsChunkingIdentity ||
            digest is! String ||
            !_sha(digest))) {
      _invalid();
    }
    return (
      files: files,
      segmentSize: (manifest['segment'] as Map)['size'] as int,
      from: from,
      identityDigest: digest is String ? digest : '',
    );
  }

  static SemanticAsset? _assetOf(Object? name, Object? size, Object? sha) =>
      name is String &&
          _plain(name) &&
          size is int &&
          size >= 0 &&
          sha is String &&
          _sha(sha)
      ? (name: name, size: size, sha256: sha)
      : null;

  static final _libraryTag = RegExp(r'^v(\d+)-[A-Za-z0-9._+-]+$');

  static int? _tagVersion(Object? tag) => tag is String
      ? int.tryParse(_libraryTag.firstMatch(tag)?.group(1) ?? '')
      : null;

  Future<_Meta?> _metadata(
    String mirrorDir, {
    bool preferWindows = false,
  }) async {
    try {
      var value = jsonDecode(
        await File(p.join(mirrorDir, manifestFileName)).readAsString(),
      );
      if (value is! Map<String, dynamic> ||
          value['libraryVersion'] is! int ||
          _tagVersion(value['libraryTag']) != value['libraryVersion']) {
        return null;
      }
      if (preferWindows && value.containsKey('windows')) {
        final windows = value['windows'];
        if (windows is! Map<String, dynamic> ||
            windows['family'] != SemanticVectorsFamily.windows.id ||
            windows['libraryTag'] != value['libraryTag'] ||
            windows['libraryVersion'] != value['libraryVersion']) {
          return null;
        }
        value = windows;
      }
      final tag = value['libraryTag'] as String;
      final version = value['libraryVersion'] as int;
      final family = value.containsKey('family')
          ? SemanticVectorsFamily.byId(value['family'])
          : SemanticVectorsFamily.legacy;
      if (family == SemanticVectorsFamily.legacy) {
        final base = _assetOf(
          value['manifestName'],
          value['manifestSize'],
          value['manifestSha256'],
        );
        if (base == null) return null;
        return _Meta(
          family: family!,
          chain: false,
          libraryTag: tag,
          libraryVersion: version,
          base: base,
          rejectedWindowsManifest: switch (value['rejectedWindowsManifest']) {
            final String sha when _sha(sha) => sha,
            _ => null,
          },
        );
      }
      if (family != SemanticVectorsFamily.windows) return null;
      final rawBase = value['base'];
      final kind = value['kind'];
      final digest = value['identityDigest'];
      final rawSteps = value['steps'];
      final base = rawBase is Map
          ? _assetOf(rawBase['name'], rawBase['size'], rawBase['sha256'])
          : null;
      if (base == null ||
          (kind != 'base' && kind != 'chain') ||
          digest is! String ||
          !_sha(digest) ||
          rawSteps is! List) {
        return null;
      }
      final steps = <_Step>[];
      var expectedFrom = 0;
      for (final raw in rawSteps) {
        if (raw is! Map ||
            raw['from'] is! int ||
            raw['to'] is! int ||
            raw['releaseTag'] !=
                '${family!.deltaReleaseTagPrefix}${raw['libraryTag']}' ||
            _tagVersion(raw['libraryTag']) != raw['to']) {
          return null;
        }
        final from = raw['from'] as int;
        final to = raw['to'] as int;
        final manifest = _assetOf(raw['name'], raw['size'], raw['sha256']);
        if (manifest == null ||
            from <= 0 ||
            from >= to ||
            (steps.isNotEmpty && from != expectedFrom)) {
          return null;
        }
        expectedFrom = to;
        steps.add(
          _Step(
            releaseTag: raw['releaseTag'] as String,
            libraryTag: raw['libraryTag'] as String,
            from: from,
            to: to,
            manifest: manifest,
          ),
        );
      }
      final chain = kind == 'chain';
      if (chain && steps.isNotEmpty && steps.last.to != version) return null;
      if (!chain && steps.isNotEmpty) return null;
      return _Meta(
        family: family!,
        chain: chain,
        libraryTag: tag,
        libraryVersion: version,
        base: base,
        identityDigest: digest,
        steps: steps,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<int?> mirroredVersion(String mirrorDir) async =>
      (await _metadata(mirrorDir))?.libraryVersion;

  Future<bool> _matches(
    String path,
    SemanticAsset file, [
    bool Function()? isCancelled,
    IOSink? copyTo,
  ]) async {
    _cancel(isCancelled);
    final source = File(path);
    final hash = Sha256Stream();
    try {
      try {
        if (!await source.exists() || await source.length() != file.size) {
          return false;
        }
        var unflushed = 0;
        await for (final chunk in source.openRead()) {
          _cancel(isCancelled);
          hash.add(chunk);
          if (copyTo == null) continue;
          copyTo.add(chunk);
          unflushed += chunk.length;
          if (unflushed >= _copyFlushBytes) {
            unflushed = 0;
            await copyTo.flush();
          }
        }
        return hash.close() == file.sha256;
      } on FileSystemException {
        if (copyTo != null) rethrow;
        return false;
      }
    } finally {
      hash.dispose();
    }
  }

  Future<({_Meta meta, List<_LoadedUnit> units})?> _load(
    String mirrorDir,
    int version, {
    bool preferWindows = false,
  }) async {
    final meta = await _metadata(mirrorDir, preferWindows: preferWindows);
    if (meta == null || meta.libraryVersion != version) return null;
    final generation = p.join(mirrorDir, meta.libraryTag);
    try {
      for (final file in _models) {
        final source = File(p.join(generation, modelFolder, file.name));
        if (!await source.exists() || await source.length() != file.size) {
          return null;
        }
      }
      final units = <_LoadedUnit>[];
      for (final step in meta.units) {
        final path = p.join(generation, 'vectors', step.manifest.name);
        if (!await _matches(path, step.manifest)) return null;
        final parsed = _vectors(
          jsonDecode(await File(path).readAsString()),
          tag: step.libraryTag,
          version: step.to,
          family: meta.family,
          deltaName: step.from > 0 ? step.manifest.name : null,
        );
        if (parsed.from != step.from ||
            (meta.windows && parsed.identityDigest != meta.identityDigest)) {
          return null;
        }
        for (final file in parsed.files) {
          final source = File(p.join(generation, 'vectors', file.name));
          if (!await source.exists() || await source.length() != file.size) {
            return null;
          }
        }
        units.add(
          _LoadedUnit(
            step: step,
            files: parsed.files,
            segmentSize: parsed.segmentSize,
          ),
        );
      }
      return (meta: meta, units: units);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<bool> pending({
    required String mirrorDir,
    required String dbPath,
    required int libraryVersion,
    String? vectorsRootPath,
    bool preferencesReady = true,
    bool supportsWindows = false,
    bool needsBase = false,
  }) async {
    final data = await _load(
      mirrorDir,
      libraryVersion,
      preferWindows: supportsWindows,
    );
    if (data == null) return false;
    final meta = data.meta;
    if (meta.windows && !supportsWindows) return false;
    final root = vectorsRootPath ?? p.dirname(p.dirname(dbPath));
    final sets = await readInstalledSets(p.join(root, 'vectors'));
    final live = sets.firstOrNull;
    if (_keepsWindowsSet(meta, live, supportsWindows)) return false;
    if (!preferencesReady) return true;
    if (needsBase && !meta.chain) return true;
    final vectorsCurrent = !meta.windows
        ? sets.any(
            (set) =>
                set.libraryVersion == meta.libraryVersion &&
                set.libraryReleaseTag == meta.libraryTag,
          )
        : live != null &&
              live.windows &&
              live.identityDigest == meta.identityDigest &&
              (meta.chain
                  ? live.libraryVersion >= meta.libraryVersion
                  : live.libraryVersion > meta.libraryVersion ||
                        (live.libraryVersion == meta.libraryVersion &&
                            live.libraryReleaseTag == meta.libraryTag));
    if (!vectorsCurrent) return true;
    for (final file in _models) {
      if (!await _matches(
        p.join(p.dirname(dbPath), modelFolder, file.name),
        file,
      )) {
        return true;
      }
    }
    return false;
  }

  /// A machine already on the preferred windows family waits for a windows
  /// download rather than taking the legacy set back, as Otzaria does.
  static bool _keepsWindowsSet(
    _Meta meta,
    SemanticInstalledSet? live,
    bool supportsWindows,
  ) => !meta.windows && supportsWindows && live != null && live.windows;

  /// The sound sets under [vectors], live first (`CURRENT`, then `PREVIOUS`).
  static Future<List<SemanticInstalledSet>> readInstalledSets(
    String vectors,
  ) async {
    String? marker;
    try {
      marker = (await File(
        p.join(vectors, windowsIdentityFileName),
      ).readAsString()).trim();
    } on FileSystemException {
      marker = null;
    }
    final sets = <SemanticInstalledSet>[];
    for (final pointerName in const ['CURRENT', 'PREVIOUS']) {
      try {
        final pointer = jsonDecode(
          await File(p.join(vectors, pointerName)).readAsString(),
        );
        if (pointer is! Map ||
            pointer['set'] is! String ||
            pointer['set_sha256'] is! String ||
            pointer['generation'] is! int ||
            !RegExp(
              r'^gen-[0-9]+/set\.json$',
            ).hasMatch(pointer['set'] as String)) {
          continue;
        }
        final bytes = await File(
          p.join(vectors, pointer['set'] as String),
        ).readAsBytes();
        if (Sha256Stream.ofBytes(bytes) != pointer['set_sha256']) continue;
        final set = jsonDecode(utf8.decode(bytes));
        if (set is! Map ||
            set['format'] != 'otzaria-vector-set' ||
            set['format_version'] != 1 ||
            set['generation'] != pointer['generation'] ||
            set['library_version'] is! int ||
            set['library_release_tag'] is! String ||
            set['segments'] is! List ||
            (set['segments'] as List).isEmpty) {
          continue;
        }
        var complete = true;
        for (final segment in set['segments'] as List) {
          if (segment is! Map ||
              segment['file'] is! String ||
              !RegExp(
                r'^segments/[0-9a-f]{32}\.oxv$',
              ).hasMatch(segment['file'] as String) ||
              segment['size'] is! int) {
            complete = false;
            break;
          }
          final file = File(p.join(vectors, segment['file'] as String));
          if (!await file.exists() || await file.length() != segment['size']) {
            complete = false;
            break;
          }
        }
        if (!complete) continue;
        final digest = set['identity_digest'];
        final identity = digest is String ? digest : '';
        sets.add(
          SemanticInstalledSet(
            libraryVersion: set['library_version'] as int,
            libraryReleaseTag: set['library_release_tag'] as String,
            identityDigest: identity,
            windows: identity.isNotEmpty && marker == identity,
          ),
        );
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return sets;
  }

  Future<void> _ensureOwnedDirectory(String path) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      var owned = false;
      for (final marker in const ['.otzaria-semantic', 'CURRENT', 'PREVIOUS']) {
        if (await File(p.join(path, marker)).exists()) owned = true;
      }
      if (!owned && !await directory.list().isEmpty) {
        throw FileSystemException(
          AppL10n.strings.libraryDomain.companionsInstallFailed(_name),
          path,
        );
      }
    }
    await directory.create(recursive: true);
    await File(p.join(path, '.otzaria-semantic')).writeAsString('');
  }

  static const _copyFlushBytes = 16 * 1024 * 1024;

  @visibleForTesting
  Future<String> concatenateVectorParts({
    required String vectorsDir,
    required List<SemanticAsset> parts,
    required String workDir,
    bool Function()? isCancelled,
  }) async {
    final name = parts.first.name.replaceFirst(RegExp(r'\.part-\d+$'), '');
    final segmentPath = p.join(workDir, name);
    final sink = File(segmentPath).openWrite();
    try {
      for (final part in parts) {
        _cancel(isCancelled);
        final source = p.join(vectorsDir, part.name);
        if (!await _matches(source, part, isCancelled, sink)) {
          _invalid();
        }
      }
    } finally {
      await sink.close();
    }
    return segmentPath;
  }

  void _ensureSpace(String path, int needed) {
    final free = _freeBytesFor(path);
    if (free == null || free >= needed) return;
    throw FileSystemException(
      AppL10n.strings.libraryDomain.notEnoughDiskSpace(
        path,
        DiskSpaceProbe.formatBytes(needed),
        DiskSpaceProbe.formatBytes(free),
      ),
      path,
    );
  }

  // Only a base can repair these, so the chain ends as "needs a base".
  static const _setRefusesDelta = {
    SemanticErrorKind.artifactIncompatible,
    SemanticErrorKind.artifactCorrupt,
    SemanticErrorKind.artifactMissing,
  };

  Future<SemanticVectorsEngine> _openEngine(String workDir) async {
    final factory = _engineFactory;
    if (factory != null) return factory(workDir);
    return _NativeVectorsEngine.open(workDir, _nativeLibrary);
  }

  /// The steps of [meta]'s chain the installed set still needs; throws when
  /// the set is not on the chain.
  Future<List<_LoadedUnit>> _remainingSteps(
    _Meta meta,
    List<_LoadedUnit> units,
    SemanticVectorsEngine engine,
    String vectorsDir,
  ) async {
    final SemanticEngineInfo info;
    try {
      info = await engine.info(vectorsDir);
    } on SemanticError catch (error) {
      if (error.kind != SemanticErrorKind.artifactCorrupt) rethrow;
      throw const SemanticChainNotApplicableException();
    }
    String? marker;
    try {
      marker = (await File(
        p.join(vectorsDir, windowsIdentityFileName),
      ).readAsString()).trim();
    } on FileSystemException {
      marker = null;
    }
    if (!info.present ||
        info.identityDigest.isEmpty ||
        marker != info.identityDigest ||
        info.identityDigest != meta.identityDigest) {
      throw const SemanticChainNotApplicableException();
    }
    if (info.libraryVersion >= meta.libraryVersion) return const [];
    final start = units.indexWhere(
      (unit) => unit.step.from == info.libraryVersion,
    );
    if (start < 0) throw const SemanticChainNotApplicableException();
    return units.sublist(start);
  }

  /// Returns whether a base was installed; `false` for a chain or a skip.
  Future<bool> install({
    required String mirrorDir,
    required String dbPath,
    required int libraryVersion,
    String? vectorsRootPath,
    bool supportsWindows = false,
    Future<void> Function()? beforeActivate,
    void Function(String)? onStage,
    bool Function()? isCancelled,
  }) async {
    _cancel(isCancelled);
    final data = await _load(
      mirrorDir,
      libraryVersion,
      preferWindows: supportsWindows,
    );
    if (data == null || (data.meta.windows && !supportsWindows)) {
      _invalid();
    }
    final meta = data.meta;
    onStage?.call(AppL10n.strings.libraryDomain.semanticInstalling);
    final root = vectorsRootPath ?? p.dirname(p.dirname(dbPath));
    final vectorsDir = p.join(root, 'vectors');
    final generation = p.join(mirrorDir, meta.libraryTag);
    final live = (await readInstalledSets(vectorsDir)).firstOrNull;
    if (_keepsWindowsSet(meta, live, supportsWindows)) return false;
    final work = await Directory.systemTemp.createTemp(
      'otzaria-semantic-install-',
    );
    SemanticVectorsEngine? engine;
    try {
      var units = data.units;
      // A chain is judged against the installed set before any file is
      // hashed: an off-chain set needs nothing from the drive.
      if (meta.chain) {
        engine = await _openEngine(work.path);
        units = await _remainingSteps(meta, units, engine, vectorsDir);
      }
      final parted = [
        for (final unit in units)
          if (unit.files.length > 1) ...unit.files,
      ];
      _ensureSpace(
        vectorsDir,
        units.fold(0, (size, unit) => size + unit.segmentSize),
      );
      if (parted.isNotEmpty) {
        _ensureSpace(
          Directory.systemTemp.path,
          parted.fold(0, (size, file) => size + file.size),
        );
      }
      for (final group in [
        (modelFolder, _models),
        (
          'vectors',
          [
            for (final unit in units) ...[unit.step.manifest, ...unit.files],
          ],
        ),
      ]) {
        for (final file in group.$2) {
          if (parted.contains(file)) continue;
          _cancel(isCancelled);
          final source = p.join(generation, group.$1, file.name);
          if (!await _matches(source, file, isCancelled)) {
            _invalid();
          }
        }
      }
      final segments = <String>[
        for (final unit in units)
          unit.files.length == 1
              ? p.join(generation, 'vectors', unit.files.single.name)
              : await concatenateVectorParts(
                  vectorsDir: p.join(generation, 'vectors'),
                  parts: unit.files,
                  workDir: work.path,
                  isCancelled: isCancelled,
                ),
      ];
      await beforeActivate?.call();
      final modelDirectory = p.join(p.dirname(dbPath), modelFolder);
      await _ensureOwnedDirectory(modelDirectory);
      await _ensureOwnedDirectory(vectorsDir);
      for (final file in _models) {
        _cancel(isCancelled);
        final source = p.join(generation, modelFolder, file.name);
        final target = p.join(p.dirname(dbPath), modelFolder, file.name);
        if (await _matches(target, file, isCancelled)) continue;
        _ensureSpace(p.dirname(target), file.size);
        await Directory(p.dirname(target)).create(recursive: true);
        final temporary = '$target.tmp';
        await File(source).copy(temporary);
        _cancel(isCancelled);
        if (!await _matches(temporary, file, isCancelled)) {
          _invalid();
        }
        await File(temporary).rename(target);
      }
      _cancel(isCancelled);
      await File(
        p.join(p.dirname(dbPath), modelFolder, '.otzaria-semantic'),
      ).writeAsString('');
      final modelIdentity = meta.windows
          ? kWindowsModelIdentityJson
          : await File(
              p.join(p.dirname(dbPath), modelFolder, 'model.json'),
            ).readAsString();
      engine ??= await _openEngine(work.path);
      for (final (index, unit) in units.indexed) {
        final manifestJson = await File(
          p.join(generation, 'vectors', unit.step.manifest.name),
        ).readAsString();
        await beforeActivate?.call();
        _cancel(isCancelled);
        _ensureSpace(vectorsDir, unit.segmentSize);
        // Before the engine call: a crash after it must not leave an unmarked
        // windows set, which Otzaria would treat as the old family.
        final marker = File(p.join(vectorsDir, windowsIdentityFileName));
        final previousMarker = meta.windows && await marker.exists()
            ? await marker.readAsString()
            : null;
        if (meta.windows) {
          await marker.writeAsString(meta.identityDigest, flush: true);
        }
        final ({int libraryVersion, bool alreadyApplied}) report;
        try {
          report = await engine.install(
            SemanticVectorsInstallInput(
              vectorsDir: vectorsDir,
              segmentPath: segments[index],
              manifestJson: manifestJson,
              publishedManifestSha256: unit.step.manifest.sha256,
              modelIdentityJson: modelIdentity,
            ),
            isCancelled: isCancelled,
          );
        } catch (error) {
          // A refused base leaves the old set live, so it keeps its own marker.
          if (meta.windows && !unit.isDelta) {
            await _restoreMarker(marker, previousMarker);
          }
          if (error is SemanticError &&
              unit.isDelta &&
              _setRefusesDelta.contains(error.kind)) {
            throw const SemanticChainNotApplicableException();
          }
          rethrow;
        }
        if (!report.alreadyApplied && report.libraryVersion != unit.step.to) {
          _invalid();
        }
      }
      if (meta.chain) {
        await beforeActivate?.call();
        _cancel(isCancelled);
        await engine.compact(vectorsDir, isCancelled: isCancelled);
      }
      return !meta.chain;
    } finally {
      engine?.dispose();
      await work.delete(recursive: true);
    }
  }

  static Future<void> _restoreMarker(File marker, String? previous) async {
    try {
      if (previous == null) {
        if (await marker.exists()) await marker.delete();
      } else {
        await marker.writeAsString(previous, flush: true);
      }
    } on FileSystemException {
      return;
    }
  }
}

class _NativeVectorsEngine implements SemanticVectorsEngine {
  _NativeVectorsEngine(this._engine);

  static Future<void>? _initialization;

  static Future<_NativeVectorsEngine> open(
    String workDir,
    ExternalLibrary? library,
  ) async {
    await (_initialization ??= RustLib.init(externalLibrary: library));
    final index = await Directory(p.join(workDir, 'index')).create();
    return _NativeVectorsEngine(
      await SearchEngine.newInstance(path: index.path),
    );
  }

  final SearchEngine _engine;

  @override
  Future<SemanticEngineInfo> info(String vectorsDir) async {
    final info = await _engine.semanticVectorsInfo(vectorsDir: vectorsDir);
    return (
      present: info.present,
      libraryVersion: info.libraryVersion,
      identityDigest: info.identityDigest,
    );
  }

  @override
  Future<({int libraryVersion, bool alreadyApplied})> install(
    SemanticVectorsInstallInput input, {
    bool Function()? isCancelled,
  }) async {
    return _withCancellation(isCancelled, (token) async {
      final report = await _engine.installSemanticVectors(
        input: input,
        cancellation: token,
      );
      return (
        libraryVersion: report.libraryVersion,
        alreadyApplied: report.alreadyApplied,
      );
    });
  }

  @override
  Future<void> compact(String vectorsDir, {bool Function()? isCancelled}) =>
      _withCancellation(isCancelled, (token) async {
        await _engine.compactSemanticVectors(
          vectorsDir: vectorsDir,
          cancellation: token,
        );
      });

  Future<T> _withCancellation<T>(
    bool Function()? isCancelled,
    Future<T> Function(SemanticCancellationToken) operation,
  ) async {
    final token = SemanticCancellationToken();
    final poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (isCancelled?.call() ?? false) token.cancel();
    });
    try {
      if (isCancelled?.call() ?? false) token.cancel();
      return await operation(token);
    } on SemanticError catch (error) {
      if (error.kind == SemanticErrorKind.cancelled) {
        throw const PatchDownloadCancelled();
      }
      rethrow;
    } finally {
      poll.cancel();
      token.dispose();
    }
  }

  @override
  void dispose() => _engine.dispose();
}
