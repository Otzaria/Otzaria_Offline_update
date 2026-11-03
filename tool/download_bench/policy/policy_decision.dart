// Prints the production connection decision for a target directory by calling
// library_manager's real functions. A Flutter package cannot be imported by the
// pure-Dart bench, so run from library_manager (see matrix.sh):
//   POLICY_DIR=<dir> flutter test <this file> -r expanded
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/download_connections.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  test('production connection policy for POLICY_DIR', () async {
    final dir = Platform.environment['POLICY_DIR']!;
    final slots = int.parse(
      Platform.environment['POLICY_SLOTS'] ??
          '${DownloadScheduler.defaultMaxConcurrent}',
    );
    final scheduler = DownloadScheduler(maxConcurrent: slots);
    bool? removable, split;
    double? speed;
    var probed = false;
    final conns = await connectionsForDir(
      scheduler,
      dir,
      removableProbe: (d) => removable = isRemovableDrive(d),
      splitProbe: (d) => split = hasSplitState(d),
      writeProbe: (d) async {
        probed = true;
        return speed = await driveWriteSpeed(d);
      },
    );
    final reason = removable != true
        ? 'not-removable-default-share'
        : split == true
        ? 'saved-split-state-default-share'
        : speed == null
        ? 'removable-probe-failed-single'
        : speed! < slowWriteBytesPerSecond
        ? 'removable-slow-write-single'
        : 'removable-fast-write-default-share';
    final mibps = speed == null ? 'n/a' : (speed! / 1048576).toStringAsFixed(1);
    // ignore: avoid_print
    print(
      'POLICY conns=$conns reason=$reason removable=$removable split=$split '
      'probed=$probed write_MiBps=$mibps slots=$slots',
    );
  });
}
