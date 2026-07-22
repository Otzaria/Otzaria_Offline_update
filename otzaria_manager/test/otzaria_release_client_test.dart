import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

http.Client _mockReleasesResponse(List<Map<String, dynamic>> releases) {
  return MockClient((request) async {
    expect(request.url.path, '/repos/Sivan22/otzaria/releases');
    return http.Response(jsonEncode(releases), 200);
  });
}

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
    'assets': assets ??
        [
          {
            'name': 'otzaria-$tag-windows.exe',
            'browser_download_url': 'https://example.com/otzaria-$tag-windows.exe',
            'size': 12345,
          },
          {
            'name': 'otzaria-macos.zip',
            'browser_download_url': 'https://example.com/otzaria-macos.zip',
            'size': 999,
          },
        ],
  };
}

void main() {
  group('OtzariaReleaseClient', () {
    test('picks the first release returned by the API, even if prerelease', () async {
      final client = OtzariaReleaseClient(
        httpClient: _mockReleasesResponse([_fakeRelease(tag: '0.9.95', prerelease: true)]),
      );

      final release = await client.fetchLatestRelease();

      expect(release.tagName, '0.9.95');
      expect(release.isPrerelease, isTrue);
      expect(release.windowsInstallerAssetName, 'otzaria-0.9.95-windows.exe');
      expect(release.windowsInstallerSizeBytes, 12345);
    });

    test('selects the asset ending in windows.exe among several assets', () async {
      final client = OtzariaReleaseClient(
        httpClient: _mockReleasesResponse([
          _fakeRelease(
            tag: '0.9.95',
            assets: [
              {'name': 'app-release.apk', 'browser_download_url': 'x', 'size': 1},
              {'name': 'otzaria-linux-raw.zip', 'browser_download_url': 'x', 'size': 1},
              {
                'name': 'otzaria-0.9.95-windows.exe',
                'browser_download_url': 'https://example.com/win.exe',
                'size': 42,
              },
            ],
          ),
        ]),
      );

      final release = await client.fetchLatestRelease();

      expect(release.windowsInstallerDownloadUrl, 'https://example.com/win.exe');
    });

    test('throws NoWindowsAssetException when no windows.exe asset exists', () async {
      final client = OtzariaReleaseClient(
        httpClient: _mockReleasesResponse([
          _fakeRelease(tag: '0.9.95', assets: [
            {'name': 'otzaria-macos.zip', 'browser_download_url': 'x', 'size': 1},
          ]),
        ]),
      );

      expect(client.fetchLatestRelease, throwsA(isA<NoWindowsAssetException>()));
    });
  });

  group('OtzariaUpdateCheckResult.updateAvailable', () {
    test('is true when there is no prior install state', () {
      final release = OtzariaRelease(
        tagName: '0.9.95',
        name: 'x',
        isPrerelease: true,
        isDraft: false,
        publishedAt: null,
        windowsInstallerAssetName: 'a',
        windowsInstallerDownloadUrl: 'b',
        windowsInstallerSizeBytes: 1,
      );

      final result = OtzariaUpdateCheckResult(latestRelease: release, currentState: null);

      expect(result.updateAvailable, isTrue);
    });

    test('is false when installed tag matches latest tag', () {
      final release = OtzariaRelease(
        tagName: '0.9.95',
        name: 'x',
        isPrerelease: true,
        isDraft: false,
        publishedAt: null,
        windowsInstallerAssetName: 'a',
        windowsInstallerDownloadUrl: 'b',
        windowsInstallerSizeBytes: 1,
      );

      final result = OtzariaUpdateCheckResult(
        latestRelease: release,
        currentState: const OtzariaInstallState(
          installedTagName: '0.9.95',
          installDir: r'C:\some\dir',
          exePath: r'C:\some\dir\otzaria.exe',
        ),
      );

      expect(result.updateAvailable, isFalse);
    });
  });
}
