// מוריד אמיתי של seforim_library_updater שכתיבתו נכשלת (IOOverrides), כדי
// שהבדיקות יעבדו עם החריג שהמנוע באמת מייצר ולא עם טיפוס נוח.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

final diskFullErrno = Platform.isWindows ? 112 : 28;
final accessDeniedErrno = Platform.isWindows ? 5 : 13;

/// כל כתיבה אל [target] נכשלת אסינכרונית עם [errno], אחרי שהקריאה חזרה.
final class _FailingDiskOverrides extends IOOverrides {
  _FailingDiskOverrides(this.target, this.errno);

  final String target;
  final int errno;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path == target ? _FailingWriteFile(file, errno) : file;
  }
}

class _FailingWriteFile implements File {
  _FailingWriteFile(this._real, this.errno);

  final File _real;
  final int errno;

  @override
  String get path => _real.path;
  @override
  bool existsSync() => _real.existsSync();
  @override
  int lengthSync() => _real.lengthSync();
  @override
  void deleteSync({bool recursive = false}) => _real.deleteSync();

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    _real.writeAsBytesSync(const []);
    return _FailingRandomAccessFile(path, errno);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FailingRandomAccessFile implements RandomAccessFile {
  _FailingRandomAccessFile(this.path, this.errno);

  @override
  final String path;
  final int errno;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) =>
      Future.delayed(
        Duration.zero,
        () => throw FileSystemException(
          'writeFrom failed',
          path,
          OSError('', errno),
        ),
      );

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// מוריד אמיתי שכתיבתו נכשלת ב-[errno], וה-error שהוא זורק.
Future<Object> realDownloadFailure(Directory dir, int errno) async {
  final dest = '${dir.path}${Platform.pathSeparator}vectors.seg';
  final body = Uint8List.fromList(List.generate(1000, (i) => i % 251));
  final source = StreamController<List<int>>()
    ..add(Uint8List.sublistView(body, 0, 100));
  final downloader = PatchDownloader(
    networkRetryDelays: const [],
    stallTimeout: const Duration(hours: 1),
    httpClient: MockClient.streaming(
      (request, _) async => http.StreamedResponse(
        source.stream,
        200,
        contentLength: body.length,
        headers: {'etag': '"e1"'},
      ),
    ),
    decompress: (_) async => null,
  );
  final outcome = Completer<Object>();
  unawaited(runZonedGuarded(
    () => IOOverrides.runWithIOOverrides(
      () => downloader.downloadToFile(
        url: 'https://x/vectors.seg',
        destPath: dest,
        expectedSize: body.length,
        expectedSha256: sha256.convert(body).toString(),
        resumeToken: 'token',
      ),
      _FailingDiskOverrides(dest, errno),
    ).then(
      (_) => outcome.completeError(StateError('the download should fail')),
      onError: (Object error) => outcome.complete(error),
    ),
    (error, _) {},
  ));
  return outcome.future.timeout(const Duration(seconds: 10));
}
