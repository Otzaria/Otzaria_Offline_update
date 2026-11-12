import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:test/test.dart';

/// קובץ אמיתי שכל כתיבה אליו נרשמת, ואפשר לעכב או להכשיל אותה.
class _SpyFile implements File {
  _SpyFile(this._real, this.log);

  final File _real;
  final _WriteLog log;

  @override
  String get path => _real.path;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _SpyHandle(await _real.open(mode: mode), log);

  @override
  Future<bool> exists() => _real.exists();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WriteLog {
  final writes = <(String name, int bytes)>[];
  Completer<void>? gate;
  Object? failure;
  int inFlight = 0;
  int peakInFlight = 0;
}

class _SpyHandle implements RandomAccessFile {
  _SpyHandle(this._real, this.log);

  final RandomAccessFile _real;
  final _WriteLog log;

  @override
  String get path => _real.path;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    if (++log.inFlight > log.peakInFlight) log.peakInFlight = log.inFlight;
    try {
      await log.gate?.future;
      final failure = log.failure;
      if (failure != null) throw failure;
      await _real.writeFrom(buffer, start, end);
      log.writes.add((
        path.split(RegExp(r'[\\/]')).last,
        (end ?? buffer.length) - start,
      ));
    } finally {
      log.inFlight--;
    }
    return this;
  }

  @override
  Future<void> close() => _real.close();
  @override
  Future<RandomAccessFile> flush() => _real.flush();
  @override
  Future<int> length() => _real.length();
  @override
  Future<RandomAccessFile> truncate(int length) => _real.truncate(length);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const mib = 1024 * 1024;
  late Directory dir;
  late _WriteLog log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('write_behind_');
    log = _WriteLog();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<RandomAccessFile> open(WriteBehindPool pool, String name) => pool
      .wrap(_SpyFile(File('${dir.path}/$name'), log))
      .open(mode: FileMode.write);

  Uint8List bytes(int length, int fill) =>
      Uint8List(length)..fillRange(0, length, fill);

  test('הכתיבה חוזרת מיד, והסגירה מחכה שהכול ירד לכונן בסדר הנכון', () async {
    final pool = WriteBehindPool();
    log.gate = Completer<void>();
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(3000, 1));
    await handle.writeFrom(bytes(5000, 2), 1000, 4000);
    expect(log.writes, isEmpty);
    expect(pool.pendingBytes, 6000);

    log.gate!.complete();
    await handle.close();
    expect(pool.pendingBytes, 0);
    final content = File('${dir.path}/a.bin').readAsBytesSync();
    expect(content.length, 6000);
    expect(content[2999], 1);
    expect(content[3000], 2);
    expect(log.writes, [('a.bin', 6000)], reason: 'חתיכות קטנות מאוחדות');
  });

  test('החוצץ של הקורא מועתק ולא נשמר', () async {
    final pool = WriteBehindPool();
    log.gate = Completer<void>();
    final handle = await open(pool, 'a.bin');
    final buffer = bytes(100, 7);
    await handle.writeFrom(buffer);
    buffer.fillRange(0, 100, 9);
    log.gate!.complete();
    await handle.close();
    expect(File('${dir.path}/a.bin').readAsBytesSync(), everyElement(7));
  });

  test('כותב אחד בכל רגע, ברצפים של קובץ שלם ולא לסירוגין', () async {
    final pool = WriteBehindPool(minBurstBytes: 2 * mib);
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    log.gate = Completer<void>();
    // לסירוגין, כמו שתי הורדות שרצות יחד.
    for (var i = 0; i < 6; i++) {
      await a.writeFrom(bytes(mib ~/ 2, 1));
      await b.writeFrom(bytes(mib ~/ 2, 2));
    }
    log.gate!.complete();
    await Future.wait([a.close(), b.close()]);

    expect(log.peakInFlight, 1);
    final order = [for (final w in log.writes) w.$1];
    final switches = [
      for (var i = 1; i < order.length; i++)
        if (order[i] != order[i - 1]) i,
    ].length;
    expect(switches, 1, reason: '$order');
    expect(File('${dir.path}/a.bin').lengthSync(), 3 * mib);
    expect(File('${dir.path}/b.bin').lengthSync(), 3 * mib);
  });

  test('תור מלא מעכב את הכותב עד שהכונן מתפנה', () async {
    final pool = WriteBehindPool(maxPendingBytes: mib);
    log.gate = Completer<void>();
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(mib, 1));
    var returned = false;
    final blocked =
        handle.writeFrom(bytes(mib, 2)).then((_) => returned = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(returned, isFalse);
    log.gate!.complete();
    await blocked;
    await handle.close();
    expect(File('${dir.path}/a.bin').lengthSync(), 2 * mib);
  });

  test('מעט בייטים נכתבים אחרי maxDelay גם בלי רצף מלא', () async {
    final pool = WriteBehindPool(
      maxDelay: const Duration(milliseconds: 150),
    );
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(10, 1));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(log.writes, [('a.bin', 10)]);
    await handle.close();
  });

  test('כשל כתיבה מגיע לכתיבה הבאה ולסגירה, והקובץ נסגר', () async {
    final pool = WriteBehindPool();
    log.failure = const FileSystemException('disk gone');
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(10, 1));
    await expectLater(handle.flush(), throwsA(isA<FileSystemException>()));
    await expectLater(
      handle.writeFrom(bytes(10, 1)),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(handle.close(), throwsA(isA<FileSystemException>()));
    expect(pool.pendingBytes, 0);
    File('${dir.path}/a.bin').deleteSync();
  });

  test('length ו-truncate רואים את מה שנכתב', () async {
    final pool = WriteBehindPool();
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(5000, 1));
    expect(await handle.length(), 5000);
    await handle.truncate(1000);
    await handle.close();
    expect(File('${dir.path}/a.bin').lengthSync(), 1000);
  });

  List<String> runs() {
    final order = [for (final w in log.writes) w.$1];
    return [
      for (var i = 0; i < order.length; i++)
        if (i == 0 || order[i] != order[i - 1]) order[i],
    ];
  }

  test('נצמד לקובץ אחד; קובץ שהסתיים נכנס רק כשהנוכחי מחכה לרשת', () async {
    final pool = WriteBehindPool(minBurstBytes: mib);
    final active = await open(pool, 'active.bin');
    final done = await open(pool, 'done.bin');
    log.gate = Completer<void>();
    await active.writeFrom(bytes(4 * mib, 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await done.writeFrom(bytes(3 * mib, 2));
    final closing = done.close();
    await active.writeFrom(bytes(2 * mib, 1));
    log.gate!.complete();
    await closing;
    expect(runs(), ['active.bin', 'done.bin'], reason: 'בלי מעבר באמצע');
    expect(File('${dir.path}/done.bin').lengthSync(), 3 * mib);

    await active.writeFrom(bytes(mib, 1));
    await active.close();
    expect(runs(), ['active.bin', 'done.bin', 'active.bin']);
    expect(File('${dir.path}/active.bin').lengthSync(), 7 * mib);
  });

  test('כשהנוכחי מחכה לרשת, קובץ אחר שעוד יורד אינו נכנס במקומו', () async {
    final pool = WriteBehindPool(minBurstBytes: mib);
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    await a.writeFrom(bytes(2 * mib, 1));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await b.writeFrom(bytes(3 * mib, 2));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(runs(), ['a.bin']);

    await a.writeFrom(bytes(mib + 10, 1));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(runs(), ['a.bin']);
    expect(log.writes.last.$2, mib, reason: 'שארית קטנה מגוש מחכה לסגירה');
    await a.close();
    await b.close();
    expect(runs(), ['a.bin', 'b.bin']);
    expect(File('${dir.path}/a.bin').lengthSync(), 3 * mib + 10);
  });

  test('קובץ נוכחי שנתקע מפנה את הכותב אחרי starvedPatience', () async {
    final pool = WriteBehindPool(
      minBurstBytes: mib,
      starvedPatience: const Duration(milliseconds: 200),
    );
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    await a.writeFrom(bytes(2 * mib, 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await b.writeFrom(bytes(3 * mib, 2));
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(runs(), ['a.bin', 'b.bin']);
    await a.close();
    await b.close();
  });

  test('הקובץ הזמני נוצר בתיקיית הביניים ונמחק עם הסגירה האחרונה', () async {
    final spill = Directory('${dir.path}/spill')..createSync();
    final pool = WriteBehindPool(spillRoot: spill);
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    await a.writeFrom(bytes(1000, 1));
    final own = spill.listSync().whereType<Directory>().single;
    expect(own.path, contains(WriteBehindPool.spillPrefix));
    List<String> spills() => [
          for (final entry in own.listSync())
            if (entry.path.endsWith('.spill')) entry.path,
        ];
    expect(spills(), hasLength(2));
    await a.close();
    expect(spills(), hasLength(1));
    await b.close();
    expect(spill.listSync(), isEmpty);
  });

  test('בלי תיקיית ביניים הכתיבה ישירה, ואינה נכשלת', () async {
    final blocked = File('${dir.path}/not-a-dir')..writeAsStringSync('x');
    final pool = WriteBehindPool(spillRoot: Directory(blocked.path));
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(5000, 3));
    expect(log.writes, [('a.bin', 5000)]);
    expect(pool.pendingBytes, 0);
    await handle.close();
    expect(File('${dir.path}/a.bin').lengthSync(), 5000);
  });

  /// תוכן שכל בייט בו תלוי במקומו, כדי שסדר שגוי או כפילות ייראו.
  Uint8List pattern(int offset, int length) => Uint8List.fromList([
        for (var i = 0; i < length; i++)
          ((offset + i) * 31 + (offset + i) ~/ 251) & 0xff,
      ]);

  test('שלושה קבצים לסירוגין, אחד מהם בהמשך לקובץ קיים: התוכן זהה בייט לבייט',
      () async {
    final pool = WriteBehindPool(minBurstBytes: 256 * 1024);
    File('${dir.path}/c.bin').writeAsBytesSync(pattern(0, 70000));
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    final c = await pool
        .wrap(_SpyFile(File('${dir.path}/c.bin'), log))
        .open(mode: FileMode.append);
    final sizes = {a: 0, b: 0, c: 70000};
    for (var round = 0; round < 60; round++) {
      for (final (handle, step) in [(a, 54321), (b, 7777), (c, 131072)]) {
        await handle.writeFrom(pattern(sizes[handle]!, step));
        sizes[handle] = sizes[handle]! + step;
      }
      if (round % 7 == 0) await Future<void>.delayed(Duration.zero);
    }
    await Future.wait([a.close(), b.close(), c.close()]);
    for (final (name, handle) in [('a', a), ('b', b), ('c', c)]) {
      expect(
        File('${dir.path}/$name.bin').readAsBytesSync(),
        pattern(0, sizes[handle]!),
        reason: name,
      );
    }
    expect(log.peakInFlight, 1);
  });

  test('הקובץ הזמני מתרוקן כשהכול כבר ביעד, ואינו גדל לגודל הקובץ', () async {
    final pool = WriteBehindPool(minBurstBytes: mib);
    final handle = await open(pool, 'a.bin');
    for (var i = 0; i < 4; i++) {
      await handle.writeFrom(bytes(10 * mib, i));
      await handle.flush();
      await handle.writeFrom(bytes(10, i));
      expect(pool.spillBytes, lessThan(mib), reason: 'סבב $i');
    }
    await handle.close();
    expect(pool.spillBytes, 0);
    expect(File('${dir.path}/a.bin').lengthSync(), 4 * (10 * mib + 10));
  });

  test('תקרת המקום הזמני קטנה: הכתיבה מתעכבת ואינה נתקעת', () async {
    final pool = WriteBehindPool(maxPendingBytes: 2 * mib, minBurstBytes: mib);
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    for (var i = 0; i < 12; i++) {
      await a.writeFrom(pattern(i * mib, mib));
      await b.writeFrom(pattern(i * 300000, 300000));
      expect(pool.spillBytes, lessThanOrEqualTo(4 * mib));
    }
    await Future.wait([a.close(), b.close()]);
    expect(File('${dir.path}/a.bin').readAsBytesSync(), pattern(0, 12 * mib));
    expect(
      File('${dir.path}/b.bin').readAsBytesSync(),
      pattern(0, 12 * 300000),
    );
  });

  test('abandonPending: מה שלא נכתב נזרק, הקובץ נשאר תחילית, והסגירה נכשלת',
      () async {
    final pool = WriteBehindPool(minBurstBytes: mib);
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(pattern(0, 2 * mib));
    await handle.flush();
    log.gate = Completer<void>();
    await handle.writeFrom(pattern(2 * mib, 3 * mib));
    pool.abandonPending();
    expect(pool.pendingBytes, 0);
    await handle.writeFrom(pattern(5 * mib, mib));
    log.gate!.complete();
    await expectLater(handle.close(), throwsA(isA<FileSystemException>()));
    final onDisk = File('${dir.path}/a.bin').readAsBytesSync();
    expect(onDisk.length, inInclusiveRange(2 * mib, 3 * mib));
    expect(onDisk, pattern(0, onDisk.length));

    final next = await open(pool, 'b.bin');
    await next.writeFrom(bytes(10, 1));
    await next.close();
    expect(File('${dir.path}/b.bin').lengthSync(), 10);
  });

  test('קובץ שכתיבה אליו נכשלה והוא נשאר: הפתיחה הבאה נכשלת פעם אחת', () async {
    final pool = WriteBehindPool();
    log.failure = const FileSystemException('disk gone');
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(10, 1));
    await expectLater(handle.close(), throwsA(isA<FileSystemException>()));
    log.failure = null;
    Future<RandomAccessFile> resume(String name) => pool
        .wrap(_SpyFile(File('${dir.path}/$name'), log))
        .open(mode: FileMode.append);
    await expectLater(resume('a.bin'), throwsA(isA<FileSystemException>()));
    final again = await resume('a.bin');
    await again.close();

    log.failure = const FileSystemException('disk gone');
    final truncated = await open(pool, 'c.bin');
    await truncated.writeFrom(bytes(10, 1));
    await expectLater(truncated.close(), throwsA(isA<FileSystemException>()));
    log.failure = null;
    final rewritten = await open(pool, 'c.bin');
    await rewritten.close();

    log.failure = const FileSystemException('disk gone');
    final other = await open(pool, 'b.bin');
    await other.writeFrom(bytes(10, 1));
    await expectLater(other.close(), throwsA(isA<FileSystemException>()));
    log.failure = null;
    pool.wrap(File('${dir.path}/b.bin')).deleteSync();
    final fresh = await open(pool, 'b.bin');
    await fresh.close();

    log.failure = const FileSystemException('disk gone');
    final gone = await open(pool, 'x.bin');
    await gone.writeFrom(bytes(10, 1));
    await expectLater(gone.close(), throwsA(isA<FileSystemException>()));
    log.failure = null;
    File('${dir.path}/x.bin').deleteSync();
    final recreated = await resume('x.bin');
    await recreated.close();
  });

  test('ביטול בזמן סגירה: קובץ שנשאר לו מעט מסיים שלם, ואחר נזרק', () async {
    final pool = WriteBehindPool(minBurstBytes: mib, yieldBytes: 4 * mib);
    log.gate = Completer<void>();
    final small = await open(pool, 'a.bin');
    final big = await open(pool, 'b.bin');
    await small.writeFrom(pattern(0, 2 * mib));
    await big.writeFrom(pattern(0, 6 * mib));
    final smallClosed = small.close();
    final bigClosed = expectLater(
      big.close(),
      throwsA(isA<FileSystemException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    pool.abandonPending();
    log.gate!.complete();
    await smallClosed;
    await bigClosed;
    expect(File('${dir.path}/a.bin').readAsBytesSync(), pattern(0, 2 * mib));
    expect(File('${dir.path}/b.bin').lengthSync(), lessThan(6 * mib));
    expect(pool.spillBytes, 0);
  });

  test('ביטול כשהתקרה מלאה משחרר כותבים שמחכים למקום', () async {
    final pool = WriteBehindPool(maxPendingBytes: mib, minBurstBytes: mib);
    log.gate = Completer<void>();
    final a = await open(pool, 'a.bin');
    final b = await open(pool, 'b.bin');
    await a.writeFrom(bytes(100, 1));
    final flushed = a.flush().then((_) {}, onError: (_) {});
    final parked = b.writeFrom(bytes(3 * mib, 2));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    pool.abandonPending();
    log.gate!.complete();
    await parked.timeout(const Duration(seconds: 5));
    await flushed;
    await expectLater(a.close(), throwsA(isA<FileSystemException>()));
    await expectLater(b.close(), throwsA(isA<FileSystemException>()));
    expect(pool.spillBytes, 0);
  });

  test('סגירה כפולה אינה מחסירה פעמיים מחשבון המקום הזמני', () async {
    final pool = WriteBehindPool();
    final keep = await open(pool, 'keep.bin');
    final handle = await open(pool, 'a.bin');
    await handle.writeFrom(bytes(mib, 1));
    await handle.close();
    try {
      await handle.close();
    } catch (_) {}
    expect(pool.spillBytes, 0);
    await keep.close();
  });

  test('קובץ שהסתיים נכנס אחרי yieldBytes גם כשלנוכחי עוד יש מה לכתוב',
      () async {
    final pool = WriteBehindPool(minBurstBytes: mib, yieldBytes: 2 * mib);
    final big = await open(pool, 'big.bin');
    final small = await open(pool, 'small.bin');
    log.gate = Completer<void>();
    await big.writeFrom(bytes(8 * mib, 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await small.writeFrom(bytes(mib, 2));
    final closing = small.close();
    log.gate!.complete();
    await closing;
    expect(runs().take(2), ['big.bin', 'small.bin']);
    expect(
      log.writes.where((w) => w.$1 == 'big.bin').length,
      lessThan(8),
      reason: 'הקטן לא חיכה לכל הגדול',
    );
    await big.close();
    expect(File('${dir.path}/big.bin').lengthSync(), 8 * mib);
  });

  test('sweepStaleSpill: תיקייה של תור חי נשארת, ושל תהליך שמת נמחקת מיד',
      () async {
    final root = Directory('${dir.path}/tmp')..createSync();
    final pool = WriteBehindPool(spillRoot: root);
    final handle = await open(pool, 'a.bin');
    final live = root.listSync().whereType<Directory>().single;
    final dead = Directory('${root.path}/${WriteBehindPool.spillPrefix}dead')
      ..createSync();
    File('${dead.path}/.lock').writeAsStringSync('');
    File('${dead.path}/0.spill').writeAsStringSync('x');

    WriteBehindPool.sweepStaleSpill(root: root);
    expect(live.existsSync(), isTrue);
    expect(dead.existsSync(), isFalse);
    await handle.close();
    expect(root.listSync(), isEmpty);
  });

  test('sweepStaleSpill מוחק רק תיקיות ביניים ישנות מיממה', () {
    final root = Directory('${dir.path}/tmp')..createSync();
    final stale = Directory('${root.path}/${WriteBehindPool.spillPrefix}old')
      ..createSync();
    File('${stale.path}/0.spill').writeAsStringSync('x');
    final other = Directory('${root.path}/unrelated')..createSync();

    WriteBehindPool.sweepStaleSpill(root: root);
    expect(stale.existsSync(), isTrue, reason: 'חדשה: אולי של תהליך חי');

    WriteBehindPool.sweepStaleSpill(
      root: root,
      now: DateTime.now().add(const Duration(days: 2)),
    );
    expect(stale.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
  });

  test('runZoned עוטף רק נתיבים שאושרו, וקריאה אינה עוברת בתור', () async {
    final pool = WriteBehindPool();
    final inside = '${dir.path}/in.bin', outside = '${dir.path}/out.bin';
    await pool.runZoned(() async {
      final wrapped = await File(inside).open(mode: FileMode.write);
      final plain = await File(outside).open(mode: FileMode.write);
      await wrapped.writeFrom(bytes(10, 1));
      await plain.writeFrom(bytes(10, 1));
      expect(File(outside).lengthSync(), 10);
      expect(pool.pendingBytes, 10);
      await wrapped.close();
      await plain.close();
      final reader = await File(inside).open();
      expect(await reader.length(), 10);
      await reader.close();
    }, shouldWrap: (path) => path == inside);
    expect(pool.pendingBytes, 0);
  });
}
