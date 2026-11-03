import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// החיבורים לקובץ גדול במשבצת של [scheduler] — אותה חלוקה של הייצוא, כדי
/// שגם הנלווים שחולקים איתו את המשבצות לא יעברו את התקרה הכוללת.
int connectionsPerFile(DownloadScheduler scheduler) {
  final share =
      LibraryMirrorExporter.maxTotalConnections ~/ scheduler.maxConcurrent;
  if (share < 1) return 1;
  const requested = PatchDownloader.defaultMaxConnections;
  return share < requested ? share : requested;
}

/// מתחת לקצב כתיבה כזה (10 MiB/s) הורדה מפוצלת מאטה: צירוף הטווחים מגדיל
/// את הכתיבה ל-1.5x-1.75x. הרשת הצפויה היא ~2 MiB/s.
const int slowWriteBytesPerSecond = 10 * 1024 * 1024;

/// חיבור יחיד ליעד איטי לכתיבה או כשהמדידה נכשלה; נכס שכבר מפוצל ממשיך
/// בחלוקה, כי חיבור יחיד היה זורק אותה.
int connectionsForTarget(
  DownloadScheduler scheduler, {
  required bool slowTarget,
  required bool resumingSplit,
}) => slowTarget && !resumingSplit ? 1 : connectionsPerFile(scheduler);

/// שורש הכונן בצורה ש-`GetDriveTypeW` מקבל (`E:\`, `\\server\share\`).
@visibleForTesting
String driveRootFor(String path, {p.Context? context}) {
  final ctx = context ?? p.context;
  final root = ctx.rootPrefix(ctx.absolute(path)).replaceAll('/', r'\');
  if (root.isEmpty) return '';
  return root.endsWith(r'\') ? root : '$root\\';
}

/// כונן נשלף לפי ווינדוס בלבד (`DRIVE_REMOVABLE`); בשאר המערכות false.
bool isRemovableDrive(String path) {
  if (!Platform.isWindows) return false;
  try {
    final root = driveRootFor(path);
    if (root.isEmpty) return false;
    final getDriveType = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Uint32 Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)
        >('GetDriveTypeW');
    final native = root.toNativeUtf16();
    try {
      return getDriveType(native) == 2; // DRIVE_REMOVABLE
    } finally {
      malloc.free(native);
    }
  } catch (_) {
    return false;
  }
}

typedef WriteSpeedProbe = Future<double?> Function(String dir);

const writeProbeTimeout = Duration(seconds: 10);
const _probePrefix = '.write_probe_';
const _probeChunkBytes = 256 * 1024;
const _probeFlushEvery = 4;

/// מוחק גשושיות יתומות של תהליך אחר שקרס; רק לפי תבנית השם ורק ישנות.
void _sweepOrphanProbes(String dir) {
  try {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    for (final entry in Directory(dir).listSync(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is! File ||
          !RegExp(r'^\.write_probe_(\d+)_\d+$').hasMatch(name) ||
          name.startsWith('$_probePrefix${pid}_')) {
        continue;
      }
      try {
        if (entry.lastModifiedSync().isBefore(cutoff)) entry.deleteSync();
      } catch (_) {}
    }
  } catch (_) {}
}

class _ProbeRun {
  bool stop = false;
  final done = Completer<void>();
}

final _activeProbes = <_ProbeRun>{};

/// מחכה שכל מדידת כתיבה פעילה תסגור את הקובץ ותמחק אותו; עם [cancel] מבקש
/// קודם מכולן להפסיק. מי שמכריז "הכל הושלם" או "הכונן מוכן" חייב לחכות לזה:
/// כתיבה שעוד פועלת מחזיקה את הקובץ ואת הכונן.
Future<void> settleWriteProbes({bool cancel = false}) async {
  while (_activeProbes.isNotEmpty) {
    final runs = _activeProbes.toList();
    if (cancel) {
      for (final run in runs) {
        run.stop = true;
      }
    }
    await Future.wait(runs.map((run) => run.done.future));
  }
}

/// קצב כתיבה לקובץ זמני, או null בכשל או בביטול. [timeout] מבקש הפסקה;
/// פעולה שכבר נמסרה למערכת ההפעלה חייבת להסתיים לפני שסוגרים ומחזירים.
Future<double?> measureWriteSpeed(
  String dir, {
  int totalBytes = 8 * 1024 * 1024,
  Duration budget = const Duration(milliseconds: 1500),
  Duration timeout = writeProbeTimeout,
  bool Function()? isCancelled,
  @visibleForTesting Future<RandomAccessFile> Function(File file)? open,
}) async {
  if (isCancelled?.call() ?? false) return null;
  final file = File(
    p.join(dir, '$_probePrefix${pid}_${DateTime.now().microsecondsSinceEpoch}'),
  );
  final run = _ProbeRun();
  _activeProbes.add(run);
  bool stopped() => run.stop || (isCancelled?.call() ?? false);

  Future<double?> probe() async {
    RandomAccessFile? raf;
    try {
      if (stopped()) return null;
      await Directory(dir).create(recursive: true);
      if (stopped()) return null;
      _sweepOrphanProbes(dir);
      raf = await (open ?? (f) => f.open(mode: FileMode.write))(file);
      if (stopped()) return null;
      final chunk = Uint8List(_probeChunkBytes);
      var seed = 0x2545F491;
      for (var i = 0; i < chunk.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        chunk[i] = seed >> 16;
      }
      final watch = Stopwatch()..start();
      var written = 0;
      var writes = 0;
      while (written < totalBytes && watch.elapsed < budget) {
        if (stopped()) return null;
        await raf.writeFrom(chunk);
        written += chunk.length;
        if (++writes % _probeFlushEvery == 0) await raf.flush();
      }
      if (stopped()) return null;
      if (writes % _probeFlushEvery != 0) await raf.flush();
      if (stopped()) return null;
      watch.stop();
      final micros = watch.elapsedMicroseconds;
      return micros <= 0 ? null : written * 1000000 / micros;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  final running = probe().whenComplete(() {
    _activeProbes.remove(run);
    run.done.complete();
  });
  final deadline = Timer(timeout, () => run.stop = true);
  try {
    return await running;
  } finally {
    deadline.cancel();
  }
}

final _speeds = <String, ({Future<double?> speed, DateTime at})>{};
const _speedTtl = Duration(minutes: 10);

@visibleForTesting
void resetWriteSpeedCache() => _speeds.clear();

/// [measureWriteSpeed] עם מטמון לכל כונן בתוך התהליך; כשל אינו נשמר. התוקף
/// קצר כי כונן נשלף מוחלף באותה אות. [isCancelled] מועבר רק למדידה המובנית.
Future<double?> driveWriteSpeed(
  String dir, {
  WriteSpeedProbe? measure,
  DateTime Function()? clock,
  Duration timeout = writeProbeTimeout,
  bool Function()? isCancelled,
}) async {
  final now = (clock ?? DateTime.now)();
  var key = driveRootFor(dir);
  if (key.isEmpty) key = dir;
  if (Platform.isWindows) key = key.toLowerCase();
  final cached = _speeds[key];
  if (cached != null) {
    final age = now.difference(cached.at);
    if (!age.isNegative && age < _speedTtl) return cached.speed;
  }
  final speed = (() async {
    try {
      return await (measure != null
          ? measure(dir).timeout(timeout)
          : measureWriteSpeed(dir, isCancelled: isCancelled, timeout: timeout));
    } catch (_) {
      return null;
    }
  })();
  _speeds[key] = (speed: speed, at: now);
  final value = await speed;
  if (value == null && identical(_speeds[key]?.speed, speed)) {
    _speeds.remove(key);
  }
  return value;
}

/// האם [statePath] (`<dest>.segments`) הוא מצב פיצול שההורדה תמשיך ממנו, לפי
/// אותם תנאים שהמנוע בודק לפני המשך (בלי התאמת כתובת): מבנה תקין, והקבצים
/// שעל הדיסק עקביים איתו. עם [token] נדרשת גם התאמה לאסימון הנכס. יתום — לא
/// קריא כמצב, של אסימון אחר, או שהיעד שלם — המנוע ימחק אותו בלאו הכי, ולכן
/// אינו מצדיק הקלה. קובץ שאי אפשר לקרוא (שגיאת קובץ) נחשב כמצב: שמרני.
@visibleForTesting
bool isLiveSegmentState(String statePath, {String? token}) {
  try {
    final stateFile = File(statePath);
    if (!stateFile.existsSync()) return false;
    final json = jsonDecode(stateFile.readAsStringSync());
    if (json is! Map || json['v'] != 1) return false;
    final stored = json['token'];
    if (stored is! String || (token != null && stored != token)) return false;
    final size = json['size'];
    final bounds = (json['bounds'] as List).cast<int>();
    final assembled = json['assembled'] as int;
    if (size is! int ||
        bounds.length < 3 ||
        bounds.first != 0 ||
        bounds.last != size) {
      return false;
    }
    for (var i = 1; i < bounds.length; i++) {
      if (bounds[i] <= bounds[i - 1]) return false;
    }
    if (assembled < 1 || assembled > bounds.length - 1) return false;
    if (json['etag'] == null && json['sha256'] == null) return false;
    final dest = statePath.substring(0, statePath.length - '.segments'.length);
    final destFile = File(dest);
    final destLength = destFile.existsSync() ? destFile.lengthSync() : 0;
    if (destLength >= size) return false;
    if (assembled > 1 && destLength < bounds[assembled]) return false;
    for (var i = assembled; i < bounds.length - 1; i++) {
      final segment = File('$dest.seg-$i');
      if (segment.existsSync() &&
          segment.lengthSync() > bounds[i + 1] - bounds[i]) {
        return false;
      }
    }
    return true;
  } on FileSystemException {
    return true;
  } catch (_) {
    return false;
  }
}

/// האם לנכס [destPath] יש מצב פיצול חי (מצב של נכס אחר או יתום אינו נספר).
bool hasAssetSplitState(String destPath, {String? token}) =>
    isLiveSegmentState('$destPath.segments', token: token);

/// האם יש ב-[dir] מצב פיצול חי (`*.segments`, ראו [isLiveSegmentState]), עד
/// [maxDepth] רמות. `.segments` יתום אינו נספר ואינו נמחק. תיקייה שאי אפשר
/// לקרוא נחשבת כמצב שמור: הפסדו עולה ~1.5GB. ההחלטה כאן היא לכל התיקייה כי
/// המנוע מקבל מספר חיבורים אחד; ברמת נכס ראו [hasAssetSplitState].
bool hasSplitState(
  String dir, {
  int maxDepth = 4,
  @visibleForTesting List<FileSystemEntity> Function(String)? list,
}) {
  final lister =
      list ?? (String d) => Directory(d).listSync(followLinks: false);
  final pending = [(dir, 0)];
  while (pending.isNotEmpty) {
    final (current, depth) = pending.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = lister(current);
    } catch (_) {
      if (!Directory(current).existsSync()) continue;
      return true;
    }
    for (final entry in entries) {
      if (entry is File &&
          entry.path.endsWith('.segments') &&
          isLiveSegmentState(entry.path)) {
        return true;
      }
      if (entry is Directory && depth < maxDepth) {
        pending.add((entry.path, depth + 1));
      }
    }
  }
  return false;
}

/// הבחירה לתיקיית יעד שלמה; הזיהויים ניתנים להזרקה לבדיקות. מדידת הכתיבה
/// נעשית רק בכונן נשלף שאין בו מצב פיצול חי. בביטול ([isCancelled]) מחכה
/// שהמדידה תסגור ותמחק את הקובץ שלה ומחזיר את ברירת המחדל — הקורא עוצר בעצמו.
Future<int> connectionsForDir(
  DownloadScheduler scheduler,
  String dir, {
  bool Function(String)? removableProbe,
  bool Function(String)? splitProbe,
  WriteSpeedProbe? writeProbe,
  bool Function()? isCancelled,
}) async {
  if (!(removableProbe ?? isRemovableDrive)(dir)) {
    return connectionsPerFile(scheduler);
  }
  if ((splitProbe ?? hasSplitState)(dir)) return connectionsPerFile(scheduler);
  final speed =
      await (writeProbe ?? (d) => driveWriteSpeed(d, isCancelled: isCancelled))(
        dir,
      );
  if (isCancelled?.call() ?? false) {
    await settleWriteProbes(cancel: true);
    return connectionsPerFile(scheduler);
  }
  return connectionsForTarget(
    scheduler,
    slowTarget: speed == null || speed < slowWriteBytesPerSecond,
    resumingSplit: false,
  );
}

/// הבחירה לנכס בודד: מצב פיצול חי של אותו נכס ממשיך בחלוקה בלי מדידה; אחרת
/// בכונן נשלף מודדים. כך `.segments` יתום או של נכס אחר לא משפיע עליו.
Future<int> connectionsForAsset(
  DownloadScheduler scheduler,
  String destPath, {
  String? token,
  bool Function(String)? removableProbe,
  WriteSpeedProbe? writeProbe,
  bool Function()? isCancelled,
}) async {
  if (hasAssetSplitState(destPath, token: token)) {
    return connectionsPerFile(scheduler);
  }
  final dir = p.dirname(destPath);
  if (!(removableProbe ?? isRemovableDrive)(dir)) {
    return connectionsPerFile(scheduler);
  }
  final speed =
      await (writeProbe ?? (d) => driveWriteSpeed(d, isCancelled: isCancelled))(
        dir,
      );
  if (isCancelled?.call() ?? false) {
    await settleWriteProbes(cancel: true);
    return connectionsPerFile(scheduler);
  }
  return connectionsForTarget(
    scheduler,
    slowTarget: speed == null || speed < slowWriteBytesPerSecond,
    resumingSplit: false,
  );
}
