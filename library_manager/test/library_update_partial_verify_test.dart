import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/db_fixtures.dart';
import 'support/zstd_fixtures.dart';

void main() {
  final bindings = nativeZstd();
  const hasher = LogicalContentHasher();
  final order = hashTableOrderForSchemaVersion(2);

  late Directory tempDir;
  late String dbPath;
  late LibraryUpdateApplier applier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('partial-verify-test-');
    dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    applier = LibraryUpdateApplier(processGuard: const _NoOtzaria());
  });

  tearDown(() async {
    applier.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  LogicalContentHashReport reportOf(String path) {
    final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      return hasher.computeReport(db, tableOrder: order, rowOrder: null);
    } finally {
      db.close();
    }
  }

  String state(String name, int version, List<List> rows) =>
      writeSchema2Db(p.join(tempDir.path, name), version: version, rows: rows);

  PatchEdge edge({
    required int from,
    required int to,
    required List<List> upsertRows,
    required LogicalContentHashReport before,
    required LogicalContentHashReport after,
    Map<String, String>? toTablesOverride,
  }) {
    final raw = buildSchema2PatchEdge(
      bindings!,
      tempDir.path,
      from: from,
      to: to,
      upsertRows: upsertRows,
      fromHash: before.wholeHash!,
      toHash: after.wholeHash!,
    );
    final m = raw.manifest;
    return PatchEdge(
      manifest: DeltaManifest(
        fromVersion: m.fromVersion,
        toVersion: m.toVersion,
        fromSchemaVersion: m.fromSchemaVersion,
        toSchemaVersion: m.toSchemaVersion,
        fromContentHash: m.fromContentHash,
        toContentHash: m.toContentHash,
        fromTableContentHashes: before.tableHashes,
        toTableContentHashes: toTablesOverride ?? after.tableHashes,
        patchFiles: m.patchFiles,
      ),
      patchFileUrls: raw.patchFileUrls,
      manifestUrl: raw.manifestUrl,
    );
  }

  LibraryUpdatePlan plan(List<PatchEdge> steps) => LibraryUpdatePlan.delta(
    localVersion: steps.first.manifest.fromVersion,
    targetVersion: steps.last.manifest.toVersion,
    steps: steps,
  );

  bool skipWithoutZstd() {
    if (bindings != null) return false;
    markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
    return true;
  }

  test('אימות חלקי: הטבלאות שלא השתנו אינן נקראות וזה נרשם בלוג', () async {
    if (skipWithoutZstd()) return;
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'aleph'],
      ],
    );
    final r1 = reportOf(
      state('s1.db', 1, [
        [1, 'aleph'],
      ]),
    );
    final r2 = reportOf(
      state('s2.db', 2, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
    );
    final log = <String>[];

    await applier.applyDelta(
      plan: plan([
        edge(
          from: 1,
          to: 2,
          upsertRows: [
            [2, 'bet'],
          ],
          before: r1,
          after: r2,
        ),
      ]),
      dbPath: dbPath,
      onLog: (m) {
        if (m.startsWith('final verification')) log.add(m);
      },
    );

    expect(log, hasLength(1));
    expect(log.single, contains('(partial)'));
    expect(log.single, contains('schema_meta='));
    expect(log.single, contains('source='));
    final skipped = order.where((t) => t != 'schema_meta' && t != 'source');
    for (final t in skipped) {
      expect(log.single, contains(t));
    }
    expect(log.single, contains('skipped ${skipped.length}'));
    expect(
      const OfflineLibraryDbRecoveryService().unverifiedVersion(dbPath),
      isNull,
    );
  });

  test('hash שגוי לטבלה שהשתנתה נדחה והמסד נשאר כשהיה', () async {
    if (skipWithoutZstd()) return;
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'aleph'],
      ],
    );
    final r1 = reportOf(
      state('s1.db', 1, [
        [1, 'aleph'],
      ]),
    );
    final r2 = reportOf(
      state('s2.db', 2, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
    );
    final bad = {...r2.tableHashes, 'source': 'f' * 64};

    await expectLater(
      applier.applyDelta(
        plan: plan([
          edge(
            from: 1,
            to: 2,
            upsertRows: [
              [2, 'bet'],
            ],
            before: r1,
            after: r2,
            toTablesOverride: bad,
          ),
        ]),
        dbPath: dbPath,
      ),
      throwsA(isA<PatchApplyException>()),
    );
    final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
    expect(db.select('SELECT COUNT(*) c FROM source').first['c'], 1);
    db.close();
  });

  test('טבלה ששונתה בצעד מוקדם מאומתת גם כשהצעד האחרון לא נגע בה', () async {
    if (skipWithoutZstd()) return;
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'aleph'],
      ],
    );
    final r1 = reportOf(
      state('s1.db', 1, [
        [1, 'aleph'],
      ]),
    );
    final r2 = reportOf(
      state('s2.db', 2, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
    );
    final r3 = reportOf(
      state('s3.db', 3, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
    );
    final log = <String>[];

    await applier.applyDelta(
      plan: plan([
        edge(
          from: 1,
          to: 2,
          upsertRows: [
            [2, 'bet'],
          ],
          before: r1,
          after: r2,
        ),
        edge(from: 2, to: 3, upsertRows: const [], before: r2, after: r3),
      ]),
      dbPath: dbPath,
      onLog: (m) {
        if (m.startsWith('final verification')) log.add(m);
      },
    );

    expect(log.single, contains('source='));
    expect(log.single, contains('schema_meta='));
  });

  group('chainVerifyManifest', () {
    const marker = 'changed-earlier-in-chain';
    const file = PatchFileEntry(
      file: 'p',
      compression: 'zstd',
      sha256: 'x',
      size: 1,
      uncompressedSha256: 'y',
      uncompressedSize: 1,
    );

    DeltaManifest step(
      Map<String, String> from,
      Map<String, String> to, {
      int fromSchema = 2,
      int toSchema = 2,
    }) => DeltaManifest(
      fromVersion: 1,
      toVersion: 2,
      fromSchemaVersion: fromSchema,
      toSchemaVersion: toSchema,
      fromContentHash: 'a',
      toContentHash: 'b',
      fromTableContentHashes: from,
      toTableContentHashes: to,
      patchFiles: const [file],
    );

    test('טבלה שנוספה בצעד מוקדם ולא שונתה אחריו מסומנת כשונה', () {
      final merged = LibraryUpdateApplier.chainVerifyManifest([
        step({'a': '1'}, {'a': '1', 'n': '5'}),
        step({'a': '1', 'n': '5'}, {'a': '1', 'n': '5'}),
      ])!;

      expect(merged.fromTableContentHashes!['n'], marker);
      expect(merged.fromTableContentHashes!['a'], '1');
    });

    test('טבלה שנמחקה בצעד מוקדם אינה מופיעה ואינה מפילה את המיזוג', () {
      final merged = LibraryUpdateApplier.chainVerifyManifest([
        step({'a': '1', 'd': '9'}, {'a': '2'}),
        step({'a': '2'}, {'a': '2'}),
      ])!;

      expect(merged.fromTableContentHashes!.keys, ['a']);
      expect(merged.fromTableContentHashes!['a'], marker);
    });

    test('טבלה שנמחקה ונוספה מחדש בשרשרת נשארת מחוץ למפת from', () {
      final merged = LibraryUpdateApplier.chainVerifyManifest([
        step({'a': '1', 't': '3'}, {'a': '1'}),
        step({'a': '1'}, {'a': '1', 't': '4'}),
      ])!;

      expect(merged.fromTableContentHashes!.containsKey('t'), isFalse);
      expect(merged.toTableContentHashes!['t'], '4');
    });

    test('צעד בלי מפת hash לטבלאות מחזיר null', () {
      const noMaps = DeltaManifest(
        fromVersion: 1,
        toVersion: 2,
        fromSchemaVersion: 2,
        toSchemaVersion: 2,
        fromContentHash: 'a',
        toContentHash: 'b',
        patchFiles: [file],
      );
      expect(
        LibraryUpdateApplier.chainVerifyManifest([
          noMaps,
          step({'a': '1'}, {'a': '1'}),
        ]),
        isNull,
      );
    });
  });

  test('אימות חלקי שומר בתים לכל טבלה ומשתמש בהם בהחלה הבאה', () async {
    if (skipWithoutZstd()) return;
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'aleph'],
      ],
    );
    final r1 = reportOf(
      state('s1.db', 1, [
        [1, 'aleph'],
      ]),
    );
    final r2 = reportOf(
      state('s2.db', 2, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
    );

    await applier.applyDelta(
      plan: plan([
        edge(
          from: 1,
          to: 2,
          upsertRows: [
            [2, 'bet'],
          ],
          before: r1,
          after: r2,
        ),
      ]),
      dbPath: dbPath,
    );

    final saved = File(
      p.join(
        const OfflineLibraryDbRecoveryService().patchTmpDirFor(dbPath),
        'verify_table_bytes.json',
      ),
    );
    expect(saved.existsSync(), isTrue);
    expect(jsonDecode(saved.readAsStringSync()), contains('source'));
    expect(
      File(
        p.join(p.dirname(saved.path), 'verify_total_bytes.txt'),
      ).existsSync(),
      isFalse,
    );
  });

  test('מניפסט בלי hash לפי טבלאות נופל לאימות מלא', () async {
    if (skipWithoutZstd()) return;
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'aleph'],
      ],
    );
    final r1 = reportOf(
      state('s1.db', 1, [
        [1, 'aleph'],
      ]),
    );
    final r2 = reportOf(
      state('s2.db', 2, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
    );
    final raw = buildSchema2PatchEdge(
      bindings!,
      tempDir.path,
      from: 1,
      to: 2,
      upsertRows: [
        [2, 'bet'],
      ],
      fromHash: r1.wholeHash!,
      toHash: r2.wholeHash!,
    );
    final log = <String>[];

    await applier.applyDelta(
      plan: plan([raw]),
      dbPath: dbPath,
      onLog: (m) {
        if (m.startsWith('final verification')) log.add(m);
      },
    );

    expect(log.single, contains('whole database'));
  });
}

class _NoOtzaria extends OtzariaProcessGuard {
  const _NoOtzaria();
  @override
  Future<bool> isAnyRunning(List<String> names) async => false;
}
