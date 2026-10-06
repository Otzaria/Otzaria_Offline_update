import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/src/search_feedback/search_feedback_identity.dart';
import 'package:error_reports_manager/src/search_feedback/search_feedback_sender.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);
  final protocolErrors = {
    'invalid_json': SearchFeedbackOutcomeKind.drop,
    'bad_signature': SearchFeedbackOutcomeKind.drop,
    'invalid_payload': SearchFeedbackOutcomeKind.drop,
    'unknown_key': SearchFeedbackOutcomeKind.unknownKey,
    'key_blocked': SearchFeedbackOutcomeKind.keyBlocked,
    'too_large': SearchFeedbackOutcomeKind.tooLarge,
    'rate_limited': SearchFeedbackOutcomeKind.retryLater,
    'shabbat': SearchFeedbackOutcomeKind.retryLater,
    'disabled': SearchFeedbackOutcomeKind.retryLater,
  };
  for (final entry in protocolErrors.entries) {
    for (final status in [400, 503]) {
      test('${entry.key} controls recovery on HTTP $status', () {
        final result = SearchFeedbackSender.classify(
            status, jsonEncode({'error': entry.key}), {'retry-after': '65'},
            now: now);
        expect(result.kind, entry.value);
        expect(result.retryAfter, const Duration(seconds: 65));
        expect(
            result.strike,
            status == 503 && !['shabbat', 'disabled'].contains(entry.key)
                ? SearchFeedbackStrike.serverError
                : SearchFeedbackStrike.none);
      });
    }
  }

  for (final status in [200, 400, 401, 403, 404, 408, 429, 500, 502]) {
    test('non-protocol HTTP $status preserves data for retry', () {
      for (final body in ['<html>blocked</html>', '[]', 'null', '{}']) {
        final result =
            SearchFeedbackSender.classify(status, body, {}, now: now);
        expect(result.kind, SearchFeedbackOutcomeKind.retryLater);
        expect(
            result.strike,
            status >= 500
                ? SearchFeedbackStrike.serverError
                : [408, 429].contains(status)
                    ? SearchFeedbackStrike.none
                    : SearchFeedbackStrike.filtered);
      }
    });
  }

  for (final entry in {
    400: SearchFeedbackOutcomeKind.drop,
    401: SearchFeedbackOutcomeKind.drop,
    422: SearchFeedbackOutcomeKind.drop,
    413: SearchFeedbackOutcomeKind.tooLarge,
    409: SearchFeedbackOutcomeKind.retryLater
  }.entries) {
    test('unrecognized protocol error uses HTTP ${entry.key}', () {
      expect(
          SearchFeedbackSender.classify(
                  entry.key, '{"error":"future_code"}', {},
                  now: now)
              .kind,
          entry.value);
    });
  }

  test('HTTP 413 without JSON requests splitting', () {
    expect(SearchFeedbackSender.classify(413, '', {}, now: now).kind,
        SearchFeedbackOutcomeKind.tooLarge);
  });

  test('successful partial acceptance keeps the rejected count', () {
    final result = SearchFeedbackSender.classify(
        202, '{"accepted":3,"rejected":2}', {},
        now: now);
    expect(result.kind, SearchFeedbackOutcomeKind.accepted);
    expect(result.rejected, 2);
    expect(result.keyId, isNull);
  });

  test('malformed optional success fields do not become keys or counters', () {
    final result = SearchFeedbackSender.classify(
        200, '{"keyId":42,"rejected":"2"}', {},
        now: now);
    expect(result.kind, SearchFeedbackOutcomeKind.accepted);
    expect(result.keyId, isNull);
    expect(result.rejected, 0);
  });

  for (final value in [null, '', ' ', '-1', '1.5', 'tomorrow']) {
    test('invalid Retry-After $value does not invent a delay', () {
      expect(SearchFeedbackSender.parseRetryAfter(value, now: now), isNull);
    });
  }
  test('Retry-After supports seconds and HTTP dates with a zero lower bound',
      () {
    expect(SearchFeedbackSender.parseRetryAfter(' 65 ', now: now),
        const Duration(seconds: 65));
    expect(
        SearchFeedbackSender.parseRetryAfter(
            HttpDate.format(now.add(const Duration(seconds: 90))),
            now: now),
        const Duration(seconds: 90));
    expect(
        SearchFeedbackSender.parseRetryAfter(
            HttpDate.format(now.subtract(const Duration(seconds: 90))),
            now: now),
        Duration.zero);
  });

  SearchFeedbackSender sender(http.Client client,
          {Duration timeout = const Duration(seconds: 1)}) =>
      SearchFeedbackSender(
          client: () => client,
          baseUrl: Uri.parse('https://otzaria.org'),
          clock: () => now,
          timeout: timeout);
  SearchFeedbackIdentity identity() =>
      SearchFeedbackIdentity.fromSeed(List.filled(32, 7));

  test(
      'register and events sign exact transmitted bytes with distinct key headers',
      () async {
    final key = identity();
    var calls = 0;
    const body = '{"query":"תורה"}';
    final client = MockClient((request) async {
      calls++;
      expect(request.bodyBytes, utf8.encode(body));
      expect(
          request.headers['content-type'], 'application/json; charset=utf-8');
      expect(request.headers['user-agent'], 'otzaria-search-feedback/1.2');
      expect(
          ed.VerifyKey(key.publicKey).verify(
              signature: ed.Signature(
                  base64.decode(request.headers['X-Otzaria-Signature']!)),
              message: request.bodyBytes),
          isTrue);
      expect(
          request.url.path,
          calls == 1
              ? '/api/search-feedback/register'
              : '/api/search-feedback/events');
      expect(
          request.headers['X-Otzaria-Key-Id'], calls == 1 ? isNull : key.keyId);
      return http.Response('{"keyId":"registered-key"}', 200);
    });
    addTearDown(client.close);
    final transport = sender(client);
    expect(
        (await transport.register(identity: key, body: body, appVersion: '1.2'))
            .keyId,
        'registered-key');
    expect(
        (await transport.sendEvents(
                identity: key, body: body, appVersion: '1.2'))
            .kind,
        SearchFeedbackOutcomeKind.accepted);
    expect(calls, 2);
  });

  for (final allowedChecks in [0, 1]) {
    test('revoked consent after $allowedChecks checks prevents HTTP entirely',
        () async {
      var checks = 0;
      final client = MockClient((_) async => fail('consent revoked'));
      addTearDown(client.close);
      final result = await sender(client).sendEvents(
          identity: identity(),
          body: '{}',
          appVersion: '1.2',
          canSend: () => checks++ < allowedChecks);
      expect(result.kind, SearchFeedbackOutcomeKind.retryLater);
      expect(checks, allowedChecks + 1);
    });
  }

  for (final error in [
    const SocketException('offline'),
    http.ClientException('closed'),
    const HandshakeException('TLS'),
    TimeoutException('slow')
  ]) {
    test(
        '${error.runtimeType} retains the batch without counting a server strike',
        () async {
      final client = MockClient((_) async => throw error);
      addTearDown(client.close);
      final result = await sender(client)
          .sendEvents(identity: identity(), body: '{}', appVersion: '1.2');
      expect(result.kind, SearchFeedbackOutcomeKind.retryLater);
      expect(result.strike, SearchFeedbackStrike.none);
    });
  }

  test('an unfinished request reaches the configured timeout', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);
    final result =
        await sender(client, timeout: const Duration(milliseconds: 20))
            .sendEvents(identity: identity(), body: '{}', appVersion: '1.2');
    expect(result.kind, SearchFeedbackOutcomeKind.retryLater);
    expect(result.strike, SearchFeedbackStrike.none);
    pending.complete(http.Response('{"accepted":1}', 200));
  });
}
