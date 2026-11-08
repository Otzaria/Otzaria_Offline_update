// Times offline apply stages with the real LibraryUpdateApplier on a COPY of
// seforim.db; run via apply_suite.sh (APPLY_* variables documented there).
// The bench lib is not a package dependency of library_manager.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/library_update_applier.dart';
import 'package:library_manager/src/services/library_updater_l10n.dart';
import 'package:library_manager/src/services/otzaria_process_guard.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../lib/meter.dart';
import '../lib/scratch.dart';

/// Stable stage names: `patch_<PatchApplier stage>`, `full_verify_<check>`.
String stageKey(LibraryApplyProgress p) => switch (p.stage) {
  LibraryApplyStage.downloadingPatch => 'patch_fetch',
  LibraryApplyStage.decompressingPatch => 'patch_extract',
  LibraryApplyStage.applyingPatch => 'patch_${p.patchStage ?? 'start'}',
  LibraryApplyStage.downloadingFullDb => 'full_fetch',
  LibraryApplyStage.decompressingFullDb => 'full_extract',
  LibraryApplyStage.verifying => 'full_verify_${p.verifyStage ?? 'start'}',
  LibraryApplyStage.writingFullDb => 'full_swap',
  final s => s.name,
};

String _need(String name) {
  final v = Platform.environment[name];
  if (v == null || v.isEmpty) throw BenchFailure('$name is required');
  return v;
}

void main() {
  test('offline apply stages', () async {
    final mirror = _need('APPLY_MIRROR');
    final source = File(_need('APPLY_DB')).absolute.path;
    final route = Platform.environment['APPLY_ROUTE'] ?? 'auto';
    if (!{'auto', 'delta', 'full'}.contains(route)) {
      throw BenchFailure('APPLY_ROUTE must be auto, delta or full');
    }
    if (!File(source).existsSync()) throw BenchFailure('no DB at $source');
    final names = OtzariaProcessGuard.processNamesFor(Platform.operatingSystem);
    if (await const OtzariaProcessGuard().isAnyRunning(names)) {
      throw BenchFailure('close Otzaria first: the DB may be mid-write');
    }
    // Committed pages still in the WAL would make the copy an older DB.
    final wal = File('$source-wal');
    if (wal.existsSync() && wal.lengthSync() > 0) {
      throw BenchFailure('$source-wal holds data: open and close Otzaria once');
    }
    final sourceStamp = (
      File(source).lengthSync(),
      File(source).lastModifiedSync(),
    );
    final workPath = canonicalScratchPath(_need('APPLY_WORK')).toLowerCase();
    final mirrorPath = Directory(
      mirror,
    ).resolveSymbolicLinksSync().toLowerCase();
    final sep = Platform.pathSeparator;
    final mirrorDir = mirrorPath.endsWith(sep) ? mirrorPath : '$mirrorPath$sep';
    if (workPath == mirrorPath || workPath.startsWith(mirrorDir)) {
      throw BenchFailure('APPLY_WORK must be outside the mirror');
    }
    useLibraryUpdaterL10n();
    final work = OwnedDir.open(_need('APPLY_WORK'));
    final db = work.file('seforim.db');
    // A fresh directory also proves the copy cannot be the source itself.
    if (File(db).existsSync()) {
      throw BenchFailure('APPLY_WORK must be a new directory');
    }
    final sw = Stopwatch()..start();
    var ok = false;
    try {
      await File(source).copy(db);
      final copyMs = sw.elapsedMilliseconds;
      final sizeBefore = File(db).lengthSync();

      // --- the measured update starts here ---
      final t0 = sw.elapsedMilliseconds;
      final io0 = processWrites();
      final cpu0 = processCpuSeconds();
      final local = const LocalDbVersionReader().read(db);
      final discovery =
          await OfflineLibraryUpdateDiscovery(
            client: LocalMirrorLibraryReleaseClient(mirrorDir: mirror),
            supportedDbSchemaVersion: kSupportedDbSchemaVersion,
          ).discover(
            allowPrerelease: Platform.environment['APPLY_PRERELEASE'] == '1',
          );
      // Forcing a route = hiding the other one from the real planner.
      final plan = const OfflineLibraryUpdatePlanner().plan(
        localVersion: local.dbVersion,
        hasLocalVersionMeta: local.hasVersionMeta,
        latestVersion: discovery.latestVersion,
        edges: route == 'full' ? const [] : discovery.edges,
        latestFullDbAsset: route == 'delta'
            ? null
            : discovery.latestFullDbAsset,
        fullDbReleaseTag: discovery.fullDbReleaseTag,
        latestFullDbVersion: discovery.latestFullDbVersion,
        latestContentTag: discovery.latestContentTag,
      );
      final planMs = sw.elapsedMilliseconds - t0;
      final isDelta = plan.kind == LibraryUpdatePlanKind.delta;
      if (!isDelta && plan.kind != LibraryUpdatePlanKind.fullDownload) {
        throw BenchFailure(
          'nothing to measure: plan is ${plan.kind.name} '
          '(local v${local.dbVersion}) ${plan.reason ?? ''}',
        );
      }
      const estimate = ApplyTimeEstimate();
      final stepBytes = [for (final e in plan.deltaSteps) e.compressedSize];
      final inputBytes = isDelta
          ? stepBytes.fold<int>(0, (a, b) => a + b)
          : plan.fullDbAsset!.size;
      final clock = StageClock(() => sw.elapsedMilliseconds)..enter('setup');
      final applier = LibraryUpdateApplier();
      void onProgress(LibraryApplyProgress p) => clock.enter(stageKey(p));
      try {
        if (isDelta) {
          await applier.applyDelta(
            plan: plan,
            dbPath: db,
            onProgress: onProgress,
          );
        } else {
          await applier.applyFullDownload(
            plan: plan,
            dbPath: db,
            onProgress: onProgress,
          );
        }
      } finally {
        applier.dispose();
      }
      clock.stop();
      final totalMs = sw.elapsedMilliseconds - t0;
      // --- end of the measured update ---

      final io1 = processWrites();
      final cpu1 = processCpuSeconds();
      final after = const LocalDbVersionReader().read(db);
      if (after.dbVersion != plan.targetVersion) {
        throw BenchFailure(
          'DB is v${after.dbVersion} after apply, plan said v${plan.targetVersion}',
        );
      }
      if ((File(source).lengthSync(), File(source).lastModifiedSync()) !=
          sourceStamp) {
        throw BenchFailure('the source DB changed during the run: $source');
      }
      final mirrorDrive = driveInfo(mirror), dbDrive = driveInfo(db);
      final record = <String, Object?>{
        'kind': 'apply',
        'label': Platform.environment['APPLY_LABEL'] ?? 'n/a',
        ...await runEnvironment(),
        // flutter_tester hosts the test harness too: memory is an upper bound
        'runtime': 'flutter_tester',
        'route': isDelta ? 'delta' : 'full',
        'route_requested': route,
        'from_version': local.dbVersion,
        'to_version': plan.targetVersion,
        'steps': isDelta ? plan.deltaSteps.length : 1,
        'input_MiB': mib(inputBytes),
        'db_before_MiB': mib(sizeBefore),
        'db_after_MiB': mib(File(db).lengthSync()),
        'mirror_kind': mirrorDrive.kind,
        'mirror_fs': mirrorDrive.fs,
        'db_kind': dbDrive.kind,
        'db_fs': dbDrive.fs,
        // The copy just wrote the DB: its pages are hot, unlike a real machine.
        'db_cache': 'warm-after-copy',
        'setup_copy_s': secs(copyMs),
        'plan_s': secs(planMs),
        for (final s in clock.order) 'stage_${s}_s': secs(clock.ms[s]!),
        'total_s': secs(totalMs),
        'estimate_s':
            (isDelta
                    ? estimate.deltaRouteSeconds(stepBytes)
                    : estimate.fullRouteSeconds(inputBytes))
                .toStringAsFixed(0),
        'cpu_s': cpu0 == null || cpu1 == null
            ? 'n/a'
            : (cpu1 - cpu0).toStringAsFixed(2),
        'peak_rss_MiB': mib(peakRssBytes()),
        'proc_write_MiB': io0 == null || io1 == null
            ? 'n/a'
            : mib(io1.writeBytes - io0.writeBytes),
        'proc_read_MiB': io0 == null || io1 == null
            ? 'n/a'
            : mib(io1.readBytes - io0.readBytes),
        'content_ok': true,
      };
      final line = record.entries.map((e) => '${e.key}=${e.value}').join(' ');
      // ignore: avoid_print
      print('APPLYRESULT $line');
      if (Platform.environment['APPLY_JSON'] case final path?) {
        appendJsonl(path, record);
      }
      ok = true;
    } finally {
      if (Platform.environment['APPLY_KEEP'] != '1') {
        try {
          OwnedDir.removeTree(work.path);
        } on Object catch (e) {
          final message = 'could not remove ${work.path} (a DB copy): $e';
          // A failed run already throws; a successful one must not hide this.
          if (ok) throw BenchFailure(message);
          // ignore: avoid_print
          print(message);
        }
      }
    }
  }, timeout: Timeout.none);
}
