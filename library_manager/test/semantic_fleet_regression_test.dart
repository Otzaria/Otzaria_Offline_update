import 'dart:convert';
import 'dart:io';

import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/db_fixtures.dart';
import 'support/semantic_fixtures.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-fleet-');
  });
  tearDown(() async => temp.delete(recursive: true));

  for (final mixed in [false, true]) {
    test(
      'download bound stays unknown for ${mixed ? 'mixed' : 'windows'} fleet',
      () async {
        final github = FakeVectorsGithub()
          ..windowsBase(30)
          ..legacyBase(30);
        addTearDown(github.client.close);
        final assets = SemanticSearchAssets(
          httpClient: github.client,
          models: fakeModels,
        );
        addTearDown(assets.dispose);
        final pending = await assets.peekPending(
          mirrorDir: p.join(temp.path, 'mirror'),
          libraryTag: libraryTagOf(30),
          fleet: SemanticFleet([
            const SemanticMachineState(
              supportsWindows: true,
              family: SemanticVectorsFamily.windows,
              libraryVersion: 29,
              identityDigest: identityA,
            ),
            if (mixed)
              const SemanticMachineState(
                supportsWindows: false,
                family: SemanticVectorsFamily.legacy,
                libraryVersion: 29,
              ),
          ]),
        );
        expect(pending, isTrue);
        expect(assets.peekedPendingBytes, isNull);
      },
    );
  }

  test(
    'a mixed fleet must still update its existing windows machine',
    () async {
      final github = FakeVectorsGithub()
        ..windowsBase(30)
        ..legacyBase(30);
      addTearDown(github.client.close);
      final engines = <FakeVectorsEngine>[];
      final assets = SemanticSearchAssets(
        httpClient: github.client,
        models: fakeModels,
      );
      addTearDown(assets.dispose);
      final mirror = p.join(temp.path, 'mirror');
      final db = p.join(temp.path, 'machine', 'books', 'seforim.db');
      final vectors = p.join(temp.path, 'machine', 'vectors');
      await assets.sync(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(30),
        fleet: const SemanticFleet([
          SemanticMachineState(
            supportsWindows: true,
            family: SemanticVectorsFamily.windows,
            libraryVersion: 29,
            identityDigest: identityA,
          ),
          SemanticMachineState(
            supportsWindows: false,
            family: SemanticVectorsFamily.legacy,
            libraryVersion: 29,
          ),
        ]),
      );
      await writeInstalledSet(vectors, version: 29);
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      final pending = await assets.pending(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        supportsWindows: true,
      );
      expect(
        pending,
        isTrue,
        reason: 'v29 windows machine must not silently stop receiving updates',
      );
      final offline = SemanticSearchAssets(
        httpClient: MockClient((request) async {
          fail('offline install sent a request to ${request.url}');
        }),
        models: fakeModels,
        engineFactory: (_) async {
          final engine = FakeVectorsEngine(version: 29);
          engines.add(engine);
          return engine;
        },
      );
      addTearDown(offline.dispose);
      await offline.install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        supportsWindows: true,
      );
      expect(engines.single.version, 30);
      expect(
        engines.single.installs.single.modelIdentityJson,
        kWindowsModelIdentityJson,
      );

      final legacyDb = p.join(temp.path, 'legacy', 'books', 'seforim.db');
      expect(
        await offline.pending(
          mirrorDir: mirror,
          dbPath: legacyDb,
          libraryVersion: 30,
        ),
        isTrue,
      );
      await offline.install(
        mirrorDir: mirror,
        dbPath: legacyDb,
        libraryVersion: 30,
      );
      expect(engines, hasLength(2));
      expect(engines.last.installs.single.modelIdentityJson, fakeModelJson);
      expect(engines.every((engine) => engine.disposed), isTrue);
      expect(
        github.downloads.where((name) => name == 'model.json'),
        hasLength(1),
      );
      final meta =
          jsonDecode(
                await File(
                  p.join(mirror, SemanticSearchAssets.manifestFileName),
                ).readAsString(),
              )
              as Map;
      expect(meta['manifestName'], legacyManifestName(30));
      expect(meta['windows']['family'], 'windows');
    },
  );

  for (final settings in [null, const OtzariaSettings()]) {
    test(
      settings == null
          ? 'a failed settings read preserves the record and its recovery request'
          : 'confirmed absence of consent removes the machine record',
      () async {
        final dataDir = p.join(temp.path, 'data');
        final store = LibraryStateStore(
          p.join(dataDir, LibraryStateStore.fileName),
        );
        final db = p.join(temp.path, 'seforim.db');
        await File(db).writeAsBytes(buildVersionOnlyDb(temp.path, 30));
        await store.saveCustomDbPath(db);
        const recorded = SemanticMachineState(
          supportsWindows: false,
          family: SemanticVectorsFamily.legacy,
          libraryVersion: 29,
          needsBase: true,
        );
        await store.recordOwnSemanticState(recorded);
        final manifest = File(
          p.join(dataDir, 'mirror', 'library', 'releases.json'),
        );
        await manifest.parent.create(recursive: true);
        await manifest.writeAsString(
          jsonEncode({
            'formatVersion': 1,
            'exportedAt': DateTime.now().toIso8601String(),
            'releases': [
              {
                'tag': libraryTagOf(30),
                'isPrerelease': false,
                'isDraft': false,
                'assets': [],
              },
            ],
          }),
        );
        final manager = LibraryManager(
          dataDir: dataDir,
          operatingSystem: 'linux',
          environment: {'HOME': p.join(temp.path, 'home')},
          settingsReader: _SettingsReader(settings),
        );
        addTearDown(manager.dispose);
        await manager.checkForUpdate();
        expect(
          (await store.loadOwnSemanticState())?.toJson(),
          settings == null ? recorded.toJson() : null,
        );
      },
    );
  }
}

class _SettingsReader extends OtzariaSettingsReader {
  const _SettingsReader(this.settings);

  final OtzariaSettings? settings;

  @override
  Future<OtzariaSettings?> read(String dataRootPath) async => settings;
}
