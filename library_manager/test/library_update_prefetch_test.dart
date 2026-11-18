import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/library_update_applier.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/db_fixtures.dart';
import 'support/zstd_fixtures.dart';

void main() {
  final bindings = nativeZstd();
  const hasher = LogicalContentHasher();
  const recovery = OfflineLibraryDbRecoveryService();

  late Directory tempDir;
  late String dbPath;
  late List<String> events;
  ({String h1, String h2, String h3})? cached;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prefetch-test-');
    dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    events = [];
    cached = null;
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String hashOf(String path) {
    final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      return hasher.compute(
        db,
        tableOrder: kHashTableOrderSchema2,
        rowOrder: null,
      );
    } finally {
      db.close();
    }
  }

  ({String h1, String h2, String h3}) buildChain() {
    String h(int v, List<List> rows) => hashOf(
      writeSchema2Db(p.join(tempDir.path, 'e$v.db'), version: v, rows: rows),
    );
    return (
      h1: h(1, [
        [1, 'aleph'],
      ]),
      h2: h(2, [
        [1, 'aleph'],
        [2, 'bet'],
      ]),
      h3: h(3, [
        [1, 'aleph'],
        [2, 'bet'],
        [3, 'gimel'],
      ]),
    );
  }

  ({String h1, String h2, String h3}) chainHashes() => cached ??= buildChain();

  LibraryUpdatePlan chainPlan() {
    final h = chainHashes();
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'aleph'],
      ],
    );
    PatchEdge edge(int from, int to, List<List> rows, String a, String b) =>
        buildSchema2PatchEdge(
          bindings!,
          tempDir.path,
          from: from,
          to: to,
          upsertRows: rows,
          fromHash: a,
          toHash: b,
        );
    return LibraryUpdatePlan.delta(
      localVersion: 1,
      targetVersion: 3,
      steps: [
        edge(
          1,
          2,
          [
            [2, 'bet'],
          ],
          h.h1,
          h.h2,
        ),
        edge(
          2,
          3,
          [
            [3, 'gimel'],
          ],
          h.h2,
          h.h3,
        ),
      ],
    );
  }

  ZstdFileStreamer recordingStreamer({
    Future<bool> Function(String source, bool Function()? isCancelled)? around,
  }) {
    return (
      String source,
      String dest, {
      void Function(int, int)? onProgress,
      void Function(int)? onOutputProgress,
      void Function(String)? onSourceDigest,
      void Function(String, int)? onOutputDigest,
      bool Function()? isCancelled,
      int? maxOutputBytes,
    }) async {
      final tag = RegExp(r'patch_(\d+_\d+)_').firstMatch(source)!.group(1)!;
      events.add('stream:$tag');
      if (around != null && tag == '2_3') {
        await around(source, isCancelled);
      }
      return ZstdFileDecompressor.decompressFileToFile(
        source,
        dest,
        onProgress: onProgress,
        onOutputProgress: onOutputProgress,
        onSourceDigest: onSourceDigest,
        onOutputDigest: onOutputDigest,
        isCancelled: isCancelled,
        maxOutputBytes: maxOutputBytes,
      );
    };
  }

  void recordProgress(LibraryApplyProgress e) {
    if (e.stage == LibraryApplyStage.applyingPatch && e.patchStage == null) {
      events.add('apply:${e.stepIndex}');
    }
  }

  bool skip() {
    if (bindings != null) return false;
    markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
    return true;
  }

  List<String> leftovers() {
    final dir = Directory(recovery.patchTmpDirFor(dbPath));
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync()) p.basename(f.path),
    ].where((n) => n.endsWith('.db') || n.endsWith('.extracting')).toList();
  }

  test('patch הבא מובא בזמן שהקודם מוחל, והשרשרת מגיעה ליעד', () async {
    if (skip()) return;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(),
      freeBytesFor: (_) => 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();

    await applier.applyDelta(
      plan: plan,
      dbPath: dbPath,
      onProgress: recordProgress,
      onStepApplied: (_, v) => events.add('applied:$v'),
    );

    final s2 = events.indexOf('stream:2_3');
    expect(s2, greaterThan(events.indexOf('apply:1')));
    expect(s2, lessThan(events.indexOf('apply:2')));
    expect(hashOf(dbPath), chainHashes().h3);
    expect(leftovers(), isEmpty);
  });

  test('כשל בהבאה מראש צף רק כשהצעד שלו מגיע', () async {
    if (skip()) return;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(
        around: (_, _) async => throw const PatchDownloadException('boom'),
      ),
      freeBytesFor: (_) => 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();

    await expectLater(
      applier.applyDelta(
        plan: plan,
        dbPath: dbPath,
        onProgress: recordProgress,
        onStepApplied: (_, v) => events.add('applied:$v'),
      ),
      throwsA(isA<PatchDownloadException>()),
    );

    expect(events, contains('applied:2'));
    expect(events, isNot(contains('apply:2')));
    expect(hashOf(dbPath), chainHashes().h2);
    expect(leftovers(), isEmpty);
  });

  test('כשל בצעד הנוכחי מבטל את ההבאה מראש וממתין לה', () async {
    if (skip()) return;
    var sawAbort = false;
    var exited = false;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(
        around: (_, isCancelled) async {
          while (!(isCancelled?.call() ?? false)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          sawAbort = true;
          exited = true;
          throw const ZstdCancelledException('abort');
        },
      ),
      freeBytesFor: (_) => 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();

    await expectLater(
      applier.applyDelta(
        plan: plan,
        dbPath: dbPath,
        onStepApplied: (_, v) => throw StateError('callback failed'),
      ),
      throwsStateError,
    );

    expect(sawAbort, isTrue);
    expect(exited, isTrue, reason: 'applyDelta ממתין שההבאה תיעצר');
    expect(leftovers(), isEmpty);
  });

  test('ביטול משתמש בזמן ההבאה מראש מדווח כביטול ומנקה', () async {
    if (skip()) return;
    var cancelled = false;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(
        around: (_, isCancelled) async {
          while (!(isCancelled?.call() ?? false)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          throw const ZstdCancelledException('cancelled');
        },
      ),
      freeBytesFor: (_) => 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();

    await expectLater(
      applier.applyDelta(
        plan: plan,
        dbPath: dbPath,
        isCancelled: () => cancelled,
        onStepApplied: (_, v) => cancelled = true,
      ),
      throwsA(isA<LibraryApplyCancelledException>()),
    );

    expect(hashOf(dbPath), chainHashes().h2);
    expect(leftovers(), isEmpty);
  });

  test(
    'onFinalStepStart נקרא פעם אחת, אחרי הצעד הראשון ולפני האחרון',
    () async {
      if (skip()) return;
      final applier = LibraryUpdateApplier(
        processGuard: const _NoOtzaria(),
        freeBytesFor: (_) => 1 << 40,
      );
      addTearDown(applier.dispose);
      final plan = chainPlan();

      await applier.applyDelta(
        plan: plan,
        dbPath: dbPath,
        onStepApplied: (_, v) => events.add('applied:$v'),
        onFinalStepStart: () async => events.add('final'),
      );

      expect(events, ['applied:2', 'final', 'applied:3']);
    },
  );

  test('onFinalStepStart אינו נקרא כשצעד מוקדם נכשל', () async {
    if (skip()) return;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      freeBytesFor: (_) => 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();

    await expectLater(
      applier.applyDelta(
        plan: plan,
        dbPath: dbPath,
        onStepApplied: (_, v) => throw StateError('stop'),
        onFinalStepStart: () async => events.add('final'),
      ),
      throwsStateError,
    );

    expect(events, isEmpty);
  });

  test('בלי מקום מוכח לשני patches ההבאה נעשית ברצף', () async {
    if (skip()) return;
    final logs = <String>[];
    late int maxUncompressed;
    late LibraryUpdateApplier applier;
    applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(),
      freeBytesFor: (_) =>
          DiskSpaceProbe.defaultHeadroomBytes +
          File(dbPath).lengthSync() +
          2 * maxUncompressed +
          1,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();
    maxUncompressed = plan.deltaSteps
        .map((s) => s.manifest.patchFiles.first.uncompressedSize)
        .reduce((a, b) => a > b ? a : b);

    await applier.applyDelta(
      plan: plan,
      dbPath: dbPath,
      onProgress: recordProgress,
      onStepApplied: (_, v) => events.add('applied:$v'),
      onLog: logs.add,
    );

    expect(
      events.indexOf('stream:2_3'),
      greaterThan(events.indexOf('applied:2')),
    );
    expect(logs.any((l) => l.contains('skipped')), isTrue);
    expect(hashOf(dbPath), chainHashes().h3);
    expect(leftovers(), isEmpty);
  });

  test('מקום שנעלם אחרי ההבאה מראש עוצר את הצעד, כמו בנתיב הרציף', () async {
    if (skip()) return;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(),
      freeBytesFor: (_) => events.contains('stream:2_3') ? 1 : 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();

    await expectLater(
      applier.applyDelta(
        plan: plan,
        dbPath: dbPath,
        onProgress: recordProgress,
      ),
      throwsA(isA<LibraryApplyException>()),
    );

    expect(events, isNot(contains('apply:2')));
    expect(hashOf(dbPath), chainHashes().h2);
    expect(leftovers(), isEmpty);
  });

  test('קובץ .extracting שנשאר מקריסה נמחק בתחילת ההחלה', () async {
    if (skip()) return;
    final applier = LibraryUpdateApplier(
      processGuard: const _NoOtzaria(),
      streamFile: recordingStreamer(),
      freeBytesFor: (_) => 1 << 40,
    );
    addTearDown(applier.dispose);
    final plan = chainPlan();
    final stale = File(
      p.join(recovery.patchTmpDirFor(dbPath), 'old-patch.db.extracting'),
    )..createSync(recursive: true);
    final keep = File(p.join(p.dirname(stale.path), 'verify_total_bytes.txt'))
      ..writeAsStringSync('5');

    await applier.applyDelta(plan: plan, dbPath: dbPath);

    expect(stale.existsSync(), isFalse);
    expect(keep.existsSync(), isTrue);
    expect(leftovers(), isEmpty);
  });
}

class _NoOtzaria extends OtzariaProcessGuard {
  const _NoOtzaria();
  @override
  Future<bool> isAnyRunning(List<String> names) async => false;
}
