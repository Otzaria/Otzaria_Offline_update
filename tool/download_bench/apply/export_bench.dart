// Times a real library mirror download with the production exporter and
// LibraryManager's connection policy. From library_manager:
// EXPORT_DIR=<new dir> flutter test <this>. Not a dependency there.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/download_connections.dart';
import 'package:library_manager/src/services/library_updater_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../lib/meter.dart';
import '../lib/scratch.dart';

String _need(String name) {
  final v = Platform.environment[name];
  if (v == null || v.isEmpty) throw BenchFailure('$name is required');
  return v;
}

/// Bytes of every regular file under [dir], recursively.
int treeBytes(String dir) => Directory(dir)
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .fold(0, (a, f) => a + f.lengthSync());

void main() {
  test('library mirror export', () async {
    useLibraryUpdaterL10n();
    // A resumed mirror would time only the missing assets.
    final out = OwnedDir.open(_need('EXPORT_DIR'));
    final dest = out.path;
    final leftovers = Directory(
      dest,
    ).listSync(followLinks: false).where((e) => !e.path.endsWith(ownedMarker));
    if (leftovers.isNotEmpty) {
      throw BenchFailure('$dest is not empty; give EXPORT_DIR a new path');
    }
    final fromVersion = int.tryParse(Platform.environment['EXPORT_FROM'] ?? '');
    final scheduler = DownloadScheduler();
    final decided = <String>[];
    final exporter = LibraryMirrorExporter(
      supportedDbSchemaVersion: kSupportedDbSchemaVersion,
      scheduler: scheduler,
      connectionsForAsset: (destPath, size, sha256, resumeToken) async {
        final n =
            size > 0 && size < PatchDownloader.defaultSegmentThresholdBytes
            ? connectionsPerFile(scheduler)
            : await connectionsForAsset(
                scheduler,
                destPath,
                token: resumeToken ?? sha256,
              );
        decided.add('${destPath.split(RegExp(r'[\\/]')).last}=$n');
        return n;
      },
    );
    final sw = Stopwatch()..start();
    final io0 = processWrites();
    final cpu0 = processCpuSeconds();
    var downloaded = 0;
    int? announced;
    final stages = <String>[];
    bool exported;
    try {
      exported = await exporter.export(
        destDir: dest,
        allowPrerelease: false,
        fromVersion: fromVersion,
        onStage: (s) {
          if (stages.isEmpty || stages.last != s) stages.add(s);
        },
        onBytesProgress: (d, t) {
          downloaded = d;
          announced ??= t;
        },
      );
    } finally {
      exporter.dispose();
    }
    // Includes the release-list fetch, as the user waits for it too.
    final exportMs = sw.elapsedMilliseconds;
    await settleWriteProbes();
    final io1 = processWrites();
    final cpu1 = processCpuSeconds();
    final mirrorBytes = treeBytes(dest);

    // Optional upper bound for full staging: the finished local mirror copied
    // file by file to COPY_TO (content was verified by the export itself).
    String copyMs = 'n/a';
    final copyTo = Platform.environment['EXPORT_COPY_TO'];
    if (copyTo != null && copyTo.isNotEmpty) {
      final target = OwnedDir.open(copyTo).path;
      final c = Stopwatch()..start();
      for (final f in Directory(
        dest,
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        final rel = f.path.substring(dest.length + 1);
        if (rel == ownedMarker || rel.endsWith('.lock')) continue;
        final to = File('$target${Platform.pathSeparator}$rel');
        to.parent.createSync(recursive: true);
        await f.copy(to.path);
        final raf = to.openSync(mode: FileMode.append);
        try {
          raf.flushSync();
        } finally {
          raf.closeSync();
        }
      }
      copyMs = secs(c.elapsedMilliseconds);
    }

    final drive = driveInfo(dest);
    final record = <String, Object?>{
      'kind': 'export',
      'label': Platform.environment['EXPORT_LABEL'] ?? 'n/a',
      ...await runEnvironment(),
      'runtime': 'flutter_tester',
      'mode': fromVersion == null
          ? 'full-mirror'
          : 'personal-from-v$fromVersion',
      'exported': exported,
      'target_kind': drive.kind,
      'target_fs': drive.fs,
      'conns_decided': decided.join(','),
      'announced_MiB': announced == null ? 'n/a' : mib(announced!),
      'downloaded_MiB': mib(downloaded),
      'mirror_MiB': mib(mirrorBytes),
      'export_s': secs(exportMs),
      'rate_MiBps': exportMs == 0
          ? 'n/a'
          : (downloaded / 1048576 / (exportMs / 1000)).toStringAsFixed(2),
      'copy_to_target_s': copyMs,
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
      'stages': stages.length,
    };
    final line = record.entries.map((e) => '${e.key}=${e.value}').join(' ');
    // ignore: avoid_print
    print('EXPORTRESULT $line');
    if (Platform.environment['EXPORT_JSON'] case final path?) {
      appendJsonl(path, record);
    }
  }, timeout: Timeout.none);
}
