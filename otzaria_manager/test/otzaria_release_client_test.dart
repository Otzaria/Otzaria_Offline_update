import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

http.Client _mockReleasesResponse(List<Map<String, dynamic>> releases) {
  return MockClient((request) async {
    expect(request.url.path, '/repos/Otzaria/otzaria/releases');
    return http.Response(jsonEncode(releases), 200);
  });
}

/// רשימת האסטים כאן היא צילום נאמן של release אמיתי (0.9.96+736), כולל
/// חבילות ה-FULL של ~2GB שאסור לבחור.
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
  bool prerelease = true,
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
  group('OtzariaReleaseClient (Windows)', () {
    test('picks the first release returned by the API, even if prerelease',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse(
            [_fakeRelease(tag: '0.9.95', prerelease: true)]),
      );

      final release = await client.fetchLatestRelease();

      expect(release.tagName, '0.9.95');
      expect(release.isPrerelease, isTrue);
      expect(release.installerKind, OtzariaInstallerKind.windowsSetupExe);
      expect(release.installerAssetName, 'otzaria-0.9.95-windows.exe');
      expect(release.installerSizeBytes, 31);
    });

    test('selects the plain windows.exe, never the 2GB FULL installer',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
        httpClient: _mockReleasesResponse([_fakeRelease(tag: '0.9.96')]),
      );

      final release = await client.fetchLatestRelease();

      expect(release.installerDownloadUrl, 'win');
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

  group('OtzariaReleaseClient (macOS)', () {
    test('prefers otzaria-macos.zip over the dmg and over the FULL zip',
        () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.macos,
        httpClient: _mockReleasesResponse([_fakeRelease(tag: '0.9.96')]),
      );

      final release = await client.fetchLatestRelease();

      expect(release.installerKind, OtzariaInstallerKind.macAppZip);
      expect(release.installerAssetName, 'otzaria-macos.zip');
      expect(release.installerDownloadUrl, 'mac-zip');
      expect(release.installerSizeBytes, 74);
    });

    test('falls back to the dmg when no zip is published', () async {
      final client = OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.macos,
        httpClient: _mockReleasesResponse([
          _fakeRelease(tag: '0.9.93', assets: [
            {
              'name': 'otzaria-macos-full.zip',
              'browser_download_url': 'full',
              'size': 2145
            },
            {
              'name': 'otzaria-macos.dmg',
              'browser_download_url': 'dmg',
              'size': 67
            },
          ]),
        ]),
      );

      final release = await client.fetchLatestRelease();

      expect(release.installerKind, OtzariaInstallerKind.macAppDmg);
      expect(release.installerDownloadUrl, 'dmg');
    });

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
        // זה בדיוק המצב אחרי זיהוי התקנה קיימת: ה-.app מדווח 0.9.96
        // (CFBundleShortVersionString) בעוד תג ה-release הוא 0.9.96+736.
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
