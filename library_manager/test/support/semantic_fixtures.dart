import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticError, SemanticErrorKind, SemanticVectorsInstallInput;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;

const identityA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const identityB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// QA491 windows and anchor identities.
const identityC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const identityD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

String libraryTagOf(int version) => 'v$version-20261001000000';

String baseManifestName(int v) =>
    'otzaria-vectors-abcd1234-v$v-base.manifest.json';
String baseSegmentName(int v) => 'otzaria-vectors-abcd1234-v$v-base.oxv.zst';
String legacyManifestName(int v) =>
    'otzaria-vectors-legacy-v$v-base.manifest.json';
String deltaManifestName(int from, int to) =>
    'otzaria-vectors-abcd1234-v$from-v$to.manifest.json';
String deltaSegmentName(int from, int to) =>
    'otzaria-vectors-abcd1234-v$from-v$to.oxv.zst';

const fakeModelJson = '{"fake":"legacy model identity"}';
final _fakeModelBytes = <String, List<int>>{
  'model.json': utf8.encode(fakeModelJson),
  'LICENSE': utf8.encode('fake license'),
};

/// Small stand-ins for the pinned model, so a sync needs no real model.
final List<SemanticAsset> fakeModels = [
  for (final MapEntry(:key, :value) in _fakeModelBytes.entries)
    (name: key, size: value.length, sha256: Sha256Stream.ofBytes(value)),
];

const fakeQa491ModelJson = '{"fake":"qa491 model identity"}';
final _fakeQa491Bytes = <String, List<int>>{
  'model.json': utf8.encode(fakeQa491ModelJson),
  'LICENSE': utf8.encode('fake qa491 license'),
};

/// A QA491 spec with small stand-ins for its files (pass as `specs:`).
final SemanticModelSpec fakeQa491Spec = SemanticModelSpec(
  generation: SemanticModelGeneration.qa491,
  folder: SemanticModelSpec.qa491.folder,
  baseUrl: SemanticModelSpec.qa491.baseUrl,
  familyId: SemanticModelSpec.qa491.familyId,
  tokenizerChecksum: SemanticModelSpec.qa491.tokenizerChecksum,
  files: [
    for (final MapEntry(:key, :value) in _fakeQa491Bytes.entries)
      (name: key, size: value.length, sha256: Sha256Stream.ofBytes(value)),
  ],
  windowsIdentityJson: kQa491WindowsModelIdentityJson,
);

final fakeSpecs = <SemanticModelGeneration, SemanticModelSpec>{
  SemanticModelGeneration.qa491: fakeQa491Spec,
};

Future<void> installModels(String dir, {bool qa491 = false}) async {
  await Directory(dir).create(recursive: true);
  await File(p.join(dir, '.otzaria-semantic')).writeAsString('');
  for (final MapEntry(:key, :value)
      in (qa491 ? _fakeQa491Bytes : _fakeModelBytes).entries) {
    await File(p.join(dir, key)).writeAsBytes(value);
  }
}

/// SeforimLibrary's vector releases, served from memory.
class FakeVectorsGithub {
  final _releases = <String, Map<String, Object?>>{};
  final _files = <String, List<int>>{};
  final apiTags = <String>[];
  final downloads = <String>[];
  final failingTags = <String>{};
  final garbledTags = <String>{};
  final truncated = <String>{};

  void addAsset(String releaseTag, String name) {
    final release = _releases[releaseTag]!;
    (release['assets']! as List).add({
      'name': name,
      'size': 1,
      'browser_download_url': '$_download/$releaseTag/$name',
    });
  }

  static const _download =
      'https://github.com/Otzaria/SeforimLibrary/releases/download';

  void _release(
    String releaseTag, {
    required String manifestName,
    required Map<String, Object?> manifest,
    required String segmentName,
    required List<int> segment,
  }) {
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final sha = Sha256Stream.ofBytes(manifestBytes);
    _files['$releaseTag/$manifestName'] = manifestBytes;
    _files['$releaseTag/$segmentName'] = segment;
    _releases[releaseTag] = {
      'tag_name': releaseTag,
      'prerelease': true,
      'body': 'Manifest: `$manifestName`, SHA-256 `$sha`',
      'assets': [
        {
          'name': manifestName,
          'size': manifestBytes.length,
          'digest': 'sha256:$sha',
          'browser_download_url': '$_download/$releaseTag/$manifestName',
        },
        {
          'name': segmentName,
          'size': segment.length,
          'browser_download_url': '$_download/$releaseTag/$segmentName',
        },
      ],
    };
  }

  static Map<String, Object?> manifestOf({
    required String kind,
    required int from,
    required int to,
    required String file,
    required List<int> segment,
    String identity = identityA,
    int chunking = kWindowsChunkingIdentity,
    int lineTextVersion = 4,
    int keyVersion = 1,
    bool emptyText = false,
    String? familyId,
  }) => {
    'format': 'otzaria-vectors-release',
    'formatVersion': 1,
    'kind': kind,
    'identity': {
      'text': emptyText
          ? <String, Object?>{}
          : {'line_text_version': lineTextVersion, 'key_version': keyVersion},
      'model': {
        'family_id': familyId ?? SemanticModelSpec.round2.familyId,
        'tokenizer_checksum': SemanticSearchAssets.modelFiles[1].sha256,
        'chunking_identity': chunking,
      },
      'store': {'store_format_version': 3, 'vector_precision': 'rot192-i8i4'},
    },
    'identityDigest': identity,
    'codecParamsSha256': '0' * 64,
    'fromLibraryVersion': from,
    'toLibraryVersion': to,
    'libraryReleaseTag': libraryTagOf(to),
    'segment': {
      'sha256': Sha256Stream.ofBytes(segment),
      'size': segment.length * 4,
    },
    'files': [
      {
        'file': file,
        'compression': 'zstd',
        'sha256': Sha256Stream.ofBytes(segment),
        'size': segment.length,
      },
    ],
  };

  static List<int> _bytes(int size, int seed) =>
      List<int>.generate(size, (i) => (i * 31 + seed) % 251);

  void windowsBase(
    int v, {
    int segmentSize = 1000,
    String identity = identityA,
    int chunking = kWindowsChunkingIdentity,
    int lineTextVersion = 4,
    int keyVersion = 1,
    bool emptyText = false,
  }) {
    final segment = _bytes(segmentSize, v);
    _release(
      'vectors-windows-${libraryTagOf(v)}',
      manifestName: baseManifestName(v),
      manifest: manifestOf(
        kind: 'base',
        from: 0,
        to: v,
        file: baseSegmentName(v),
        segment: segment,
        identity: identity,
        chunking: chunking,
        lineTextVersion: lineTextVersion,
        keyVersion: keyVersion,
        emptyText: emptyText,
      ),
      segmentName: baseSegmentName(v),
      segment: segment,
    );
  }

  void legacyBase(
    int v, {
    int lineTextVersion = 4,
    int keyVersion = 1,
    bool emptyText = false,
    String identity = '',
  }) {
    final segment = _bytes(500, v + 7);
    _release(
      'vectors-${libraryTagOf(v)}',
      manifestName: legacyManifestName(v),
      manifest: manifestOf(
        kind: 'base',
        from: 0,
        to: v,
        file: 'legacy-v$v.oxv.zst',
        segment: segment,
        identity: identity,
        chunking: 2685558872390372738,
        lineTextVersion: lineTextVersion,
        keyVersion: keyVersion,
        emptyText: emptyText,
      ),
      segmentName: 'legacy-v$v.oxv.zst',
      segment: segment,
    );
  }

  /// QA491 base of [v]: windows form (`vectors-qa491-windows-`) or anchor.
  void qa491Base(
    int v, {
    bool windows = false,
    String? identity,
    int segmentSize = 800,
    int lineTextVersion = 4,
    int keyVersion = 1,
  }) {
    final segment = _bytes(segmentSize, v + (windows ? 13 : 17));
    final digest = identity ?? (windows ? identityC : identityD);
    final manifestName =
        'otzaria-vectors-qa491${windows ? 'w' : 'a'}-v$v-base.manifest.json';
    final segmentName =
        'otzaria-vectors-qa491${windows ? 'w' : 'a'}-v$v-base.oxv.zst';
    _release(
      'vectors-qa491-${windows ? 'windows-' : ''}${libraryTagOf(v)}',
      manifestName: manifestName,
      manifest: manifestOf(
        kind: 'base',
        from: 0,
        to: v,
        file: segmentName,
        segment: segment,
        identity: digest,
        chunking: windows ? kWindowsChunkingIdentity : 2685558872390372738,
        lineTextVersion: lineTextVersion,
        keyVersion: keyVersion,
        familyId: SemanticModelSpec.qa491.familyId,
      ),
      segmentName: segmentName,
      segment: segment,
    );
  }

  /// QA491 windows delta of [from]..[to].
  void qa491Delta(int from, int to, {String? identity, int segmentSize = 40}) {
    final segment = _bytes(segmentSize, from * 100 + to + 5);
    _release(
      'vectors-qa491-windows-delta-${libraryTagOf(to)}',
      manifestName: 'otzaria-vectors-qa491w-v$from-v$to.manifest.json',
      manifest: manifestOf(
        kind: 'delta',
        from: from,
        to: to,
        file: 'otzaria-vectors-qa491w-v$from-v$to.oxv.zst',
        segment: segment,
        identity: identity ?? identityC,
        familyId: SemanticModelSpec.qa491.familyId,
      ),
      segmentName: 'otzaria-vectors-qa491w-v$from-v$to.oxv.zst',
      segment: segment,
    );
  }

  /// [manifestFrom] lets the manifest disagree with the asset name.
  void delta(
    int from,
    int to, {
    int segmentSize = 50,
    String identity = identityA,
    int? manifestFrom,
    int lineTextVersion = 4,
  }) {
    final segment = _bytes(segmentSize, from * 100 + to);
    _release(
      'vectors-windows-delta-${libraryTagOf(to)}',
      manifestName: deltaManifestName(from, to),
      manifest: manifestOf(
        kind: 'delta',
        from: manifestFrom ?? from,
        to: to,
        file: deltaSegmentName(from, to),
        segment: segment,
        identity: identity,
        lineTextVersion: lineTextVersion,
      ),
      segmentName: deltaSegmentName(from, to),
      segment: segment,
    );
  }

  late final MockClient client = MockClient((request) async {
    final url = request.url;
    if (url.host == 'api.github.com') {
      final tag = url.pathSegments.last;
      apiTags.add(tag);
      if (failingTags.contains(tag)) return http.Response('', 500);
      if (garbledTags.contains(tag)) return http.Response('{"tag_name":', 200);
      final release = _releases[tag];
      return release == null
          ? http.Response('{"message":"Not Found"}', 404)
          : http.Response(jsonEncode(release), 200);
    }
    final name = url.pathSegments.last;
    downloads.add(name);
    final qa491Model = url.toString().startsWith(
      SemanticModelSpec.qa491.baseUrl,
    );
    if (qa491Model ||
        url.toString().startsWith(SemanticSearchAssets.modelBaseUrl)) {
      final bytes = (qa491Model ? _fakeQa491Bytes : _fakeModelBytes)[name];
      return bytes == null
          ? http.Response('', 404)
          : http.Response.bytes(bytes, 200);
    }
    final key = url.pathSegments.skip(4).join('/');
    final bytes = _files[key];
    return bytes == null
        ? http.Response('', 404)
        : http.Response.bytes(
            truncated.contains(name) ? bytes.sublist(1) : bytes,
            200,
          );
  });
}

/// A set as the engine leaves it: pointer, `set.json`, one segment.
Future<void> writeInstalledSet(
  String vectors, {
  required int version,
  String identity = identityA,
  bool windows = true,
  String? familyId,
  bool omitFamily = false,
}) async {
  const segment = 'segments/0123456789abcdef0123456789abcdef.oxv';
  final segmentFile = File(p.join(vectors, segment));
  await segmentFile.parent.create(recursive: true);
  await segmentFile.writeAsBytes([1, 2, 3]);
  final set = utf8.encode(
    jsonEncode({
      'format': 'otzaria-vector-set',
      'format_version': 1,
      'generation': version,
      'identity': {
        'model': {
          if (!omitFamily)
            'family_id': familyId ?? SemanticModelSpec.round2.familyId,
          'chunking_identity': windows
              ? kWindowsChunkingIdentity
              : 2685558872390372738,
        },
      },
      'identity_digest': identity,
      'library_version': version,
      'library_release_tag': libraryTagOf(version),
      'segments': [
        {'file': segment, 'size': 3},
      ],
    }),
  );
  final setPath = 'gen-${version.toString().padLeft(6, '0')}/set.json';
  await File(p.join(vectors, setPath)).create(recursive: true);
  await File(p.join(vectors, setPath)).writeAsBytes(set);
  await File(p.join(vectors, 'CURRENT')).writeAsString(
    jsonEncode({
      'generation': version,
      'set': setPath,
      'set_sha256': Sha256Stream.ofBytes(set),
    }),
  );
  await File(p.join(vectors, '.otzaria-semantic')).writeAsString('');
  final marker = File(
    p.join(vectors, SemanticSearchAssets.windowsIdentityFileName),
  );
  if (windows) {
    await marker.writeAsString(identity);
  } else if (await marker.exists()) {
    await marker.delete();
  }
}

class FakeVectorsEngine implements SemanticVectorsEngine {
  FakeVectorsEngine({
    this.present = true,
    this.version = 0,
    this.identity = identityA,
    this.refuse = false,
    this.error,
    this.infoError,
    this.verifyError,
    this.onInstall,
  });

  final bool present;
  int version;
  final String identity;
  final bool refuse;
  final SemanticError? error;
  final SemanticError? verifyError;
  final verifications = <String>[];
  final SemanticError? infoError;
  final void Function(SemanticVectorsInstallInput input)? onInstall;
  final installs = <SemanticVectorsInstallInput>[];
  bool disposed = false;
  final compactions = <String>[];
  int? compactedVersion;
  Object? compactionError;

  @override
  Future<void> compact(
    String vectorsDir, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) {
      throw StateError('compaction called after cancellation');
    }
    compactions.add(vectorsDir);
    compactedVersion = version;
    final failure = compactionError;
    if (failure != null) throw failure;
  }

  @override
  Future<SemanticEngineInfo> info(String vectorsDir) async {
    final failure = infoError;
    if (failure != null) throw failure;
    return (
      present: present,
      libraryVersion: present ? version : 0,
      identityDigest: present ? identity : '',
    );
  }

  @override
  Future<void> verify(String vectorsDir) async {
    verifications.add(vectorsDir);
    final failure = verifyError;
    if (failure != null) throw failure;
  }

  @override
  Future<({int libraryVersion, bool alreadyApplied})> install(
    SemanticVectorsInstallInput input, {
    bool Function()? isCancelled,
  }) async {
    onInstall?.call(input);
    final failure = error;
    if (failure != null) throw failure;
    if (refuse) {
      throw const SemanticError(
        kind: SemanticErrorKind.artifactIncompatible,
        message: 'the delta does not follow the set',
      );
    }
    installs.add(input);
    version =
        (jsonDecode(input.manifestJson) as Map)['toLibraryVersion'] as int;
    return (libraryVersion: version, alreadyApplied: false);
  }

  @override
  void dispose() => disposed = true;
}

/// Applies [edit] to every record of `semantic.json` that describes a plan:
/// the top level, `windows` and each entry of `plans`.
Future<void> editMirrorMeta(
  String mirrorDir,
  void Function(Map<String, dynamic> record) edit,
) async {
  final file = File(p.join(mirrorDir, SemanticSearchAssets.manifestFileName));
  final meta = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  for (final record in [
    meta,
    if (meta['windows'] is Map) meta['windows'] as Map<String, dynamic>,
    for (final plan in (meta['plans'] as List?) ?? const [])
      plan as Map<String, dynamic>,
  ]) {
    edit(record);
  }
  await file.writeAsString(jsonEncode(meta));
}
