import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  final api = Uri.parse('https://api.github.com/repos/o/r/releases');
  final raw = Uri.parse('https://raw.githubusercontent.com/o/r/file.md');

  late Duration elapsed;
  late GithubRateLimitGate gate;

  setUp(() {
    elapsed = Duration.zero;
    gate = GithubRateLimitGate(
      elapsed: () => elapsed,
      clock: () => DateTime.utc(2026, 10, 1, 12),
    );
  });

  group('GithubReleaseAsset', () {
    test('parses the digest as lowercase hex and ignores other forms', () {
      final asset = GithubReleaseAsset.tryParse({
        'name': 'a.exe',
        'browser_download_url': 'https://x/a.exe',
        'size': 10,
        'state': 'uploaded',
        'digest': 'sha256:ABCDEF',
      })!;
      expect(asset.name, 'a.exe');
      expect(asset.downloadUrl, 'https://x/a.exe');
      expect(asset.size, 10);
      expect(asset.sha256, 'abcdef');
      expect(asset.isReady, isTrue);
      expect(githubAssetSha256('md5:abc'), isNull);
      expect(githubAssetSha256(null), isNull);
      expect(githubAssetSha256(7), isNull);
    });

    test('a malformed asset is null rather than a throw', () {
      expect(GithubReleaseAsset.tryParse('x'), isNull);
      expect(
        GithubReleaseAsset.tryParse({'name': 'a', 'size': 1}),
        isNull,
      );
      expect(
        GithubReleaseAsset.tryParse(
          {'name': 'a', 'browser_download_url': 'u', 'size': '1'},
        ),
        isNull,
      );
    });

    test('an upload in progress or an empty asset is not ready', () {
      GithubReleaseAsset asset({Object? state, int size = 5}) =>
          GithubReleaseAsset.tryParse({
            'name': 'a',
            'browser_download_url': 'u',
            'size': size,
            if (state != null) 'state': state,
          })!;
      expect(asset().isReady, isTrue);
      expect(asset(state: 'starter').isReady, isFalse);
      expect(asset(size: 0).isReady, isFalse);
      expect(asset(state: 3).isReady, isTrue);
    });
  });

  group('githubGet', () {
    test('sends the API headers and decodes UTF-8 regardless of charset',
        () async {
      late http.BaseRequest seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response.bytes(utf8.encode(jsonEncode({'n': 'שלום'})), 200);
      });
      final decoded = await githubGetJson(
        client,
        api,
        timeout: const Duration(seconds: 5),
        statusError: (status) => StateError('$status'),
        gate: gate,
      );
      expect(decoded, {'n': 'שלום'});
      expect(seen.headers['User-Agent'], githubUserAgent);
      expect(seen.headers['X-GitHub-Api-Version'], '2022-11-28');
      expect(seen.headers['Accept'], 'application/vnd.github+json');
    });

    test('a non-200 status goes through the caller error', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      await expectLater(
        githubGetJson(
          client,
          api,
          timeout: const Duration(seconds: 5),
          statusError: (status) => StateError('status $status'),
          gate: gate,
        ),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', 'status 503')),
      );
    });

    test('a plain 403 or 429 is not a rate limit', () async {
      for (final status in [403, 429]) {
        final client = MockClient((_) async => http.Response('{}', status));
        final response = await githubGet(
          client,
          api,
          timeout: const Duration(seconds: 5),
          gate: gate,
        );
        expect(response.statusCode, status);
      }
      expect(gate.remaining, isNull);
    });

    test('times out with the given timeout', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('[]', 200);
      });
      await expectLater(
        githubGet(
          client,
          api,
          timeout: const Duration(milliseconds: 20),
          gate: gate,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('rate limit', () {
    http.Response limited({Map<String, String> headers = const {}}) =>
        http.Response('{"message":"API rate limit exceeded"}', 403,
            headers: headers);

    test('X-RateLimit-Reset is measured against the server Date header',
        () async {
      final server = DateTime.utc(2026, 10, 1, 9);
      final reset = server.add(const Duration(minutes: 12, seconds: 30));
      final client = MockClient(
        (_) async => limited(headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          'date': HttpDate.format(server),
        }),
      );
      final error = await githubGet(
        client,
        api,
        timeout: const Duration(seconds: 5),
        gate: gate,
      ).then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<GithubRateLimitException>());
      final limit = error as GithubRateLimitException;
      expect(limit.statusCode, 403);
      expect(limit.retryAfter, const Duration(minutes: 12, seconds: 30));
      expect(limit.retryAfterMinutes, 13);
      expect(
        limit.resetAt,
        DateTime.utc(2026, 10, 1, 12, 12, 30),
      );
      expect(gate.remaining, const Duration(minutes: 12, seconds: 30));
    });

    test('Retry-After wins and 429 counts too', () async {
      final client = MockClient(
        (_) async => http.Response('', 429, headers: {'retry-after': '61'}),
      );
      await expectLater(
        githubGet(client, api, timeout: const Duration(seconds: 5), gate: gate),
        throwsA(isA<GithubRateLimitException>()
            .having((e) => e.retryAfterMinutes, 'minutes', 2)),
      );
    });

    test('remaining 0 without a reset time has no wait and no gate', () async {
      final client = MockClient(
        (_) async => limited(headers: {'x-ratelimit-remaining': '0'}),
      );
      await expectLater(
        githubGet(client, api, timeout: const Duration(seconds: 5), gate: gate),
        throwsA(isA<GithubRateLimitException>()
            .having((e) => e.retryAfter, 'retryAfter', isNull)),
      );
      expect(gate.remaining, isNull);
    });

    test('a far-off reset is capped at one hour', () async {
      final client = MockClient(
        (_) async => http.Response('', 403, headers: {'retry-after': '86400'}),
      );
      await expectLater(
        githubGet(client, api, timeout: const Duration(seconds: 5), gate: gate),
        throwsA(isA<GithubRateLimitException>()),
      );
      expect(gate.remaining, githubRateLimitMaxWait);
    });

    test('the gate fails fast until it expires, then lets requests through',
        () async {
      var calls = 0;
      var limitedNow = true;
      final client = MockClient((_) async {
        calls++;
        return limitedNow
            ? http.Response('', 403, headers: {'retry-after': '120'})
            : http.Response('[]', 200);
      });
      Future<http.Response> get() => githubGet(
            client,
            api,
            timeout: const Duration(seconds: 5),
            gate: gate,
          );

      await expectLater(get(), throwsA(isA<GithubRateLimitException>()));
      expect(calls, 1);

      limitedNow = false;
      elapsed = const Duration(seconds: 30);
      await expectLater(
        get(),
        throwsA(isA<GithubRateLimitException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.retryAfter, 'retryAfter',
                const Duration(seconds: 90))),
      );
      expect(calls, 1);

      elapsed = const Duration(seconds: 120);
      expect((await get()).statusCode, 200);
      expect(calls, 2);
      expect(gate.remaining, isNull);
    });

    test('the gate never blocks a host other than the API', () async {
      gate.close(const Duration(minutes: 5));
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 403, headers: {'retry-after': '60'});
      });
      final response = await githubGet(
        client,
        raw,
        timeout: const Duration(seconds: 5),
        headers: githubUserAgentHeaders,
        gate: gate,
      );
      expect(response.statusCode, 403);
      expect(calls, 1);
    });

    test('the message is localized and says when to retry', () {
      final previous = AppL10n.language;
      addTearDown(() => AppL10n.use(previous));
      AppL10n.use(AppLanguage.english);
      final error = GithubRateLimitException(
        uri: api,
        retryAfter: const Duration(minutes: 4),
      );
      expect(error.toString(), contains('4 minutes'));
      expect(
        GithubRateLimitException(uri: api).toString(),
        contains('later'),
      );
    });
  });
}
