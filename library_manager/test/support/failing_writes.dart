import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The OS code for a full drive: 112 on Windows, ENOSPC elsewhere.
final int diskFullErrno = Platform.isWindows ? 112 : 28;

/// כשל כתיבה אסינכרוני של הדיסק: הקובץ שנכתב אליו מקבל [failAfterBytes] בתים
/// ואז הכתיבה נכשלת כ"הכונן מלא" (errno 112 / 28) — בזמן שהקורא עדיין מוסיף נתונים.
Future<T> runWithFailingWrites<T>(
  FutureOr<T> Function() body, {
  required bool Function(String path) matches,
  int failAfterBytes = 0,
  int? errno,
  void Function(String path)? onOpened,
}) => IOOverrides.runZoned(
  () async => body(),
  createFile: (path) {
    final real = Zone.root.run(() => File(path));
    if (!matches(path)) return real;
    return _FailingWriteFile(
      real,
      failAfterBytes,
      errno ?? diskFullErrno,
      onOpened,
    );
  },
);

class _FailingWriteFile implements File {
  _FailingWriteFile(this._real, this._failAfter, this._errno, this._onOpened);

  final File _real;
  final int _failAfter;
  final int _errno;
  final void Function(String path)? _onOpened;

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    _onOpened?.call(_real.path);
    return IOSink(
      _FailingConsumer(
        _real.openWrite(mode: mode, encoding: encoding),
        _real.path,
        _failAfter,
        _errno,
      ),
      encoding: encoding,
    );
  }

  @override
  Future<File> copy(String newPath) => Future.error(
    FileSystemException(
      'Cannot copy file to \'$newPath\'',
      _real.path,
      OSError('There is not enough space on the disk.', _errno),
    ),
  );

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _real.open(mode: mode);

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => _real.exists();

  @override
  bool existsSync() => _real.existsSync();

  @override
  Future<int> length() => _real.length();

  @override
  int lengthSync() => _real.lengthSync();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _real.delete(recursive: recursive);

  @override
  void deleteSync({bool recursive = false}) =>
      _real.deleteSync(recursive: recursive);

  @override
  Future<File> rename(String newPath) => _real.rename(newPath);

  @override
  File renameSync(String newPath) => _real.renameSync(newPath);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _real.openRead(start, end);

  @override
  Future<Uint8List> readAsBytes() => _real.readAsBytes();

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _real.readAsString(encoding: encoding);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not forwarded');
}

class _FailingConsumer implements StreamConsumer<List<int>> {
  _FailingConsumer(this._inner, this._path, this._failAfter, this._errno);

  final IOSink _inner;
  final String _path;
  final int _failAfter;
  final int _errno;
  var _written = 0;

  @override
  Future addStream(Stream<List<int>> stream) {
    final done = Completer<void>();
    late StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (chunk) {
        _written += chunk.length;
        if (_written > _failAfter) {
          subscription.cancel();
          // כמו `_FileStreamConsumer` האמיתי: הידית נסגרת לפני שהכשל מדווח.
          _inner.close().whenComplete(() {
            if (done.isCompleted) return;
            done.completeError(
              FileSystemException(
                'Write failed',
                _path,
                OSError('There is not enough space on the disk.', _errno),
              ),
              StackTrace.current,
            );
          });
          return;
        }
        _inner.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  @override
  Future close() async {
    await _inner.close();
  }
}

/// Like [runWithFailingWrites], for writes through `File.open` +
/// `RandomAccessFile.writeFrom`: matching files fail with "disk full" async.
Future<T> runWithFailingRandomWrites<T>(
  FutureOr<T> Function() body, {
  required bool Function(String path) matches,
  int? errno,
}) => IOOverrides.runZoned(
  () async => body(),
  createFile: (path) {
    final real = Zone.root.run(() => File(path));
    return matches(path)
        ? _RandomWriteFile(real, errno ?? diskFullErrno)
        : real;
  },
);

class _RandomWriteFile implements File {
  _RandomWriteFile(this._real, this._errno);

  final File _real;
  final int _errno;

  @override
  String get path => _real.path;

  @override
  bool existsSync() => _real.existsSync();

  @override
  Future<bool> exists() => _real.exists();

  @override
  int lengthSync() => _real.lengthSync();

  @override
  Future<int> length() => _real.length();

  @override
  void deleteSync({bool recursive = false}) =>
      _real.deleteSync(recursive: recursive);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (mode == FileMode.read) return _real.open(mode: mode);
    _real.writeAsBytesSync(
      const [],
      mode: mode == FileMode.append ? FileMode.append : FileMode.write,
    );
    return _FailingRandomAccessFile(_real.path, _errno);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not forwarded');
}

class _FailingRandomAccessFile implements RandomAccessFile {
  _FailingRandomAccessFile(this.path, this._errno);

  @override
  final String path;
  final int _errno;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) => Future.delayed(
    Duration.zero,
    () => throw FileSystemException(
      'writeFrom failed',
      path,
      OSError('There is not enough space on the disk.', _errno),
    ),
  );

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not forwarded');
}
