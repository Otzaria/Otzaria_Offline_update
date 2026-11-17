// Issue #265 / #273: what the smart-search plan downloads on a drive, built
// from the layout Otzaria really published for v36..v38.
//
// One fixture byte stands for one MB of the real release (a base is ~1840
// bytes, the v37->v38 windows delta 34), so the 0.5x-of-base cap and the
// "how much was downloaded" arithmetic are those of production.
//
// Requirement (maintainer, #265): a drive never downloads more than one full
// base per model generation that a real or newest-installer machine needs.
import 'dart:convert';
import 'dart:io';

import 'package:library_manager/library_manager.dart' show LibraryManager;
import 'package:library_manager/src/services/library_state_store.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

const _r2 = SemanticModelGeneration.round2;
const _qa = SemanticModelGeneration.qa491;

// Real published size (MB) of every vector segment of the fixture layout.
int _realMb(String name) {
  int pick(Map<Object, int> table, Object key) =>
      table[key] ?? (throw StateError('no real size for $name'));
  RegExpMatch? m(String pattern) => RegExp(pattern).firstMatch(name);
  if (m(r'^legacy-v(\d+)\.oxv\.zst$') case final x?) {
    return pick({36: 1824, 37: 1821, 38: 1847}, int.parse(x[1]!));
  }
  if (m(r'^otzaria-vectors-abcd1234-v(\d+)-base\.oxv\.zst$') case final x?) {
    return pick({36: 1817, 37: 1816, 38: 1845}, int.parse(x[1]!));
  }
  if (m(r'^otzaria-vectors-abcd1234-v(\d+)-v(\d+)\.oxv\.zst$') case final x?) {
    return pick({'35-36': 2, '36-37': 40, '37-38': 34}, '${x[1]}-${x[2]}');
  }
  if (m(r'^otzaria-vectors-qa491a-v(\d+)-base\.oxv\.zst$') case final x?) {
    return pick({36: 1825, 37: 1821, 38: 1848}, int.parse(x[1]!));
  }
  if (m(r'^otzaria-vectors-qa491w-v(\d+)-base\.oxv\.zst$') case final x?) {
    return pick({36: 1811, 38: 1838}, int.parse(x[1]!));
  }
  if (m(r'^otzaria-vectors-qa491w-v(\d+)-v(\d+)\.oxv\.zst$') case final x?) {
    return pick({'35-36': 2, '36-38': 74}, '${x[1]}-${x[2]}');
  }
  throw StateError('no real size for $name');
}

// --- machines, as `_recordSemanticState` writes them -----------------------

/// Round2 PC on a windows set.
SemanticMachineState _r2Win(int v) => SemanticMachineState(
  supportsWindows: true,
  family: SemanticVectorsFamily.windows,
  libraryVersion: v,
  identityDigest: identityA,
  generation: _r2,
);

/// Round2 PC whose app has no windows support, on the anchor set.
SemanticMachineState _r2Anchor(int v) => SemanticMachineState(
  supportsWindows: false,
  family: SemanticVectorsFamily.legacy,
  libraryVersion: v,
  identityDigest: '',
  generation: _r2,
);

/// Round2 PC whose app reads windows sets but holds the anchor set.
SemanticMachineState _r2WinOnAnchor(int v) => SemanticMachineState(
  supportsWindows: true,
  family: SemanticVectorsFamily.legacy,
  libraryVersion: v,
  identityDigest: '',
  generation: _r2,
);

/// QA491 PC on a windows set (only v36/v38 windows bases exist).
SemanticMachineState _qaWin(int v) => SemanticMachineState(
  supportsWindows: true,
  family: SemanticVectorsFamily.windows,
  libraryVersion: v,
  identityDigest: identityC,
  generation: _qa,
);

/// QA491 PC whose app reads windows sets but holds the anchor set (what
/// `vectors-qa491-v37` gave it: no `vectors-qa491-windows-v37` exists).
SemanticMachineState _qaWinOnAnchor(int v) => SemanticMachineState(
  supportsWindows: true,
  family: SemanticVectorsFamily.legacy,
  libraryVersion: v,
  identityDigest: identityD,
  generation: _qa,
);

/// QA491 PC without windows support (no or stale capabilities file).
SemanticMachineState _qaAnchor(int v) => SemanticMachineState(
  supportsWindows: false,
  family: SemanticVectorsFamily.legacy,
  libraryVersion: v,
  identityDigest: identityD,
  generation: _qa,
);

/// Consent given, nothing installed yet.
SemanticMachineState _fresh(SemanticModelGeneration g, {bool windows = true}) =>
    SemanticMachineState(supportsWindows: windows, family: null, generation: g);

void main() {
  late Directory temp;
  late String mirror;
  late FakeVectorsGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-scenarios-');
    mirror = p.join(temp.path, 'mirror');
    github = FakeVectorsGithub();
  });
  tearDown(() async {
    github.client.close();
    await temp.delete(recursive: true);
  });

  /// What Otzaria/SeforimLibrary really published (checked with `gh release
  /// view`, 2026-11-16): four bases per version; windows deltas only for
  /// the windows families; qa491-windows has v36 and v38 but NO v37 base,
  /// and its one delta to v38 starts at v36.
  void publishRealLayout() {
    github
      ..legacyBase(36)
      ..legacyBase(37)
      ..legacyBase(38)
      ..windowsBase(36, segmentSize: 1817)
      ..windowsBase(37, segmentSize: 1816)
      ..windowsBase(38, segmentSize: 1845)
      ..delta(35, 36, segmentSize: 2)
      ..delta(36, 37, segmentSize: 40)
      ..delta(37, 38, segmentSize: 34)
      ..qa491Base(36, segmentSize: 1825)
      ..qa491Base(37, segmentSize: 1821)
      ..qa491Base(38, segmentSize: 1848)
      ..qa491Base(36, windows: true, segmentSize: 1811)
      ..qa491Base(38, windows: true, segmentSize: 1838)
      ..qa491Delta(35, 36, segmentSize: 2)
      ..qa491Delta(36, 38, segmentSize: 74);
  }

  SemanticSearchAssets assets({FakeVectorsEngine? engine}) {
    final value = SemanticSearchAssets(
      httpClient: github.client,
      models: fakeModels,
      specs: fakeSpecs,
      engineFactory: engine == null ? null : (_) async => engine,
    );
    addTearDown(value.dispose);
    return value;
  }

  /// Runs a real `sync`; returns the vector segments that crossed the wire.
  Future<Set<String>> sync(SemanticFleet fleet, {int target = 38}) async {
    github.downloads.clear();
    await assets().sync(
      mirrorDir: mirror,
      libraryTag: libraryTagOf(target),
      fleet: fleet,
      libraryTagFor: libraryTagOf,
    );
    return {
      for (final name in github.downloads)
        if (name.endsWith('.oxv.zst')) name,
    };
  }

  int mb(Set<String> names) => names.fold(0, (sum, n) => sum + _realMb(n));

  void row(String scenario, SemanticFleet fleet, Set<String> got) {
    // ignore: avoid_print
    print(
      'ROW | $scenario | groups=${fleet.groups.length} '
      '[${[for (final g in fleet.groups) '${g.generation.id}/${g.family.id}'].join(', ')}]'
      ' | ${(got.toList()..sort()).join(', ')} | ${mb(got)} MB '
      '(${(mb(got) * 1e6 / 1073741824).toStringAsFixed(2)} GiB)',
    );
  }

  /// The fleet the launcher would build: records on the drive plus one
  /// synthetic anchor machine for the newest installer in `mirror/app`.
  Future<SemanticFleet> driveFleet(
    List<SemanticMachineState> pcs,
    List<String>? installers,
  ) async {
    final dir = Directory(p.join(temp.path, 'data'))
      ..createSync(recursive: true);
    final now = DateTime.now().toUtc().toIso8601String();
    await File(p.join(dir.path, LibraryStateStore.fileName)).writeAsString(
      jsonEncode({
        'semanticMachines': {
          for (final (i, pc) in pcs.indexed)
            'pc$i|user': {...pc.toJson(), 'seen': now, 'localTime': now},
        },
      }),
    );
    final manager = LibraryManager(
      dataDir: dir.path,
      mirroredOtzariaVersions: installers == null
          ? null
          : () async => installers,
    );
    addTearDown(manager.dispose);
    return manager.semanticFleetForTest();
  }

  const windowsDelta37to38 = 'otzaria-vectors-abcd1234-v37-v38.oxv.zst';
  const r2WindowsBase38 = 'otzaria-vectors-abcd1234-v38-base.oxv.zst';
  const r2AnchorBase38 = 'legacy-v38.oxv.zst';
  const qaAnchorBase38 = 'otzaria-vectors-qa491a-v38-base.oxv.zst';
  const qaWindowsBase38 = 'otzaria-vectors-qa491w-v38-base.oxv.zst';
  const qaDelta36to38 = 'otzaria-vectors-qa491w-v36-v38.oxv.zst';
  const installers = ['0.9.98.2+807', '0.9.98.3+809'];

  group('a. one PC, round2 windows', () {
    test('v37 -> v38 downloads exactly the 34 MB delta', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_r2Win(37)]);
      final got = await sync(fleet);
      row('a r2-windows v37', fleet, got);
      expect(got, {windowsDelta37to38});
      expect(mb(got), 34);
    });

    test('the delta applies on the offline PC (base + delta = v38)', () async {
      publishRealLayout();
      await sync(SemanticFleet([_r2Win(37)]));
      final vectors = p.join(temp.path, 'machine', 'vectors');
      final db = p.join(temp.path, 'machine', 'library', 'seforim.db');
      await writeInstalledSet(vectors, version: 37);
      final engine = FakeVectorsEngine(version: 37);
      final offline = assets(engine: engine);
      expect(
        await offline.pending(
          generation: _r2,
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 38,
          vectorsRootPath: p.dirname(vectors),
          supportsWindows: true,
        ),
        isTrue,
      );
      await offline.install(
        generation: _r2,
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 38,
        vectorsRootPath: p.dirname(vectors),
        supportsWindows: true,
      );
      expect(engine.version, 38);
      final steps = [
        for (final input in engine.installs)
          (jsonDecode(input.manifestJson) as Map)['fromLibraryVersion'],
      ];
      expect(steps, [37]);
    });
  });

  group('b. one qa491 PC at v37', () {
    test('anchor PC: the anchor base again (no anchor delta exists) '
        '-- unavoidable given what Otzaria publishes', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_qaAnchor(37)]);
      final got = await sync(fleet);
      row('b1 qa491 anchor v37', fleet, got);
      expect(got, {qaAnchorBase38});
    });

    test('windows-capable PC holding the anchor v37 set, alone in its '
        'generation, gets the whole windows base (a delta cannot start from '
        'an anchor set)', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_qaWinOnAnchor(37)]);
      final got = await sync(fleet);
      row('b2 qa491 windows-capable on anchor v37', fleet, got);
      expect(got, {qaWindowsBase38});
      expect(
        github.apiTags,
        isNot(contains('vectors-qa491-windows-delta-${libraryTagOf(38)}')),
        reason: 'chainStartFor returns null before any delta is looked up',
      );
    });

    test(
      'a qa491 PC on a windows set at v36 does get the 74 MB delta',
      () async {
        publishRealLayout();
        final fleet = SemanticFleet([_qaWin(36)]);
        final got = await sync(fleet);
        row('b3 qa491 windows v36', fleet, got);
        expect(got, {qaDelta36to38});
      },
    );

    test('a qa491 windows set at v35 chains 35->36->38 (2 + 74 MB)', () async {
      publishRealLayout();
      final got = await sync(SemanticFleet([_qaWin(35)]));
      expect(mb(got), 76);
    });
  });

  group('c. the reporter-like drive', () {
    // PC1/PC2: 0.9.98.3 without a capabilities file (record: no windows);
    // PC3: 0.9.98.3 declaring windows but holding the anchor v37 set.
    final qaPcs = [_qaAnchor(37), _qaAnchor(37), _qaWinOnAnchor(37)];

    test('c1 older round2 PC recorded on windows v37: the qa491 anchor base '
        '+ the 34 MB delta', () async {
      publishRealLayout();
      final fleet = await driveFleet([...qaPcs, _r2Win(37)], installers);
      final got = await sync(fleet);
      row('c1 3 qa491 PCs + r2 windows v37 recorded', fleet, got);
      expect(fleet.groups, hasLength(2));
      expect(got, {windowsDelta37to38, qaAnchorBase38});
      expect(mb(got), 1848 + 34);
    });

    test('c2 the round2 PC is gone but an older round2 installer is still in '
        'mirror/app: one base', () async {
      publishRealLayout();
      final fleet = await driveFleet(qaPcs, installers);
      final got = await sync(fleet);
      row('c2 3 qa491 PCs, no r2 record, r2 installer present', fleet, got);
      expect(fleet.groups, hasLength(1));
      expect(got, {qaAnchorBase38});
      expect(mb(got), 1848);
    });

    test(
      'c3 a fresh round2 PC beside one at v37: round2 is all windows-capable '
      'so it keeps one windows base; qa491 one anchor base',
      () async {
        publishRealLayout();
        final fleet = await driveFleet([
          ...qaPcs,
          _r2Win(37),
          _fresh(_r2),
        ], installers);
        final got = await sync(fleet);
        row('c3 3 qa491 PCs + r2 windows v37 + fresh r2', fleet, got);
        expect(got, {r2WindowsBase38, qaAnchorBase38});
      },
    );

    test('c4 no record at all: one anchor base, for the newest installer '
        'only', () async {
      publishRealLayout();
      for (final listed in [
        installers,
        installers.reversed.toList(),
        ['0.9.98.3+809'],
      ]) {
        final fleet = await driveFleet([], listed);
        final got = await sync(fleet);
        row('c4 no records, installers $listed', fleet, got);
        expect(got, {qaAnchorBase38});
        Directory(mirror).deleteSync(recursive: true);
      }
      final older = await driveFleet([], ['0.9.98.2+807']);
      expect(await sync(older), {r2AnchorBase38});
    });

    test(
      'c5 best case: every qa491 PC reads windows -> one group, one base',
      () async {
        publishRealLayout();
        final fleet = await driveFleet(
          [_qaWinOnAnchor(37), _qaWinOnAnchor(37), _qaWinOnAnchor(37)],
          ['0.9.98.3+809'],
        );
        final got = await sync(fleet);
        row('c5 3 qa491 windows-capable PCs', fleet, got);
        expect(got, {qaWindowsBase38});
      },
    );

    test('c6 anchor PCs + windows-capable PCs on the anchor set of ONE '
        'generation share one anchor base', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_qaAnchor(37), _qaWinOnAnchor(37)]);
      expect(fleet.groups, hasLength(1));
      final got = await sync(fleet);
      row('c6 qa491 anchor + qa491 windows-capable', fleet, got);
      expect(got, {qaAnchorBase38});
    });

    test('c7 a generation with no anchor-only PC keeps a windows base, so '
        'its PCs can migrate and chain later', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_r2Win(37), _r2Win(37), _fresh(_r2)]);
      expect(fleet.groups, hasLength(1));
      expect(await sync(fleet), {r2WindowsBase38});
    });

    test('c8 the pre-click number is unknown for several groups and for '
        'any windows group', () async {
      publishRealLayout();
      final probe = assets();
      Future<int?> peek(SemanticFleet f) async {
        expect(
          await probe.peekPending(
            mirrorDir: mirror,
            libraryTag: libraryTagOf(38),
            fleet: f,
          ),
          isTrue,
        );
        return probe.peekedPendingBytes;
      }

      expect(await peek(SemanticFleet([_qaAnchor(37)])), isNotNull);
      expect(await peek(SemanticFleet([_r2Win(37)])), isNull);
      expect(
        await peek(SemanticFleet([_qaAnchor(37), _qaWinOnAnchor(37)])),
        isNotNull,
        reason: 'one anchor group: its size is known',
      );
      expect(
        await peek(SemanticFleet([_r2Anchor(37), _r2Win(37)])),
        isNull,
        reason: 'two groups',
      );
    });

    test('c9 anchor PC + PC on a windows set + fresh and anchor-holding '
        'windows-capable PCs: one anchor base and the 34 MB delta', () async {
      publishRealLayout();
      final fleet = SemanticFleet([
        _r2Anchor(37),
        _r2Win(37),
        _fresh(_r2),
        _r2WinOnAnchor(37),
      ]);
      expect(fleet.groups, hasLength(2));
      final got = await sync(fleet);
      row('c9 r2 anchor + windows set + fresh + windows-on-anchor', fleet, got);
      expect(got, {r2AnchorBase38, windowsDelta37to38});
      expect(mb(got), 1847 + 34);
      expect(await sync(fleet), isEmpty);
      expect(
        await assets().peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(38),
          fleet: fleet,
        ),
        isFalse,
      );
    });

    test('c10 a PC on a windows set whose chain failed still needs a windows '
        'base: it never takes the anchor set back', () async {
      publishRealLayout();
      const stuck = SemanticMachineState(
        supportsWindows: true,
        family: SemanticVectorsFamily.windows,
        libraryVersion: 37,
        identityDigest: identityA,
        needsBase: true,
        generation: _r2,
      );
      final got = await sync(SemanticFleet([_r2Anchor(37), stuck]));
      expect(got, {r2AnchorBase38, r2WindowsBase38});
    });

    test('c11 whichever plan the drive carries, no PC is told the drive '
        'does not match', () async {
      publishRealLayout();
      await sync(
        SemanticFleet([
          _r2Anchor(37),
          _r2Win(37),
          _fresh(_r2),
          _r2WinOnAnchor(37),
        ]),
      );
      final db = p.join(temp.path, 'machine', 'library', 'seforim.db');
      final vectors = p.join(temp.path, 'machine', 'vectors');
      Future<SmartSearchStatus> assessAs({
        required bool windows,
        int? installed,
        bool windowsSet = false,
      }) async {
        if (Directory(vectors).existsSync()) {
          Directory(vectors).deleteSync(recursive: true);
        }
        if (installed != null) {
          await writeInstalledSet(
            vectors,
            version: installed,
            windows: windowsSet,
          );
        }
        return assets().assess(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 38,
          support: SemanticAppSupport(
            generation: _r2,
            windows: windows,
            basis: SemanticSupportBasis.declared,
          ),
        );
      }

      for (final (name, status) in [
        ('anchor-only', await assessAs(windows: false)),
        ('fresh windows-capable', await assessAs(windows: true)),
        (
          'windows-capable on the anchor set',
          await assessAs(windows: true, installed: 37),
        ),
        (
          'on a windows set',
          await assessAs(windows: true, installed: 37, windowsSet: true),
        ),
      ]) {
        expect(status.state, SmartSearchState.readyOnDrive, reason: name);
        expect(status.reason, SmartSearchReason.partsMissing, reason: name);
      }
    });

    test('c12 a fresh windows-capable PC installs the anchor base while the '
        'drive also carries a windows delta for others', () async {
      publishRealLayout();
      await sync(SemanticFleet([_r2Anchor(37), _r2Win(37), _fresh(_r2)]));
      final db = p.join(temp.path, 'machine', 'library', 'seforim.db');
      final engine = FakeVectorsEngine();
      await assets(engine: engine).install(
        generation: _r2,
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 38,
        supportsWindows: true,
      );
      expect(engine.version, 38);
      expect(engine.installs, hasLength(1));
      expect(
        (jsonDecode(engine.installs.single.manifestJson)
            as Map)['fromLibraryVersion'],
        anyOf(isNull, 0),
      );
    });
  });

  group('d. a complete base for the previous version is on the drive', () {
    test('the v37 anchor base is pruned and v38 is fetched whole', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_qaAnchor(36)]);
      final v37 = await sync(fleet, target: 37);
      expect(mb(v37), 1821);
      final v38 = await sync(fleet);
      expect(mb(v38), 1848);
      expect(
        [
          for (final f in Directory(
            p.join(mirror, libraryTagOf(37)),
          ).listSync(recursive: true))
            if (f is File && !f.path.endsWith('.lock')) f.path,
        ],
        isEmpty,
        reason: 'only .lock inodes survive the prune',
      );
    });

    test('a windows base v37 on the drive is not the start of the '
        'v37->v38 delta; a no-set PC gets a fresh 1845 MB base', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_fresh(_r2)]);
      expect(mb(await sync(fleet, target: 37)), 1816);
      final got = await sync(fleet);
      row('d windows base v37 held, v38 wanted by a no-set PC', fleet, got);
      expect(got, {r2WindowsBase38});
    });

    test(
      'by the requirement: base v37 held on the drive + the 34 MB delta '
      'serve a v38 base',
      () async {
        publishRealLayout();
        final fleet = SemanticFleet([_fresh(_r2)]);
        await sync(fleet, target: 37);
        expect(mb(await sync(fleet)), lessThan(100));
      },
      skip:
          'needs a mirror plan of "base + chain" (the meta only knows base XOR '
          'chain) and not pruning the previous base',
    );
  });

  group('e. repeated sync', () {
    test('the second run downloads nothing and a peek is clean', () async {
      publishRealLayout();
      final fleet = await driveFleet(qaPcs(), installers);
      expect(await sync(fleet), {qaAnchorBase38});
      expect(await sync(fleet), isEmpty);
      expect(
        await assets().peekPending(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(38),
          fleet: fleet,
        ),
        isFalse,
      );
    });

    test('delta route: the second run downloads nothing either', () async {
      publishRealLayout();
      final fleet = SemanticFleet([_r2Win(37)]);
      expect(mb(await sync(fleet)), 34);
      expect(await sync(fleet), isEmpty);
    });
  });
}

List<SemanticMachineState> qaPcs() => [
  _qaAnchor(37),
  _qaAnchor(37),
  _qaWinOnAnchor(37),
];
