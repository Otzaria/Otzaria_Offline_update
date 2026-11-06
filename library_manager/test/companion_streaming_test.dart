import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/companion_file_operations.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/zstd_fixtures.dart';

void main() {
  final bindings = nativeZstd();
  late Directory temporary;
  late String library;
  late String mirror;
  late String dbPath;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('companion-streaming-');
    library = p.join(temporary.path, 'library');
    mirror = p.join(temporary.path, 'mirror');
    await Directory(library).create();
    await Directory(mirror).create();
    dbPath = p.join(library, 'seforim.db');
    await File(dbPath).writeAsString('live library');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<void> manifest(
    String asset,
    String name, {
    String tag = 'new',
    bool compressed = false,
    int? version,
  }) async {
    final source = File(p.join(mirror, name));
    await File(p.join(mirror, CompanionMirrorManifest.fileName)).writeAsString(
      jsonEncode({
        'formatVersion': 1,
        asset: {
          'fileName': name,
          'size': await source.length(),
          'sha256': (await sha256.bind(source.openRead()).first).toString(),
          'tag': tag,
          'compressed': compressed,
          if (version != null) 'version': version,
        },
      }),
    );
  }

  Future<void> seedDictionary() async {
    await File(p.join(library, 'lexical.db')).writeAsString('old dictionary');
    await File(p.join(library, 'lexical.db.version')).writeAsString('old');
    await File(p.join(mirror, 'lexical.db')).writeAsBytes(Uint8List(4 << 20));
    await manifest('dictionary', 'lexical.db');
  }

  void expectOldDictionary() {
    final target = p.join(library, 'lexical.db');
    expect(File(target).readAsStringSync(), 'old dictionary');
    expect(File('$target.version').readAsStringSync(), 'old');
    expect(Directory('$target.offline-staging').existsSync(), isFalse);
    expect(Directory(companionBackupPath(target)).existsSync(), isFalse);
    expect(File(dbPath).readAsStringSync(), 'live library');
  }

  test(
    'cancelling the last dictionary write preserves content and marker',
    () async {
      await seedDictionary();
      var cancelled = false;
      final report = await const CompanionAssetsInstaller().install(
        mirrorDir: mirror,
        dbPath: dbPath,
        isCancelled: () => cancelled,
        onProgress: (_, done, total) {
          if (done == total && done > 0) cancelled = true;
        },
      );
      expect(
        report.errors[CompanionAsset.dictionary],
        isA<PatchDownloadCancelled>(),
      );
      expect(report.delivered, isEmpty);
      expectOldDictionary();
      expect(await File(p.join(mirror, 'lexical.db')).length(), 4 << 20);
    },
  );

  test(
    'dictionary output cap and callback errors preserve the old install',
    () async {
      await seedDictionary();
      final capped = await const CompanionAssetsInstaller(
        maxOutputBytes: 128 << 10,
      ).install(mirrorDir: mirror, dbPath: dbPath);
      expect(
        capped.outcomes[CompanionAsset.dictionary],
        CompanionInstallOutcome.failed,
      );
      expectOldDictionary();
      final failure = StateError('progress callback');
      final failed = await const CompanionAssetsInstaller().install(
        mirrorDir: mirror,
        dbPath: dbPath,
        onProgress: (_, done, __) {
          if (done > 0) throw failure;
        },
      );
      expect(failed.errors[CompanionAsset.dictionary], same(failure));
      expectOldDictionary();
    },
  );

  test(
    'growth after the size check is stopped during writing and cleaned',
    () async {
      final source = File(p.join(mirror, 'growing.db'));
      await source.writeAsBytes(Uint8List(128 << 10));
      final target = p.join(library, 'copy');
      var largestWritten = 0;
      await expectLater(
        copyCompanionFile(
          source: source,
          destination: target,
          maxOutputBytes: 128 << 10,
          expectedSize: 128 << 10,
          onProgress: (written) {
            if (written == 0) {
              source.writeAsBytesSync(
                Uint8List(128 << 10),
                mode: FileMode.append,
              );
            }
            largestWritten = written;
          },
        ),
        throwsA(isA<FormatException>()),
      );
      expect(largestWritten, lessThanOrEqualTo(128 << 10));
      expect(File(target).existsSync(), isFalse);
      expect(await source.length(), 256 << 10);
    },
  );

  test(
    'catalog verification fails before replacing an existing database',
    () async {
      final target = p.join(library, 'otzar-HB_catalog.db');
      final old = sqlite3.sqlite3.open(target);
      old.execute(
        'CREATE TABLE db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      old.execute("INSERT INTO db_meta VALUES ('version', '1')");
      old.close();
      final before = File(target).readAsBytesSync();
      await File(
        p.join(mirror, 'otzar-HB_catalog.db'),
      ).writeAsString('not SQLite');
      await manifest('catalog', 'otzar-HB_catalog.db', version: 2);
      final report = await const CompanionAssetsInstaller().install(
        mirrorDir: mirror,
        dbPath: dbPath,
      );
      expect(
        report.outcomes[CompanionAsset.catalog],
        CompanionInstallOutcome.failed,
      );
      expect(File(target).readAsBytesSync(), before);
      expect(Directory('$target.offline-staging').existsSync(), isFalse);
    },
  );

  test('an empty zstd output cannot become a metadata-only catalog', () async {
    if (bindings == null) {
      markTestSkipped('libzstd is unavailable');
      return;
    }
    final target = p.join(library, 'otzar-HB_catalog.db');
    final old = sqlite3.sqlite3.open(target);
    old.execute('CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT)');
    old.execute("INSERT INTO books VALUES (1, 'existing catalog')");
    old.close();
    final before = File(target).readAsBytesSync();
    final source = File(p.join(mirror, 'catalog.db.zst'));
    await source.writeAsBytes(compressWithZstd(bindings, Uint8List(0)));
    final compressedBefore = await source.readAsBytes();
    await manifest('catalog', 'catalog.db.zst', compressed: true, version: 2);
    final report = await const CompanionAssetsInstaller().install(
      mirrorDir: mirror,
      dbPath: dbPath,
    );
    expect(
      report.outcomes[CompanionAsset.catalog],
      CompanionInstallOutcome.failed,
    );
    expect(File(target).readAsBytesSync(), before);
    expect(await source.readAsBytes(), compressedBefore);
    expect(Directory('$target.offline-staging').existsSync(), isFalse);
    expect(Directory(companionBackupPath(target)).existsSync(), isFalse);
  });

  for (final cancelNative in [true, false]) {
    test(
      'Talmud cancellation in ${cancelNative ? 'zstd' : 'TAR'} preserves the old tree',
      () async {
        if (bindings == null) {
          markTestSkipped('libzstd is unavailable');
          return;
        }
        final target = p.join(
          library,
          CompanionAssetsInstaller.talmudFolderName,
        );
        await Directory(target).create();
        await File(p.join(target, 'old.pdf')).writeAsString('old PDF');
        await File(p.join(target, '.version')).writeAsString('old');
        final archive = Archive()
          ..addFile(
            ArchiveFile.bytes(
              '${CompanionAssetsInstaller.talmudFolderName}/new.pdf',
              Uint8List(8 << 20),
            ),
          );
        final source = File(p.join(mirror, 'talmud.tar.zst'));
        await source.writeAsBytes(
          compressWithZstd(
            bindings,
            Uint8List.fromList(TarEncoder().encodeBytes(archive)),
          ),
        );
        final compressedBefore = await source.readAsBytes();
        await manifest('talmud', 'talmud.tar.zst', compressed: true);
        var cancelled = false;
        final watch = Stopwatch();
        final report = await const CompanionAssetsInstaller().install(
          mirrorDir: mirror,
          dbPath: dbPath,
          isCancelled: () => cancelled,
          onProgress: (_, written, total) {
            if (written > 0 && (total == null) == cancelNative && !cancelled) {
              cancelled = true;
              watch.start();
            }
          },
        );
        watch.stop();
        expect(cancelled, isTrue);
        expect(
          report.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.failed,
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(File(p.join(target, 'old.pdf')).readAsStringSync(), 'old PDF');
        expect(File(p.join(target, '.version')).readAsStringSync(), 'old');
        expect(File(p.join(target, 'new.pdf')).existsSync(), isFalse);
        expect(Directory('$target.offline-staging').existsSync(), isFalse);
        expect(await source.readAsBytes(), compressedBefore);
      },
    );
  }

  test(
    'unsafe TAR entry never leaves staging or damages the old tree',
    () async {
      if (bindings == null) {
        markTestSkipped('libzstd is unavailable');
        return;
      }
      final target = p.join(library, CompanionAssetsInstaller.talmudFolderName);
      await Directory(target).create();
      await File(p.join(target, '.version')).writeAsString('old');
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            '${CompanionAssetsInstaller.talmudFolderName}/new.pdf',
            'new',
          ),
        )
        ..addFile(ArchiveFile.string('../seforim.db', 'wrong'));
      final source = File(p.join(mirror, 'talmud.tar.zst'));
      await source.writeAsBytes(
        compressWithZstd(
          bindings,
          Uint8List.fromList(TarEncoder().encodeBytes(archive)),
        ),
      );
      await manifest('talmud', 'talmud.tar.zst', compressed: true);
      final report = await const CompanionAssetsInstaller().install(
        mirrorDir: mirror,
        dbPath: dbPath,
      );
      expect(
        report.outcomes[CompanionAsset.talmud],
        CompanionInstallOutcome.failed,
      );
      expect(File(dbPath).readAsStringSync(), 'live library');
      expect(File(p.join(target, '.version')).readAsStringSync(), 'old');
      expect(Directory('$target.offline-staging').existsSync(), isFalse);
    },
  );

  test('failure during the marker rename rolls back both files', () async {
    final target = p.join(library, 'lexical.db');
    final marker = '$target.version';
    File(target).writeAsStringSync('old');
    File(marker).writeAsStringSync('old version');
    final staged = p.join(library, 'new-content');
    File(staged).writeAsStringSync('new');
    expect(
      () => commitCompanionInstall(target, {
        target: staged,
        marker: p.join(library, 'missing-marker'),
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(target).readAsStringSync(), 'old');
    expect(File(marker).readAsStringSync(), 'old version');
    expect(Directory(companionBackupPath(target)).existsSync(), isFalse);
  });

  for (final committed in [false, true]) {
    test(
      'recovery ${committed ? 'keeps committed content' : 'restores an interrupted swap'}',
      () {
        final target = p.join(library, 'lexical.db');
        final marker = '$target.version';
        final backup = Directory(companionBackupPath(target))..createSync();
        File(
          p.join(backup.path, 'state.json'),
        ).writeAsStringSync('[true,true]');
        File(p.join(backup.path, '0')).writeAsStringSync('old');
        File(p.join(backup.path, '1')).writeAsStringSync('old version');
        File(target).writeAsStringSync('new');
        if (committed) {
          File(marker).writeAsStringSync('new version');
          File(p.join(backup.path, 'committed')).writeAsStringSync('1');
        }
        recoverCompanionInstall(target, [target, marker]);
        expect(File(target).readAsStringSync(), committed ? 'new' : 'old');
        expect(
          File(marker).readAsStringSync(),
          committed ? 'new version' : 'old version',
        );
        expect(backup.existsSync(), isFalse);
      },
    );
  }

  test('mirror source aliasing staging is rejected before cleanup', () async {
    await seedDictionary();
    final target = p.join(library, 'lexical.db');
    final work = Directory('$target.offline-staging')..createSync();
    final source = File(p.join(work.path, 'source.db'))
      ..writeAsStringSync('mirror source');
    await File(p.join(mirror, CompanionMirrorManifest.fileName)).writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'dictionary': {
          'fileName': source.path,
          'size': source.lengthSync(),
          'tag': 'new',
        },
      }),
    );
    final report = await const CompanionAssetsInstaller().install(
      mirrorDir: mirror,
      dbPath: dbPath,
    );
    expect(
      report.outcomes[CompanionAsset.dictionary],
      CompanionInstallOutcome.failed,
    );
    expect(source.readAsStringSync(), 'mirror source');
    expect(File(target).readAsStringSync(), 'old dictionary');
  });

  test(
    'recovery remains pending without a mirror and runs without it',
    () async {
      final target = p.join(library, 'lexical.db');
      final backup = Directory(companionBackupPath(target))..createSync();
      File(
        p.join(backup.path, 'state.json'),
      ).writeAsStringSync('[true,true,false,false]');
      File(p.join(backup.path, '0')).writeAsStringSync('old dictionary');
      File(p.join(backup.path, '1')).writeAsStringSync('old');
      const installer = CompanionAssetsInstaller();
      final pending = await installer.pendingWork(
        mirrorDir: mirror,
        dbPath: dbPath,
      );
      expect(pending.pending, {CompanionAsset.dictionary});
      expect(File(target).existsSync(), isFalse);
      final blocked = StateError('Otzaria is running');
      final failed = await installer.install(
        mirrorDir: mirror,
        dbPath: dbPath,
        beforeCommit: () async => throw blocked,
      );
      expect(failed.errors[CompanionAsset.dictionary], same(blocked));
      expect(
        File(p.join(backup.path, '0')).readAsStringSync(),
        'old dictionary',
      );
      final recovered = await installer.install(
        mirrorDir: mirror,
        dbPath: dbPath,
      );
      expect(
        recovered.outcomes[CompanionAsset.dictionary],
        CompanionInstallOutcome.installed,
      );
      expectOldDictionary();
    },
  );

  test(
    'committed cleanup can resume after the journal was already removed',
    () {
      final target = p.join(library, 'lexical.db');
      File(target).writeAsStringSync('new');
      final backup = Directory(companionBackupPath(target))..createSync();
      File(p.join(backup.path, '0')).writeAsStringSync('old');
      File(p.join(backup.path, 'committed')).writeAsStringSync('1');
      recoverCompanionInstall(target, [target]);
      expect(File(target).readAsStringSync(), 'new');
      expect(backup.existsSync(), isFalse);
    },
  );

  test('recovery preserves a mirror source inside the backup', () async {
    final target = p.join(library, 'lexical.db');
    final backup = Directory(companionBackupPath(target))..createSync();
    File(
      p.join(backup.path, 'state.json'),
    ).writeAsStringSync('[true,false,false,false]');
    final source = File(p.join(backup.path, '0'))
      ..writeAsStringSync('mirror source');
    await File(p.join(mirror, CompanionMirrorManifest.fileName)).writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'dictionary': {
          'fileName': source.path,
          'size': source.lengthSync(),
          'tag': 'new',
        },
      }),
    );
    final report = await const CompanionAssetsInstaller().install(
      mirrorDir: mirror,
      dbPath: dbPath,
    );
    expect(
      report.outcomes[CompanionAsset.dictionary],
      CompanionInstallOutcome.failed,
    );
    expect(source.readAsStringSync(), 'mirror source');
    expect(File(target).existsSync(), isFalse);
  });

  test(
    'recovery cannot delete another asset source and unrelated assets install',
    () async {
      final talmud = p.join(library, CompanionAssetsInstaller.talmudFolderName);
      final backup = Directory(companionBackupPath(talmud))..createSync();
      File(p.join(backup.path, 'committed')).writeAsStringSync('1');
      final source = File(p.join(backup.path, '0'))
        ..writeAsStringSync('dictionary mirror source');
      final dictionary = File(p.join(library, 'lexical.db'))
        ..writeAsStringSync('old dictionary');
      final catalogSource = p.join(mirror, 'catalog.db');
      final catalog = sqlite3.sqlite3.open(catalogSource);
      // A valid legacy catalog need not carry version/schema metadata.
      catalog.execute(
        'CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT)',
      );
      catalog.execute("INSERT INTO books VALUES (1, 'legacy catalog')");
      catalog.close();
      await File(
        p.join(mirror, CompanionMirrorManifest.fileName),
      ).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          // No Talmud entry: its interrupted cleanup still owns the source.
          'dictionary': {
            'fileName': source.path,
            'size': source.lengthSync(),
            'tag': 'new',
          },
          'catalog': {
            'fileName': 'catalog.db',
            'size': File(catalogSource).lengthSync(),
            'version': 2,
          },
        }),
      );
      final report = await const CompanionAssetsInstaller().install(
        mirrorDir: mirror,
        dbPath: dbPath,
      );
      expect(
        report.outcomes[CompanionAsset.dictionary],
        CompanionInstallOutcome.failed,
      );
      expect(
        report.outcomes[CompanionAsset.talmud],
        CompanionInstallOutcome.failed,
      );
      expect(
        report.outcomes[CompanionAsset.catalog],
        CompanionInstallOutcome.installed,
      );
      expect(source.readAsStringSync(), 'dictionary mirror source');
      expect(dictionary.readAsStringSync(), 'old dictionary');
      expect(backup.existsSync(), isTrue);
      expect(File(dbPath).readAsStringSync(), 'live library');
    },
  );
}
