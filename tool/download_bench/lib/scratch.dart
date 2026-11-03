// Scratch directories owned by one bench run: canonical paths, an ownership
// marker, and a cleanup that only ever touches what the run itself created.
import 'dart:io';

class BenchFailure implements Exception {
  BenchFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Written into every directory this tool created or adopted while empty.
const ownedMarker = '.download_bench_owned';

final _internalName = RegExp(
  r'(\.(lock|resume|segments|joining|tmp|bench-copy|partial|probe|hdr)'
  r'|\.seg-?\d+|\.part-\d+(\.resume)?|\.[0-9a-f]{12})$',
  caseSensitive: false,
);
final _deviceName = RegExp(
  r'^(con|prn|aux|nul|conin\$|conout\$|clock\$|com[0-9¹²³]|lpt[0-9¹²³])$',
  caseSensitive: false,
);

/// Throws unless [name] is one plain, portable file name that cannot collide
/// with the tool's own files. Applied on every OS: the drive may travel.
String checkAssetName(String name) {
  void bad(String why) => throw BenchFailure("bad asset name '$name': $why");
  if (name.isEmpty || name == '.' || name == '..') bad('empty or dot');
  if (name.length > 200) bad('too long');
  if (name.contains(RegExp(r'[\\/:<>"|?*\x00-\x1f\x7f]'))) {
    bad('separator, stream or forbidden character');
  }
  if (RegExp(r'%[0-9a-fA-F]{2}').hasMatch(name)) bad('encoded characters');
  if (name.endsWith('.') || name.endsWith(' ') || name.startsWith(' ')) {
    bad('leading space or trailing dot/space');
  }
  if (name.contains('~')) bad('8.3 short-name form');
  if (_deviceName.hasMatch(name.split('.').first.trimRight())) {
    bad('reserved device name');
  }
  if (name.toLowerCase() == ownedMarker || _internalName.hasMatch(name)) {
    bad("collides with the tool's own files");
  }
  return name;
}

/// The checked file name of a download URL (its decoded last path segment).
String assetNameOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.pathSegments.isEmpty) {
    throw BenchFailure("no file name in '$url'");
  }
  return checkAssetName(uri.pathSegments.last);
}

String get _sep => Platform.pathSeparator;
String _key(String p) => Platform.isWindows ? p.toLowerCase() : p;
bool _isLock(String name) => name.toLowerCase().endsWith('.lock');
bool _isRoot(String p) => Directory(p).parent.path == Directory(p).path;

String _normalize(String raw) {
  var p = Directory(raw).absolute.uri.normalizePath().toFilePath();
  while (p.length > 1 && !_isRoot(p) && (p.endsWith('/') || p.endsWith(r'\'))) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Absolute, `..`-free path with symlink/junction ancestors rejected and short
/// names expanded. Refuses a drive root, the home directory and its parents.
String canonicalScratchPath(String raw, {String? home}) {
  if (raw.trim().isEmpty) throw BenchFailure('empty path');
  if (raw.split(RegExp(r'[\\/]')).contains('..')) {
    throw BenchFailure("'..' is not allowed in '$raw'");
  }
  final abs = _normalize(raw);
  if (_isRoot(abs)) throw BenchFailure("refusing drive root '$abs'");
  String? existing;
  for (var cur = abs; ; cur = Directory(cur).parent.path) {
    final type = FileSystemEntity.typeSync(cur, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw BenchFailure("'$cur' is a link; use a direct path");
    }
    if (type != FileSystemEntityType.notFound) {
      existing ??= cur;
    }
    if (_isRoot(cur)) break;
  }
  if (existing == null) throw BenchFailure("no existing ancestor of '$abs'");
  final resolved = Directory(existing).resolveSymbolicLinksSync();
  final rest = abs.length > existing.length
      ? abs.substring(existing.length).replaceFirst(RegExp(r'^[\\/]+'), '')
      : '';
  final canon = rest.isEmpty
      ? resolved
      : resolved.endsWith(_sep)
      ? '$resolved$rest'
      : '$resolved$_sep$rest';
  final h =
      home ??
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'];
  if (h != null && h.isNotEmpty) {
    var hp = _normalize(h);
    if (Directory(hp).existsSync()) {
      hp = Directory(hp).resolveSymbolicLinksSync();
    }
    final c = _key(canon), k = _key(hp);
    if (c == k || k.startsWith(c.endsWith(_sep) ? c : '$c$_sep')) {
      throw BenchFailure("refusing home directory or its parent '$canon'");
    }
  }
  return canon;
}

/// A directory this run may write into and clean: only files created after
/// [open] are deleted, never `.lock` files (AGENTS.md 5.2) or subdirectories.
class OwnedDir {
  OwnedDir._(this.path, this._before);
  final String path;
  final Set<String> _before;

  /// Creates [raw] (marker inside) or adopts it when it is empty or already
  /// carries the marker; anything else is somebody else's directory.
  static OwnedDir open(String raw) {
    final path = canonicalScratchPath(raw);
    final dir = Directory(path);
    final marker = File('$path$_sep$ownedMarker');
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.file) {
      throw BenchFailure("'$path' is a file");
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      marker.writeAsStringSync('created by download_bench pid $pid\n');
    } else if (!marker.existsSync()) {
      if (dir.listSync(followLinks: false).isNotEmpty) {
        throw BenchFailure(
          "'$path' is not empty and was not created by download_bench "
          '(no $ownedMarker); refusing to write into it',
        );
      }
      marker.writeAsStringSync('created by download_bench pid $pid\n');
    }
    return OwnedDir._(path, _names(dir));
  }

  static Set<String> _names(Directory d) => {
    for (final e in d.listSync(followLinks: false))
      _key(e.uri.pathSegments.where((s) => s.isNotEmpty).last),
  };

  /// The path of [name] inside this directory, after [checkAssetName] and a
  /// check that the result is a direct child that is not a link or directory.
  String file(String name) => derived(name, '');

  /// [file] of `name + suffix`, for the tool's own temporary names.
  String derived(String name, String suffix) {
    checkAssetName(name);
    if (suffix.contains(RegExp(r'[\\/:<>"|?*\x00-\x1f\x7f]')) ||
        suffix.endsWith('.') ||
        suffix.endsWith(' ') ||
        name.length + suffix.length > 255) {
      throw BenchFailure("bad temporary suffix '$suffix'");
    }
    final full = '$path$_sep$name$suffix';
    if (_key(_normalize(full)) != _key(full)) {
      throw BenchFailure("'$name' does not resolve inside '$path'");
    }
    final type = FileSystemEntity.typeSync(full, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.directory) {
      throw BenchFailure("'$name' is a ${type.toString().toLowerCase()}");
    }
    return full;
  }

  bool _mine(String name) =>
      !_before.contains(_key(name)) &&
      _key(name) != ownedMarker &&
      !_isLock(name);

  /// Deletes files this run created that are not in [keep] (sidecars, partial
  /// files). Throws when one cannot be deleted.
  Duration cleanup({required Set<String> keep}) {
    final sw = Stopwatch()..start();
    final failed = <String>[];
    for (final e in Directory(path).listSync(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is! File || keep.contains(name) || !_mine(name)) continue;
      try {
        e.deleteSync();
      } on FileSystemException catch (x) {
        failed.add('$name (${x.message})');
      }
    }
    if (failed.isNotEmpty) {
      throw BenchFailure('cleanup could not delete: ${failed.join(', ')}');
    }
    return sw.elapsed;
  }

  /// Failure path: removes what the run created plus [outputs] (even if they
  /// pre-existed); keeps locks. Returns names that could not be deleted.
  List<String> discard({Set<String> outputs = const {}}) {
    final failed = <String>[];
    final dir = Directory(path);
    if (!dir.existsSync()) return failed;
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is! File || name == ownedMarker || _isLock(name)) continue;
      if (!_mine(name) && !outputs.contains(name)) continue;
      try {
        e.deleteSync();
      } on FileSystemException {
        failed.add(name);
      }
    }
    return failed;
  }

  /// Removes a whole scratch root created by this tool (marker required), for
  /// use after the process that held its locks has exited.
  static void removeTree(String raw) {
    final path = canonicalScratchPath(raw);
    if (!File('$path$_sep$ownedMarker').existsSync()) {
      throw BenchFailure("'$path' has no $ownedMarker; refusing to delete it");
    }
    for (final e in Directory(
      path,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is Link) throw BenchFailure("'${e.path}' is a link; not deleting");
    }
    Directory(path).deleteSync(recursive: true);
  }
}
