import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show Sha256Stream;
import 'package:test/test.dart';

import 'support/native_engine.dart';
import 'support/semantic_fixtures.dart' show identityB;

/// The real binary installs the real set; `pending()` then reads what the
/// binary wrote. Only the model family is the test model's (a test-only seam).
void main() {
  final skip = nativeSkipReason(needsVectorSet: true);
  const tag = 'v1-20261001000000';
  const manifestName = 'otzaria-vectors-testmock-v1-base.manifest.json';
  late Directory temp;
  late String mirror;
  late String db;
  late String root;
  late Map<String, dynamic> release;
  late List<SemanticAsset> models;

  List<int> fixtureBytes(String name) =>
      File(p.join(nativeVectorSetDir, name)).readAsBytesSync();

  SemanticAsset asset(String name, List<int> bytes) =>
      (name: name, size: bytes.length, sha256: Sha256Stream.ofBytes(bytes));

  Future<void> publish(Map<String, dynamic> manifest) async {
    final bytes = utf8.encode(jsonEncode(manifest));
    final vectors = p.join(mirror, tag, 'vectors');
    await Directory(vectors).create(recursive: true);
    await File(p.join(vectors, manifestName)).writeAsBytes(bytes);
    await File(
      p.join(vectors, 'segment.oxv'),
    ).writeAsBytes(fixtureBytes('segment.oxv'));
    await File(
      p.join(mirror, SemanticSearchAssets.manifestFileName),
    ).writeAsString(
      jsonEncode({
        'libraryTag': tag,
        'libraryVersion': 1,
        'manifestName': manifestName,
        'manifestSize': bytes.length,
        'manifestSha256': Sha256Stream.ofBytes(bytes),
      }),
    );
  }

  SemanticSearchAssets assets() => SemanticSearchAssets(
    models: models,
    nativeLibrary: ExternalLibrary.open(hookEngineLibrary()!),
    modelFamily: (
      familyId: 'test-mock@0000000',
      tokenizerChecksum:
          ((release['identity'] as Map)['model'] as Map)['tokenizer_checksum']
              as String,
    ),
  );

  Future<bool> pending() async {
    final subject = assets();
    addTearDown(subject.dispose);
    return subject.pending(
      mirrorDir: mirror,
      dbPath: db,
      libraryVersion: 1,
      vectorsRootPath: root,
    );
  }

  setUp(() async {
    if (skip != null) return;
    temp = await Directory.systemTemp.createTemp('native-pending-');
    mirror = p.join(temp.path, 'mirror');
    db = p.join(temp.path, 'machine', 'library', 'seforim.db');
    root = p.join(temp.path, 'machine');
    models = [
      asset('model.json', fixtureBytes('model.json')),
      asset('LICENSE', utf8.encode('license')),
    ];
    release =
        jsonDecode(utf8.decode(fixtureBytes('release.json')))
            as Map<String, dynamic>;
    release['files'] = [asset('segment.oxv', fixtureBytes('segment.oxv'))]
        .map(
          (f) => {
            'file': f.name,
            'compression': 'none',
            'uncompressedSha256': f.sha256,
            'uncompressedSize': f.size,
            'size': f.size,
            'sha256': f.sha256,
          },
        )
        .toList();
    for (final model in models) {
      final file = File(
        p.join(mirror, tag, SemanticSearchAssets.modelFolder, model.name),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        model.name == 'model.json'
            ? fixtureBytes('model.json')
            : utf8.encode('license'),
      );
    }
    await publish(release);
  });

  tearDown(() async {
    if (skip != null) return;
    await temp.delete(recursive: true);
  });

  Future<void> install() async {
    final subject = assets();
    addTearDown(subject.dispose);
    expect(
      await subject.install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 1,
        vectorsRootPath: root,
      ),
      isTrue,
    );
  }

  test('offers the set until the binary installs it, then stops', () async {
    expect(await pending(), isTrue);
    await install();
    expect(await pending(), isFalse);
  }, skip: skip);

  test(
    'the same tag republished under another identity is offered again',
    () async {
      await install();
      release['identityDigest'] = identityB;
      await publish(release);
      expect(await pending(), isTrue);
    },
    skip: skip,
  );

  /// A sound set (pointer, `set.json`, one segment) that does not touch the
  /// real installed one: its own generation and segment name.
  Future<String> parkedSet({
    required int generation,
    required int libraryVersion,
    required String identity,
  }) async {
    final vectors = p.join(root, 'vectors');
    final segment = 'segments/${'${generation}0' * 16}'.substring(0, 41);
    final segmentFile = File(p.join(vectors, '$segment.oxv'));
    expect(segmentFile.existsSync(), isFalse);
    await segmentFile.parent.create(recursive: true);
    await segmentFile.writeAsBytes([1, 2, 3]);
    final set = utf8.encode(
      jsonEncode({
        'format': 'otzaria-vector-set',
        'format_version': 1,
        'generation': generation,
        'identity_digest': identity,
        'library_version': libraryVersion,
        'library_release_tag': tag,
        'segments': [
          {'file': '$segment.oxv', 'size': 3},
        ],
      }),
    );
    final setPath = 'gen-${generation.toString().padLeft(6, '0')}/set.json';
    final setFile = File(p.join(vectors, setPath));
    expect(setFile.existsSync(), isFalse);
    await setFile.create(recursive: true);
    await setFile.writeAsBytes(set);
    return jsonEncode({
      'generation': generation,
      'set': setPath,
      'set_sha256': Sha256Stream.ofBytes(set),
    });
  }

  Future<List<SemanticInstalledSet>> installedSets() =>
      SemanticSearchAssets.readInstalledSets(p.join(root, 'vectors'));

  test(
    'a matching live set is enough, an old previous one is not offered',
    () async {
      await install();
      final vectors = p.join(root, 'vectors');
      final live = (await installedSets()).single;
      final previous = await parkedSet(
        generation: 90,
        libraryVersion: 1,
        identity: identityB,
      );
      await File(p.join(vectors, 'PREVIOUS')).writeAsString(previous);
      // both sets are sound, so the verdict is about which one pending reads
      final sets = await installedSets();
      expect(sets, hasLength(2));
      expect(sets.first.identityDigest, live.identityDigest);
      expect(sets.last.identityDigest, identityB);
      expect(await pending(), isFalse);
    },
    skip: skip,
  );

  test(
    'an old live set is offered even when the previous one matches',
    () async {
      await install();
      final vectors = p.join(root, 'vectors');
      final matching = (await installedSets()).single;
      await File(
        p.join(vectors, 'CURRENT'),
      ).rename(p.join(vectors, 'PREVIOUS'));
      final old = await parkedSet(
        generation: 91,
        libraryVersion: 1,
        identity: identityB,
      );
      await File(p.join(vectors, 'CURRENT')).writeAsString(old);
      final sets = await installedSets();
      expect(sets, hasLength(2));
      expect(sets.first.identityDigest, identityB);
      expect(sets.last.identityDigest, matching.identityDigest);
      expect(await pending(), isTrue);
    },
    skip: skip,
  );
}
