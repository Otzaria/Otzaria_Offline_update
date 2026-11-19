import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'support/db_fixtures.dart';
import 'support/zstd_fixtures.dart';

/// The DB's last step and the companion install run together, and neither
/// failure leaks into the other.
void main() {
  final bindings = nativeZstd();

  late Directory tempDir;
  late String dataDir;
  late String dbPath;
  late String lexical;
  late _FakeDeltaApplier applier;
  late _Guard guard;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('companion-overlap-');
    dataDir = p.join(tempDir.path, 'OtzariaData');
    dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    lexical = p.join(p.dirname(dbPath), 'lexical.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    File(dbPath).writeAsBytesSync(buildVersionOnlyDb(tempDir.path, 4));
    final store = LibraryStateStore(p.join(dataDir, 'library_state.json'));
    await store.saveCustomDbPath(dbPath);
    await store.saveAppliedRelease(tag: 'v4', dbVersion: 4);

    final mirror = Directory(p.join(dataDir, 'mirror', 'companions'))
      ..createSync(recursive: true);
    File(p.join(mirror.path, 'lexical.db')).writeAsStringSync('LEXICAL');
    File(
      p.join(mirror.path, CompanionMirrorManifest.fileName),
    ).writeAsStringSync(
      jsonEncode({
        'formatVersion': 1,
        'exportedAt': '2026-08-09T00:00:00.000Z',
        'dictionary': {
          'fileName': 'lexical.db',
          'size': 7,
          'tag': 'v2',
          'sha256': sha256.convert(utf8.encode('LEXICAL')).toString(),
        },
      }),
    );
    applier = _FakeDeltaApplier();
    guard = _Guard();
  });

  tearDown(() async {
    AppL10n.use(AppLanguage.hebrew);
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  LibraryManager manager({int? freeBytes = 1 << 40}) => LibraryManager(
    dataDir: dataDir,
    operatingSystem: 'linux',
    processGuard: guard,
    environment: {'HOME': p.join(tempDir.path, 'home')},
    applier: applier,
    freeBytesFor: (_) => freeBytes,
  );

  LibraryUpdateCheckResult check() {
    final edge = buildSchema2PatchEdge(
      bindings!,
      tempDir.path,
      from: 4,
      to: 5,
      upsertRows: const [],
    );
    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      plan: LibraryUpdatePlan.delta(
        localVersion: 4,
        targetVersion: 5,
        steps: [edge],
      ),
    );
  }

  bool skip() {
    if (bindings != null) return false;
    markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
    return true;
  }

  File stagedMarker() => File('$lexical.offline-staging/lexical.db.version');

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('הנלווים מוכנים בזמן שהצעד האחרון רץ, ו-commit ממתין למסד', () async {
    if (skip()) return;
    final m = manager();
    addTearDown(m.dispose);
    final stages = <LibraryApplyStage>[];

    final apply = m.applyUpdate(
      check(),
      onProgress: (e) => stages.add(e.stage),
    );
    await applier.inFinalStep.future;
    await until(() => stagedMarker().existsSync());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final callsWhileStaged = guard.calls;

    expect(stagedMarker().existsSync(), isTrue, reason: 'הוכנו במקביל');
    expect(File(lexical).existsSync(), isFalse, reason: 'אין commit לפני המסד');
    expect(applier.finished, isFalse);
    expect(stages, isNot(contains(LibraryApplyStage.installingCompanions)));

    applier.gate.complete();
    await apply;

    expect(applier.finished, isTrue);
    expect(File(lexical).readAsStringSync(), 'LEXICAL');
    expect(guard.calls, greaterThan(callsWhileStaged));
    expect(stagedMarker().existsSync(), isFalse);
  });

  test('כשל במסד: הנלווים שהוכנו נזרקים בלי commit, בלי אזהרה', () async {
    if (skip()) return;
    final m = manager();
    addTearDown(m.dispose);
    applier.failWith = StateError('db failed');
    final warnings = <String>[];

    final apply = m.applyUpdate(
      check(),
      onCompanionWarning: (name, _) => warnings.add(name),
    );
    final outcome = expectLater(apply, throwsStateError);
    await applier.inFinalStep.future;
    await until(() => stagedMarker().existsSync());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final callsWhileStaged = guard.calls;
    applier.gate.complete();
    await outcome;

    final store = LibraryStateStore(p.join(dataDir, 'library_state.json'));
    expect(await store.loadDeliveredCompanions(), isEmpty);
    expect(File(lexical).existsSync(), isFalse);
    expect(Directory('$lexical.offline-staging').existsSync(), isFalse);
    expect(Directory('$lexical.offline-backup').existsSync(), isFalse);
    expect(warnings, isEmpty);
    expect(guard.calls, callsWhileStaged, reason: 'ה-commit לא הגיע לבדיקה');
  });

  test('כשל במסד משאיר את הנלווים הישנים כפי שהיו', () async {
    if (skip()) return;
    final m = manager();
    addTearDown(m.dispose);
    File(lexical).writeAsStringSync('OLD');
    applier.failWith = StateError('db failed');

    final apply = m.applyUpdate(check());
    final outcome = expectLater(apply, throwsStateError);
    await applier.inFinalStep.future;
    await until(() => stagedMarker().existsSync());
    applier.gate.complete();
    await outcome;

    expect(File(lexical).readAsStringSync(), 'OLD');
    expect(File('$lexical.version').existsSync(), isFalse);
  });

  test('עם חפיפה, אוצריא פתוחה ב-commit עדיין חוסמת את הנלווים', () async {
    if (skip()) return;
    final m = manager();
    addTearDown(m.dispose);
    final warnings = <Object>[];

    final apply = m.applyUpdate(
      check(),
      onCompanionWarning: (_, error) => warnings.add(error),
    );
    await applier.inFinalStep.future;
    await until(() => stagedMarker().existsSync());
    guard.running = true;
    applier.gate.complete();
    await apply;

    expect(applier.finished, isTrue);
    expect(warnings.single, isA<OtzariaIsRunningException>());
    expect(File(lexical).existsSync(), isFalse);
  });

  test('כשל בנלווים אינו מכשיל את המסד ומדווח כאזהרה', () async {
    if (skip()) return;
    final m = manager();
    addTearDown(m.dispose);
    Directory('$lexical.next.version').createSync(recursive: true);
    File(lexical).writeAsStringSync('OLD');
    final warnings = <String>[];

    final apply = m.applyUpdate(
      check(),
      onCompanionWarning: (name, _) => warnings.add(name),
    );
    await applier.inFinalStep.future;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    applier.gate.complete();
    await apply;

    expect(applier.finished, isTrue);
    expect(warnings, isNotEmpty);
    expect(File(lexical).readAsStringSync(), 'OLD');
  });

  test('המקום נמדד לפי הגודל המחולץ של הנלווים, בלי מכפיל על הדחוס', () async {
    if (skip()) return;
    final last = check().plan!.deltaSteps.last.manifest.patchFiles.first;
    final base =
        DiskSpaceProbe.defaultHeadroomBytes +
        File(dbPath).lengthSync() +
        2 * last.uncompressedSize;

    final tight = manager(freeBytes: base + 6);
    addTearDown(tight.dispose);
    final apply = tight.applyUpdate(check());
    await applier.inFinalStep.future;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(stagedMarker().existsSync(), isFalse, reason: 'חסר בייט אחד');
    applier.gate.complete();
    await apply;
  });

  test('בגודל מחולץ ידוע ומקום מספיק בדיוק — חופפים', () async {
    if (skip()) return;
    final last = check().plan!.deltaSteps.last.manifest.patchFiles.first;
    final base =
        DiskSpaceProbe.defaultHeadroomBytes +
        File(dbPath).lengthSync() +
        2 * last.uncompressedSize;
    final m = manager(freeBytes: base + 7);
    addTearDown(m.dispose);

    final apply = m.applyUpdate(check());
    await applier.inFinalStep.future;
    await until(() => stagedMarker().existsSync());

    expect(stagedMarker().existsSync(), isTrue);
    applier.gate.complete();
    await apply;
  });

  test('גודל מחולץ לא ידוע של פריט דחוס — ברצף', () async {
    if (skip()) return;
    File(
      p.join(dataDir, 'mirror', 'companions', CompanionMirrorManifest.fileName),
    ).writeAsStringSync(
      jsonEncode({
        'formatVersion': 1,
        'exportedAt': '2026-08-09T00:00:00.000Z',
        'dictionary': {
          'fileName': 'lexical.db',
          'size': 7,
          'tag': 'v2',
          'compressed': true,
        },
      }),
    );
    final m = manager();
    addTearDown(m.dispose);

    final apply = m.applyUpdate(check());
    await applier.inFinalStep.future;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(stagedMarker().existsSync(), isFalse);
    applier.gate.complete();
    await apply;
  });

  test('בלי מקום מוכח לשניהם הנלווים מתחילים רק אחרי המסד', () async {
    if (skip()) return;
    final m = manager(freeBytes: 1);
    addTearDown(m.dispose);

    final apply = m.applyUpdate(check());
    await applier.inFinalStep.future;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(File(lexical).existsSync(), isFalse);

    applier.gate.complete();
    await apply;
    expect(File(lexical).readAsStringSync(), 'LEXICAL');
  });
}

class _FakeDeltaApplier extends LibraryUpdateApplier {
  final inFinalStep = Completer<void>();
  final gate = Completer<void>();
  Object? failWith;
  bool finished = false;

  @override
  Future<Set<int>> applyDelta({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(Set<int> booksTouched, int toVersion)? onStepApplied,
    bool Function()? isCancelled,
    void Function(String message)? onLog,
    Future<void> Function()? onFinalStepStart,
  }) async {
    await onFinalStepStart?.call();
    inFinalStep.complete();
    await gate.future;
    final error = failWith;
    if (error != null) throw error;
    finished = true;
    return const {};
  }
}

class _Guard extends OtzariaProcessGuard {
  bool running = false;
  int calls = 0;

  @override
  Future<bool> isAnyRunning(List<String> processNames) async {
    calls++;
    return running;
  }

  @override
  Future<bool> isRunning(String processName) async {
    calls++;
    return running;
  }
}
