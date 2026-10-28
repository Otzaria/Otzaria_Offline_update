import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticError, SemanticErrorKind;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/failing_writes.dart' show diskFullErrno;
import 'support/semantic_fixtures.dart';

void main() {
  engineContractTest();
  const version = 30;
  late Directory temp;
  late String mirror;
  late String db;
  late FakeVectorsGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-contract-test-');
    mirror = p.join(temp.path, 'mirror');
    db = p.join(temp.path, 'machine', 'library', 'seforim.db');
    github = FakeVectorsGithub();
  });

  tearDown(() async {
    github.client.close();
    await temp.delete(recursive: true);
  });

  SemanticSearchAssets assets() =>
      SemanticSearchAssets(httpClient: github.client, models: fakeModels);

  Future<void> sync({
    SemanticFleet fleet = const SemanticFleet(),
    SemanticSearchAssets? using,
  }) async {
    final subject = using ?? assets();
    try {
      await subject.sync(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(version),
        fleet: fleet,
        libraryTagFor: libraryTagOf,
      );
    } finally {
      if (using == null) subject.dispose();
    }
  }

  Future<({bool pending, SemanticEngineIncompatibleException? why})> peek({
    SemanticFleet fleet = const SemanticFleet(),
  }) async {
    final subject = assets();
    try {
      final pending = await subject.peekPending(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(version),
        fleet: fleet,
      );
      return (pending: pending, why: subject.peekedIncompatibility);
    } finally {
      subject.dispose();
    }
  }

  const windowsFleet = SemanticFleet([
    SemanticMachineState(
      supportsWindows: true,
      family: SemanticVectorsFamily.windows,
      libraryVersion: 0,
    ),
  ]);

  for (final windows in [false, true]) {
    for (final line in [1, 5]) {
      test('a fresh ${windows ? 'windows' : 'legacy'} peek rejects text $line '
          'from metadata before offering a download', () async {
        if (windows) {
          github.windowsBase(version, lineTextVersion: line);
        } else {
          github.legacyBase(version, lineTextVersion: line);
        }
        final result = await peek(
          fleet: windows ? windowsFleet : const SemanticFleet(),
        );
        expect(result.pending, isFalse);
        expect(result.why?.lineTextVersion, line);
        expect(github.downloads, [
          windows ? baseManifestName(version) : legacyManifestName(version),
        ]);
      });
    }
  }

  group('a release the engine cannot read', () {
    test(
      'a fresh windows machine without a legacy fallback hears why',
      () async {
        github.windowsBase(version, lineTextVersion: 1);
        final result = await peek(
          fleet: const SemanticFleet([
            SemanticMachineState(
              supportsWindows: true,
              family: null,
              libraryVersion: 0,
            ),
          ]),
        );
        expect(result.pending, isFalse);
        expect(result.why?.lineTextVersion, 1);
        expect(github.downloads, [baseManifestName(version)]);
      },
    );
    test(
      'a fresh windows machine can still use readable legacy metadata',
      () async {
        github
          ..windowsBase(version, lineTextVersion: 1)
          ..legacyBase(version);
        final result = await peek(
          fleet: const SemanticFleet([
            SemanticMachineState(
              supportsWindows: true,
              family: null,
              libraryVersion: 0,
            ),
          ]),
        );
        expect(result.pending, isTrue);
        expect(result.why, isNull);
        expect(github.downloads, [
          baseManifestName(version),
          legacyManifestName(version),
        ]);
      },
    );
    test(
      'is refused from its manifest, before any asset is downloaded',
      () async {
        github.legacyBase(version, lineTextVersion: 1);

        await expectLater(
          sync(),
          throwsA(
            isA<SemanticEngineIncompatibleException>()
                .having((e) => e.lineTextVersion, 'line_text_version', 1)
                .having((e) => e.toolIsOlder, 'toolIsOlder', isFalse),
          ),
        );

        expect(github.downloads, [legacyManifestName(version)]);
        expect(
          Directory(mirror).existsSync() &&
              Directory(
                mirror,
              ).listSync().any((e) => e.path.endsWith('semantic.json')),
          isFalse,
        );
      },
    );

    test('built for a newer engine says the tool is the old side', () async {
      github.legacyBase(version, lineTextVersion: 5);

      await expectLater(
        sync(),
        throwsA(
          isA<SemanticEngineIncompatibleException>().having(
            (e) => e.toolIsOlder,
            'toolIsOlder',
            isTrue,
          ),
        ),
      );
      expect(github.downloads, [legacyManifestName(version)]);
    });

    test('the contract the engine reads is accepted whole', () async {
      github.legacyBase(version);

      await sync();

      expect(github.downloads, contains('legacy-v$version.oxv.zst'));
    });

    test(
      'an unusable windows release falls back to a readable legacy one',
      () async {
        github.windowsBase(version, lineTextVersion: 1);
        github.legacyBase(version);

        await sync(fleet: windowsFleet);

        expect(github.downloads, isNot(contains(baseSegmentName(version))));
        expect(github.downloads, contains('legacy-v$version.oxv.zst'));
      },
    );

    test(
      'both families unreadable is the incompatibility, not a retry',
      () async {
        github.windowsBase(version, lineTextVersion: 1);
        github.legacyBase(version, lineTextVersion: 1);

        await expectLater(
          sync(fleet: windowsFleet),
          throwsA(isA<SemanticEngineIncompatibleException>()),
        );
        expect(github.downloads, [
          baseManifestName(version),
          legacyManifestName(version),
        ]);
      },
    );

    test('is not offered again by the light check once it was found', () async {
      github.legacyBase(version, lineTextVersion: 1);
      expect((await peek()).pending, isFalse);

      final again = await peek();
      expect(again.pending, isFalse);
      expect(again.why?.lineTextVersion, 1);
      expect(github.downloads, [legacyManifestName(version)]);
    });

    test('a republished release is judged again', () async {
      github.legacyBase(version, lineTextVersion: 1);
      await expectLater(
        sync(),
        throwsA(isA<SemanticEngineIncompatibleException>()),
      );

      final fixed = FakeVectorsGithub()..legacyBase(version);
      final subject = SemanticSearchAssets(
        httpClient: fixed.client,
        models: fakeModels,
      );
      addTearDown(subject.dispose);
      expect(
        await subject.peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(version),
        ),
        isTrue,
      );
      await sync(using: subject);
      expect(fixed.downloads, contains('legacy-v$version.oxv.zst'));
    });
  });

  group('other shapes of an unreadable release', () {
    test('a manifest without identity.text reads as version 0', () async {
      github.legacyBase(version, emptyText: true);

      await expectLater(
        sync(),
        throwsA(
          isA<SemanticEngineIncompatibleException>()
              .having((e) => e.lineTextVersion, 'line_text_version', 0)
              .having((e) => e.toolIsOlder, 'toolIsOlder', isFalse),
        ),
      );
      expect(github.downloads, [legacyManifestName(version)]);
    });

    test('a key_version alone is enough to refuse', () async {
      github.legacyBase(version, keyVersion: 2);

      await expectLater(
        sync(),
        throwsA(
          isA<SemanticEngineIncompatibleException>()
              .having((e) => e.keyVersion, 'key_version', 2)
              .having((e) => e.toolIsOlder, 'toolIsOlder', isTrue),
        ),
      );
      expect(github.downloads, [legacyManifestName(version)]);
    });

    test('an unreadable delta falls back to the base', () async {
      github
        ..windowsBase(version)
        ..delta(version - 1, version, lineTextVersion: 1);

      await sync(
        fleet: const SemanticFleet([
          SemanticMachineState(
            supportsWindows: true,
            family: SemanticVectorsFamily.windows,
            libraryVersion: version - 1,
            identityDigest: identityA,
          ),
        ]),
      );

      expect(github.downloads, contains(baseSegmentName(version)));
      expect(
        github.downloads,
        isNot(contains(deltaSegmentName(version - 1, version))),
      );
    });

    test('the hint lapses when the engine contract it was written under '
        'changes', () async {
      github.legacyBase(version, lineTextVersion: 1);
      await expectLater(
        sync(),
        throwsA(isA<SemanticEngineIncompatibleException>()),
      );
      expect((await peek()).pending, isFalse);

      final hint = File(
        p.join(mirror, SemanticSearchAssets.incompatibleFileName),
      );
      final record = jsonDecode(await hint.readAsString()) as Map;
      (record['engine'] as Map)['lineTextVersion'] = 3;
      await hint.writeAsString(jsonEncode(record));

      final checkedAgain = await peek();
      expect(checkedAgain.pending, isFalse);
      expect(checkedAgain.why?.lineTextVersion, 1);
      expect(github.downloads, [
        legacyManifestName(version),
        legacyManifestName(version),
      ]);
    });
  });

  group('the target Otzaria', () {
    late FakeVectorsEngine engine;

    Future<bool> install(bool? reads, {SemanticError? error}) async {
      github.windowsBase(version);
      await sync(fleet: windowsFleet);
      engine = FakeVectorsEngine(present: false, error: error);
      final offline = SemanticSearchAssets(
        models: fakeModels,
        engineFactory: (_) async => engine,
      );
      addTearDown(offline.dispose);
      return offline.install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: version,
        vectorsRootPath: p.dirname(db).replaceFirst('library', ''),
        supportsWindows: true,
        targetReadsLineText4: reads,
      );
    }

    for (final (name, error) in [
      (
        'InsufficientDiskSpace',
        const SemanticError(
          kind: SemanticErrorKind.insufficientDiskSpace,
          message: 'needs more free space',
        ),
      ),
      (
        'an Internal error carrying the OS code',
        SemanticError(
          kind: SemanticErrorKind.internal,
          message: 'write failed: no space (os error $diskFullErrno)',
        ),
      ),
    ]) {
      test('a full drive reported by the engine as $name is a '
          'StorageFullException', () async {
        await expectLater(
          install(true, error: error),
          throwsA(
            isA<StorageFullException>().having((e) => e.cause, 'cause', error),
          ),
        );
      });
    }

    test('one that reads text 4 installs', () async {
      expect(await install(true), isTrue);
      expect(engine.installs, hasLength(1));
    });

    test('one known not to read it keeps the set and reports it', () async {
      await expectLater(
        install(false),
        throwsA(
          isA<SemanticEngineIncompatibleException>().having(
            (e) => e.reason,
            'reason',
            SemanticIncompatibilityReason.updateOtzaria,
          ),
        ),
      );
      expect(engine.installs, isEmpty);
      expect(
        File(
          p.join(
            p.dirname(db).replaceFirst('library', ''),
            'vectors',
            'CURRENT',
          ),
        ).existsSync(),
        isFalse,
      );
    });

    test('one whose version is unknown is not assumed to read it', () async {
      await expectLater(
        install(null),
        throwsA(
          isA<SemanticEngineIncompatibleException>().having(
            (e) => e.reason,
            'reason',
            SemanticIncompatibilityReason.otzariaUnproven,
          ),
        ),
      );
      expect(engine.installs, isEmpty);
    });
  });

  group('a legacy release republished under the same tag', () {
    Future<bool> pendingWith(String installedIdentity) async {
      github.legacyBase(version, identity: identityA);
      await sync();
      await installModels(
        p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
      );
      final root = p.join(temp.path, 'root');
      await writeInstalledSet(
        p.join(root, 'vectors'),
        version: version,
        identity: installedIdentity,
        windows: false,
      );
      final offline = SemanticSearchAssets(models: fakeModels);
      addTearDown(offline.dispose);
      return offline.pending(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: version,
        vectorsRootPath: root,
      );
    }

    test('is offered over a set installed under another identity', () async {
      expect(await pendingWith(identityB), isTrue);
    });

    test('is not offered over the set it published', () async {
      expect(await pendingWith(identityA), isFalse);
    });

    test(
      'is offered when only the previous set matches, not the live one',
      () async {
        github.legacyBase(version, identity: identityA);
        await sync();
        await installModels(
          p.join(p.dirname(db), SemanticSearchAssets.modelFolder),
        );
        final vectors = p.join(temp.path, 'root', 'vectors');
        await writeInstalledSet(
          vectors,
          version: version,
          identity: identityA,
          windows: false,
        );
        await File(
          p.join(vectors, 'CURRENT'),
        ).rename(p.join(vectors, 'PREVIOUS'));
        await writeInstalledSet(
          vectors,
          version: version - 1,
          identity: identityA,
          windows: false,
        );
        final offline = SemanticSearchAssets(models: fakeModels);
        addTearDown(offline.dispose);

        expect(
          await offline.pending(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: version,
            vectorsRootPath: p.join(temp.path, 'root'),
          ),
          isTrue,
        );
      },
    );
  });

  group('the family a machine selects decides', () {
    const mixed = SemanticFleet([
      SemanticMachineState(
        supportsWindows: false,
        family: SemanticVectorsFamily.legacy,
        libraryVersion: 0,
      ),
      SemanticMachineState(
        supportsWindows: true,
        family: SemanticVectorsFamily.windows,
        libraryVersion: 0,
      ),
    ]);

    /// Makes the mirror's [windows] or legacy manifest declare text 1.
    Future<void> tamper({required bool windows}) async {
      github
        ..legacyBase(version)
        ..windowsBase(version);
      await sync(fleet: mixed);
      final name = windows
          ? baseManifestName(version)
          : legacyManifestName(version);
      final file = File(p.join(mirror, libraryTagOf(version), 'vectors', name));
      final manifest = jsonDecode(await file.readAsString()) as Map;
      ((manifest['identity'] as Map)['text'] as Map)['line_text_version'] = 1;
      final bytes = utf8.encode(jsonEncode(manifest));
      await file.writeAsBytes(bytes);
      final metaFile = File(
        p.join(mirror, SemanticSearchAssets.manifestFileName),
      );
      final meta = jsonDecode(await metaFile.readAsString()) as Map;
      final target = windows ? meta['windows'] as Map : meta;
      final entry = windows ? target['base'] as Map : target;
      entry[windows ? 'size' : 'manifestSize'] = bytes.length;
      entry[windows ? 'sha256' : 'manifestSha256'] = Sha256Stream.ofBytes(
        bytes,
      );
      await metaFile.writeAsString(jsonEncode(meta));
    }

    Future<({bool pending, SemanticEngineIncompatibleException? why})> check({
      required bool windows,
    }) async {
      final subject = assets();
      addTearDown(subject.dispose);
      return (
        pending: await subject.pending(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: version,
          supportsWindows: windows,
        ),
        why: await subject.incompatibility(
          mirrorDir: mirror,
          libraryVersion: version,
          supportsWindows: windows,
        ),
      );
    }

    test(
      'a readable windows family is offered over an unreadable legacy one',
      () async {
        await tamper(windows: false);
        final result = await check(windows: true);
        expect(result.pending, isTrue);
        expect(result.why, isNull);
      },
    );

    test(
      'an unreadable selected family is reported, not the other one',
      () async {
        await tamper(windows: true);
        final windows = await check(windows: true);
        expect(windows.pending, isFalse);
        expect(windows.why, isNotNull);
        final legacy = await check(windows: false);
        expect(legacy.pending, isTrue);
        expect(legacy.why, isNull);
      },
    );

    test('a machine without windows support selects legacy in both', () async {
      await tamper(windows: false);
      final result = await check(windows: false);
      expect(result.pending, isFalse);
      expect(result.why?.lineTextVersion, 1);
    });
  });

  group(
    'a machine on a live windows set facing an unreadable windows release',
    () {
      String root() => p.join(temp.path, 'machine');

      Future<void> mirrorFallsBackToLegacy() async {
        github
          ..windowsBase(version, lineTextVersion: 1)
          ..legacyBase(version);
        await sync(fleet: windowsFleet);
      }

      SemanticFleet machineWith(SemanticVectorsFamily? family) =>
          SemanticFleet([
            SemanticMachineState(
              supportsWindows: true,
              family: family,
              libraryVersion: family == null ? 0 : version - 1,
              identityDigest: family == null ? '' : identityA,
            ),
          ]);

      test('is told why nothing installs, online and offline alike', () async {
        await mirrorFallsBackToLegacy();
        await writeInstalledSet(
          p.join(root(), 'vectors'),
          version: version - 1,
          identity: identityA,
        );
        final offline = SemanticSearchAssets(models: fakeModels);
        addTearDown(offline.dispose);

        expect(
          await offline.pending(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: version,
            vectorsRootPath: root(),
            supportsWindows: true,
          ),
          isFalse,
        );
        final why = await offline.incompatibility(
          mirrorDir: mirror,
          libraryVersion: version,
          supportsWindows: true,
          vectorsRootPath: root(),
        );
        expect(why?.reason, SemanticIncompatibilityReason.republishAssets);

        final online = await peek(
          fleet: machineWith(SemanticVectorsFamily.windows),
        );
        expect(online.pending, isFalse);
        expect(
          online.why?.reason,
          SemanticIncompatibilityReason.republishAssets,
        );
      });

      test(
        'a machine without a windows set still gets the legacy vectors',
        () async {
          await mirrorFallsBackToLegacy();
          final offline = SemanticSearchAssets(models: fakeModels);
          addTearDown(offline.dispose);

          expect(
            await offline.incompatibility(
              mirrorDir: mirror,
              libraryVersion: version,
              supportsWindows: true,
              vectorsRootPath: root(),
            ),
            isNull,
          );
          expect((await peek(fleet: machineWith(null))).why, isNull);
        },
      );
    },
  );

  group('a mirror that already holds an unreadable release', () {
    Future<void> holdUnreadableRelease() async {
      github.legacyBase(version);
      await sync();
      final tag = libraryTagOf(version);
      final manifestFile = File(
        p.join(mirror, tag, 'vectors', legacyManifestName(version)),
      );
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      ((manifest['identity'] as Map)['text'] as Map)['line_text_version'] = 1;
      final bytes = utf8.encode(jsonEncode(manifest));
      await manifestFile.writeAsBytes(bytes);
      final metaFile = File(
        p.join(mirror, SemanticSearchAssets.manifestFileName),
      );
      final meta = jsonDecode(await metaFile.readAsString()) as Map;
      meta['manifestSize'] = bytes.length;
      meta['manifestSha256'] = Sha256Stream.ofBytes(bytes);
      await metaFile.writeAsString(jsonEncode(meta));
      github.legacyBase(version, lineTextVersion: 1);
    }

    test('the light check does not offer it again', () async {
      await holdUnreadableRelease();

      final result = await peek();

      expect(result.pending, isFalse);
      expect(result.why?.lineTextVersion, 1);
    });

    test(
      'a machine keeping its windows set is not told to republish legacy',
      () async {
        await holdUnreadableRelease();
        final root = p.join(temp.path, 'machine');
        await writeInstalledSet(p.join(root, 'vectors'), version: version - 1);
        final offline = SemanticSearchAssets(models: fakeModels);
        addTearDown(offline.dispose);

        expect(
          await offline.incompatibility(
            mirrorDir: mirror,
            libraryVersion: version,
            supportsWindows: true,
            vectorsRootPath: root,
          ),
          isNull,
        );
      },
    );

    test(
      'the offline check offers no install and install names the cause',
      () async {
        await holdUnreadableRelease();
        final offline = SemanticSearchAssets(models: fakeModels);
        addTearDown(offline.dispose);

        expect(
          await offline.pending(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: version,
          ),
          isFalse,
        );
        await expectLater(
          offline.install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: version,
          ),
          throwsA(isA<SemanticEngineIncompatibleException>()),
        );
        expect(
          (await offline.incompatibility(
            mirrorDir: mirror,
            libraryVersion: version,
          ))?.lineTextVersion,
          1,
        );
      },
    );
  });
}

/// הקבוע שהמראה בודקת חייב לעקוב אחרי המנוע שנארז; אחרת ההורדה מתקבלת וההתקנה
/// נדחית ב-`artifactIncompatible`.
void engineContractTest() {
  test('the text contract is the one the pinned engine declares', () {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map;
    final engine = (config['packages'] as List).cast<Map>().firstWhere(
      (package) => package['name'] == 'otzaria_search_engine',
    );
    final root = Uri.parse(
      engine['rootUri'] as String,
    ).resolve('').toFilePath();
    final source = File(p.join(root, 'rust', 'src', 'api', 'search_engine.rs'));
    if (!source.existsSync()) {
      markTestSkipped('the engine source is not in the package cache');
      return;
    }
    final declared = RegExp(
      r'const LINE_TEXT_VERSION: u32 = (\d+);',
    ).firstMatch(source.readAsStringSync());
    expect(
      int.parse(declared!.group(1)!),
      kSemanticEngineText.lineTextVersion,
      reason: 'bump otzaria_search_engine or kSemanticEngineText together',
    );
  });
}
