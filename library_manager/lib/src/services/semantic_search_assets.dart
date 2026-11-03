import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart'
    show SemanticAppSupport, SemanticSupportBasis;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'atomic_file.dart' show writeStringAtomically;
import 'download_connections.dart';
import 'github_fetch.dart';
import 'semantic_status.dart';
import 'semantic_vectors_plan.dart';
import 'storage_guard.dart';

export 'package:otzaria_manager/otzaria_manager.dart'
    show SemanticAppSupport, SemanticSupportBasis;

export 'semantic_status.dart';
export 'semantic_vectors_plan.dart';

typedef SemanticAsset = ({String name, int size, String sha256});

/// Everything that differs between two model generations: where the model
/// lives, what it must be called, what the vectors' manifest must name.
class SemanticModelSpec {
  const SemanticModelSpec({
    required this.generation,
    required this.folder,
    required this.baseUrl,
    required this.familyId,
    required this.tokenizerChecksum,
    required this.files,
    required this.windowsIdentityJson,
  });

  final SemanticModelGeneration generation;

  /// The model folder beside the DB.
  final String folder;
  final String baseUrl;

  /// What a vectors manifest's `identity.model.family_id` must be.
  final String familyId;
  final String tokenizerChecksum;

  /// Needed for basic search; an optional passage graph is not listed.
  final List<SemanticAsset> files;

  /// The `model.json` bytes Otzaria's windows family ships for this model.
  final String windowsIdentityJson;

  SemanticAsset get identityFile =>
      files.firstWhere((file) => file.name == 'model.json');

  SemanticAsset get graph => files.first;

  static const round2 = SemanticModelSpec(
    generation: SemanticModelGeneration.round2,
    folder: 'meivin-round2-onnx',
    baseUrl:
        'https://github.com/Otzaria/otzaria-semantic-search/releases/download/model-meivin-round2-int8-v1',
    familyId:
        'ArieLLL123/judaic-semantic-round2-onnx-zayit@1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca',
    tokenizerChecksum:
        '0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9',
    files: <SemanticAsset>[
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
    ],
    windowsIdentityJson: kWindowsModelIdentityJson,
  );

  static const qa491 = SemanticModelSpec(
    generation: SemanticModelGeneration.qa491,
    folder: 'meivin-qa491-onnx',
    baseUrl:
        'https://github.com/Otzaria/otzaria-semantic-search/releases/download/model-meivin-qa491-int8-v1',
    familyId: 'otzaria/Meivin-Embed-QA491-native256',
    tokenizerChecksum:
        '0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9',
    files: <SemanticAsset>[
      (
        name: 'query.int8.onnx',
        size: 42625431,
        sha256:
            '82b87180616cee55357b90858f327f4d98b86b2e5589f6771d50b788ad383597',
      ),
      (
        name: 'tokenizer.json',
        size: 2191362,
        sha256:
            '0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9',
      ),
      (
        name: 'model.json',
        size: 634,
        sha256:
            '58227b5df294a2c20a706482de5d431875941f22ee5007cf20ddc84536801fad',
      ),
      (
        name: 'LICENSE',
        size: 3992,
        sha256:
            '92267258dabd9077849cc5ab63a5b0b0b3ca9849e1112fd0d13d9691df7e0739',
      ),
    ],
    windowsIdentityJson: kQa491WindowsModelIdentityJson,
  );

  static const all = <SemanticModelGeneration, SemanticModelSpec>{
    SemanticModelGeneration.round2: round2,
    SemanticModelGeneration.qa491: qa491,
  };

  static SemanticModelGeneration? generationOfFamily(Object? familyId) {
    for (final spec in all.values) {
      if (spec.familyId == familyId) return spec.generation;
    }
    return null;
  }
}

/// The installed set is not where the drive's delta chain continues from;
/// only a full smart-search download on the online machine helps.
class SemanticChainNotApplicableException implements Exception {
  const SemanticChainNotApplicableException();

  @override
  String toString() => AppL10n.strings.libraryDomain.semanticFullDownloadNeeded;
}

/// Published vectors the bundled engine would refuse (`identity.text`);
/// downloading again cannot help.
class SemanticEngineIncompatibleException implements Exception {
  const SemanticEngineIncompatibleException({
    required this.lineTextVersion,
    required this.keyVersion,
    SemanticIncompatibilityReason? reason,
  }) : _reason = reason;

  final int lineTextVersion;
  final int keyVersion;
  final SemanticIncompatibilityReason? _reason;

  /// The vectors were built for a newer engine than this tool bundles.
  bool get toolIsOlder =>
      lineTextVersion > kSemanticEngineText.lineTextVersion ||
      (lineTextVersion == kSemanticEngineText.lineTextVersion &&
          keyVersion > kSemanticEngineText.keyVersion);

  /// Which side must change; the target Otzaria's reasons are set explicitly.
  SemanticIncompatibilityReason get reason =>
      _reason ??
      (toolIsOlder
          ? SemanticIncompatibilityReason.updateTool
          : SemanticIncompatibilityReason.republishAssets);

  @override
  String toString() {
    final strings = AppL10n.strings.libraryDomain;
    return switch (reason) {
      SemanticIncompatibilityReason.updateTool =>
        strings.semanticIncompatibleUpdateTool,
      SemanticIncompatibilityReason.updateOtzaria =>
        strings.semanticIncompatibleUpdateOtzaria,
      SemanticIncompatibilityReason.republishAssets =>
        strings.semanticIncompatibleRepublish,
      SemanticIncompatibilityReason.otzariaUnproven =>
        strings.semanticIncompatibleOtzariaUnproven,
    };
  }
}

/// A vector set as its `CURRENT`/`PREVIOUS` pointer files describe it.
class SemanticInstalledSet {
  const SemanticInstalledSet({
    required this.libraryVersion,
    required this.libraryReleaseTag,
    required this.identityDigest,
    required this.windows,
    this.familyId,
    this.chunkingIdentity,
  });

  final int libraryVersion;
  final String libraryReleaseTag;
  final String identityDigest;

  /// `.otzaria-windows-identity` names this set, as Otzaria requires.
  final bool windows;

  /// `identity.model.family_id` of `set.json`; `null` when it is not there.
  final String? familyId;
  final int? chunkingIdentity;

  /// The model generation the set was built for; `null` = not provable.
  SemanticModelGeneration? get generation =>
      SemanticModelSpec.generationOfFamily(familyId);

  /// Whether the windows marker agrees with the set's chunking: a windows
  /// set without the marker is read by Otzaria as the other shape.
  bool get markerConsistent =>
      chunkingIdentity == null ||
      windows == (chunkingIdentity == kWindowsChunkingIdentity);
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

  Future<void> verify(String vectorsDir);

  Future<({int libraryVersion, bool alreadyApplied})> install(
    SemanticVectorsInstallInput input, {
    bool Function()? isCancelled,
  });

  Future<void> compact(String vectorsDir, {bool Function()? isCancelled});

  void dispose();
}

typedef SemanticEngineFactory =
    Future<SemanticVectorsEngine> Function(String workDir);

@visibleForTesting
Future<void> disposeSemanticEngineWork(
  SemanticVectorsEngine? engine,
  Directory work,
) async {
  engine?.dispose();
  // A Tantivy reload already running can outlive dispose and write its old path.
  // Moving our scratch directory first keeps that callback outside the deletion.
  late Directory retired;
  for (var attempt = 0; ; attempt++) {
    try {
      retired = await work.rename('${work.path}.retired');
      break;
    } on FileSystemException catch (error) {
      if (!Platform.isWindows ||
          ![5, 32].contains(error.osError?.errorCode) ||
          attempt == 9) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  await retired.delete(recursive: true);
}

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
    this.generation = SemanticModelGeneration.round2,
    required this.family,
    required this.chain,
    required this.libraryTag,
    required this.libraryVersion,
    required this.base,
    this.identityDigest = '',
    this.steps = const [],
    this.rejectedWindowsManifest,
  });

  final SemanticModelGeneration generation;
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
            releaseTag: '${family.releaseTagPrefixFor(generation)}$libraryTag',
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
          'generation': generation.id,
          'family': family.id,
          'kind': chain ? 'chain' : 'base',
          'libraryTag': libraryTag,
          'libraryVersion': libraryVersion,
          'identityDigest': identityDigest,
          'base': {'name': base.name, 'size': base.size, 'sha256': base.sha256},
          'steps': [for (final step in steps) step.toJson()],
        }
      : {
          'generation': generation.id,
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
    this.identityDigest = '',
  });

  final _Step step;
  final List<SemanticAsset> files;
  final int segmentSize;
  final String identityDigest;

  bool get isDelta => step.from > 0;
}

class SemanticSearchAssets {
  SemanticSearchAssets({
    http.Client? httpClient,
    ExternalLibrary? nativeLibrary,
    DownloadScheduler? scheduler,
    int? Function(String)? freeBytesFor,
    bool Function(String)? removableProbe,
    WriteSpeedProbe? writeProbe,
    SemanticEngineFactory? engineFactory,
    @visibleForTesting List<SemanticAsset>? models,
    @visibleForTesting
    ({String familyId, String tokenizerChecksum})? modelFamily,
    @visibleForTesting Map<SemanticModelGeneration, SemanticModelSpec>? specs,
  }) : _injectedClient = httpClient,
       _nativeLibrary = nativeLibrary,
       _scheduler = scheduler ?? DownloadScheduler(),
       _freeBytesFor = freeBytesFor ?? DiskSpaceProbe.freeBytesFor,
       _removableProbe = removableProbe,
       _writeProbe = writeProbe,
       _engineFactory = engineFactory,
       _specs = {
         ...SemanticModelSpec.all,
         if (models != null || modelFamily != null)
           SemanticModelGeneration.round2: SemanticModelSpec(
             generation: SemanticModelGeneration.round2,
             folder: SemanticModelSpec.round2.folder,
             baseUrl: SemanticModelSpec.round2.baseUrl,
             familyId: modelFamily?.familyId ?? productionModelFamily.familyId,
             tokenizerChecksum:
                 modelFamily?.tokenizerChecksum ??
                 productionModelFamily.tokenizerChecksum,
             files: models ?? modelFiles,
             windowsIdentityJson: kWindowsModelIdentityJson,
           ),
         ...?specs,
       },
       _ownsClient = httpClient == null;

  final http.Client? _injectedClient;
  http.Client? _createdClient;
  http.Client get _client =>
      _injectedClient ?? (_createdClient ??= http.Client());
  Duration timeout = const Duration(seconds: 30);
  Duration stallTimeout = const Duration(minutes: 5);
  final DownloadScheduler _scheduler;
  final int? Function(String) _freeBytesFor;
  final bool Function(String)? _removableProbe;
  final WriteSpeedProbe? _writeProbe;
  final bool _ownsClient;
  final ExternalLibrary? _nativeLibrary;
  final SemanticEngineFactory? _engineFactory;
  final Map<SemanticModelGeneration, SemanticModelSpec> _specs;

  SemanticModelSpec _spec(SemanticModelGeneration generation) =>
      _specs[generation]!;

  /// The family and tokenizer a Round2 manifest must name.
  static final productionModelFamily = (
    familyId: SemanticModelSpec.round2.familyId,
    tokenizerChecksum: SemanticModelSpec.round2.tokenizerChecksum,
  );
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
    required SemanticModelGeneration generation,
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
        generation,
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
    SemanticModelGeneration generation,
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
      generation: generation,
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
    SemanticModelGeneration generation,
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
          '${family.deltaReleaseTagPrefixFor(generation)}$tag',
          delta: true,
        );
        if (release == null) return null;
        final step = await _remote(
          release,
          libraryTag: tag,
          version: to,
          family: family,
          generation: generation,
          isCancelled: isCancelled,
          delta: true,
        );
        // A chain never joins identities, and so never generations.
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
    } on SemanticEngineIncompatibleException {
      return null;
    }
  }

  /// What to mirror for [libraryTag]: `null` when no vectors were published.
  Future<({_Meta meta, List<_Remote> remotes})?> _plan(
    String mirrorDir,
    String libraryTag,
    int version,
    SemanticFleet fleet,
    String? Function(int version) libraryTagFor,
    bool Function()? isCancelled,
  ) async {
    final generation = fleet.generation;
    String? rejectedWindows;
    Object? windowsFault;
    if (fleet.family == SemanticVectorsFamily.windows) {
      const family = SemanticVectorsFamily.windows;
      final release = await _windowsRelease(libraryTag, generation);
      _Remote? base;
      if (release != null) {
        try {
          base = await _remote(
            release,
            libraryTag: libraryTag,
            version: version,
            family: family,
            generation: generation,
            isCancelled: isCancelled,
          );
        } on _Unusable catch (fault) {
          rejectedWindows = _rejectionKey(release);
          windowsFault = fault;
        } on SemanticEngineIncompatibleException catch (fault) {
          await _recordIncompatible(mirrorDir, release, fault);
          windowsFault = fault;
        }
      }
      if (base != null) {
        final start = fleet.chainStartFor(base.identityDigest);
        if (start != null) {
          final chain = start >= version
              ? <_Remote>[]
              : await _deltaChain(
                  base,
                  start,
                  generation,
                  libraryTagFor,
                  isCancelled,
                );
          if (chain != null) {
            final meta = _metaOf(family, generation, base, chain: chain);
            if (fleet.canApply(meta.stepRange, version)) {
              return (meta: meta, remotes: chain);
            }
          }
        }
        return (meta: _metaOf(family, generation, base), remotes: [base]);
      }
    }
    const family = SemanticVectorsFamily.legacy;
    final release = await _fetchRelease(
      '${family.releaseTagPrefixFor(generation)}$libraryTag',
    );
    if (release == null) {
      if (windowsFault != null) throw windowsFault;
      return null;
    }
    final _Remote base;
    try {
      base = await _remote(
        release,
        libraryTag: libraryTag,
        version: version,
        family: family,
        generation: generation,
        isCancelled: isCancelled,
      );
    } on SemanticEngineIncompatibleException catch (fault) {
      await _recordIncompatible(mirrorDir, release, fault);
      rethrow;
    }
    return (
      meta: _metaOf(family, generation, base, rejectedWindows: rejectedWindows),
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
  Future<_Release?> _windowsRelease(
    String libraryTag,
    SemanticModelGeneration generation,
  ) async {
    try {
      return await _fetchRelease(
        '${SemanticVectorsFamily.windows.releaseTagPrefixFor(generation)}$libraryTag',
      );
    } on _HttpFailure {
      rethrow;
    } on FormatException {
      return null;
    }
  }

  _Meta _metaOf(
    SemanticVectorsFamily family,
    SemanticModelGeneration generation,
    _Remote base, {
    List<_Remote>? chain,
    String? rejectedWindows,
  }) => _Meta(
    generation: generation,
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

  int _modelDownloadBytes(SemanticModelGeneration generation) => [
    for (final file in _spec(generation).files)
      file.name == 'tokenizer.json' ? tokenizerZip : file,
  ].fold<int>(0, (sum, file) => sum + file.size);

  /// Set by [peekPending] when a published release is known unreadable by
  /// the bundled engine, which is why nothing is offered.
  SemanticEngineIncompatibleException? get peekedIncompatibility =>
      _peekedIncompatibility;
  SemanticEngineIncompatibleException? _peekedIncompatibility;

  /// The hint [sync] leaves beside `semantic.json`: a release found unreadable
  /// costs a manifest, and the light check must not offer it again.
  static const incompatibleFileName = 'semantic-incompatible.json';

  Future<Map<String, Map>> _recordedIncompatible(String mirrorDir) async {
    try {
      final value = jsonDecode(
        await File(p.join(mirrorDir, incompatibleFileName)).readAsString(),
      );
      final engine = value is Map ? value['engine'] : null;
      final releases = value is Map ? value['releases'] : null;
      if (engine is! Map ||
          engine['lineTextVersion'] != kSemanticEngineText.lineTextVersion ||
          engine['keyVersion'] != kSemanticEngineText.keyVersion ||
          releases is! Map) {
        return {};
      }
      return {
        for (final MapEntry(:key, :value) in releases.entries)
          if (key is String && value is Map) key: value,
      };
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<SemanticEngineIncompatibleException?> _recorded(
    String mirrorDir,
    _Release release,
  ) async {
    final entry = (await _recordedIncompatible(mirrorDir))[release.releaseTag];
    final line = entry?['lineTextVersion'];
    final key = entry?['keyVersion'];
    if (entry == null ||
        entry['key'] != _rejectionKey(release) ||
        line is! int ||
        key is! int) {
      return null;
    }
    return SemanticEngineIncompatibleException(
      lineTextVersion: line,
      keyVersion: key,
    );
  }

  Future<void> _recordIncompatible(
    String mirrorDir,
    _Release release,
    SemanticEngineIncompatibleException fault,
  ) async {
    final releases = await _recordedIncompatible(mirrorDir);
    releases[release.releaseTag] = {
      'key': _rejectionKey(release),
      'lineTextVersion': fault.lineTextVersion,
      'keyVersion': fault.keyVersion,
    };
    try {
      await Directory(mirrorDir).create(recursive: true);
      await writeStringAtomically(
        p.join(mirrorDir, incompatibleFileName),
        jsonEncode({
          'engine': {
            'lineTextVersion': kSemanticEngineText.lineTextVersion,
            'keyVersion': kSemanticEngineText.keyVersion,
          },
          'releases': releases,
        }),
      );
    } on FileSystemException {
      // A hint for the light check only; the incompatibility is what is thrown.
    }
  }

  /// Why the vectors the mirror holds for [libraryVersion] cannot be
  /// installed, or `null` when they can (or none are held).
  Future<SemanticEngineIncompatibleException?> incompatibility({
    required String mirrorDir,
    required int libraryVersion,
    required SemanticModelGeneration generation,
    bool supportsWindows = false,
    String? dbPath,
    String? vectorsRootPath,
  }) async {
    final root =
        vectorsRootPath ??
        (dbPath == null ? null : p.dirname(p.dirname(dbPath)));
    if (supportsWindows && root != null) {
      final meta = await _metadata(
        mirrorDir,
        generation: generation,
        preferWindows: true,
      );
      final live = (await readInstalledSets(
        p.join(root, 'vectors'),
      )).firstOrNull;
      if (meta != null &&
          meta.libraryVersion == libraryVersion &&
          _keepsWindowsSet(meta, live, supportsWindows, generation)) {
        final hint = (await _recordedIncompatible(
          mirrorDir,
        ))['${SemanticVectorsFamily.windows.releaseTagPrefixFor(generation)}${meta.libraryTag}'];
        final line = hint?['lineTextVersion'];
        final key = hint?['keyVersion'];
        if (line is int && key is int) {
          return SemanticEngineIncompatibleException(
            lineTextVersion: line,
            keyVersion: key,
          );
        }
        // The machine keeps its windows set and never installs legacy.
        return null;
      }
    }
    try {
      await _load(
        mirrorDir,
        libraryVersion,
        generation: generation,
        preferWindows: supportsWindows,
        reportIncompatible: true,
      );
      return null;
    } on SemanticEngineIncompatibleException catch (fault) {
      return fault;
    }
  }

  List<SemanticFleet> _provenGroups(SemanticFleet fleet) {
    final groups = fleet.groups;
    if (groups.isEmpty) {
      throw const SemanticEngineIncompatibleException(
        lineTextVersion: 0,
        keyVersion: 0,
        reason: SemanticIncompatibilityReason.otzariaUnproven,
      );
    }
    return groups;
  }

  Future<bool> peekPending({
    required String mirrorDir,
    required String libraryTag,
    SemanticFleet fleet = const SemanticFleet(),
  }) async {
    _peekedPendingBytes = null;
    _peekedIncompatibility = null;
    final groups = _provenGroups(fleet);
    for (final group in groups) {
      if (await _peekPending(mirrorDir, libraryTag, group)) {
        if (groups.length != 1) _peekedPendingBytes = null;
        _peekedIncompatibility = null;
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
    final generation = fleet.generation;
    final version = _version(libraryTag);
    SemanticEngineIncompatibleException? windowsFault;
    if (fleet.family == SemanticVectorsFamily.windows) {
      final release = await _windowsRelease(libraryTag, generation);
      final local = await _metadata(mirrorDir, generation: generation);
      final rejected =
          local != null &&
          !local.windows &&
          local.libraryTag == libraryTag &&
          release != null &&
          local.rejectedWindowsManifest == _rejectionKey(release);
      var unreadable = release == null
          ? null
          : await _recorded(mirrorDir, release);
      if (release != null && !rejected && unreadable == null) {
        if (await _windowsMirrorServes(
          mirrorDir,
          libraryTag,
          version,
          release,
          fleet,
          generation,
        )) {
          return false;
        }
        try {
          await _remote(
            release,
            libraryTag: libraryTag,
            version: version,
            family: SemanticVectorsFamily.windows,
            generation: generation,
          );
          return true;
        } on SemanticEngineIncompatibleException catch (fault) {
          await _recordIncompatible(mirrorDir, release, fault);
          unreadable = fault;
        } on _Unusable {
          // Match download planning: unusable windows metadata permits legacy.
        }
      }
      windowsFault = unreadable;
      // Machines on a live windows set never install legacy: say why instead.
      if (unreadable != null &&
          fleet.machines.isNotEmpty &&
          fleet.machines.every(
            (m) => m.family == SemanticVectorsFamily.windows,
          )) {
        _peekedIncompatibility = unreadable;
        _peekedPendingBytes = 0;
        return false;
      }
    }
    final fetched = await _fetchRelease(
      '${SemanticVectorsFamily.legacy.releaseTagPrefixFor(generation)}$libraryTag',
    );
    if (fetched == null) {
      _peekedIncompatibility = windowsFault;
      return false;
    }
    final remote = fetched.manifest;
    final recorded = await _recorded(mirrorDir, fetched);
    if (recorded != null) {
      _peekedIncompatibility = recorded;
      _peekedPendingBytes = 0;
      return false;
    }
    SemanticEngineIncompatibleException? held;
    ({_Meta meta, List<_LoadedUnit> units})? local;
    try {
      local = await _load(
        mirrorDir,
        version,
        generation: generation,
        reportIncompatible: true,
      );
    } on SemanticEngineIncompatibleException catch (fault) {
      held = fault;
    }
    if (held != null) {
      final meta = await _metadata(mirrorDir, generation: generation);
      if (meta != null &&
          !meta.windows &&
          meta.libraryTag == libraryTag &&
          meta.base.name == remote['name'] &&
          meta.base.size == remote['size'] &&
          meta.base.sha256 == fetched.digest) {
        _peekedIncompatibility = held;
        _peekedPendingBytes = 0;
        return false;
      }
    }
    if (local == null ||
        local.meta.windows ||
        local.meta.libraryTag != libraryTag ||
        local.meta.base.name != remote['name'] ||
        local.meta.base.size != remote['size'] ||
        local.meta.base.sha256 != fetched.digest) {
      try {
        await _remote(
          fetched,
          libraryTag: libraryTag,
          version: version,
          family: SemanticVectorsFamily.legacy,
          generation: generation,
        );
      } on SemanticEngineIncompatibleException catch (fault) {
        await _recordIncompatible(mirrorDir, fetched, fault);
        _peekedIncompatibility = fault;
        _peekedPendingBytes = 0;
        return false;
      }
      _peekedPendingBytes = fetched.assets.values.fold<int>(
        _modelDownloadBytes(generation),
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
    SemanticModelGeneration generation,
  ) async {
    final ({_Meta meta, List<_LoadedUnit> units})? local;
    try {
      local = await _load(
        mirrorDir,
        version,
        generation: generation,
        preferWindows: true,
        reportIncompatible: true,
      );
    } on SemanticEngineIncompatibleException catch (fault) {
      final held = await _metadata(
        mirrorDir,
        generation: generation,
        preferWindows: true,
      );
      final same =
          held != null &&
          held.windows &&
          held.libraryTag == libraryTag &&
          held.base.name == release.manifest['name'] &&
          held.base.size == release.manifest['size'] &&
          held.base.sha256 == release.digest;
      if (same) _peekedIncompatibility = fault;
      return same;
    }
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

  /// The tokenizer travels as a zip; the verified file is unpacked from it.
  static SemanticAsset _downloadAsset(SemanticAsset file) =>
      file.name == 'tokenizer.json' ? tokenizerZip : file;

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
    final groups = _provenGroups(fleet);
    final version = _version(libraryTag);
    onStage?.call(AppL10n.strings.libraryDomain.semanticDownloading);
    final plans = <_Meta>[];
    final remotes = <String, _Remote>{};
    for (final group in groups) {
      final plan = await _plan(
        mirrorDir,
        libraryTag,
        version,
        group,
        libraryTagFor ?? (_) => null,
        isCancelled,
      );
      _cancel(isCancelled);
      if (plan == null) _httpFailure(HttpStatus.notFound);
      plans.removeWhere(
        (m) =>
            m.generation == plan.meta.generation &&
            m.family == plan.meta.family,
      );
      plans.add(plan.meta);
      for (final remote in plan.remotes) {
        remotes[remote.releaseTag] = remote;
      }
    }
    final metadata = _mirrorJson(plans);
    final generation = p.join(mirrorDir, libraryTag);
    // By destination path: the same file name lives in each generation's folder.
    final reused = <String, ({String source, int size})>{};
    final downloadModels = <({SemanticModelSpec spec, SemanticAsset file})>[];
    for (final spec in [
      for (final gen in SemanticModelGeneration.values)
        if (plans.any((m) => m.generation == gen)) _spec(gen),
    ]) {
      for (final file in spec.files) {
        final source = await reusableModelSource(
          mirrorDir: mirrorDir,
          libraryTag: libraryTag,
          file: file,
          generation: spec.generation,
          isCancelled: isCancelled,
        );
        if (source != null) {
          reused[p.join(generation, spec.folder, file.name)] = (
            source: source,
            size: file.size,
          );
        } else {
          downloadModels.add((spec: spec, file: file));
        }
      }
    }
    final vectorFiles = [
      for (final remote in remotes.values)
        for (final file in remote.files)
          (file: file, url: remote.urls[file.name]!),
    ];
    final progress = ByteProgressAggregator(
      totalBytes: [
        for (final model in downloadModels) _downloadAsset(model.file),
        for (final vector in vectorFiles) vector.file,
      ].fold<int>(0, (sum, file) => sum + file.size),
      onProgress: onBytesProgress,
    );
    final jobs = <({SemanticAsset file, String url, String dest})>[
      for (final model in downloadModels)
        (
          file: _downloadAsset(model.file),
          url: '${model.spec.baseUrl}/${_downloadAsset(model.file).name}',
          dest: p.join(
            generation,
            model.spec.folder,
            _downloadAsset(model.file).name,
          ),
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
    final downloaders = <PatchDownloader>[];
    Future<double?>? measured;
    final probe =
        _writeProbe ?? (d) => driveWriteSpeed(d, isCancelled: isCancelled);
    try {
      for (final job in jobs) {
        downloaders.add(
          newDownloader(
            maxConnections: await connectionsForAsset(
              _scheduler,
              job.dest,
              token: job.file.sha256,
              removableProbe: _removableProbe,
              // One measurement of the mirror drive serves every asset.
              writeProbe: (_) => measured ??= probe(mirrorDir),
              isCancelled: isCancelled,
            ),
          ),
        );
      }
      await _ensureMirrorSpace(
        mirrorDir: mirrorDir,
        generation: generation,
        jobs: [
          for (final job in jobs)
            (file: job.file, url: job.url, dest: job.dest),
        ],
        reused: reused,
        manifestBytes: remotes.values.fold<int>(
          0,
          (sum, remote) => sum + remote.manifestBytes.length,
        ),
        downloaders: downloaders,
      );
      progress.announce();
      _cancel(isCancelled);
      for (final model in plans) {
        await Directory(
          p.join(generation, _spec(model.generation).folder),
        ).create(recursive: true);
      }
      await Directory(p.join(generation, 'vectors')).create(recursive: true);
      for (final entry in reused.entries) {
        final target = entry.key;
        if (p.equals(entry.value.source, target)) continue;
        _cancel(isCancelled);
        final temporary = '$target.tmp';
        await File(entry.value.source).copy(temporary);
        await File(temporary).rename(target);
      }
      // Verifying and assembling touch the drive; they are stages, never
      // counted as network.
      final verifying = <String, (bool, int)>{};
      void showLocalWork(String name, int? percent, {bool assembling = false}) {
        final next = percent == null ? null : (assembling, percent);
        if (next == null) {
          if (verifying.remove(name) == null) return;
        } else if (verifying[name] == next) {
          return;
        } else {
          verifying[name] = next;
        }
        final strings = AppL10n.strings.libraryDomain;
        onStage?.call(
          verifying.isEmpty
              ? strings.semanticDownloading
              : [
                  for (final MapEntry(:key, value: (assembly, value))
                      in verifying.entries)
                    assembly
                        ? strings.exportAssembling(
                            libraryTag,
                            p.basename(key),
                            value,
                          )
                        : strings.exportVerifying(
                            libraryTag,
                            p.basename(key),
                            value,
                          ),
                ].join('\n'),
        );
      }

      await _scheduler.run<void>([
        for (final (index, job) in jobs.indexed)
          () async {
            _cancel(isCancelled);
            final slot = slots[index];
            try {
              await downloaders[index].downloadToFile(
                url: job.url,
                destPath: job.dest,
                expectedSize: job.file.size,
                expectedSha256: job.file.sha256,
                resumeToken: job.file.sha256,
                // The engine verifies a prefix before resuming: bytes arriving
                // end that asset's local-work stage.
                onProgress: (done, total) {
                  showLocalWork(job.dest, null);
                  slot.report(done, total);
                },
                onExistingBytes: slot.markExisting,
                onVerifyProgress: (done, total) => showLocalWork(
                  job.dest,
                  total > 0 ? (done * 100 ~/ total).clamp(0, 100) : 0,
                ),
                onAssembleProgress: (done, total) => showLocalWork(
                  job.dest,
                  total > 0 ? (done * 100 ~/ total).clamp(0, 100) : 0,
                  assembling: true,
                ),
                isCancelled: isCancelled,
              );
            } finally {
              showLocalWork(job.dest, null);
            }
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
    } on FileSystemException catch (error, stack) {
      throwStorageAware(error, stack, mirrorDir);
    } finally {
      for (final downloader in downloaders) {
        downloader.dispose();
      }
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
  PatchDownloader newDownloader({int? maxConnections}) => PatchDownloader(
    httpClient: _client,
    decompress: (_) async => null,
    stallTimeout: stallTimeout,
    maxConnections: maxConnections ?? connectionsPerFile(_scheduler),
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

  /// Refuses before the first write when the drive is known to lack room;
  /// unknown free space never blocks.
  Future<void> _ensureMirrorSpace({
    required String mirrorDir,
    required String generation,
    required List<({SemanticAsset file, String url, String dest})> jobs,
    required Map<String, ({String source, int size})> reused,
    required int manifestBytes,
    required List<PatchDownloader> downloaders,
  }) async {
    var needed = manifestBytes;
    for (final (index, job) in jobs.indexed) {
      final downloader = downloaders[index];
      final size = job.file.size;
      if (job.file.name == tokenizerZip.name) {
        final unzipped = p.join(p.dirname(job.dest), 'tokenizer.json');
        final tokenizer = modelFiles[1].size;
        if (await _heldLength(unzipped, tokenizer) < tokenizer) {
          needed += tokenizer;
        }
      }
      final ranges = _rangeResume(job.dest, job.url, job.file, downloader);
      final held = ranges?.held ?? await _heldLength(job.dest, size);
      final missing = size - held;
      if (missing > 0) needed += missing;
      final connections = downloader.maxConnections;
      if (ranges != null) {
        needed += ranges.largestUnassembled;
      } else if (missing > 0 &&
          connections >= 2 &&
          size >= downloader.segmentThresholdBytes) {
        needed += (size + connections - 1) ~/ connections;
      }
    }
    for (final entry in reused.entries) {
      if (p.equals(entry.value.source, entry.key)) continue;
      needed += entry.value.size;
    }
    if (needed == 0) return;
    final free = _freeBytesFor(mirrorDir);
    if (free == null || !DiskSpaceProbe.lacksSpace(free, needed)) return;
    throw StorageFullException(
      dir: mirrorDir,
      neededBytes: needed,
      freeBytes: free,
      message: AppL10n.strings.libraryDomain.mirrorNotEnoughDiskSpace(
        _volumeOf(mirrorDir),
        DiskSpaceProbe.formatBytes(needed),
        DiskSpaceProbe.formatBytes(free),
      ),
    );
  }

  /// The drive the mirror sits on: the message names it, not "semantic".
  static String _volumeOf(String dir) {
    final root = p.rootPrefix(p.absolute(dir));
    return root.isEmpty || root == '/' ? dir : root;
  }

  /// What the downloader resumes from `<dest>.segments` (prefix plus ranges);
  /// `null` when it would discard the state.
  ({int held, int largestUnassembled})? _rangeResume(
    String dest,
    String url,
    SemanticAsset file,
    PatchDownloader downloader,
  ) {
    if (downloader.maxConnections < 2 ||
        file.size < downloader.segmentThresholdBytes) {
      return null;
    }
    try {
      final state = jsonDecode(File('$dest.segments').readAsStringSync());
      if (state is! Map ||
          state['v'] != 1 ||
          state['token'] != file.sha256 ||
          state['url'] != url ||
          state['size'] != file.size ||
          state['sha256'] != file.sha256 ||
          (state['etag'] != null && state['etag'] is! String)) {
        return null;
      }
      final bounds = (state['bounds'] as List).cast<int>();
      final assembled = state['assembled'] as int;
      if (bounds.length < 3 ||
          bounds.first != 0 ||
          bounds.last != file.size ||
          assembled < 1 ||
          assembled > bounds.length - 1) {
        return null;
      }
      for (var i = 1; i < bounds.length; i++) {
        if (bounds[i] <= bounds[i - 1]) return null;
      }
      final target = File(dest);
      final destLength = target.existsSync() ? target.lengthSync() : 0;
      if (destLength >= file.size) return null;
      if (assembled > 1 && destLength < bounds[assembled]) return null;
      // A tail beyond the assembled prefix is cut by the next assembly.
      var held = destLength < bounds[assembled]
          ? destLength
          : bounds[assembled];
      var largest = 0;
      for (var i = assembled; i < bounds.length - 1; i++) {
        final length = bounds[i + 1] - bounds[i];
        if (length > largest) largest = length;
        final range = File('$dest.seg-$i');
        if (!range.existsSync()) continue;
        final have = range.lengthSync();
        if (have > length) return null;
        held += have;
      }
      return (held: held, largestUnassembled: largest);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<int> _heldLength(String path, int size) async {
    try {
      final file = File(path);
      if (!await file.exists()) return 0;
      final length = await file.length();
      return length > size ? size : length;
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
    SemanticModelGeneration generation = SemanticModelGeneration.round2,
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
      final path = p.join(mirrorDir, name, _spec(generation).folder, file.name);
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
    required SemanticModelGeneration generation,
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
    if (model is! Map ||
        model['family_id'] != _spec(generation).familyId ||
        model['tokenizer_checksum'] != _spec(generation).tokenizerChecksum) {
      _invalid();
    }
    final text = (identity as Map)['text'];
    // A manifest built before these fields existed reads as version 0.
    final rawLine = text is Map ? text['line_text_version'] : null;
    final rawKey = text is Map ? text['key_version'] : null;
    final lineText = rawLine is int ? rawLine : 0;
    final keyVersion = rawKey is int ? rawKey : 0;
    if (lineText != kSemanticEngineText.lineTextVersion ||
        keyVersion != kSemanticEngineText.keyVersion) {
      throw SemanticEngineIncompatibleException(
        lineTextVersion: lineText,
        keyVersion: keyVersion,
      );
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

  /// The `semantic.json` document: the Round2 plans in the fields old
  /// launchers read, and every plan (any generation) under `plans`.
  Map<String, Object?> _mirrorJson(List<_Meta> plans) {
    final round2 = plans
        .where((m) => m.generation == SemanticModelGeneration.round2)
        .toList();
    final legacy = round2.where((m) => !m.windows).firstOrNull;
    final windows = round2.where((m) => m.windows).firstOrNull;
    final first = plans.first;
    final json = <String, Object?>{
      if (legacy != null || windows != null)
        ...(legacy ?? windows)!.toJson()
      else ...{
        // No Round2 plan: nothing an old launcher could install.
        'libraryTag': first.libraryTag,
        'libraryVersion': first.libraryVersion,
      },
    };
    if (legacy != null && windows != null) {
      json['windows'] = windows.toJson();
    }
    json['plans'] = [for (final plan in plans) plan.toJson()];
    return json;
  }

  _Meta? _pick(
    List<_Meta> metas,
    SemanticModelGeneration generation, {
    bool preferWindows = false,
  }) {
    final own = metas.where((m) => m.generation == generation).toList();
    final windows = own.where((m) => m.windows).firstOrNull;
    final legacy = own.where((m) => !m.windows).firstOrNull;
    return preferWindows ? (windows ?? legacy) : (legacy ?? windows);
  }

  Future<_Meta?> _metadata(
    String mirrorDir, {
    required SemanticModelGeneration generation,
    bool preferWindows = false,
  }) async => _pick(
    await _allMetadata(mirrorDir),
    generation,
    preferWindows: preferWindows,
  );

  /// Every plan of `semantic.json`. A document without `plans` is the
  /// pre-generation format, which could only ever describe Round2.
  Future<List<_Meta>> _allMetadata(String mirrorDir) async =>
      (await _readDrive(mirrorDir)).metas;

  /// [fileExists] with [complete] false: a `semantic.json` this tool could
  /// not fully read, which is not the same as no file.
  Future<({List<_Meta> metas, bool fileExists, bool complete})> _readDrive(
    String mirrorDir, {
    bool requireRead = false,
  }) async {
    final file = File(p.join(mirrorDir, manifestFileName));
    bool exists;
    try {
      exists = await file.exists();
    } on FileSystemException {
      if (requireRead) rethrow;
      exists = true;
    }
    if (!exists) {
      return (metas: const <_Meta>[], fileExists: false, complete: true);
    }
    const unreadable = (metas: <_Meta>[], fileExists: true, complete: false);
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic> ||
          value['libraryVersion'] is! int ||
          _tagVersion(value['libraryTag']) != value['libraryVersion']) {
        return unreadable;
      }
      final tag = value['libraryTag'] as String;
      final version = value['libraryVersion'] as int;
      final raw = value['plans'];
      final metas = <_Meta>[];
      var complete = true;
      if (raw is List) {
        for (final entry in raw) {
          _Meta? meta;
          if (entry is Map<String, dynamic>) {
            final generation = SemanticModelGeneration.byId(
              entry['generation'],
            );
            if (generation != null &&
                entry['libraryTag'] == tag &&
                entry['libraryVersion'] == version) {
              meta = _parseMeta(entry, generation);
            }
          }
          if (meta == null) {
            complete = false;
          } else {
            metas.add(meta);
          }
        }
        return (
          metas: metas,
          fileExists: true,
          complete: complete && metas.isNotEmpty,
        );
      }
      final legacy = _parseMeta(value, SemanticModelGeneration.round2);
      if (legacy != null) metas.add(legacy);
      final windows = value['windows'];
      if (windows is Map<String, dynamic> &&
          windows['family'] == SemanticVectorsFamily.windows.id &&
          windows['libraryTag'] == tag &&
          windows['libraryVersion'] == version) {
        final meta = _parseMeta(windows, SemanticModelGeneration.round2);
        if (meta != null) metas.add(meta);
      }
      return (metas: metas, fileExists: true, complete: metas.isNotEmpty);
    } on FileSystemException {
      if (requireRead) rethrow;
      return unreadable;
    } on FormatException {
      return unreadable;
    }
  }

  _Meta? _parseMeta(
    Map<String, dynamic> value,
    SemanticModelGeneration generation,
  ) {
    final tag = value['libraryTag'];
    final version = value['libraryVersion'];
    if (tag is! String || version is! int) return null;
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
        generation: generation,
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
              '${family!.deltaReleaseTagPrefixFor(generation)}${raw['libraryTag']}' ||
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
      generation: generation,
      family: family!,
      chain: chain,
      libraryTag: tag,
      libraryVersion: version,
      base: base,
      identityDigest: digest,
      steps: steps,
    );
  }

  /// The library version the drive holds smart-search data for.
  Future<int?> mirroredVersion(String mirrorDir) async =>
      (await _allMetadata(mirrorDir)).firstOrNull?.libraryVersion;

  /// The model generations the drive holds data for.
  Future<Set<SemanticModelGeneration>> mirroredGenerations(
    String mirrorDir,
  ) async => {
    for (final meta in await _allMetadata(mirrorDir)) meta.generation,
  };
  Future<bool> _matches(
    String path,
    SemanticAsset file, [
    bool Function()? isCancelled,
  ]) async {
    try {
      await _verify(path, file, isCancelled);
      return true;
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
  }

  Future<void> _requireSize(String path, SemanticAsset file) async {
    final source = File(path);
    final strings = AppL10n.strings.libraryDomain;
    if (!await source.exists()) {
      throw FormatException(strings.localSourceNotFound(path));
    }
    final length = await source.length();
    if (length != file.size) {
      throw FormatException(
        strings.localFileSizeMismatch(file.size, length, path),
      );
    }
  }

  Future<void> _verify(
    String path,
    SemanticAsset file, [
    bool Function()? isCancelled,
    GuardedSink? copyTo,
  ]) async {
    _cancel(isCancelled);
    await _requireSize(path, file);
    final source = File(path);
    final hash = Sha256Stream();
    try {
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
      if (hash.close() != file.sha256) {
        throw FormatException(
          AppL10n.strings.libraryDomain.localFileHashMismatch(path),
        );
      }
    } finally {
      hash.dispose();
    }
  }

  Future<({_Meta meta, List<_LoadedUnit> units})?> _load(
    String mirrorDir,
    int version, {
    required SemanticModelGeneration generation,
    bool preferWindows = false,
    bool reportIncompatible = false,
  }) async {
    try {
      return await _loadSource(
        mirrorDir,
        version,
        generation: generation,
        preferWindows: preferWindows,
        requireRead: false,
      );
    } on IOException {
      return null;
    } on FormatException {
      return null;
    } on SemanticEngineIncompatibleException {
      if (reportIncompatible) rethrow;
      return null;
    }
  }

  Future<({_Meta meta, List<_LoadedUnit> units})?> _loadSource(
    String mirrorDir,
    int version, {
    required SemanticModelGeneration generation,
    bool preferWindows = false,
    bool requireRead = true,
  }) async {
    try {
      final drive = await _readDrive(mirrorDir, requireRead: requireRead);
      final meta = _pick(drive.metas, generation, preferWindows: preferWindows);
      if (meta == null || meta.libraryVersion != version) return null;
      final spec = _spec(generation);
      final dir = p.join(mirrorDir, meta.libraryTag);
      for (final file in spec.files) {
        await _requireSize(p.join(dir, spec.folder, file.name), file);
      }
      final units = <_LoadedUnit>[];
      for (final step in meta.units) {
        final path = p.join(dir, 'vectors', step.manifest.name);
        await _verify(path, step.manifest);
        final parsed = _vectors(
          jsonDecode(await File(path).readAsString()),
          tag: step.libraryTag,
          version: step.to,
          family: meta.family,
          generation: generation,
          deltaName: step.from > 0 ? step.manifest.name : null,
        );
        if (parsed.from != step.from ||
            (meta.windows && parsed.identityDigest != meta.identityDigest)) {
          return null;
        }
        for (final file in parsed.files) {
          await _requireSize(p.join(dir, 'vectors', file.name), file);
        }
        units.add(
          _LoadedUnit(
            step: step,
            files: parsed.files,
            segmentSize: parsed.segmentSize,
            identityDigest: parsed.identityDigest,
          ),
        );
      }
      return (meta: meta, units: units);
    } on FileSystemException catch (error, stack) {
      throwStorageAware(error, stack, mirrorDir);
    }
  }

  /// Whether installing from the drive is the next step; see [assess] for
  /// every other outcome. [generation] is what the installed Otzaria proves
  /// it reads; `null` = unproven.
  Future<bool> pending({
    required String mirrorDir,
    required String dbPath,
    required int libraryVersion,
    String? vectorsRootPath,
    bool preferencesReady = true,
    bool supportsWindows = false,
    required SemanticModelGeneration? generation,
    bool needsBase = false,
    void Function()? onRecoveryVerified,
  }) async => (await assess(
    mirrorDir: mirrorDir,
    dbPath: dbPath,
    libraryVersion: libraryVersion,
    support: SemanticAppSupport(
      generation: generation,
      windows: supportsWindows,
      basis: generation == null
          ? SemanticSupportBasis.unproven
          : SemanticSupportBasis.declared,
    ),
    vectorsRootPath: vectorsRootPath,
    preferencesReady: preferencesReady,
    needsBase: needsBase,
    onRecoveryVerified: onRecoveryVerified,
  )).installable;

  /// What the drive and this computer hold for the model generation and
  /// vector shape the installed Otzaria reads. Reads small files only (the
  /// model, the set's pointers); never the gigabytes of vectors.
  Future<SmartSearchStatus> assess({
    required String mirrorDir,
    required String dbPath,
    required int libraryVersion,
    required SemanticAppSupport support,
    String? vectorsRootPath,
    bool preferencesReady = true,
    bool needsBase = false,
    void Function()? onRecoveryVerified,
  }) async {
    final root = vectorsRootPath ?? p.dirname(p.dirname(dbPath));
    final vectorsDir = p.join(root, 'vectors');
    final live = (await readInstalledSets(vectorsDir)).firstOrNull;
    final drive = await _readDrive(mirrorDir);
    final metas = drive.metas;
    final driveGenerations = {for (final meta in metas) meta.generation};
    final generation = support.generation;
    String key(_Meta? meta) => [
      support.proofKey,
      libraryVersion,
      drive.fileExists,
      drive.complete,
      meta?.generation.id,
      meta?.family.id,
      meta?.libraryTag,
      meta?.base.sha256,
      meta?.identityDigest,
      live?.libraryVersion,
      live?.libraryReleaseTag,
      live?.identityDigest,
      live?.familyId,
      live?.windows,
      preferencesReady,
    ].join('|');
    SmartSearchStatus status(
      SmartSearchState state,
      SmartSearchReason reason, {
      _Meta? meta,
      Set<SmartSearchPart> missing = const {},
      Set<SmartSearchPart> present = const {},
      Object? incompatibility,
    }) => SmartSearchStatus(
      state: state,
      reason: reason,
      required: generation == null
          ? null
          : (
              generation: generation,
              family: support.windows
                  ? SemanticVectorsFamily.windows
                  : SemanticVectorsFamily.legacy,
            ),
      driveGenerations: driveGenerations,
      installedGeneration: live?.generation,
      missing: missing,
      present: present,
      incompatibility: incompatibility,
      proofKey: key(meta),
    );
    if (generation == null) {
      return status(
        support.unrecognizedFamilies.isNotEmpty
            ? SmartSearchState.unsupported
            : SmartSearchState.unverified,
        support.unrecognizedFamilies.isNotEmpty
            ? SmartSearchReason.appFamilyUnknown
            : SmartSearchReason.appUnproven,
      );
    }
    final spec = _spec(generation);
    final modelDir = p.join(p.dirname(dbPath), spec.folder);
    final meta = _pick(metas, generation, preferWindows: support.windows);
    if (meta == null) {
      if (drive.fileExists && !drive.complete) {
        return status(
          SmartSearchState.unverified,
          SmartSearchReason.driveUnreadable,
        );
      }
      if (metas.isNotEmpty) {
        return status(
          SmartSearchState.driveNotMatching,
          SmartSearchReason.driveOtherGeneration,
        );
      }
      final inUse =
          preferencesReady ||
          live != null ||
          await Directory(modelDir).exists();
      return status(
        inUse ? SmartSearchState.needsDriveDownload : SmartSearchState.notInUse,
        inUse ? SmartSearchReason.driveEmpty : SmartSearchReason.none,
      );
    }
    if (meta.libraryVersion != libraryVersion) {
      return status(
        SmartSearchState.driveNotMatching,
        SmartSearchReason.driveOlderVersion,
        meta: meta,
      );
    }
    if (meta.windows && !support.windows) {
      return status(
        SmartSearchState.driveNotMatching,
        SmartSearchReason.driveOtherShape,
        meta: meta,
      );
    }
    if (_keepsWindowsSet(meta, live, support.windows, generation)) {
      return status(
        SmartSearchState.driveNotMatching,
        SmartSearchReason.keepsWindowsSet,
        meta: meta,
      );
    }
    final ({_Meta meta, List<_LoadedUnit> units})? data;
    try {
      data = await _load(
        mirrorDir,
        libraryVersion,
        generation: generation,
        preferWindows: support.windows,
        reportIncompatible: true,
      );
    } on SemanticEngineIncompatibleException catch (fault) {
      return status(
        SmartSearchState.unsupported,
        SmartSearchReason.engineIncompatible,
        meta: meta,
        incompatibility: fault,
      );
    }
    if (data == null) {
      return status(
        SmartSearchState.needsDriveDownload,
        SmartSearchReason.driveIncomplete,
        meta: meta,
      );
    }
    final missing = <SmartSearchPart>{};
    final present = <SmartSearchPart>{};
    final vectorsCurrent =
        live != null &&
        live.markerConsistent &&
        live.familyId == spec.familyId &&
        (!meta.windows
            ? !live.windows &&
                  live.libraryVersion == meta.libraryVersion &&
                  live.libraryReleaseTag == meta.libraryTag &&
                  _sameIdentity(
                    live.identityDigest,
                    data.units.single.identityDigest,
                  )
            : live.windows &&
                  live.identityDigest == meta.identityDigest &&
                  (meta.chain
                      ? live.libraryVersion >= meta.libraryVersion
                      : live.libraryVersion > meta.libraryVersion ||
                            (live.libraryVersion == meta.libraryVersion &&
                                live.libraryReleaseTag == meta.libraryTag)));
    (vectorsCurrent ? present : missing).add(SmartSearchPart.vectors);
    var modelOk = true;
    for (final file in spec.files) {
      if (!await _matches(p.join(modelDir, file.name), file)) {
        modelOk = false;
        break;
      }
    }
    (modelOk ? present : missing).add(SmartSearchPart.model);
    (preferencesReady ? present : missing).add(SmartSearchPart.preferences);
    if (missing.isEmpty && needsBase && live != null) {
      // A repair by Otzaria can keep the same version and identity.
      // Verify its contents before clearing the recorded failure.
      final work = await Directory.systemTemp.createTemp('semantic-recovery-');
      SemanticVectorsEngine? engine;
      try {
        engine = await _openEngine(work.path);
        final info = await engine.info(vectorsDir);
        if (!info.present ||
            info.libraryVersion != live.libraryVersion ||
            info.identityDigest != live.identityDigest) {
          missing.add(SmartSearchPart.vectors);
        } else {
          await engine.verify(vectorsDir);
        }
      } on SemanticError {
        missing.add(SmartSearchPart.vectors);
      } finally {
        await disposeSemanticEngineWork(engine, work);
      }
      if (missing.isEmpty) onRecoveryVerified?.call();
    }
    present.removeAll(missing);
    if (missing.isNotEmpty) {
      return status(
        SmartSearchState.readyOnDrive,
        SmartSearchReason.partsMissing,
        meta: meta,
        missing: missing,
        present: present,
      );
    }
    return status(
      SmartSearchState.installedVerified,
      SmartSearchReason.none,
      meta: meta,
      present: present,
    );
  }

  /// A machine already on the preferred windows family waits for a windows
  /// download rather than taking the anchor set back, as Otzaria does, but
  /// only when that set is of the generation the app reads now.
  static bool _keepsWindowsSet(
    _Meta meta,
    SemanticInstalledSet? live,
    bool supportsWindows,
    SemanticModelGeneration generation,
  ) =>
      !meta.windows &&
      supportsWindows &&
      live != null &&
      live.windows &&
      live.generation == generation;

  /// A set installed under another identity is not the published one. A
  /// published manifest with no digest has nothing to compare; a set with no
  /// recorded identity cannot be proven to be the published one.
  static bool _sameIdentity(String installed, String published) =>
      published.isEmpty || (installed.isNotEmpty && installed == published);

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
        final model = set['identity'] is Map
            ? (set['identity'] as Map)['model']
            : null;
        final family = model is Map ? model['family_id'] : null;
        final chunking = model is Map ? model['chunking_identity'] : null;
        sets.add(
          SemanticInstalledSet(
            libraryVersion: set['library_version'] as int,
            libraryReleaseTag: set['library_release_tag'] as String,
            identityDigest: identity,
            windows: identity.isNotEmpty && marker == identity,
            familyId: family is String ? family : null,
            chunkingIdentity: chunking is int ? chunking : null,
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

  Future<void> _ensureOwnedDirectory(
    String path, {
    SemanticModelSpec? spec,
  }) async {
    final directory = Directory(path);
    if (await directory.exists()) {
      var owned = false;
      for (final marker in const ['.otzaria-semantic', 'CURRENT', 'PREVIOUS']) {
        if (await File(p.join(path, marker)).exists()) owned = true;
      }
      if (!owned && spec != null) {
        final identity = spec.files
            .where((file) => file.name == 'model.json')
            .firstOrNull;
        final names = spec.files.map((file) => file.name).toSet();
        final entries = await directory.list(followLinks: false).toList();
        owned =
            identity != null &&
            entries.every(
              (entry) =>
                  entry is File && names.contains(p.basename(entry.path)),
            ) &&
            await _matches(p.join(path, identity.name), identity, null);
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
    final sink = GuardedSink(File(segmentPath).openWrite(), segmentPath);
    try {
      for (final part in parts) {
        _cancel(isCancelled);
        final source = p.join(vectorsDir, part.name);
        await _verify(source, part, isCancelled, sink);
      }
    } catch (_) {
      await sink.closeAfterFailure();
      rethrow;
    }
    await sink.close();
    return segmentPath;
  }

  void _ensureSpace(String path, int needed) {
    final free = _freeBytesFor(path);
    if (free == null || free >= needed) return;
    throw StorageFullException(
      dir: path,
      neededBytes: needed,
      freeBytes: free,
      message: AppL10n.strings.libraryDomain.notEnoughDiskSpace(
        path,
        DiskSpaceProbe.formatBytes(needed),
        DiskSpaceProbe.formatBytes(free),
      ),
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
    required SemanticModelGeneration? generation,
    bool? targetReadsLineText4 = true,
    Future<void> Function()? beforeActivate,
    void Function(String)? onStage,
    bool Function()? isCancelled,
  }) async {
    _cancel(isCancelled);
    if (generation == null) {
      throw const SemanticEngineIncompatibleException(
        lineTextVersion: 0,
        keyVersion: 0,
        reason: SemanticIncompatibilityReason.otzariaUnproven,
      );
    }
    final spec = _spec(generation);
    final data = await _loadSource(
      mirrorDir,
      libraryVersion,
      generation: generation,
      preferWindows: supportsWindows,
    );
    if (data == null || (data.meta.windows && !supportsWindows)) {
      throw FormatException(
        AppL10n.strings.libraryDomain.semanticStatusNeedsDriveDownload,
      );
    }
    final meta = data.meta;
    onStage?.call(AppL10n.strings.libraryDomain.semanticInstalling);
    final root = vectorsRootPath ?? p.dirname(p.dirname(dbPath));
    final vectorsDir = p.join(root, 'vectors');
    final generationDir = p.join(mirrorDir, meta.libraryTag);
    final live = (await readInstalledSets(vectorsDir)).firstOrNull;
    if (_keepsWindowsSet(meta, live, supportsWindows, generation)) {
      return false;
    }
    if (targetReadsLineText4 != true) {
      throw SemanticEngineIncompatibleException(
        lineTextVersion: kSemanticEngineText.lineTextVersion,
        keyVersion: kSemanticEngineText.keyVersion,
        reason: targetReadsLineText4 == null
            ? SemanticIncompatibilityReason.otzariaUnproven
            : SemanticIncompatibilityReason.updateOtzaria,
      );
    }
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
        (spec.folder, spec.files),
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
          final source = p.join(generationDir, group.$1, file.name);
          await _verify(source, file, isCancelled);
        }
      }
      final segments = <String>[
        for (final unit in units)
          unit.files.length == 1
              ? p.join(generationDir, 'vectors', unit.files.single.name)
              : await concatenateVectorParts(
                  vectorsDir: p.join(generationDir, 'vectors'),
                  parts: unit.files,
                  workDir: work.path,
                  isCancelled: isCancelled,
                ),
      ];
      await beforeActivate?.call();
      final modelDirectory = p.join(p.dirname(dbPath), spec.folder);
      await _ensureOwnedDirectory(modelDirectory, spec: spec);
      await _ensureOwnedDirectory(vectorsDir);
      for (final file in spec.files) {
        _cancel(isCancelled);
        final source = p.join(generationDir, spec.folder, file.name);
        final target = p.join(p.dirname(dbPath), spec.folder, file.name);
        if (await _matches(target, file, isCancelled)) continue;
        _ensureSpace(p.dirname(target), file.size);
        await Directory(p.dirname(target)).create(recursive: true);
        final temporary = '$target.tmp';
        await File(source).copy(temporary);
        _cancel(isCancelled);
        await _verify(temporary, file, isCancelled);
        await File(temporary).rename(target);
      }
      _cancel(isCancelled);
      await File(
        p.join(p.dirname(dbPath), spec.folder, '.otzaria-semantic'),
      ).writeAsString('');
      final modelIdentity = meta.windows
          ? spec.windowsIdentityJson
          : await File(
              p.join(p.dirname(dbPath), spec.folder, 'model.json'),
            ).readAsString();
      engine ??= await _openEngine(work.path);
      for (final (index, unit) in units.indexed) {
        final manifestJson = await File(
          p.join(generationDir, 'vectors', unit.step.manifest.name),
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
          final failure = storageFailureFromEngine(error, vectorsDir);
          if (failure != null) throw failure;
          rethrow;
        }
        if (!report.alreadyApplied && report.libraryVersion != unit.step.to) {
          _invalid();
        }
      }
      if (meta.chain) {
        await beforeActivate?.call();
        _cancel(isCancelled);
        try {
          await engine.compact(vectorsDir, isCancelled: isCancelled);
        } catch (error) {
          final failure = storageFailureFromEngine(error, vectorsDir);
          if (failure != null) throw failure;
          rethrow;
        }
      }
      return !meta.chain;
    } on FileSystemException catch (error, stack) {
      throwStorageAware(error, stack, vectorsDir);
    } finally {
      await disposeSemanticEngineWork(engine, work);
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
  Future<void> verify(String vectorsDir) =>
      _withCancellation(null, (token) async {
        await _engine.verifySemanticVectors(
          vectorsDir: vectorsDir,
          cancellation: token,
        );
      });

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
