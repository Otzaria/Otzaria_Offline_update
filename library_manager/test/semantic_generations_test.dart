// Model generations (Round2 / QA491) and vector shapes (anchor / windows) are
// separate axes; every fixture here is synthetic and lives under the system
// temp directory, never the user's drive, mirror or Otzaria data.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticError, SemanticErrorKind;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

const _round2 = SemanticModelGeneration.round2;
const _qa491 = SemanticModelGeneration.qa491;

SemanticAppSupport _app(
  SemanticModelGeneration? generation, {
  bool windows = false,
}) => SemanticAppSupport(
  generation: generation,
  windows: windows,
  basis: generation == null
      ? SemanticSupportBasis.unproven
      : SemanticSupportBasis.declared,
);

SemanticMachineState _machine(
  SemanticModelGeneration? generation, {
  bool windows = false,
  int version = 0,
  String identity = '',
}) => SemanticMachineState(
  supportsWindows: windows,
  family: version == 0
      ? null
      : windows
      ? SemanticVectorsFamily.windows
      : SemanticVectorsFamily.legacy,
  libraryVersion: version,
  identityDigest: identity,
  generation: generation,
);

void main() {
  late Directory temp;
  late String mirror;
  late String db;
  late String vectors;
  late FakeVectorsGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-generations-');
    mirror = p.join(temp.path, 'mirror');
    db = p.join(temp.path, 'machine', 'books', 'seforim.db');
    vectors = p.join(temp.path, 'machine', 'vectors');
    github = FakeVectorsGithub();
  });
  tearDown(() async {
    github.client.close();
    await temp.delete(recursive: true);
  });

  SemanticSearchAssets assets({
    http.Client? client,
    FakeVectorsEngine? engine,
  }) {
    final value = SemanticSearchAssets(
      httpClient: client ?? github.client,
      models: fakeModels,
      specs: fakeSpecs,
      engineFactory: engine == null ? null : (_) async => engine,
    );
    addTearDown(value.dispose);
    return value;
  }

  Future<void> sync(SemanticFleet fleet, {int version = 30}) => assets().sync(
    mirrorDir: mirror,
    libraryTag: libraryTagOf(version),
    fleet: fleet,
    libraryTagFor: libraryTagOf,
  );

  Future<SmartSearchStatus> assess(
    SemanticAppSupport support, {
    SemanticSearchAssets? using,
    int version = 30,
    bool preferencesReady = true,
    bool needsBase = false,
  }) => (using ?? assets()).assess(
    mirrorDir: mirror,
    dbPath: db,
    libraryVersion: version,
    support: support,
    preferencesReady: preferencesReady,
    needsBase: needsBase,
    vectorsRootPath: p.dirname(vectors),
  );

  Future<Map<String, dynamic>> mirrorJson() async =>
      jsonDecode(
            await File(
              p.join(mirror, SemanticSearchAssets.manifestFileName),
            ).readAsString(),
          )
          as Map<String, dynamic>;

  group('the verified application table', () {
    test('QA491 starts at 0.9.98.3, everything older reads Round2', () {
      expect(
        OtzariaCapabilities.semanticGenerationForAppVersion('0.9.98.2'),
        _round2,
      );
      expect(
        OtzariaCapabilities.semanticGenerationForAppVersion('0.9.98.3'),
        _qa491,
      );
      expect(
        OtzariaCapabilities.semanticGenerationForAppVersion('0.9.98.3+809'),
        _qa491,
      );
      expect(
        OtzariaCapabilities.semanticGenerationForAppVersion('0.9.99'),
        isNull,
      );
    });
  });

  group('isolated reproduction of the live report', () {
    test('a QA491 Otzaria with only Round2 on the drive is never up to '
        'date', () async {
      // The drive carries Round2 only; the machine holds a Round2 set made
      // from it (identity b) and the Round2 model.
      github.legacyBase(36, identity: identityB);
      await sync(SemanticFleet([_machine(_round2)]), version: 36);
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      await writeInstalledSet(
        vectors,
        version: 36,
        windows: false,
        identity: identityB,
      );

      // What the old logic answered: judged as a Round2 application.
      expect(
        await assess(_app(_round2), version: 36).then((s) => s.state),
        SmartSearchState.installedVerified,
      );
      // The application reads QA491 (capabilities of 0.9.98.3).
      final status = await assess(_app(_qa491, windows: true), version: 36);
      expect(status.allClear, isFalse);
      expect(status.state, SmartSearchState.driveNotMatching);
      expect(status.reason, SmartSearchReason.driveOtherGeneration);
      expect(status.driveGenerations, {_round2});
      expect(status.installedGeneration, _round2);
      expect(
        await assets().pending(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 36,
          vectorsRootPath: p.dirname(vectors),
          supportsWindows: true,
          generation: _qa491,
        ),
        isFalse,
        reason: 'nothing installable, and not reported as done either',
      );
    });
  });

  group('one generation at a time', () {
    test(
      'QA491 only: drive, models and vectors follow the application',
      () async {
        github.qa491Base(30);
        await sync(SemanticFleet([_machine(_qa491)]));
        final meta = await mirrorJson();
        expect(
          meta.containsKey('manifestName'),
          isFalse,
          reason: 'old launchers must not see a QA491 set as Round2',
        );
        expect((meta['plans'] as List).single['generation'], 'qa491');
        expect(
          Directory(
            p.join(mirror, libraryTagOf(30), SemanticModelSpec.qa491.folder),
          ).existsSync(),
          isTrue,
        );
        expect(
          Directory(
            p.join(mirror, libraryTagOf(30), SemanticSearchAssets.modelFolder),
          ).existsSync(),
          isFalse,
        );
        expect(
          github.apiTags.any((t) => t.startsWith('vectors-qa491-')),
          isTrue,
        );
        expect(
          github.apiTags.where((t) => t.startsWith('vectors-v')),
          isEmpty,
          reason: 'no Round2 request for a fleet that only reads QA491',
        );

        var status = await assess(_app(_qa491));
        expect(status.state, SmartSearchState.readyOnDrive);
        expect(status.missing, {
          SmartSearchPart.model,
          SmartSearchPart.vectors,
        });

        // A Round2 application reading the same drive gets nothing from it.
        status = await assess(_app(_round2));
        expect(status.state, SmartSearchState.driveNotMatching);

        final engine = FakeVectorsEngine();
        final installed = await assets(engine: engine).install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          generation: _qa491,
        );
        expect(installed, isTrue);
        expect(
          engine.installs.single.modelIdentityJson,
          fakeQa491ModelJson,
          reason: 'the anchor identity is the model folder\'s model.json',
        );
        expect(
          File(
            p.join(p.dirname(db), SemanticModelSpec.qa491.folder, 'model.json'),
          ).existsSync(),
          isTrue,
        );
        expect(
          Directory(
            p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
          ).existsSync(),
          isFalse,
        );
        // The engine wrote the set; now the same check says so.
        await writeInstalledSet(
          vectors,
          version: 30,
          windows: false,
          identity: identityD,
          familyId: SemanticModelSpec.qa491.familyId,
        );
        status = await assess(_app(_qa491));
        expect(status.state, SmartSearchState.installedVerified);
        expect(status.installedGeneration, _qa491);
      },
    );

    test('QA491 windows installs with the QA491 windows identity', () async {
      github.qa491Base(30, windows: true);
      await sync(SemanticFleet([_machine(_qa491, windows: true)]));
      final engine = FakeVectorsEngine(identity: identityC);
      await assets(engine: engine).install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        vectorsRootPath: p.dirname(vectors),
        supportsWindows: true,
        generation: _qa491,
      );
      expect(
        engine.installs.single.modelIdentityJson,
        kQa491WindowsModelIdentityJson,
      );
      expect(
        File(
          p.join(vectors, SemanticSearchAssets.windowsIdentityFileName),
        ).readAsStringSync(),
        identityC,
      );
    });

    test('Round2 only keeps working', () async {
      github.legacyBase(30, identity: identityB);
      await sync(SemanticFleet([_machine(_round2)]));
      final meta = await mirrorJson();
      expect(meta['manifestName'], legacyManifestName(30));
      expect(
        (await assess(_app(_round2))).state,
        SmartSearchState.readyOnDrive,
      );
      expect(
        (await assess(_app(_qa491))).reason,
        SmartSearchReason.driveOtherGeneration,
      );
    });

    test('the same library version with another generation is found', () async {
      // Round2 set at version 30 installed; QA491 published for the same 30.
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      await installModels(
        p.join(p.dirname(db), SemanticModelSpec.qa491.folder),
        qa491: true,
      );
      await writeInstalledSet(
        vectors,
        version: 30,
        windows: false,
        identity: identityB,
      );
      final status = await assess(_app(_qa491));
      expect(status.state, SmartSearchState.readyOnDrive);
      expect(status.missing, {SmartSearchPart.vectors});
      expect(status.present, contains(SmartSearchPart.model));
      expect(status.installedGeneration, _round2);
    });
  });

  group('a drive that serves several computers', () {
    test('a mixed Round2 anchor and QA491 windows fleet gets both', () async {
      github
        ..legacyBase(30, identity: identityB)
        ..qa491Base(30, windows: true);
      await sync(
        SemanticFleet([_machine(_round2), _machine(_qa491, windows: true)]),
      );
      final meta = await mirrorJson();
      expect(meta['manifestName'], legacyManifestName(30));
      expect(
        [for (final plan in meta['plans'] as List) plan['generation']],
        ['round2', 'qa491'],
      );
      expect(
        (await assess(_app(_round2))).state,
        SmartSearchState.readyOnDrive,
      );
      expect(
        (await assess(_app(_qa491, windows: true))).state,
        SmartSearchState.readyOnDrive,
      );
      expect(
        (await assess(_app(_qa491, windows: false))).state,
        SmartSearchState.driveNotMatching,
        reason: 'only the windows shape of QA491 is mirrored',
      );
    });

    test('anchor and windows machines of two generations make four '
        'targets, none deleted', () async {
      final fleet = SemanticFleet([
        _machine(_round2),
        _machine(_round2, windows: true),
        _machine(_qa491),
        _machine(_qa491, windows: true),
      ]);
      expect(
        [for (final group in fleet.groups) (group.generation, group.family)],
        [
          (_round2, SemanticVectorsFamily.legacy),
          (_round2, SemanticVectorsFamily.windows),
          (_qa491, SemanticVectorsFamily.legacy),
          (_qa491, SemanticVectorsFamily.windows),
        ],
      );
    });

    test('an empty fleet follows the installer on the drive', () async {
      github.qa491Base(30, windows: false);
      await sync(const SemanticFleet([], [_qa491]));
      expect((await mirrorJson())['plans'], hasLength(1));
      expect(github.apiTags.where((t) => t.startsWith('vectors-v')), isEmpty);
    });

    for (final peek in [true, false]) {
      test('${peek ? 'peek' : 'sync'} without a proven target keeps the '
          'mirror and reports that the application is unproven', () async {
        github.qa491Base(30);
        await sync(SemanticFleet([_machine(_qa491)]));
        final before = await mirrorJson();
        github.apiTags.clear();
        final subject = assets();
        const fleet = SemanticFleet([], []);

        await expectLater(
          peek
              ? subject.peekPending(
                  mirrorDir: mirror,
                  libraryTag: libraryTagOf(30),
                  fleet: fleet,
                )
              : subject.sync(
                  mirrorDir: mirror,
                  libraryTag: libraryTagOf(30),
                  fleet: fleet,
                ),
          throwsA(
            isA<SemanticEngineIncompatibleException>().having(
              (error) => error.reason,
              'reason',
              SemanticIncompatibilityReason.otzariaUnproven,
            ),
          ),
        );
        expect(github.apiTags, isEmpty);
        expect(await mirrorJson(), before);
      });
    }

    test('a record from before generations is unknown, kept, and shapes '
        'nothing', () async {
      final old = SemanticMachineState.fromJson({
        'supportsWindows': false,
        'family': 'legacy',
        'libraryVersion': 29,
        'identityDigest': '',
        'needsBase': false,
      })!;
      expect(old.generation, isNull);
      final fleet = SemanticFleet([old], [_qa491]);
      expect(fleet.unknownGenerationMachines, 1);
      expect(fleet.groups.single.generation, _qa491);
      expect(old.toJson()['generation'], 'unknown');
    });

    test('a future generation recorded by a newer tool stays unknown', () {
      final future = SemanticMachineState.fromJson({
        'supportsWindows': true,
        'family': 'windows',
        'libraryVersion': 29,
        'identityDigest': identityA,
        'generation': 'qa900',
      })!;
      expect(future.generation, isNull);
    });

    test('a delta chain never joins two generations or identities', () {
      final fleet = SemanticFleet([
        _machine(_round2, windows: true, version: 29, identity: identityA),
        _machine(_qa491, windows: true, version: 29, identity: identityA),
      ]);
      expect(fleet.chainStartFor(identityA), isNull);
      final qa = SemanticFleet([
        _machine(_qa491, windows: true, version: 28, identity: identityC),
        _machine(_qa491, windows: true, version: 29, identity: identityC),
      ]);
      expect(qa.chainStartFor(identityC), 28);
      expect(qa.chainStartFor(identityA), isNull);
    });

    test('QA491 deltas continue only a QA491 set', () async {
      github
        ..qa491Base(30, windows: true)
        ..qa491Delta(29, 30);
      await sync(
        SemanticFleet([
          _machine(_qa491, windows: true, version: 29, identity: identityC),
        ]),
      );
      final plan = (await mirrorJson())['plans'] as List;
      expect(plan.single['kind'], 'chain');
      expect(
        (plan.single['steps'] as List).single['releaseTag'],
        startsWith('vectors-qa491-windows-delta-'),
      );
    });
  });

  group('what the installed application proves', () {
    test(
      'a family this tool does not know is unsupported, never "done"',
      () async {
        github.qa491Base(30);
        await sync(SemanticFleet([_machine(_qa491)]));
        final support = OtzariaCapabilities.semanticSupport(
          capabilities: const OtzariaCapabilities(
            appVersion: '1.2.0',
            semanticVectorFamilies: ['vectors-qa900-windows', 'vectors-qa491'],
          ),
          installedVersion: '1.2.0',
        );
        expect(support.generation, isNull);
        final status = await assess(support);
        expect(status.state, SmartSearchState.unsupported);
        expect(status.reason, SmartSearchReason.appFamilyUnknown);
        expect(status.allClear, isFalse);
        expect(status.message, isNotNull);
        await expectLater(
          assets().install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            vectorsRootPath: p.dirname(vectors),
            generation: null,
          ),
          throwsA(isA<SemanticEngineIncompatibleException>()),
        );
      },
    );

    test('no proof at all is unverified, not Round2', () async {
      github.legacyBase(30, identity: identityB);
      await sync(SemanticFleet([_machine(_round2)]));
      final status = await assess(OtzariaCapabilities.semanticSupport());
      expect(status.state, SmartSearchState.unverified);
      expect(status.reason, SmartSearchReason.appUnproven);
    });

    test('the cache key changes with the application, the vectors and the '
        'drive', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      final first = (await assess(_app(_qa491))).proofKey;
      expect((await assess(_app(_qa491))).proofKey, first);
      expect(
        (await assess(_app(_qa491, windows: true))).proofKey,
        isNot(first),
      );
      expect((await assess(_app(_round2))).proofKey, isNot(first));
      await writeInstalledSet(
        vectors,
        version: 29,
        windows: false,
        identity: identityD,
      );
      expect((await assess(_app(_qa491))).proofKey, isNot(first));
    });
  });

  group('the drive can be missing, damaged or of another family', () {
    test('no mirror: needs a download when smart search is in use, nothing '
        'when it is not', () async {
      var status = await assess(_app(_qa491));
      expect(status.state, SmartSearchState.needsDriveDownload);
      expect(status.reason, SmartSearchReason.driveEmpty);
      status = await assess(_app(_qa491), preferencesReady: false);
      expect(status.state, SmartSearchState.notInUse);
    });

    final tag30 = libraryTagOf(30);
    for (final scenario in {
      'a damaged file': '{not json',
      'a file of a future format': jsonEncode({
        'libraryTag': tag30,
        'libraryVersion': 30,
        'plans': 'v9',
      }),
      'no plans at all': jsonEncode({
        'libraryTag': tag30,
        'libraryVersion': 30,
        'plans': <Object>[],
      }),
      'a plan of a future generation only': jsonEncode({
        'libraryTag': tag30,
        'libraryVersion': 30,
        'plans': [
          {
            'generation': 'qa900',
            'libraryTag': tag30,
            'libraryVersion': 30,
            'family': 'vectors',
          },
        ],
      }),
    }.entries) {
      for (final ready in [true, false]) {
        test('${scenario.key} in semantic.json is unverified, never '
            '${ready ? 'an empty drive' : 'not in use'} '
            '(preferences ${ready ? '' : 'not '}ready)', () async {
          await Directory(mirror).create(recursive: true);
          await File(
            p.join(mirror, 'semantic.json'),
          ).writeAsString(scenario.value);
          final status = await assess(_app(_qa491), preferencesReady: ready);
          expect(status.state, SmartSearchState.unverified);
          expect(status.reason, SmartSearchReason.driveUnreadable);
          expect(status.allClear, isFalse);
          expect(status.message, isNotNull);
        });
      }
    }

    test('a plan this tool cannot read hides a readable one of '
        'another generation', () async {
      github.legacyBase(30, identity: identityB);
      await sync(SemanticFleet([_machine(_round2)]));
      final json = await mirrorJson();
      (json['plans'] as List).add({
        'generation': 'qa900',
        'libraryTag': tag30,
        'libraryVersion': 30,
      });
      await File(
        p.join(mirror, 'semantic.json'),
      ).writeAsString(jsonEncode(json));
      final status = await assess(_app(_qa491));
      expect(status.state, SmartSearchState.unverified);
      expect(status.reason, SmartSearchReason.driveUnreadable);
      expect(
        (await assess(_app(_round2))).state,
        isNot(SmartSearchState.unverified),
        reason: 'the plan the application needs was read in full',
      );
    });

    test('a manifest of another model family is not offered', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      final dir = Directory(p.join(mirror, libraryTagOf(30), 'vectors'));
      final manifest = dir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.manifest.json'),
      );
      final json =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      ((json['identity'] as Map)['model'] as Map)['family_id'] = 'someone/else';
      manifest.writeAsStringSync(jsonEncode(json));
      final status = await assess(_app(_qa491));
      expect(status.allClear, isFalse);
      expect(status.installable, isFalse);
      expect(status.state, SmartSearchState.needsDriveDownload);
    });

    test('a truncated model file makes the drive incomplete', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      final model = File(
        p.join(
          mirror,
          libraryTagOf(30),
          SemanticModelSpec.qa491.folder,
          'LICENSE',
        ),
      );
      model.writeAsBytesSync([1]);
      final status = await assess(_app(_qa491));
      expect(status.reason, SmartSearchReason.driveIncomplete);
    });

    test('the drive holds an older library version', () async {
      github.qa491Base(29);
      await sync(SemanticFleet([_machine(_qa491)]), version: 29);
      final status = await assess(_app(_qa491), version: 30);
      expect(status.state, SmartSearchState.driveNotMatching);
      expect(status.reason, SmartSearchReason.driveOlderVersion);
    });
  });

  group('installed data against the application', () {
    test('a windows set without its marker is not current', () async {
      github.qa491Base(30, windows: true);
      await sync(SemanticFleet([_machine(_qa491, windows: true)]));
      await installModels(
        p.join(p.dirname(db), SemanticModelSpec.qa491.folder),
        qa491: true,
      );
      await writeInstalledSet(
        vectors,
        version: 30,
        windows: true,
        identity: identityC,
        familyId: SemanticModelSpec.qa491.familyId,
      );
      expect(
        (await assess(_app(_qa491, windows: true))).state,
        SmartSearchState.installedVerified,
      );
      File(
        p.join(vectors, SemanticSearchAssets.windowsIdentityFileName),
      ).deleteSync();
      final status = await assess(_app(_qa491, windows: true));
      expect(status.state, SmartSearchState.readyOnDrive);
      expect(status.missing, {SmartSearchPart.vectors});
    });

    for (final family in <String?>[
      null,
      'otzaria/Future-Gen-9',
      'ArieLLL123/other',
    ]) {
      test('a live set of an unknown model (${family ?? 'no family_id'}) is '
          'not verified', () async {
        github.legacyBase(30, identity: identityB);
        await sync(SemanticFleet([_machine(_round2)]));
        await installModels(
          p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
        );
        await writeInstalledSet(
          vectors,
          version: 30,
          windows: false,
          identity: identityB,
          familyId: family,
          omitFamily: family == null,
        );
        final status = await assess(_app(_round2));
        expect(status.allClear, isFalse);
        expect(status.state, isNot(SmartSearchState.installedVerified));
        expect(status.reason, SmartSearchReason.partsMissing);
        expect(status.missing, contains(SmartSearchPart.vectors));
      });
    }

    test('a QA491 windows set with no family_id is not verified', () async {
      github.qa491Base(30, windows: true);
      await sync(SemanticFleet([_machine(_qa491, windows: true)]));
      await installModels(
        p.join(p.dirname(db), SemanticModelSpec.qa491.folder),
        qa491: true,
      );
      await writeInstalledSet(
        vectors,
        version: 30,
        identity: identityC,
        omitFamily: true,
      );
      final status = await assess(_app(_qa491, windows: true));
      expect(status.allClear, isFalse);
      expect(status.missing, contains(SmartSearchPart.vectors));
    });

    test('a Round2 windows set is not kept for a QA491 application', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      await writeInstalledSet(vectors, version: 30, identity: identityA);
      final status = await assess(_app(_qa491, windows: true));
      expect(
        status.state,
        SmartSearchState.readyOnDrive,
        reason: 'its anchor set may be installed over another generation',
      );
    });

    test('a QA491 windows set is kept until a windows download', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      await writeInstalledSet(
        vectors,
        version: 29,
        identity: identityC,
        familyId: SemanticModelSpec.qa491.familyId,
      );
      final status = await assess(_app(_qa491, windows: true));
      expect(status.state, SmartSearchState.driveNotMatching);
      expect(status.reason, SmartSearchReason.keepsWindowsSet);
    });

    test('a partial result names what is missing', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      await installModels(
        p.join(p.dirname(db), SemanticModelSpec.qa491.folder),
        qa491: true,
      );
      final status = await assess(_app(_qa491), preferencesReady: false);
      expect(status.state, SmartSearchState.readyOnDrive);
      expect(status.missing, {
        SmartSearchPart.vectors,
        SmartSearchPart.preferences,
      });
      expect(status.present, {SmartSearchPart.model});
    });

    test('a failed completion check is not hidden behind a successful '
        'engine write', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      // The engine reports success but the set on disk is Round2's.
      final engine = FakeVectorsEngine();
      await assets(engine: engine).install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        vectorsRootPath: p.dirname(vectors),
        generation: _qa491,
      );
      await writeInstalledSet(
        vectors,
        version: 30,
        windows: false,
        identity: identityB,
      );
      final status = await assess(_app(_qa491));
      expect(status.allClear, isFalse);
      expect(status.missing, contains(SmartSearchPart.vectors));
    });
  });

  group('failure and cancellation while swapping', () {
    test('a refused install leaves the working set and its pointers', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      await writeInstalledSet(
        vectors,
        version: 29,
        windows: false,
        identity: identityB,
      );
      final before = File(p.join(vectors, 'CURRENT')).readAsStringSync();
      final engine = FakeVectorsEngine(
        error: const SemanticError(
          kind: SemanticErrorKind.artifactCorrupt,
          message: 'refused',
        ),
      );
      await expectLater(
        assets(engine: engine).install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          generation: _qa491,
        ),
        throwsA(isA<SemanticError>()),
      );
      expect(File(p.join(vectors, 'CURRENT')).readAsStringSync(), before);
      final live = (await SemanticSearchAssets.readInstalledSets(
        vectors,
      )).first;
      expect(live.identityDigest, identityB);
      expect(live.generation, _round2);
    });

    test('a cancellation after the models leaves the old set live', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      await writeInstalledSet(
        vectors,
        version: 29,
        windows: false,
        identity: identityB,
      );
      final before = File(p.join(vectors, 'CURRENT')).readAsStringSync();
      var calls = 0;
      await expectLater(
        assets(engine: FakeVectorsEngine()).install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: p.dirname(vectors),
          generation: _qa491,
          isCancelled: () => ++calls > 12,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(File(p.join(vectors, 'CURRENT')).readAsStringSync(), before);
    });
  });

  group('the drive travels', () {
    test('another computer installs from the drive with no network', () async {
      github.qa491Base(30);
      await sync(SemanticFleet([_machine(_qa491)]));
      final other = p.join(temp.path, 'other-machine', 'books', 'seforim.db');
      final offline = SemanticSearchAssets(
        httpClient: MockClient((request) async {
          fail('offline step sent a request to ${request.url}');
        }),
        models: fakeModels,
        specs: fakeSpecs,
        engineFactory: (_) async => FakeVectorsEngine(),
      );
      addTearDown(offline.dispose);
      final status = await offline.assess(
        mirrorDir: mirror,
        dbPath: other,
        libraryVersion: 30,
        support: _app(_qa491),
        vectorsRootPath: p.dirname(p.dirname(other)),
      );
      expect(status.state, SmartSearchState.readyOnDrive);
      await offline.install(
        mirrorDir: mirror,
        dbPath: other,
        libraryVersion: 30,
        vectorsRootPath: p.dirname(p.dirname(other)),
        generation: _qa491,
      );
      expect(
        File(
          p.join(
            p.dirname(other),
            SemanticModelSpec.qa491.folder,
            'model.json',
          ),
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('constants against the application', () {
    test('QA491 pins match the official release', () {
      const spec = SemanticModelSpec.qa491;
      expect(spec.folder, 'meivin-qa491-onnx');
      expect(spec.familyId, 'otzaria/Meivin-Embed-QA491-native256');
      expect(spec.baseUrl, endsWith('model-meivin-qa491-int8-v1'));
      expect(spec.graph.name, 'query.int8.onnx');
      expect(spec.graph.size, 42625431);
      expect(
        spec.graph.sha256,
        '82b87180616cee55357b90858f327f4d98b86b2e5589f6771d50b788ad383597',
      );
      expect(spec.identityFile.size, 634);
      expect(
        spec.identityFile.sha256,
        '58227b5df294a2c20a706482de5d431875941f22ee5007cf20ddc84536801fad',
      );
      expect(
        SemanticVectorsFamily.windows.releaseTagPrefixFor(_qa491),
        'vectors-qa491-windows-',
      );
      expect(
        SemanticVectorsFamily.windows.deltaReleaseTagPrefixFor(_qa491),
        'vectors-qa491-windows-delta-',
      );
      expect(
        SemanticVectorsFamily.legacy.releaseTagPrefixFor(_qa491),
        'vectors-qa491-',
      );
      expect(
        SemanticVectorsFamily.legacy.deltaReleaseTagPrefixFor(_qa491),
        isNull,
      );
    });

    test('the QA491 windows identity bytes are the application\'s', () {
      expect(kQa491WindowsModelIdentityJson.length, 633);
      expect(
        kQa491WindowsModelIdentityJson,
        contains('"chunking_identity": 320260894818558297'),
      );
    });
  });
}
