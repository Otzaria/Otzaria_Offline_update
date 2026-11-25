import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/setup_error_screen.dart';
import 'package:launcher_app/src/services/app_paths.dart';
import 'package:launcher_app/src/services/machine_state_migration.dart';
import 'package:library_manager/library_manager.dart' show LibraryStateStore;
import 'package:path/path.dart' as p;

import 'test_harness.dart';

void main() {
  late Directory sandbox;
  late String drive;
  late String machine;
  late AppPaths paths;

  File state(String dir, String name, {bool legacy = false}) =>
      File(p.joinAll([dir, if (!legacy) 'logs', name]));

  void save(String dir, String name, Map<String, Object?> value,
      {bool legacy = false}) {
    state(dir, name, legacy: legacy)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(value));
  }

  Map<String, dynamic> load(String name) =>
      jsonDecode(state(drive, name).readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('machine-state-migration-');
    drive = p.join(sandbox.path, 'drive');
    machine = p.join(sandbox.path, 'machine');
    Directory(p.join(drive, 'logs')).createSync(recursive: true);
    paths = AppPaths(
      dataDir: drive,
      stateDir: drive,
      readOnly: true,
      mirrorLocked: true,
      prefsDir: machine,
    );
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  test('imports an explicit machine choice without losing another computer',
      () async {
    final local = LibraryStateStore.inDir(p.join(machine, 'logs'));
    final chosen = p.join(sandbox.path, 'chosen', 'seforim.db');
    await local.saveCustomDbPath(chosen, explicit: true);
    save(drive, 'library_state.json', {
      'customDbPaths': {'online': 'online.db'},
      'readableSemanticTarget': {'tag': 'drive-semantic'},
    });

    await paths.seedStateFromMachine();

    final choice =
        await LibraryStateStore.inDir(paths.stateFilesDir).loadCustomDbChoice();
    expect(choice, (path: chosen, explicit: true));
    expect(load('library_state.json')['customDbPaths']['online'], 'online.db');
    expect(load('library_state.json')['readableSemanticTarget'],
        {'tag': 'drive-semantic'});
    expect(await local.loadCustomDbChoice(), choice);
  });

  test('merges legacy roots on both sides before moving state to logs',
      () async {
    save(
        drive,
        'notices_seen.json',
        {
          'seen': {
            'online': ['one']
          },
        },
        legacy: true);
    save(
        machine,
        'notices_seen.json',
        {
          'seen': {
            'offline': ['two']
          },
        },
        legacy: true);

    await paths.seedStateFromMachine();
    await paths.migrateStateFiles();

    expect(load('notices_seen.json')['seen'], {
      'online': ['one'],
      'offline': ['two'],
    });
  });

  test('an unchanged source cannot resurrect a deleted destination choice',
      () async {
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'old.db'},
    });
    await paths.seedStateFromMachine();
    save(drive, 'library_state.json', {'customDbPaths': <String, Object?>{}});

    await paths.seedStateFromMachine();

    expect(load('library_state.json')['customDbPaths'], isEmpty);
  });

  test('a later read-only session imports only changed local records',
      () async {
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'old.db', 'removed': 'stale.db'},
    });
    await paths.seedStateFromMachine();
    save(drive, 'library_state.json', {
      'customDbPaths': {'offline': 'old.db'},
    });
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'new.db', 'removed': 'stale.db'},
      'customDbPathsExplicit': {'offline': 'new.db'},
    });

    await paths.seedStateFromMachine();

    expect(load('library_state.json')['customDbPaths'], {'offline': 'new.db'});
    expect(load('library_state.json')['customDbPathsExplicit'],
        {'offline': 'new.db'});
  });

  test('a pending launcher report reaches the drive with its original envelope',
      () async {
    final local = AppReportService(directory: AppReportService.dirIn(machine));
    final portable = AppReportService(directory: AppReportService.dirIn(drive));
    addTearDown(local.dispose);
    addTearDown(portable.dispose);
    await local.queueReport(AppReport(
      reportId: 'offline-report',
      type: AppReportType.bug,
      trigger: AppReportTrigger.manual,
      title: 'Offline report',
      description: 'Queued while the drive was entirely read-only',
      reporterEmail: 'qa@example.invalid',
      appVersion: '0.30',
      platform: 'windows',
      createdAt: DateTime.utc(2026, 11, 20),
      diagnostics: const {'keep': 'attached'},
      errorLog: 'original log',
    ));
    final original = Directory(p.join(local.directory, 'pending'))
        .listSync()
        .whereType<File>()
        .single;
    final bytes = original.readAsBytesSync();

    await paths.seedStateFromMachine();

    expect(await portable.getPendingReportsCount(), 1);
    expect(await local.getPendingReportsCount(), 0);
    expect(
        File(p.join(portable.directory, 'pending', p.basename(original.path)))
            .readAsBytesSync(),
        bytes);
    await portable.deletePendingReport('offline-report');
    await paths.seedStateFromMachine();
    expect(await portable.getPendingReportsCount(), 0);
  });

  test('merges every state schema without mixing a logical record', () async {
    final fixtures = <String, (Map<String, Object?>, Map<String, Object?>)>{
      'otzaria_install_state.json': (
        {
          'installedTagName': 'online',
          'installDir': 'drive',
          'launchPath': 'drive.exe'
        },
        {
          'installedTagName': 'offline',
          'installDir': 'local',
          'launchPath': 'local.exe'
        },
      ),
      'store_app_destination.json': (
        {
          'hosts': {
            'same': {'dir': 'drive', 'tag': 'drive-tag'}
          }
        },
        {
          'hosts': {
            'same': {'dir': 'local', 'tag': 'local-tag'},
            'new': {'dir': 'new', 'tag': 'new-tag'}
          }
        },
      ),
      'custom_apps_announced.json': (
        {
          'announced': {
            'same': ['a']
          }
        },
        {
          'announced': {
            'same': ['b'],
            'new': ['c']
          }
        },
      ),
      'plugins_known.json': (
        {
          'hosts': {
            'same': {
              'seen': ['a'],
              'notified': ['x']
            }
          }
        },
        {
          'hosts': {
            'same': {
              'seen': ['b'],
              'notified': ['y']
            },
            'new': {'seen': <String>[]}
          }
        },
      ),
      'notices_seen.json': (
        {
          'seen': {
            'same': ['a']
          }
        },
        {
          'seen': {
            'same': ['b']
          }
        },
      ),
      'library_state.json': (
        {
          'customDbPaths': {'same': 'drive.db'},
          'customDbPathsExplicit': {'same': 'drive.db'},
          'appliedReleases': {
            'same': {'tag': 'drive-tag', 'dbVersion': 1}
          },
          'deliveredCompanions': {
            'same': {'a': 'drive-digest'}
          },
          'readableSemanticTarget': {'tag': 'drive'},
        },
        {
          'customDbPaths': {'same': 'local.db'},
          'customDbPathsExplicit': {'same': 'local.db'},
          'appliedReleases': {
            'same': {'tag': 'local-tag', 'dbVersion': 2},
            'new': {'tag': 'new', 'dbVersion': 3}
          },
          'deliveredCompanions': {
            'same': {'a': 'local-digest', 'b': 'new-digest'}
          },
          'readableSemanticTarget': {'tag': 'unrelated-drive'},
        },
      ),
    };
    expect(fixtures.keys.toSet(), AppPaths.stateFileNames.toSet());
    for (final entry in fixtures.entries) {
      save(drive, entry.key, entry.value.$1);
      save(machine, entry.key, entry.value.$2);
    }

    await paths.seedStateFromMachine();

    expect(load('otzaria_install_state.json'),
        fixtures['otzaria_install_state.json']!.$1);
    expect(load('store_app_destination.json')['hosts'], {
      'same': {'dir': 'drive', 'tag': 'drive-tag'},
      'new': {'dir': 'new', 'tag': 'new-tag'},
    });
    expect(load('custom_apps_announced.json')['announced'], {
      'same': ['a', 'b'],
      'new': ['c']
    });
    expect(load('notices_seen.json')['seen'], {
      'same': ['a', 'b']
    });
    expect(load('plugins_known.json')['hosts'], {
      'same': {
        'seen': ['a', 'b'],
        'notified': ['x', 'y']
      },
      'new': {'seen': <String>[]},
    });
    final library = load('library_state.json');
    expect(library['customDbPaths'], {'same': 'drive.db'});
    expect(library['customDbPathsExplicit'], {'same': 'drive.db'});
    expect(library['appliedReleases'], {
      'same': {'tag': 'drive-tag', 'dbVersion': 1},
      'new': {'tag': 'new', 'dbVersion': 3},
    });
    expect(library['deliveredCompanions'], {
      'same': {'a': 'drive-digest', 'b': 'new-digest'}
    });
    expect(library['readableSemanticTarget'], {'tag': 'drive'});
  });

  for (final year in [2020, 2032]) {
    test(
        'aligns logical clocks without expiring active machines (source $year)',
        () async {
      Map<String, Object?> semantic(String name, int version, String seen) => {
            'supportsWindows': true,
            'family': 'none',
            'libraryVersion': version,
            'identityDigest': name,
            'seen': seen,
          };
      const targetTime = '2026-01-01T00:00:00.000Z';
      final sourceTime = '$year-01-01T00:00:00.000Z';
      save(drive, 'library_state.json', {
        'knownDbVersions': {'online': 4},
        'knownDbVersionsSeen': {'online': targetTime},
        'semanticMachines': {'online': semantic('online', 4, targetTime)},
      });
      save(machine, 'library_state.json', {
        'knownDbVersions': {'offline': 8},
        'knownDbVersionsSeen': {'offline': sourceTime},
        'semanticMachines': {'offline': semantic('offline', 8, sourceTime)},
      });

      await paths.seedStateFromMachine();

      final store = LibraryStateStore.inDir(paths.stateFilesDir);
      expect(await store.lowestKnownDbVersion(), 4);
      expect((await store.liveRegisteredMachines()).map((m) => m.key).toSet(),
          {'online', 'offline'});
      expect(
          (await store.liveSemanticStates())
              .map((m) => m.identityDigest)
              .toSet(),
          {'online', 'offline'});
      expect(load('library_state.json')['knownDbVersionsSeen']['offline'],
          targetTime);
    });
  }

  test('timestamped version records move together and retain the newer writer',
      () async {
    save(drive, 'library_state.json', {
      'knownDbVersions': {'fresh-source': 1, 'fresh-target': 7},
      'knownDbVersionsSeen': {
        'fresh-source': '2020-01-01Z',
        'fresh-target': '2020-01-01Z'
      },
      'knownDbVersionsLocalTime': {
        'fresh-source': '2026-01-01T00:00:00Z',
        'fresh-target': '2026-03-01T00:00:00Z'
      },
      'knownDbVersionsNames': {'fresh-source': 'old', 'fresh-target': 'keep'},
    });
    save(machine, 'library_state.json', {
      'knownDbVersions': {'fresh-source': 2, 'fresh-target': 6},
      'knownDbVersionsSeen': {
        'fresh-source': '2030-01-01Z',
        'fresh-target': '2030-01-01Z'
      },
      'knownDbVersionsLocalTime': {
        'fresh-source': '2026-02-01T00:00:00Z',
        'fresh-target': '2026-02-01T00:00:00Z'
      },
      'knownDbVersionsNames': {
        'fresh-source': 'new',
        'fresh-target': 'discard'
      },
    });

    await paths.seedStateFromMachine();

    final json = load('library_state.json');
    expect(json['knownDbVersions'], {'fresh-source': 2, 'fresh-target': 7});
    expect(json['knownDbVersionsNames'],
        {'fresh-source': 'new', 'fresh-target': 'keep'});
    expect(json['knownDbVersionsLocalTime'], {
      'fresh-source': '2026-02-01T00:00:00Z',
      'fresh-target': '2026-03-01T00:00:00Z',
    });
  });

  test('malformed local records are not interpreted as intentional deletions',
      () async {
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'keep.db'}
    });
    await paths.seedStateFromMachine();
    save(machine, 'library_state.json', {'customDbPaths': 'damaged'});

    await expectLater(
        paths.seedStateFromMachine(), throwsA(isA<AppPathsException>()));

    expect(load('library_state.json')['customDbPaths'], {'offline': 'keep.db'});
  });

  test('an explicit record removal in a valid source is still imported',
      () async {
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'remove.db'}
    });
    await paths.seedStateFromMachine();
    save(machine, 'library_state.json', {'customDbPaths': <String, Object?>{}});

    await paths.seedStateFromMachine();

    expect(load('library_state.json')['customDbPaths'], isEmpty);
  });

  final invalidStates =
      <(String, Map<String, Object?>, List<Map<String, Object?>>)>[
    (
      'library_state.json',
      {
        'customDbPaths': {'offline': 'keep.db'}
      },
      [
        {'customDbPaths': null},
        {
          'customDbPaths': {'offline': 42}
        },
        {
          'customDbPathsExplicit': {'offline': true}
        },
        {'customDbPath': 42},
        {
          'appliedReleases': {
            'offline': {'tag': 42, 'dbVersion': 1}
          }
        },
        {
          'deliveredCompanions': {'offline': null}
        },
        {
          'knownDbVersions': {'offline': '42'}
        },
        {
          'knownDbVersionsSeen': {'offline': 42}
        },
        {
          'knownDbVersionsLocalTime': {'offline': 42}
        },
        {
          'knownDbVersionsNames': {'offline': 42}
        },
        {
          'semanticMachines': {
            'offline': {'supportsWindows': 'broken'}
          }
        },
      ]
    ),
    (
      'otzaria_install_state.json',
      {'installedTagName': 'v', 'installDir': 'dir', 'launchPath': 'app'},
      [
        {'installedTagName': 42},
        {'installedTagName': 'v', 'installDir': 'dir'},
      ]
    ),
    (
      'custom_apps_announced.json',
      {
        'announced': {
          'offline': ['a']
        }
      },
      [
        {'announced': null},
        {
          'announced': {
            'offline': ['a', 42]
          }
        },
      ]
    ),
    (
      'plugins_known.json',
      {
        'hosts': {
          'offline': {
            'seen': ['a']
          }
        }
      },
      [
        {
          'hosts': {'offline': null}
        },
        {
          'hosts': {
            'offline': {'seen': null}
          }
        },
        {
          'hosts': {
            'offline': {
              'seen': [42]
            }
          }
        },
      ]
    ),
    (
      'notices_seen.json',
      {
        'seen': {
          'offline': ['a']
        }
      },
      [
        {'seen': 42},
        {
          'seen': {'offline': 42}
        },
      ]
    ),
    (
      'store_app_destination.json',
      {
        'hosts': {
          'offline': {'dir': 'dir', 'tag': 'v'}
        }
      },
      [
        {'hosts': 42},
        {
          'hosts': {
            'offline': {'dir': 42, 'tag': 'v'}
          }
        },
      ]
    ),
  ];
  for (final (name, original, broken) in invalidStates) {
    for (var i = 0; i < broken.length; i++) {
      test(
          'invalid $name field/record $i cannot delete previously imported state',
          () async {
        save(machine, name, original);
        await paths.seedStateFromMachine();
        final before = state(drive, name).readAsBytesSync();
        save(machine, name, broken[i]);

        await expectLater(
            paths.seedStateFromMachine(), throwsA(isA<AppPathsException>()));

        expect(state(drive, name).readAsBytesSync(), before);
      });
    }
  }

  test('fallback machine identity does not filter its own legacy records',
      () async {
    final key = LibraryStateStore.legacyMachineKey();
    save(machine, 'library_state.json', {
      'customDbPaths': {key: 'local.db'}
    });

    await MachineStateMigration(
            sourceDir: machine,
            targetDir: drive,
            fileNames: AppPaths.stateFileNames,
            machineKey: key)
        .run();

    expect(load('library_state.json')['customDbPaths'], {key: 'local.db'});
  });

  test(
      'a valid legacy absolute choice is upgraded, without carrying drive globals',
      () async {
    final chosen = p.join(sandbox.path, 'local-books', 'seforim.db');
    Directory(p.dirname(chosen)).createSync();
    save(
        machine,
        'library_state.json',
        {
          'customDbPath': chosen,
          'readableSemanticTarget': {'tag': 'different-drive'},
        },
        legacy: true);

    await paths.seedStateFromMachine();

    final store = LibraryStateStore.inDir(paths.stateFilesDir, dataDir: drive);
    expect(await store.loadCustomDbChoice(), (path: chosen, explicit: false));
    expect(load('library_state.json').containsKey('readableSemanticTarget'),
        isFalse);
  });

  test('legacy fallback copy is atomic and leaves its source on failure',
      () async {
    save(
        drive,
        'library_state.json',
        {
          'customDbPaths': {'offline': 'keep.db'}
        },
        legacy: true);
    final source = state(drive, 'library_state.json', legacy: true);
    final target = state(drive, 'library_state.json');

    await IOOverrides.runWithIOOverrides(paths.migrateStateFiles,
        _FailRename((path) => path == target.path, 0, allFiles: true));

    expect(source.existsSync(), isTrue);
    expect(target.existsSync(), isFalse);
    await paths.migrateStateFiles();
    expect(source.existsSync(), isFalse);
    expect(load('library_state.json')['customDbPaths'], {'offline': 'keep.db'});
  });

  test('logs takes precedence over stale legacy state on both sides', () async {
    save(drive, 'notices_seen.json', {
      'seen': {
        'online': ['current']
      }
    });
    save(
        drive,
        'notices_seen.json',
        {
          'seen': {
            'online': ['stale']
          }
        },
        legacy: true);
    save(machine, 'notices_seen.json', {
      'seen': {
        'offline': ['current']
      }
    });
    save(
        machine,
        'notices_seen.json',
        {
          'seen': {
            'offline': ['stale']
          }
        },
        legacy: true);

    await paths.seedStateFromMachine();

    expect(load('notices_seen.json')['seen'], {
      'online': ['current'],
      'offline': ['current']
    });
  });

  test(
      'a corrupt checkpoint fails closed, without resurrecting a removed record',
      () async {
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'old.db'}
    });
    await paths.seedStateFromMachine();
    save(drive, 'library_state.json', {'customDbPaths': <String, Object?>{}});
    final journal = Directory(p.join(drive, 'logs', 'migrations'))
        .listSync()
        .whereType<File>()
        .single;
    journal.writeAsStringSync('{');

    await expectLater(
        paths.seedStateFromMachine(),
        throwsA(isA<AppPathsException>()
            .having((e) => e.kind, 'kind', AppPathsFailure.stateMigration)));

    expect(load('library_state.json')['customDbPaths'], isEmpty);
    expect(journal.readAsStringSync(), '{');
  });

  for (final failAt in [1, 2]) {
    test(
        'atomic checkpoint failure $failAt is recoverable without losing state',
        () async {
      save(machine, 'library_state.json', {
        'customDbPaths': {'offline': 'local.db'}
      });
      final fault = _FailRename(
          (target) => p.dirname(target).endsWith('migrations'), failAt);
      await expectLater(
          IOOverrides.runWithIOOverrides(paths.seedStateFromMachine, fault),
          throwsA(isA<AppPathsException>()));
      expect(state(machine, 'library_state.json').existsSync(), isTrue);

      await paths.seedStateFromMachine();

      expect(
          load('library_state.json')['customDbPaths'], {'offline': 'local.db'});
      final before = state(drive, 'library_state.json').readAsBytesSync();
      await paths.seedStateFromMachine();
      expect(state(drive, 'library_state.json').readAsBytesSync(), before);
    });
  }

  test('recovery retains evidence of an independently changed target',
      () async {
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'A.db'}
    });
    await paths.seedStateFromMachine();
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'B.db'}
    });
    final fault = _FailRename(
        (target) => target == state(drive, 'library_state.json').path, 1);
    await expectLater(
        IOOverrides.runWithIOOverrides(paths.seedStateFromMachine, fault),
        throwsA(isA<AppPathsException>()));
    save(drive, 'library_state.json', {
      'customDbPaths': {'offline': 'C.db'}
    });
    save(machine, 'library_state.json', {
      'customDbPaths': {'offline': 'D.db'}
    });

    await paths.seedStateFromMachine();

    expect(load('library_state.json')['customDbPaths'], {'offline': 'C.db'});
  });

  testWidgets(
      'a migration failure has a visible stop screen and retry guidance',
      (tester) async {
    state(machine, 'library_state.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{');
    final error = await tester.runAsync(() async {
      try {
        await paths.seedStateFromMachine();
        fail('Expected migration to stop');
      } on AppPathsException catch (error) {
        return error;
      }
    });
    expect(error!.kind, AppPathsFailure.stateMigration);
    await pumpScreen(
        tester, SetupErrorScreen(error: error, showWindowButtons: false));
    expect(
        find.text(stringsOf().setupError.stateMigrationTitle), findsOneWidget);
    expect(find.text(error.message), findsOneWidget);
    expect(find.text(stringsOf().setupError.explanation), findsNothing);
  });
}

final class _FailRename extends IOOverrides {
  _FailRename(this.matches, this.failAt, {this.allFiles = false});
  final bool Function(String) matches;
  final int failAt;
  final bool allFiles;
  int count = 0;

  @override
  File createFile(String path) {
    final real = Zone.root.run(() => File(path));
    return allFiles || path.endsWith('.tmp')
        ? _RenameFile(real, (target) {
            if (matches(target) && (++count == failAt || failAt == 0)) {
              throw FileSystemException(
                  'Injected atomic rename failure', target);
            }
          })
        : real;
  }
}

class _RenameFile implements File {
  _RenameFile(this.real, this.beforeRename);
  final File real;
  final void Function(String) beforeRename;
  @override
  String get path => real.path;
  @override
  Directory get parent => real.parent;
  @override
  Future<Uint8List> readAsBytes() => real.readAsBytes();
  @override
  Future<File> copy(String newPath) => real.copy(newPath);
  @override
  Future<File> writeAsBytes(List<int> bytes,
          {FileMode mode = FileMode.write, bool flush = false}) =>
      real.writeAsBytes(bytes, mode: mode, flush: flush);
  @override
  Future<File> writeAsString(String contents,
          {FileMode mode = FileMode.write,
          Encoding encoding = utf8,
          bool flush = false}) =>
      real.writeAsString(contents,
          mode: mode, encoding: encoding, flush: flush);
  @override
  Future<File> rename(String newPath) {
    beforeRename(newPath);
    return real.rename(newPath);
  }

  @override
  Future<bool> exists() => real.exists();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      real.delete(recursive: recursive);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
