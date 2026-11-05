import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/db_fixtures.dart';
import 'support/zstd_fixtures.dart';

void main() {
  final bindings = nativeZstd();
  late Directory temp;
  late String dbPath;
  late LibraryUpdateApplier applier;
  const recovery = OfflineLibraryDbRecoveryService();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('offline-streaming-');
    dbPath = p.join(temp.path, 'seforim.db');
    applier = LibraryUpdateApplier(processGuard: const _ClosedGuard());
  });

  tearDown(() async {
    applier.dispose();
    await temp.delete(recursive: true);
  });

  String hashOf(String path) {
    final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      return const LogicalContentHasher().compute(
        db,
        tableOrder: kHashTableOrderSchema2,
        rowOrder: null,
      );
    } finally {
      db.close();
    }
  }

  PatchEdge makeEdge({bool wrongOutputHash = false, bool large = false}) {
    writeSchema2Db(
      dbPath,
      version: 1,
      rows: [
        [1, 'one'],
      ],
    );
    final name = large ? base64Encode(pseudoRandomBytes(512 << 10)) : 'two';
    final expected = writeSchema2Db(
      p.join(temp.path, 'expected.db'),
      version: 2,
      rows: [
        [1, 'one'],
        [2, name],
      ],
    );
    return buildSchema2PatchEdge(
      bindings!,
      temp.path,
      from: 1,
      to: 2,
      upsertRows: [
        [2, name],
      ],
      fromHash: hashOf(dbPath),
      toHash: hashOf(expected),
      uncompressedSha256Override: wrongOutputHash ? '0' * 64 : null,
    );
  }

  LibraryUpdatePlan remotePlan(PatchEdge edge, _FileServer server) {
    final file = edge.manifest.patchFiles.single;
    return LibraryUpdatePlan.delta(
      localVersion: 1,
      targetVersion: 2,
      steps: [
        PatchEdge(
          manifest: edge.manifest,
          patchFileUrls: {file.file: server.url},
          manifestUrl: 'fixture.json',
        ),
      ],
    );
  }

  LibraryUpdatePlan fullPlan(_FileServer server) =>
      LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 2,
        asset: ReleaseAsset(
          name: 'seforim.db.zst',
          downloadUrl: server.url,
          size: server.bytes.length,
          digest: 'sha256:${sha256.convert(server.bytes)}',
          id: 71,
        ),
        releaseTag: 'v2',
      );

  void assertNoIncompleteInstall() {
    expect(File('$dbPath.new').existsSync(), isFalse);
    expect(File('$dbPath.old').existsSync(), isFalse);
    expect(File(recovery.markerPathFor(dbPath)).existsSync(), isFalse);
  }

  for (final suffix in [
    '.new',
    '.old',
    '.download.zst',
    '.download.zst.resume',
    '.lock',
  ]) {
    test('local full source cannot alias owned update file $suffix', () async {
      File(dbPath).writeAsStringSync('live database');
      final source = File('$dbPath$suffix')
        ..writeAsStringSync('source archive');
      final sourcePath = Platform.isWindows
          ? source.path
          : (Link(
              p.join(temp.path, 'mirror.zst'),
            )..createSync(source.path)).path;
      final plan = LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 2,
        asset: ReleaseAsset(
          name: 'full.zst',
          downloadUrl: sourcePath,
          size: source.lengthSync(),
          id: 9,
        ),
        releaseTag: 'v2',
      );
      await expectLater(
        applier.applyFullDownload(plan: plan, dbPath: dbPath),
        throwsArgumentError,
      );
      expect(File(dbPath).readAsStringSync(), 'live database');
      expect(source.readAsStringSync(), 'source archive');
      expect(File(recovery.markerPathFor(dbPath)).existsSync(), isFalse);
    });
  }

  test('local delta source inside update cache is never removed', () async {
    if (bindings == null) {
      markTestSkipped('native zstd unavailable');
      return;
    }
    final edge = makeEdge();
    final entry = edge.manifest.patchFiles.single;
    final cache = Directory(recovery.patchTmpDirFor(dbPath))..createSync();
    final source = File(edge.patchFileUrls.values.single).copySync(
      p.join(cache.path, '${extractedPatchFileName(entry.file)}.extracting'),
    );
    final original = source.readAsBytesSync();
    final plan = LibraryUpdatePlan.delta(
      localVersion: 1,
      targetVersion: 2,
      steps: [
        PatchEdge(
          manifest: edge.manifest,
          patchFileUrls: {entry.file: source.path},
          manifestUrl: 'fixture.json',
        ),
      ],
    );
    await expectLater(
      applier.applyDelta(plan: plan, dbPath: dbPath),
      throwsArgumentError,
    );
    expect(source.readAsBytesSync(), original);
    expect(hashOf(dbPath), edge.manifest.fromContentHash);
  });

  test(
    'remote delta streams native output and commits verified schema 2',
    () async {
      if (bindings == null) {
        markTestSkipped('native zstd unavailable');
        return;
      }
      final edge = makeEdge();
      final server = await _FileServer.start(
        File(edge.patchFileUrls.values.single).readAsBytesSync(),
      );
      addTearDown(server.close);
      final progress = <LibraryApplyProgress>[];
      await applier.applyDelta(
        plan: remotePlan(edge, server),
        dbPath: dbPath,
        onProgress: progress.add,
      );
      expect(hashOf(dbPath), edge.manifest.toContentHash);
      expect(
        progress.map((e) => e.stage),
        contains(LibraryApplyStage.decompressingPatch),
      );
      expect(recovery.unverifiedVersion(dbPath), isNull);
      assertNoIncompleteInstall();
    },
  );

  test('remote delta output hash failure preserves installed DB', () async {
    if (bindings == null) {
      markTestSkipped('native zstd unavailable');
      return;
    }
    final edge = makeEdge(wrongOutputHash: true);
    final before = File(dbPath).readAsBytesSync();
    final server = await _FileServer.start(
      File(edge.patchFileUrls.values.single).readAsBytesSync(),
    );
    addTearDown(server.close);
    await expectLater(
      applier.applyDelta(plan: remotePlan(edge, server), dbPath: dbPath),
      throwsA(isA<PatchDownloadException>()),
    );
    expect(File(dbPath).readAsBytesSync(), before);
    final cache = Directory(recovery.patchTmpDirFor(dbPath));
    expect(
      cache.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.db') || f.path.endsWith('.extracting'),
      ),
      isEmpty,
    );
    assertNoIncompleteInstall();
  });

  test(
    'cancel during remote delta extraction keeps download for retry',
    () async {
      if (bindings == null) {
        markTestSkipped('native zstd unavailable');
        return;
      }
      final edge = makeEdge();
      final before = File(dbPath).readAsBytesSync();
      final server = await _FileServer.start(
        File(edge.patchFileUrls.values.single).readAsBytesSync(),
      );
      addTearDown(server.close);
      final plan = remotePlan(edge, server);
      var cancelled = false;
      var applyingReported = false;
      await expectLater(
        applier.applyDelta(
          plan: plan,
          dbPath: dbPath,
          isCancelled: () => cancelled,
          onProgress: (progress) {
            if (progress.stage == LibraryApplyStage.decompressingPatch) {
              cancelled = true;
            }
            applyingReported |=
                progress.stage == LibraryApplyStage.applyingPatch;
          },
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(applyingReported, isFalse);
      expect(File(dbPath).readAsBytesSync(), before);
      final compressed = File(
        p.join(
          recovery.patchTmpDirFor(dbPath),
          edge.manifest.patchFiles.single.file,
        ),
      );
      expect(compressed.existsSync(), isTrue);
      expect(File('${compressed.path}.resume').existsSync(), isTrue);
      assertNoIncompleteInstall();
      final requestsBeforeRetry = server.requests;
      await applier.applyDelta(plan: plan, dbPath: dbPath);
      expect(server.requests, requestsBeforeRetry);
      expect(hashOf(dbPath), edge.manifest.toContentHash);
      expect(compressed.existsSync(), isFalse);
      assertNoIncompleteInstall();
    },
  );

  test(
    'remote delta resumes a dropped connection and verifies final DB',
    () async {
      if (bindings == null) {
        markTestSkipped('native zstd unavailable');
        return;
      }
      final edge = makeEdge(large: true);
      final server = await _FileServer.start(
        File(edge.patchFileUrls.values.single).readAsBytesSync(),
        dropFirst: true,
      );
      addTearDown(server.close);
      await applier.applyDelta(plan: remotePlan(edge, server), dbPath: dbPath);
      expect(server.requests, greaterThan(1));
      expect(server.offsets.any((offset) => offset > 0), isTrue);
      expect(hashOf(dbPath), edge.manifest.toContentHash);
      assertNoIncompleteInstall();
    },
  );

  test(
    'full output limit retains verified download and allows safe retry',
    () async {
      if (bindings == null) {
        markTestSkipped('native zstd unavailable');
        return;
      }
      final raw = buildVersionOnlyDb(temp.path, 2);
      File(dbPath).writeAsStringSync('old database');
      final server = await _FileServer.start(compressWithZstd(bindings, raw));
      addTearDown(server.close);
      applier.dispose();
      applier = LibraryUpdateApplier(
        processGuard: const _ClosedGuard(),
        maxFullDbBytes: raw.length - 1,
      );
      final plan = fullPlan(server);
      await expectLater(
        applier.applyFullDownload(plan: plan, dbPath: dbPath),
        throwsA(isA<ZstdOutputLimitExceeded>()),
      );
      expect(File(dbPath).readAsStringSync(), 'old database');
      expect(File('$dbPath.download.zst').existsSync(), isTrue);
      assertNoIncompleteInstall();
      final count = server.requests;
      applier.dispose();
      applier = LibraryUpdateApplier(processGuard: const _ClosedGuard());
      await applier.applyFullDownload(plan: plan, dbPath: dbPath);
      expect(server.requests, count);
      expect(File(dbPath).readAsBytesSync(), raw);
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
      assertNoIncompleteInstall();
    },
  );

  test(
    'cancel at final full install progress leaves original database intact',
    () async {
      if (bindings == null) {
        markTestSkipped('native zstd unavailable');
        return;
      }
      final raw = buildVersionOnlyDb(temp.path, 2);
      final source = File(p.join(temp.path, 'full.zst'))
        ..writeAsBytesSync(compressWithZstd(bindings, raw));
      File(dbPath).writeAsStringSync('old database');
      final plan = LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 2,
        asset: ReleaseAsset(
          name: 'full.zst',
          downloadUrl: source.path,
          size: source.lengthSync(),
          id: 9,
          digest: 'sha256:${sha256.convert(source.readAsBytesSync())}',
        ),
        releaseTag: 'v2',
      );
      var cancelled = false;
      await expectLater(
        applier.applyFullDownload(
          plan: plan,
          dbPath: dbPath,
          isCancelled: () => cancelled,
          onProgress: (progress) {
            if (progress.stage == LibraryApplyStage.writingFullDb) {
              cancelled = true;
            }
          },
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(File(dbPath).readAsStringSync(), 'old database');
      expect(source.existsSync(), isTrue);
      assertNoIncompleteInstall();
    },
  );
}

class _ClosedGuard extends OtzariaProcessGuard {
  const _ClosedGuard();
  @override
  Future<bool> isAnyRunning(List<String> processNames) async => false;
  @override
  Future<bool> isRunning(String processName) async => false;
}

class _FileServer {
  _FileServer(this._server, this.bytes, this.dropFirst) {
    _server.listen(_handle);
  }
  final HttpServer _server;
  final Uint8List bytes;
  final bool dropFirst;
  int requests = 0;
  final offsets = <int>[];
  String get url => 'http://127.0.0.1:${_server.port}/fixture.zst';
  static Future<_FileServer> start(
    Uint8List bytes, {
    bool dropFirst = false,
  }) async => _FileServer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    bytes,
    dropFirst,
  );
  Future<void> close() => _server.close(force: true);
  Future<void> _handle(HttpRequest request) async {
    requests++;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final offset = range == null
        ? 0
        : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    offsets.add(offset);
    final response = request.response;
    response.headers.set(HttpHeaders.etagHeader, '"fixture-v1"');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.contentLength = bytes.length - offset;
    if (offset > 0) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $offset-${bytes.length - 1}/${bytes.length}',
      );
    }
    if (dropFirst && requests == 1) {
      final socket = await response.detachSocket();
      socket.add(Uint8List.sublistView(bytes, 0, bytes.length ~/ 2));
      await socket.flush();
      socket.destroy();
      return;
    }
    response.add(Uint8List.sublistView(bytes, offset));
    await response.close();
  }
}
