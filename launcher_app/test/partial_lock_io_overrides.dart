import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:launcher_app/src/services/app_paths.dart';
import 'package:path/path.dart' as p;

Directory _realDirectory(String path) => Zone.root.run(() => Directory(path));
File _realFile(String path) => Zone.root.run(() => File(path));

/// כונן שחלק מתיקיותיו נעולות: [lockedDirs] (יחסית ל-OtzariaData, `''` = השורש)
/// נכשלות בכתיבה, ו-[uncreatable] אינן ניתנות ליצירה.
final class PartialLockIOOverrides extends IOOverrides {
  PartialLockIOOverrides({
    required this.driveRoot,
    this.lockedDirs = const {},
    this.uncreatable = const {},
    this.partialWrite = false,
    Map<String, int> transientFailures = const {},
  }) : _transient = {...transientFailures};

  /// כמה כשלי כתיבה חולפים נשארו לכל תיקייה, לפני שהכתיבה מצליחה.
  final Map<String, int> _transient;

  /// כתיבת קובץ הבדיקה במקום נעול יוצרת אותו ואז נכשלת (דיסק מלא).
  final bool partialWrite;

  /// התיקיות (יחסית) שנוצר בהן קובץ בדיקה, לפי הסדר.
  final List<String> probed = [];

  final String driveRoot;
  final Set<String> lockedDirs;
  final Set<String> uncreatable;

  String get _dataDir =>
      p.join(p.dirname(Platform.resolvedExecutable), AppPaths.dirName);

  bool _onDrive(String path) => path == _dataDir || p.isWithin(_dataDir, path);

  String _rel(String path) =>
      path == _dataDir ? '' : p.relative(path, from: _dataDir);

  String _mapped(String path) =>
      path == _dataDir ? driveRoot : p.join(driveRoot, _rel(path));

  @override
  Directory createDirectory(String path) {
    if (!_onDrive(path)) return _realDirectory(path);
    if (uncreatable.contains(_rel(path))) return _DeniedDirectory(path);
    return _realDirectory(_mapped(path));
  }

  @override
  File createFile(String path) {
    if (!_onDrive(path)) return _realFile(path);
    if (p.basename(path).startsWith('.write-test')) {
      final dir = _rel(p.dirname(path));
      probed.add(dir);
      final left = _transient[dir] ?? 0;
      if (left > 0) {
        _transient[dir] = left - 1;
        return _DeniedFile(path);
      }
      if (lockedDirs.contains(dir)) {
        return partialWrite
            ? _PartialFile(_realFile(_mapped(path)))
            : _DeniedFile(path);
      }
    }
    return _realFile(_mapped(path));
  }
}

class _PartialFile implements File {
  _PartialFile(this._real);

  final File _real;

  @override
  String get path => _real.path;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await _real.create();
    throw FileSystemException('No space left on device', path);
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _real.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeniedDirectory implements Directory {
  _DeniedDirectory(this.path);

  @override
  final String path;

  @override
  Future<Directory> create({bool recursive = false}) =>
      Future.error(FileSystemException('Access is denied', path));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeniedFile implements File {
  _DeniedFile(this.path);

  @override
  final String path;

  @override
  Future<bool> exists() async => false;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      Future.error(FileSystemException('Access is denied', path));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// תיקיות הנתונים שהמשגר כותב אליהן במחשב לא-מקוון, יחסית ל-OtzariaData.
final List<String> dataFolders = [
  'logs',
  p.join('reports', 'outbox'),
  p.join('reports', 'launcher'),
  'search-feedback',
];
