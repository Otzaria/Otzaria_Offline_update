import 'dart:convert';
import 'dart:io';

import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart' show LibraryManager;
import 'package:library_manager/src/services/library_state_store.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticError, SemanticErrorKind;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

void main() {
  late Directory temp;
  late String mirror;
  late String db;
  late String vectors;
  late FakeVectorsGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-delta-test-');
    mirror = p.join(temp.path, 'mirror');
    db = p.join(temp.path, 'machine', 'library', 'seforim.db');
    vectors = p.join(temp.path, 'machine', 'vectors');
    github = FakeVectorsGithub();
  });

  tearDown(() async {
    github.client.close();
    await temp.delete(recursive: true);
  });

  SemanticMachineState windowsAt(
    int version, {
    String identity = identityA,
    bool needsBase = false,
  }) => SemanticMachineState(
    supportsWindows: true,
    family: SemanticVectorsFamily.windows,
    libraryVersion: version,
    identityDigest: identity,
    needsBase: needsBase,
  );

  Future<void> sync(SemanticFleet fleet, {int target = 30}) async {
    final assets = SemanticSearchAssets(
      httpClient: github.client,
      models: fakeModels,
    );
    try {
      await assets.sync(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(target),
        fleet: fleet,
        libraryTagFor: libraryTagOf,
      );
    } finally {
      assets.dispose();
    }
  }

  Future<Map<String, dynamic>> metadata() async =>
      jsonDecode(
            await File(
              p.join(mirror, SemanticSearchAssets.manifestFileName),
            ).readAsString(),
          )
          as Map<String, dynamic>;

  Future<Set<String>> mirroredVectors({int target = 30}) async => {
    for (final entry in Directory(
      p.join(mirror, libraryTagOf(target), 'vectors'),
    ).listSync())
      if (!entry.path.endsWith('.lock') && !entry.path.endsWith('.resume'))
        p.basename(entry.path),
  };

  group('the window model identity', () {
    test('is byte-identical to Otzaria\'s model.json', () {
      final bytes = utf8.encode(kWindowsModelIdentityJson);
      expect(bytes, hasLength(655));
      expect(
        Sha256Stream.ofBytes(bytes),
        '2b8726e48e9379aa5682f9110b0d71c358c0f1aebf5681f870fed2783f248157',
      );
      final json = jsonDecode(kWindowsModelIdentityJson) as Map;
      expect(json['chunking_identity'], kWindowsChunkingIdentity);
    });
  });

  group('family from the recorded machines', () {
    test('no record downloads the legacy family', () {
      expect(const SemanticFleet().family, SemanticVectorsFamily.legacy);
    });

    test('one machine without windows support keeps the legacy family', () {
      expect(
        SemanticFleet([
          windowsAt(30),
          const SemanticMachineState(
            supportsWindows: false,
            family: SemanticVectorsFamily.legacy,
            libraryVersion: 30,
          ),
        ]).family,
        SemanticVectorsFamily.legacy,
      );
    });

    test('every machine supporting windows selects the windows family', () {
      final fleet = SemanticFleet([
        windowsAt(29),
        const SemanticMachineState(supportsWindows: true, family: null),
      ]);
      expect(fleet.family, SemanticVectorsFamily.windows);
      expect(fleet.chainStartFor(identityA), isNull);
      expect(
        SemanticFleet([windowsAt(29), windowsAt(27)]).chainStartFor(identityA),
        27,
      );
      expect(
        SemanticFleet([windowsAt(29), windowsAt(27)]).chainStartFor(identityB),
        isNull,
      );
      expect(
        SemanticFleet([
          windowsAt(29, needsBase: true),
        ]).chainStartFor(identityA),
        isNull,
      );
    });

    test('the state store keeps one record per machine', () async {
      final store = LibraryStateStore(p.join(temp.path, 'library_state.json'));
      expect(await store.liveSemanticStates(), isEmpty);
      await store.recordOwnSemanticState(windowsAt(29, needsBase: true));
      await store.recordOwnSemanticState(windowsAt(30));
      final states = await store.liveSemanticStates();
      expect(states, hasLength(1));
      expect(states.single.libraryVersion, 30);
      expect(states.single.needsBase, isFalse);
      expect(states.single.family, SemanticVectorsFamily.windows);
      expect((await store.loadOwnSemanticState())?.identityDigest, identityA);
      await store.recordOwnSemanticState(null);
      expect(await store.liveSemanticStates(), isEmpty);
    });
  });

  group('online plan', () {
    test(
      'a mixed fleet mirrors a legacy base and a windows chain independently',
      () async {
        github
          ..legacyBase(30)
          ..windowsBase(30)
          ..delta(29, 30);
        final fleet = SemanticFleet([
          windowsAt(29),
          const SemanticMachineState(
            supportsWindows: false,
            family: SemanticVectorsFamily.legacy,
            libraryVersion: 20,
          ),
        ]);
        await sync(fleet);
        final meta = await metadata();
        expect(meta['manifestName'], legacyManifestName(30));
        expect(meta['windows']['kind'], 'chain');
        expect(meta['windows']['steps'], hasLength(1));
        expect(await mirroredVectors(), {
          legacyManifestName(30),
          'legacy-v30.oxv.zst',
          deltaManifestName(29, 30),
          deltaSegmentName(29, 30),
        });
        final assets = SemanticSearchAssets(
          httpClient: github.client,
          models: fakeModels,
        );
        addTearDown(assets.dispose);
        Future<bool> peek() => assets.peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
          fleet: fleet,
        );
        expect(await peek(), isFalse);
        await File(
          p.join(mirror, libraryTagOf(30), 'vectors', deltaSegmentName(29, 30)),
        ).delete();
        expect(await peek(), isTrue);
        await sync(fleet);
        expect(await peek(), isFalse);
        await File(
          p.join(mirror, libraryTagOf(30), 'vectors', 'legacy-v30.oxv.zst'),
        ).delete();
        expect(await peek(), isTrue);
      },
    );

    test(
      'a mixed mirror prunes only the family that leaves the fleet',
      () async {
        github
          ..legacyBase(30)
          ..windowsBase(30)
          ..delta(29, 30);
        final fleet = SemanticFleet([
          windowsAt(29),
          const SemanticMachineState(supportsWindows: false, family: null),
        ]);
        await sync(fleet);
        await sync(SemanticFleet([windowsAt(29)]));
        expect((await metadata())['family'], 'windows');
        expect(await mirroredVectors(), {
          deltaManifestName(29, 30),
          deltaSegmentName(29, 30),
        });
        await sync(fleet);
        await sync(const SemanticFleet());
        expect((await metadata()).containsKey('windows'), isFalse);
        expect(await mirroredVectors(), {
          legacyManifestName(30),
          'legacy-v30.oxv.zst',
        });
      },
    );

    test('a found chain puts only the deltas in the mirror', () async {
      github
        ..windowsBase(30)
        ..delta(28, 29)
        ..delta(29, 30);
      await sync(SemanticFleet([windowsAt(28), windowsAt(29)]));

      final meta = await metadata();
      expect(meta['family'], 'windows');
      expect(meta['kind'], 'chain');
      expect(meta.containsKey('manifestName'), isFalse);
      expect(
        [for (final step in meta['steps'] as List) (step['from'], step['to'])],
        [(28, 29), (29, 30)],
      );
      expect(await mirroredVectors(), {
        deltaManifestName(28, 29),
        deltaSegmentName(28, 29),
        deltaManifestName(29, 30),
        deltaSegmentName(29, 30),
      });
      expect(github.downloads, isNot(contains(baseSegmentName(30))));
      expect(github.apiTags, [
        'vectors-windows-${libraryTagOf(30)}',
        'vectors-windows-delta-${libraryTagOf(30)}',
        'vectors-windows-delta-${libraryTagOf(29)}',
      ]);
    });

    test('machines already at the target need no vectors at all', () async {
      github.windowsBase(30);
      await sync(SemanticFleet([windowsAt(30)]));
      expect((await metadata())['kind'], 'chain');
      expect((await metadata())['steps'], isEmpty);
      expect(await mirroredVectors(), isEmpty);
    });

    Future<void> expectBase(SemanticFleet fleet) async {
      await sync(fleet);
      final meta = await metadata();
      expect(meta['family'], 'windows');
      expect(meta['kind'], 'base');
      expect(await mirroredVectors(), {
        baseManifestName(30),
        baseSegmentName(30),
      });
    }

    test('a chain longer than the limit falls back to the base', () async {
      github.windowsBase(30, segmentSize: 100000);
      for (var v = 20; v < 30; v++) {
        github.delta(v, v + 1);
      }
      await expectBase(SemanticFleet([windowsAt(20)]));
      expect(
        github.apiTags.where((t) => t.startsWith('vectors-windows-delta-')),
        hasLength(kSemanticDeltaChainLimits.maxSteps),
      );
    });

    test('a chain larger than half the base falls back to it', () async {
      github
        ..windowsBase(30, segmentSize: 100)
        ..delta(28, 29, segmentSize: 30)
        ..delta(29, 30, segmentSize: 30);
      await expectBase(SemanticFleet([windowsAt(28)]));
    });

    test('a missing step falls back to the base', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30);
      await expectBase(SemanticFleet([windowsAt(28)]));
    });

    test('a delta of another identity falls back to the base', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30, identity: identityB);
      await expectBase(SemanticFleet([windowsAt(29)]));
    });

    test('a machine on another identity falls back to the base', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30);
      await expectBase(
        SemanticFleet([windowsAt(29), windowsAt(29, identity: identityB)]),
      );
    });

    test('a delta whose name disagrees with its manifest falls back to the '
        'base', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30, manifestFrom: 28);
      await expectBase(SemanticFleet([windowsAt(29)]));
    });

    test('a machine between two steps falls back to the base', () async {
      github
        ..windowsBase(30)
        ..delta(28, 30);
      await expectBase(SemanticFleet([windowsAt(28), windowsAt(29)]));
    });

    test('a machine that needs a base gets one', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30);
      await expectBase(SemanticFleet([windowsAt(29, needsBase: true)]));
      expect(
        github.apiTags.where((t) => t.startsWith('vectors-windows-delta-')),
        isEmpty,
      );
    });

    test(
      'a network failure in the chain is not taken as "use the base"',
      () async {
        github
          ..windowsBase(30)
          ..delta(29, 30)
          ..failingTags.add('vectors-windows-delta-${libraryTagOf(30)}');
        await expectLater(
          sync(SemanticFleet([windowsAt(29)])),
          throwsA(isA<FormatException>()),
        );
        expect(
          File(
            p.join(mirror, SemanticSearchAssets.manifestFileName),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('a truncated delta manifest fails the download instead of taking the '
        'base', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30)
        ..truncated.add(deltaManifestName(29, 30));
      await expectLater(
        sync(SemanticFleet([windowsAt(29)])),
        throwsA(isA<FormatException>()),
      );
      expect(github.downloads, isNot(contains(baseSegmentName(30))));
      expect(
        File(
          p.join(mirror, SemanticSearchAssets.manifestFileName),
        ).existsSync(),
        isFalse,
      );
    });

    test('needsBase is set by a failed chain and cleared by a base', () {
      bool next(SemanticMachineState? previous, {bool base = false}) =>
          LibraryManager.nextNeedsBase(
            previous: previous,
            libraryVersion: 29,
            identityDigest: identityA,
            baseInstalled: base,
          );
      expect(
        LibraryManager.nextNeedsBase(
          previous: null,
          libraryVersion: 29,
          identityDigest: identityA,
          chainFailed: true,
        ),
        isTrue,
      );
      expect(next(windowsAt(29, needsBase: true)), isTrue);
      expect(next(windowsAt(29, needsBase: true), base: true), isFalse);
      expect(next(windowsAt(28, needsBase: true)), isFalse);
      expect(next(windowsAt(29)), isFalse);
    });

    test('without a windows release the legacy one is mirrored', () async {
      github.legacyBase(30);
      await sync(SemanticFleet([windowsAt(29)]));
      final meta = await metadata();
      expect(meta['family'], 'legacy');
      expect(meta['manifestName'], legacyManifestName(30));
      expect(github.apiTags, [
        'vectors-windows-${libraryTagOf(30)}',
        'vectors-${libraryTagOf(30)}',
      ]);
    });

    test('an unusable windows release falls back to the legacy one, and the '
        'light check remembers it', () async {
      github
        ..windowsBase(30, chunking: 1)
        ..legacyBase(30);
      final fleet = SemanticFleet([windowsAt(29)]);
      await sync(fleet);
      final meta = await metadata();
      expect(meta['family'], 'legacy');
      expect(meta['rejectedWindowsManifest'], isA<String>());

      final assets = SemanticSearchAssets(
        httpClient: github.client,
        models: fakeModels,
      );
      addTearDown(assets.dispose);
      expect(
        await assets.peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
          fleet: fleet,
        ),
        isFalse,
      );

      github.addAsset('vectors-windows-${libraryTagOf(30)}', 'late.bin');
      expect(
        await assets.peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
          fleet: fleet,
        ),
        isTrue,
      );
    });

    test('an unusable windows release with no legacy one names the real '
        'fault', () async {
      github.windowsBase(30, chunking: 1);
      await expectLater(
        sync(SemanticFleet([windowsAt(29)])),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.companionAssetMissingInRelease(
              AppL10n.strings.libraryDomain.companionSemanticName,
            ),
          ),
        ),
      );
    });

    test('a windows release for another line-text version falls back to '
        'the legacy one', () async {
      github
        ..windowsBase(30, lineText: kSemanticLineTextVersion - 1)
        ..legacyBase(30);
      await sync(SemanticFleet([windowsAt(29)]));
      final meta = await metadata();
      expect(meta['family'], 'legacy');
      expect(github.downloads, isNot(contains(endsWith(baseSegmentName(30)))));
    });

    test('a release for another line-text version fails before its segment '
        'is downloaded', () async {
      github.legacyBase(30, lineText: kSemanticLineTextVersion - 1);
      await expectLater(
        sync(const SemanticFleet()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.semanticBuiltForOlderOtzaria,
          ),
        ),
      );
      expect(github.downloads, isNot(contains(endsWith('legacy-v30.oxv.zst'))));
    });

    test('a release for a newer line-text version asks for a newer '
        'launcher', () async {
      github.legacyBase(30, lineText: kSemanticLineTextVersion + 1);
      await expectLater(
        sync(const SemanticFleet()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.semanticNeedsNewerLauncher,
          ),
        ),
      );
    });

    test('the light check does not offer a release for another line-text '
        'version', () async {
      github.legacyBase(30, lineText: kSemanticLineTextVersion - 1);
      final assets = SemanticSearchAssets(
        httpClient: github.client,
        models: fakeModels,
      );
      addTearDown(assets.dispose);
      for (var check = 0; check < 2; check++) {
        expect(
          await assets.peekPending(
            mirrorDir: mirror,
            libraryTag: libraryTagOf(30),
          ),
          isFalse,
        );
      }
      expect(assets.peekedPendingBytes, 0);
      expect(github.downloads, [
        legacyManifestName(30),
        legacyManifestName(30),
      ]);
    });

    test('the light check still offers a usable legacy release', () async {
      github.legacyBase(30);
      final assets = SemanticSearchAssets(
        httpClient: github.client,
        models: fakeModels,
      );
      addTearDown(assets.dispose);
      expect(
        await assets.peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
        ),
        isTrue,
      );
      expect(assets.peekedPendingBytes, greaterThan(0));
    });

    test(
      'a cut-off API reply fails the download instead of falling back',
      () async {
        github
          ..windowsBase(30)
          ..legacyBase(30)
          ..garbledTags.add('vectors-windows-${libraryTagOf(30)}');
        await expectLater(
          sync(SemanticFleet([windowsAt(29)])),
          throwsA(isA<FormatException>()),
        );
        expect(
          File(
            p.join(mirror, SemanticSearchAssets.manifestFileName),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('a switch from base to chain prunes the base files', () async {
      github
        ..windowsBase(30)
        ..delta(29, 30);
      await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
      final lock = File(
        p.join(mirror, libraryTagOf(30), 'vectors', 'segment.lock'),
      );
      await lock.writeAsString('lock');
      await sync(SemanticFleet([windowsAt(29)]));
      expect(await mirroredVectors(), {
        deltaManifestName(29, 30),
        deltaSegmentName(29, 30),
      });
      expect(await lock.readAsString(), 'lock');
      final vectorsDir = p.join(mirror, libraryTagOf(30), 'vectors');
      expect(
        File(p.join(vectorsDir, '${baseSegmentName(30)}.resume')).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(vectorsDir, '${deltaSegmentName(29, 30)}.resume'),
        ).existsSync(),
        isTrue,
      );
    });

    Future<bool> peek(SemanticFleet fleet) async {
      final assets = SemanticSearchAssets(
        httpClient: github.client,
        models: fakeModels,
      );
      try {
        return await assets.peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
          fleet: fleet,
        );
      } finally {
        assets.dispose();
      }
    }

    test('the light check accepts a chain only while every machine can use '
        'it', () async {
      github
        ..windowsBase(30)
        ..delta(28, 29)
        ..delta(29, 30);
      await sync(SemanticFleet([windowsAt(28)]));
      github.apiTags.clear();

      expect(await peek(SemanticFleet([windowsAt(28)])), isFalse);
      expect(
        await peek(SemanticFleet([windowsAt(29), windowsAt(30)])),
        isFalse,
      );
      expect(await peek(SemanticFleet([windowsAt(27)])), isTrue);
      expect(
        await peek(SemanticFleet([windowsAt(28, needsBase: true)])),
        isTrue,
      );
      expect(
        github.apiTags,
        everyElement('vectors-windows-${libraryTagOf(30)}'),
      );
    });

    test('the light check accepts a windows base for any machine', () async {
      github
        ..windowsBase(30)
        ..legacyBase(30);
      await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
      expect(await peek(SemanticFleet([windowsAt(29)])), isFalse);
      expect(await peek(const SemanticFleet()), isTrue);
    });
  });

  group('offline install', () {
    late FakeVectorsEngine engine;

    SemanticSearchAssets offline() => SemanticSearchAssets(
      httpClient: MockClient((request) async {
        fail('offline method sent a request to ${request.url}');
      }),
      models: fakeModels,
      engineFactory: (_) async => engine,
    );

    Future<void> install({bool supportsWindows = true}) async {
      final assets = offline();
      try {
        await assets.install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          supportsWindows: supportsWindows,
        );
      } finally {
        assets.dispose();
      }
    }

    Future<bool> pending({bool supportsWindows = true}) async {
      final assets = offline();
      try {
        return await assets.pending(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          supportsWindows: supportsWindows,
        );
      } finally {
        assets.dispose();
      }
    }

    Future<void> chainMirror() async {
      github
        ..windowsBase(30)
        ..delta(27, 28)
        ..delta(28, 29)
        ..delta(29, 30);
      await sync(SemanticFleet([windowsAt(27)]));
    }

    List<(int, int)> applied() => [
      for (final input in engine.installs)
        (
          (jsonDecode(input.manifestJson) as Map)['fromLibraryVersion'] as int,
          (jsonDecode(input.manifestJson) as Map)['toLibraryVersion'] as int,
        ),
    ];

    test(
      'cancellation before compaction leaves the applied steps and stops',
      () async {
        await chainMirror();
        await writeInstalledSet(vectors, version: 29);
        engine = FakeVectorsEngine(version: 29);
        final assets = offline();
        addTearDown(assets.dispose);
        var cancelled = false;
        await expectLater(
          assets.install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            supportsWindows: true,
            beforeActivate: () async {
              if (engine.installs.isNotEmpty) cancelled = true;
            },
            isCancelled: () => cancelled,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        expect(engine.version, 30);
        expect(engine.compactions, isEmpty);
        expect(engine.disposed, isTrue);
      },
    );

    test('a chain compacts once after its last step', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 27);
      engine = FakeVectorsEngine(version: 27);
      await install();
      expect(engine.compactions, [vectors]);
      expect(engine.compactedVersion, 30);
      expect(engine.disposed, isTrue);
    });

    test('a retried chain also compacts an already updated set', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 30);
      engine = FakeVectorsEngine(version: 30);
      await install();
      expect(engine.installs, isEmpty);
      expect(engine.compactions, [vectors]);
    });

    test('a compaction failure is reported and disposes the engine', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 29);
      const error = SemanticError(
        kind: SemanticErrorKind.insufficientDiskSpace,
        message: 'compaction needs space',
      );
      engine = FakeVectorsEngine(version: 29)..compactionError = error;
      await expectLater(install(), throwsA(same(error)));
      expect(engine.version, 30);
      expect(engine.disposed, isTrue);
    });

    for (final (installed, expected) in [
      (27, [(27, 28), (28, 29), (29, 30)]),
      (28, [(28, 29), (29, 30)]),
      (29, [(29, 30)]),
      (30, <(int, int)>[]),
    ]) {
      test('a chain applies from v$installed only the missing steps', () async {
        await chainMirror();
        await writeInstalledSet(vectors, version: installed);
        engine = FakeVectorsEngine(version: installed);
        await install();
        expect(applied(), expected);
        for (final input in engine.installs) {
          expect(input.modelIdentityJson, kWindowsModelIdentityJson);
          expect(input.vectorsDir, vectors);
        }
        expect(engine.disposed, isTrue);
      });
    }

    for (final (name, version, marker) in [
      ('below the chain', 26, true),
      ('of the legacy family', 28, false),
    ]) {
      test('an installed set $name is not touched', () async {
        await chainMirror();
        await writeInstalledSet(vectors, version: version, windows: marker);
        engine = FakeVectorsEngine(version: version);
        await expectLater(
          install(),
          throwsA(isA<SemanticChainNotApplicableException>()),
        );
        expect(engine.installs, isEmpty);
        expect(
          Directory(
            p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
          ).existsSync(),
          isFalse,
        );
      });
    }

    test('an installed set of another identity is not touched', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 28, identity: identityB);
      engine = FakeVectorsEngine(version: 28, identity: identityB);
      await expectLater(
        install(),
        throwsA(isA<SemanticChainNotApplicableException>()),
      );
      expect(engine.installs, isEmpty);
    });

    test('a delta the engine refuses ends as "full download needed"', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 28);
      engine = FakeVectorsEngine(version: 28, refuse: true);
      await expectLater(
        install(),
        throwsA(
          isA<SemanticChainNotApplicableException>().having(
            (e) => '$e',
            'message',
            AppL10n.strings.libraryDomain.semanticFullDownloadNeeded,
          ),
        ),
      );
    });

    for (final kind in [
      SemanticErrorKind.artifactCorrupt,
      SemanticErrorKind.artifactMissing,
    ]) {
      test('a delta failing on a ${kind.name} set ends as "full download '
          'needed"', () async {
        await chainMirror();
        await writeInstalledSet(vectors, version: 28);
        engine = FakeVectorsEngine(
          version: 28,
          error: SemanticError(kind: kind, message: 'set'),
        );
        await expectLater(
          install(),
          throwsA(isA<SemanticChainNotApplicableException>()),
        );
      });
    }

    test(
      'a set the engine cannot read ends as "full download needed"',
      () async {
        await chainMirror();
        await writeInstalledSet(vectors, version: 28);
        engine = FakeVectorsEngine(
          version: 28,
          infoError: const SemanticError(
            kind: SemanticErrorKind.artifactCorrupt,
            message: 'unreadable',
          ),
        );
        await expectLater(
          install(),
          throwsA(isA<SemanticChainNotApplicableException>()),
        );
      },
    );

    test('a machine needing a base is offered the base it already holds, and '
        'installing it reports a base', () async {
      github.windowsBase(30);
      await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      await writeInstalledSet(vectors, version: 30);
      expect(await pending(), isFalse);
      final assets = offline();
      try {
        expect(
          await assets.pending(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            vectorsRootPath: p.dirname(vectors),
            supportsWindows: true,
            needsBase: true,
          ),
          isTrue,
        );
        engine = FakeVectorsEngine(version: 30);
        expect(
          await assets.install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            vectorsRootPath: p.dirname(vectors),
            supportsWindows: true,
          ),
          isTrue,
        );
      } finally {
        assets.dispose();
      }
    });

    test('a chain install does not report a base', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 29);
      engine = FakeVectorsEngine(version: 29);
      final assets = offline();
      addTearDown(assets.dispose);
      expect(
        await assets.install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          supportsWindows: true,
        ),
        isFalse,
      );
    });

    test('a legacy mirror leaves a windows set alone on a windows-capable '
        'machine', () async {
      github.legacyBase(30);
      await sync(const SemanticFleet());
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      await writeInstalledSet(vectors, version: 29);
      engine = FakeVectorsEngine(version: 29);
      expect(await pending(), isFalse);
      final assets = offline();
      addTearDown(assets.dispose);
      expect(
        await assets.install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          supportsWindows: true,
        ),
        isFalse,
      );
      expect(engine.installs, isEmpty);
      expect(await pending(supportsWindows: false), isTrue);
    });

    for (final previous in [identityB, null]) {
      test('a refused windows base restores the previous marker '
          '(${previous == null ? 'none' : 'another set'})', () async {
        github.windowsBase(30);
        await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
        final marker = File(
          p.join(vectors, SemanticSearchAssets.windowsIdentityFileName),
        );
        if (previous == null) {
          await writeInstalledSet(vectors, version: 29, windows: false);
        } else {
          await writeInstalledSet(vectors, version: 29, identity: previous);
        }
        engine = FakeVectorsEngine(
          version: 29,
          error: const SemanticError(
            kind: SemanticErrorKind.insufficientDiskSpace,
            message: 'full',
          ),
          onInstall: (_) => expect(marker.readAsStringSync(), identityA),
        );
        await expectLater(install(), throwsA(isA<SemanticError>()));
        if (previous == null) {
          expect(marker.existsSync(), isFalse);
        } else {
          expect(marker.readAsStringSync(), previous);
        }
      });
    }

    test('a windows base is not offered over a newer windows set', () async {
      github.windowsBase(30);
      await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      await writeInstalledSet(vectors, version: 31);
      expect(await pending(), isFalse);
    });

    test('a windows base writes both markers before the engine runs', () async {
      github.windowsBase(30);
      await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
      engine = FakeVectorsEngine(
        present: false,
        onInstall: (input) {
          final dir = input.vectorsDir;
          expect(File(p.join(dir, '.otzaria-semantic')).existsSync(), isTrue);
          expect(
            File(
              p.join(dir, SemanticSearchAssets.windowsIdentityFileName),
            ).readAsStringSync(),
            identityA,
          );
          expect(input.modelIdentityJson, kWindowsModelIdentityJson);
        },
      );
      await install();
      expect(applied(), [(0, 30)]);
    });

    test('a legacy base keeps the installed model identity', () async {
      github.legacyBase(30);
      await sync(const SemanticFleet());
      engine = FakeVectorsEngine(present: false);
      await install(supportsWindows: false);
      expect(engine.installs.single.modelIdentityJson, fakeModelJson);
      expect(
        File(
          p.join(vectors, SemanticSearchAssets.windowsIdentityFileName),
        ).existsSync(),
        isFalse,
      );
    });

    test('a windows mirror is neither offered nor installed where Otzaria '
        'lacks windows support', () async {
      await chainMirror();
      await writeInstalledSet(vectors, version: 28);
      engine = FakeVectorsEngine(version: 28);
      expect(await pending(supportsWindows: false), isFalse);
      await expectLater(install(supportsWindows: false), throwsFormatException);
      expect(engine.installs, isEmpty);
    });

    test('pending answers for a chain mirror', () async {
      await chainMirror();
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      await writeInstalledSet(vectors, version: 28);
      expect(await pending(), isTrue);
      await writeInstalledSet(vectors, version: 30);
      expect(await pending(), isFalse);
      await writeInstalledSet(vectors, version: 30, identity: identityB);
      expect(await pending(), isTrue);
      await writeInstalledSet(vectors, version: 30, windows: false);
      expect(await pending(), isTrue);
    });

    test(
      'pending of a windows base wants the windows set of its version',
      () async {
        github.windowsBase(30);
        await sync(SemanticFleet([windowsAt(29, needsBase: true)]));
        await installModels(
          p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
        );
        await writeInstalledSet(vectors, version: 30, windows: false);
        expect(await pending(), isTrue);
        await writeInstalledSet(vectors, version: 30);
        expect(await pending(), isFalse);
      },
    );

    test('a mirror written before windows support still loads', () async {
      github.legacyBase(30);
      await sync(const SemanticFleet());
      final file = File(p.join(mirror, SemanticSearchAssets.manifestFileName));
      final meta = jsonDecode(await file.readAsString()) as Map;
      await file.writeAsString(
        jsonEncode(
          Map.of(meta)
            ..remove('family')
            ..remove('kind'),
        ),
      );
      final assets = offline();
      try {
        expect(await assets.mirroredVersion(mirror), 30);
      } finally {
        assets.dispose();
      }
      expect(await pending(supportsWindows: false), isTrue);
      engine = FakeVectorsEngine(present: false);
      await install(supportsWindows: false);
      expect(engine.installs, hasLength(1));
    });
  });

  test('the engine refusing something else is not hidden', () async {
    github
      ..windowsBase(30)
      ..delta(29, 30);
    await sync(SemanticFleet([windowsAt(29)]));
    await writeInstalledSet(vectors, version: 29);
    final engine = FakeVectorsEngine(
      version: 29,
      error: const SemanticError(
        kind: SemanticErrorKind.insufficientDiskSpace,
        message: 'full',
      ),
    );
    final assets = SemanticSearchAssets(
      models: fakeModels,
      engineFactory: (_) async => engine,
    );
    addTearDown(assets.dispose);
    await expectLater(
      assets.install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        vectorsRootPath: p.dirname(vectors),
        supportsWindows: true,
      ),
      throwsA(isA<SemanticError>()),
    );
  });

  test('the installed set reader follows the identity marker', () async {
    expect(await SemanticSearchAssets.readInstalledSets(vectors), isEmpty);
    await writeInstalledSet(vectors, version: 29);
    final set = (await SemanticSearchAssets.readInstalledSets(vectors)).single;
    expect(set.libraryVersion, 29);
    expect(set.identityDigest, identityA);
    expect(set.windows, isTrue);
    await File(
      p.join(vectors, SemanticSearchAssets.windowsIdentityFileName),
    ).writeAsString(identityB);
    expect(
      (await SemanticSearchAssets.readInstalledSets(vectors)).single.windows,
      isFalse,
    );
  });
}
