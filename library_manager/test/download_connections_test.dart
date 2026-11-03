import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/download_connections.dart';
import 'package:library_manager/src/services/semantic_search_assets.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

const _mib = 1024 * 1024;

/// מצב פיצול תקין כפי שהמנוע כותב אותו, לנכס שגודלו 200 בייטים.
void writeLiveState(String statePath, {String token = 't'}) {
  File(statePath).parent.createSync(recursive: true);
  File(statePath).writeAsStringSync(
    jsonEncode({
      'v': 1,
      'token': token,
      'url': 'u',
      'size': 200,
      'sha256': null,
      'etag': 'e',
      'bounds': [0, 100, 200],
      'assembled': 1,
    }),
  );
}

void main() {
  // הנלווים חולקים את משבצות הייצוא, ולכן גם את חלוקת החיבורים שלו.
  test('החלוקה זהה לזו של הייצוא בכל גודל של תור', () {
    for (final slots in [1, 2, 3, 4, 8, 16]) {
      final scheduler = DownloadScheduler(maxConcurrent: slots);
      final exporter = LibraryMirrorExporter(
        supportedDbSchemaVersion: kSupportedDbSchemaVersion,
        scheduler: scheduler,
      );
      addTearDown(exporter.dispose);

      expect(
        connectionsPerFile(scheduler),
        exporter.connectionsPerFile,
        reason: '$slots משבצות',
      );
    }
  });

  removableChoice();
  splitState();
  orphanState();
  writeSpeed();
  cancellableProbe();
  drivePaths();

  test('הנלווים והחיפוש החכם מורידים בחלוקה הזו', () {
    final scheduler = DownloadScheduler(maxConcurrent: 4);
    final companions = CompanionAssetsMirror(scheduler: scheduler);
    addTearDown(companions.dispose);
    final semantic = SemanticSearchAssets(scheduler: scheduler);
    addTearDown(semantic.dispose);
    final downloader = semantic.newDownloader();
    addTearDown(downloader.dispose);

    expect(connectionsPerFile(scheduler), 2);
    expect(companions.maxConnectionsPerFile, 2);
    expect(downloader.maxConnections, 2);
  });
}

void removableChoice() {
  final scheduler = DownloadScheduler(maxConcurrent: 4);

  test('יעד איטי מקבל חיבור יחיד, קבוע לא משתנה', () {
    int pick(bool slow, bool split) =>
        connectionsForTarget(scheduler, slowTarget: slow, resumingSplit: split);
    expect(pick(true, false), 1);
    expect(pick(false, false), 2);
    expect(pick(true, true), 2, reason: 'מצב פיצול שמור ממשיך');
    expect(pick(false, true), 2);
  });

  Future<int> choose({
    bool removable = true,
    bool split = false,
    required Future<double?> Function(String) probe,
  }) => connectionsForDir(
    scheduler,
    'E:/m',
    removableProbe: (_) => removable,
    splitProbe: (_) => split,
    writeProbe: probe,
  );

  test('כונן נשלף מהיר: חלוקה רגילה, גם אם הוא מדווח נשלף', () async {
    expect(await choose(probe: (_) async => 40.0 * _mib), 2);
    expect(
      await choose(probe: (_) async => slowWriteBytesPerSecond.toDouble()),
      2,
      reason: 'בדיוק על הסף נחשב מהיר',
    );
  });

  test('כונן נשלף איטי: חיבור יחיד', () async {
    expect(await choose(probe: (_) async => 3.0 * _mib), 1);
  });

  test('מדידה שנכשלה: חיבור יחיד (כמו שהיה בכונן נשלף)', () async {
    expect(await choose(probe: (_) async => null), 1);
  });

  test('מצב פיצול שמור ממשיך בחלוקה ולא מודד', () async {
    var probed = 0;
    expect(
      await choose(
        split: true,
        probe: (_) async {
          probed++;
          return 1.0 * _mib;
        },
      ),
      2,
    );
    expect(probed, 0);
  });

  test('כונן קבוע לא נמדד כלל', () async {
    var probed = 0;
    expect(
      await choose(
        removable: false,
        probe: (_) async {
          probed++;
          return 1.0 * _mib;
        },
      ),
      2,
    );
    expect(probed, 0);
  });

  test(
    'הנלווים: איטי=1, מהיר=2, נכשל=1, ונכס עם .segments נשאר מפוצל',
    () async {
      final dir = Directory.systemTemp.createTempSync('conn_');
      addTearDown(() => dir.deleteSync(recursive: true));
      CompanionAssetsMirror mirrorWith(double? speed) {
        final mirror = CompanionAssetsMirror(
          scheduler: scheduler,
          removableProbe: (_) => true,
          writeProbe: (_) async => speed,
        );
        addTearDown(mirror.dispose);
        return mirror;
      }

      final fresh = '${dir.path}/a.bin';
      final split = '${dir.path}/b.bin';
      final newSplit = '${dir.path}/c.bin';
      writeLiveState('$split.segments');
      writeLiveState('$newSplit.new.segments');
      final slow = mirrorWith(3.0 * _mib);
      expect(await slow.maxConnectionsFor(fresh), 1);
      expect(await slow.maxConnectionsFor(split, token: 't'), 2);
      expect(await slow.maxConnectionsFor('$newSplit.new', token: 't'), 2);
      expect(await mirrorWith(40.0 * _mib).maxConnectionsFor(fresh), 2);
      expect(await mirrorWith(null).maxConnectionsFor(fresh), 1);
    },
  );
}

void splitState() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('split_'));
  tearDown(() {
    if (Platform.isWindows) {
      Process.runSync('icacls', [root.path, '/T', '/grant', '*S-1-1-0:(F)']);
    }
    root.deleteSync(recursive: true);
  });

  void touch(String relative) {
    final file = File(p.join(root.path, relative));
    if (relative.endsWith('.segments')) return writeLiveState(file.path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{}');
  }

  test('אין מצב שמור בתיקייה ריקה או שאינה קיימת', () {
    expect(hasSplitState(root.path), isFalse);
    expect(hasSplitState(p.join(root.path, 'missing')), isFalse);
    touch('a.bin');
    touch('sub/b.bin.seg-0');
    expect(hasSplitState(root.path), isFalse);
  });

  test('מזהה .segments ו-.new.segments, גם בתת-תיקייה', () {
    touch('a.bin.segments');
    expect(hasSplitState(root.path), isTrue);
    File(p.join(root.path, 'a.bin.segments')).deleteSync();
    touch('g/vectors/v.oxv.new.segments');
    expect(hasSplitState(root.path), isTrue);
    expect(hasSplitState(root.path, maxDepth: 1), isFalse);
  });

  test('תיקייה שאי אפשר לקרוא אותה נחשבת כמצב שמור, לא כאין מצב', () {
    touch('sub/a.bin');
    final result = hasSplitState(
      root.path,
      list: (dir) {
        if (p.basename(dir) == 'sub') {
          throw const FileSystemException('denied', 'sub');
        }
        return Directory(dir).listSync();
      },
    );
    expect(result, isTrue);
  });

  test('שורש שאי אפשר לקרוא אותו נחשב כמצב שמור', () {
    expect(
      hasSplitState(root.path, list: (_) => throw const OSError('x', 5)),
      isTrue,
    );
  });

  test('ערך בלתי קריא אמיתי (icacls) לא מאבד מצב פיצול שמור', () {
    touch('a.bin.segments');
    touch('locked/inner.bin');
    final locked = p.join(root.path, 'locked');
    final denied = Process.runSync('icacls', [
      locked,
      '/deny',
      '*S-1-1-0:(RD)',
    ]);
    expect(denied.exitCode, 0, reason: '${denied.stdout}${denied.stderr}');
    expect(hasSplitState(root.path), isTrue);
    File(p.join(root.path, 'a.bin.segments')).deleteSync();
    expect(
      hasSplitState(root.path),
      isTrue,
      reason: 'תיקייה נעולה בלי מצב גלוי: שמרני',
    );
  }, skip: Platform.isWindows ? false : 'icacls');
}

void writeSpeed() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('speed_');
    resetWriteSpeedCache();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('המדידה כותבת קובץ זמני ומוחקת אותו', () async {
    final speed = await measureWriteSpeed(root.path, totalBytes: 2 * _mib);
    expect(speed, isNotNull);
    expect(speed, greaterThan(0));
    expect(root.listSync(), isEmpty);
  });

  test('מדידה בתיקייה שאי אפשר לכתוב בה מחזירה null', () async {
    final file = File(p.join(root.path, 'f'))..writeAsStringSync('x');
    expect(await measureWriteSpeed(p.join(file.path, 'sub')), isNull);
  });

  test('תוצאה נשמרת לכל כונן, פגה אחרי זמן, וכשל לא נשמר', () async {
    var calls = 0;
    double? next = 5.0 * _mib;
    Future<double?> measure(String _) async {
      calls++;
      return next;
    }

    var now = DateTime(2026);
    DateTime clock() => now;
    expect(
      await driveWriteSpeed(root.path, measure: measure, clock: clock),
      5.0 * _mib,
    );
    await driveWriteSpeed(
      p.join(root.path, 'other'),
      measure: measure,
      clock: clock,
    );
    expect(calls, 1, reason: 'אותו כונן');

    now = now.add(const Duration(minutes: 11));
    next = null;
    expect(
      await driveWriteSpeed(root.path, measure: measure, clock: clock),
      isNull,
    );
    expect(calls, 2);
    next = 7.0 * _mib;
    expect(
      await driveWriteSpeed(root.path, measure: measure, clock: clock),
      7.0 * _mib,
    );
    expect(calls, 3, reason: 'כשל לא נשמר');
  });

  test('שעון שזז אחורה אינו משתמש במטמון', () async {
    var calls = 0;
    Future<double?> measure(String _) async {
      calls++;
      return 5.0 * _mib;
    }

    var now = DateTime(2026);
    DateTime clock() => now;
    await driveWriteSpeed(root.path, measure: measure, clock: clock);
    now = now.subtract(const Duration(hours: 1));
    await driveWriteSpeed(root.path, measure: measure, clock: clock);
    expect(calls, 2);
  });

  test('מדידה תקועה נקטעת, חוזרת null ואינה נשמרת', () async {
    var calls = 0;
    final stuck = Completer<double?>();
    Future<double?> measure(String _) {
      calls++;
      return stuck.future;
    }

    expect(
      await driveWriteSpeed(
        root.path,
        measure: measure,
        timeout: const Duration(milliseconds: 50),
      ),
      isNull,
    );
    expect(
      await driveWriteSpeed(
        root.path,
        measure: measure,
        timeout: const Duration(milliseconds: 50),
      ),
      isNull,
    );
    expect(calls, 2);
  });

  test('חריגה מהזמן הכולל מחזירה null ומשאירה את התיקייה נקייה', () async {
    final speed = await measureWriteSpeed(root.path, timeout: Duration.zero);
    expect(speed, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(root.listSync(), isEmpty);
  });

  test('גשושית יתומה של תהליך אחר נמחקת, ושאר הקבצים נשארים', () async {
    final old = DateTime.now().subtract(const Duration(hours: 1));
    final orphan = File(p.join(root.path, '.write_probe_1_2'))
      ..writeAsStringSync('x')
      ..setLastModifiedSync(old);
    final fresh = File(p.join(root.path, '.write_probe_3_4'))
      ..writeAsStringSync('x');
    final own = File(p.join(root.path, '.write_probe_${pid}_5'))
      ..writeAsStringSync('x')
      ..setLastModifiedSync(old);
    final other = File(p.join(root.path, 'book.db'))
      ..writeAsStringSync('x')
      ..setLastModifiedSync(old);
    final lookalike = File(p.join(root.path, '.write_probe_x'))
      ..writeAsStringSync('x')
      ..setLastModifiedSync(old);

    await measureWriteSpeed(root.path, totalBytes: _mib);

    expect(orphan.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(own.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
    expect(lookalike.existsSync(), isTrue);
  });

  test('חריגה מהמדידה היא כשל ולא נזרקת', () async {
    expect(
      await driveWriteSpeed(
        root.path,
        measure: (_) => throw const FileSystemException('boom'),
      ),
      isNull,
    );
  });
}

void drivePaths() {
  test('שורש הכונן לפי צורת הנתיב', () {
    final win = p.windows;
    expect(driveRootFor('E:/m/x', context: win), r'E:\');
    expect(driveRootFor(r'E:\m', context: win), r'E:\');
    expect(driveRootFor(r'e:\', context: win), r'e:\');
    expect(driveRootFor(r'\\srv\share\dir\f', context: win), r'\\srv\share\');
  });

  test('isRemovableDrive: תיקיית הזמניים אינה נשלפת', () {
    expect(isRemovableDrive(Directory.systemTemp.path), isFalse);
    expect(isRemovableDrive('relative/path'), isFalse);
  });
}

void orphanState() {
  late Directory root;
  final scheduler = DownloadScheduler(maxConcurrent: 4);
  setUp(() => root = Directory.systemTemp.createTempSync('orphan_'));
  tearDown(() => root.deleteSync(recursive: true));

  String at(String name) => p.join(root.path, name);

  test('.segments יתום (לא קריא כמצב) אינו מצב חי ואינו נמחק', () {
    File(at('a.bin.segments')).writeAsStringSync('not json');
    File(at('b.bin.segments')).writeAsStringSync('{}');
    expect(hasSplitState(root.path), isFalse);
    expect(File(at('a.bin.segments')).existsSync(), isTrue);
    expect(File(at('b.bin.segments')).existsSync(), isTrue);
  });

  test('מצב של אסימון אחר, יעד שלם או צירוף חסר אינם חיים', () {
    writeLiveState(at('a.bin.segments'), token: 'old');
    expect(isLiveSegmentState(at('a.bin.segments'), token: 'new'), isFalse);
    expect(isLiveSegmentState(at('a.bin.segments'), token: 'old'), isTrue);
    File(at('a.bin')).writeAsBytesSync(List.filled(200, 0));
    expect(isLiveSegmentState(at('a.bin.segments')), isFalse, reason: 'שלם');
    File(at('a.bin')).deleteSync();
    final state =
        jsonDecode(File(at('a.bin.segments')).readAsStringSync())
            as Map<String, Object?>;
    File(
      at('a.bin.segments'),
    ).writeAsStringSync(jsonEncode({...state, 'assembled': 2}));
    expect(
      isLiveSegmentState(at('a.bin.segments')),
      isFalse,
      reason: 'assembled>1 בלי תחילית',
    );
  });

  test('מצב חי אחד בתיקייה עדיין משאיר את ההחלטה ברמת התיקייה', () {
    File(at('orphan.bin.segments')).writeAsStringSync('{}');
    expect(hasSplitState(root.path), isFalse);
    writeLiveState(at('live.bin.segments'));
    expect(hasSplitState(root.path), isTrue);
  });

  test(
    'connectionsForAsset: יתום או נכס אחר לא מבטלים מדידה של נכס אחר',
    () async {
      var probed = 0;
      Future<int> pick(String name, {String? token}) => connectionsForAsset(
        scheduler,
        at(name),
        token: token,
        removableProbe: (_) => true,
        writeProbe: (_) async {
          probed++;
          return 3.0 * _mib;
        },
      );
      File(at('orphan.bin.segments')).writeAsStringSync('{}');
      writeLiveState(at('live.bin.segments'), token: 'live');
      writeLiveState(at('stale.bin.segments'), token: 'old');

      expect(await pick('live.bin', token: 'live'), 2, reason: 'resume תקין');
      expect(probed, 0);
      expect(await pick('fresh.bin', token: 'x'), 1);
      expect(await pick('orphan.bin', token: 'x'), 1);
      expect(await pick('stale.bin', token: 'new'), 1);
      expect(probed, 3);
      expect(File(at('stale.bin.segments')).existsSync(), isTrue);
    },
  );

  test('הנלווים: אסימון ישן ב-.segments אינו משאיר פיצול', () async {
    final mirror = CompanionAssetsMirror(
      scheduler: scheduler,
      removableProbe: (_) => true,
      writeProbe: (_) async => 3.0 * _mib,
    );
    addTearDown(mirror.dispose);
    writeLiveState(at('a.bin.segments'), token: 'old');
    expect(await mirror.maxConnectionsFor(at('a.bin'), token: 'new'), 1);
    expect(await mirror.maxConnectionsFor(at('a.bin'), token: 'old'), 2);
  });
}

class _FakeRaf implements RandomAccessFile {
  _FakeRaf(this.onWrite);
  final Future<void> Function(int index) onWrite;
  int writes = 0;
  int flushes = 0;
  bool closed = false;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    await onWrite(writes++);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    flushes++;
    return this;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void cancellableProbe() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('cancel_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<RandomAccessFile> Function(File) opener(_FakeRaf raf) => (file) async {
    file.createSync();
    return raf;
  };

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  test('ביטול עוצר את הכתיבה, סוגר ומסיר את הקובץ', () async {
    var cancelled = false;
    final raf = _FakeRaf((i) async {
      if (i == 2) cancelled = true;
    });
    final speed = await measureWriteSpeed(
      root.path,
      isCancelled: () => cancelled,
      open: opener(raf),
    );
    expect(speed, isNull);
    expect(raf.writes, 3, reason: 'אחרי הנתח שבו בוטל לא נכתב עוד');
    expect(raf.closed, isTrue);
    expect(root.listSync(), isEmpty);
  });

  test('await על הביטול לא חוזר לפני סיום הכתיבה הפעילה', () async {
    final gate = Completer<void>();
    final raf = _FakeRaf((i) => i == 1 ? gate.future : Future.value());
    final measured = measureWriteSpeed(root.path, open: opener(raf));
    await until(() => raf.writes == 2);

    var settled = false;
    final settling = settleWriteProbes(
      cancel: true,
    ).then((_) => settled = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(settled, isFalse, reason: 'כתיבה עוד פועלת');
    expect(raf.closed, isFalse);
    expect(root.listSync(), hasLength(1));

    gate.complete();
    await settling;
    expect(await measured, isNull);
    expect(raf.writes, 2, reason: 'לא נכתב נתח נוסף אחרי הביטול');
    expect(raf.closed, isTrue);
    expect(root.listSync(), isEmpty);
  });

  test('timeout מבקש הפסקה: כתיבה תקועה לא ממשיכה אחרי שחזרה', () async {
    final gate = Completer<void>();
    final raf = _FakeRaf((i) => i == 1 ? gate.future : Future.value());
    final measured = measureWriteSpeed(
      root.path,
      timeout: const Duration(milliseconds: 50),
      open: opener(raf),
    );
    await until(() => raf.writes == 2);
    Timer(const Duration(milliseconds: 200), gate.complete);
    expect(await measured, isNull);
    await settleWriteProbes();
    expect(raf.writes, 2);
    expect(raf.closed, isTrue);
    expect(root.listSync(), isEmpty);
  });

  test('timeout אינו מחזיר בזמן שכתיבה עדיין פעילה', () async {
    final gate = Completer<void>();
    final raf = _FakeRaf((_) => gate.future);
    var returned = false;
    final measured =
        measureWriteSpeed(
          root.path,
          timeout: const Duration(milliseconds: 20),
          open: opener(raf),
        ).then((speed) {
          returned = true;
          return speed;
        });
    await until(() => raf.writes == 1);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(returned, isFalse, reason: 'הכונן עדיין מוחזק בידי המדידה');
      expect(raf.closed, isFalse);
    } finally {
      gate.complete();
      expect(await measured, isNull);
      await settleWriteProbes();
      expect(raf.closed, isTrue);
      expect(root.listSync(), isEmpty);
    }
  });

  test('מדידה שהגיעה לתקציב שוטפת גם קבוצה חלקית של כתיבות', () async {
    final raf = _FakeRaf((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await measureWriteSpeed(
      root.path,
      budget: const Duration(milliseconds: 50),
      open: opener(raf),
    );
    expect(raf.writes, inInclusiveRange(1, 3));
    expect(raf.flushes, 1);
    expect(raf.closed, isTrue);
  });

  test('connectionsForDir בביטול מחזיר ברירת מחדל ולא חיבור יחיד', () async {
    final scheduler = DownloadScheduler(maxConcurrent: 4);
    Future<int> pick(bool cancelled) => connectionsForDir(
      scheduler,
      root.path,
      removableProbe: (_) => true,
      splitProbe: (_) => false,
      writeProbe: (_) async => null,
      isCancelled: () => cancelled,
    );
    expect(await pick(false), 1);
    expect(await pick(true), 2);
  });
}
