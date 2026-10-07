import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../search_feedback/search_feedback_events.dart';
import '../search_feedback/search_feedback_identity.dart';
import '../search_feedback/search_feedback_queue.dart';
import '../search_feedback/search_feedback_queue_lock.dart';
import '../search_feedback/search_feedback_sender.dart';

typedef SearchFeedbackUploadResult = ({int sent, int rejected, int remaining});

/// נושא מקטעים קיימים של אוצריא; אינו רושם פעילות חיפוש בעצמו.
class SearchFeedbackTransport {
  SearchFeedbackTransport(this.directory, {http.Client? client, Uri? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Uri.parse('https://otzaria.org');

  final String directory;
  final http.Client _client;
  final Uri _baseUrl;
  bool _stopped = false;
  int _backoffStep = 0;

  static String dirIn(String dataDir) => p.join(dataDir, 'search-feedback');

  SearchFeedbackQueue _queue(String path) => SearchFeedbackQueue(
        () async => Directory(path),
        clock: DateTime.now,
      );

  Future<int> pending(String sourceDirectory) async {
    if (!await Directory(sourceDirectory).exists()) return 0;
    final queue = _queue(sourceDirectory);
    await queue.load();
    return queue.eventCount;
  }

  /// ההצעה כוללת רק אירועים קריאים עם מפתח שמאפשר איסוף.
  Future<int> pendingForCollection(String sourceDirectory) async {
    final identity = await SearchFeedbackIdentityStore(
      () async => Directory(sourceDirectory),
    ).load();
    if (identity == null || identity.blocked) return 0;
    final carried = await SearchFeedbackIdentityStore(
      () async => Directory(p.join(directory, identity.keyId)),
    ).load();
    if (carried?.blocked == true) return 0;
    if (!await Directory(sourceDirectory).exists()) return 0;
    final queue = _queue(sourceDirectory);
    var count = 0;
    await for (final file in Directory(sourceDirectory).list()) {
      if (file is! File) continue;
      final batch = await queue.read(p.basename(file.path));
      count += batch?.eventLines.length ?? 0;
    }
    return count;
  }

  /// חסימת שרת אינה נעקפת בהסכמה חדשה של המשתמש.
  Future<bool> resumeAfterConsent(String sourceDirectory) async {
    if (!await Directory(sourceDirectory).parent.exists()) return false;
    final identity = await SearchFeedbackIdentityStore(
      () async => Directory(sourceDirectory),
    ).load();
    if (identity?.blocked == true) return false;
    if (identity != null) {
      final carriedIdentity = await SearchFeedbackIdentityStore(
        () async => Directory(p.join(directory, identity.keyId)),
      ).load();
      if (carriedIdentity?.blocked == true) return false;
    }
    await _queue(sourceDirectory).resume();
    return true;
  }

  Future<int> count() async {
    var count = 0;
    if (!await Directory(directory).exists()) return count;
    await for (final entity in Directory(directory).list()) {
      if (entity is! Directory) continue;
      count += await pending(entity.path);
    }
    return count;
  }

  /// ההסכמה והיעדר תהליך פעיל נבדקים שוב לפני כל העברה.
  Future<int> collect(String sourceDirectory,
      {required Future<bool> Function() mayCollect}) async {
    if (!await mayCollect()) return 0;
    final identity = await SearchFeedbackIdentityStore(
      () async => Directory(sourceDirectory),
    ).load();
    if (identity == null || identity.blocked) return 0;
    await Directory(directory).create(recursive: true);
    final transportLock = await SearchFeedbackQueueLock.acquire(
      p.join(directory, 'transport.lock'),
    );
    try {
      final source = _queue(sourceDirectory);
      final destination = p.join(directory, identity.keyId);
      await Directory(destination).create(recursive: true);
      final destinationIdentity = SearchFeedbackIdentityStore(
        () async => Directory(destination),
      );
      final carriedIdentity = await destinationIdentity.load();
      if (carriedIdentity?.blocked == true) return 0;
      if (carriedIdentity == null) await destinationIdentity.save(identity);
      var collected = 0;
      for (final name in await source.sealAndList()) {
        if (!await mayCollect()) break;
        final claimed = await source.claim(name);
        if (claimed == null) continue;
        final batch = await source.read(claimed);
        if (batch == null) continue;
        final lock = await SearchFeedbackQueueLock.acquire('$destination.lock');
        try {
          // נשמר לפני המחיקה במקור, ושם המקטע מאפשר חזרה אחרי קריסה.
          await File(p.join(destination, '.dirty'))
              .writeAsString('', flush: true);
          final target = File(p.join(destination, claimed));
          final temp = File('${target.path}.tmp');
          await temp.writeAsString(
            '${batch.contextJson}\n${batch.eventLines.join('\n')}\n',
            flush: true,
          );
          await temp.rename(target.path);
        } finally {
          await lock.release();
        }
        await source.remove(claimed);
        collected += batch.eventLines.length;
      }
      return collected;
    } finally {
      await transportLock.release();
    }
  }

  void stop() => _stopped = true;
  void close() {
    stop();
    _client.close();
  }

  /// העלאה מפורשת בלבד, עם החתימה והפרוטוקול המקוריים של אוצריא.
  Future<SearchFeedbackUploadResult> upload() async {
    _stopped = false;
    var sent = 0, rejected = 0;
    await Directory(directory).create(recursive: true);
    final lock = await SearchFeedbackQueueLock.acquire(
      p.join(directory, 'transport.lock'),
    );
    try {
      final retryFile = File(p.join(directory, 'retry-at.txt'));
      final filteredFile = File(p.join(directory, 'network-block.json'));
      if (await retryFile.exists()) {
        final retryAt = DateTime.tryParse(await retryFile.readAsString());
        if (retryAt != null && retryAt.isAfter(DateTime.now())) {
          return (sent: 0, rejected: 0, remaining: await count());
        }
      }
      Future<void> defer(SearchFeedbackOutcome outcome) async {
        _stopped = true;
        _backoffStep++;
        var delay = outcome.retryAfter;
        if (outcome.strike == SearchFeedbackStrike.filtered) {
          var previous = 0;
          if (await filteredFile.exists()) {
            final block = jsonDecode(await filteredFile.readAsString()) as Map;
            previous = block['delaySeconds'] as int? ?? 0;
          }
          delay ??= Duration(seconds: previous == 0 ? 21600 : previous * 2);
          if (delay > const Duration(hours: 24)) {
            delay = const Duration(hours: 24);
          }
          if (outcome.retryAfter == null && delay < const Duration(hours: 6)) {
            delay = const Duration(hours: 6);
          }
          await filteredFile.writeAsString(
            jsonEncode({'delaySeconds': delay.inSeconds}),
            flush: true,
          );
        } else if (delay == null) {
          final factor = 1 << (_backoffStep > 21 ? 20 : _backoffStep - 1);
          delay = Duration(seconds: 30 * factor);
          if (delay > const Duration(hours: 6)) {
            delay = const Duration(hours: 6);
          }
        }
        if (delay > const Duration(hours: 24)) {
          delay = const Duration(hours: 24);
        }
        await retryFile.writeAsString(
          DateTime.now().add(delay).toUtc().toIso8601String(),
          flush: true,
        );
      }

      await for (final entity in Directory(directory).list()) {
        if (entity is! Directory || _stopped) continue;
        final store = SearchFeedbackIdentityStore(() async => entity);
        final identity = await store.load();
        if (identity == null || identity.blocked) continue;
        final queue = _queue(entity.path);
        final sender = SearchFeedbackSender(
          client: () => _client,
          baseUrl: _baseUrl,
          clock: DateTime.now,
        );
        for (final name in await queue.sealAndList()) {
          if (_stopped) break;
          final claimed = await queue.claim(name);
          if (claimed == null) continue;
          final batch = await queue.read(claimed,
              notBefore: DateTime.now().subtract(const Duration(days: 29)));
          if (batch == null) continue;
          final context = jsonDecode(batch.contextJson) as Map;
          if (batch.eventLines.isEmpty || context['localOnly'] == true) {
            await queue.remove(claimed);
            continue;
          }
          final version = context['appVersion'] as String? ?? '';
          Future<bool> register() async {
            final outcome = await sender.register(
              identity: identity,
              body: searchFeedbackJsonEncode({
                'schema': 1,
                'publicKey': identity.publicKeyBase64,
                'app': 'otzaria',
                'appVersion': truncateForSearchFeedback(version, 64),
                'platform': context['platform'],
                'createdAt': searchFeedbackIsoTime(DateTime.now()),
              }),
              appVersion: version,
              canSend: () => !_stopped,
            );
            if (outcome.kind == SearchFeedbackOutcomeKind.keyBlocked) {
              identity.blocked = true;
              await store.save(identity);
              await queue.purge();
            }
            if (outcome.kind != SearchFeedbackOutcomeKind.accepted ||
                (outcome.keyId != null && outcome.keyId != identity.keyId)) {
              await defer(outcome);
              return false;
            }
            identity.registeredKeyId = identity.keyId;
            await store.save(identity);
            return true;
          }

          if (!identity.isRegistered && !await register()) break;
          Future<SearchFeedbackOutcome> post() => sender.sendEvents(
                identity: identity,
                body: '{"schema":1,"batchId":"${newSearchFeedbackId()}",'
                    '"sentAt":"${searchFeedbackIsoTime(DateTime.now())}",'
                    '"context":${batch.contextJson},'
                    '"events":[${batch.eventLines.join(',')}]}',
                appVersion: version,
                canSend: () => !_stopped,
              );
          var outcome = await post();
          if (outcome.kind == SearchFeedbackOutcomeKind.unknownKey) {
            identity.registeredKeyId = null;
            await store.save(identity);
            if (!await register()) break;
            outcome = await post();
          }
          switch (outcome.kind) {
            case SearchFeedbackOutcomeKind.accepted:
              sent += batch.eventLines.length - outcome.rejected;
              rejected += outcome.rejected;
              await queue.remove(claimed);
              _backoffStep = 0;
              if (await retryFile.exists()) await retryFile.delete();
              if (await filteredFile.exists()) await filteredFile.delete();
            case SearchFeedbackOutcomeKind.drop:
              rejected += batch.eventLines.length;
              await queue.remove(claimed);
            case SearchFeedbackOutcomeKind.tooLarge:
              await queue.split(claimed);
            case SearchFeedbackOutcomeKind.keyBlocked:
              identity.blocked = true;
              await store.save(identity);
              await queue.purge();
              _stopped = true;
            case SearchFeedbackOutcomeKind.unknownKey:
            case SearchFeedbackOutcomeKind.retryLater:
              // לא מוחקים נתונים כשמסנן מחזיר דף חסימה או כשאין רשת.
              if (outcome.strike == SearchFeedbackStrike.serverError) {
                final record = await queue.addStrike(
                  claimed,
                  outcome.strike.name,
                  DateTime.now(),
                );
                if (record.count >= 5 &&
                    DateTime.now().difference(record.firstAt) >=
                        const Duration(hours: 24)) {
                  rejected += batch.eventLines.length;
                  await queue.remove(claimed);
                }
              }
              await defer(outcome);
          }
          if (_stopped) break;
        }
      }
      return (sent: sent, rejected: rejected, remaining: await count());
    } finally {
      await lock.release();
    }
  }
}
