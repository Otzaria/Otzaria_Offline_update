import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seforim_library_updater/src/models/library_release.dart';
import 'package:seforim_library_updater/src/services/github_library_release_client.dart';
import 'package:seforim_library_updater/src/services/library_update_discovery.dart';
import 'package:seforim_library_updater/src/services/local_mirror_library_release_client.dart';
import 'package:test/test.dart';

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

/// בונה manifest JSON עבור patch from→to. [fromSchema]/[toSchema] מאפשרים
/// לדמות release שעבר לסכמה שאין לנו סדר hash עבורה.
String _manifestJson(
  int from,
  int to, {
  int fromSchema = 1,
  int toSchema = 1,
}) =>
    jsonEncode({
      'fromVersion': from,
      'toVersion': to,
      'fromSchemaVersion': fromSchema,
      'toSchemaVersion': toSchema,
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
      expect(result.fullDbReleaseTag, 'v3');
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
      expect(result.fullDbReleaseTag, 'v4');
    });

    // הבאג שהופיע בשטח: ה-tag שנרשם כ"מאיפה התוכן שלנו הגיע" חייב להיות של
    // ה-release החדש ביותר, ולא של נושא המסד המלא — אחרת כל החלפה של נושא
    // המסד נראתה כפרסום מחדש, והוצע "עדכון" מגרסה 22 לגרסה 22.
    test('release עם patches בלבד הוא latestContentTag, גם כשהמסד המלא ישן',
        () async {
      final releases = jsonEncode([
        {
          'tag_name': 'v22-latest',
          'assets': [
            {
              'name': 'patch-v21-v22.db.zst',
              'browser_download_url': 'https://x/v22/patch-v21-v22.db.zst',
              'size': 1000
            },
            {
              'name': 'patch-v21-v22.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v22/patch-v21-v22.db.zst.manifest.json',
              'size': 100
            },
          ],
        },
        {
          'tag_name': 'v21-carrier',
          'assets': [
            {
              'name': 'seforim.db.zst',
              'browser_download_url': 'https://x/v21/seforim.db.zst',
              'size': 1200000000
            },
          ],
        },
      ]);
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases')) return http.Response(releases, 200);
        if (url.endsWith('patch-v21-v22.db.zst.manifest.json')) {
          return http.Response(_manifestJson(21, 22), 200);
        }
        return http.Response('not found', 404);
      });
      final discovery = LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
      final result = await discovery.discover(allowPrerelease: false);

      expect(result.latestVersion, 22);
      expect(result.fullDbReleaseTag, 'v21-carrier');
      expect(result.latestContentTag, 'v22-latest');
    });

    test('ללא releases כלל → latestVersion=0, בלי edges ובלי DB מלא', () async {
      final mock = MockClient((_) async => http.Response('[]', 200));
      final discovery = LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
      final result = await discovery.discover(allowPrerelease: true);
      expect(result.latestVersion, 0);
      expect(result.edges, isEmpty);
      expect(result.latestFullDbAsset, isNull);
      expect(result.fullDbReleaseTag, isNull);
      expect(result.latestContentTag, isNull);
    });

    // manifest פגום/חסר מפיל רק את ה-edge שלו — שאר המסלולים חייבים לשרוד.
    test('manifest פגום מדלג על ה-edge בלבד', () async {
      final releases = jsonEncode([
        {
          'tag_name': 'v3',
          'assets': [
            {
              'name': 'patch-v1-v3.db.zst',
              'browser_download_url': 'https://x/v3/patch-v1-v3.db.zst',
              'size': 10
            },
            {
              'name': 'patch-v1-v3.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v3/patch-v1-v3.db.zst.manifest.json',
              'size': 10
            },
            {
              'name': 'patch-v2-v3.db.zst',
              'browser_download_url': 'https://x/v3/patch-v2-v3.db.zst',
              'size': 10
            },
            {
              'name': 'patch-v2-v3.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v3/patch-v2-v3.db.zst.manifest.json',
              'size': 10
            },
          ],
        },
      ]);
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases')) return http.Response(releases, 200);
        if (url.endsWith('patch-v1-v3.db.zst.manifest.json')) {
          return http.Response('{{{ broken', 200);
        }
        return http.Response(_manifestJson(2, 3), 200);
      });
      final discovery = LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
      final result = await discovery.discover(allowPrerelease: true);
      expect(
          result.edges.map((e) => '${e.fromVersion}-${e.toVersion}'), ['2-3']);
      expect(result.latestVersion, 3);
    });

    test('קובץ patch שה-manifest מצביע עליו חסר → ה-edge מדולג', () async {
      final releases = jsonEncode([
        {
          'tag_name': 'v3',
          'assets': [
            // ה-manifest קיים אך patch-v2-v3.db.zst עצמו אינו ב-release.
            {
              'name': 'patch-v2-v3.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v3/patch-v2-v3.db.zst.manifest.json',
              'size': 10
            },
            {
              'name': 'seforim.db.zst',
              'browser_download_url': 'https://x/v3/seforim.db.zst',
              'size': 100
            },
          ],
        },
      ]);
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases')) return http.Response(releases, 200);
        return http.Response(_manifestJson(2, 3), 200);
      });
      final discovery = LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
      final result = await discovery.discover(allowPrerelease: true);
      expect(result.edges, isEmpty);
      // הגרסה עדיין נגזרת משם ה-manifest, וה-DB המלא זמין ל-fallback.
      expect(result.latestVersion, 3);
      expect(result.latestFullDbAsset, isNotNull);
    });

    test('כשל רשת ברשימת ה-releases מתפשט החוצה', () {
      final mock = MockClient((_) async => http.Response('boom', 500));
      final discovery = LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
      expect(() => discovery.discover(allowPrerelease: true),
          throwsA(isA<Exception>()));
    });
  });

  // ⚠️ הבאג בשטח: SeforimLibrary פרסמה v26 עם patches שמצהירים
  // `toSchemaVersion: 4`, ואין לנו סדר hash לסכמה כזו. הכישלון התגלה רק
  // בתוך `PatchApplier.apply` — אחרי ~1.5GB הורדה, ~5.5GB חילוץ והחלפת המסד
  // החי (v23) במסד v21 של המראה. הסינון כאן הוא מה שמקדים אותו.
  group('discover — סכמה שאין לה סדר hash', () {
    /// גרף כמו בשטח: v26 (patch 22→26), v22 (patch 21→22), v21 (מסד מלא).
    /// [toSchemaOf26] קובע לאיזו סכמה ה-patch של v26 מצהיר שהוא מוביל.
    LibraryUpdateDiscovery buildDiscovery({required int toSchemaOf26}) {
      final releases = jsonEncode([
        {
          'tag_name': 'v26',
          'assets': [
            {
              'name': 'patch-v22-v26.db.zst',
              'browser_download_url': 'https://x/v26/patch-v22-v26.db.zst',
              'size': 1000
            },
            {
              'name': 'patch-v22-v26.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v26/patch-v22-v26.db.zst.manifest.json',
              'size': 100
            },
          ],
        },
        {
          'tag_name': 'v22',
          'assets': [
            {
              'name': 'patch-v21-v22.db.zst',
              'browser_download_url': 'https://x/v22/patch-v21-v22.db.zst',
              'size': 1000
            },
            {
              'name': 'patch-v21-v22.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/v22/patch-v21-v22.db.zst.manifest.json',
              'size': 100
            },
          ],
        },
        {
          'tag_name': 'v21',
          'assets': [
            {
              'name': 'seforim.db.zst',
              'browser_download_url': 'https://x/v21/seforim.db.zst',
              'size': 1200000000
            },
          ],
        },
      ]);
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases')) return http.Response(releases, 200);
        if (url.endsWith('patch-v22-v26.db.zst.manifest.json')) {
          return http.Response(
            _manifestJson(22, 26, fromSchema: 2, toSchema: toSchemaOf26),
            200,
          );
        }
        if (url.endsWith('patch-v21-v22.db.zst.manifest.json')) {
          return http.Response(
            _manifestJson(21, 22, fromSchema: 2, toSchema: 2),
            200,
          );
        }
        return http.Response('not found', 404);
      });
      return LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
    }

    test('הקשת שחוצה את הסכמה מסוננת, אך הגרסה נשארת ה-latest', () async {
      final result =
          await buildDiscovery(toSchemaOf26: 4).discover(allowPrerelease: true);

      // הגרסה נגזרת מכל הקשתות, גם מזו שאיננו יודעים להחיל: אחרת v26 היה
      // נראה כ"מעודכן" והמשתמש לא היה יודע שיש חדש בכלל.
      expect(result.latestVersion, 26);
      expect(
        result.edges.map((e) => '${e.fromVersion}-${e.toVersion}'),
        ['21-22'],
      );
      expect(result.unsupportedSchemaVersions, {4});
      expect(result.blockingSchemaVersion, 4);
      // וה-fallback היחיד שנשאר הוא המסד המלא של v21.
      expect(result.fullDbReleaseTag, 'v21');
      expect(result.latestFullDbVersion, 21);
    });

    test('כשכל הסכמות מוכרות — אין חסימה ואין קשת מסוננת', () async {
      final result =
          await buildDiscovery(toSchemaOf26: 2).discover(allowPrerelease: true);

      expect(result.latestVersion, 26);
      expect(
        result.edges.map((e) => '${e.fromVersion}-${e.toVersion}').toSet(),
        {'22-26', '21-22'},
      );
      expect(result.unsupportedSchemaVersions, isEmpty);
      expect(result.blockingSchemaVersion, isNull);
    });

    /// release שנושא את ה-manifest בלבד — בדיוק מה שהמראה כותבת כשהיא מדלגת
    /// על קובץ patch שאינו ניתן להחלה. ה-tag חסר מספר בכוונה, כדי שהגרסה
    /// תוכל להגיע מהקשת ולא מה-tag.
    LibraryUpdateDiscovery manifestOnly({required int toSchema}) {
      final releases = jsonEncode([
        {
          'tag_name': 'rolling',
          'assets': [
            {
              'name': 'patch-v22-v26.db.zst.manifest.json',
              'browser_download_url':
                  'https://x/rolling/patch-v22-v26.db.zst.manifest.json',
              'size': 100
            },
          ],
        },
      ]);
      final mock = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/releases')) return http.Response(releases, 200);
        return http.Response(
          _manifestJson(22, 26, fromSchema: 2, toSchema: toSchema),
          200,
        );
      });
      return LibraryUpdateDiscovery(
          client: GithubLibraryReleaseClient(httpClient: mock));
    }

    test('קובץ patch חסר בסכמה מוכרת → אין קשת בכלל', () async {
      final result =
          await manifestOnly(toSchema: 2).discover(allowPrerelease: true);
      expect(result.edges, isEmpty);
      // הקשת לא נבנתה כלל, ולכן גם הגרסה אינה נגזרת ממנה.
      expect(result.latestVersion, 0);
      expect(result.unsupportedSchemaVersions, isEmpty);
    });

    // המראה נושאת manifest בלי קובץ ה-patch (מאות בתים במקום מאות MB); בלי
    // הקשת הזו הגרסה החדשה נעלמת מהמראה ונראית באופליין כ"מעודכן".
    test('קובץ patch חסר בסכמה שאינה נתמכת → קשת מטא-דאטה שנספרת ל-latest',
        () async {
      final result =
          await manifestOnly(toSchema: 4).discover(allowPrerelease: true);
      expect(result.latestVersion, 26);
      expect(result.edges, isEmpty); // מסוננת מהתכנון
      expect(result.blockingSchemaVersion, 4);
    });
  });

  group('releaseVersionOf', () {
    LibraryRelease withAssets(String tag, List<String> names) =>
        _release(tag: tag, assetNames: names);

    test('נגזר מה-toVersion הגבוה ביותר בשמות ה-manifests', () {
      expect(
        LibraryUpdateDiscovery.releaseVersionOf(withAssets('לא-מספרי', [
          'patch-v1-v2.db.zst.manifest.json',
          'patch-v2-v5.db.zst.manifest.json',
        ])),
        5,
      );
    });

    test('נופל ל-tag כשאין manifests', () {
      expect(
        LibraryUpdateDiscovery.releaseVersionOf(
            withAssets('v7', ['seforim.db.zst'])),
        7,
      );
    });

    test('0 כשאין manifests ואין מספר ב-tag', () {
      expect(
        LibraryUpdateDiscovery.releaseVersionOf(withAssets('latest', [])),
        0,
      );
    });
  });

  // המראה המקומית היא המקור היחיד במסלול הבדיקה — הגילוי חייב לעבוד מולה
  // בדיוק כמו מול GitHub, ולהיכשל בבירור כשהיא חסרה.
  group('discover מעל מראה מקומית', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('discovery_mirror'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    String write(String name, String content) {
      final path = '${tmp.path}${Platform.pathSeparator}$name';
      File(path).writeAsStringSync(content);
      return name;
    }

    test('בונה edges מקבצים על הדיסק', () async {
      write('patch-v2-v3.db.zst.manifest.json', _manifestJson(2, 3));
      write('patch-v2-v3.db.zst', 'x');
      write('seforim.db.zst', 'y');
      write(
        'releases.json',
        jsonEncode({
          'releases': [
            {
              'tag': 'v3',
              'assets': [
                {
                  'name': 'patch-v2-v3.db.zst.manifest.json',
                  'downloadUrl': 'patch-v2-v3.db.zst.manifest.json',
                  'size': 10
                },
                {
                  'name': 'patch-v2-v3.db.zst',
                  'downloadUrl': 'patch-v2-v3.db.zst',
                  'size': 1
                },
                {
                  'name': 'seforim.db.zst',
                  'downloadUrl': 'seforim.db.zst',
                  'size': 1
                },
              ],
            },
          ],
        }),
      );

      final discovery = LibraryUpdateDiscovery(
          client: LocalMirrorLibraryReleaseClient(mirrorDir: tmp.path));
      final result = await discovery.discover(allowPrerelease: true);
      expect(result.latestVersion, 3);
      expect(result.edges, hasLength(1));
      expect(File(result.edges.single.patchFileUrls.values.single).existsSync(),
          isTrue);
      expect(result.fullDbReleaseTag, 'v3');
    });

    test('releases.json חסר → LocalMirrorException (בלי נפילה לרשת)', () {
      final discovery = LibraryUpdateDiscovery(
          client: LocalMirrorLibraryReleaseClient(mirrorDir: tmp.path));
      expect(() => discovery.discover(allowPrerelease: true),
          throwsA(isA<LocalMirrorException>()));
    });

    test('קובץ manifest חסר במראה → ה-edge מדולג, ה-DB המלא נשאר', () async {
      write('seforim.db.zst', 'y');
      write(
        'releases.json',
        jsonEncode({
          'releases': [
            {
              'tag': 'v3',
              'assets': [
                {
                  'name': 'patch-v2-v3.db.zst.manifest.json',
                  'downloadUrl': 'patch-v2-v3.db.zst.manifest.json',
                  'size': 10
                },
                {
                  'name': 'seforim.db.zst',
                  'downloadUrl': 'seforim.db.zst',
                  'size': 1
                },
              ],
            },
          ],
        }),
      );
      final discovery = LibraryUpdateDiscovery(
          client: LocalMirrorLibraryReleaseClient(mirrorDir: tmp.path));
      final result = await discovery.discover(allowPrerelease: true);
      expect(result.edges, isEmpty);
      expect(result.latestVersion, 3);
      expect(result.latestFullDbAsset, isNotNull);
    });
  });
}
