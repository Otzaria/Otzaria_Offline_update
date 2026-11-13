import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// כותב יחיד לכל הקבצים שנפתחים דרכו: `writeFrom` שומר בקובץ זמני מקומי וחוזר,
/// וכותב אחד מעביר ליעד קובץ אחד בכל פעם — מה שכונן USB איטי כותב הכי מהר.
class WriteBehindPool {
  WriteBehindPool({
    this.maxPendingBytes = 4 * 1024 * 1024 * 1024,
    this.minBurstBytes = 16 * 1024 * 1024,
    this.yieldBytes = 64 * 1024 * 1024,
    this.maxDelay = const Duration(seconds: 5),
    this.starvedPatience = const Duration(seconds: 10),
    Directory? spillRoot,
  }) : _spillRoot = spillRoot ?? Directory.systemTemp;

  /// תקרת הקבצים הזמניים בדיסק המקומי; מעליה `writeFrom` מחכה לכונן.
  final int maxPendingBytes;

  /// קובץ שעוד יורד מתחיל להיכתב רק כשנצבר לו כזה רצף, או אחרי [maxDelay].
  final int minBurstBytes;

  /// אחרי רצף כזה קובץ שהורדתו הסתיימה נכנס לפני המשך הקובץ הנוכחי.
  final int yieldBytes;
  final Duration maxDelay;

  /// כמה מחכים לקובץ הנוכחי שנעצר, לפני מעבר לקובץ אחר שעוד יורד.
  final Duration starvedPatience;

  static const String spillPrefix = 'otzaria_write_behind_';
  static const String _lockName = '.lock';
  static const int _blockBytes = 1024 * 1024;
  static const int _recycleBytes = 8 * 1024 * 1024;

  final Directory _spillRoot;
  final List<_WriteBehindHandle> _open = [];
  final Set<String> _poisoned = {};
  _WriteBehindHandle? _current;
  Directory? _spillDir;
  RandomAccessFile? _lock;
  int _spillCount = 0;
  int _opening = 0;
  int _pending = 0;
  int _spillBytes = 0;
  int _sinceSwitch = 0;
  bool _pumping = false;
  Completer<void>? _wake;
  Completer<void>? _room;

  /// הבייטים שהתקבלו ועוד לא נכתבו לכונן.
  int get pendingBytes => _pending;

  /// הבייטים שהקבצים הזמניים תופסים כרגע בדיסק המקומי.
  int get spillBytes => _spillBytes;

  /// [File] שכל פתיחה שלו לכתיבה עוברת דרך התור; שאר הפעולות ישירות.
  File wrap(File file) => _WriteBehindFile(file, this);

  /// מריץ את [body] כשכל `File(path)` ש-[shouldWrap] מאשר נפתח דרך התור.
  R runZoned<R>(
    R Function() body, {
    required bool Function(String) shouldWrap,
  }) {
    final previous = IOOverrides.current;
    File base(String path) => previous?.createFile(path) ?? _plainFile(path);
    return IOOverrides.runZoned(
      body,
      createFile: (path) => shouldWrap(path) ? wrap(base(path)) : base(path),
    );
  }

  /// זורק את מה שעוד לא נכתב לכונן, לביטול: הקבצים נשארים תחילית תקינה,
  /// וסגירת כל קובץ פתוח תיכשל כדי שלא ייחשב שלם.
  void abandonPending() {
    for (final handle in _open) {
      handle._abandon();
    }
    _wakeRoom();
  }

  /// מוחק תיקיות זמניות שתהליך אחר השאיר: כל תיקייה שהנעילה שלה פנויה, ובלי
  /// קובץ נעילה רק ישנה מיממה.
  static void sweepStaleSpill({Directory? root, DateTime? now}) {
    try {
      final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 1));
      for (final entry in (root ?? Directory.systemTemp).listSync(
        followLinks: false,
      )) {
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (entry is! Directory || !name.startsWith(spillPrefix)) continue;
        try {
          final lock = _plainFile(_join(entry.path, _lockName));
          if (lock.existsSync()) {
            // נעילה תפוסה זורקת: התיקייה של תהליך חי.
            final handle = lock.openSync(mode: FileMode.append);
            try {
              handle.lockSync();
              handle.unlockSync();
            } finally {
              handle.closeSync();
            }
          } else if (!entry.statSync().modified.isBefore(cutoff)) {
            continue;
          }
          entry.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static String _join(String dir, String name) =>
      '$dir${Platform.pathSeparator}$name';

  String _newSpillPath() {
    final dir = _spillDir ??= _spillRoot.createTempSync(spillPrefix);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _lock ??= _plainFile(_join(dir.path, _lockName)).openSync(
      mode: FileMode.write,
    )..lockSync();
    return _join(dir.path, '${_spillCount++}.spill');
  }

  void _closed(_WriteBehindHandle handle) {
    if (!_open.remove(handle)) return;
    _spillFreed(handle._accepted - handle._base);
    if (_open.isNotEmpty || _opening > 0) return;
    final dir = _spillDir;
    if (dir == null) return;
    try {
      _lock?.closeSync();
      _lock = null;
      _plainFile(_join(dir.path, _lockName)).deleteSync();
      dir.deleteSync();
      _spillDir = null;
    } catch (_) {}
  }

  void _kick() {
    final wake = _wake;
    _wake = null;
    wake?.complete();
    if (!_pumping) {
      _pumping = true;
      unawaited(_pump());
    }
  }

  Future<void> _waitRoom(_WriteBehindHandle waiter) async {
    while (_spillBytes > maxPendingBytes &&
        !waiter._abandoned &&
        waiter._error == null) {
      await Future.wait([
        for (final handle in _open.toList()) handle._recycle(force: true),
      ]);
      if (_spillBytes <= maxPendingBytes) return;
      // אין מה שעוד יתפנה (למשל ריקון שנכשל): המתנה כאן לא תסתיים לעולם.
      if (_pending == 0 && !_open.any((h) => h._writing)) return;
      _kick();
      await (_room ??= Completer<void>()).future;
    }
  }

  void _spillFreed(int bytes) {
    _spillBytes -= bytes;
    if (_spillBytes <= maxPendingBytes) _wakeRoom();
  }

  void _wakeRoom() {
    final room = _room;
    _room = null;
    room?.complete();
  }

  /// קובץ שהורדתו הסתיימה ומחכה רק לכתיבה; הקטן קודם, כדי לשחרר את בעליו.
  _WriteBehindHandle? _finished({_WriteBehindHandle? except}) {
    _WriteBehindHandle? best;
    for (final handle in _open) {
      if (identical(handle, except) || !handle._drainRequested) continue;
      if (handle._queued == 0) continue;
      if (best == null || handle._queued < best._queued) best = handle;
    }
    return best;
  }

  /// הקובץ הנוכחי כבר כתב רצף ארוך, וקובץ שהסתיים מחכה מאחוריו.
  bool _shouldYield(_WriteBehindHandle current) =>
      !current._drainRequested &&
      _sinceSwitch >= yieldBytes &&
      _finished(except: current) != null;

  _WriteBehindHandle? _pick(DateTime now) {
    final current = _current;
    final overBudget = _spillBytes > maxPendingBytes;
    if (current != null && _open.contains(current)) {
      // נצמדים לקובץ אחד עד סופו: כל מעבר בין קבצים עולה לכונן כשנייה.
      final hasWork = current._queued >= _blockBytes ||
          (current._queued > 0 && current._drainRequested);
      if (hasWork && !_shouldYield(current)) return current;
      final finished = _finished(except: current);
      if (finished != null) return finished;
      if (hasWork) return current;
      if (!overBudget && now.difference(current._lastWrite) < starvedPatience) {
        return null;
      }
    }
    final finished = _finished();
    if (finished != null) return finished;
    _WriteBehindHandle? best;
    for (final handle in _open) {
      if (handle._queued == 0) continue;
      final ready = handle._queued >= minBurstBytes ||
          overBudget ||
          now.difference(handle._oldest!) >= maxDelay;
      if (ready && (best == null || handle._queued > best._queued)) {
        best = handle;
      }
    }
    return best;
  }

  Future<void> _pump() async {
    try {
      while (true) {
        final handle = _pick(DateTime.now());
        if (handle == null) {
          if (_open.every((h) => h._queued == 0)) return;
          final wake = _wake ??= Completer<void>();
          await wake.future.timeout(
            const Duration(milliseconds: 100),
            onTimeout: () {},
          );
          continue;
        }
        if (!identical(handle, _current)) {
          _current = handle;
          _sinceSwitch = 0;
        }
        await handle._writeBurst();
      }
    } finally {
      _pumping = false;
      if (_open.any((h) => h._queued > 0)) _kick();
    }
  }
}

/// באזור השורש אין דריסה, ולכן `File` שם הוא הקובץ האמיתי ולא עטיפה.
File _plainFile(String path) => Zone.root.run(() => File(path));

class _WriteBehindHandle implements RandomAccessFile {
  _WriteBehindHandle(this._real, this._pool, this._spillPath, this._spill) {
    _pool._open.add(this);
  }

  final RandomAccessFile _real;
  final WriteBehindPool _pool;
  final String _spillPath;
  final RandomAccessFile _spill;
  RandomAccessFile? _spillReader;

  /// כמה בייטים התקבלו, כמה מהם כבר ביעד, ומאיזה מהם מתחיל הקובץ הזמני.
  int _accepted = 0;
  int _copied = 0;
  int _base = 0;
  Future<void> _spillTail = Future<void>.value();
  DateTime? _oldest;
  DateTime _lastWrite = DateTime.now();
  bool _drainRequested = false;
  bool _writing = false;
  bool _direct = false;
  bool _abandoned = false;
  bool _closing = false;
  Object? _error;
  StackTrace? _errorStack;
  Completer<void>? _idle;

  int get _queued => _accepted - _copied;

  @override
  String get path => _real.path;

  void _throwIfFailed() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _errorStack!);
  }

  /// פעולות על הקובץ הזמני רצות אחת אחרי השנייה: כתיבה ומיחזור לא מתערבבים.
  Future<T> _withSpill<T>(Future<T> Function() action) {
    final previous = _spillTail;
    final done = Completer<void>();
    _spillTail = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }

  /// מרוקן קובץ זמני שכולו כבר ביעד, כדי שלא יגדל לגודל הקובץ כולו.
  Future<void> _recycle({bool force = false}) => _withSpill(() async {
        final held = _accepted - _base;
        if (_queued > 0 || _writing || held == 0) return;
        if (!force && held < WriteBehindPool._recycleBytes) return;
        try {
          await _spill.truncate(0);
          await _spill.setPosition(0);
        } catch (_) {
          _pool._wakeRoom();
          return;
        }
        _base = _accepted;
        _pool._spillFreed(held);
      });

  void _fail(Object error, StackTrace stack) {
    _error ??= error;
    _errorStack ??= stack;
    _pool._poisoned.add(path);
    _dropQueued();
  }

  void _dropQueued() {
    _pool._pending -= _queued;
    _copied = _accepted;
  }

  void _abandon() {
    if (_abandoned) return;
    // קובץ שכבר נסגר ונשאר לו מעט מסיים: כשל בסגירה היה מוחק את כולו.
    if (_closing && _queued <= _pool.yieldBytes) return;
    _abandoned = true;
    _dropQueued();
    if (_writing) return;
    _signalIdle();
    unawaited(_recycle(force: true));
  }

  void _signalIdle() {
    final idle = _idle;
    _idle = null;
    idle?.complete();
  }

  /// כותב ליעד את מה שנצבר, גם מה שמגיע תוך כדי, בגושים שלמים; שארית קטנה
  /// מגוש נכתבת רק כשהקובץ נסגר, כי כתיבות קטנות הן האיטיות ביותר לכונן.
  Future<void> _writeBurst() async {
    if (_error != null || _abandoned) {
      _dropQueued();
      _signalIdle();
      return;
    }
    _writing = true;
    try {
      final reader = _spillReader ??= await _plainFile(_spillPath).open();
      await reader.setPosition(_copied - _base);
      do {
        final want = _queued < WriteBehindPool._blockBytes
            ? _queued
            : WriteBehindPool._blockBytes;
        final block = await reader.read(want);
        if (_abandoned) break;
        if (block.isEmpty) {
          throw FileSystemException('spill truncated', _spillPath);
        }
        await _real.writeFrom(block);
        if (_abandoned) break;
        _copied += block.length;
        _pool._pending -= block.length;
        _pool._sinceSwitch += block.length;
      } while ((_queued >= WriteBehindPool._blockBytes ||
              (_queued > 0 && _drainRequested)) &&
          !_pool._shouldYield(this));
    } catch (error, stack) {
      // תוכן אחרי כשל כתיבה אינו ודאי: מה שנצבר נזרק, והקורא מקבל את השגיאה.
      _fail(error, stack);
    } finally {
      _writing = false;
      _lastWrite = DateTime.now();
      _oldest = _queued == 0 ? null : _lastWrite;
      if (_queued == 0) {
        _signalIdle();
        unawaited(
          _recycle(force: _pool._spillBytes > _pool.maxPendingBytes),
        );
      }
    }
  }

  /// מחכה שכל מה שהתקבל ייכתב, וזורק כשל כתיבה שקרה בדרך.
  Future<void> _drain() async {
    while (_queued > 0 || _writing) {
      _drainRequested = true;
      _pool._kick();
      await (_idle ??= Completer<void>()).future;
    }
    _drainRequested = false;
    _throwIfFailed();
  }

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    _throwIfFailed();
    final stop = RangeError.checkValidRange(start, end, buffer.length);
    if (stop == start || _abandoned) return this;
    if (!_direct) {
      if (_queued == 0 && !_writing) await _recycle();
      final spilled = await _withSpill(() async {
        try {
          await _spill.writeFrom(buffer, start, stop);
        } catch (_) {
          return false;
        }
        // כשל של היעד בזמן הכתיבה הזמנית: הבייטים האלה לא נכנסים לתור.
        if (_error != null || _abandoned) return true;
        final count = stop - start;
        _accepted += count;
        _oldest ??= DateTime.now();
        _pool._pending += count;
        _pool._spillBytes += count;
        return true;
      });
      // אין מקום זמני בדיסק המקומי: ממשיכים בכתיבה ישירה ליעד.
      if (!spilled) _direct = true;
    }
    if (_direct) {
      await _drain();
      if (_abandoned) return this;
      await _real.writeFrom(buffer, start, stop);
      return this;
    }
    _throwIfFailed();
    _pool._kick();
    await _pool._waitRoom(this);
    _throwIfFailed();
    return this;
  }

  @override
  Future<void> close() async {
    _closing = true;
    try {
      await _drain();
    } finally {
      try {
        await _spillReader?.close();
      } catch (_) {}
      try {
        await _spillTail;
        await _spill.close();
        _plainFile(_spillPath).deleteSync();
      } catch (_) {}
      _pool._closed(this);
      await _real.close();
    }
    if (_abandoned) {
      throw FileSystemException('write-behind: pending writes dropped', path);
    }
  }

  @override
  Future<RandomAccessFile> writeByte(int value) => writeFrom([value]);

  @override
  Future<RandomAccessFile> writeString(
    String string, {
    Encoding encoding = utf8,
  }) =>
      writeFrom(encoding.encode(string));

  @override
  Future<RandomAccessFile> flush() async {
    await _drain();
    await _real.flush();
    return this;
  }

  @override
  Future<int> length() async {
    await _drain();
    return _real.length();
  }

  @override
  Future<int> position() async {
    await _drain();
    return _real.position();
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await _drain();
    await _real.setPosition(position);
    return this;
  }

  @override
  Future<RandomAccessFile> truncate(int length) async {
    await _drain();
    await _real.truncate(length);
    return this;
  }

  @override
  Future<int> readByte() async {
    await _drain();
    return _real.readByte();
  }

  @override
  Future<Uint8List> read(int count) async {
    await _drain();
    return _real.read(count);
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    await _drain();
    return _real.readInto(buffer, start, end);
  }

  @override
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) async {
    await _real.lock(mode, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) async {
    await _real.unlock(start, end);
    return this;
  }

  /// פעולה סינכרונית אינה יכולה לחכות לתור; היא חוקית רק כשהוא ריק.
  T _sync<T>(T Function() action) {
    if (_queued > 0 || _writing) {
      throw StateError('write-behind: sync call with pending writes');
    }
    _throwIfFailed();
    return action();
  }

  @override
  void closeSync() => _sync(() {
        try {
          _spillReader?.closeSync();
          _spill.closeSync();
          _plainFile(_spillPath).deleteSync();
        } catch (_) {}
        _pool._closed(this);
        _real.closeSync();
      });

  @override
  void flushSync() => _sync(_real.flushSync);

  @override
  int lengthSync() => _sync(_real.lengthSync);

  @override
  int positionSync() => _sync(_real.positionSync);

  @override
  void setPositionSync(int position) =>
      _sync(() => _real.setPositionSync(position));

  @override
  void truncateSync(int length) => _sync(() => _real.truncateSync(length));

  @override
  int readByteSync() => _sync(_real.readByteSync);

  @override
  Uint8List readSync(int count) => _sync(() => _real.readSync(count));

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) =>
      _sync(() => _real.readIntoSync(buffer, start, end));

  @override
  int writeByteSync(int value) => _sync(() => _real.writeByteSync(value));

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) =>
      _sync(() => _real.writeFromSync(buffer, start, end));

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) =>
      _sync(() => _real.writeStringSync(string, encoding: encoding));

  @override
  void lockSync([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) =>
      _real.lockSync(mode, start, end);

  @override
  void unlockSync([int start = 0, int end = -1]) =>
      _real.unlockSync(start, end);
}

class _WriteBehindFile implements File {
  _WriteBehindFile(this._real, this._pool);

  final File _real;
  final WriteBehindPool _pool;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (mode != FileMode.read && _pool._poisoned.remove(path)) {
      final resumes =
          mode == FileMode.append || mode == FileMode.writeOnlyAppend;
      // כתיבה קודמת לקובץ הזה נכשלה והוא נשאר: מי שממשיך אותו חייב לדעת.
      if (resumes && await _real.exists()) {
        throw FileSystemException('write-behind: earlier write failed', path);
      }
    }
    final handle = await _real.open(mode: mode);
    if (mode == FileMode.read) return handle;
    _pool._opening++;
    try {
      final spillPath = _pool._newSpillPath();
      final spill = await _plainFile(spillPath).open(mode: FileMode.write);
      return _WriteBehindHandle(handle, _pool, spillPath, spill);
    } catch (_) {
      // בלי מקום זמני בדיסק המקומי הכתיבה נשארת ישירה, כמו בלי התור.
      return handle;
    } finally {
      _pool._opening--;
    }
  }

  @override
  String get path => _real.path;
  @override
  Uri get uri => _real.uri;
  @override
  bool get isAbsolute => _real.isAbsolute;
  @override
  File get absolute => _real.absolute;
  @override
  Directory get parent => _real.parent;
  @override
  Future<bool> exists() => _real.exists();
  @override
  bool existsSync() => _real.existsSync();
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      _real.create(recursive: recursive, exclusive: exclusive);
  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _real.createSync(recursive: recursive, exclusive: exclusive);
  @override
  Future<File> rename(String newPath) => _real.rename(newPath);
  @override
  File renameSync(String newPath) => _real.renameSync(newPath);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    _pool._poisoned.remove(path);
    return _real.delete(recursive: recursive);
  }

  @override
  void deleteSync({bool recursive = false}) {
    _pool._poisoned.remove(path);
    _real.deleteSync(recursive: recursive);
  }

  @override
  String toString() => _real.toString();
  @override
  Future<File> copy(String newPath) => _real.copy(newPath);
  @override
  File copySync(String newPath) => _real.copySync(newPath);
  @override
  Future<int> length() => _real.length();
  @override
  int lengthSync() => _real.lengthSync();
  @override
  Future<DateTime> lastAccessed() => _real.lastAccessed();
  @override
  DateTime lastAccessedSync() => _real.lastAccessedSync();
  @override
  Future<dynamic> setLastAccessed(DateTime time) => _real.setLastAccessed(time);
  @override
  void setLastAccessedSync(DateTime time) => _real.setLastAccessedSync(time);
  @override
  Future<DateTime> lastModified() => _real.lastModified();
  @override
  DateTime lastModifiedSync() => _real.lastModifiedSync();
  @override
  Future<dynamic> setLastModified(DateTime time) => _real.setLastModified(time);
  @override
  void setLastModifiedSync(DateTime time) => _real.setLastModifiedSync(time);
  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _real.openSync(mode: mode);
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _real.openRead(start, end);
  @override
  IOSink openWrite(
          {FileMode mode = FileMode.write, Encoding encoding = utf8}) =>
      _real.openWrite(mode: mode, encoding: encoding);
  @override
  Future<Uint8List> readAsBytes() => _real.readAsBytes();
  @override
  Uint8List readAsBytesSync() => _real.readAsBytesSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _real.readAsString(encoding: encoding);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      _real.readAsStringSync(encoding: encoding);
  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      _real.readAsLines(encoding: encoding);
  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      _real.readAsLinesSync(encoding: encoding);
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) =>
      _real.writeAsBytes(bytes, mode: mode, flush: flush);
  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) =>
      _real.writeAsBytesSync(bytes, mode: mode, flush: flush);
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      _real.writeAsString(
        contents,
        mode: mode,
        encoding: encoding,
        flush: flush,
      );
  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      _real.writeAsStringSync(
        contents,
        mode: mode,
        encoding: encoding,
        flush: flush,
      );
  @override
  Future<String> resolveSymbolicLinks() => _real.resolveSymbolicLinks();
  @override
  String resolveSymbolicLinksSync() => _real.resolveSymbolicLinksSync();
  @override
  Future<FileStat> stat() => _real.stat();
  @override
  FileStat statSync() => _real.statSync();
  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) =>
      _real.watch(events: events, recursive: recursive);
}
