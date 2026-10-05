import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:error_reports_manager/src/search_feedback/search_feedback_identity.dart';
import 'package:error_reports_manager/src/search_feedback/search_feedback_queue.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String source, destination;
  late SearchFeedbackIdentity identity;
  late SearchFeedbackQueue queue;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('search-feedback-test-');
    source = p.join(temporary.path, 'source');
    destination = p.join(temporary.path, 'drive');
    identity = SearchFeedbackIdentity.fromSeed(List.filled(32, 7));
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    queue =
        SearchFeedbackQueue(() async => Directory(source), clock: DateTime.now);
    await queue.append({
      'type': 'search',
      'eventId': 'test-event-id',
      'clientTime': DateTime.now().toUtc().toIso8601String(),
      'query': 'תורה',
    }, {
      'app': 'otzaria',
      'appVersion': '1.2',
      'platform': 'windows'
    });
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('persisted paths cannot expose or remove files outside the queue',
      () async {
    final victim = File(p.join(temporary.path, 'seg-victim.jsonl'));
    const contents = '{"app":"otzaria"}\n{"query":"private"}\n';
    await victim.writeAsString(contents);
    final metadata = File(p.join(source, 'queue-state.json'));
    final state = jsonDecode(await metadata.readAsString()) as Map;
    (state['segments'] as List).add({
      'name': '../seg-victim.jsonl',
      'events': 1,
      'bytes': contents.length,
    });
    await metadata.writeAsString(jsonEncode(state));
    expect(await queue.sealAndList(), hasLength(1));
    for (final name in [
      '../seg-victim.jsonl',
      r'..\seg-victim.jsonl',
      victim.path,
      'seg-../seg-victim.jsonl',
      'queue-state.json',
    ]) {
      expect(await queue.read(name), isNull);
      expect(await queue.claim(name), isNull);
      await queue.split(name);
      await queue.remove(name);
      expect(await victim.readAsString(), contents);
    }
    expect(await File(p.join(source, 'queue-state.json')).exists(), true);
  });

  test('consent denial leaves queue and drive untouched', () async {
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.collect(source, mayCollect: () async => false), 0);
    expect(await transport.pending(source), 1);
    expect(await Directory(destination).exists(), false);
  });

  test('failed drive write leaves source events available', () async {
    await Directory(destination).create();
    await File(p.join(destination, identity.keyId))
        .writeAsString('blocked path');
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    await expectLater(transport.collect(source, mayCollect: () async => true),
        throwsA(isA<FileSystemException>()));
    expect(await transport.pending(source), 1);
  });

  test('transport preserves context events key and signed upstream protocol',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.headers['user-agent'], 'otzaria-search-feedback/1.2');
      expect(
          ed.VerifyKey(identity.publicKey).verify(
            signature: ed.Signature(
                base64.decode(request.headers['X-Otzaria-Signature']!)),
            message: request.bodyBytes,
          ),
          true);
      final body = jsonDecode(request.body) as Map;
      expect(body['schema'], 1);
      if (request.url.path.endsWith('/register')) {
        expect(body['publicKey'], identity.publicKeyBase64);
        return http.Response(jsonEncode({'keyId': identity.keyId}), 200);
      }
      expect(request.url.path, '/api/search-feedback/events');
      expect(request.headers['X-Otzaria-Key-Id'], identity.keyId);
      expect(body['context']['appVersion'], '1.2');
      expect(body['events'].single['query'], 'תורה');
      expect(request.body.contains('תורה'), false);
      return http.Response('{"accepted":1,"rejected":0}', 200);
    });
    final transport = SearchFeedbackTransport(destination, client: client);
    addTearDown(transport.close);
    expect(await transport.collect(source, mayCollect: () async => true), 1);
    expect(await transport.pending(source), 0);
    expect(await transport.count(), 1);
    expect(await transport.upload(), (sent: 1, rejected: 0, remaining: 0));
    expect(requests, 2);
  });

  test('filter response keeps collected data for another attempt', () async {
    identity.registeredKeyId = identity.keyId;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    final transport = SearchFeedbackTransport(destination,
        client: MockClient(
            (_) async => http.Response('<html>blocked</html>', 200)));
    addTearDown(transport.close);
    await transport.collect(source, mayCollect: () async => true);
    expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 1));
    final block = File(p.join(destination, 'network-block.json'));
    expect(
        (jsonDecode(await block.readAsString()) as Map)['delaySeconds'], 21600);
    await File(p.join(destination, 'retry-at.txt')).writeAsString(
      DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String(),
    );
    expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 1));
    expect(
        (jsonDecode(await block.readAsString()) as Map)['delaySeconds'], 43200);
  });

  test('blocked key cannot be resumed or collected', () async {
    identity.blocked = true;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.resumeAfterConsent(source), false);
    expect(await transport.collect(source, mayCollect: () async => true), 0);
    expect(await transport.pending(source), 1);
  });

  test('blocked carried identity cannot be restored from the offline machine',
      () async {
    final blocked =
        SearchFeedbackIdentity.fromSeed(List.filled(32, 7), blocked: true);
    await SearchFeedbackIdentityStore(
      () async => Directory(p.join(destination, identity.keyId)),
    ).save(blocked);
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.collect(source, mayCollect: () async => true), 0);
    expect(await transport.resumeAfterConsent(source), false);
    expect(await transport.pending(source), 1);
    expect(
        (await SearchFeedbackIdentityStore(
          () async => Directory(p.join(destination, identity.keyId)),
        ).load())!
            .blocked,
        true);
  });

  test(
      'registration Retry-After stops other installations and persists across clicks',
      () async {
    final other = SearchFeedbackIdentity.fromSeed(List.filled(32, 8));
    final otherSource = p.join(temporary.path, 'other');
    await SearchFeedbackIdentityStore(() async => Directory(otherSource))
        .save(other);
    await SearchFeedbackQueue(() async => Directory(otherSource),
            clock: DateTime.now)
        .append({
      'type': 'search',
      'eventId': 'other-event-id',
      'clientTime': DateTime.now().toUtc().toIso8601String()
    }, {
      'app': 'otzaria',
      'appVersion': '1.2',
      'platform': 'windows'
    });
    var requests = 0;
    final transport =
        SearchFeedbackTransport(destination, client: MockClient((_) async {
      requests++;
      return http.Response('{"error":"rate_limited"}', 429,
          headers: {'retry-after': '120'});
    }));
    addTearDown(transport.close);
    await transport.collect(source, mayCollect: () async => true);
    await transport.collect(otherSource, mayCollect: () async => true);
    expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 2));
    expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 2));
    expect(requests, 1);
  });

  test(
      'unknown key registers once and retries events with the same installation',
      () async {
    identity.registeredKeyId = identity.keyId;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    var events = 0, registrations = 0;
    final transport = SearchFeedbackTransport(destination,
        client: MockClient((request) async {
      if (request.url.path.endsWith('/register')) {
        registrations++;
        return http.Response(jsonEncode({'keyId': identity.keyId}), 200);
      }
      events++;
      return events == 1
          ? http.Response('{"error":"unknown_key"}', 401)
          : http.Response('{"accepted":1}', 200);
    }));
    addTearDown(transport.close);
    await transport.collect(source, mayCollect: () async => true);
    expect(await transport.upload(), (sent: 1, rejected: 0, remaining: 0));
    expect(events, 2);
    expect(registrations, 1);
  });

  test('expired and local-only events are never sent to production', () async {
    await queue.purge();
    await queue.resume();
    await queue.append({
      'type': 'search',
      'eventId': 'expired-event',
      'clientTime': DateTime.now()
          .subtract(const Duration(days: 30))
          .toUtc()
          .toIso8601String()
    }, {
      'app': 'otzaria',
      'appVersion': '1.2'
    });
    await queue.append({
      'type': 'search',
      'eventId': 'local-event',
      'clientTime': DateTime.now().toUtc().toIso8601String()
    }, {
      'app': 'otzaria',
      'appVersion': '1.2',
      'localOnly': true
    });
    var requests = 0;
    final transport =
        SearchFeedbackTransport(destination, client: MockClient((_) async {
      requests++;
      return http.Response('{"accepted":1}', 200);
    }));
    addTearDown(transport.close);
    await transport.collect(source, mayCollect: () async => true);
    expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 0));
    expect(requests, 0);
  });
}
