import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/models/library_update_plan.dart';
import 'package:test/test.dart';

DeltaManifest manifest(int from, int to, {int size = 1000}) => DeltaManifest(
      fromVersion: from,
      toVersion: to,
      fromSchemaVersion: 2,
      toSchemaVersion: 2,
      fromContentHash: 'h$from',
      toContentHash: 'h$to',
      patchFiles: [
        PatchFileEntry(
          file: 'patch-v$from-v$to.db.zst',
          compression: 'zstd',
          sha256: 'c',
          size: size,
          uncompressedSha256: 'u',
          uncompressedSize: size * 2,
        ),
      ],
    );

PatchEdge edge(int from, int to, {int size = 1000}) => PatchEdge(
      manifest: manifest(from, to, size: size),
      patchFileUrls: {'patch-v$from-v$to.db.zst': 'https://x/p'},
      manifestUrl: 'https://x/m.json',
    );

const _asset = ReleaseAsset(
  name: 'seforim.db.zst',
  downloadUrl: 'https://x/seforim.db.zst',
  size: 1197000000,
);

void main() {
  group('PatchEdge', () {
    test('גרסאות וגודל דחוס נגזרים מה-manifest', () {
      final e = edge(2, 3, size: 42);
      expect(e.fromVersion, 2);
      expect(e.toVersion, 3);
      expect(e.compressedSize, 42);
    });

    test('גודל דחוס הוא סכום כל קובצי ה-patch', () {
      const multi = PatchEdge(
        manifest: DeltaManifest(
          fromVersion: 1,
          toVersion: 2,
          fromSchemaVersion: 2,
          toSchemaVersion: 2,
          fromContentHash: 'a',
          toContentHash: 'b',
          patchFiles: [
            PatchFileEntry(
              file: 'a.zst',
              compression: 'zstd',
              sha256: 'x',
              size: 10,
              uncompressedSha256: 'y',
              uncompressedSize: 20,
            ),
            PatchFileEntry(
              file: 'b.zst',
              compression: 'zstd',
              sha256: 'x',
              size: 32,
              uncompressedSha256: 'y',
              uncompressedSize: 64,
            ),
          ],
        ),
        patchFileUrls: {},
        manifestUrl: 'm',
      );
      expect(multi.compressedSize, 42);
    });

    test('שוויון לפי ערך (props)', () {
      expect(edge(1, 2), edge(1, 2));
      expect(edge(1, 2), isNot(edge(1, 3)));
    });
  });

  group('LibraryUpdatePlan', () {
    test('none — targetVersion נופל לגרסה המקומית וגודל ההורדה 0', () {
      final plan = LibraryUpdatePlan.none(localVersion: 7);
      expect(plan.kind, LibraryUpdatePlanKind.none);
      expect(plan.targetVersion, 7);
      expect(plan.totalDownloadSize, 0);
      expect(plan.deltaSteps, isEmpty);
      expect(plan.fullDbAsset, isNull);
      expect(plan.reason, isNull);
    });

    test('none עם targetVersion מפורש שומר אותו', () {
      final plan = LibraryUpdatePlan.none(localVersion: 7, targetVersion: 9);
      expect(plan.targetVersion, 9);
    });

    test('delta — גודל ההורדה הוא סכום הקשתות', () {
      final plan = LibraryUpdatePlan.delta(
        localVersion: 1,
        targetVersion: 3,
        steps: [edge(1, 2, size: 100), edge(2, 3, size: 250)],
      );
      expect(plan.kind, LibraryUpdatePlanKind.delta);
      expect(plan.totalDownloadSize, 350);
      expect(plan.deltaSteps, hasLength(2));
    });

    // התוכנית מוחזרת לצרכן; שינוי בשוגג של הצעדים היה משנה תוכנית "מאושרת".
    test('deltaSteps אינם ניתנים לשינוי', () {
      final plan = LibraryUpdatePlan.delta(
        localVersion: 1,
        targetVersion: 2,
        steps: [edge(1, 2)],
      );
      expect(() => plan.deltaSteps.add(edge(2, 3)),
          throwsA(isA<UnsupportedError>()));
    });

    test('fullDownload — גודל ההורדה הוא גודל הנכס', () {
      final plan = LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 3,
        asset: _asset,
        releaseTag: 'v3',
        reason: 'why',
      );
      expect(plan.kind, LibraryUpdatePlanKind.fullDownload);
      expect(plan.totalDownloadSize, _asset.size);
      expect(plan.fullDbReleaseTag, 'v3');
      expect(plan.reason, 'why');
      expect(plan.deltaSteps, isEmpty);
    });

    test('blocked — גודל ההורדה 0 ויש reason', () {
      final plan = LibraryUpdatePlan.blocked(
        localVersion: 1,
        targetVersion: 3,
        reason: 'stuck',
      );
      expect(plan.kind, LibraryUpdatePlanKind.blocked);
      expect(plan.totalDownloadSize, 0);
      expect(plan.reason, 'stuck');
    });

    test('שוויון לפי ערך (props)', () {
      final a = LibraryUpdatePlan.none(localVersion: 3, targetVersion: 3);
      final b = LibraryUpdatePlan.none(localVersion: 3, targetVersion: 3);
      final c = LibraryUpdatePlan.none(localVersion: 3, targetVersion: 4);
      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
