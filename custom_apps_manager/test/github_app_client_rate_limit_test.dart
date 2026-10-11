import 'dart:convert';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:test/test.dart';

void main() {
  const source =
      GithubSource(owner: 'someone', repo: 'their-app', assetPattern: '');

  tearDown(GithubRateLimitGate.shared.reset);

  test('a rate limit surfaces as GithubRateLimitException', () async {
    final client = GithubAppClient(
      httpClient: MockClient(
        (_) async => http.Response('', 403, headers: {
          'x-ratelimit-remaining': '0',
          'retry-after': '30',
        }),
      ),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.fetchLatest(source),
      throwsA(isA<GithubRateLimitException>()
          .having((e) => e.retryAfterMinutes, 'minutes', 1)),
    );
  });

  test('a plain error status keeps the package exception', () async {
    final client = GithubAppClient(
      httpClient: MockClient((_) async => http.Response('nope', 404)),
    );
    addTearDown(client.dispose);

    await expectLater(
      client.fetchReleases(source),
      throwsA(isA<AppDescriptorException>()),
    );
  });

  test('UTF-8 is decoded even without a charset', () async {
    final client = GithubAppClient(
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode([
            {
              'tag_name': 'v1',
              'prerelease': false,
              'draft': false,
              'assets': [
                {
                  'name': 'תוכנה.exe',
                  'browser_download_url': 'https://x/a.exe',
                  'size': 3,
                  'digest': 'sha256:ABC',
                },
              ],
            },
          ])),
          200,
        ),
      ),
    );
    addTearDown(client.dispose);

    final release = (await client.fetchReleases(source)).single;
    expect(release.assets.single.name, 'תוכנה.exe');
    expect(release.assets.single.sha256, 'abc');
  });
}
