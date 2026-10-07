import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'search_feedback_events.dart';
import 'search_feedback_queue_lock.dart';

/// מקטע בתור: קובץ JSONL שהשורה הראשונה בו היא ה-ClientContext.
class SearchFeedbackSegment {
  SearchFeedbackSegment(this.name, {required this.events, required this.bytes});

  String name;
  int events;
  int bytes;
}

/// כשלים רצופים של מקטע מסוים, נשמרים על הדיסק כדי שיצטברו גם בין הפעלות.
class SearchFeedbackStrikeRecord {
  const SearchFeedbackStrikeRecord({
    required this.kind,
    required this.count,
    required this.firstAt,
  });

  final String kind;
  final int count;
  final DateTime firstAt;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'count': count,
        'firstAt': firstAt.toUtc().toIso8601String(),
      };

  static SearchFeedbackStrikeRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final count = json['count'];
    final firstAt = DateTime.tryParse('${json['firstAt']}');
    if (kind is! String || count is! int || firstAt == null) return null;
    return SearchFeedbackStrikeRecord(
      kind: kind,
      count: count,
      firstAt: firstAt,
    );
  }
}

/// אצווה שנקראה מהדיסק: ה-context והאירועים כשורות JSON גולמיות.
class SearchFeedbackStoredBatch {
  const SearchFeedbackStoredBatch({
    required this.segmentName,
    required this.contextJson,
    required this.eventLines,
  });

  final String segmentName;
  final String contextJson;
  final List<String> eventLines;

  /// אותה אצווה בלי [key] ב-context.
  SearchFeedbackStoredBatch withoutContextKey(String key) {
    final context = jsonDecode(contextJson) as Map<String, dynamic>
      ..remove(key);
    return SearchFeedbackStoredBatch(
      segmentName: segmentName,
      contextJson: searchFeedbackJsonEncode(context),
      eventLines: eventLines,
    );
  }
}

/// תור משותף לחלונות. רק worker נוגע בדיסק; נעילת OS מגינה גם בין תהליכים.
class SearchFeedbackQueue {
  SearchFeedbackQueue(
    this._directory, {
    required DateTime Function() clock,
    this.maxEvents = 5000,
    this.maxBytes = 5 * 1024 * 1024,
    this.segmentEvents = SearchFeedbackLimits.eventsPerBatch,
    this.segmentBytes = SearchFeedbackLimits.batchBytes -
        SearchFeedbackLimits.batchEnvelopeReserve,
  })  : _clock = clock,
        _owner = newSearchFeedbackId();
  static const strikesFileName = 'strikes.json';
  // כל האובייקטים באותו isolate משתמשים באותו סדר; ה-OS מסנכרן תהליכים.
  static final Map<String, Future<void>> _tails = {};
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final String _owner;
  final int maxEvents, maxBytes, segmentEvents, segmentBytes;
  int _events = 0, _bytes = 0;
  Future<String>? _resolvedPath;
  int get eventCount => _events;
  int get byteCount => _bytes;
  bool get isEmpty => _events == 0;
  Future<dynamic> _run(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    final resolving = _resolvedPath ??= _canonicalDirectory(_directory);
    late final String path;
    try {
      path = await resolving;
    } catch (_) {
      if (identical(_resolvedPath, resolving)) _resolvedPath = null;
      rethrow;
    }
    final previous = _tails[path] ?? Future<void>.value();
    final result = previous.then(
      (_) => _queueWorker(
        path,
        _owner,
        _clock(),
        maxEvents,
        maxBytes,
        segmentEvents,
        segmentBytes,
        op,
        args,
      ),
    );
    final tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _tails[path] = tail;
    try {
      final output = await result;
      _events = output['events'] as int;
      _bytes = output['bytes'] as int;
      return output['result'];
    } finally {
      if (identical(_tails[path], tail)) {
        unawaited(_tails.remove(path));
      }
    }
  }

  Future<void> load() async {
    await _run('load');
  }

  Future<void> append(
    Map<String, Object?> event,
    Map<String, Object?> context, {
    DateTime? recordedAt,
  }) async {
    final stamp = (recordedAt ?? DateTime.now()).microsecondsSinceEpoch;
    await _run('append', {
      'event': event,
      'context': context,
      'recordedAt': stamp,
    });
  }

  Future<List<String>> sealAndList() async =>
      List<String>.from(await _run('seal') as List);
  Future<String?> claim(String name) async =>
      await _run('claim', {'name': name}) as String?;
  Future<SearchFeedbackStoredBatch?> read(
    String name, {
    DateTime? notBefore,
  }) async {
    final value = await _run('read', {'name': name, 'notBefore': notBefore});
    if (value == null) return null;
    return SearchFeedbackStoredBatch(
      segmentName: name,
      contextJson: value['context'] as String,
      eventLines: List<String>.from(value['lines'] as List),
    );
  }

  Future<void> remove(String name) async {
    await _run('remove', {'name': name});
  }

  Future<void> split(String name) async {
    await _run('split', {'name': name});
  }

  Future<void> purge() async {
    await _run('purge');
  }

  /// שער הכתיבה המשותף נפתח רק אחרי הסכמה מפורשת חדשה.
  Future<void> resume() async {
    await _run('resume');
  }

  Future<SearchFeedbackStrikeRecord> addStrike(
    String name,
    String kind,
    DateTime now,
  ) async {
    final value = await _run('strike', {
      'name': name,
      'kind': kind,
      'now': now,
    });
    return SearchFeedbackStrikeRecord.fromJson(value)!;
  }

  Future<void> clearStrikes(String name) async {
    await _run('clearStrike', {'name': name});
  }
}

Future<String> _canonicalDirectory(
  Future<Directory> Function() directory,
) async {
  final requested = (await directory()).absolute;
  var existing = requested;
  while (!await existing.exists()) {
    existing = existing.parent;
  }
  final base = await existing.resolveSymbolicLinks();
  return p.normalize(
    p.join(base, p.relative(requested.path, from: existing.path)),
  );
}

Future<Map<String, Object?>> _queueWorker(
  String path,
  String owner,
  DateTime now,
  int maxEvents,
  int maxBytes,
  int segmentEvents,
  int segmentBytes,
  String op,
  Map<String, Object?> args,
) =>
    Isolate.run(
      () => _queueDisk(
        path,
        owner,
        now,
        maxEvents,
        maxBytes,
        segmentEvents,
        segmentBytes,
        op,
        args,
      ),
    );

Future<Map<String, Object?>> _queueDisk(
  String path,
  String owner,
  DateTime now,
  int maxEvents,
  int maxBytes,
  int segmentEvents,
  int segmentBytes,
  String op,
  Map<String, Object?> args,
) async {
  final dir = Directory(path);
  await dir.parent.create(recursive: true);
  final lock = await SearchFeedbackQueueLock.acquire('$path.lock');
  try {
    await _recoverPurge(path);
    final queue = _DiskQueue(
      () async => dir,
      clock: () => now,
      maxEvents: maxEvents,
      maxBytes: maxBytes,
      segmentEvents: segmentEvents,
      segmentBytes: segmentBytes,
    ).._owner = owner;
    await queue.load();
    dynamic value;
    final modifying = !{'load', 'read'}.contains(op);
    if (modifying) {
      await dir.create(recursive: true);
      await File(p.join(path, '.dirty')).writeAsString(
        op == 'purge' ? '${DateTime.now().microsecondsSinceEpoch}' : '',
        flush: true,
      );
    }
    switch (op) {
      case 'load':
        break;
      case 'append':
        final epoch = File('$path.epoch');
        final permission =
            await epoch.exists() ? await epoch.readAsString() : '';
        final cutoff = int.tryParse(permission.split(':').last) ?? 0;
        if (!permission.startsWith('revoked:') &&
            (args['recordedAt'] as int) > cutoff) {
          await queue.append(
            Map<String, Object?>.from(args['event'] as Map),
            Map<String, Object?>.from(args['context'] as Map),
          );
        }
      case 'resume':
        final epoch = File('$path.epoch');
        if (await epoch.exists()) {
          final cutoff = (await epoch.readAsString()).split(':').last;
          final temp = File('$path.epoch.tmp');
          await temp.writeAsString(cutoff, flush: true);
          await temp.rename(epoch.path);
        }
      case 'seal':
        value = await queue.sealAndList();
      case 'claim':
        value = await queue.claim(args['name'] as String);
      case 'read':
        final batch = await queue.read(
          args['name'] as String,
          notBefore: args['notBefore'] as DateTime?,
        );
        if (batch != null) {
          value = {'context': batch.contextJson, 'lines': batch.eventLines};
        }
      case 'remove':
        await queue.remove(args['name'] as String);
      case 'split':
        await queue.split(args['name'] as String);
      case 'strike':
        value = (await queue.addStrike(
          args['name'] as String,
          args['kind'] as String,
          args['now'] as DateTime,
        ))
            .toJson();
      case 'clearStrike':
        await queue.clearStrikes(args['name'] as String);
      case 'purge':
        // משאיר מחסום גם לכתיבה שכבר החלה בחלון אחר, בלי למחוק את קובץ הנעילה.
        final temp = File('$path.epoch.tmp');
        await temp.writeAsString(
          'revoked:${await File(p.join(path, '.dirty')).readAsString()}',
          flush: true,
        );
        await temp.rename('$path.epoch');
        await queue.purge();
    }
    if (modifying) {
      if (op == 'purge') {
        for (final name in [
          'queue-state.json',
          'queue-state.json.tmp',
          '.dirty',
        ]) {
          final file = File(p.join(path, name));
          if (await file.exists()) await file.delete();
        }
      } else {
        await queue._persist(dir);
      }
    }
    return {
      'result': value,
      'events': queue.eventCount,
      'bytes': queue.byteCount,
    };
  } finally {
    await lock.release();
  }
}

// יומן המחיקה שורד קריסה בין פרסום ביטול ההסכמה למחיקת האירועים.
// משלימים את המחיקה לפני שקריאה או כתיבה יוכלו לשחזר את האירועים הישנים.
Future<void> _recoverPurge(String path) async {
  final dirty = File(p.join(path, '.dirty'));
  if (!await dirty.exists()) return;
  final cutoff = int.tryParse(await dirty.readAsString());
  if (cutoff == null) return;
  final temp = File('$path.epoch.tmp');
  await temp.writeAsString('revoked:$cutoff', flush: true);
  await temp.rename('$path.epoch');
  await for (final entity in Directory(path).list()) {
    final name = p.basename(entity.path);
    if (entity is File &&
        (name.endsWith('.jsonl') ||
            name == 'strikes.json' ||
            name == 'strikes.json.tmp' ||
            name == 'queue-state.json' ||
            name == 'queue-state.json.tmp')) {
      await entity.delete();
    }
  }
  await dirty.delete();
}

/// תור מתמשך בקובצי JSONL (הוספה בלבד); כל מקטע = אצווה אחת עם context אחיד.
/// משותף לכל החלונות (תהליכים): מקטע נלקח לשליחה בשינוי שם, ומחיקה סובלנית.
class _DiskQueue {
  _DiskQueue(
    this._directory, {
    required DateTime Function() clock,
    this.maxEvents = 5000,
    this.maxBytes = 5 * 1024 * 1024,
    this.segmentEvents = SearchFeedbackLimits.eventsPerBatch,
    this.segmentBytes = SearchFeedbackLimits.batchBytes -
        SearchFeedbackLimits.batchEnvelopeReserve,
  }) : _clock = clock;

  static const String _prefix = 'seg-';
  static const String _extension = '.jsonl';
  static const String _claimedExtension = '.claimed.jsonl';
  static const String strikesFileName = 'strikes.json';

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final int maxEvents;
  final int maxBytes;
  final int segmentEvents;
  final int segmentBytes;

  final List<SearchFeedbackSegment> _segments = [];
  SearchFeedbackSegment? _open;
  String? _openContext;
  bool _loaded = false;
  int _sequence = 0;
  String _owner = '';
  Map<String, dynamic> _owners = {};

  Future<void> _persist(Directory dir) async {
    if (_open == null) {
      _owners.remove(_owner);
    } else {
      _owners[_owner] = {'name': _open!.name, 'context': _openContext};
    }
    final live = {for (final s in _segments) s.name};
    _owners.removeWhere((_, value) => !live.contains((value as Map)['name']));
    final temp = File(p.join(dir.path, 'queue-state.json.tmp'));
    await temp.writeAsString(
      jsonEncode({
        'segments': [
          for (final s in _segments)
            {'name': s.name, 'events': s.events, 'bytes': s.bytes},
        ],
        'owners': _owners,
        'sequence': _sequence,
      }),
      flush: true,
    );
    await temp.rename(p.join(dir.path, 'queue-state.json'));
    final dirty = File(p.join(dir.path, '.dirty'));
    if (await dirty.exists()) await dirty.delete();
  }

  Future<void> _tail = Future.value();
  final Map<String, SearchFeedbackStrikeRecord> _strikes = {};

  int get eventCount => _segments.fold(0, (sum, s) => sum + s.events);

  int get byteCount => _segments.fold(0, (sum, s) => sum + s.bytes);

  bool get isEmpty => eventCount == 0;

  /// מריץ את [action] אחרי כל הפעולות הקודמות; כשל אינו שובר את התור.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }

  Future<void> load() => _serialized(_ensureLoaded);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final dir = await _directory();
    _segments.clear();
    final metadata = File(p.join(dir.path, 'queue-state.json'));
    final dirty = File(p.join(dir.path, '.dirty'));
    if (!await dirty.exists() && await metadata.exists()) {
      try {
        final state = jsonDecode(await metadata.readAsString()) as Map;
        for (final row in state['segments'] as List) {
          if (!_isSegmentName(row['name'] as String)) continue;
          final stat =
              await File(p.join(dir.path, row['name'] as String)).stat();
          // ספירה שמורה תקפה רק כל עוד קובץ האירועים תואם לה.
          if (stat.type != FileSystemEntityType.file ||
              stat.size != row['bytes']) {
            throw const FormatException('stale queue metadata');
          }
          _segments.add(
            SearchFeedbackSegment(
              row['name'] as String,
              events: row['events'] as int,
              bytes: row['bytes'] as int,
            ),
          );
        }
        _owners = Map<String, dynamic>.from(state['owners'] as Map);
        _sequence = state['sequence'] as int? ?? 0;
        final own = _owners[_owner];
        if (own is Map) {
          _open = _segments.where((s) => s.name == own['name']).firstOrNull;
          _openContext = own['context'] as String?;
        }
        await _loadStrikes(dir);
        _loaded = true;
        return;
      } catch (_) {
        _segments.clear();
      }
    }
    if (await dir.exists()) {
      final files = <File>[
        await for (final entity in dir.list())
          if (entity is File && _isSegmentName(p.basename(entity.path))) entity,
      ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final file in files) {
        final String text;
        try {
          text = await file.readAsString();
        } on FileSystemException {
          continue; // נלקח או נמחק בתהליך אחר.
        }
        final lines = const LineSplitter().convert(text);
        final events = lines.length > 1 ? lines.length - 1 : 0;
        if (events == 0) {
          if (await _isStale(file)) {
            await _deleteFile(dir, p.basename(file.path));
          }
          continue;
        }
        _segments.add(
          SearchFeedbackSegment(
            p.basename(file.path),
            events: events,
            bytes: utf8.encode(text).length,
          ),
        );
      }
    }
    await _loadStrikes(dir);
    _loaded = true;
  }

  Future<void> _loadStrikes(Directory dir) async {
    _strikes.clear();
    final file = File(p.join(dir.path, strikesFileName));
    if (!await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final names = {for (final s in _segments) s.name};
      for (final entry in json.entries) {
        final record = SearchFeedbackStrikeRecord.fromJson(entry.value);
        if (record != null && names.contains(entry.key)) {
          _strikes[entry.key as String] = record;
        }
      }
    } on FormatException {
      // קובץ פגום — מתחילים את הספירה מחדש.
    }
  }

  Future<void> _saveStrikes(Directory dir) async {
    final file = File(p.join(dir.path, strikesFileName));
    if (_strikes.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await dir.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        for (final entry in _strikes.entries) entry.key: entry.value.toJson(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  /// סופר כשל נוסף מסוג [kind] למקטע; סוג אחר מתחיל ספירה חדשה.
  Future<SearchFeedbackStrikeRecord> addStrike(
    String name,
    String kind,
    DateTime now,
  ) =>
      _serialized(() async {
        await _ensureLoaded();
        final previous = _strikes[name];
        final record = previous != null && previous.kind == kind
            ? SearchFeedbackStrikeRecord(
                kind: kind,
                count: previous.count + 1,
                firstAt: previous.firstAt,
              )
            : SearchFeedbackStrikeRecord(kind: kind, count: 1, firstAt: now);
        _strikes[name] = record;
        await _saveStrikes(await _directory());
        return record;
      });

  /// מאפס את ספירת הכשלים של מקטע.
  Future<void> clearStrikes(String name) => _serialized(() async {
        await _ensureLoaded();
        if (_strikes.remove(name) == null) return;
        await _saveStrikes(await _directory());
      });

  static bool _isSegmentName(String name) =>
      name.startsWith(_prefix) &&
      name.endsWith(_extension) &&
      !name.contains(RegExp(r'[/\\:\x00]'));

  /// מוסיף אירוע. context שונה מהמקטע הפתוח פותח מקטע חדש.
  Future<void> append(
    Map<String, Object?> event,
    Map<String, Object?> context,
  ) =>
      _serialized(() async {
        await _ensureLoaded();
        final line = searchFeedbackJsonEncode(event);
        final lineBytes = line.length + 1;
        if (lineBytes > segmentBytes) return;
        final contextJson = searchFeedbackJsonEncode(context);
        final dir = await _directory();
        await dir.create(recursive: true);

        var open = _open;
        if (open != null && !await File(p.join(dir.path, open.name)).exists()) {
          // תהליך אחר לקח את המקטע לשליחה — ממשיכים במקטע חדש.
          _segments.remove(open);
          open = null;
        }
        if (open == null ||
            _openContext != contextJson ||
            open.events >= segmentEvents ||
            open.bytes + lineBytes > segmentBytes + contextJson.length + 1) {
          open = SearchFeedbackSegment(_newName(), events: 0, bytes: 0);
          _segments.add(open);
          _open = open;
          _openContext = contextJson;
          await File(p.join(dir.path, open.name))
              .writeAsString('$contextJson\n');
          open.bytes = contextJson.length + 1;
        }
        await File(
          p.join(dir.path, open.name),
        ).writeAsString('$line\n', mode: FileMode.append);
        open
          ..events += 1
          ..bytes += lineBytes;
        await _enforceCaps(dir);
      });

  /// מוחק מקטעים ותיקים עד שהתור חוזר לתקרות.
  Future<void> _enforceCaps(Directory dir) async {
    while (_segments.isNotEmpty &&
        (eventCount > maxEvents || byteCount > maxBytes)) {
      final oldest = _segments.removeAt(0);
      await _deleteFile(dir, oldest.name);
      if (_strikes.remove(oldest.name) != null) await _saveStrikes(dir);
    }
  }

  String _newName() {
    final micros = _clock().toUtc().microsecondsSinceEpoch;
    final seq = (_sequence++).toString().padLeft(20, '0');
    final id = newSearchFeedbackId();
    return '$_prefix${micros.toString().padLeft(17, '0')}-$seq-$_owner-$id$_extension';
  }

  /// מקטע ריק ישן; מקטע ריק טרי עשוי להיות פתוח לכתיבה בתהליך אחר.
  Future<bool> _isStale(File file) async {
    try {
      final modified = await file.lastModified();
      return _clock().difference(modified) > const Duration(hours: 1);
    } on FileSystemException {
      return false;
    }
  }

  /// סוגר את המקטע הפתוח וקורא שוב את התיקייה (כולל מקטעים של חלונות אחרים).
  Future<List<String>> sealAndList() => _serialized(() async {
        _open = null;
        _openContext = null;
        await _ensureLoaded();
        return [for (final segment in _segments) segment.name];
      });

  /// לוקח מקטע לשליחה בשינוי שם אטומי; `null` כשתהליך אחר כבר לקח אותו.
  Future<String?> claim(String name) => _serialized(() async {
        if (!_isSegmentName(name)) return null;
        if (name.endsWith(_claimedExtension)) return name;
        final dir = await _directory();
        final claimed = '${name.substring(0, name.length - _extension.length)}'
            '$_claimedExtension';
        try {
          await File(p.join(dir.path, name)).rename(p.join(dir.path, claimed));
        } on FileSystemException {
          _segments.removeWhere((s) => s.name == name);
          return null;
        }
        for (final segment in _segments) {
          if (segment.name == name) segment.name = claimed;
        }
        if (_open?.name == name) _open = null;
        final strike = _strikes.remove(name);
        if (strike != null) {
          _strikes[claimed] = strike;
          await _saveStrikes(dir);
        }
        return claimed;
      });

  /// קורא מקטע לשליחה. שורות פגומות ואירועים מלפני [notBefore] מושמטים;
  /// null = המקטע כבר אינו קיים.
  Future<SearchFeedbackStoredBatch?> read(String name, {DateTime? notBefore}) =>
      _serialized(() async {
        if (!_isSegmentName(name)) return null;
        final dir = await _directory();
        final file = File(p.join(dir.path, name));
        if (!await file.exists()) return null;
        final List<String> lines;
        try {
          lines = const LineSplitter().convert(await file.readAsString());
        } on FileSystemException {
          return null;
        }
        if (lines.isEmpty) return null;
        // שורה ראשונה שאינה ClientContext (כתיבה מתחרה) — האצווה נזרקת.
        if (!_isContextLine(lines.first)) {
          return SearchFeedbackStoredBatch(
            segmentName: name,
            contextJson: '{}',
            eventLines: const [],
          );
        }
        final contextJson = lines.first;
        return SearchFeedbackStoredBatch(
          segmentName: name,
          contextJson: contextJson,
          eventLines: [
            for (final line in lines.skip(1))
              if (_isFreshEvent(line, notBefore)) line,
          ],
        );
      });

  static bool _isContextLine(String line) {
    try {
      final json = jsonDecode(line);
      return json is Map && json['app'] == 'otzaria';
    } on FormatException {
      return false;
    }
  }

  static bool _isFreshEvent(String line, DateTime? notBefore) {
    try {
      final json = jsonDecode(line);
      if (json is! Map) return false;
      if (notBefore == null) return true;
      final time = DateTime.tryParse('${json['clientTime']}');
      return time != null && !time.isBefore(notBefore);
    } on FormatException {
      return false;
    }
  }

  /// מסיר מקטע שנשלח (או שהוחלט לוותר עליו).
  Future<void> remove(String name) => _serialized(() async {
        if (!_isSegmentName(name)) return;
        final dir = await _directory();
        _segments.removeWhere((s) => s.name == name);
        if (_open?.name == name) _open = null;
        await _deleteFile(dir, name);
        if (_strikes.remove(name) != null) await _saveStrikes(dir);
      });

  /// מפצל מקטע לשניים במקומו בסדר התור; מקטע של אירוע אחד מוסר.
  Future<void> split(String name) => _serialized(() async {
        if (!_isSegmentName(name)) return;
        final dir = await _directory();
        final file = File(p.join(dir.path, name));
        final index = _segments.indexWhere((s) => s.name == name);
        if (index < 0 || !await file.exists()) return;
        final lines = const LineSplitter().convert(await file.readAsString());
        final events = lines.skip(1).toList();
        _segments.removeAt(index);
        if (_open?.name == name) _open = null;
        if (_strikes.remove(name) != null) await _saveStrikes(dir);
        if (events.length < 2) {
          await file.delete();
          return;
        }
        final half = events.length ~/ 2;
        final base = name.substring(0, name.length - _extension.length);
        final parts = [events.sublist(0, half), events.sublist(half)];
        for (var i = 0; i < parts.length; i++) {
          final partName = '$base${i == 0 ? 'a' : 'b'}$_extension';
          final text = '${[lines.first, ...parts[i]].join('\n')}\n';
          await File(p.join(dir.path, partName)).writeAsString(text);
          _segments.insert(
            index + i,
            SearchFeedbackSegment(
              partName,
              events: parts[i].length,
              bytes: utf8.encode(text).length,
            ),
          );
        }
        await file.delete();
      });

  /// מוחק את כל התור מהדיסק.
  Future<void> purge() => _serialized(() async {
        final dir = await _directory();
        _segments.clear();
        _strikes.clear();
        _open = null;
        _openContext = null;
        _loaded = true;
        if (!await dir.exists()) return;
        await _saveStrikes(dir);
        await for (final entity in dir.list()) {
          if (entity is File && _isSegmentName(p.basename(entity.path))) {
            await _deleteFile(dir, p.basename(entity.path));
          }
        }
      });

  static Future<void> _deleteFile(Directory dir, String name) async {
    try {
      await File(p.join(dir.path, name)).delete();
    } on FileSystemException {
      // כבר נמחק או נלקח בתהליך אחר.
    }
  }
}
