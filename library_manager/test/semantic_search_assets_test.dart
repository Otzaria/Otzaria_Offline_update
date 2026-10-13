import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

const tag = 'v30-20260930165019';
const manifestName = 'otzaria-vectors-test-v30-base.manifest.json';

Map<String, Object?> manifest({
  String file = 'segment.oxv.zst',
  int version = 30,
}) => {
  'kind': 'base',
  'libraryReleaseTag': tag,
  'toLibraryVersion': version,
  'segment': {'size': 3},
  'identity': {
    'model': {
      'family_id':
          'ArieLLL123/judaic-semantic-round2-onnx-zayit@1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca',
      'tokenizer_checksum': SemanticSearchAssets.modelFiles[1].sha256,
    },
  },
  'files': [
    {
      'file': file,
      'size': 3,
      'sha256': Sha256Stream.ofBytes([1, 2, 3]),
    },
  ],
};

void main() {
  final modelFixture = Platform.environment['OTZARIA_SEMANTIC_MODEL_FIXTURE'];
  final vectorFixture = Platform.environment['OTZARIA_SEMANTIC_VECTOR_FIXTURE'];
  late Directory temp;
  late String mirror;
  late String db;
  late SemanticSearchAssets assets;
  var requests = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('semantic-assets-test-');
    mirror = p.join(temp.path, 'mirror');
    db = p.join(temp.path, 'machine', 'library', 'seforim.db');
    requests = 0;
    assets = SemanticSearchAssets(
      httpClient: MockClient((request) async {
        requests++;
        fail('offline method sent a request to ${request.url}');
      }),
    );
  });

  tearDown(() async {
    assets.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> writeMirror({int version = 30, bool corrupt = false}) async {
    final bytes = utf8.encode(jsonEncode(manifest(version: version)));
    final manifestFile = File(p.join(mirror, tag, 'vectors', manifestName));
    await manifestFile.parent.create(recursive: true);
    await manifestFile.writeAsBytes(corrupt ? [1] : bytes);
    await File(
      p.join(mirror, tag, 'vectors', 'segment.oxv.zst'),
    ).writeAsBytes([1, 2, 3]);
    for (final model in SemanticSearchAssets.modelFiles) {
      final file = File(
        p.join(mirror, tag, SemanticSearchAssets.modelFolder, model.name),
      );
      await file.parent.create(recursive: true);
      final handle = await file.open(mode: FileMode.write);
      try {
        await handle.truncate(model.size);
      } finally {
        await handle.close();
      }
    }
    await File(
      p.join(mirror, SemanticSearchAssets.manifestFileName),
    ).writeAsString(
      jsonEncode({
        'libraryTag': tag,
        'libraryVersion': 30,
        'manifestName': manifestName,
        'manifestSize': bytes.length,
        'manifestSha256': Sha256Stream.ofBytes(bytes),
      }),
    );
  }

  Future<bool> peek({
    int status = 200,
    String remoteTag = tag,
    String? digest,
    bool publishDigest = true,
    String? notes,
  }) async {
    final bytes = utf8.encode(jsonEncode(manifest()));
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'api.github.com');
      expect(
        request.url.path,
        '/repos/Otzaria/SeforimLibrary/releases/tags/vectors-$remoteTag',
      );
      expect(request.headers['User-Agent'], 'otzaria-launcher');
      return http.Response(
        jsonEncode({
          'tag_name': 'vectors-$remoteTag',
          'body': notes ?? '',
          'assets': [
            {
              'name': manifestName,
              'size': bytes.length,
              if (publishDigest)
                'digest': 'sha256:${digest ?? Sha256Stream.ofBytes(bytes)}',
            },
            {'name': 'segment.oxv.zst', 'size': 3},
          ],
        }),
        status,
      );
    });
    final online = SemanticSearchAssets(httpClient: client);
    try {
      return await online.peekPending(mirrorDir: mirror, libraryTag: remoteTag);
    } finally {
      expect(calls, 1);
      online.dispose();
      client.close();
    }
  }

  test(
    'light check recognizes a complete mirror without asset requests',
    () async {
      await writeMirror();
      expect(await peek(), isFalse);
    },
  );

  test(
    'light check detects republished vectors under the same library tag',
    () async {
      await writeMirror();
      expect(await peek(digest: List.filled(64, '1').join()), isTrue);
    },
  );

  test('light check detects vectors for a new library tag', () async {
    await writeMirror();
    expect(await peek(remoteTag: 'v31-20261005120000'), isTrue);
  });

  test('light check detects semantic data missing from the mirror', () async {
    expect(await peek(), isTrue);
  });

  test('light check detects incomplete model and vector mirrors', () async {
    await writeMirror();
    await File(
      p.join(mirror, tag, SemanticSearchAssets.modelFolder, 'LICENSE'),
    ).writeAsBytes([1]);
    expect(await peek(), isTrue);
    await writeMirror();
    await File(p.join(mirror, tag, 'vectors', 'segment.oxv.zst')).delete();
    expect(await peek(), isTrue);
  });

  test('light check treats unpublished vectors as no new download', () async {
    expect(await peek(status: 404), isFalse);
  });

  test(
    'light check never treats rate limit or unverifiable data as up to date',
    () async {
      await expectLater(peek(status: 403), throwsFormatException);
      await expectLater(peek(publishDigest: false), throwsFormatException);
    },
  );

  test('light check accepts the upstream release notes digest', () async {
    await writeMirror();
    final digest = Sha256Stream.ofBytes(utf8.encode(jsonEncode(manifest())));
    expect(
      await peek(publishDigest: false, notes: '$manifestName SHA-256: $digest'),
      isFalse,
    );
    await expectLater(
      peek(notes: '$manifestName SHA-256: ${List.filled(64, '2').join()}'),
      throwsFormatException,
    );
  });

  test(
    'empty mirror has no semantic update and never checks network',
    () async {
      expect(await assets.mirroredVersion(mirror), isNull);
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse,
      );
      expect(requests, 0);
    },
  );

  test('matching mirror offers import for missing local data', () async {
    await writeMirror();
    expect(await assets.mirroredVersion(mirror), 30);
    expect(
      await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
      isTrue,
    );
    expect(requests, 0);
  });

  test('installation checks unpacked vector space before writing', () async {
    await writeMirror();
    final root = p.dirname(p.dirname(db));
    final checked = <String>[];
    final installer = SemanticSearchAssets(
      freeBytesFor: (path) {
        checked.add(path);
        return 2;
      },
    );
    try {
      await expectLater(
        installer.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        throwsA(isA<FileSystemException>()),
      );
      expect(checked, contains(p.join(root, 'vectors')));
      expect(await Directory(root).exists(), isFalse);
      expect(requests, 0);
    } finally {
      installer.dispose();
    }
  });

  test('unknown free space does not block artifact verification', () async {
    await writeMirror();
    final installer = SemanticSearchAssets(freeBytesFor: (_) => null);
    try {
      await expectLater(
        installer.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        throwsFormatException,
      );
      expect(await Directory(p.dirname(db)).exists(), isFalse);
      expect(requests, 0);
    } finally {
      installer.dispose();
    }
  });

  test(
    'split vectors require space for every part in the work volume',
    () async {
      await writeMirror();
      final value = manifest();
      final files = value['files'] as List;
      files.add({
        'file': 'segment.oxv.zst.part-2',
        'size': 3,
        'sha256': Sha256Stream.ofBytes([4, 5, 6]),
      });
      final vectors = p.join(mirror, tag, 'vectors');
      await File(
        p.join(vectors, 'segment.oxv.zst.part-2'),
      ).writeAsBytes([4, 5, 6]);
      final bytes = utf8.encode(jsonEncode(value));
      await File(p.join(vectors, manifestName)).writeAsBytes(bytes);
      await File(
        p.join(mirror, SemanticSearchAssets.manifestFileName),
      ).writeAsString(
        jsonEncode({
          'libraryTag': tag,
          'libraryVersion': 30,
          'manifestName': manifestName,
          'manifestSize': bytes.length,
          'manifestSha256': Sha256Stream.ofBytes(bytes),
        }),
      );
      final installer = SemanticSearchAssets(
        freeBytesFor: (path) => path == Directory.systemTemp.path ? 5 : 100,
      );
      try {
        await expectLater(
          installer.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.path,
              'work volume',
              Directory.systemTemp.path,
            ),
          ),
        );
        expect(await Directory(p.dirname(p.dirname(db))).exists(), isFalse);
        expect(await File(p.join(vectors, 'segment.oxv.zst')).readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect(requests, 0);
      } finally {
        installer.dispose();
      }
    },
  );

  test('a mirror cannot offer vectors for another installed library', () async {
    await writeMirror();
    expect(
      await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 31),
      isFalse,
    );
  });

  test('a mirror with a missing vector archive is never offered', () async {
    await writeMirror();
    await File(p.join(mirror, tag, 'vectors', 'segment.oxv.zst')).delete();
    expect(
      await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
      isFalse,
    );
  });

  test('a mirror with a truncated model is never offered', () async {
    await writeMirror();
    await File(
      p.join(mirror, tag, SemanticSearchAssets.modelFolder, 'LICENSE'),
    ).writeAsBytes([1]);
    expect(
      await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
      isFalse,
    );
  });

  test('corrupt manifest is never offered or installed', () async {
    await writeMirror(corrupt: true);
    expect(
      await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
      isFalse,
    );
    await expectLater(
      assets.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
      throwsFormatException,
    );
    expect(
      await Directory(
        p.join(p.dirname(p.dirname(db)), 'semantic-import'),
      ).exists(),
      isFalse,
    );
    expect(requests, 0);
  });

  test('version mismatch inside authenticated manifest is rejected', () async {
    await writeMirror(version: 31);
    expect(
      await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
      isFalse,
    );
  });

  test(
    'installation rejects incomplete model without network or consent writes',
    () async {
      await writeMirror();
      await expectLater(
        assets.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        throwsFormatException,
      );
      expect(await Directory(p.dirname(p.dirname(db))).exists(), isFalse);
      expect(requests, 0);
    },
  );

  test('cancelled sync and install do nothing', () async {
    await expectLater(
      assets.sync(mirrorDir: mirror, libraryTag: tag, isCancelled: () => true),
      throwsA(isA<PatchDownloadCancelled>()),
    );
    await expectLater(
      assets.install(
        mirrorDir: mirror,
        dbPath: db,
        libraryVersion: 30,
        isCancelled: () => true,
      ),
      throwsA(isA<PatchDownloadCancelled>()),
    );
    expect(await Directory(mirror).exists(), isFalse);
    expect(requests, 0);
  });

  test('model file is reused from a previous generation', () async {
    final bytes = [9, 8, 7];
    final asset = (name: 'm.bin', size: 3, sha256: Sha256Stream.ofBytes(bytes));
    const old = 'v29-20260920000000';
    final source = File(
      p.join(mirror, old, SemanticSearchAssets.modelFolder, 'm.bin'),
    );
    await source.parent.create(recursive: true);
    await source.writeAsBytes(bytes);
    expect(
      await assets.reusableModelSource(
        mirrorDir: mirror,
        libraryTag: tag,
        file: asset,
      ),
      source.path,
    );
    await source.writeAsBytes([1, 1, 1]);
    expect(
      await assets.reusableModelSource(
        mirrorDir: mirror,
        libraryTag: tag,
        file: asset,
      ),
      isNull,
    );
  });

  test('pruning keeps only the current generation', () async {
    for (final name in ['v29-20260920000000', tag, 'v31-20261004170255']) {
      final file = File(p.join(mirror, name, 'vectors', 'x'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1]);
    }
    await File(p.join(mirror, 'semantic.json')).writeAsString('{}');
    await Directory(p.join(mirror, 'other')).create();
    await assets.pruneOldGenerations(mirror, tag);
    expect(await Directory(p.join(mirror, tag)).exists(), isTrue);
    expect(
      await Directory(p.join(mirror, 'v29-20260920000000')).exists(),
      isFalse,
    );
    expect(
      await Directory(p.join(mirror, 'v31-20261004170255')).exists(),
      isFalse,
    );
    expect(await Directory(p.join(mirror, 'other')).exists(), isTrue);
    expect(await File(p.join(mirror, 'semantic.json')).exists(), isTrue);
    await assets.pruneOldGenerations(p.join(temp.path, 'missing'), tag);
  });

  Future<void> rejectRelease({
    String? digest,
    String file = 'segment.oxv.zst',
    int version = 30,
    String? url,
  }) async {
    final bytes = utf8.encode(
      jsonEncode(manifest(file: file, version: version)),
    );
    var calls = 0;
    final online = SemanticSearchAssets(
      httpClient: MockClient((request) async {
        calls++;
        expect(request.headers['User-Agent'], 'otzaria-launcher');
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'tag_name': 'vectors-$tag',
              'body': '',
              'assets': [
                {
                  'name': manifestName,
                  'size': bytes.length,
                  if (digest != null) 'digest': 'sha256:$digest',
                  'browser_download_url':
                      url ??
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$manifestName',
                },
              ],
            }),
            200,
          );
        }
        expect(request.url.pathSegments.last, manifestName);
        return http.Response.bytes(bytes, 200);
      }),
    );
    try {
      await expectLater(
        online.sync(mirrorDir: mirror, libraryTag: tag),
        throwsFormatException,
      );
      expect(calls, lessThanOrEqualTo(2));
      expect(
        await File(
          p.join(mirror, SemanticSearchAssets.manifestFileName),
        ).exists(),
        isFalse,
      );
    } finally {
      online.dispose();
    }
  }

  test('release without a published manifest digest is rejected', () async {
    await rejectRelease();
  });

  test(
    'published digest mismatch is rejected before large model downloads',
    () async {
      await rejectRelease(digest: List.filled(64, '0').join());
    },
  );

  test('manifest URLs outside the expected release are rejected', () async {
    await rejectRelease(url: 'https://example.com/$manifestName');
  });

  test(
    'traversal filename inside a digest verified manifest is rejected',
    () async {
      final value = manifest(file: '../segment.oxv.zst');
      await rejectRelease(
        file: '../segment.oxv.zst',
        digest: Sha256Stream.ofBytes(utf8.encode(jsonEncode(value))),
      );
    },
  );

  test('digest verified manifest must target the requested library', () async {
    final value = manifest(version: 31);
    await rejectRelease(
      version: 31,
      digest: Sha256Stream.ofBytes(utf8.encode(jsonEncode(value))),
    );
  });

  test(
    'real pinned models sync and staging never counts as installation',
    () async {
      final bytes = utf8.encode(jsonEncode(manifest()));
      final digest = Sha256Stream.ofBytes(bytes);
      final progress = <(int, int?)>[];
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'tag_name': 'vectors-$tag',
              'assets': [
                {
                  'name': manifestName,
                  'size': bytes.length,
                  'digest': 'sha256:$digest',
                  'browser_download_url':
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$manifestName',
                },
                {
                  'name': 'segment.oxv.zst',
                  'size': 3,
                  'browser_download_url':
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/segment.oxv.zst',
                },
              ],
            }),
            200,
          );
        }
        final name = request.url.pathSegments.last;
        expect(
          await File(
            p.join(mirror, SemanticSearchAssets.manifestFileName),
          ).exists(),
          isFalse,
        );
        if (name == manifestName) return http.Response.bytes(bytes, 200);
        if (name == 'segment.oxv.zst') {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response.bytes(
          await File(p.join(modelFixture!, name)).readAsBytes(),
          200,
        );
      });
      final online = SemanticSearchAssets(httpClient: client);
      try {
        await online.sync(
          mirrorDir: mirror,
          libraryTag: tag,
          onBytesProgress: (received, total) => progress.add((received, total)),
        );
      } finally {
        online.dispose();
        client.close();
      }
      expect(progress.first.$1, 0);
      expect(progress.last.$1, progress.last.$2);
      expect(
        Directory(mirror).listSync().map((e) => p.basename(e.path)),
        isNot(contains(endsWith('.tmp'))),
      );
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue,
      );
      final root = p.dirname(p.dirname(db));
      final staged = p.join(root, 'semantic-import');
      for (final file in SemanticSearchAssets.modelFiles) {
        final target = File(
          p.join(staged, SemanticSearchAssets.modelFolder, file.name),
        );
        await target.parent.create(recursive: true);
        await File(
          p.join(mirror, tag, SemanticSearchAssets.modelFolder, file.name),
        ).copy(target.path);
      }
      for (final name in [manifestName, 'segment.oxv.zst']) {
        final target = File(p.join(staged, 'vectors', name));
        await target.parent.create(recursive: true);
        await File(p.join(mirror, tag, 'vectors', name)).copy(target.path);
      }
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue,
      );
      final direct = SemanticSearchAssets(
        nativeLibrary: ExternalLibrary.open(
          p.join(modelFixture!, 'search_engine.dll'),
        ),
      );
      try {
        await expectLater(
          direct.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
          throwsA(isA<SemanticError>()),
        );
        expect(
          await File(p.join(root, 'vectors', 'CURRENT')).exists(),
          isFalse,
        );
        for (final file in SemanticSearchAssets.modelFiles) {
          expect(
            await File(
              p.join(
                p.dirname(db),
                SemanticSearchAssets.modelFolder,
                file.name,
              ),
            ).exists(),
            isTrue,
          );
        }
      } finally {
        direct.dispose();
      }
      expect(requests, 0);
    },
    skip: modelFixture == null
        ? 'Set OTZARIA_SEMANTIC_MODEL_FIXTURE to the real pinned model release'
        : false,
  );
  test(
    'official native engine installs usable vectors at exact app paths',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  p.join(vectorFixture!, 'release.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final segmentBytes = await File(
        p.join(vectorFixture, 'segment.oxv'),
      ).readAsBytes();
      fixture['files'] = [
        {
          'file': 'segment.oxv',
          'compression': 'none',
          'uncompressedSha256': Sha256Stream.ofBytes(segmentBytes),
          'uncompressedSize': segmentBytes.length,
          'size': segmentBytes.length,
          'sha256': Sha256Stream.ofBytes(segmentBytes),
        },
      ];
      final manifestBytes = utf8.encode(jsonEncode(fixture));
      final mirrorVectors = Directory(p.join(mirror, tag, 'vectors'));
      await mirrorVectors.create(recursive: true);
      await File(
        p.join(mirrorVectors.path, 'segment.oxv'),
      ).writeAsBytes(segmentBytes);
      await File(
        p.join(mirrorVectors.path, manifestName),
      ).writeAsBytes(manifestBytes);
      await File(
        p.join(mirror, SemanticSearchAssets.manifestFileName),
      ).writeAsString(
        jsonEncode({
          'libraryTag': tag,
          'libraryVersion': 30,
          'manifestName': manifestName,
          'manifestSize': manifestBytes.length,
          'manifestSha256': Sha256Stream.ofBytes(manifestBytes),
        }),
      );
      for (final file in SemanticSearchAssets.modelFiles) {
        final target = File(
          p.join(mirror, tag, SemanticSearchAssets.modelFolder, file.name),
        );
        await target.parent.create(recursive: true);
        await File(p.join(modelFixture!, file.name)).copy(target.path);
      }
      final actualRoot = p.join(temp.path, 'configured-library-parent');
      final externalDb = p.join(
        temp.path,
        'other-location',
        'nested',
        'seforim.db',
      );
      final direct = SemanticSearchAssets(
        nativeLibrary: ExternalLibrary.open(
          p.join(modelFixture!, 'search_engine.dll'),
        ),
      );
      var activationChecks = 0;
      try {
        expect(
          await direct.pending(
            mirrorDir: mirror,
            dbPath: externalDb,
            libraryVersion: 30,
            vectorsRootPath: actualRoot,
          ),
          isTrue,
        );
        await direct.install(
          mirrorDir: mirror,
          dbPath: externalDb,
          libraryVersion: 30,
          vectorsRootPath: actualRoot,
          beforeActivate: () async {
            activationChecks++;
          },
        );
        expect(activationChecks, 2);
        expect(
          await File(p.join(actualRoot, 'vectors', 'CURRENT')).exists(),
          isTrue,
        );
        expect(
          await Directory(p.join(actualRoot, 'semantic-import')).exists(),
          isFalse,
        );
        expect(
          await Directory(
            p.join(p.dirname(p.dirname(externalDb)), 'vectors'),
          ).exists(),
          isFalse,
        );
        expect(
          await direct.pending(
            mirrorDir: mirror,
            dbPath: externalDb,
            libraryVersion: 30,
            vectorsRootPath: actualRoot,
          ),
          isFalse,
        );
        expect(
          await direct.pending(
            mirrorDir: mirror,
            dbPath: externalDb,
            libraryVersion: 30,
            vectorsRootPath: actualRoot,
            preferencesReady: false,
          ),
          isTrue,
        );
        final index = await Directory(
          p.join(temp.path, 'native-verifier-index'),
        ).create();
        final engine = await SearchEngine.newInstance(path: index.path);
        final cancellation = SemanticCancellationToken();
        try {
          final info = await engine.semanticVectorsInfo(
            vectorsDir: p.join(actualRoot, 'vectors'),
          );
          expect(info.present, isTrue);
          expect(info.libraryVersion, 30);
          expect(info.libraryReleaseTag, tag);
          expect(info.slotsLive, BigInt.one);
          await engine.verifySemanticVectors(
            vectorsDir: p.join(actualRoot, 'vectors'),
            cancellation: cancellation,
          );
        } finally {
          cancellation.dispose();
          engine.dispose();
        }
        await direct.install(
          mirrorDir: mirror,
          dbPath: externalDb,
          libraryVersion: 30,
          vectorsRootPath: actualRoot,
        );
        final foreignRoot = p.join(temp.path, 'unrelated-root');
        final unrelated = File(p.join(foreignRoot, 'vectors', 'personal.txt'));
        await unrelated.parent.create(recursive: true);
        await unrelated.writeAsString('preserve');
        await expectLater(
          direct.install(
            mirrorDir: mirror,
            dbPath: externalDb,
            libraryVersion: 30,
            vectorsRootPath: foreignRoot,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await unrelated.readAsString(), 'preserve');
      } finally {
        direct.dispose();
      }
    },
    skip: modelFixture == null || vectorFixture == null
        ? 'Set real model and native OXV fixture paths to exercise the production engine'
        : false,
  );

  const oldTag = 'v29-20260920000000';
  const partialTag = 'v28-20260910000000';
  final modelSkip = modelFixture == null
      ? 'Set OTZARIA_SEMANTIC_MODEL_FIXTURE to the real pinned model release'
      : false;

  Future<void> seedGeneration(
    String name, {
    bool models = false,
    bool vectors = true,
  }) async {
    if (vectors) {
      final file = File(p.join(mirror, name, 'vectors', 'old.bin'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([5, 5, 5]);
    }
    if (!models) return;
    for (final model in SemanticSearchAssets.modelFiles) {
      final target = File(
        p.join(mirror, name, SemanticSearchAssets.modelFolder, model.name),
      );
      await target.parent.create(recursive: true);
      await File(p.join(modelFixture!, model.name)).copy(target.path);
    }
  }

  Future<void> writeOldPointer() => File(
    p.join(mirror, SemanticSearchAssets.manifestFileName),
  ).writeAsString(jsonEncode({'libraryTag': oldTag, 'stale': true}));

  Future<String> pointerTag() async =>
      (jsonDecode(
                await File(
                  p.join(mirror, SemanticSearchAssets.manifestFileName),
                ).readAsString(),
              )
              as Map)['libraryTag']
          as String;

  MockClient releaseClient({
    required List<Uri> modelRequests,
    int segmentStatus = 200,
  }) {
    final bytes = utf8.encode(jsonEncode(manifest()));
    return MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(
          jsonEncode({
            'tag_name': 'vectors-$tag',
            'assets': [
              {
                'name': manifestName,
                'size': bytes.length,
                'digest': 'sha256:${Sha256Stream.ofBytes(bytes)}',
                'browser_download_url':
                    'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$manifestName',
              },
              {
                'name': 'segment.oxv.zst',
                'size': 3,
                'browser_download_url':
                    'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/segment.oxv.zst',
              },
            ],
          }),
          200,
        );
      }
      final name = request.url.pathSegments.last;
      if (name == manifestName) return http.Response.bytes(bytes, 200);
      if (name == 'segment.oxv.zst') {
        return segmentStatus == 200
            ? http.Response.bytes([1, 2, 3], 200)
            : http.Response('', segmentStatus);
      }
      modelRequests.add(request.url);
      return http.Response('', 404);
    });
  }

  Future<void> runSync(
    MockClient client, {
    bool Function()? isCancelled,
  }) async {
    final online = SemanticSearchAssets(httpClient: client);
    try {
      await online.sync(
        mirrorDir: mirror,
        libraryTag: tag,
        isCancelled: isCancelled,
      );
    } finally {
      online.dispose();
      client.close();
    }
  }

  Future<void> syncWithStalledSegment(Duration stallTimeout) async {
    await seedGeneration(oldTag, models: true);
    final inner = releaseClient(modelRequests: <Uri>[]);
    final client = _StallingSegmentClient(
      inner,
      const Duration(milliseconds: 400),
    );
    final online = SemanticSearchAssets(httpClient: client)
      ..stallTimeout = stallTimeout;
    try {
      await online.sync(mirrorDir: mirror, libraryTag: tag);
    } finally {
      online.dispose();
      client.close();
    }
  }

  test(
    'sync gives up when the download stalls longer than the limit',
    skip: modelSkip,
    () async {
      await expectLater(
        syncWithStalledSegment(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test(
    'sync waits out a stall shorter than the limit',
    skip: modelSkip,
    () async {
      await syncWithStalledSegment(const Duration(seconds: 5));
      expect(await pointerTag(), tag);
    },
  );

  test('the default stall limit tolerates a slow CDN', () {
    expect(
      SemanticSearchAssets().stallTimeout,
      greaterThanOrEqualTo(const Duration(minutes: 2)),
    );
  });

  test(
    'sync copies models from the old generation, then prunes it and repoints',
    () async {
      await seedGeneration(oldTag, models: true);
      await File(
        p.join(mirror, partialTag, 'vectors', 'half.part'),
      ).create(recursive: true);
      await Directory(p.join(mirror, 'other')).create();
      await writeOldPointer();
      final modelRequests = <Uri>[];
      await runSync(releaseClient(modelRequests: modelRequests));
      expect(modelRequests, isEmpty);
      expect(await pointerTag(), tag);
      expect(await Directory(p.join(mirror, oldTag)).exists(), isFalse);
      expect(await Directory(p.join(mirror, partialTag)).exists(), isFalse);
      expect(await Directory(p.join(mirror, 'other')).exists(), isTrue);
      for (final model in SemanticSearchAssets.modelFiles) {
        final copied = File(
          p.join(mirror, tag, SemanticSearchAssets.modelFolder, model.name),
        );
        expect(Sha256Stream.ofBytes(await copied.readAsBytes()), model.sha256);
        expect(File('${copied.path}.tmp').existsSync(), isFalse);
      }
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue,
      );
    },
    skip: modelSkip,
  );

  test(
    'a failed prune does not fail a successful sync',
    () async {
      await seedGeneration(oldTag, models: true);
      await writeOldPointer();
      final locked = await File(
        p.join(mirror, oldTag, 'vectors', 'old.bin'),
      ).open();
      try {
        await runSync(releaseClient(modelRequests: <Uri>[]));
        expect(await pointerTag(), tag);
        expect(
          File(p.join(mirror, oldTag, 'vectors', 'old.bin')).existsSync(),
          isTrue,
        );
      } finally {
        await locked.close();
      }
      await assets.pruneOldGenerations(mirror, tag);
      expect(await Directory(p.join(mirror, oldTag)).exists(), isFalse);
    },
    skip: !Platform.isWindows
        ? 'file locking by an open handle is Windows-specific'
        : modelSkip,
  );

  test(
    'pruneOldGenerations survives a locked generation and removes the rest',
    () async {
      await seedGeneration(oldTag);
      await seedGeneration(partialTag);
      final locked = await File(
        p.join(mirror, oldTag, 'vectors', 'old.bin'),
      ).open();
      try {
        await assets.pruneOldGenerations(mirror, tag);
        expect(await Directory(p.join(mirror, oldTag)).exists(), isTrue);
        expect(await Directory(p.join(mirror, partialTag)).exists(), isFalse);
      } finally {
        await locked.close();
      }
    },
    skip: !Platform.isWindows
        ? 'file locking by an open handle is Windows-specific'
        : false,
  );

  test(
    'sync failing at the model download keeps old and partial generations',
    () async {
      await seedGeneration(oldTag);
      await File(
        p.join(mirror, partialTag, 'vectors', 'half.part'),
      ).create(recursive: true);
      await writeOldPointer();
      final modelRequests = <Uri>[];
      await expectLater(
        runSync(releaseClient(modelRequests: modelRequests)),
        throwsA(anything),
      );
      expect(modelRequests, isNotEmpty);
      expect(await pointerTag(), oldTag);
      expect(
        File(p.join(mirror, oldTag, 'vectors', 'old.bin')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(mirror, partialTag, 'vectors', 'half.part')).existsSync(),
        isTrue,
      );
    },
  );

  test('sync failing at the vector download keeps old generations', () async {
    await seedGeneration(oldTag, models: true);
    await File(
      p.join(mirror, partialTag, 'vectors', 'half.part'),
    ).create(recursive: true);
    await writeOldPointer();
    await expectLater(
      runSync(releaseClient(modelRequests: <Uri>[], segmentStatus: 500)),
      throwsA(anything),
    );
    expect(await pointerTag(), oldTag);
    expect(Directory(p.join(mirror, oldTag)).existsSync(), isTrue);
    expect(Directory(p.join(mirror, partialTag)).existsSync(), isTrue);
  }, skip: modelSkip);

  test(
    'cancelling between model copies leaves no model-looking temp file',
    () async {
      await seedGeneration(oldTag, models: true);
      await writeOldPointer();
      final target = Directory(
        p.join(mirror, tag, SemanticSearchAssets.modelFolder),
      );
      final stale = File(
        p.join(target.path, '${SemanticSearchAssets.modelFiles[0].name}.tmp'),
      );
      await stale.create(recursive: true);
      await stale.writeAsBytes([1, 2, 3]);
      var copied = 0;
      bool cancelAfterFirstCopy() {
        copied = target
            .listSync()
            .where((e) => e is File && !e.path.endsWith('.tmp'))
            .length;
        return copied >= 1;
      }

      await expectLater(
        runSync(
          releaseClient(modelRequests: <Uri>[]),
          isCancelled: cancelAfterFirstCopy,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(copied, 1);
      expect(await pointerTag(), oldTag);
      expect(Directory(p.join(mirror, oldTag)).existsSync(), isTrue);
      for (final model in SemanticSearchAssets.modelFiles) {
        final found = await assets.reusableModelSource(
          mirrorDir: mirror,
          libraryTag: tag,
          file: model,
        );
        expect(found, isNot(endsWith('.tmp')));
      }
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse,
      );
      await runSync(releaseClient(modelRequests: <Uri>[]));
      expect(await pointerTag(), tag);
      expect(
        target.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.tmp'),
        ),
        isEmpty,
      );
    },
    skip: modelSkip,
  );

  test(
    'missing active vectors decide pending without reading local models',
    () async {
      await writeMirror();
      final model = File(
        p.join(
          p.dirname(db),
          SemanticSearchAssets.modelFolder,
          SemanticSearchAssets.modelFiles[0].name,
        ),
      );
      await model.parent.create(recursive: true);
      final handle = await model.open(mode: FileMode.write);
      try {
        await handle.truncate(SemanticSearchAssets.modelFiles[0].size);
      } finally {
        await handle.close();
      }
      await Process.run('chmod', ['000', model.path]);
      addTearDown(() => Process.run('chmod', ['644', model.path]));
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue,
      );
    },
    skip: Platform.isWindows ? 'relies on POSIX file permissions' : false,
  );

  Future<void> syncWithLargeVectors({
    required DownloadScheduler scheduler,
    required List<String> requested,
    void Function(int inFlight)? onInFlight,
    List<int>? onDisk,
    void Function(int downloaded, int? total)? onBytesProgress,
  }) async {
    const vectorName = 'segment.oxv.zst';
    const vectorSize = 50000000;
    final large = manifest();
    large['files'] = [
      {'file': vectorName, 'size': vectorSize, 'sha256': '1' * 64},
      if (onDisk != null)
        {
          'file': 'complete.oxv.zst',
          'size': onDisk.length,
          'sha256': Sha256Stream.ofBytes(onDisk),
        },
    ];
    if (onDisk != null) {
      final complete = File(p.join(mirror, tag, 'vectors', 'complete.oxv.zst'));
      await complete.parent.create(recursive: true);
      await complete.writeAsBytes(onDisk);
    }
    final bytes = utf8.encode(jsonEncode(large));
    var inFlight = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(
          jsonEncode({
            'tag_name': 'vectors-$tag',
            'assets': [
              {
                'name': manifestName,
                'size': bytes.length,
                'digest': 'sha256:${Sha256Stream.ofBytes(bytes)}',
                'browser_download_url':
                    'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$manifestName',
              },
              {
                'name': vectorName,
                'size': vectorSize,
                'browser_download_url':
                    'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$vectorName',
              },
              if (onDisk != null)
                {
                  'name': 'complete.oxv.zst',
                  'size': onDisk.length,
                  'browser_download_url':
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/complete.oxv.zst',
                },
            ],
          }),
          200,
        );
      }
      final name = request.url.pathSegments.last;
      if (name == manifestName) return http.Response.bytes(bytes, 200);
      requested.add(name);
      inFlight++;
      onInFlight?.call(inFlight);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      inFlight--;
      return http.Response('', 404);
    });
    final online = SemanticSearchAssets(
      httpClient: client,
      scheduler: scheduler,
    );
    try {
      await expectLater(
        online.sync(
          mirrorDir: mirror,
          libraryTag: tag,
          onBytesProgress: onBytesProgress,
        ),
        throwsA(anything),
      );
    } finally {
      online.dispose();
      client.close();
    }
    expect(
      await File(
        p.join(mirror, SemanticSearchAssets.manifestFileName),
      ).exists(),
      isFalse,
    );
  }

  test('sync starts the largest smart-search download first', () async {
    final requested = <String>[];
    await syncWithLargeVectors(
      scheduler: DownloadScheduler(maxConcurrent: 1),
      requested: requested,
    );
    expect(requested, ['segment.oxv.zst']);
  });

  test(
    'sync deducts complete files from the total before the first byte',
    () async {
      final onDisk = List<int>.generate(4096, (i) => i % 251);
      final totals = <int?>[];
      await syncWithLargeVectors(
        scheduler: DownloadScheduler(maxConcurrent: 1),
        requested: <String>[],
        onDisk: onDisk,
        onBytesProgress: (_, total) => totals.add(total),
      );
      final planned = [
        for (final file in SemanticSearchAssets.modelFiles)
          file.name == 'tokenizer.json'
              ? SemanticSearchAssets.tokenizerZip
              : file,
      ].fold<int>(50000000, (sum, file) => sum + file.size);
      expect(totals, isNotEmpty);
      expect(totals.toSet(), {planned});
    },
  );

  test('sync downloads models and vectors in parallel', () async {
    final requested = <String>[];
    var peak = 0;
    await syncWithLargeVectors(
      scheduler: DownloadScheduler(),
      requested: requested,
      onInFlight: (inFlight) {
        if (inFlight > peak) peak = inFlight;
      },
    );
    expect(peak, greaterThan(1));
  });

  test(
    'unreadable smart-search files do not abort the pending check',
    () async {
      await writeMirror();
      final local = File(
        p.join(
          p.dirname(db),
          SemanticSearchAssets.modelFolder,
          SemanticSearchAssets.modelFiles.first.name,
        ),
      );
      await local.parent.create(recursive: true);
      final handle = await local.open(mode: FileMode.write);
      try {
        await handle.truncate(SemanticSearchAssets.modelFiles.first.size);
      } finally {
        await handle.close();
      }
      await Process.run('chmod', ['000', local.path]);
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue,
      );
      final mirrored = File(p.join(mirror, tag, 'vectors', manifestName));
      await Process.run('chmod', ['000', mirrored.path]);
      expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse,
      );
      expect(requests, 0);
    },
    skip: Platform.isWindows ? 'chmod permissions are POSIX-specific' : false,
  );

  Future<List<int>> writePartedMirror({bool corruptLast = false}) async {
    final parts = {
      'segment.oxv.part-000': List<int>.generate(70000, (i) => i % 251),
      'segment.oxv.part-001': List<int>.generate(50000, (i) => i % 241),
    };
    final value = manifest();
    value['files'] = [
      for (final entry in parts.entries)
        {
          'file': entry.key,
          'size': entry.value.length,
          'sha256': Sha256Stream.ofBytes(entry.value),
        },
    ];
    final bytes = utf8.encode(jsonEncode(value));
    final vectors = Directory(p.join(mirror, tag, 'vectors'));
    await vectors.create(recursive: true);
    await File(p.join(vectors.path, manifestName)).writeAsBytes(bytes);
    for (final entry in parts.entries) {
      final content = [...entry.value];
      if (corruptLast && entry.key == parts.keys.last) content[0] ^= 1;
      await File(p.join(vectors.path, entry.key)).writeAsBytes(content);
    }
    for (final model in SemanticSearchAssets.modelFiles) {
      final target = File(
        p.join(mirror, tag, SemanticSearchAssets.modelFolder, model.name),
      );
      await target.parent.create(recursive: true);
      await File(p.join(modelFixture!, model.name)).copy(target.path);
    }
    await File(
      p.join(mirror, SemanticSearchAssets.manifestFileName),
    ).writeAsString(
      jsonEncode({
        'libraryTag': tag,
        'libraryVersion': 30,
        'manifestName': manifestName,
        'manifestSize': bytes.length,
        'manifestSha256': Sha256Stream.ofBytes(bytes),
      }),
    );
    return [for (final part in parts.values) ...part];
  }

  test(
    'a corrupt vector part is rejected while joining, before any install write',
    () async {
      await writePartedMirror(corruptLast: true);
      final root = Directory(p.join(temp.path, 'library-parent'));
      var activations = 0;
      await expectLater(
        assets.install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: root.path,
          beforeActivate: () async => activations++,
        ),
        throwsFormatException,
      );
      expect(activations, 0);
      expect(await root.exists(), isFalse);
      expect(await Directory(p.dirname(db)).exists(), isFalse);
      expect(requests, 0);
    },
    skip: modelSkip,
  );

  test(
    'vector parts are joined in a system temp work directory before activation',
    () async {
      final expected = await writePartedMirror();
      final root = Directory(p.join(temp.path, 'library-parent'));
      await root.create();
      Future<Set<String>> workDirectories() => Directory.systemTemp
          .list()
          .where(
            (entry) =>
                p.basename(entry.path).startsWith('otzaria-semantic-install-'),
          )
          .map((entry) => entry.path)
          .toSet();
      final before = await workDirectories();
      String? workPath;
      List<int>? joined;
      await expectLater(
        assets.install(
          mirrorDir: mirror,
          dbPath: db,
          libraryVersion: 30,
          vectorsRootPath: root.path,
          beforeActivate: () async {
            workPath = (await workDirectories()).difference(before).single;
            joined = await File(p.join(workPath!, 'segment.oxv')).readAsBytes();
            throw StateError('stop before activation');
          },
        ),
        throwsStateError,
      );
      expect(joined, expected);
      expect(await Directory(workPath!).exists(), isFalse);
      expect(await root.list().toList(), isEmpty);
      expect(await Directory(p.dirname(db)).exists(), isFalse);
    },
    skip: modelSkip,
  );

  group('concatenateVectorParts', () {
    late String vectors;
    late String work;

    setUp(() async {
      vectors = p.join(temp.path, 'vectors');
      work = p.join(temp.path, 'work');
      await Directory(vectors).create(recursive: true);
      await Directory(work).create(recursive: true);
    });

    Future<List<SemanticAsset>> writeParts(
      Map<String, List<int>> parts, {
      Set<String> corrupt = const {},
    }) async {
      final assets = <SemanticAsset>[];
      for (final entry in parts.entries) {
        assets.add((
          name: entry.key,
          size: entry.value.length,
          sha256: Sha256Stream.ofBytes(entry.value),
        ));
        final content = [...entry.value];
        if (corrupt.contains(entry.key)) content[content.length - 1] ^= 1;
        await File(p.join(vectors, entry.key)).writeAsBytes(content);
      }
      return assets;
    }

    test(
      'joins the parts in order under the name without the part suffix',
      () async {
        final first = List<int>.generate(70000, (i) => i % 251);
        final second = List<int>.generate(50000, (i) => i % 241);
        final parts = await writeParts({
          'segment.oxv.part-000': first,
          'segment.oxv.part-001': second,
        });

        final joined = await assets.concatenateVectorParts(
          vectorsDir: vectors,
          parts: parts,
          workDir: work,
        );

        expect(joined, p.join(work, 'segment.oxv'));
        expect(await File(joined).readAsBytes(), [...first, ...second]);
        expect(requests, 0);
      },
    );

    test('a part above the flush threshold is copied whole', () async {
      final big = List<int>.generate(17 * 1024 * 1024, (i) => i % 253);
      final tail = List<int>.generate(1000, (i) => i % 7);
      final parts = await writeParts({
        'segment.oxv.part-000': big,
        'segment.oxv.part-001': tail,
      });

      final joined = await assets.concatenateVectorParts(
        vectorsDir: vectors,
        parts: parts,
        workDir: work,
      );

      final bytes = await File(joined).readAsBytes();
      expect(bytes.length, big.length + tail.length);
      expect(
        Sha256Stream.ofBytes(bytes),
        Sha256Stream.ofBytes([...big, ...tail]),
      );
    });

    test('a corrupt later part is rejected while joining', () async {
      final parts = await writeParts(
        {
          'segment.oxv.part-000': List<int>.generate(4000, (i) => i % 251),
          'segment.oxv.part-001': List<int>.generate(3000, (i) => i % 241),
        },
        corrupt: {'segment.oxv.part-001'},
      );

      await expectLater(
        assets.concatenateVectorParts(
          vectorsDir: vectors,
          parts: parts,
          workDir: work,
        ),
        throwsFormatException,
      );
    });

    test('a missing or truncated part is rejected', () async {
      final parts = await writeParts({
        'segment.oxv.part-000': List<int>.generate(4000, (i) => i % 251),
        'segment.oxv.part-001': List<int>.generate(3000, (i) => i % 241),
      });
      await File(
        p.join(vectors, 'segment.oxv.part-001'),
      ).writeAsBytes(List<int>.filled(10, 0));

      await expectLater(
        assets.concatenateVectorParts(
          vectorsDir: vectors,
          parts: parts,
          workDir: work,
        ),
        throwsFormatException,
      );

      await File(p.join(vectors, 'segment.oxv.part-001')).delete();
      await expectLater(
        assets.concatenateVectorParts(
          vectorsDir: vectors,
          parts: parts,
          workDir: work,
        ),
        throwsFormatException,
      );
    });

    test('cancellation stops the join', () async {
      final parts = await writeParts({
        'segment.oxv.part-000': List<int>.generate(4000, (i) => i % 251),
        'segment.oxv.part-001': List<int>.generate(3000, (i) => i % 241),
      });

      await expectLater(
        assets.concatenateVectorParts(
          vectorsDir: vectors,
          parts: parts,
          workDir: work,
          isCancelled: () => true,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
    });
  });

  test(
    'model copy checks free space in the model folder before writing',
    () async {
      await writePartedMirror();
      final root = p.join(temp.path, 'library-parent');
      final modelDir = p.join(p.dirname(db), SemanticSearchAssets.modelFolder);
      final checked = <String>[];
      final installer = SemanticSearchAssets(
        freeBytesFor: (path) {
          checked.add(path);
          return path == modelDir ? 1 : 1 << 40;
        },
      );
      try {
        await expectLater(
          installer.install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            vectorsRootPath: root,
          ),
          throwsA(
            isA<FileSystemException>().having(
              (error) => error.path,
              'model folder',
              modelDir,
            ),
          ),
        );
        expect(checked, contains(modelDir));
        expect(
          await Directory(
            modelDir,
          ).list().where((entry) => entry.path.endsWith('.tmp')).toList(),
          isEmpty,
        );
        expect(
          await Directory(p.join(root, 'vectors')).list().toList(),
          isEmpty,
        );
        expect(requests, 0);
      } finally {
        installer.dispose();
      }
    },
    skip: modelSkip,
  );

  test(
    'vectors space is checked again right before the native install',
    () async {
      await writePartedMirror();
      final root = p.join(temp.path, 'library-parent');
      final vectorsDir = p.join(root, 'vectors');
      var vectorChecks = 0;
      final installer = SemanticSearchAssets(
        nativeLibrary: ExternalLibrary.open(
          p.join(modelFixture!, 'search_engine.dll'),
        ),
        freeBytesFor: (path) {
          if (path != vectorsDir) return 1 << 40;
          vectorChecks++;
          return vectorChecks == 1 ? 1 << 40 : 1;
        },
      );
      try {
        await expectLater(
          installer.install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            vectorsRootPath: root,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(vectorChecks, 2);
        expect(await File(p.join(vectorsDir, 'CURRENT')).exists(), isFalse);
        expect(requests, 0);
      } finally {
        installer.dispose();
      }
    },
    skip: modelSkip,
  );

  test('pending מקומי אינו יוצר לקוח HTTP', () async {
    var created = 0;
    await http.runWithClient(
      () async {
        final local = SemanticSearchAssets();
        await local.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30);
        local.dispose();
      },
      () {
        created++;
        return MockClient((_) async => http.Response('', 500));
      },
    );
    expect(created, 0);
  });
}

class _StallingSegmentClient extends http.BaseClient {
  _StallingSegmentClient(this._inner, this._stall);

  final http.Client _inner;
  final Duration _stall;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (request.url.pathSegments.last != 'segment.oxv.zst') return response;
    final bytes = await response.stream.toBytes();
    return http.StreamedResponse(
      () async* {
        yield bytes.sublist(0, 1);
        await Future<void>.delayed(_stall);
        yield bytes.sublist(1);
      }(),
      response.statusCode,
      contentLength: bytes.length,
    );
  }

  @override
  void close() => _inner.close();
}
