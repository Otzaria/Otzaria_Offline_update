import 'dart:convert';
import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// JSON של release כפי ש-GitHub מחזיר, מצומצם לשדות שאנחנו קוראים.
Map<String, dynamic> release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  List<String> assets = const [],
}) =>
    {
      'tag_name': tag,
      'prerelease': prerelease,
      'draft': draft,
      'published_at': '2026-08-13T10:00:00Z',
      'assets': [
        for (final name in assets)
          {
            'name': name,
            'browser_download_url': 'https://example.test/$name',
            'size': 100,
          },
      ],
    };

void main() {
  const source =
      GithubSource(owner: 'someone', repo: 'their-app', assetPattern: '');

  GithubAppClient clientReturning(List<Map<String, dynamic>> releases) =>
      GithubAppClient(
        httpClient: MockClient((request) async {
          expect(request.headers['User-Agent'], isNotEmpty,
              reason: 'בלי User-Agent גיטהאב מחזיר 403 לכל בקשה');
          return http.Response(
            jsonEncode(releases),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

  group('בחירת הגרסה', () {
    test('היציבה האחרונה מנצחת, גם כשיש pre-release חדש ממנה', () async {
      final client = clientReturning([
        release('v2.0-beta', prerelease: true),
        release('v1.9'),
        release('v1.8'),
      ]);

      expect((await client.fetchLatest(source))!.tagName, 'v1.9');
    });

    test('כשאין יציבה בכלל — ה-pre-release נבחר', () async {
      final client = clientReturning([release('v2.0-beta', prerelease: true)]);
      expect((await client.fetchLatest(source))!.tagName, 'v2.0-beta');
    });

    test('טיוטות מסוננות', () async {
      final client = clientReturning([
        release('v3.0', draft: true),
        release('v2.0'),
      ]);
      expect((await client.fetchLatest(source))!.tagName, 'v2.0');
    });

    test('ריפו בלי גרסאות — null ולא שגיאה', () async {
      expect(await clientReturning([]).fetchLatest(source), isNull);
    });
  });

  group('נרמול הגרסה', () {
    test('מסיר v מוביל וחלק build', () {
      expect(GithubRelease.normalizeVersion('v1.4.2'), '1.4.2');
      expect(GithubRelease.normalizeVersion('V1.4.2'), '1.4.2');
      expect(GithubRelease.normalizeVersion('0.9.96+736'), '0.9.96');
      expect(GithubRelease.normalizeVersion('1.0'), '1.0');
    });
  });

  group('בחירת הקובץ מתוך הגרסה', () {
    final withAssets = GithubRelease.fromJson(release(
      'v2.0',
      assets: [
        'App-2.0-x86.exe',
        'App-2.0-x64.exe',
        'App-2.0-x64.exe.sha256',
        'App-2.0-portable.zip',
      ],
    ));

    test('התבנית בוחרת את הקובץ הנכון, לא את הראשון', () {
      final pattern = GithubAssetPattern.fromAssetName('App-1.0-x64.exe');
      expect(
        GithubAppClient.selectAsset(withAssets, pattern)!.name,
        'App-2.0-x64.exe',
      );
    });

    test('קובץ ה-sha אינו נבחר בטעות — התבנית מעוגנת', () {
      final pattern = GithubAssetPattern.fromAssetName('App-1.0-x64.exe');
      final selected = GithubAppClient.selectAsset(withAssets, pattern)!;
      expect(selected.name.endsWith('.sha256'), isFalse);
    });

    test('אין התאמה — null, וההודעה למעלה תסביר', () {
      final pattern = GithubAssetPattern.fromAssetName('Other-1.0.msi');
      expect(GithubAppClient.selectAsset(withAssets, pattern), isNull);
    });
  });

  group('שגיאות רשת', () {
    test('סטטוס שאינו 200 — הודעה שנושאת אותו', () async {
      final client = GithubAppClient(
        httpClient: MockClient((_) async => http.Response('nope', 404)),
      );

      await expectLater(
        client.fetchReleases(source),
        throwsA(
          isA<AppDescriptorException>()
              .having((e) => e.message, 'message', contains('404')),
        ),
      );
    });

    test('תשובה שאינה רשימה נדחית', () async {
      final client = GithubAppClient(
        httpClient: MockClient((_) async => http.Response('{"a":1}', 200)),
      );

      await expectLater(
        client.fetchReleases(source),
        throwsA(isA<AppDescriptorException>()),
      );
    });
  });

  group('הורדה', () {
    test('הקובץ נכתב ומדווחת התקדמות', () async {
      final root = tempMirrorRoot();
      final client = GithubAppClient(
        httpClient: MockClient(
          (_) async => http.Response.bytes(List.filled(50, 65), 200),
        ),
      );

      final target = p.join(root, 'out', 'App.exe');
      var lastReceived = 0;
      await client.download(
        const GithubAsset(
          name: 'App.exe',
          downloadUrl: 'https://example.test/App.exe',
          sizeBytes: 50,
        ),
        target,
        onProgress: (received, _) => lastReceived = received,
      );

      expect(File(target).lengthSync(), 50);
      expect(lastReceived, 50);
    });

    test('סטטוס שגוי — הקובץ אינו נשאר על הדיסק', () async {
      final root = tempMirrorRoot();
      final client = GithubAppClient(
        httpClient: MockClient((_) async => http.Response('no', 500)),
      );

      final target = p.join(root, 'out', 'App.exe');
      await expectLater(
        client.download(
          const GithubAsset(
            name: 'App.exe',
            downloadUrl: 'https://example.test/App.exe',
            sizeBytes: 50,
          ),
          target,
        ),
        throwsA(isA<AppDescriptorException>()),
      );
      expect(File(target).existsSync(), isFalse);
    });
  });
}
