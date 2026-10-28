import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

FileSystemException _writeError(String path, int errno) => FileSystemException(
      'write failed',
      path,
      OSError('simulated', errno),
    );

/// כל כתיבה ל-[target] נכשלת אסינכרונית, אחרי שהקריאה חזרה, כמו כתיבה אמיתית.
final class _FailingDiskOverrides extends IOOverrides {
  _FailingDiskOverrides(this.target, this.errno, {this.failOpen = false});

  final String target;
  final handles = <_FailingRandomAccessFile>[];
  final int errno;
  final bool failOpen;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path == target
        ? _FailingWriteFile(file, errno, handles, failOpen: failOpen)
        : file;
  }
}

class _FailingWriteFile implements File {
  _FailingWriteFile(this._real, this.errno, this.handles,
      {this.failOpen = false});

  final File _real;
  final int errno;
  final List<_FailingRandomAccessFile> handles;
  final bool failOpen;

  @override
  String get path => _real.path;
  @override
  Directory get parent => _real.parent;
  @override
  Future<bool> exists() => _real.exists();
  @override
  Future<int> length() => _real.length();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) => _real.delete();
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) =>
      _real.writeAsBytes(bytes, mode: mode, flush: flush);
  @override
  Future<File> rename(String newPath) => _real.rename(newPath);

  void _touch(FileMode mode) => _real.writeAsBytesSync(
        const [],
        mode: mode == FileMode.append ? FileMode.append : FileMode.write,
      );

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    _touch(mode);
    return IOSink(_FailingConsumer(path, errno));
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (failOpen) throw _writeError(path, errno);
    _touch(mode);
    final handle = _FailingRandomAccessFile(path, errno);
    handles.add(handle);
    return handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// כמו `_FileStreamConsumer` של dart:io: עוצר את הזרם, כותב, ונכשל.
class _FailingConsumer implements StreamConsumer<List<int>> {
  _FailingConsumer(this.path, this.errno);

  final String path;
  final int errno;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final done = Completer<void>();
    late StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (_) {
        subscription.pause();
        Timer.run(() {
          subscription.cancel();
          if (!done.isCompleted) done.completeError(_writeError(path, errno));
        });
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  @override
  Future<void> close() async {}
}

class _FailingRandomAccessFile implements RandomAccessFile {
  _FailingRandomAccessFile(this.path, this.errno);

  @override
  final String path;
  final int errno;
  var closed = false;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) =>
      Future.delayed(Duration.zero, () => throw _writeError(path, errno));

  @override
  Future<RandomAccessFile> truncate(int length) async {
    Zone.root.run(() {
      final real = File(path).openSync(mode: FileMode.append);
      real.truncateSync(length);
      real.closeSync();
    });
    return this;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Capture {
  _Capture(this.error, this.uncaught);
  final Object? error;
  final List<Object> uncaught;
}

Future<_Capture> _runCapturing(
  IOOverrides overrides,
  Future<void> Function() body,
) async {
  final uncaught = <Object>[];
  final outcome = Completer<Object?>();
  unawaited(runZonedGuarded(
    () => IOOverrides.runWithIOOverrides(body, overrides).then(
      (_) => outcome.complete(null),
      onError: (Object error) => outcome.complete(error),
    ),
    (error, _) => uncaught.add(error),
  ));
  final error = await outcome.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () => TimeoutException('the download did not finish'),
  );
  return _Capture(error, uncaught);
}

void main() {
  late Directory temp;
  late String target;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('write-failure-');
    target = '${temp.path}${Platform.pathSeparator}asset.bin';
  });
  tearDown(() => temp.deleteSync(recursive: true));

  final body = Uint8List.fromList(List.generate(1000, (i) => i % 251));
  final fullErrno = Platform.isWindows ? 112 : 28;

  // המקור מוסר צ'אנק ונשאר פתוח: בלי טיפול מיידי בכשל הכתיבה ההורדה תלויה.
  ({http.Client client, Future<void> cancelled}) openSource() {
    final cancelled = Completer<void>();
    final source = StreamController<List<int>>(
      onCancel: () {
        if (!cancelled.isCompleted) cancelled.complete();
      },
    )..add(Uint8List.sublistView(body, 0, 100));
    final client = MockClient.streaming(
      (request, _) async => http.StreamedResponse(
        source.stream,
        200,
        contentLength: body.length,
        headers: {'etag': '"e1"'},
      ),
    );
    addTearDown(client.close);
    return (client: client, cancelled: cancelled.future);
  }

  Future<void> run(http.Client client, {bool sha = true}) => downloadFile(
        client: client,
        url: 'https://example.test/asset.bin',
        destinationPath: target,
        expectedSize: body.length,
        stallTimeout: const Duration(hours: 1),
        maxAttempts: 2,
        calculateSha256: sha,
        statusError: (status) => StateError('HTTP $status'),
        sizeError: (actual, expected) => StateError('size $actual/$expected'),
      );

  void expectNothingLeft() {
    expect(File('$target.part').existsSync(), isFalse);
    expect(File('$target.resume').existsSync(), isFalse);
    expect(File(target).existsSync(), isFalse);
  }

  test(
      'disk full while the source is open: StorageFullException, no zone '
      'error, body cancelled, handle closed, no leftovers', () async {
    final source = openSource();
    final overrides = _FailingDiskOverrides('$target.part', fullErrno);
    final result = await _runCapturing(overrides, () => run(source.client));

    expect(result.uncaught, isEmpty);
    expect(
      result.error,
      isA<StorageFullException>()
          .having((e) => e.dir, 'dir', temp.path)
          .having((e) => e.cause, 'cause', isA<FileSystemException>())
          .having((e) => e.neededBytes, 'needed', isNull)
          .having((e) => e.freeBytes, 'free', isNull),
    );
    expect(isStorageFull(result.error), isTrue);
    expect(overrides.handles, isNotEmpty);
    expect(overrides.handles.every((h) => h.closed), isTrue);
    await source.cancelled.timeout(const Duration(seconds: 1));
    expectNothingLeft();
  });

  test('disk full opening the output cancels the unconsumed response body',
      () async {
    final source = openSource();
    final result = await _runCapturing(
      _FailingDiskOverrides('$target.part', fullErrno, failOpen: true),
      () => run(source.client),
    );
    expect(result.uncaught, isEmpty);
    expect(result.error, isA<StorageFullException>());
    await source.cancelled.timeout(const Duration(seconds: 1));
  });

  test(
      'a resumed download that hits a full disk keeps the bytes it already '
      'had, trimmed to what was fully written', () async {
    File('$target.part').writeAsBytesSync(Uint8List.sublistView(body, 0, 300));
    File('$target.resume').writeAsStringSync(jsonEncode({
      'url': 'https://example.test/asset.bin',
      'expectedSize': body.length,
      'etag': '"e1"',
      'total': body.length,
      'headers': {'etag': '"e1"'},
    }));
    final cancelled = Completer<void>();
    final source = StreamController<List<int>>(
      onCancel: () => cancelled.complete(),
    )..add(Uint8List.sublistView(body, 300, 400));
    final client = MockClient.streaming(
      (request, _) async => http.StreamedResponse(
        source.stream,
        206,
        contentLength: 700,
        headers: {'etag': '"e1"', 'content-range': 'bytes 300-999/1000'},
      ),
    );
    addTearDown(client.close);

    final result = await _runCapturing(
      _FailingDiskOverrides('$target.part', fullErrno),
      () => run(client, sha: false),
    );

    expect(result.uncaught, isEmpty);
    expect(result.error, isA<StorageFullException>());
    await cancelled.future.timeout(const Duration(seconds: 1));
    expect(File('$target.part').lengthSync(), 300);
    expect(File('$target.resume').existsSync(), isTrue);
    expect(File(target).existsSync(), isFalse);
  });

  test(
      'a non-storage write failure keeps its original error, is not retried '
      'and closes the handle', () async {
    final source = openSource();
    final result = await _runCapturing(
      _FailingDiskOverrides('$target.part', 1006),
      () => run(source.client),
    );

    expect(result.uncaught, isEmpty);
    expect(
      result.error,
      isA<FileSystemException>()
          .having((e) => e.osError?.errorCode, 'errno', 1006),
    );
    await source.cancelled.timeout(const Duration(seconds: 1));
    expectNothingLeft();
  });
}
