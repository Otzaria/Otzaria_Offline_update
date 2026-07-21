import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/services/github_library_release_client.dart';
import 'package:seforim_library_updater/src/services/library_update_discovery.dart';

LibraryRelease _release({
  required String tag,
  bool prerelease = false,
  bool draft = false,
  List<String> assetNames = const [],
}) {
  return LibraryRelease(
    tag: tag,
    isPrerelease: prerelease,
    isDraft: draft,
    publishedAt: null,
    assets: assetNames
        .map((n) =>
            ReleaseAsset(name: n, downloadUrl: 'https://x/$tag/$n', size: 100))
        .toList(),
  );
}

/// בונה manifest JSON עבור patch from→to.
String _manifestJson(int from, int to) => jsonEncode({
      'fromVersion': from,
      'toVersion': to,
      'fromSchemaVersion': 1,
      'toSchemaVersion': 1,
      'fromContentHash': 'hash$from',
      'toContentHash': 'hash$to',
      'patchFiles': [
        {
          'file': 'patch-v$from-v$to.db.zst',
          'compression': 'zstd',
          'sha256': 'c',
          'size': (to - from) * 1000,
          'uncompressedSha256': 'u',
          'uncompressedSize': (to - from) * 2000,
        }
      ],
    });

void main() {
  group('eligibleReleases', () {
    test('מתעלם מ-draft תמיד', () {
      final result = LibraryUpdateDiscovery.eligibleReleases(
        [
          _release(tag: 'v3'),
          _release(tag: 'v4', draft: true),
        ],
        allowPrerelease: true,
      );
      expect(result.map((r) => r.tag), ['v3']);
    });

    test('ערוץ יציב לא בוחר prerelease', () {
      final result = LibraryUpdateDiscovery.eligibleReleases(
        [
          _release(tag: 'v3'),
          _release(tag: 'v4', prerelease: true),
        ],
        allowPrerelease: false,
      );
      expect(result.map((r) => r.tag), ['v3']);
    });

    test('ערוץ dev כן בוחר prerelease', () {
      final result = LibraryUpdateDiscovery.eligibleReleases(
        [
          _release(tag: 'v3'),
          _release(tag: 'v4', prerelease: true),
        ],
        allowPrerelease: true,
      );
      expect(result.map((r) => r.tag), ['v3', 'v4']);
    });
  });

  group('parseVersionFromTag', () {
    test('מחלץ מ-v3', () {
      expect(LibraryUpdateDiscovery.parseVersionFromTag('v3'), 3);
    });
    test('מחלץ מ-3', () {
      expect(LibraryUpdateDiscovery.parseVersionFromTag('3'), 3);
    });
    test('null אם אין מספר', () {
      expect(LibraryUpdateDiscovery.parseVersionFromTag('latest'), isNull);
    });
  });

  group('discover (mock client)', () {
    // releases: v3 (1→3, 2→3), v2 (1→2), v1 (אין patches)
    final releasesJson = jsonEncode([
      {
        'tag_name': 'v3',
        'prerelease': false,
        'draft': false,
        'published_at': '2026-06-27T21:00:00Z',
        'assets': [
          {
            'name': 'seforim.db.zst',
            'browser_download_url': 'https://x/v3/seforim.db.zst',
            'size': 1197000000
          },
          {
            'name': 'patch-v1-v3.db.zst',
            'browser_download_url': 'https://x/v3/patch-v1-v3.db.zst',
            'size': 2836082
          },
          {
            'name': 'patch-v1-v3.db.zst.manifest.json',
            'browser_download_url':
                'https://x/v3/patch-v1-v3.db.zst.manifest.json',
            'size': 605
          },
          {
            'name': 'patch-v2-v3.db.zst',
            'browser_download_url': 'https://x/v3/patch-v2-v3.db.zst',
            'size': 1870859
          },
          {
            'name': 'patch-v2-v3.db.zst.manifest.json',
            'browser_download_url':
                'https://x/v3/patch-v2-v3.db.zst.manifest.json',
            'size': 605
          },
        ],
      },
      {
        'tag_name': 'v2',
        'prerelease': false,
        'draft': false,
        'published_at': '2026-06-26T11:00:00Z',
        'assets': [
          {
            'name': 'seforim.db.zst',
            'browser_download_url': 'https://x/v2/seforim.db.zst',
            'size': 1195000000
          },
          {
            'name': 'patch-v1-v2.db.zst',
            'browser_download_url': 'https://x/v2/patch-v1-v2.db.zst',
            'size': 1040075
          },
          {
            'name': 'patch-v1-v2.db.zst.manifest.json',
            'browser_download_url':
                'https://x/v2/patch-v1-v2.db.zst.manifest.json',
            'size': 604
          },
        ],
      },
    ]);

    GithubLibraryReleaseClient buildClient() {
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases?') || url.endsWith('/releases')) {
          return http.Response(releasesJson, 200);
        }
        if (url.endsWith('patch-v1-v3.db.zst.manifest.json')) {
          return http.Response(_manifestJson(1, 3), 200);
        }
        if (url.endsWith('patch-v2-v3.db.zst.manifest.json')) {
          return http.Response(_manifestJson(2, 3), 200);
        }
        if (url.endsWith('patch-v1-v2.db.zst.manifest.json')) {
          return http.Response(_manifestJson(1, 2), 200);
        }
        return http.Response('not found', 404);
      });
      return GithubLibraryReleaseClient(httpClient: mock);
    }

    test('בונה edges, מזהה latest=3 ו-full asset', () async {
      final discovery = LibraryUpdateDiscovery(client: buildClient());
      final result = await discovery.discover(allowPrerelease: false);

      expect(result.latestVersion, 3);
      expect(result.edges, hasLength(3)); // 1→3, 2→3, 1→2
      final pairs =
          result.edges.map((e) => '${e.fromVersion}-${e.toVersion}').toSet();
      expect(pairs, {'1-3', '2-3', '1-2'});

      // ה-edge 1→3 צריך להכיל URL להורדת ה-patch
      final direct = result.edges
          .firstWhere((e) => e.fromVersion == 1 && e.toVersion == 3);
      expect(direct.patchFileUrls['patch-v1-v3.db.zst'],
          'https://x/v3/patch-v1-v3.db.zst');

      expect(
          result.latestFullDbAsset?.downloadUrl, 'https://x/v3/seforim.db.zst');
      expect(result.latestReleaseTag, 'v3');
    });

    test('release חדש עם DB מלא בלבד (ללא patches) נחשב latest', () async {
      // v4 יצא עם seforim.db.zst בלבד; latestVersion חייב להיות 4, לא 3.
      final releasesJsonV4 = jsonEncode([
        {
          'tag_name': 'v4',
          'prerelease': false,
          'draft': false,
          'assets': [
            {
              'name': 'seforim.db.zst',
              'browser_download_url': 'https://x/v4/seforim.db.zst',
              'size': 1200000000
            },
          ],
        },
        {
          'tag_name': 'v3',
          'prerelease': false,
          'draft': false,
          'assets': [
            {
              'name': 'patch-v2-v3.db.zst',
              'browser_download_url': 'https://x/v3/patch-v2-v3.db.zst',
              'size': 1870859
            },
            {
              'name': 'patch-v2-v3.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v3/patch-v2-v3.db.zst.manifest.json',
              'size': 605
            },
          ],
        },
      ]);
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases?') || url.endsWith('/releases')) {
          return http.Response(releasesJsonV4, 200);
        }
        if (url.endsWith('patch-v2-v3.db.zst.manifest.json')) {
          return http.Response(_manifestJson(2, 3), 200);
        }
        return http.Response('not found', 404);
      });
      final discovery = LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
      final result = await discovery.discover(allowPrerelease: false);

      expect(result.latestVersion, 4); // מה-full DB, גבוה מ-edge המקסימלי (3)
      expect(
          result.latestFullDbAsset?.downloadUrl, 'https://x/v4/seforim.db.zst');
      expect(result.latestReleaseTag, 'v4');
    });
  });
}
