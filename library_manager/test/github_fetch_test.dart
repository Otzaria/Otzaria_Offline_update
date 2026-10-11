import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/github_fetch.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';

void main() {
  final api = Uri.parse('https://api.github.com/repos/o/r/releases/latest');

  late Duration elapsed;
  late GithubRateLimitGate gate;

  setUp(() {
    elapsed = Duration.zero;
    gate = GithubRateLimitGate(
      elapsed: () => elapsed,
      clock: () => DateTime.utc(2026, 10, 1, 12),
    );
  });

  tearDown(GithubRateLimitGate.shared.reset);

  test('sends the shared API headers', () async {
    late http.BaseRequest seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response('{}', 200);
    });
    await githubGet(client, api, timeout: const Duration(seconds: 5));
    expect(seen.headers['User-Agent'], githubUserAgent);
    expect(seen.headers['X-GitHub-Api-Version'], '2022-11-28');
    expect(seen.headers['Accept'], 'application/vnd.github+json');
  });

  test('a plain 403 stays a status for the caller', () async {
    final client = MockClient((_) async => http.Response('{}', 403));
    final response = await githubGet(
      client,
      api,
      timeout: const Duration(seconds: 5),
      gate: gate,
    );
    expect(response.statusCode, 403);
    expect(gate.remaining, isNull);
  });

  test('X-RateLimit-Reset against the server Date closes the gate', () async {
    final server = DateTime.utc(2026, 10, 1, 9);
    final reset = server.add(const Duration(minutes: 3));
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        '',
        403,
        headers: {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
          'date': HttpDate.format(server),
        },
      );
    });
    Future<http.Response> get() =>
        githubGet(client, api, timeout: const Duration(seconds: 5), gate: gate);

    await expectLater(
      get(),
      throwsA(
        isA<GithubRateLimitException>()
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(minutes: 3),
            )
            .having(
              (e) => e.resetAt,
              'resetAt',
              DateTime.utc(2026, 10, 1, 12, 3),
            ),
      ),
    );
    elapsed = const Duration(minutes: 1);
    await expectLater(
      get(),
      throwsA(
        isA<GithubRateLimitException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(minutes: 2),
        ),
      ),
    );
    expect(calls, 1);
    elapsed = const Duration(minutes: 3);
    await expectLater(get(), throwsA(isA<GithubRateLimitException>()));
    expect(calls, 2);
  });

  test('the gate leaves release downloads alone', () async {
    gate.close(const Duration(minutes: 5));
    final client = MockClient((_) async => http.Response('55', 200));
    final response = await githubGet(
      client,
      Uri.parse('https://github.com/o/r/releases/download/t/version.txt'),
      timeout: const Duration(seconds: 5),
      headers: githubUserAgentHeaders,
      gate: gate,
    );
    expect(response.statusCode, 200);
  });

  test('a capped wait never exceeds an hour', () {
    final limit = githubRateLimitOf(
      http.Response('', 429, headers: {'retry-after': '999999'}),
    );
    expect(limit!.wait, githubRateLimitMaxWait);
    expect(
      githubRateLimitOf(http.Response('', 429, headers: {'retry-after': 'x'})),
      isNull,
    );
  });

  test('companion discovery reports the rate limit and fails fast', () async {
    var apiCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host == githubApiHost) apiCalls++;
      return http.Response('', 403, headers: {'retry-after': '600'});
    });
    final temp = await Directory.systemTemp.createTemp('github-fetch-');
    addTearDown(() => temp.delete(recursive: true));
    final mirror = CompanionAssetsMirror(httpClient: client);
    addTearDown(mirror.dispose);

    final errors = <Object>[];
    await mirror.sync(
      destDir: temp.path,
      onWarning: (_, error) => errors.add(error),
    );
    expect(errors, isNotEmpty);
    expect(errors, everyElement(isA<GithubRateLimitException>()));
    final afterSync = apiCalls;

    await expectLater(
      mirror.peekPending(destDir: temp.path),
      throwsA(isA<GithubRateLimitException>()),
    );
    expect(apiCalls, afterSync);
  });

  test('a rate-limited semantic release is not reported as invalid', () async {
    final client = MockClient(
      (_) async => http.Response('', 403, headers: {'retry-after': '60'}),
    );
    final temp = await Directory.systemTemp.createTemp('github-fetch-');
    addTearDown(() => temp.delete(recursive: true));
    final assets = SemanticSearchAssets(httpClient: client);
    addTearDown(assets.dispose);
    await expectLater(
      assets.peekPending(mirrorDir: temp.path, libraryTag: 'v30-abc'),
      throwsA(
        isA<GithubRateLimitException>().having(
          (e) => e.retryAfterMinutes,
          'minutes',
          1,
        ),
      ),
    );
  });
}
