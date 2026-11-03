import 'package:otzaria_manager/otzaria_manager.dart'
    show SemanticModelGeneration;

export 'package:otzaria_manager/otzaria_manager.dart'
    show SemanticModelGeneration;

/// The two shapes of published smart-search vectors (anchor = `legacy`).
/// The model generation is a separate axis: see [SemanticModelGeneration].
enum SemanticVectorsFamily {
  legacy('vectors-', null, 'legacy'),
  windows('vectors-windows-', 'vectors-windows-delta-', 'windows');

  const SemanticVectorsFamily(
    this.releaseTagPrefix,
    this.deltaReleaseTagPrefix,
    this.id,
  );

  /// Round2's tags; use [releaseTagPrefixFor] for any other generation.
  final String releaseTagPrefix;
  final String? deltaReleaseTagPrefix;

  /// The value stored in `semantic.json` and in the per-machine record.
  final String id;

  String releaseTagPrefixFor(SemanticModelGeneration generation) =>
      switch ((generation, this)) {
        (SemanticModelGeneration.round2, _) => releaseTagPrefix,
        (SemanticModelGeneration.qa491, SemanticVectorsFamily.legacy) =>
          'vectors-qa491-',
        (SemanticModelGeneration.qa491, SemanticVectorsFamily.windows) =>
          'vectors-qa491-windows-',
      };

  String? deltaReleaseTagPrefixFor(SemanticModelGeneration generation) =>
      switch ((generation, this)) {
        (_, SemanticVectorsFamily.legacy) => null,
        (SemanticModelGeneration.round2, _) => deltaReleaseTagPrefix,
        (SemanticModelGeneration.qa491, _) => 'vectors-qa491-windows-delta-',
      };

  static SemanticVectorsFamily? byId(Object? id) {
    for (final family in values) {
      if (family.id == id) return family;
    }
    return null;
  }
}

/// A delta chain wins over the base only within these limits, as in Otzaria.
const kSemanticDeltaChainLimits = (maxSteps: 8, maxBaseSizeRatio: 0.5);

const kWindowsChunkingIdentity = 320260894818558297;

/// `identity.text` the bundled `otzaria_search_engine` accepts: its
/// `LINE_TEXT_VERSION` and the sidecar's key version. Move with that pin.
const kSemanticEngineText = (lineTextVersion: 4, keyVersion: 1);

/// Byte-identical to Otzaria's `meivin-round2-windows-onnx/model.json`;
/// explicit `\n` so a CRLF checkout cannot change the bytes it verifies.
const String kWindowsModelIdentityJson =
    '{\n'
    '  "family_id": "ArieLLL123/judaic-semantic-round2-onnx-zayit@1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca",\n'
    '  "tokenizer_checksum": "0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9",\n'
    '  "embedding_dim": 256,\n'
    '  "pooling": "in-graph",\n'
    '  "max_tokens": 256,\n'
    '  "embedding_text_version": 2,\n'
    '  "normalization_version": 1,\n'
    '  "chunking_identity": 320260894818558297,\n'
    '  "query_packages": [\n'
    '    {\n'
    '      "checksum": "9e408407922b4aab26dd148cbe4b9a0e573c65591cfc799ba28e991d77d9d065",\n'
    '      "quantization": "int8"\n'
    '    },\n'
    '    {\n'
    '      "checksum": "4a4a2ae88a86f15ffe6069bfcefc3abd13c207cec5d7aaef52c0c59d752ade46",\n'
    '      "quantization": "fp32"\n'
    '    }\n'
    '  ]\n'
    '}\n';

/// Byte-identical to Otzaria's `meivin-qa491-windows-onnx/model.json`.
const String kQa491WindowsModelIdentityJson =
    '{\n'
    '  "family_id": "otzaria/Meivin-Embed-QA491-native256",\n'
    '  "tokenizer_checksum": "0664287976ecb078bdfd8f5e5515dc87d8cb7f985a79a481aa1cdf7a7321c0e9",\n'
    '  "embedding_dim": 256,\n'
    '  "pooling": "in-graph",\n'
    '  "max_tokens": 256,\n'
    '  "query_max_tokens": 128,\n'
    '  "embedding_text_version": 2,\n'
    '  "normalization_version": 1,\n'
    '  "chunking_identity": 320260894818558297,\n'
    '  "query_packages": [\n'
    '    {\n'
    '      "checksum": "e90a67be02c077990c7bc2a6485f6872769ac2a71eb9779d25ceb1fcd97ac9b3",\n'
    '      "quantization": "int8"\n'
    '    },\n'
    '    {\n'
    '      "checksum": "5f80c47d3310a21fcc0c2f541fbb5732ba254555ef45afc2712cab63c8a33059",\n'
    '      "quantization": "fp32"\n'
    '    }\n'
    '  ]\n'
    '}\n';

/// What one machine's smart-search set looks like, as recorded on the drive.
class SemanticMachineState {
  const SemanticMachineState({
    required this.supportsWindows,
    required this.family,
    this.libraryVersion = 0,
    this.identityDigest = '',
    this.needsBase = false,
    this.generation = SemanticModelGeneration.round2,
  });

  final bool supportsWindows;

  /// `null` = nothing installed.
  final SemanticVectorsFamily? family;
  final int libraryVersion;
  final String identityDigest;

  /// A chain from the drive did not apply here; only a base can help.
  final bool needsBase;

  /// The model generation this machine's Otzaria reads; `null` = unknown (a
  /// record from before generations, or an app nothing proves). An unknown
  /// machine is never served by guesswork and never deleted.
  final SemanticModelGeneration? generation;

  Map<String, Object?> toJson() => {
    'supportsWindows': supportsWindows,
    'family': family?.id ?? 'none',
    'libraryVersion': libraryVersion,
    'identityDigest': identityDigest,
    'needsBase': needsBase,
    'generation': generation?.id ?? 'unknown',
  };

  static SemanticMachineState? fromJson(Object? json) {
    if (json is! Map ||
        json['supportsWindows'] is! bool ||
        json['libraryVersion'] is! int ||
        json['identityDigest'] is! String) {
      return null;
    }
    final family = SemanticVectorsFamily.byId(json['family']);
    if (family == null && json['family'] != 'none') return null;
    return SemanticMachineState(
      supportsWindows: json['supportsWindows'] as bool,
      family: family,
      libraryVersion: json['libraryVersion'] as int,
      identityDigest: json['identityDigest'] as String,
      needsBase: json['needsBase'] == true,
      generation: SemanticModelGeneration.byId(json['generation']),
    );
  }
}

/// What one download serves: a model generation in one vector shape.
typedef SemanticTarget = ({
  SemanticModelGeneration generation,
  SemanticVectorsFamily family,
});

/// The recorded machines a download serves.
class SemanticFleet {
  const SemanticFleet([
    this.machines = const [],
    this.fallbackGenerations = const [SemanticModelGeneration.round2],
  ]);

  final List<SemanticMachineState> machines;

  /// Served only while no machine of a known generation is recorded: what the
  /// drive's own installers read.
  final List<SemanticModelGeneration> fallbackGenerations;

  /// Recorded machines nothing proves a generation for; they shape no
  /// download and their records are kept.
  int get unknownGenerationMachines =>
      machines.where((m) => m.generation == null).length;

  List<SemanticMachineState> get _known =>
      machines.where((m) => m.generation != null).toList();

  /// The model generation of a single group.
  SemanticModelGeneration get generation =>
      _known.isEmpty ? fallbackGenerations.first : _known.first.generation!;

  SemanticVectorsFamily get family =>
      _known.isNotEmpty && _known.every((m) => m.supportsWindows)
      ? SemanticVectorsFamily.windows
      : SemanticVectorsFamily.legacy;

  /// Each generation and shape serves its own machines.
  List<SemanticFleet> get groups {
    final known = _known;
    if (known.isEmpty) {
      return [
        for (final generation in fallbackGenerations.toSet())
          SemanticFleet(const [], [generation]),
      ];
    }
    final groups = <SemanticFleet>[];
    for (final generation in SemanticModelGeneration.values) {
      final ofGeneration = known.where((m) => m.generation == generation);
      if (ofGeneration.isEmpty) continue;
      final anchor = ofGeneration.where((m) => !m.supportsWindows).toList();
      final windows = ofGeneration.where((m) => m.supportsWindows).toList();
      if (anchor.isNotEmpty) groups.add(SemanticFleet(anchor));
      if (windows.isNotEmpty) groups.add(SemanticFleet(windows));
    }
    return groups;
  }

  /// The lowest installed version when every machine holds a windows set of
  /// [identityDigest] that a chain may continue; otherwise `null` (base).
  int? chainStartFor(String identityDigest) {
    if (family != SemanticVectorsFamily.windows || identityDigest.isEmpty) {
      return null;
    }
    int? lowest;
    for (final machine in machines) {
      if (machine.needsBase ||
          machine.generation != generation ||
          machine.family != SemanticVectorsFamily.windows ||
          machine.identityDigest != identityDigest ||
          machine.libraryVersion <= 0) {
        return null;
      }
      if (lowest == null || machine.libraryVersion < lowest) {
        lowest = machine.libraryVersion;
      }
    }
    return lowest;
  }

  /// Every machine stands where a step of [chain] starts, or at [target].
  bool canApply(List<({int from, int to})> chain, int target) {
    final starts = {for (final step in chain) step.from};
    return machines.every(
      (m) => m.libraryVersion >= target || starts.contains(m.libraryVersion),
    );
  }
}

/// Which side must change before the published smart-search vectors install.
enum SemanticIncompatibilityReason {
  /// The vectors need a newer engine than this tool bundles.
  updateTool,

  /// The vectors fit this tool, but the target Otzaria is known not to read them.
  updateOtzaria,

  /// The vectors were built for an older engine than this tool bundles.
  republishAssets,

  /// The vectors fit this tool, but no version of the target Otzaria is known.
  otzariaUnproven,
}
