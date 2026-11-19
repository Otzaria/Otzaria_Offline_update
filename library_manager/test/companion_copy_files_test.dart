import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/companion_file_operations.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  late Directory temp;
  late File source;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('copy-files-test-');
    source = File(p.join(temp.path, 'source.bin'))
      ..writeAsBytesSync(Uint8List.fromList(List.generate(4000, (i) => i)));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  List<CompanionCopyJob> jobs(int count, {int size = 100}) => [
    for (var i = 0; i < count; i++)
      (
        source: source,
        destination: p.join(temp.path, 'out', 'd$i', 'f$i.bin'),
        expectedSize: size,
        start: i * size,
        end: (i + 1) * size,
      ),
  ];

  test('every file is complete when the call returns', () async {
    final reports = <int>[];
    final written = await copyCompanionFiles(
      jobs(20),
      maxOutputBytes: 1 << 20,
      concurrency: 3,
      onProgress: reports.add,
    );
    expect(written, 2000);
    expect(reports.last, 2000);
    final all = source.readAsBytesSync();
    for (var i = 0; i < 20; i++) {
      expect(
        File(p.join(temp.path, 'out', 'd$i', 'f$i.bin')).readAsBytesSync(),
        all.sublist(i * 100, (i + 1) * 100),
      );
    }
  });

  test('an empty list is a no-op', () async {
    expect(await copyCompanionFiles([], maxOutputBytes: 10), 0);
  });

  test('a non-positive concurrency is rejected instead of copying nothing', () {
    expect(
      () =>
          copyCompanionFiles(jobs(2), maxOutputBytes: 1 << 20, concurrency: 0),
      throwsRangeError,
    );
  });

  test(
    'one failing file fails the stage and leaves no partial output',
    () async {
      final list = jobs(12);
      list[5] = (
        source: list[5].source,
        destination: list[5].destination,
        expectedSize: 99,
        start: 500,
        end: 600,
      );
      await expectLater(
        copyCompanionFiles(list, maxOutputBytes: 1 << 20, concurrency: 4),
        throwsFormatException,
      );
      expect(File(list[5].destination).existsSync(), isFalse);
      // Nothing is still writing: the tree can be removed at once.
      await Directory(p.join(temp.path, 'out')).delete(recursive: true);
    },
  );

  test('cancelling stops the copy and removes the unfinished files', () async {
    var polls = 0;
    final list = jobs(30);
    await expectLater(
      copyCompanionFiles(
        list,
        maxOutputBytes: 1 << 20,
        concurrency: 4,
        // Progress reports are throttled, so cancel from the poll itself.
        isCancelled: () => ++polls > 20,
      ),
      throwsA(isA<PatchDownloadCancelled>()),
    );
    final copied = [
      for (final job in list)
        if (File(job.destination).existsSync()) job,
    ];
    expect(copied.length, lessThan(30));
    for (final job in copied) {
      expect(File(job.destination).lengthSync(), 100);
    }
    await Directory(p.join(temp.path, 'out')).delete(recursive: true);
  });
  test('two jobs for one destination are rejected before any write', () async {
    final list = jobs(2);
    list[1] = (
      source: list[1].source,
      destination: list[0].destination.toUpperCase(),
      expectedSize: 100,
      start: 100,
      end: 200,
    );
    await expectLater(
      copyCompanionFiles(list, maxOutputBytes: 1 << 20),
      throwsArgumentError,
    );
    expect(File(list[0].destination).existsSync(), isFalse);
  }, skip: Platform.isLinux);

  test('maxOutputBytes caps the total across files', () async {
    await expectLater(
      copyCompanionFiles(jobs(5), maxOutputBytes: 450, concurrency: 1),
      throwsFormatException,
    );
    await Directory(p.join(temp.path, 'out')).delete(recursive: true);
  });
}
