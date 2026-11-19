import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:ffi/ffi.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'storage_guard.dart';

typedef CompanionTarEntry = ({String path, int offset, int size});

void checkCompanionCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() == true) throw const PatchDownloadCancelled();
}

String _resolvedPath(String path) {
  final absolute = p.normalize(p.absolute(path));
  if (FileSystemEntity.typeSync(absolute) != FileSystemEntityType.notFound) {
    return File(absolute).resolveSymbolicLinksSync();
  }
  final parent = p.dirname(absolute);
  return parent == absolute
      ? absolute
      : p.join(_resolvedPath(parent), p.basename(absolute));
}

void guardCompanionSource(String source, Iterable<String> ownedPaths) {
  final resolved = _resolvedPath(source);
  for (final path in ownedPaths) {
    final owned = _resolvedPath(path);
    if (p.equals(resolved, owned) ||
        p.isWithin(owned, resolved) ||
        (FileSystemEntity.typeSync(source) != FileSystemEntityType.notFound &&
            FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound &&
            FileSystemEntity.identicalSync(resolved, owned))) {
      throw ArgumentError(
        AppL10n.strings.libraryDomain.companionExtractionFailed(
          p.basename(source),
        ),
      );
    }
  }
}

Future<int> copyCompanionFile({
  required File source,
  required String destination,
  required int maxOutputBytes,
  required int expectedSize,
  String? expectedSha256,
  int start = 0,
  int? end,
  bool Function()? isCancelled,
  void Function(int bytesWritten)? onProgress,
}) async {
  checkCompanionCancelled(isCancelled);
  final hasher = expectedSha256 == null ? null : Sha256Stream();
  RandomAccessFile? output;
  var opened = false;
  var completed = false;
  var written = 0;
  final clock = Stopwatch()..start();
  var lastProgress = 0;
  var reportedWrite = false;
  void report(int count) {
    if (onProgress == null) return;
    final now = clock.elapsedMilliseconds;
    if (count != 0 &&
        count != expectedSize &&
        reportedWrite &&
        now - lastProgress < 100) {
      return;
    }
    if (count > 0) reportedWrite = true;
    lastProgress = now;
    onProgress(count);
  }

  try {
    if (expectedSize < 0 || expectedSize > maxOutputBytes) {
      throw FormatException(
        AppL10n.strings.libraryDomain.localFileTooLarge(
          maxOutputBytes,
          destination,
        ),
      );
    }
    report(0);
    checkCompanionCancelled(isCancelled);
    output = await File(destination).open(mode: FileMode.write);
    opened = true;
    await for (final chunk in source.openRead(start, end)) {
      checkCompanionCancelled(isCancelled);
      if (chunk.length > expectedSize - written) {
        throw FormatException(
          AppL10n.strings.libraryDomain.localFileTooLarge(
            expectedSize,
            destination,
          ),
        );
      }
      await output.writeFrom(chunk);
      hasher?.add(chunk);
      written += chunk.length;
      report(written);
      checkCompanionCancelled(isCancelled);
    }
    await output.flush();
    await output.close();
    output = null;
    checkCompanionCancelled(isCancelled);
    final actualSize = await File(destination).length();
    if (written != expectedSize || actualSize != written) {
      throw FormatException(
        AppL10n.strings.libraryDomain.localFileSizeMismatch(
          expectedSize,
          actualSize,
          destination,
        ),
      );
    }
    final digest = hasher?.close();
    if (expectedSha256 != null &&
        digest?.toLowerCase() != expectedSha256.toLowerCase()) {
      throw FormatException(
        AppL10n.strings.libraryDomain.checksumMismatchDetailed(
          p.basename(source.path),
          expectedSha256,
          digest ?? '',
        ),
      );
    }
    checkCompanionCancelled(isCancelled);
    completed = true;
    return written;
  } catch (error, stack) {
    Error.throwWithStackTrace(asStorageFailure(error, destination), stack);
  } finally {
    try {
      await output?.close();
    } catch (_) {}
    hasher?.dispose();
    if (opened && !completed) {
      try {
        await File(destination).delete();
      } on FileSystemException {
        // Preserve the failure that stopped the write.
      }
    }
  }
}

typedef CompanionCopyJob = ({
  File source,
  String destination,
  int expectedSize,
  int start,
  int? end,
});

const companionCopyConcurrency = 8;

/// Dedupe key for a path on this platform's filesystem.
String companionPathKey(String path) =>
    Platform.isLinux ? path : path.toLowerCase();

/// Copies [jobs], [concurrency] files at once; returns after every file is
/// closed, rethrowing the first failure once the running ones cleaned up.
Future<int> copyCompanionFiles(
  List<CompanionCopyJob> jobs, {
  required int maxOutputBytes,
  int concurrency = companionCopyConcurrency,
  bool Function()? isCancelled,
  void Function(int bytesWritten)? onProgress,
}) async {
  RangeError.checkValueInInterval(concurrency, 1, 1 << 16, 'concurrency');
  final destinations = <String>{};
  for (final job in jobs) {
    if (!destinations.add(companionPathKey(p.normalize(job.destination)))) {
      throw ArgumentError.value(
        job.destination,
        'jobs',
        'duplicate destination',
      );
    }
  }
  final progress = List<int>.filled(jobs.length, 0);
  var reserved = 0;
  var total = 0;
  var next = 0;
  Object? failure;
  StackTrace? failureStack;
  final clock = Stopwatch()..start();
  var lastReport = -1000;
  bool stopped() => failure != null || (isCancelled?.call() ?? false);

  Future<void> worker() async {
    while (failure == null) {
      final index = next++;
      if (index >= jobs.length) return;
      final job = jobs[index];
      try {
        if (job.expectedSize < 0 ||
            job.expectedSize > maxOutputBytes - reserved) {
          throw FormatException(
            AppL10n.strings.libraryDomain.localFileTooLarge(
              maxOutputBytes,
              job.destination,
            ),
          );
        }
        reserved += job.expectedSize;
        await File(job.destination).parent.create(recursive: true);
        await copyCompanionFile(
          source: job.source,
          destination: job.destination,
          start: job.start,
          end: job.end,
          expectedSize: job.expectedSize,
          maxOutputBytes: maxOutputBytes,
          isCancelled: stopped,
          onProgress: (bytes) {
            total += bytes - progress[index];
            progress[index] = bytes;
            final now = clock.elapsedMilliseconds;
            if (now - lastReport >= 100) {
              lastReport = now;
              onProgress?.call(total);
            }
          },
        );
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
        return;
      }
    }
  }

  await Future.wait([
    for (var i = 0; i < concurrency && i < jobs.length; i++) worker(),
  ]);
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  checkCompanionCancelled(isCancelled);
  onProgress?.call(total);
  return total;
}

Future<List<CompanionTarEntry>> readCompanionTar(
  String tarPath, {
  required String rootName,
  required Set<String> ignoredNames,
  required int maxOutputBytes,
  bool Function()? isCancelled,
}) async {
  checkCompanionCancelled(isCancelled);
  final flag = calloc<Uint8>();
  final address = flag.address;
  final language = AppL10n.language;
  Object? callbackError;
  StackTrace? callbackStack;
  final poll = isCancelled == null
      ? null
      : Timer.periodic(const Duration(milliseconds: 50), (_) {
          try {
            if (isCancelled()) flag.value = 1;
          } catch (error, stack) {
            callbackError ??= error;
            callbackStack ??= stack;
            flag.value = 1;
          }
        });
  try {
    final entries = await _runTarRead(
      tarPath,
      rootName,
      ignoredNames,
      maxOutputBytes,
      address,
      language,
    );
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    checkCompanionCancelled(isCancelled);
    return entries;
  } catch (_) {
    if (callbackError != null) {
      Error.throwWithStackTrace(callbackError!, callbackStack!);
    }
    rethrow;
  } finally {
    poll?.cancel();
    calloc.free(flag);
  }
}

Future<List<CompanionTarEntry>> _runTarRead(
  String tarPath,
  String rootName,
  Set<String> ignoredNames,
  int limit,
  int cancelAddress,
  AppLanguage language,
) => Isolate.run(
  () =>
      _readTar(tarPath, rootName, ignoredNames, limit, cancelAddress, language),
);

List<CompanionTarEntry> _readTar(
  String tarPath,
  String rootName,
  Set<String> ignoredNames,
  int limit,
  int cancelAddress,
  AppLanguage language,
) {
  AppL10n.use(language);
  final input = _CancellableTarInput(tarPath, cancelAddress);
  final decoder = TarDecoder();
  final entries = <CompanionTarEntry>[];
  final names = <String>{};
  var size = 0;
  var count = 0;
  Never invalid() => throw FormatException(
    AppL10n.strings.libraryDomain.companionExtractionFailed(rootName),
  );
  try {
    decoder.decodeStream(
      input,
      verify: true,
      callback: (entry) {
        input.checkCancelled();
        if (++count > 10000 ||
            entry.name.length > 4096 ||
            entry.isSymbolicLink ||
            (entry.isFile &&
                !{'', '\u0000', '0'}.contains(decoder.files.last.typeFlag))) {
          invalid();
        }
        final name = p.posix.normalize(entry.name.replaceAll('\\', '/'));
        if (name == '.' && !entry.isFile) return;
        if (p.posix.isAbsolute(name) ||
            p.windows.isAbsolute(name) ||
            name.contains(':') ||
            (name != rootName && !p.posix.isWithin(rootName, name))) {
          invalid();
        }
        if (!entry.isFile || ignoredNames.contains(p.posix.basename(name))) {
          return;
        }
        final raw = entry.rawContent?.getStream(decompress: false);
        final declared = decoder.files.last.fileSize;
        if (raw is! InputFileStream ||
            raw.length != declared ||
            !names.add(companionPathKey(name)) ||
            declared > limit - size) {
          invalid();
        }
        size += declared;
        entries.add((
          path: name,
          offset: raw.fileOffset + raw.position,
          size: declared,
        ));
      },
    );
    if (entries.isEmpty || input.position > input.fileLength) invalid();
    return entries;
  } finally {
    input.closeSync();
  }
}

class _CancellableTarInput extends InputFileStream {
  _CancellableTarInput(this.sourcePath, int address)
    : flag = Pointer<Uint8>.fromAddress(address),
      super.withFileHandle(FileHandle(sourcePath));

  final String sourcePath;
  final Pointer<Uint8> flag;

  void checkCancelled() {
    if (flag.value != 0) throw const PatchDownloadCancelled();
  }

  @override
  InputStream readBytes(int count) {
    checkCancelled();
    if (count < 0 || count > length) {
      throw FormatException(
        AppL10n.strings.libraryDomain.localFileSizeMismatch(
          count,
          length,
          sourcePath,
        ),
      );
    }
    return super.readBytes(count);
  }

  @override
  InputStream peekBytes(int count, {int offset = 0}) {
    checkCancelled();
    return super.peekBytes(count, offset: offset);
  }
}

String companionBackupPath(String target) => '$target.offline-backup';

FileSystemEntity _entity(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.directory
    ? Directory(path)
    : File(path);

Future<void> _removeEntity(String path) async {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    await _entity(path).delete(recursive: true);
  }
}

Future<void> recoverCompanionInstall(String target, List<String> paths) async {
  final backup = Directory(companionBackupPath(target));
  if (!backup.existsSync()) return;
  if (File(p.join(backup.path, 'committed')).existsSync()) {
    await _cleanCommittedBackup(backup);
    return;
  }
  final stateFile = File(p.join(backup.path, 'state.json'));
  if (!stateFile.existsSync() &&
      backup.listSync().every(
        (entry) => p.basename(entry.path) == 'state.json.tmp',
      )) {
    await backup.delete(recursive: true);
    return;
  }
  final state = jsonDecode(stateFile.readAsStringSync());
  if (state is! List ||
      state.length != paths.length ||
      state.any((entry) => entry is! bool)) {
    throw StateError(
      AppL10n.strings.libraryDomain.companionExtractionFailed(
        p.basename(target),
      ),
    );
  }
  for (var i = paths.length - 1; i >= 0; i--) {
    final saved = p.join(backup.path, '$i');
    if (FileSystemEntity.typeSync(saved, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await _removeEntity(paths[i]);
      _entity(saved).renameSync(paths[i]);
    } else if (state[i] == false) {
      await _removeEntity(paths[i]);
    }
  }
  await backup.delete(recursive: true);
}

Future<void> _cleanCommittedBackup(Directory backup) async {
  for (final entry in backup.listSync(followLinks: false)) {
    if (p.basename(entry.path) != 'committed') {
      await entry.delete(recursive: true);
    }
  }
  // Keep the commit decision until every old file and the journal are gone.
  await File(p.join(backup.path, 'committed')).delete();
  await backup.delete();
}

/// Files and their markers move together; the journal recovers an interrupted swap.
Future<void> commitCompanionInstall(
  String target,
  Map<String, String?> replacements,
) async {
  final paths = replacements.keys.toList();
  final backup = Directory(companionBackupPath(target));
  final existed = [
    for (final path in paths)
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound,
  ];
  backup.createSync();
  var prepared = false;
  try {
    File(p.join(backup.path, 'state.json.tmp'))
      ..writeAsStringSync(jsonEncode(existed), flush: true)
      ..renameSync(p.join(backup.path, 'state.json'));
    prepared = true;
    for (var i = 0; i < paths.length; i++) {
      if (existed[i]) _entity(paths[i]).renameSync(p.join(backup.path, '$i'));
    }
    for (final entry in replacements.entries) {
      if (entry.value != null) _entity(entry.value!).renameSync(entry.key);
    }
    File(p.join(backup.path, 'committed')).writeAsStringSync('1', flush: true);
  } catch (_) {
    try {
      if (prepared) {
        await _removeEntity(p.join(backup.path, 'committed'));
        await recoverCompanionInstall(target, paths);
      } else {
        await backup.delete(recursive: true);
      }
    } catch (_) {
      // Leave the journal and old content for the next recovery attempt.
    }
    rethrow;
  }
  try {
    await _cleanCommittedBackup(backup);
  } on FileSystemException {
    // The committed marker makes a later cleanup safe.
  }
}
