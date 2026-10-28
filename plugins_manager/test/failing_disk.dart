import 'dart:convert';
import 'dart:io';

/// כל כתיבה לקובץ שנתיבו מקיים [matches] נכשלת אסינכרונית ב-[errno], כמו
/// כונן מלא. שאר הפעולות עוברות לקובץ האמיתי.
final class FailingDiskOverrides extends IOOverrides {
  FailingDiskOverrides(this.matches, {int? errno})
      : errno = errno ?? _diskFullErrno;

  final bool Function(String path) matches;
  final int errno;
  final failedPaths = <String>[];

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return matches(path) ? _FailingFile(file, errno, failedPaths) : file;
  }
}

class _FailingFile implements File {
  _FailingFile(this._real, this.errno, this.failed);

  final File _real;
  final int errno;
  final List<String> failed;

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
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await Future<void>.delayed(Duration.zero);
    failed.add(path);
    throw FileSystemException(
      'write failed',
      path,
      OSError('simulated', errno),
    );
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    _real.writeAsBytesSync(
      const [],
      mode: mode == FileMode.append ? FileMode.append : FileMode.write,
    );
    return _FailingHandle(path, errno, failed);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FailingHandle implements RandomAccessFile {
  _FailingHandle(this.path, this.errno, this.failed);

  @override
  final String path;
  final int errno;
  final List<String> failed;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) =>
      Future.delayed(Duration.zero, () {
        failed.add(path);
        throw FileSystemException(
          'write failed',
          path,
          OSError('simulated', errno),
        );
      });

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// יצירת תיקייה שנתיבה מקיים [matches] נכשלת ב-[errno].
final class FailingMkdirOverrides extends IOOverrides {
  FailingMkdirOverrides(this.matches, {required this.errno});

  final bool Function(String path) matches;
  final int errno;

  @override
  Directory createDirectory(String path) {
    final real = super.createDirectory(path);
    return matches(path) ? _FailingDirectory(real, errno) : real;
  }
}

class _FailingDirectory implements Directory {
  _FailingDirectory(this._real, this.errno);

  final Directory _real;
  final int errno;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => _real.exists();

  @override
  Future<Directory> create({bool recursive = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    throw FileSystemException('mkdir', path, OSError('simulated', errno));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final int _diskFullErrno = Platform.isWindows ? 112 : 28;
