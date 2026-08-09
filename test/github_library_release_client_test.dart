import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/src/services/github_library_release_client.dart';
import 'package:test/test.dart';

/// תשובת JSON עם charset מפורש — כמו GitHub. בלי הכותרת `http.Response`
/// מקודד ב-latin1, ואז טקסט עברי בבדיקה עצמה היה נשבר.
http.Response json(Object? body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> releaseJson(String tag) => {
      'tag_name': tag,
      'prerelease': false,
      'draft': false,
      'published_at': '2026-06-27T21:00:00Z',
      'assets': [
        {
          'name': 'seforim.db.zst',
          'browser_download_url': 'https://x/$tag/seforim.db.zst',
          'size': 10,
        },
      ],
    };

Map<String, dynamic> manifestJson() => {
      'fromVersion': 1,
      'toVersion': 2,
      'fromSchemaVersion': 2,
      'toSchemaVersion': 2,
      'fromContentHash': 'aa',
      'toContentHash': 'bb',
      'patchFiles': [
        {
          'file': 'patch-v1-v2.db.zst',
          'compression': 'zstd',
          'sha256': 'c',
          'size': 5,
          'uncompressedSha256': 'u',
          'uncompressedSize': 9,
        }
      ],
    };

LibraryDomainStrings get strings => AppL10n.strings.libraryDomain;

void main() {
  group('fetchReleases', () {
    test('עמוד יחיד (פחות מ-per_page) → בקשה אחת בלבד', () async {
      final requested = <Uri>[];
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return json([releaseJson('v3'), releaseJson('v2')]);
        }),
      );
      final releases = await client.fetchReleases();
      expect(releases.map((r) => r.tag), ['v3', 'v2']);
      expect(requested, hasLength(1));
      expect(requested.single.queryParameters['per_page'], '100');
      expect(requested.single.queryParameters['page'], '1');
    });

    // ⚠️ בלי User-Agent ה-API מחזיר 403 — הכותרת הזו היא מלכודת מתועדת.
    test('כל בקשה נושאת User-Agent ואת כותרות ה-API של GitHub', () async {
      Map<String, String>? seen;
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((request) async {
          seen = request.headers;
          return json(<Object>[]);
        }),
      );
      await client.fetchReleases();
      expect(seen?['User-Agent'], isNotNull);
      expect(seen?['User-Agent'], isNotEmpty);
      expect(seen?['Accept'], 'application/vnd.github+json');
      expect(seen?['X-GitHub-Api-Version'], '2022-11-28');
    });

    test('מעבר לעמוד הבא כשהעמוד מלא, ועצירה בעמוד חלקי', () async {
      final pages = <String>[];
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((request) async {
          final page = request.url.queryParameters['page']!;
          pages.add(page);
          if (page == '1') {
            return json(List.generate(100, (i) => releaseJson('v$i')));
          }
          return json([releaseJson('last')]);
        }),
      );
      final releases = await client.fetchReleases();
      expect(pages, ['1', '2']);
      expect(releases, hasLength(101));
      expect(releases.last.tag, 'last');
    });

    // backstop מתועד: 20 עמודים לכל היותר, גם כשהשרת לא נגמר לעולם.
    test('שרת שמחזיר עמוד מלא לנצח נעצר אחרי 20 עמודים', () async {
      var pages = 0;
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((request) async {
          pages++;
          return json(List.generate(100, (i) => releaseJson('v$i')));
        }),
      );
      final releases = await client.fetchReleases();
      expect(pages, 20);
      expect(releases, hasLength(2000));
    });

    test('סטטוס שאינו 200 → Exception בהודעת ה-l10n', () {
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json({'message': 'nope'}, 503)),
      );
      expect(
        client.fetchReleases,
        throwsA(isA<Exception>().having(
          (e) => '$e',
          'message',
          contains(strings.releasesRequestFailed(503)),
        )),
      );
    });

    test('גוף שאינו רשימה → FormatException', () {
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json({'message': 'not a list'})),
      );
      expect(
        client.fetchReleases,
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          strings.releasesResponseNotList,
        )),
      );
    });

    test('פריטים שאינם אובייקטים ברשימה מדולגים', () async {
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json([1, 'x', releaseJson('v9')])),
      );
      final releases = await client.fetchReleases();
      expect(releases.map((r) => r.tag), ['v9']);
    });

    test('גוף UTF-8 (תגית עברית) מפוענח נכון', () async {
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json([releaseJson('גרסה-15')])),
      );
      final releases = await client.fetchReleases();
      expect(releases.single.tag, 'גרסה-15');
    });

    test('timeout ניתן לשינוי בזמן ריצה ותופס שרת תקוע', () async {
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return json(<Object>[]);
        }),
      );
      client.timeout = const Duration(milliseconds: 50);
      await expectLater(
          client.fetchReleases(), throwsA(isA<TimeoutException>()));
    });
  });

  group('fetchManifest', () {
    test('manifest תקין מפוענח', () async {
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json(manifestJson())),
      );
      final manifest = await client.fetchManifest('https://x/m.json');
      expect(manifest.fromVersion, 1);
      expect(manifest.toVersion, 2);
    });

    test('סטטוס שאינו 200 → Exception בהודעת ה-l10n', () {
      const url = 'https://x/m.json';
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => http.Response('missing', 404)),
      );
      expect(
        () => client.fetchManifest(url),
        throwsA(isA<Exception>().having(
          (e) => '$e',
          'message',
          contains(strings.manifestDownloadFailed(url, 404)),
        )),
      );
    });

    test('גוף שאינו אובייקט JSON → FormatException', () {
      const url = 'https://x/m.json';
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json([1, 2, 3])),
      );
      expect(
        () => client.fetchManifest(url),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          strings.manifestNotJsonObject(url),
        )),
      );
    });

    test('manifest חסר שדה חובה → FormatException', () {
      final broken = manifestJson()..remove('toContentHash');
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((_) async => json(broken)),
      );
      expect(
        () => client.fetchManifest('https://x/m.json'),
        throwsFormatException,
      );
    });

    test('גם ל-manifest נשלח User-Agent', () async {
      Map<String, String>? seen;
      final client = GithubLibraryReleaseClient(
        httpClient: MockClient((request) async {
          seen = request.headers;
          return json(manifestJson());
        }),
      );
      await client.fetchManifest('https://x/m.json');
      expect(seen?['User-Agent'], isNotNull);
    });
  });

  // ה-client מוזרק כאן, ולכן dispose אסור שיסגור אותו — אחרת שיתוף לקוח בין
  // GithubLibraryReleaseClient ל-PatchDownloader (כמו ב-LibraryMirrorExporter)
  // היה שובר את ההורדה.
  test('dispose אינו סוגר לקוח שהוזרק מבחוץ', () async {
    var calls = 0;
    final client = GithubLibraryReleaseClient(
      httpClient: MockClient((_) async {
        calls++;
        return json(<Object>[]);
      }),
    );
    client.dispose();
    await client.fetchReleases();
    expect(calls, 1);
  });

  test('ברירת המחדל מצביעה ל-Otzaria/SeforimLibrary', () async {
    Uri? url;
    final client = GithubLibraryReleaseClient(
      httpClient: MockClient((request) async {
        url = request.url;
        return json(<Object>[]);
      }),
    );
    await client.fetchReleases();
    expect(client.owner, 'Otzaria');
    expect(client.repository, 'SeforimLibrary');
    expect(url?.path, '/repos/Otzaria/SeforimLibrary/releases');
  });
}
