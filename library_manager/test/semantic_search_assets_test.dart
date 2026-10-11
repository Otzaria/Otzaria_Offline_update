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
      expect(request.headers['User-Agent'], 'otzaria-offline-update');
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
        expect(request.headers['User-Agent'], 'otzaria-offline-update');
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
}
