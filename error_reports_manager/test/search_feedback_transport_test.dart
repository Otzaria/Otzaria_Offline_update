import 'dart:async';
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

  for (final contents in <String?>[null, '{"app":"otzaria"}\n']) {
    test('pending ignores stale metadata for segment contents $contents',
        () async {
      final name = (await queue.sealAndList()).single;
      final file = File(p.join(source, name));
      if (contents == null) {
        await file.delete();
      } else {
        await file.writeAsString(contents);
      }
      final transport = SearchFeedbackTransport(destination);
      addTearDown(transport.close);
      expect(await transport.pending(source), 0);
    });
  }

  for (final kind in ['missing', 'blocked', 'carriedBlocked']) {
    test('collection offer ignores $kind identity', () async {
      if (kind == 'missing') {
        await SearchFeedbackIdentityStore(() async => Directory(source))
            .delete();
      } else {
        identity.blocked = true;
        await SearchFeedbackIdentityStore(() async => Directory(
            kind == 'blocked'
                ? source
                : p.join(destination, identity.keyId))).save(identity);
      }
      final transport = SearchFeedbackTransport(destination);
      addTearDown(transport.close);
      expect(await transport.pendingForCollection(source), 0);
      expect(await transport.pending(source), 1);
    });
  }

  test('collection offer ignores batches without readable events', () async {
    final name = (await queue.sealAndList()).single;
    await File(p.join(source, name))
        .writeAsString('{"app":"otzaria"}\ninvalid\n');
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.pendingForCollection(source), 0);
  });

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

  test('local-only segments stay in source and do not enter collection counts',
      () async {
    await queue.append({'type': 'search', 'query': 'private debug'},
        {'app': 'otzaria', 'localOnly': true});
    final privateName = (await queue.sealAndList()).last;
    final privateFile = File(p.join(source, privateName));
    await privateFile.writeAsString((await privateFile.readAsString())
        .replaceAll('"localOnly":true', '"localOnly" : true'));
    final privateBytes = await privateFile.readAsBytes();
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.pendingForCollection(source), 1);
    expect(await transport.collect(source, mayCollect: () async => true), 1);
    expect(await privateFile.readAsBytes(), privateBytes);
    expect(await transport.pendingForCollection(source), 0);
    expect(await transport.count(), 1);
    final carried = SearchFeedbackQueue(
        () async => Directory(p.join(destination, identity.keyId)),
        clock: DateTime.now);
    await carried
        .append({'type': 'search'}, {'app': 'otzaria', 'localOnly': true});
    expect(await transport.count(), 1);
  });

  test('only local data does not carry a signing identity', () async {
    await queue.purge();
    await queue.resume();
    await queue.append({'type': 'search', 'query': 'private debug'},
        {'app': 'otzaria', 'localOnly': true});
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.pendingForCollection(source), 0);
    expect(await transport.collect(source, mayCollect: () async => true), 0);
    expect(await transport.pending(source), 1);
    expect(
        await SearchFeedbackIdentityStore(
            () async => Directory(p.join(destination, identity.keyId))).load(),
        isNull);
    expect(await transport.count(), 0);
  });

  for (final onDrive in [false, true]) {
    test(
        'legacy query redacted before ${onDrive ? 'upload' : 'collection'} with valid signature',
        () async {
      identity.registeredKeyId = identity.keyId;
      await SearchFeedbackIdentityStore(() async => Directory(source))
          .save(identity);
      final name = (await queue.sealAndList()).single;
      final file = File(p.join(source, name));
      final lines = const LineSplitter().convert(await file.readAsString());
      final event = jsonDecode(lines[1]) as Map<String, dynamic>;
      event.addAll({
        'query': 'שו"ת person+private@example.com תורה',
        'queryLength': 500,
        'queryWordCount': 99,
        'result': {'passageText': 'אמר דוד תורה person@example.com'},
      });
      final raw = '${lines.first}\n${jsonEncode(event)}\n';
      await file.writeAsString(raw);
      final carriedDirectory = p.join(destination, identity.keyId);
      if (onDrive) {
        await Directory(carriedDirectory).create(recursive: true);
        await SearchFeedbackIdentityStore(
            () async => Directory(carriedDirectory)).save(identity);
        await File(p.join(carriedDirectory, name)).writeAsString(raw);
      }
      Map? sent;
      final transport = SearchFeedbackTransport(destination,
          client: MockClient((request) async {
        expect(
            ed.VerifyKey(identity.publicKey).verify(
              signature: ed.Signature(
                  base64Decode(request.headers['X-Otzaria-Signature']!)),
              message: request.bodyBytes,
            ),
            isTrue);
        sent =
            ((jsonDecode(request.body) as Map)['events'] as List).single as Map;
        return http.Response('{"accepted":1}', 200);
      }));
      addTearDown(transport.close);
      if (!onDrive) {
        expect(
            await transport.collect(source, mayCollect: () async => true), 1);
        final carried = SearchFeedbackQueue(
            () async => Directory(carriedDirectory),
            clock: DateTime.now);
        final carriedFile = File(
            p.join(carriedDirectory, (await carried.sealAndList()).single));
        expect(await carriedFile.readAsString(),
            isNot(contains('person+private@example.com')));
      }
      expect(await transport.upload(), (sent: 1, rejected: 0, remaining: 0));
      expect(sent!['query'], 'שו"ת <email> תורה');
      expect(sent!['queryLength'], 'שו"ת <email> תורה'.length);
      expect(sent!['queryWordCount'], 3);
      expect(sent!['eventId'], event['eventId']);
      expect(sent!['result'], event['result']);
    });
  }

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

  test('no connection backs off on this computer only, not on the drive',
      () async {
    identity.registeredKeyId = identity.keyId;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    var offlineRequests = 0;
    final offline =
        SearchFeedbackTransport(destination, client: MockClient((_) async {
      offlineRequests++;
      throw const SocketException('down');
    }));
    addTearDown(offline.close);
    expect(await offline.retryAt(), isNull);
    await offline.collect(source, mayCollect: () async => true);
    final before = DateTime.now();
    expect(await offline.upload(), (sent: 0, rejected: 0, remaining: 1));
    final retryAt = await offline.retryAt();
    expect(retryAt, isNotNull);
    expect(retryAt!.isAfter(before.add(const Duration(seconds: 29))), isTrue);
    expect(await offline.upload(), (sent: 0, rejected: 0, remaining: 1));
    expect(offlineRequests, 1);
    expect(await File(p.join(destination, 'retry-at.txt')).exists(), isFalse);

    // אותו כונן במחשב המקוון: אין השהיה שנסעה איתו.
    var onlineRequests = 0;
    final online =
        SearchFeedbackTransport(destination, client: MockClient((_) async {
      onlineRequests++;
      return http.Response('{"accepted":1}', 200);
    }));
    addTearDown(online.close);
    expect(await online.retryAt(), isNull);
    expect(await online.upload(), (sent: 1, rejected: 0, remaining: 0));
    expect(onlineRequests, 1);
  });

  test('a server Retry-After travels with the drive and is honoured', () async {
    identity.registeredKeyId = identity.keyId;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    final first = SearchFeedbackTransport(destination,
        client: MockClient((_) async => http.Response(
            '{"error":"rate_limited"}', 429,
            headers: {'retry-after': '120'})));
    addTearDown(first.close);
    await first.collect(source, mayCollect: () async => true);
    expect(await first.upload(), (sent: 0, rejected: 0, remaining: 1));

    var requests = 0;
    final other =
        SearchFeedbackTransport(destination, client: MockClient((_) async {
      requests++;
      return http.Response('{"accepted":1}', 200);
    }));
    addTearDown(other.close);
    final retryAt = await other.retryAt();
    expect(retryAt, isNotNull);
    expect(retryAt!.isAfter(DateTime.now().add(const Duration(seconds: 100))),
        isTrue);
    expect(await other.upload(), (sent: 0, rejected: 0, remaining: 1));
    expect(requests, 0);
  });

  group('מקטע גדול מדי מפוצל ונשלח באותו סבב', () {
    Future<void> addEvents(int count) async {
      for (var i = 0; i < count; i++) {
        await queue.append({
          'type': 'search',
          'eventId': 'extra-$i',
          'clientTime': DateTime.now().toUtc().toIso8601String(),
          'query': 'q$i',
        }, {
          'app': 'otzaria',
          'appVersion': '1.2',
          'platform': 'windows'
        });
      }
    }

    Future<SearchFeedbackTransport> prepare(http.Client client) async {
      identity.registeredKeyId = identity.keyId;
      await SearchFeedbackIdentityStore(() async => Directory(source))
          .save(identity);
      await addEvents(3);
      final transport = SearchFeedbackTransport(destination, client: client);
      addTearDown(transport.close);
      expect(await transport.collect(source, mayCollect: () async => true), 4);
      return transport;
    }

    List<String> ids(http.Request request) => [
          for (final e in (jsonDecode(request.body) as Map)['events'] as List)
            (e as Map)['eventId'] as String,
        ];

    test('החצאים נשלחים באותו סבב, בלי אובדן ובלי כפילות', () async {
      final delivered = <String>[];
      var requests = 0;
      final transport = await prepare(MockClient((request) async {
        requests++;
        final batch = ids(request);
        if (batch.length > 2) {
          return http.Response('{"error":"too_large"}', 413);
        }
        delivered.addAll(batch);
        return http.Response('{"accepted":${batch.length}}', 200);
      }));

      expect(await transport.upload(), (sent: 4, rejected: 0, remaining: 0));
      expect(requests, 3);
      expect(delivered..sort(),
          ['extra-0', 'extra-1', 'extra-2', 'test-event-id']);
      expect(await transport.count(), 0);
    });

    test('כשל זמני אחרי הצלחה חלקית: נשמר רק מה שטרם אושר, והמשך בלי כפילות',
        () async {
      final delivered = <String>[];
      var failSecond = true;
      final transport = await prepare(MockClient((request) async {
        final batch = ids(request);
        if (batch.length > 2) {
          return http.Response('{"error":"too_large"}', 413);
        }
        if (failSecond && delivered.isNotEmpty) {
          return http.Response('{"error":"rate_limited"}', 429,
              headers: {'retry-after': '120'});
        }
        delivered.addAll(batch);
        return http.Response('{"accepted":${batch.length}}', 200);
      }));

      expect(await transport.upload(), (sent: 2, rejected: 0, remaining: 2));
      expect(delivered, hasLength(2));
      expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 2));

      failSecond = false;
      await File(p.join(destination, 'retry-at.txt')).writeAsString(
          DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toUtc()
              .toIso8601String());
      expect(await transport.upload(), (sent: 2, rejected: 0, remaining: 0));
      expect(delivered..sort(),
          ['extra-0', 'extra-1', 'extra-2', 'test-event-id']);
    });

    test('שרת שדוחה כל גודל: הפיצול נעצר, ואירוע בודד נספר כנדחה', () async {
      var requests = 0;
      final transport = await prepare(MockClient((request) async {
        requests++;
        return http.Response('{"error":"too_large"}', 413);
      }));

      expect(await transport.upload(), (sent: 0, rejected: 4, remaining: 0));
      expect(requests, lessThan(20));
      expect(await transport.count(), 0);
    });
  });

  for (final contents in ['{"delaySec', '[1]', '{"delaySeconds":"x"}']) {
    test('corrupt filter backoff $contents still defers the next attempt',
        () async {
      identity.registeredKeyId = identity.keyId;
      await SearchFeedbackIdentityStore(() async => Directory(source))
          .save(identity);
      var requests = 0;
      final transport =
          SearchFeedbackTransport(destination, client: MockClient((_) async {
        requests++;
        return http.Response('<html>blocked</html>', 200);
      }));
      addTearDown(transport.close);
      await transport.collect(source, mayCollect: () async => true);
      final block = File(p.join(destination, 'network-block.json'));
      await block.writeAsString(contents);
      expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 1));
      expect((jsonDecode(await block.readAsString()) as Map)['delaySeconds'],
          21600);
      final retryAt = DateTime.parse(
          await File(p.join(destination, 'retry-at.txt')).readAsString());
      expect(
          retryAt.isAfter(DateTime.now().add(const Duration(hours: 5))), true);
      expect(await transport.upload(), (sent: 0, rejected: 0, remaining: 1));
      expect(requests, 1);
      expect(await File(p.join(destination, 'network-block.json.tmp')).exists(),
          false);
    });
  }

  test('blockedByServer: a working key, or no key yet, is not blocked',
      () async {
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.blockedByServer(source), false);
    final empty = p.join(temporary.path, 'fresh-otzaria', 'search_feedback');
    await Directory(empty).create(recursive: true);
    expect(await transport.blockedByServer(empty), false);
    expect(await transport.resumeAfterConsent(source), true);
  });

  test('blocked key cannot be resumed or collected', () async {
    identity.blocked = true;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    final transport = SearchFeedbackTransport(destination);
    addTearDown(transport.close);
    expect(await transport.resumeAfterConsent(source), false);
    expect(await transport.blockedByServer(source), true);
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
    expect(await transport.blockedByServer(source), true);
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

  group('המפתח הפרטי בכונן', () {
    File carriedKey() => File(p.join(
        destination, identity.keyId, SearchFeedbackIdentityStore.fileName));

    test('איסוף שלא העביר אף מקטע אינו מעתיק את המפתח', () async {
      await queue.purge();
      final transport = SearchFeedbackTransport(destination);
      addTearDown(transport.close);

      expect(await transport.collect(source, mayCollect: () async => true), 0);
      expect(carriedKey().existsSync(), isFalse);
    });

    test('נמחק מהכונן כשכל המקטעים נשלחו, ונשאר כשנותר מה לשלוח', () async {
      identity.registeredKeyId = identity.keyId;
      await SearchFeedbackIdentityStore(() async => Directory(source))
          .save(identity);
      var accept = false;
      final transport =
          SearchFeedbackTransport(destination, client: MockClient((_) async {
        return accept
            ? http.Response('{"accepted":1}', 200)
            : http.Response('', 503);
      }));
      addTearDown(transport.close);
      await transport.collect(source, mayCollect: () async => true);
      expect(carriedKey().existsSync(), isTrue);

      expect((await transport.upload()).remaining, 1);
      expect(carriedKey().existsSync(), isTrue);

      accept = true;
      await File(p.join(destination, 'retry-at.txt')).delete();
      expect(await transport.upload(), (sent: 1, rejected: 0, remaining: 0));
      expect(carriedKey().existsSync(), isFalse);
    });
  });

  group('carriedOffline (C6)', () {
    Future<void> addOld() => queue.append({
          'type': 'search',
          'eventId': 'old-event',
          'clientTime': DateTime.now()
              .subtract(const Duration(days: 40))
              .toUtc()
              .toIso8601String(),
        }, {
          'app': 'otzaria',
          'appVersion': '1.2',
          'platform': 'windows'
        });

    Future<void> registered() async {
      identity.registeredKeyId = identity.keyId;
      await SearchFeedbackIdentityStore(() async => Directory(source))
          .save(identity);
    }

    test('אירועים עד 89 יום נשלחים עם carriedOffline:true', () async {
      await addOld();
      await registered();
      final bodies = <Map<String, dynamic>>[];
      final transport =
          SearchFeedbackTransport(destination, client: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(body);
        return http.Response(
            '{"accepted":${(body['events'] as List).length}}', 200);
      }));
      addTearDown(transport.close);
      await transport.collect(source, mayCollect: () async => true);

      expect(await transport.upload(), (sent: 2, rejected: 0, remaining: 0));
      expect(bodies.single['carriedOffline'], isTrue);
    });

    test('שרת שדוחה את המנה — שליחה חוזרת בלי הדגל, בחלון של 29 יום', () async {
      await addOld();
      await registered();
      final bodies = <Map<String, dynamic>>[];
      final transport =
          SearchFeedbackTransport(destination, client: MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(body);
        if (bodies.length == 1) {
          return http.Response('{"error":"invalid","field":"x"}', 422);
        }
        return http.Response(
            '{"accepted":${(body['events'] as List).length}}', 200);
      }));
      addTearDown(transport.close);
      await transport.collect(source, mayCollect: () async => true);

      expect(await transport.upload(), (sent: 1, rejected: 1, remaining: 0));
      expect(bodies, hasLength(2));
      expect(bodies.last.containsKey('carriedOffline'), isFalse);
      expect(
          (bodies.last['events'] as List).single['eventId'], 'test-event-id');
    });
  });

  test('expired and local-only events are never sent to production', () async {
    await queue.purge();
    await queue.resume();
    await queue.append({
      'type': 'search',
      'eventId': 'expired-event',
      'clientTime': DateTime.now()
          .subtract(const Duration(days: 90))
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

  test('stop aborts the in-flight request without deferring the next run',
      () async {
    identity.registeredKeyId = identity.keyId;
    await SearchFeedbackIdentityStore(() async => Directory(source))
        .save(identity);
    final started = Completer<void>();
    var aborted = false;
    var calls = 0;
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      if (calls++ > 0) {
        return http.StreamedResponse(
            Stream.value(utf8.encode('{"accepted":1,"rejected":0}')), 200);
      }
      started.complete();
      await (request as http.Abortable).abortTrigger;
      aborted = true;
      throw http.RequestAbortedException(request.url);
    });
    final transport = SearchFeedbackTransport(destination, client: client);
    addTearDown(transport.close);
    await transport.collect(source, mayCollect: () async => true);
    final run = transport.upload();
    await started.future;
    transport.stop();
    expect(await run, (sent: 0, rejected: 0, remaining: 1));
    expect(aborted, isTrue);
    expect(await File(p.join(destination, 'retry-at.txt')).exists(), isFalse);
    expect(await transport.upload(), (sent: 1, rejected: 0, remaining: 0));
  });
}
