import 'dart:convert';
import 'dart:io';

import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/semantic_fixtures.dart';

/// v34 הביא ~1.75GB של וקטורים דחוסים, ושום בדיקה לא שאלה אם יש מקום לפני
/// הכתיבה הראשונה לכונן המראה.
void main() {
  const headroom = DiskSpaceProbe.defaultHeadroomBytes;
  late Directory temp;
  late String mirror;
  late FakeVectorsGithub github;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-space-test-');
    mirror = p.join(temp.path, 'mirror');
    github = FakeVectorsGithub();
  });

  tearDown(() async {
    github.client.close();
    await temp.delete(recursive: true);
  });

  final modelBytes = fakeModels.fold<int>(0, (sum, file) => sum + file.size);

  int manifestBytes(int version) => utf8
      .encode(
        jsonEncode(
          FakeVectorsGithub.manifestOf(
            kind: 'base',
            from: 0,
            to: version,
            file: 'legacy-v$version.oxv.zst',
            segment: List<int>.generate(
              500,
              (i) => (i * 31 + version + 7) % 251,
            ),
            identity: '',
            chunking: 2685558872390372738,
          ),
        ),
      )
      .length;

  Future<void> sync(int version, {required int? Function(String) free}) async {
    final assets = SemanticSearchAssets(
      httpClient: github.client,
      models: fakeModels,
      freeBytesFor: free,
    );
    try {
      await assets.sync(
        mirrorDir: mirror,
        libraryTag: libraryTagOf(version),
        libraryTagFor: libraryTagOf,
      );
    } finally {
      assets.dispose();
    }
  }

  Future<StorageFullException> refused(int version, {int free = 0}) async {
    try {
      await sync(version, free: (_) => free);
    } on StorageFullException catch (error) {
      return error;
    }
    fail('the sync was not refused');
  }

  test('a full drive is refused before any asset is written', () async {
    github.legacyBase(30);

    final error = await refused(30);

    expect(error.dir, mirror);
    expect(error.freeBytes, 0);
    expect(error.neededBytes, 500 + manifestBytes(30) + modelBytes);
    expect(
      error.message,
      AppL10n.strings.libraryDomain.notEnoughDiskSpace(
        mirror,
        DiskSpaceProbe.formatBytes(error.neededBytes!),
        DiskSpaceProbe.formatBytes(0),
      ),
    );
    expect(github.downloads, [legacyManifestName(30)]);
    expect(Directory(p.join(mirror, libraryTagOf(30))).existsSync(), isFalse);
  });

  test('the headroom is part of the question', () async {
    github.legacyBase(30);
    final needed = (await refused(30)).neededBytes!;

    expect(
      (await refused(30, free: needed + headroom - 1)).freeBytes,
      isNotNull,
    );

    await sync(30, free: (_) => needed + headroom);
    expect(github.downloads, contains('legacy-v30.oxv.zst'));
  });

  test('unknown free space does not block the download', () async {
    github.legacyBase(30);

    await sync(30, free: (_) => null);

    expect(github.downloads, contains('legacy-v30.oxv.zst'));
  });

  test('bytes already on the drive are not counted again', () async {
    github.legacyBase(30);
    final full = (await refused(30)).neededBytes!;
    final vectors = p.join(mirror, libraryTagOf(30), 'vectors');
    await Directory(vectors).create(recursive: true);
    final segment = File(p.join(vectors, 'legacy-v30.oxv.zst'));

    await segment.writeAsBytes(List<int>.filled(200, 1));
    expect((await refused(30)).neededBytes, full - 200);

    await segment.writeAsBytes(List<int>.filled(500, 1));
    expect((await refused(30)).neededBytes, full - 500);
  });

  test(
    'a model reused from an older generation is counted once, as a copy',
    () async {
      github.legacyBase(29);
      github.legacyBase(30);
      await sync(29, free: (_) => null);
      github.downloads.clear();

      final error = await refused(30);

      expect(error.neededBytes, 500 + manifestBytes(30) + modelBytes);
      expect(
        github.downloads.where(fakeModels.map((m) => m.name).contains),
        isEmpty,
      );
    },
  );

  test(
    'the pinned model counts its zipped tokenizer and the unzipped copy',
    () async {
      github.legacyBase(30);
      final assets = SemanticSearchAssets(
        httpClient: github.client,
        freeBytesFor: (_) => 0,
      );
      addTearDown(assets.dispose);

      final error = await assets
          .sync(mirrorDir: mirror, libraryTag: libraryTagOf(30))
          .then<StorageFullException>(
            (_) => fail('the sync was not refused'),
            onError: (Object error) => error as StorageFullException,
          );

      final download = [
        for (final file in SemanticSearchAssets.modelFiles)
          file.name == 'tokenizer.json'
              ? SemanticSearchAssets.tokenizerZip
              : file,
      ].fold<int>(0, (sum, file) => sum + file.size);
      expect(
        error.neededBytes,
        500 +
            manifestBytes(30) +
            download +
            SemanticSearchAssets.modelFiles[1].size,
      );
    },
  );

  group('a range download that was interrupted', () {
    final segment = List<int>.generate(500, (i) => (i * 31 + 30 + 7) % 251);
    final bounds = [0, 125, 250, 375, 500];

    Future<void> leaveRanges({
      String? token,
      String? url,
      Object? etag,
      int lastRange = 125,
      int tail = 0,
    }) async {
      final vectors = p.join(mirror, libraryTagOf(30), 'vectors');
      await Directory(vectors).create(recursive: true);
      final dest = p.join(vectors, 'legacy-v30.oxv.zst');
      await File(dest).writeAsBytes(List<int>.filled(125 + tail, 1));
      for (final (i, length) in [125, 125, lastRange].indexed) {
        await File('$dest.seg-${i + 1}').writeAsBytes(List.filled(length, 1));
      }
      await File('$dest.segments').writeAsString(
        jsonEncode({
          'v': 1,
          'token': token ?? Sha256Stream.ofBytes(segment),
          'url':
              url ??
              'https://github.com/Otzaria/SeforimLibrary/releases/download/'
                  'vectors-${libraryTagOf(30)}/legacy-v30.oxv.zst',
          'size': 500,
          'sha256': Sha256Stream.ofBytes(segment),
          'etag': etag,
          'bounds': bounds,
          'assembled': 1,
        }),
      );
    }

    Future<StorageFullException> refusedWithRanges({
      int threshold = 100,
    }) async {
      final assets = _RangeAssets(github, threshold: threshold);
      addTearDown(assets.dispose);
      try {
        await assets.sync(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
          libraryTagFor: libraryTagOf,
        );
      } on StorageFullException catch (error) {
        return error;
      }
      fail('the sync was not refused');
    }

    test('is counted by the ranges already on the drive', () async {
      github.legacyBase(30);
      await leaveRanges(lastRange: 120);

      final error = await refusedWithRanges();

      expect(error.neededBytes, manifestBytes(30) + modelBytes + 5 + 125);
    });

    test(
      'is not refused when the room covers the rest and the assembly',
      () async {
        github.legacyBase(30);
        await leaveRanges(lastRange: 120);
        final needed = manifestBytes(30) + modelBytes + 5 + 125;
        final assets = _RangeAssets(github, free: needed + headroom);
        addTearDown(assets.dispose);

        await assets.sync(
          mirrorDir: mirror,
          libraryTag: libraryTagOf(30),
          libraryTagFor: libraryTagOf,
        );

        expect(github.downloads, contains('legacy-v30.oxv.zst'));
      },
    );

    test('ranges saved for another address are not counted', () async {
      github.legacyBase(30);
      await leaveRanges(url: 'https://example.test/other', lastRange: 120);

      final error = await refusedWithRanges();

      expect(error.neededBytes, manifestBytes(30) + modelBytes + 375 + 125);
    });

    test(
      'a tail left by an interrupted assembly is not counted twice',
      () async {
        github.legacyBase(30);
        await leaveRanges(lastRange: 120, tail: 60);

        final error = await refusedWithRanges();

        expect(error.neededBytes, manifestBytes(30) + modelBytes + 5 + 125);
      },
    );

    test(
      'ranges are not counted when the downloader would not split',
      () async {
        github.legacyBase(30);
        await leaveRanges(lastRange: 120);

        final error = await refusedWithRanges(threshold: 1000);

        expect(error.neededBytes, manifestBytes(30) + modelBytes + 375);
      },
    );

    test('a complete file with a leftover state needs nothing more', () async {
      github.legacyBase(30);
      await leaveRanges(lastRange: 120, tail: 375);

      final error = await refusedWithRanges();

      expect(error.neededBytes, manifestBytes(30) + modelBytes);
    });

    test(
      'ranges all downloaded but not yet assembled still need room to join',
      () async {
        github.legacyBase(30);
        await leaveRanges();

        final error = await refusedWithRanges();

        expect(error.neededBytes, manifestBytes(30) + modelBytes + 125);
      },
    );

    test('another asset\'s ranges are not counted', () async {
      github.legacyBase(30);
      await leaveRanges(token: 'another-asset');

      final error = await refusedWithRanges();

      expect(error.neededBytes, manifestBytes(30) + modelBytes + 375 + 125);
    });

    test('a malformed validator makes the range state unusable', () async {
      github.legacyBase(30);
      await leaveRanges(etag: 123);

      final error = await refusedWithRanges();

      expect(error.neededBytes, manifestBytes(30) + modelBytes + 375 + 125);
    });
  });
}

class _RangeAssets extends SemanticSearchAssets {
  _RangeAssets(FakeVectorsGithub github, {int free = 0, this.threshold = 100})
    : _github = github,
      super(
        httpClient: github.client,
        models: fakeModels,
        freeBytesFor: (_) => free,
      );

  final FakeVectorsGithub _github;
  final int threshold;

  @override
  PatchDownloader newDownloader() => PatchDownloader(
    httpClient: _github.client,
    decompress: (_) async => null,
    maxConnections: 4,
    segmentThresholdBytes: threshold,
  );
}
