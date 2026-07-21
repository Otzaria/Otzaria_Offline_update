import 'package:test/test.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/models/library_update_plan.dart';
import 'package:seforim_library_updater/src/services/library_update_planner.dart';

/// בונה PatchEdge פיקטיבי מ-[from] ל-[to] בגודל דחוס [size].
PatchEdge _edge(int from, int to, {int size = 1000}) {
  final file = 'patch-v$from-v$to.db.zst';
  return PatchEdge(
    manifest: DeltaManifest(
      fromVersion: from,
      toVersion: to,
      fromSchemaVersion: 1,
      toSchemaVersion: 1,
      fromContentHash: 'hash$from',
      toContentHash: 'hash$to',
      patchFiles: [
        PatchFileEntry(
          file: file,
          compression: 'zstd',
          sha256: 'c$from$to',
          size: size,
          uncompressedSha256: 'u$from$to',
          uncompressedSize: size * 2,
        ),
      ],
    ),
    patchFileUrls: {file: 'https://x/$file'},
    manifestUrl: 'https://x/$file.manifest.json',
  );
}

const _fullAsset = ReleaseAsset(
  name: 'seforim.db.zst',
  downloadUrl: 'https://x/seforim.db.zst',
  size: 1197000000,
);

void main() {
  const planner = LibraryUpdatePlanner();

  LibraryUpdatePlan plan({
    required int local,
    required int latest,
    required List<PatchEdge> edges,
    bool hasMeta = true,
    ReleaseAsset? full = _fullAsset,
    String? tag = 'v3',
  }) =>
      planner.plan(
        localVersion: local,
        hasLocalVersionMeta: hasMeta,
        latestVersion: latest,
        edges: edges,
        latestFullDbAsset: full,
        latestReleaseTag: tag,
      );

  group('LibraryUpdatePlanner', () {
    test('local==latest → none', () {
      final p = plan(local: 3, latest: 3, edges: [_edge(1, 2), _edge(2, 3)]);
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    test('local>latest → none', () {
      final p = plan(local: 5, latest: 3, edges: []);
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    test('יש edge ישיר 1→3 → בוחר direct (step יחיד)', () {
      final p = plan(
        local: 1,
        latest: 3,
        edges: [_edge(1, 2), _edge(2, 3), _edge(1, 3)],
      );
      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.deltaSteps, hasLength(1));
      expect(p.deltaSteps.single.fromVersion, 1);
      expect(p.deltaSteps.single.toVersion, 3);
    });

    test('רק 1→2 ו-2→3 → בוחר chain בשני שלבים', () {
      final p = plan(local: 1, latest: 3, edges: [_edge(1, 2), _edge(2, 3)]);
      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.deltaSteps, hasLength(2));
      expect(p.deltaSteps[0].toVersion, 2);
      expect(p.deltaSteps[1].toVersion, 3);
    });

    test('חסר 2→3 (רק 1→2, latest=3) → full fallback', () {
      final p = plan(local: 1, latest: 3, edges: [_edge(1, 2)]);
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      expect(p.fullDbAsset, _fullAsset);
      expect(p.fullDbReleaseTag, 'v3');
    });

    test('שני chains באותו אורך → בוחר את הזול', () {
      // שני מסלולים באורך 2: 1→2→4 מול 1→3→4. ה-1→3→4 זול יותר.
      final p = plan(
        local: 1,
        latest: 4,
        edges: [
          _edge(1, 2, size: 5000),
          _edge(2, 4, size: 5000),
          _edge(1, 3, size: 1000),
          _edge(3, 4, size: 1000),
        ],
      );
      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.deltaSteps, hasLength(2));
      expect(p.deltaSteps[0].toVersion, 3); // המסלול הזול
      expect(p.totalDownloadSize, 2000);
    });

    test('מסלול ארוך זול מול ישיר יקר → מעדיף ישיר (פחות patches)', () {
      // 1→3 ישיר (יקר) מול 1→2→3 (זול) — מספר patches קובע ראשון.
      final p = plan(
        local: 1,
        latest: 3,
        edges: [
          _edge(1, 3, size: 9000),
          _edge(1, 2, size: 100),
          _edge(2, 3, size: 100),
        ],
      );
      expect(p.deltaSteps, hasLength(1));
      expect(p.deltaSteps.single.toVersion, 3);
    });

    test('חסר schema_meta.db_version → full fallback', () {
      final p = plan(
        local: 0,
        latest: 3,
        edges: [_edge(1, 2), _edge(2, 3)],
        hasMeta: false,
      );
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
    });

    test('אין מסלול ואין DB מלא → blocked', () {
      final p = plan(
        local: 1,
        latest: 3,
        edges: [_edge(1, 2)],
        full: null,
        tag: null,
      );
      expect(p.kind, LibraryUpdatePlanKind.blocked);
      expect(p.reason, isNotNull);
    });

    test('מתעלם מ-edges אחורה ולא משתמש בהם', () {
      final p = plan(
        local: 1,
        latest: 2,
        edges: [_edge(1, 2), _edge(3, 1), _edge(2, 1)],
      );
      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.deltaSteps, hasLength(1));
      expect(p.deltaSteps.single.toVersion, 2);
    });
  });
}
