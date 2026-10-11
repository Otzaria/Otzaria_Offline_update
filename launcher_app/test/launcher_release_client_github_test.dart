import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/self_update/launcher_release_client.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';

Map<String, dynamic> _release(String tag, List<Map<String, dynamic>> assets) =>
    {
      'tag_name': tag,
      'name': tag,
      'prerelease': false,
      'draft': false,
      'assets': assets,
    };

Map<String, dynamic> _asset(String name, {int size = 4, Object? state}) => {
      'name': name,
      'browser_download_url': 'https://example/$name',
      'size': size,
      'digest': 'sha256:ABCD',
      if (state != null) 'state': state,
    };

void main() {
  tearDown(GithubRateLimitGate.shared.reset);

  test('an asset still uploading is not offered as the update', () async {
    final client = LauncherReleaseClient(
      operatingSystem: 'windows',
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode([
              _release('v0.9.0', [_asset('a.exe', state: 'starter')]),
              _release('v0.8.0', [
                _asset('a.exe', size: 0),
                _asset('b.exe', state: 'uploaded'),
              ]),
            ]),
          ),
          200,
        ),
      ),
    );
    addTearDown(client.dispose);

    final release = await client.fetchLatestStable();
    expect(release!.tagName, 'v0.8.0');
    expect(release.assetName, 'b.exe');
    expect(release.sha256, 'abcd');
  });

  test('a rate limit fails fast for the API but not for the changelog',
      () async {
    final hosts = <String>[];
    final client = LauncherReleaseClient(
      operatingSystem: 'windows',
      httpClient: MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == githubApiHost) {
          return http.Response('', 429, headers: {'retry-after': '90'});
        }
        return http.Response.bytes(utf8.encode('* **1.0**'), 200);
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.fetchLatestStable(),
      throwsA(
        isA<GithubRateLimitException>().having(
          (e) => e.retryAfterMinutes,
          'minutes',
          2,
        ),
      ),
    );
    await expectLater(
      client.fetchLatestStable(),
      throwsA(isA<GithubRateLimitException>()),
    );
    expect(await client.fetchChangelog('v0.8.0'), '* **1.0**');
    expect(hosts, [githubApiHost, 'raw.githubusercontent.com']);
  });
}
