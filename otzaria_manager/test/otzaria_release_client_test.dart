import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart'
    show NetworkBlockedException;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

http.Client _mockReleasesResponse(List<Map<String, dynamic>> releases) {
  return MockClient((request) async {
    expect(request.url.path, '/repos/Otzaria/otzaria/releases/latest');
    return http.Response(_encodeLatestFixture(releases), 200);
  });
}

List<Map<String, dynamic>> _realWorldAssets(String tag) => [
      {'name': 'app-release.apk', 'browser_download_url': 'apk', 'size': 83},
      {
        'name': 'otzaria-$tag-linux.deb',
        'browser_download_url': 'deb',
        'size': 92
      },
      {
        'name': 'otzaria-$tag-windows-full.exe',
        'browser_download_url': 'win-full',
        'size': 2114,
      },
      {
        'name': 'otzaria-$tag-windows.exe',
        'browser_download_url': 'win',
        'size': 31,
      },
      {
        'name': 'otzaria-macos-full.zip',
        'browser_download_url': 'mac-full',
        'size': 2146
      },
      {
        'name': 'otzaria-macos.dmg',
        'browser_download_url': 'mac-dmg',
        'size': 73
      },
      {
        'name': 'otzaria-macos.zip',
        'browser_download_url': 'mac-zip',
        'size': 74
      },
      {
        'name': 'otzaria-windows.zip',
        'browser_download_url': 'win-zip',
        'size': 40
      },
    ];

Map<String, dynamic> _fakeRelease({
  required String tag,
  bool prerelease = false,
  List<Map<String, dynamic>>? assets,
}) {
  return {
    'tag_name': tag,
    'name': 'Otzaria $tag',
    'prerelease': prerelease,
    'draft': false,
    'published_at': '2026-01-01T00:00:00Z',
    'assets': assets ?? _realWorldAssets(tag),
  };
}

OtzariaRelease _release({
  required String tagName,
  OtzariaInstallerKind kind = OtzariaInstallerKind.windowsSetupExe,
}) {
  return OtzariaRelease(
    tagName: tagName,
    name: 'x',
    isPrerelease: true,
    isDraft: false,
    publishedAt: null,
    installerKind: kind,
    installerAssetName: 'a',
    installerDownloadUrl: 'b',
    installerSizeBytes: 1,
  );
}

void main() {
  test(
      'only the explicitly selected Latest is queried, even below another published version',
      () async {
    final requests = <Uri>[];
    final client = OtzariaReleaseClient(
      platform: OtzariaTargetPlatform.windows,
      httpClient: MockClient((request) async {
        requests.add(request.url);
        expect(request.url.path, '/repos/Otzaria/otzaria/releases/latest');
        return http.Response(jsonEncode(_fakeRelease(tag: '1.0.0')), 200);
      }),
    );
    addTearDown(client.dispose);
    expect((await client.fetchLatestRelease()).latest!.tagName, '1.0.0');
    expect(requests, hasLength(1));
  });
  for (final flag in ['prerelease', 'draft']) {
    test('an invalid Latest $flag cannot fall back to another release',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              ..._fakeRelease(tag: '1.0.0'),
              flag: true,
            }),
            200)),
      );
      addTearDown(client.dispose);
      await expectLater(
          client.fetchLatestRelease(), throwsA(isA<GithubApiException>()));
    });
  }

  group('OtzariaReleaseClient (Windows)', () {
    test('release בלי אסט מתאים מדולג במקום להפיל את הבדיקה', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse([
          _fakeRelease(tag: '0.9.99', prerelease: false, assets: [
            {'name': 'app-release.apk', 'browser_download_url': 'a', 'size': 1},
          ]),
          _fakeRelease(tag: '0.9.98', prerelease: false),
        ]),
      );

      await expectLater(client.fetchLatestRelease(),
          throwsA(isA<NoInstallerAssetException>()));
    });

    test('selects the plain windows.exe, never the 2GB FULL installer',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse(
            [_fakeRelease(tag: '0.9.96', prerelease: false)]),
      );

      final releases = await client.fetchLatestRelease();

      expect(releases.latest!.installerDownloadUrl, 'win');
    });

    test('throws NoInstallerAssetException when no windows asset exists',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse([
          _fakeRelease(tag: '0.9.95', assets: [
            {
              'name': 'otzaria-macos.zip',
              'browser_download_url': 'x',
              'size': 1
            },
          ]),
        ]),
      );

      expect(
          client.fetchLatestRelease, throwsA(isA<NoInstallerAssetException>()));
    });
  });

  group('OtzariaReleaseClient — הבקשה עצמה', () {
    test('שולח User-Agent (בלעדיו GitHub מחזיר 403) ומבקש Latest בלבד',
        () async {
      late http.Request captured;
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            _encodeLatestFixture(
                [_fakeRelease(tag: '0.9.96', prerelease: false)]),
            200,
          );
        }),
      );

      await client.fetchLatestRelease();

      expect(captured.headers['User-Agent'], isNotEmpty);
      expect(captured.headers['Accept'], 'application/vnd.github+json');
      expect(captured.headers['X-GitHub-Api-Version'], '2022-11-28');
      expect(captured.url.path, '/repos/Otzaria/otzaria/releases/latest');
    });

    test('סטטוס לא תקין הופך ל-GithubApiException עם ההודעה מ-l10n', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: MockClient((_) async => http.Response('nope', 500)),
      );

      expect(
        client.fetchLatestRelease,
        throwsA(
          isA<GithubApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('500'), contains('Otzaria/otzaria')),
          ),
        ),
      );
    });

    test('403/418 בלי מגבלת קצב — חסימת סינון ולא "סטטוס 403"', () async {
      for (final status in [403, 418]) {
        final client = OtzariaReleaseClient(
          platform: OtzariaTargetPlatform.windows,
          httpClient: MockClient((_) async => http.Response('', status)),
        );
        await expectLater(
          client.fetchLatestRelease(),
          throwsA(
            isA<NetworkBlockedException>()
                .having((e) => e.statusCode, 'statusCode', status),
          ),
        );
      }
    });

    test('רשימת releases ריקה — StateError מנוסח דרך l10n', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse(const []),
      );

      expect(
        client.fetchLatestRelease,
        throwsA(
          isA<GithubApiException>().having((e) => e.message, 'message',
              AppL10n.strings.appDomain.noReleasesAtAll('Otzaria/otzaria')),
        ),
      );
    });

    test('draft מסונן, גם כשהוא החדש ביותר', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse([
          {..._fakeRelease(tag: '0.9.99', prerelease: false), 'draft': true},
          _fakeRelease(tag: '0.9.98', prerelease: false),
        ]),
      );

      final releases = await client.fetchLatestRelease();

      expect(releases.latest!.tagName, '0.9.98');
    });

    test('release בלי אסטים בכלל מדולג', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse([
          _fakeRelease(tag: '0.9.99', prerelease: false, assets: const []),
          _fakeRelease(tag: '0.9.98', prerelease: false),
        ]),
      );

      await expectLater(client.fetchLatestRelease(),
          throwsA(isA<NoInstallerAssetException>()));
    });

    test('שומר את תיאור ה-release הגולמי כשיש כזה', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: MockClient(
          (_) async => http.Response(
            _encodeLatestFixture([
              {
                ..._fakeRelease(tag: '0.9.96', prerelease: false),
                'body': 'מה חדש',
              },
            ]),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      expect(
          (await client.fetchLatestRelease()).latest!.releaseNotes, 'מה חדש');
    });

    test('close לא זורק', () {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse(const []),
      );

      expect(client.dispose, returnsNormally);
    });
  });

  group('OtzariaReleaseClient (macOS)', () {
    test('throws NoInstallerAssetException on a windows-only release',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.macos,
        httpClient: _mockReleasesResponse([
          _fakeRelease(tag: '0.9.95', assets: [
            {
              'name': 'otzaria-0.9.95-windows.exe',
              'browser_download_url': 'x',
              'size': 1
            },
          ]),
        ]),
      );

      expect(
        client.fetchLatestRelease,
        throwsA(
          isA<NoInstallerAssetException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('macOS'), contains('macos.zip')),
          ),
        ),
      );
    });
  });

  group('OtzariaTargetPlatform.detect', () {
    test('maps the supported desktop platforms', () {
      expect(OtzariaTargetPlatform.detect('windows'),
          OtzariaTargetPlatform.windows);
      expect(
          OtzariaTargetPlatform.detect('macos'), OtzariaTargetPlatform.macos);
    });

    test('throws on a platform with no install path', () {
      expect(
          () => OtzariaTargetPlatform.detect('linux'), throwsUnsupportedError);
    });
  });

  group('OtzariaUpdateCheckResult.updateAvailable', () {
    test('is true when there is no prior install state', () {
      final result = OtzariaUpdateCheckResult(
        latestRelease: _release(tagName: '0.9.95'),
        currentState: null,
      );

      expect(result.updateAvailable, isTrue);
    });

    test('is false when installed tag matches latest tag', () {
      final result = OtzariaUpdateCheckResult(
        latestRelease: _release(tagName: '0.9.95'),
        currentState: const OtzariaInstallState(
          installedTagName: '0.9.95',
          installDir: r'C:\some\dir',
          launchPath: r'C:\some\dir\otzaria.exe',
        ),
      );

      expect(result.updateAvailable, isFalse);
    });

    test(
      'is false when a detected install reports the version without the build suffix',
      () {
        final result = OtzariaUpdateCheckResult(
          latestRelease: _release(
            tagName: '0.9.96+736',
            kind: OtzariaInstallerKind.macAppZip,
          ),
          currentState: const OtzariaInstallState(
            installedTagName: '0.9.96',
            installDir: '/Applications',
            launchPath: '/Applications/אוצריא.app',
          ),
        );

        expect(result.updateAvailable, isFalse);
      },
    );

    test('is still true for a genuinely newer release', () {
      final result = OtzariaUpdateCheckResult(
        latestRelease: _release(tagName: '0.9.97+800'),
        currentState: const OtzariaInstallState(
          installedTagName: '0.9.96',
          installDir: '/Applications',
          launchPath: '/Applications/אוצריא.app',
        ),
      );

      expect(result.updateAvailable, isTrue);
    });

    test('normalizeVersion strips a leading v and the build suffix', () {
      expect(OtzariaUpdateCheckResult.normalizeVersion('v1.2.3+45'), '1.2.3');
      expect(OtzariaUpdateCheckResult.normalizeVersion(' 1.2.3 '), '1.2.3');
    });
  });

  group('OtzariaInstallState', () {
    test('reads the legacy exePath key so an existing install is not forgotten',
        () {
      final state = OtzariaInstallState.fromJson(const {
        'installedTagName': '0.9.95',
        'installDir': r'C:\dir',
        'exePath': r'C:\dir\otzaria.exe',
      });

      expect(state.launchPath, r'C:\dir\otzaria.exe');
    });

    test('round-trips through the current key', () {
      const state = OtzariaInstallState(
        installedTagName: '0.9.96+736',
        installDir: '/Applications',
        launchPath: '/Applications/אוצריא.app',
      );

      expect(OtzariaInstallState.fromJson(state.toJson()), state);
    });
  });
}

String _encodeLatestFixture(Object? value) {
  if (value is List &&
      value.isNotEmpty &&
      value.first is Map &&
      (value.first as Map).containsKey('tag_name')) {
    final candidates = value
        .whereType<Map>()
        .where((r) => r['prerelease'] != true && r['draft'] != true);
    value = candidates.isEmpty ? value.first : candidates.first;
  }
  return jsonEncode(value);
}
