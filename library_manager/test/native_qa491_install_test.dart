import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;
import 'package:test/test.dart';

import 'support/native_engine.dart';

// Built with the native 7.0.1 sidecar (6b006b0): two synthetic 256-dimensional
// vectors, with the published QA491 identity including query_max_tokens=128.
void main() {
  final skip = nativeSkipReason();
  const fixture = 'test/support/native_qa491_set';
  const tag = 'v36-20261101064231';
  const manifestName = 'otzaria-vectors-0e87cbd9-v36-base.manifest.json';
  const generation = SemanticModelGeneration.qa491;
  const production = SemanticModelSpec.qa491;
  const support = SemanticAppSupport(
    generation: generation,
    windows: true,
    basis: SemanticSupportBasis.declared,
  );
  late Directory temp;
  late String mirror;
  late String root;
  late String db;
  late SemanticModelSpec spec;

  List<int> fixtureBytes(String name) =>
      File(p.join(fixture, name)).readAsBytesSync();

  SemanticAsset asset(String name, List<int> bytes) =>
      (name: name, size: bytes.length, sha256: Sha256Stream.ofBytes(bytes));

  SemanticSearchAssets assets() {
    final value = SemanticSearchAssets(
      specs: {generation: spec},
      nativeLibrary: ExternalLibrary.open(hookEngineLibrary()!),
    );
    addTearDown(value.dispose);
    return value;
  }

  Future<SmartSearchStatus> assess({void Function()? verified}) =>
      assets().assess(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 36,
        vectorsRootPath: root,
        support: support,
        needsBase: verified != null,
        onRecoveryVerified: verified,
      );

  Future<void> install() async {
    expect(
      await assets().install(
        generation: generation,
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 36,
        vectorsRootPath: root,
        supportsWindows: true,
      ),
      isTrue,
    );
  }

  setUp(() async {
    if (skip != null) return;
    temp = await Directory.systemTemp.createTemp('native-qa491-install-');
    mirror = p.join(temp.path, 'mirror');
    root = p.join(temp.path, 'machine');
    db = p.join(root, 'books', 'seforim.db');
    final modelFiles = {
      'model.json': fixtureBytes('model.json'),
      // Installation checks and copies the query graph, but does not run it.
      'query.int8.onnx': utf8.encode('query graph fixture'),
      'LICENSE': utf8.encode('license fixture'),
    };
    spec = SemanticModelSpec(
      generation: generation,
      folder: production.folder,
      baseUrl: production.baseUrl,
      familyId: production.familyId,
      tokenizerChecksum: production.tokenizerChecksum,
      files: [
        for (final file in modelFiles.entries) asset(file.key, file.value),
      ],
      windowsIdentityJson: production.windowsIdentityJson,
    );
    for (final file in modelFiles.entries) {
      final destination = File(p.join(mirror, tag, spec.folder, file.key));
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(file.value);
    }
    final segment = fixtureBytes('segment.oxv');
    final segmentAsset = asset('segment.oxv', segment);
    final release =
        jsonDecode(utf8.decode(fixtureBytes('release.json')))
            as Map<String, dynamic>;
    release['files'] = [
      {
        'file': segmentAsset.name,
        'compression': 'none',
        'sha256': segmentAsset.sha256,
        'size': segmentAsset.size,
        'uncompressedSha256': segmentAsset.sha256,
        'uncompressedSize': segmentAsset.size,
      },
    ];
    final manifest = utf8.encode(jsonEncode(release));
    final vectors = await Directory(
      p.join(mirror, tag, 'vectors'),
    ).create(recursive: true);
    await File(p.join(vectors.path, manifestName)).writeAsBytes(manifest);
    await File(p.join(vectors.path, segmentAsset.name)).writeAsBytes(segment);
    await File(
      p.join(mirror, SemanticSearchAssets.manifestFileName),
    ).writeAsString(
      jsonEncode({
        'libraryTag': tag,
        'libraryVersion': 36,
        'plans': [
          {
            'generation': generation.id,
            'family': 'legacy',
            'libraryTag': tag,
            'libraryVersion': 36,
            'manifestName': manifestName,
            'manifestSize': manifest.length,
            'manifestSha256': Sha256Stream.ofBytes(manifest),
          },
        ],
      }),
    );
  });

  tearDown(() async {
    if (skip != null) return;
    await temp.delete(recursive: true);
  });

  test('QA491 installs, reopens and verifies with its exact published '
      'identity', () async {
    final before = await assess();
    expect(before.state, SmartSearchState.readyOnDrive);
    expect(
      before.missing,
      containsAll([SmartSearchPart.model, SmartSearchPart.vectors]),
    );
    await install();

    var verified = false;
    final after = await assess(verified: () => verified = true);
    expect(after.state, SmartSearchState.installedVerified);
    expect(after.installedGeneration, generation);
    expect(after.missing, isEmpty);
    expect(verified, isTrue);
    final sets = await SemanticSearchAssets.readInstalledSets(
      p.join(root, 'vectors'),
    );
    expect(
      sets.first.identityDigest,
      '0e87cbd9570c35cdf4c9163310b08cd1508bc22dbd8f7baf8cb9aff2920043f3',
    );
    expect(sets.first.markerConsistent, isTrue);
    expect(sets.first.windows, isFalse);
    final installedModel = File(
      p.join(p.dirname(db), spec.folder, 'model.json'),
    );
    final model = jsonDecode(await installedModel.readAsString()) as Map;
    expect(model['family_id'], production.familyId);
    expect(model['query_max_tokens'], 128);
    expect(
      File(p.join(p.dirname(db), spec.folder, 'query.int8.onnx')).existsSync(),
      isTrue,
    );
  }, skip: skip);

  test('QA491 recovery refuses a corrupted segment even when its pointer '
      'and length still match', () async {
    await install();
    final vectors = p.join(root, 'vectors');
    final segment =
        (await Directory(p.join(vectors, 'segments')).list().toList())
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.oxv')
            .single;
    final bytes = await segment.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await segment.writeAsBytes(bytes, flush: true);
    var verified = false;
    final after = await assess(verified: () => verified = true);
    expect(after.state, SmartSearchState.readyOnDrive);
    expect(after.missing, contains(SmartSearchPart.vectors));
    expect(verified, isFalse);
  }, skip: skip);
}
