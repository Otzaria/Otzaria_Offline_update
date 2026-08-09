import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// המודל הוא הגשר בין ה-planner ל-UI: `updateAvailable` הוא מה שקובע אם
/// מוצג כפתור עדכון, ולכן כל אחד מארבעת סוגי התוכנית נבדק כאן במפורש.
void main() {
  const asset = ReleaseAsset(
    name: 'seforim.db.zst',
    downloadUrl: 'assets/v5/seforim.db.zst',
    size: 1024,
  );

  group('LibraryUpdateCheckResult', () {
    test('ברירות המחדל: אין תוכנית, אין עדכון, לא התקנה טרייה', () {
      const result = LibraryUpdateCheckResult(dbPath: r'C:\db\seforim.db');

      expect(result.plan, isNull);
      expect(result.localVersion, isNull);
      expect(result.latestReleaseTag, isNull);
      expect(result.isFreshInstall, isFalse);
      expect(result.updateAvailable, isFalse);
      expect(result.needsManualDbPath, isFalse);
    });

    test('תוכנית none = אין עדכון זמין', () {
      final result = LibraryUpdateCheckResult(
        dbPath: r'C:\db\seforim.db',
        plan: LibraryUpdatePlan.none(localVersion: 5, targetVersion: 5),
        latestReleaseTag: 'v5',
      );

      expect(result.updateAvailable, isFalse);
      expect(result.plan!.kind, LibraryUpdatePlanKind.none);
      expect(result.plan!.totalDownloadSize, 0);
    });

    test('תוכנית fullDownload = יש עדכון, וגודל ההורדה הוא גודל הנכס', () {
      final result = LibraryUpdateCheckResult(
        dbPath: r'C:\db\seforim.db',
        plan: LibraryUpdatePlan.fullDownload(
          localVersion: 4,
          targetVersion: 5,
          asset: asset,
          releaseTag: 'v5',
        ),
        latestReleaseTag: 'v5',
      );

      expect(result.updateAvailable, isTrue);
      expect(result.plan!.fullDbReleaseTag, 'v5');
      expect(result.plan!.totalDownloadSize, 1024);
    });

    test('תוכנית delta = יש עדכון', () {
      final result = LibraryUpdateCheckResult(
        dbPath: r'C:\db\seforim.db',
        plan: LibraryUpdatePlan.delta(
          localVersion: 4,
          targetVersion: 5,
          steps: [_edge(4, 5)],
        ),
      );

      expect(result.updateAvailable, isTrue);
      expect(result.plan!.deltaSteps, hasLength(1));
    });

    test('תוכנית blocked נחשבת "יש מה לעשות" — ה-UI חייב להציג את הסיבה', () {
      final result = LibraryUpdateCheckResult(
        dbPath: r'C:\db\seforim.db',
        plan: LibraryUpdatePlan.blocked(
          localVersion: 4,
          targetVersion: 9,
          reason: 'no route',
        ),
      );

      // blocked אינו none, ולכן updateAvailable=true — זה מה שמוביל את
      // LibraryManager.applyUpdate לזרוק LibraryApplyException עם הסיבה.
      expect(result.updateAvailable, isTrue);
      expect(result.plan!.reason, 'no route');
    });

    test('התקנה טרייה: יש נתיב יעד, ואין צורך בבחירה ידנית', () {
      final result = LibraryUpdateCheckResult(
        dbPath: r'C:\data\library\seforim.db',
        localVersion: const LocalDbVersion(
          dbVersion: 0,
          schemaVersion: null,
          hasVersionMeta: false,
        ),
        plan: LibraryUpdatePlan.fullDownload(
          localVersion: 0,
          targetVersion: 5,
          asset: asset,
          releaseTag: 'v5',
        ),
        isFreshInstall: true,
      );

      expect(result.isFreshInstall, isTrue);
      expect(result.needsManualDbPath, isFalse);
      expect(result.localVersion!.hasVersionMeta, isFalse);
    });

    test('needsManualDbPath רק כשאין נתיב בכלל (תאימות לאחור)', () {
      const result = LibraryUpdateCheckResult(dbPath: null);
      expect(result.needsManualDbPath, isTrue);
    });
  });
}

PatchEdge _edge(int from, int to) => PatchEdge(
      manifest: DeltaManifest(
        fromVersion: from,
        toVersion: to,
        fromSchemaVersion: 1,
        toSchemaVersion: 1,
        fromContentHash: 'a' * 64,
        toContentHash: 'b' * 64,
        patchFiles: [
          PatchFileEntry(
            file: 'patch-v4-v5.db.zst',
            compression: 'zstd',
            sha256: 'c' * 64,
            size: 512,
            uncompressedSha256: 'd' * 64,
            uncompressedSize: 2048,
          ),
        ],
      ),
      patchFileUrls: const {
        'patch-v4-v5.db.zst': 'assets/v5/patch-v4-v5.db.zst'
      },
      manifestUrl: 'assets/v5/patch-v4-v5.db.zst.manifest.json',
    );
