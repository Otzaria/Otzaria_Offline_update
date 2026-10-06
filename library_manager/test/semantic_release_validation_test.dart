import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:test/test.dart';

void main() {
  const tag = 'v30-20260930165019';
  const name = 'otzaria-vectors-test-v30-base.manifest.json';
  final digest = List.filled(64, '1').join();
  late Directory temporary;
  late String mirror;
  late File existing;

  Map<String, Object?> asset() => {
    'name': name,
    'size': 100,
    'digest': 'sha256:$digest',
  };
  Map<String, Object?> release() => {
    'tag_name': 'vectors-$tag',
    'assets': [asset()],
  };

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('semantic-validation-');
    mirror = p.join(temporary.path, 'mirror');
    existing = File(p.join(mirror, SemanticSearchAssets.manifestFileName));
    await existing.parent.create(recursive: true);
    await existing.writeAsString('existing mirror must survive');
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<void> rejectMetadata(Object? response, {int status = 200}) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'api.github.com');
      return http.Response(jsonEncode(response), status);
    });
    addTearDown(client.close);
    final assets = SemanticSearchAssets(httpClient: client);
    addTearDown(assets.dispose);
    await expectLater(
      assets.peekPending(mirrorDir: mirror, libraryTag: tag),
      throwsFormatException,
    );
    expect(calls, 1);
    expect(await existing.readAsString(), 'existing mirror must survive');
  }

  for (final status in [401, 403, 429, 500, 503]) {
    test('HTTP $status cannot prove the semantic mirror is current', () async {
      await rejectMetadata(release(), status: status);
    });
  }

  for (final value in [null, [], 'text', 1, {}]) {
    test(
      'non-release metadata $value fails without replacing the mirror',
      () async {
        await rejectMetadata(value);
      },
    );
  }

  test(
    'metadata for a different library tag cannot announce an update',
    () async {
      await rejectMetadata({...release(), 'tag_name': 'vectors-v31-other'});
    },
  );

  for (final value in [null, {}, 'assets', []]) {
    test('missing or invalid asset list $value fails closed', () async {
      await rejectMetadata({...release(), 'assets': value});
    });
  }

  final invalidAssets = <String, Object?>{
    'not a record': 'file',
    'missing name': {'size': 100},
    'non-string name': {'name': 42, 'size': 100},
    'traversal name': {'name': '../$name', 'size': 100},
    'backslash name': {'name': 'folder\\$name', 'size': 100},
    'missing size': {'name': name},
    'negative size': {...asset(), 'size': -1},
    'fractional size': {...asset(), 'size': 1.5},
    'text size': {...asset(), 'size': '100'},
    'missing digest': {'name': name, 'size': 100},
    'invalid digest': {...asset(), 'digest': 'sha256:not-a-hash'},
  };
  for (final entry in invalidAssets.entries) {
    test('${entry.key} is rejected before any asset request', () async {
      await rejectMetadata({
        ...release(),
        'assets': [entry.value],
      });
    });
  }

  test(
    'duplicate assets are rejected rather than silently replacing entries',
    () async {
      await rejectMetadata({
        ...release(),
        'assets': [asset(), asset()],
      });
    },
  );
  test('multiple vector manifests cannot be chosen arbitrarily', () async {
    await rejectMetadata({
      ...release(),
      'assets': [
        asset(),
        {...asset(), 'name': 'otzaria-vectors-other.manifest.json'},
      ],
    });
  });
  test('release notes and GitHub digest must agree', () async {
    await rejectMetadata({
      ...release(),
      'body': '$name ${List.filled(64, '2').join()}',
    });
  });

  const prefix =
      'https://github.com/Otzaria/SeforimLibrary/releases/download/vectors-$tag';
  final urls = {
    'HTTP': '${prefix.replaceFirst('https:', 'http:')}/$name',
    'wrong host': 'https://example.com/$name',
    'wrong repository':
        '${prefix.replaceFirst('SeforimLibrary', 'Other')}/$name',
    'wrong release': '${prefix.replaceFirst(tag, 'v31-other')}/$name',
    'query': '$prefix/$name?download=1',
    'fragment': '$prefix/$name#file',
    'credentials':
        '${prefix.replaceFirst('github.com', 'user@github.com')}/$name',
    'nested path': '$prefix/subfolder/$name',
    'encoded slash': '$prefix/sub%2F$name',
  };
  for (final entry in urls.entries) {
    test(
      '${entry.key} URL cannot redirect a semantic manifest download',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          expect(
            request.url.host,
            'api.github.com',
            reason: 'invalid URL must not be requested',
          );
          return http.Response(
            jsonEncode({
              ...release(),
              'assets': [
                {...asset(), 'browser_download_url': entry.value},
              ],
            }),
            200,
          );
        });
        addTearDown(client.close);
        final assets = SemanticSearchAssets(httpClient: client);
        addTearDown(assets.dispose);
        await expectLater(
          assets.sync(mirrorDir: mirror, libraryTag: tag),
          throwsFormatException,
        );
        expect(calls, 1);
        expect(await existing.readAsString(), 'existing mirror must survive');
        expect(
          await temporary
              .list(recursive: true)
              .where((entity) => entity is File)
              .length,
          1,
        );
      },
    );
  }

  test(
    'cancellation after metadata prevents requesting the manifest',
    () async {
      var cancelled = false;
      final client = MockClient((_) async {
        cancelled = true;
        return http.Response(
          jsonEncode({
            ...release(),
            'assets': [
              {...asset(), 'browser_download_url': '$prefix/$name'},
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final assets = SemanticSearchAssets(httpClient: client);
      addTearDown(assets.dispose);
      await expectLater(
        assets.sync(
          mirrorDir: mirror,
          libraryTag: tag,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(await existing.readAsString(), 'existing mirror must survive');
    },
  );
}
