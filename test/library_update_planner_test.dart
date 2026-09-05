import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/models/delta_manifest.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/models/library_update_plan.dart';
import 'package:seforim_library_updater/src/services/library_update_planner.dart';
import 'package:test/test.dart';

/// בונה PatchEdge פיקטיבי מ-[from] ל-[to] בגודל דחוס [size].
PatchEdge _edge(
  int from,
  int to, {
  int size = 1000,
  int fromSchema = 1,
  int toSchema = 1,
}) {
  final file = 'patch-v$from-v$to.db.zst';
  return PatchEdge(
    manifest: DeltaManifest(
      fromVersion: from,
      toVersion: to,
      fromSchemaVersion: fromSchema,
      toSchemaVersion: toSchema,
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
    String? contentTag,
    String? localTag,
    int? localTagVersion,
    int? fullVersion,
    int? blockingSchema,
  }) =>
      planner.plan(
        localVersion: local,
        hasLocalVersionMeta: hasMeta,
        latestVersion: latest,
        edges: edges,
        latestFullDbAsset: full,
        fullDbReleaseTag: tag,
        latestFullDbVersion: fullVersion,
        // ברירת המחדל: ה-release החדש ביותר הוא גם נושא המסד המלא.
        latestContentTag: contentTag ?? tag,
        localReleaseTag: localTag,
        localReleaseTagVersion: localTagVersion ?? local,
        blockingSchemaVersion: blockingSchema,
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

    // ההתאוששות מ-issue #19: patch שנכשל על המסד המקומי משאיר את המשתמש
    // תקוע, אלא אם המסד המלא שבמראה נגיש מאותה תוכנית.
    test('תוכנית דלתא נושאת את ההורדה המלאה כמסלול חלופי', () {
      final p = plan(
        local: 1,
        latest: 3,
        edges: [_edge(1, 2), _edge(2, 3)],
        fullVersion: 3,
      );

      expect(p.kind, LibraryUpdatePlanKind.delta);
      final fallback = p.fullDownloadFallback!;
      expect(fallback.kind, LibraryUpdatePlanKind.fullDownload);
      expect(fallback.fullDbAsset, _fullAsset);
      expect(fallback.fullDbReleaseTag, 'v3');
      // היעד הוא מה שהנכס מביא, לא מה שה-release מכריז — אחרת האימות
      // שאחרי החילוץ דוחה את המסד.
      expect(fallback.targetVersion, 3);
      expect(fallback.fullDownloadFallback, isNull);
    });

    test('בלי מסד מלא במראה אין מסלול חלופי לתוכנית דלתא', () {
      final p = plan(local: 1, latest: 2, edges: [_edge(1, 2)], full: null);

      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.fullDownloadFallback, isNull);
    });

    test('היעד של המסלול החלופי הוא הגרסה שהנכס מביא', () {
      final p = plan(
        local: 1,
        latest: 5,
        edges: [_edge(1, 5)],
        fullVersion: 4, // ה-zst שבמראה מביא 4, לא 5
      );

      expect(p.targetVersion, 5);
      expect(p.fullDownloadFallback!.targetVersion, 4);
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
      // מה שמוצג למשתמש הוא סוף השרשרת: 3 כאן הבטיח את גרסת המסד המלא.
      expect(p.finalTargetVersion, 4);
    });

    test('בלי גרסת נכס מפורשת נשמרת ההתנהגות הקודמת — היעד הוא ה-latest', () {
      final p = plan(local: 1, latest: 3, edges: [_edge(1, 2)]);
      expect(p.targetVersion, 3);
      // בלי השלמה, שני המספרים זהים.
      expect(p.finalTargetVersion, 3);
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

    test('אין מסלול כלל ואין DB מלא → blocked', () {
      final p = plan(
        local: 1,
        latest: 3,
        edges: [_edge(2, 3)],
        full: null,
        tag: null,
      );
      expect(p.kind, LibraryUpdatePlanKind.blocked);
      expect(p.reason, isNotNull);
    });

    // מסלול שמגיע רק לחצי הדרך עדיין שווה יותר מכלום: המשתמש עולה לגרסה 2
    // בעשרות MB, ומקבל הסבר למה לא הגיע ל-3.
    test('מסלול חלקי בלי DB מלא → דלתא עד כמה שאפשר, עם הסבר', () {
      final p = plan(
        local: 1,
        latest: 3,
        edges: [_edge(1, 2)],
        full: null,
        tag: null,
      );
      expect(p.kind, LibraryUpdatePlanKind.delta);
      expect(p.finalTargetVersion, 2);
      expect(
        p.reason,
        AppL10n.strings.libraryDomain.planNoDeltaRoute(2, 3),
      );
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

    // הבאג שהופיע בשטח: המראה נושאת מסד מלא של v21 בעוד ה-release החדש הוא
    // v22 (patches בלבד). ההשוואה מול נושא המסד המלא הכריזה "עדכון" מגרסה 22
    // לגרסה 22 — ~1.4GB על מסד שכבר מעודכן.
    test('נושא המסד המלא ישן מה-release החדש → none, לא "עדכון" 22→22', () {
      final p = plan(
        local: 22,
        latest: 22,
        edges: [],
        tag: 'v21-carrier',
        contentTag: 'v22-latest',
        localTag: 'v22-latest',
      );
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    // רישום של גרסה אחרת (מסד שאוצריא עדכנה בעצמה, או מחשב אחר שכתב על
    // הכונן) אינו מעיד על התוכן שבמסד עכשיו.
    test('רישום שנעשה בגרסה אחרת אינו מפעיל הורדה מלאה', () {
      final p = plan(
        local: 22,
        latest: 22,
        edges: [],
        tag: 'v22-latest',
        localTag: 'v20-old',
        localTagVersion: 20,
      );
      expect(p.kind, LibraryUpdatePlanKind.none);
    });

    test('פרסום מחדש אמיתי באותה גרסה עדיין מזוהה', () {
      final p = plan(
        local: 22,
        latest: 22,
        edges: [],
        tag: 'v22-b',
        localTag: 'v22-a',
        localTagVersion: 22,
      );
      expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      expect(p.fullDbReleaseTag, 'v22-b');
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

    // ⚠️ הרגרסיה של v26: ה-patches ל-latest נפסלו בגלל סכמה שאיננו יודעים
    // להחיל, והמסד המלא שבמראה הוא של v21 — ישן מהמסד המקומי. המסלול הזה
    // החליף מסד v23 תקין במסד v21, ואז נכשל בהחלה והשאיר את המשתמש על 22.
    // התוכנית מקבלת edges **מסוננים** (ה-discovery כבר הסיר אותם), ולכן
    // הקשת שחוצה את הסכמה פשוט אינה כאן.
    // המראה האמיתית (ספטמבר 2026): קשתות עד v23 בסכמה 2, ו-v26 בסכמה 4
    // שסוננה. מסד v21/v22 יכול לטפס ל-23 בעשרות MB — וזה עדיף גם על
    // "חסום" וגם על הורדה מלאה של ~1.5GB שנוחתת על 21.
    group('שרשרת שנעצרת מתחת ל-latest', () {
      test('מטפסים לגרסה הגבוהה שאפשר, ולא נחסמים', () {
        final p = plan(
          local: 22,
          latest: 26,
          edges: [_edge(21, 23), _edge(22, 23)],
          fullVersion: 21,
          blockingSchema: 4,
        );

        expect(p.kind, LibraryUpdatePlanKind.delta);
        expect(p.finalTargetVersion, 23);
        expect(
          p.reason,
          AppL10n.strings.libraryDomain.planPartialDeltaSchemaStop(23, 26, 4),
        );
      });

      test('קובצי עדכון מנצחים מסד מלא שנוחת נמוך מהם', () {
        // 1.5GB שמגיעים ל-21 מול עשרות MB שמגיעים ל-23.
        final p = plan(
          local: 20,
          latest: 26,
          edges: [_edge(20, 22), _edge(22, 23)],
          fullVersion: 21,
          blockingSchema: 4,
        );

        expect(p.kind, LibraryUpdatePlanKind.delta);
        expect(p.finalTargetVersion, 23);
      });

      test('מסד מלא שמגיע גבוה יותר מנצח את השרשרת החלקית', () {
        final p = plan(
          local: 20,
          latest: 26,
          edges: [_edge(20, 22)],
          fullVersion: 26,
          blockingSchema: 4,
        );

        expect(p.kind, LibraryUpdatePlanKind.fullDownload);
        expect(p.finalTargetVersion, 26);
      });

      test('שרשרת שמגיעה ל-latest נשארת בלי הסבר', () {
        final p = plan(local: 22, latest: 23, edges: [_edge(22, 23)]);

        expect(p.kind, LibraryUpdatePlanKind.delta);
        expect(p.finalTargetVersion, 23);
        expect(p.reason, isNull);
      });
    });

    group('מסד מלא שאינו מקדם', () {
      test('מסד מלא ישן מהמקומי ובלי השלמה ל-latest → blocked, לא הורדה מלאה',
          () {
        final p = plan(
          local: 23,
          latest: 26,
          edges: [_edge(21, 22, fromSchema: 2, toSchema: 2)],
          fullVersion: 21,
        );
        expect(p.kind, LibraryUpdatePlanKind.blocked);
        // 21 ולא 22: ההשלמה חייבת להגיע ל-latest בדיוק, ואין לה מסלול.
        expect(
          p.reason,
          AppL10n.strings.libraryDomain.planFullDbWouldNotProgress(21, 23, 26),
        );
      });

      test('אותו גרף מגרסה מקומית נמוכה יותר → הורדה מלאה', () {
        final p = plan(
          local: 20,
          latest: 26,
          edges: [_edge(21, 22, fromSchema: 2, toSchema: 2)],
          fullVersion: 21,
        );
        expect(p.kind, LibraryUpdatePlanKind.fullDownload);
        expect(p.finalTargetVersion, 21);
      });

      // אין גרסה מקומית אמינה להגן עליה — וזה גם מסלול ההתקנה הטרייה.
      test('בלי meta מקומי ההגנה כבויה → הורדה מלאה', () {
        final p = plan(
          local: 23,
          latest: 26,
          edges: [_edge(21, 22, fromSchema: 2, toSchema: 2)],
          hasMeta: false,
          fullVersion: 21,
        );
        expect(p.kind, LibraryUpdatePlanKind.fullDownload);
      });
    });

    group('סכמה שאיננו יודעים להחיל — ההסבר למשתמש', () {
      test('הורדת המסד המלא היא המסלול המתוכנן, לא "אין מסלול דלתא"', () {
        final p = plan(
          local: 23,
          latest: 26,
          edges: [],
          fullVersion: 26,
          blockingSchema: 4,
        );
        final strings = AppL10n.strings.libraryDomain;
        expect(p.kind, LibraryUpdatePlanKind.fullDownload);
        expect(p.reason, strings.planNewSchemaNeedsFullDb(26, 4));
        expect(p.reason, isNot(strings.planNoDeltaRoute(23, 26)));
      });

      test('בלי סכמה חוסמת נשמר ההסבר הקודם', () {
        final p = plan(local: 23, latest: 26, edges: [], fullVersion: 26);
        expect(p.kind, LibraryUpdatePlanKind.fullDownload);
        expect(
          p.reason,
          AppL10n.strings.libraryDomain.planNoDeltaRoute(23, 26),
        );
      });

      test('סכמה חוסמת ובלי מסד מלא כלל → blocked', () {
        final p = plan(
          local: 23,
          latest: 26,
          edges: [],
          full: null,
          tag: null,
          blockingSchema: 4,
        );
        final strings = AppL10n.strings.libraryDomain;
        expect(p.kind, LibraryUpdatePlanKind.blocked);
        expect(
          p.reason,
          strings.planNoFullDbEither(strings.planPatchSchemaTooNew(4, 26)),
        );
      });
    });
  });
}
