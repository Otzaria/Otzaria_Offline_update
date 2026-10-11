import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/models/library_update_plan.dart';
import 'package:test/test.dart';

DeltaManifest manifest(
  int from,
  int to, {
  int size = 1000,
  int fromSchema = 2,
  int toSchema = 2,
  int? patchFormat,
}) =>
    DeltaManifest(
      fromVersion: from,
      toVersion: to,
      fromSchemaVersion: fromSchema,
      toSchemaVersion: toSchema,
      patchFormatVersion: patchFormat,
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

PatchEdge edge(
  int from,
  int to, {
  int size = 1000,
  int fromSchema = 2,
  int toSchema = 2,
  int? patchFormat,
}) =>
    PatchEdge(
      manifest: manifest(
        from,
        to,
        size: size,
        fromSchema: fromSchema,
        toSchema: toSchema,
        patchFormat: patchFormat,
      ),
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

    // מחסום מעבר סכמה אינו patch גם כשסכמתו ופורמטו מוכרים.
    test('fullRebase — אינו קביל', () {
      final base = edge(28, 32, fromSchema: 5, toSchema: 6, patchFormat: 4);
      final barrier = PatchEdge(
        manifest: DeltaManifest(
          fromVersion: 28,
          toVersion: 32,
          fromSchemaVersion: 5,
          toSchemaVersion: 6,
          patchFormatVersion: 4,
          fromContentHash: 'full-rebase',
          toContentHash: 'full-rebase',
          patchFiles: base.manifest.patchFiles,
          fullRebase: true,
        ),
        patchFileUrls: base.patchFileUrls,
        manifestUrl: base.manifestUrl,
      );
      expect(base.isApplicable, isTrue);
      expect(barrier.isApplicable, isFalse);
    });

    // ⚠️ הבאג בשטח: release שהצהיר `toSchemaVersion: 4` נכשל רק בתוך
    // `PatchApplier.apply` — אחרי שהמסד החי כבר הוחלף במסד ישן יותר.
    // הדגלים האלה הם מה שמוציא קשת כזו מהגרף עוד לפני התכנון.
    group('hasSupportedSchema', () {
      test('סכמות מוכרות (1→2) — נתמך', () {
        expect(
            edge(1, 2, fromSchema: 1, toSchema: 2).hasSupportedSchema, isTrue);
      });

      // המסלול שאותו הבאג חסם: v18 (סכמה 2) קופץ ל-v26 (סכמה 4) בקשת אחת.
      test('קפיצה 2→4 — נתמך מאז שנוספו סדרי סכמות 3–4', () {
        expect(edge(18, 26, fromSchema: 2, toSchema: 4).hasSupportedSchema,
            isTrue);
      });

      test('סכמת יעד שאין לה סדר hash (6→7) — לא נתמך', () {
        expect(edge(27, 28, fromSchema: 6, toSchema: 7).hasSupportedSchema,
            isFalse);
      });

      test('שני הקצות לא מוכרים (7→8) — לא נתמך', () {
        expect(edge(28, 29, fromSchema: 7, toSchema: 8).hasSupportedSchema,
            isFalse);
      });
    });

    // הציר השני: סכמת DB מוכרת, אבל פורמט ה-`patch.db` חדש מהנתמך. פסילה
    // כאן היא מה שמונע הורדת מאות MB שייפסלו רק ב-preflight.
    group('hasSupportedPatchFormat', () {
      test('מניפסט היסטורי בלי השדה — נחשב נתמך', () {
        final e = edge(1, 2, fromSchema: 1, toSchema: 2);
        expect(e.manifest.patchFormatVersion, isNull);
        expect(e.hasSupportedPatchFormat, isTrue);
        expect(e.isApplicable, isTrue);
      });

      test('פורמט 4 עם סכמה 5 — נתמך (שני צירים נפרדים)', () {
        final e = edge(26, 27, fromSchema: 4, toSchema: 5, patchFormat: 4);
        expect(e.isApplicable, isTrue);
      });

      test('פורמט 5 — נפסל אף שסכמת ה-DB מוכרת', () {
        final e = edge(26, 27, fromSchema: 4, toSchema: 5, patchFormat: 5);
        expect(e.hasSupportedSchema, isTrue);
        expect(e.hasSupportedPatchFormat, isFalse);
        expect(e.isApplicable, isFalse);
      });
    });

    // הציר השלישי: דחיסה שאיננו מכירים נפסלת בתכנון ולא בפענוח.
    test('דחיסה שאינה zstd — הקשת נפסלת', () {
      const entry = PatchFileEntry(
        file: 'patch-v1-v2.db.zst',
        compression: 'gzip',
        sha256: 'c',
        size: 1,
        uncompressedSha256: 'u',
        uncompressedSize: 2,
      );
      const e = PatchEdge(
        manifest: DeltaManifest(
          fromVersion: 1,
          toVersion: 2,
          fromSchemaVersion: 2,
          toSchemaVersion: 2,
          fromContentHash: 'a',
          toContentHash: 'b',
          patchFiles: [entry],
        ),
        patchFileUrls: {},
        manifestUrl: 'm',
      );
      expect(e.hasSupportedSchema, isTrue);
      expect(e.hasSupportedCompression, isFalse);
      expect(e.isApplicable, isFalse);
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
