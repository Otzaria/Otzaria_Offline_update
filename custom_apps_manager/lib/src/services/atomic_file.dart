import 'dart:io';

int _sequence = 0;

String uniqueTempPath(String path) =>
    '$path.$pid-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}.tmp';

String Function(String path) atomicTempPathFor = uniqueTempPath;

Future<void> Function(String from, String to) replaceFile =
    (from, to) => File(from).rename(to);

bool isAtomicTempNameOf(String fileName, String target) {
  final name = fileName.toLowerCase();
  return name.startsWith('${target.toLowerCase()}.') && name.endsWith('.tmp');
}

Future<void> writeStringAtomically(String path, String contents) async {
  final temp = File(atomicTempPathFor(path));
  try {
    await temp.writeAsString(contents, flush: true);
    await temp.rename(path);
  } catch (_) {
    await _deleteQuietly(temp);
    rethrow;
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    return;
  }
}
