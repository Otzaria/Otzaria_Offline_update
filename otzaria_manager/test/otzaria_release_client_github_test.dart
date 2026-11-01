import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:test/test.dart';

Map<String, dynamic> _release(String tag, List<Map<String, dynamic>> assets) =>
    {
      'tag_name': tag,
      'name': tag,
      'prerelease': false,
      'draft': false,
      'assets': assets,
    };

Map<String, dynamic> _asset(String name, {int size = 31, Object? state}) => {
      'name': name,
      'browser_download_url': 'https://x/$name',
      'size': size,
      if (state != null) 'state': state,
    };

OtzariaReleaseClient _client(http.Client httpClient) => OtzariaReleaseClient(
      platform: OtzariaTargetPlatform.windows,
      httpClient: httpClient,
    );

void main() {
  tearDown(GithubRateLimitGate.shared.reset);

  test('an exhausted quota surfaces as GithubRateLimitException', () async {
    var calls = 0;
    final client = _client(MockClient((_) async {
      calls++;
      return http.Response('', 403, headers: {
        'x-ratelimit-remaining': '0',
        'retry-after': '300',
      });
    }));
    addTearDown(client.dispose);

    await expectLater(
      client.fetchLatestRelease(),
      throwsA(isA<GithubRateLimitException>()
          .having((e) => e.retryAfterMinutes, 'minutes', 5)),
    );
    await expectLater(
      client.fetchLatestRelease(),
      throwsA(isA<GithubRateLimitException>()),
    );
    expect(calls, 1);
  });

  test('assets still uploading or malformed are skipped like missing ones',
      () async {
    final client = _client(MockClient((_) async => http.Response.bytes(
          utf8.encode(_encodeLatestFixture([
            _release('0.9.97', [
              _asset('otzaria-0.9.97-windows.exe', state: 'starter'),
              {'name': 'otzaria-0.9.97-windows.exe'},
              _asset('otzaria-0.9.97-windows.exe', state: 'uploaded'),
            ]),
            _release('0.9.96', [
              _asset('otzaria-0.9.96-windows.exe', size: 0),
              _asset('otzaria-0.9.96-windows.exe', state: 'uploaded'),
            ]),
          ])),
          200,
        )));
    addTearDown(client.dispose);

    final channels = await client.fetchLatestRelease();
    expect(channels.latest!.tagName, '0.9.97');
    expect(channels.latest!.installerSizeBytes, 31);
    expect(
      channels.latest!.installerDownloadUrl,
      'https://x/otzaria-0.9.97-windows.exe',
    );
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
