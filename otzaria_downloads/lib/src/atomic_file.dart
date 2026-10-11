import 'dart:io';

var _atomicWriteSequence = 0;
final _atomicWriteQueues = <String, Future<void>>{};
const _transientWindowsRenameErrors = {5, 32, 33};
const _renameAttempts = 5;

String uniqueTempPath(String path) =>
    '$path.$pid-${DateTime.now().microsecondsSinceEpoch}-${_atomicWriteSequence++}.tmp';

String Function(String path) atomicTempPathFor = uniqueTempPath;

bool isAtomicTempNameOf(String fileName, String target) {
  final name = fileName.toLowerCase();
  return name.startsWith('${target.toLowerCase()}.') && name.endsWith('.tmp');
}

Future<void> writeStringAtomically(String path, String contents) {
  final key = _atomicWriteKey(path);
  final previous = _atomicWriteQueues[key] ?? Future<void>.value();
  final result = previous.then((_) => _writeStringAtomically(path, contents));
  final tail = result.then<void>((_) {}, onError: (Object _) {});
  _atomicWriteQueues[key] = tail;
  tail.whenComplete(() {
    if (identical(_atomicWriteQueues[key], tail)) {
      _atomicWriteQueues.remove(key);
    }
  });
  return result;
}

String _atomicWriteKey(String path) {
  final absolute = File(path).absolute.path;
  return Platform.isWindows
      ? absolute.replaceAll('/', r'\').toLowerCase()
      : absolute;
}

Future<void> _writeStringAtomically(String path, String contents) async {
  final temp = File(atomicTempPathFor(path));
  try {
    await temp.writeAsString(contents, flush: true);
    await renameRetryingTransient(() => temp.rename(path));
  } catch (_) {
    try {
      await temp.delete();
    } catch (_) {}
    rethrow;
  }
}

Future<void> renameRetryingTransient(
  Future<void> Function() rename, {
  bool? isWindows,
}) async {
  final windows = isWindows ?? Platform.isWindows;
  for (var attempt = 1;; attempt++) {
    try {
      await rename();
      return;
    } on FileSystemException catch (e) {
      final transient = windows &&
          _transientWindowsRenameErrors.contains(e.osError?.errorCode);
      if (!transient || attempt >= _renameAttempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 25 * attempt));
    }
  }
}
