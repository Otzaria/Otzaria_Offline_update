import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:library_manager/src/services/storage_guard.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

import 'support/failing_writes.dart';
import 'support/semantic_fixtures.dart';

/// כשל כתיבה אסינכרוני ("הכונן מלא") בנתיבי IOSink: הוא חייב להגיע לקורא
/// כשגיאה אחת, בזמן שהמקור עוד פתוח, בלי zone error ובלי להחליף קובץ תקין.
void main() {
  const bounded = Timeout(Duration(seconds: 15));
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('storage-write-failures-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// מריץ [body] ואוסף כל שגיאה שברחה ל-zone, בלי להשתיק אותה.
  Future<({Object? thrown, List<Object> escaped})> guarded(
    Future<void> Function() body,
  ) async {
    final escaped = <Object>[];
    final finished = Completer<Object?>();
    runZonedGuarded(() {
      body().then(
        (_) => finished.complete(null),
        onError: (Object error) => finished.complete(error),
      );
    }, (error, _) => escaped.add(error));
    final thrown = await finished.future;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return (thrown: thrown, escaped: escaped);
  }

  group('concatenateVectorParts', () {
    late String vectors;
    late String work;
    late List<SemanticAsset> parts;

    setUp(() async {
      vectors = p.join(temp.path, 'vectors');
      work = p.join(temp.path, 'work');
      await Directory(vectors).create(recursive: true);
      await Directory(work).create(recursive: true);
      parts = [];
      for (final (index, size) in [70000, 50000].indexed) {
        final bytes = List<int>.generate(size, (i) => (i + index) % 251);
        final name = 'segment.oxv.part-00$index';
        parts.add((
          name: name,
          size: size,
          sha256: Sha256Stream.ofBytes(bytes),
        ));
        await File(p.join(vectors, name)).writeAsBytes(bytes);
      }
    });

    test('כשל כתיבה אסינכרוני מגיע כ-StorageFull ולא כ-zone error', () async {
      final assets = SemanticSearchAssets();
      addTearDown(assets.dispose);
      final target = p.join(work, 'segment.oxv');

      final result = await guarded(
        () => runWithFailingWrites(
          () => assets.concatenateVectorParts(
            vectorsDir: vectors,
            parts: parts,
            workDir: work,
          ),
          matches: (path) => path == target,
          failAfterBytes: 1000,
        ),
      );

      expect(result.escaped, isEmpty);
      expect(isStorageFull(result.thrown), isTrue, reason: '${result.thrown}');
      expect(result.thrown, isA<StorageFullException>());
    }, timeout: bounded);
  });

  group('הדפסת מילון נלווה (_copyVerified)', () {
    test('כשל כתיבה אינו מחליף מילון תקין ומגיע כ-StorageFull', () async {
      final mirror = p.join(temp.path, 'mirror', 'companions');
      final library = p.join(temp.path, 'books');
      await Directory(mirror).create(recursive: true);
      await Directory(library).create(recursive: true);
      final db = p.join(library, 'seforim.db');
      await File(db).writeAsString('db');
      const digest =
          'e2f31a1891597072286637d1978390dd35f8a6ca1f3dfe07fb232baccb07d1d2';
      await File(p.join(mirror, 'lexical.db')).writeAsString('LEXICAL');
      await File(
        p.join(mirror, CompanionMirrorManifest.fileName),
      ).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'exportedAt': '2026-08-09T00:00:00.000Z',
          'dictionary': {
            'fileName': 'lexical.db',
            'size': 7,
            'tag': 'v2',
            'sha256': digest,
          },
        }),
      );
      final target = File(p.join(library, 'lexical.db'));
      await target.writeAsString('OLD');
      await File('${target.path}.version').writeAsString('old-digest');
      final staged = '${target.path}.new';

      late CompanionInstallReport report;
      final result = await guarded(() async {
        report = await runWithFailingWrites(
          () => const CompanionAssetsInstaller().install(
            mirrorDir: mirror,
            dbPath: db,
          ),
          matches: (path) => path == staged,
        );
      });

      expect(result.escaped, isEmpty);
      expect(result.thrown, isNull);
      expect(
        report.outcomes[CompanionAsset.dictionary],
        CompanionInstallOutcome.failed,
      );
      expect(isStorageFull(report.errors[CompanionAsset.dictionary]), isTrue);
      expect(await target.readAsString(), 'OLD');
      expect(File(staged).existsSync(), isFalse);
    }, timeout: bounded);
  });

  group('הורדת החיפוש החכם למראה', () {
    test('כשל העתקה של מודל שנעשה בו שימוש חוזר מגיע כ-StorageFull', () async {
      final github = FakeVectorsGithub()
        ..legacyBase(29)
        ..legacyBase(30);
      addTearDown(github.client.close);
      final mirror = p.join(temp.path, 'mirror');
      Future<void> sync(int version) async {
        final assets = SemanticSearchAssets(
          httpClient: github.client,
          models: fakeModels,
          freeBytesFor: (_) => null,
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

      await sync(29);
      final source = p.join(
        mirror,
        libraryTagOf(29),
        SemanticSearchAssets.modelFolder,
        'model.json',
      );

      final result = await guarded(
        () => runWithFailingWrites(
          () => sync(30),
          matches: (path) => path == source,
        ),
      );

      expect(result.escaped, isEmpty);
      final error = result.thrown;
      expect(error, isA<StorageFullException>());
      expect((error as StorageFullException).dir, isNotNull);
      expect(error.cause, isA<FileSystemException>());
      expect(
        File(
          p.join(mirror, SemanticSearchAssets.manifestFileName),
        ).readAsStringSync(),
        contains(libraryTagOf(29)),
      );
    }, timeout: bounded);
  });

  group('GuardedSink', () {
    test('a flush that fails before done reports it is a full drive', () async {
      final sink = GuardedSink(_FlushFails(), p.join(temp.path, 'out', 'x'));

      await expectLater(
        sink.flush().timeout(const Duration(seconds: 5)),
        throwsA(
          isA<StorageFullException>().having(
            (e) => e.dir,
            'dir',
            p.join(temp.path, 'out'),
          ),
        ),
      );
    });
  });
}

class _FlushFails implements IOSink {
  @override
  Future<void> flush() => Future.error(
    FileSystemException(
      'flush failed',
      'x',
      OSError('There is not enough space on the disk.', diskFullErrno),
    ),
  );

  @override
  Future<void> get done => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
