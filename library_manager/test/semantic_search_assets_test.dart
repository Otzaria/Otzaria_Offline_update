import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

const tag = 'v30-20260930165019';
const manifestName = 'otzaria-vectors-test-v30-base.manifest.json';

Map<String, Object?> manifest(
        {String file = 'segment.oxv.zst', int version = 30}) =>
    {
      'kind': 'base',
      'libraryReleaseTag': tag,
      'toLibraryVersion': version,
      'segment': {'size': 3},
      'identity': {
        'model': {
          'family_id':
              'ArieLLL123/judaic-semantic-round2-onnx-zayit@1ec8dc68888bcea774ae9f735b2fe7cd9dc7f3ca',
          'tokenizer_checksum': SemanticSearchAssets.modelFiles[1].sha256,
        }
      },
      'files': [
        {
          'file': file,
          'size': 3,
          'sha256': Sha256Stream.ofBytes([1, 2, 3])
        }
      ],
    };

void main() {
  final modelFixture = Platform.environment['OTZARIA_SEMANTIC_MODEL_FIXTURE'];
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
    assets = SemanticSearchAssets(httpClient: MockClient((request) async {
      requests++;
      fail('offline method sent a request to ${request.url}');
    }));
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
    await File(p.join(mirror, tag, 'vectors', 'segment.oxv.zst'))
        .writeAsBytes([1, 2, 3]);
    for (final model in SemanticSearchAssets.modelFiles) {
      final file = File(
          p.join(mirror, tag, SemanticSearchAssets.modelFolder, model.name));
      await file.parent.create(recursive: true);
      final handle = await file.open(mode: FileMode.write);
      try {
        await handle.truncate(model.size);
      } finally {
        await handle.close();
      }
    }
    await File(p.join(mirror, SemanticSearchAssets.manifestFileName))
        .writeAsString(jsonEncode({
      'libraryTag': tag,
      'libraryVersion': 30,
      'manifestName': manifestName,
      'manifestSize': bytes.length,
      'manifestSha256': Sha256Stream.ofBytes(bytes),
    }));
  }

  Future<bool> peek(
      {int status = 200,
      String remoteTag = tag,
      String? digest,
      bool publishDigest = true,
      String? notes}) async {
    final bytes = utf8.encode(jsonEncode(manifest()));
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'api.github.com');
      expect(request.url.path,
          '/repos/Otzaria/SeforimLibrary/releases/tags/vectors-$remoteTag');
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
              {
                'name': 'segment.oxv.zst',
                'size': 3,
              }
            ],
          }),
          status);
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

  test('light check recognizes a complete mirror without asset requests',
      () async {
    await writeMirror();
    expect(await peek(), isFalse);
  });

  test('light check detects republished vectors under the same library tag',
      () async {
    await writeMirror();
    expect(await peek(digest: List.filled(64, '1').join()), isTrue);
  });

  test('light check detects vectors for a new library tag', () async {
    await writeMirror();
    expect(await peek(remoteTag: 'v31-20261005120000'), isTrue);
  });

  test('light check detects semantic data missing from the mirror', () async {
    expect(await peek(), isTrue);
  });

  test('light check detects incomplete model and vector mirrors', () async {
    await writeMirror();
    await File(p.join(mirror, tag, SemanticSearchAssets.modelFolder, 'LICENSE'))
        .writeAsBytes([1]);
    expect(await peek(), isTrue);
    await writeMirror();
    await File(p.join(mirror, tag, 'vectors', 'segment.oxv.zst')).delete();
    expect(await peek(), isTrue);
  });

  test('light check treats unpublished vectors as no new download', () async {
    expect(await peek(status: 404), isFalse);
  });

  test('light check never treats rate limit or unverifiable data as up to date',
      () async {
    await expectLater(peek(status: 403), throwsFormatException);
    await expectLater(peek(publishDigest: false), throwsFormatException);
  });

  test('light check accepts the upstream release notes digest', () async {
    await writeMirror();
    final digest = Sha256Stream.ofBytes(utf8.encode(jsonEncode(manifest())));
    expect(
        await peek(
            publishDigest: false, notes: '$manifestName SHA-256: $digest'),
        isFalse);
    await expectLater(
        peek(notes: '$manifestName SHA-256: ${List.filled(64, '2').join()}'),
        throwsFormatException);
  });

  test('empty mirror has no semantic update and never checks network',
      () async {
    expect(await assets.mirroredVersion(mirror), isNull);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
    expect(requests, 0);
  });

  test('matching mirror offers import for missing local data', () async {
    await writeMirror();
    expect(await assets.mirroredVersion(mirror), 30);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue);
    expect(requests, 0);
  });

  test('a mirror cannot offer vectors for another installed library', () async {
    await writeMirror();
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 31),
        isFalse);
  });

  test('a mirror with a missing vector archive is never offered', () async {
    await writeMirror();
    await File(p.join(mirror, tag, 'vectors', 'segment.oxv.zst')).delete();
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
  });

  test('a mirror with a truncated model is never offered', () async {
    await writeMirror();
    await File(p.join(mirror, tag, SemanticSearchAssets.modelFolder, 'LICENSE'))
        .writeAsBytes([1]);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
  });

  test('corrupt manifest is never offered or installed', () async {
    await writeMirror(corrupt: true);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
    await expectLater(
        assets.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        throwsFormatException);
    expect(
        await Directory(p.join(p.dirname(p.dirname(db)), 'semantic-import'))
            .exists(),
        isFalse);
    expect(requests, 0);
  });

  test('version mismatch inside authenticated manifest is rejected', () async {
    await writeMirror(version: 31);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
  });

  test(
      'installation rejects incomplete model without network or consent writes',
      () async {
    await writeMirror();
    await expectLater(
        assets.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        throwsFormatException);
    expect(await Directory(p.dirname(p.dirname(db))).exists(), isFalse);
    expect(requests, 0);
  });

  test('cancelled sync and install do nothing', () async {
    await expectLater(
        assets.sync(
            mirrorDir: mirror, libraryTag: tag, isCancelled: () => true),
        throwsA(isA<PatchDownloadCancelled>()));
    await expectLater(
        assets.install(
            mirrorDir: mirror,
            dbPath: db,
            libraryVersion: 30,
            isCancelled: () => true),
        throwsA(isA<PatchDownloadCancelled>()));
    expect(await Directory(mirror).exists(), isFalse);
    expect(requests, 0);
  });

  Future<void> rejectRelease(
      {String? digest,
      String file = 'segment.oxv.zst',
      int version = 30,
      String? url}) async {
    final bytes =
        utf8.encode(jsonEncode(manifest(file: file, version: version)));
    var calls = 0;
    final online = SemanticSearchAssets(httpClient: MockClient((request) async {
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
                  'browser_download_url': url ??
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$manifestName',
                }
              ],
            }),
            200);
      }
      expect(request.url.pathSegments.last, manifestName);
      return http.Response.bytes(bytes, 200);
    }));
    try {
      await expectLater(online.sync(mirrorDir: mirror, libraryTag: tag),
          throwsFormatException);
      expect(calls, lessThanOrEqualTo(2));
      expect(
          await File(p.join(mirror, SemanticSearchAssets.manifestFileName))
              .exists(),
          isFalse);
    } finally {
      online.dispose();
    }
  }

  test('release without a published manifest digest is rejected', () async {
    await rejectRelease();
  });

  test('published digest mismatch is rejected before large model downloads',
      () async {
    await rejectRelease(digest: List.filled(64, '0').join());
  });

  test('manifest URLs outside the expected release are rejected', () async {
    await rejectRelease(url: 'https://example.com/$manifestName');
  });

  test('traversal filename inside a digest verified manifest is rejected',
      () async {
    final value = manifest(file: '../segment.oxv.zst');
    await rejectRelease(
        file: '../segment.oxv.zst',
        digest: Sha256Stream.ofBytes(utf8.encode(jsonEncode(value))));
  });

  test('digest verified manifest must target the requested library', () async {
    final value = manifest(version: 31);
    await rejectRelease(
        version: 31,
        digest: Sha256Stream.ofBytes(utf8.encode(jsonEncode(value))));
  });

  test('real pinned models sync, stage, and recognize consumed imports',
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
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/$manifestName'
                },
                {
                  'name': 'segment.oxv.zst',
                  'size': 3,
                  'browser_download_url':
                      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag/segment.oxv.zst'
                },
              ],
            }),
            200);
      }
      final name = request.url.pathSegments.last;
      expect(
          await File(p.join(mirror, SemanticSearchAssets.manifestFileName))
              .exists(),
          isFalse);
      if (name == manifestName) return http.Response.bytes(bytes, 200);
      if (name == 'segment.oxv.zst') return http.Response.bytes([1, 2, 3], 200);
      return http.Response.bytes(
          await File(p.join(modelFixture!, name)).readAsBytes(), 200);
    });
    final online = SemanticSearchAssets(httpClient: client);
    try {
      await online.sync(
          mirrorDir: mirror,
          libraryTag: tag,
          onBytesProgress: (received, total) =>
              progress.add((received, total)));
    } finally {
      online.dispose();
      client.close();
    }
    expect(progress.first.$1, 0);
    expect(progress.last.$1, progress.last.$2);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue);
    await assets.install(mirrorDir: mirror, dbPath: db, libraryVersion: 30);
    final root = p.dirname(p.dirname(db));
    final staged = p.join(root, 'semantic-import');
    expect(await File(p.join(staged, 'vectors', manifestName)).readAsBytes(),
        bytes);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
    for (final file in SemanticSearchAssets.modelFiles) {
      final target = File(
          p.join(p.dirname(db), SemanticSearchAssets.modelFolder, file.name));
      await target.parent.create(recursive: true);
      await File(p.join(staged, SemanticSearchAssets.modelFolder, file.name))
          .copy(target.path);
    }
    await Directory(staged).delete(recursive: true);
    final vectors = p.join(root, 'vectors');
    const segment = '0123456789abcdef0123456789abcdef';
    final segmentFile = File(p.join(vectors, 'segments', '$segment.oxv'));
    await segmentFile.parent.create(recursive: true);
    await segmentFile.writeAsBytes([1, 2, 3]);
    Future<void> writeActive(String libraryTag) async {
      final setBytes = utf8.encode(jsonEncode({
        'format': 'otzaria-vector-set',
        'format_version': 1,
        'generation': 1,
        'library_version': 30,
        'library_release_tag': libraryTag,
        'segments': [
          {'file': 'segments/$segment.oxv', 'size': 3}
        ],
      }));
      final setFile = File(p.join(vectors, 'gen-000001', 'set.json'));
      await setFile.parent.create(recursive: true);
      await setFile.writeAsBytes(setBytes);
      await File(p.join(vectors, 'CURRENT')).writeAsString(jsonEncode({
        'generation': 1,
        'set': 'gen-000001/set.json',
        'set_sha256': Sha256Stream.ofBytes(setBytes),
      }));
    }

    await writeActive(tag);
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isFalse);
    await writeActive('v30-other');
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue);
    await writeActive(tag);
    await segmentFile.delete();
    expect(
        await assets.pending(mirrorDir: mirror, dbPath: db, libraryVersion: 30),
        isTrue);
    expect(requests, 0);
  },
      skip: modelFixture == null
          ? 'Set OTZARIA_SEMANTIC_MODEL_FIXTURE to the real pinned model release'
          : false);
}
