import 'dart:convert';

import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

/// גרף הקשתות שפורסם בפועל ב-SeforimLibrary (v24–v26, ספטמבר 2026), עם
/// גרסאות הסכמה והפורמט האמיתיות שלו. זו הבדיקה שאומרת "עדכון בפועל עדיין
/// עובד": מסד קיים חייב להגיע ל-latest בקובצי עדכון, ולא ב-1.4GB.
String _m(int from, int to, int fromSchema, int toSchema, int format) =>
    jsonEncode({
      'fromVersion': from,
      'toVersion': to,
      'fromSchemaVersion': fromSchema,
      'toSchemaVersion': toSchema,
      'patchFormatVersion': format,
      'fromContentHash': 'h$from',
      'toContentHash': 'h$to',
      'patchFiles': [
        {
          'file': 'patch-v$from-v$to.db.zst',
          'compression': 'zstd',
          'sha256': 'c',
          'size': (to - from) * 20000000,
          'uncompressedSha256': 'u',
          'uncompressedSize': (to - from) * 120000000,
        }
      ],
    });

PatchEdge _edge(int from, int to, int fromSchema, int toSchema, int format) =>
    PatchEdge(
      manifest: DeltaManifest.fromJson(
          jsonDecode(_m(from, to, fromSchema, toSchema, format))
              as Map<String, dynamic>),
      patchFileUrls: {'patch-v$from-v$to.db.zst': 'https://x/p'},
      manifestUrl: 'https://x/m',
    );

void main() {
  // הקשתות בפועל: v24 (23→24), v25 (17→25, 21→25, 23→25, 24→25),
  // v26 (18→26, 22→26, 24→26, 25→26).
  final edges = [
    _edge(23, 24, 2, 3, 4),
    _edge(17, 25, 1, 4, 4),
    _edge(21, 25, 2, 4, 4),
    _edge(23, 25, 2, 4, 4),
    _edge(24, 25, 3, 4, 4),
    _edge(18, 26, 2, 4, 4),
    _edge(22, 26, 2, 4, 4),
    _edge(24, 26, 3, 4, 4),
    _edge(25, 26, 4, 4, 4),
  ];

  test('כל הקשתות האמיתיות קבילות עכשיו', () {
    for (final e in edges) {
      expect(e.isApplicable, isTrue, reason: '${e.fromVersion}→${e.toVersion}');
    }
  });

  test('מסד v23 מתוכנן לדלתא עד v26, בלי מסד מלא', () {
    const planner = LibraryUpdatePlanner();
    final plan = planner.plan(
      localVersion: 23,
      hasLocalVersionMeta: true,
      latestVersion: 26,
      edges: edges,
      latestFullDbAsset: const ReleaseAsset(
        name: 'seforim.db.zst',
        downloadUrl: 'https://x/full',
        size: 1400000000,
      ),
      fullDbReleaseTag: 'v21',
      latestFullDbVersion: 21,
      latestContentTag: 'v26',
    );
    expect(plan.kind, LibraryUpdatePlanKind.delta);
    expect(plan.finalTargetVersion, 26);
    expect(plan.deltaSteps, hasLength(2));
    expect(plan.deltaSteps.first.fromVersion, 23);
    expect(plan.deltaSteps.last.toVersion, 26);
    // רציפות סכמה לאורך השרשרת — כל צעד מתחיל בסכמה שהקודם סיים בה.
    for (var i = 1; i < plan.deltaSteps.length; i++) {
      expect(
        plan.deltaSteps[i].manifest.fromSchemaVersion,
        plan.deltaSteps[i - 1].manifest.toSchemaVersion,
      );
    }
    expect(plan.reason, isNull);
  });

  test('גם מסד v18 מגיע ל-26 בקשת אחת', () {
    const planner = LibraryUpdatePlanner();
    final plan = planner.plan(
      localVersion: 18,
      hasLocalVersionMeta: true,
      latestVersion: 26,
      edges: edges,
    );
    expect(plan.kind, LibraryUpdatePlanKind.delta);
    expect(plan.deltaSteps.single.toVersion, 26);
  });
}
