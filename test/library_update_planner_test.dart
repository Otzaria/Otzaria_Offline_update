import 'package:otzaria_l10n/otzaria_l10n.dart';
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
    String? localTag,
    int? fullVersion,
  }) =>
      planner.plan(
        localVersion: local,
        hasLocalVersionMeta: hasMeta,
        latestVersion: latest,
        edges: edges,
        latestFullDbAsset: full,
        latestReleaseTag: tag,
        latestFullDbVersion: fullVersion,
        localReleaseTag: localTag,
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

    test('היעד של הורדה מלאה הוא הגרסה שהנכס מביא, לא ה-latest', () {
      // ה-release האחרון (4) הוא patch-only, וה-DB המלא האחרון הוא של 3.
      // בלי ההבחנה הזו האימות שאחרי החילוץ היה דוחה ~1.1GB שהורדו זה עתה.
      final p = plan(
        local: 1,
        latest: 4,
        edges: [_edge(2, 3), _edge(3, 4)],
        fullVersion: 3,
      );
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      expect(p.targetVersion, 3);
      expect(p.fullDbAsset, _fullAsset);
    });

    test('בלי גרסת נכס מפורשת נשמרת ההתנהגות הקודמת — היעד הוא ה-latest', () {
      final p = plan(local: 1, latest: 3, edges: [_edge(1, 2)]);
      expect(p.targetVersion, 3);
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

    // SeforimLibrary מפרסם לפעמים מסד מתוקן באותו db_version. בלי השוואת
    // ה-release tag העדכון הזה בלתי־נראה לגמרי.
    test('אותה גרסה אבל release אחר → הורדה מלאה', () {
      final p =
          plan(local: 3, latest: 3, edges: [], localTag: 'v3', tag: 'v3b');
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      expect(p.fullDbReleaseTag, 'v3b');
      expect(
        p.reason,
        AppL10n.strings.libraryDomain
            .planContentChangedWithoutVersionBump('v3b'),
      );
    });

    test('אותה גרסה ואותו release → none', () {
      final p = plan(local: 3, latest: 3, edges: [], localTag: 'v3', tag: 'v3');
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    // DB שלא הותקן דרך הלאנצ'ר — אין tag להשוות מולו, ואסור להציע בגללו
    // הורדה של ~1GB בכל פתיחה.
    test('אותה גרסה ו-tag מקומי לא ידוע → none', () {
      final p = plan(local: 3, latest: 3, edges: [], tag: 'v3b');
      expect(p.kind, LibraryUpdatePlanKind.none);
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

    test('מתעלם מ-edge עצמי (from==to) ולא נתקע', () {
      final p = plan(local: 1, latest: 2, edges: [_edge(1, 1), _edge(1, 2)]);
      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.deltaSteps, hasLength(1));
    });

    // ה-tag של ה-latest ידוע אבל אין נכס להוריד — אין מה להציע.
    test('אותה גרסה, tag שונה, אך אין DB מלא → none', () {
      final p = plan(
        local: 3,
        latest: 3,
        edges: [],
        full: null,
        tag: 'v3b',
        localTag: 'v3',
      );
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    test('אותה גרסה ו-tag של latest לא ידוע → none', () {
      final p = plan(local: 3, latest: 3, edges: [], tag: null, localTag: 'v3');
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    test('אין meta מקומי → הורדה מלאה גם כשקיים מסלול דלתא', () {
      final p = plan(
        local: 2,
        latest: 3,
        edges: [_edge(2, 3)],
        hasMeta: false,
      );
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      expect(p.reason, AppL10n.strings.libraryDomain.planLocalVersionUnknown);
    });

    test('אין meta מקומי ואין DB מלא → blocked עם שתי הסיבות', () {
      final p = plan(
        local: 0,
        latest: 3,
        edges: [],
        hasMeta: false,
        full: null,
        tag: null,
      );
      expect(p.kind, LibraryUpdatePlanKind.blocked);
      expect(
        p.reason,
        AppL10n.strings.libraryDomain.planNoFullDbEither(
            AppL10n.strings.libraryDomain.planLocalVersionUnknown),
      );
    });

    test('אין מסלול דלתא → סיבת ההורדה המלאה מגיעה מ-otzaria_l10n', () {
      final p = plan(local: 1, latest: 3, edges: []);
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      expect(p.reason, AppL10n.strings.libraryDomain.planNoDeltaRoute(1, 3));
    });

    test('גודל ההורדה של מסלול דלתא הוא סכום הקשתות שנבחרו', () {
      final p = plan(
        local: 1,
        latest: 3,
        edges: [_edge(1, 2, size: 111), _edge(2, 3, size: 222)],
      );
      expect(p.totalDownloadSize, 333);
    });

    test('הורדה מלאה מדווחת את גודל הנכס', () {
      final p = plan(local: 1, latest: 3, edges: []);
      expect(p.totalDownloadSize, _fullAsset.size);
    });
  });
}
