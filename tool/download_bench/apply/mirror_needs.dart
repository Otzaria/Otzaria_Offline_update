// Which mirror patches the real offline planner ever picks, per local version.
// From library_manager: NEEDS_MIRROR=<mirror/library> flutter test <this>.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/library_updater_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../lib/meter.dart';

void main() {
  test('mirror patch usage', () async {
    useLibraryUpdaterL10n();
    final mirror = Platform.environment['NEEDS_MIRROR'] ?? '';
    if (mirror.isEmpty) fail('NEEDS_MIRROR is required');
    final d = await OfflineLibraryUpdateDiscovery(
      client: LocalMirrorLibraryReleaseClient(mirrorDir: mirror),
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
    ).discover(allowPrerelease: false);
    String key(PatchEdge e) => '${e.fromVersion}->${e.toVersion}';
    final used = <String>{};
    final lowest = d.edges.isEmpty
        ? d.latestVersion
        : d.edges.map((e) => e.fromVersion).reduce((a, b) => a < b ? a : b);
    void collect(LibraryUpdatePlan? p) {
      if (p == null) return;
      used.addAll(p.deltaSteps.map(key));
      collect(p.fullDownloadFallback);
      collect(p.followUpDelta);
    }

    // v=-1 stands for a machine with no db_version.
    for (final v in [
      -1,
      for (var x = lowest > 0 ? lowest - 1 : 0; x < d.latestVersion; x++) x,
    ]) {
      final plan = const OfflineLibraryUpdatePlanner().plan(
        localVersion: v < 0 ? 0 : v,
        hasLocalVersionMeta: v >= 0,
        latestVersion: d.latestVersion,
        edges: d.edges,
        latestFullDbAsset: d.latestFullDbAsset,
        fullDbReleaseTag: d.fullDbReleaseTag,
        latestFullDbVersion: d.latestFullDbVersion,
        latestContentTag: d.latestContentTag,
      );
      collect(plan);
      print(
        'FROM ${v < 0 ? 'no-version' : 'v$v'} -> ${plan.kind.name} '
        '${plan.deltaSteps.map(key).join(' ')} '
        '(${mib(plan.deltaSteps.fold<int>(0, (a, e) => a + e.compressedSize))} MiB)',
      );
    }
    var usedBytes = 0, unusedBytes = 0;
    for (final e in d.edges) {
      final isUsed = used.contains(key(e));
      if (isUsed) {
        usedBytes += e.compressedSize;
      } else {
        unusedBytes += e.compressedSize;
      }
      print(
        'EDGE ${key(e)} ${mib(e.compressedSize)} MiB '
        '${isUsed ? 'used' : 'NEVER-PICKED'}',
      );
    }
    print(
      'NEEDS edges=${d.edges.length} used_MiB=${mib(usedBytes)} '
      'never_picked_MiB=${mib(unusedBytes)} '
      'full_db_MiB=${mib(d.latestFullDbAsset?.size ?? 0)}',
    );
  }, timeout: Timeout.none);
}
