import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:error_reports_manager/src/search_feedback/search_feedback_queue.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> _writeFromIsolate(
    String path, int writer, String timestamp) async {
  final time = DateTime.parse(timestamp);
  final queue =
      SearchFeedbackQueue(() async => Directory(path), clock: () => time);
  for (var i = 0; i < 6; i++) {
    await queue.append(
        {'eventId': '$writer-$i'}, {'app': 'otzaria', 'writer': writer});
  }
}

void main() {
  late Directory temporary;
  late Directory directory;
  late SearchFeedbackQueue queue;
  final now = DateTime.utc(2026, 10, 6, 12);
  const context = {'app': 'otzaria', 'appVersion': '1.2'};

  SearchFeedbackQueue create({
    int maxEvents = 5000,
    int maxBytes = 5000000,
    int segmentEvents = 100,
    int segmentBytes = 100000,
  }) =>
      SearchFeedbackQueue(
        () async => directory,
        clock: () => now,
        maxEvents: maxEvents,
        maxBytes: maxBytes,
        segmentEvents: segmentEvents,
        segmentBytes: segmentBytes,
      );

  Map<String, Object?> event(int id, {DateTime? time}) => {
        'eventId': '$id',
        'query': 'תורה $id',
        'clientTime': (time ?? now).toIso8601String(),
      };

  Future<List<Map<String, dynamic>>> readAll() async {
    final events = <Map<String, dynamic>>[];
    for (final name in await queue.sealAndList()) {
      events.addAll((await queue.read(name))!.eventLines.map(
            (line) => jsonDecode(line) as Map<String, dynamic>,
          ));
    }
    return events;
  }

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('feedback-queue-');
    directory = Directory(p.join(temporary.path, 'queue'));
    queue = create();
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('loading an absent queue does not create the data directory', () async {
    await queue.load();
    expect(queue.isEmpty, isTrue);
    expect(queue.byteCount, 0);
    expect(await directory.exists(), isFalse);
  });

  test('events and exact byte count survive a new queue instance', () async {
    await queue.append(event(1), context);
    await queue.append(event(2), context);
    final bytes = queue.byteCount;
    queue = create();
    await queue.load();
    expect(queue.eventCount, 2);
    expect(queue.byteCount, bytes);
    expect((await readAll()).map((e) => e['eventId']), ['1', '2']);
    final files =
        await directory.list().where((f) => f.path.endsWith('.jsonl')).toList();
    expect(await (files.single as File).length(), bytes);
  });

  test('changing context starts a separate batch', () async {
    await queue.append(event(1), context);
    await queue.append(event(2), {...context, 'appVersion': '1.3'});
    final names = await queue.sealAndList();
    expect(names, hasLength(2));
    expect(jsonDecode((await queue.read(names[0]))!.contextJson)['appVersion'],
        '1.2');
    expect(jsonDecode((await queue.read(names[1]))!.contextJson)['appVersion'],
        '1.3');
  });

  for (final limit in [1, 2, 3]) {
    test('segment limit $limit preserves every event in order', () async {
      queue = create(segmentEvents: limit);
      for (var i = 0; i < 7; i++) {
        await queue.append(event(i), context);
      }
      final names = await queue.sealAndList();
      expect(names, hasLength((7 / limit).ceil()));
      for (final name in names) {
        expect((await queue.read(name))!.eventLines.length,
            lessThanOrEqualTo(limit));
      }
      expect((await readAll()).map((e) => e['eventId']),
          List.generate(7, (i) => '$i'));
    });
  }

  test('event cap evicts oldest batches and retains recent events', () async {
    queue = create(maxEvents: 2, segmentEvents: 1);
    for (var i = 0; i < 4; i++) {
      await queue.append(event(i), context);
    }
    expect(queue.eventCount, 2);
    expect((await readAll()).map((e) => e['eventId']), ['2', '3']);
  });

  test('byte cap evicts an entire oversized batch', () async {
    queue = create(maxBytes: 1);
    await queue.append(event(1), context);
    expect(queue.isEmpty, isTrue);
    expect(queue.byteCount, 0);
    expect(await queue.sealAndList(), isEmpty);
  });

  test('oversized event is rejected without replacing existing events',
      () async {
    queue = create(segmentBytes: 200);
    await queue.append(event(1), context);
    await queue.append({'query': List.filled(300, 'x').join()}, context);
    expect(queue.eventCount, 1);
    expect((await readAll()).single['eventId'], '1');
  });

  test('concurrent queue instances retain all events without mixing contexts',
      () async {
    final other = create();
    await Future.wait([
      for (var i = 0; i < 12; i++)
        (i.isEven ? queue : other)
            .append(event(i), {...context, 'window': i % 2}),
    ]);
    await queue.load();
    expect(queue.eventCount, 12);
    expect((await readAll()).map((e) => e['eventId']),
        unorderedEquals(List.generate(12, (i) => '$i')));
    for (final name in await queue.sealAndList()) {
      final batch = (await queue.read(name))!;
      final window = jsonDecode(batch.contextJson)['window'];
      for (final line in batch.eventLines) {
        expect(int.parse(jsonDecode(line)['eventId'] as String) % 2, window);
      }
    }
  });

  test('a claimed batch can be read and removed after restarting', () async {
    await queue.append(event(1), context);
    final original = (await queue.sealAndList()).single;
    final claimed = (await queue.claim(original))!;
    expect(claimed, endsWith('.claimed.jsonl'));
    queue = create();
    expect(await queue.claim(claimed), claimed);
    expect((await queue.read(claimed))!.eventLines, hasLength(1));
    await queue.remove(claimed);
    await queue.remove(claimed);
    expect(queue.isEmpty, isTrue);
    expect(await queue.read(claimed), isNull);
  });

  test('independent isolates serialize disk writes without losing events',
      () async {
    final path = directory.path;
    final timestamp = now.toIso8601String();
    await Future.wait([
      Isolate.run(() => _writeFromIsolate(path, 0, timestamp)),
      Isolate.run(() => _writeFromIsolate(path, 1, timestamp)),
    ]);
    await queue.load();
    expect(queue.eventCount, 12);
    expect(
        (await readAll()).map((e) => e['eventId']),
        unorderedEquals([
          for (var writer = 0; writer < 2; writer++)
            for (var i = 0; i < 6; i++) '$writer-$i',
        ]));
    for (final name in await queue.sealAndList()) {
      final batch = (await queue.read(name))!;
      final writer = jsonDecode(batch.contextJson)['writer'];
      for (final line in batch.eventLines) {
        expect(jsonDecode(line)['eventId'], startsWith('$writer-'));
      }
    }
  });

  test('claiming a missing batch returns null', () async {
    expect(await queue.claim('seg-missing.jsonl'), isNull);
  });

  for (final count in [1, 2, 3, 5]) {
    test('splitting $count events preserves context and event order', () async {
      for (var i = 0; i < count; i++) {
        await queue.append(event(i), context);
      }
      final original = (await queue.sealAndList()).single;
      await queue.split(original);
      expect(await queue.read(original), isNull);
      final names = await queue.sealAndList();
      expect(names, hasLength(count == 1 ? 0 : 2));
      expect(
          (await readAll()).map((e) => e['eventId']),
          count == 1
              ? isEmpty
              : orderedEquals(List.generate(count, (i) => '$i')));
      for (final name in names) {
        expect(jsonDecode((await queue.read(name))!.contextJson), context);
      }
    });
  }

  test('read filters malformed and expired events at the exact cutoff',
      () async {
    await queue.append(event(1), context);
    final name = (await queue.sealAndList()).single;
    await File(p.join(directory.path, name)).writeAsString([
      jsonEncode(context),
      jsonEncode(event(0, time: now.subtract(const Duration(microseconds: 1)))),
      'not json',
      '[]',
      '{"clientTime":"invalid"}',
      jsonEncode(event(1)),
      jsonEncode(event(2, time: now.add(const Duration(seconds: 1)))),
      '',
    ].join('\n'));
    final batch = (await queue.read(name, notBefore: now))!;
    expect(batch.eventLines.map((line) => jsonDecode(line)['eventId']),
        ['1', '2']);
  });

  for (final header in ['not json', '[]', '{"app":"other"}']) {
    test('invalid context $header returns an empty batch', () async {
      await directory.create();
      await File(p.join(directory.path, 'seg-invalid.jsonl'))
          .writeAsString('$header\n${jsonEncode(event(1))}\n');
      final batch = (await queue.read('seg-invalid.jsonl'))!;
      expect(batch.contextJson, '{}');
      expect(batch.eventLines, isEmpty);
    });
  }

  test('strike counts persist and changing failure type resets the streak',
      () async {
    await queue.append(event(1), context);
    final name = (await queue.sealAndList()).single;
    expect((await queue.addStrike(name, 'server', now)).count, 1);
    queue = create();
    final later = now.add(const Duration(hours: 1));
    final second = await queue.addStrike(name, 'server', later);
    expect(second.count, 2);
    expect(second.firstAt, now);
    final changed = await queue.addStrike(name, 'filtered', later);
    expect(changed.count, 1);
    expect(changed.firstAt, later);
    await queue.clearStrikes(name);
    await queue.clearStrikes(name);
    expect(
        await File(p.join(directory.path, 'strikes.json')).exists(), isFalse);
  });

  test('claiming a batch transfers its persisted strike count', () async {
    await queue.append(event(1), context);
    final name = (await queue.sealAndList()).single;
    await queue.addStrike(name, 'server', now);
    final claimed = (await queue.claim(name))!;
    queue = create();
    expect((await queue.addStrike(claimed, 'server', now)).count, 2);
    await queue.remove(claimed);
    expect(
        await File(p.join(directory.path, 'strikes.json')).exists(), isFalse);
  });

  for (final content in ['invalid json', '[]', '{"seg-missing.jsonl":{}}']) {
    test('invalid or orphaned strikes $content do not block loading', () async {
      await queue.append(event(1), context);
      await File(p.join(directory.path, 'strikes.json')).writeAsString(content);
      queue = create();
      await queue.load();
      final name = (await queue.sealAndList()).single;
      expect((await queue.addStrike(name, 'server', now)).count, 1);
      expect(queue.eventCount, 1);
    });
  }

  for (final metadata in ['not json', '{}']) {
    test('corrupt metadata $metadata recovers persisted event files', () async {
      await queue.append(event(1), context);
      await File(p.join(directory.path, 'queue-state.json'))
          .writeAsString(metadata);
      queue = create();
      await queue.load();
      expect(queue.eventCount, 1);
      expect((await readAll()).single['eventId'], '1');
    });
  }

  test('stale context-only files are removed while recent ones survive',
      () async {
    await directory.create();
    final stale = File(p.join(directory.path, 'seg-stale.jsonl'));
    final recent = File(p.join(directory.path, 'seg-recent.jsonl'));
    for (final file in [stale, recent]) {
      await file.writeAsString('${jsonEncode(context)}\n');
    }
    await stale.setLastModified(now.subtract(const Duration(hours: 2)));
    await recent.setLastModified(now);
    await queue.load();
    expect(queue.eventCount, 0);
    expect(await stale.exists(), isFalse);
    expect(await recent.exists(), isTrue);
  });

  test('purge revokes writes until consent resumes and rejects old writes',
      () async {
    await queue.append(event(1), context);
    await queue.purge();
    expect(queue.isEmpty, isTrue);
    await queue.append(event(2), context);
    expect(queue.isEmpty, isTrue);
    await queue.resume();
    await queue.append(event(3), context, recordedAt: DateTime.utc(2000));
    expect(queue.isEmpty, isTrue);
    await queue.append(event(4), context);
    expect((await readAll()).single['eventId'], '4');
  });

  test('interrupted purge completes before events can be read', () async {
    await queue.append(event(1), context);
    await File(p.join(directory.path, '.dirty')).writeAsString('100');
    queue = create();
    await queue.load();
    expect(queue.isEmpty, isTrue);
    expect(await File('${directory.path}.epoch').readAsString(), 'revoked:100');
    expect(await File(p.join(directory.path, '.dirty')).exists(), isFalse);
  });

  test('directory resolution retries after failure', () async {
    var calls = 0;
    queue = SearchFeedbackQueue(() async {
      if (calls++ == 0) throw const FileSystemException('unavailable');
      return directory;
    }, clock: () => now);
    await expectLater(queue.load(), throwsA(isA<FileSystemException>()));
    await queue.append(event(1), context);
    expect(queue.eventCount, 1);
    expect(calls, 2);
  });

  test('removing a context key preserves the original and event lines', () {
    final batch = SearchFeedbackStoredBatch(
        segmentName: 'seg-test.jsonl',
        contextJson: jsonEncode({...context, 'private': 'value'}),
        eventLines: const ['{"id":1}']);
    final stripped = batch.withoutContextKey('private');
    expect(jsonDecode(stripped.contextJson), context);
    expect(jsonDecode(batch.contextJson)['private'], 'value');
    expect(stripped.eventLines, batch.eventLines);
    expect(stripped.segmentName, batch.segmentName);
  });
}
