import 'dart:async';
import 'dart:io';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticError, SemanticErrorKind;
import 'package:path/path.dart' as p;

/// [error] כ-[StorageFullException] כשהוא כשל "הכונן מלא"; אחרת כפי שהוא.
Object asStorageFailure(Object error, String path) => isStorageFull(error)
    ? StorageFullException(dir: p.dirname(path), cause: error)
    : error;

/// Records an async write failure at once and throws it from the next call;
/// a bare `IOSink` leaks a zone error and hangs `flush`.
class GuardedSink {
  GuardedSink(this._sink, this._path) {
    _done = _sink.done.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _failure ??= (error, stack);
      },
    );
  }

  final IOSink _sink;
  final String _path;
  late final Future<void> _done;
  (Object, StackTrace)? _failure;

  void _throwIfFailed() {
    final failure = _failure;
    if (failure == null) return;
    Error.throwWithStackTrace(asStorageFailure(failure.$1, _path), failure.$2);
  }

  void add(List<int> chunk) {
    _throwIfFailed();
    _sink.add(chunk);
  }

  Future<void> flush() async {
    _throwIfFailed();
    try {
      await Future.any([_sink.flush(), _done]);
    } catch (error, stack) {
      _failure ??= (error, stack);
    }
    _throwIfFailed();
  }

  /// סוגר ומחכה לכתיבה שנשארה; כשל שנרשם נזרק.
  Future<void> close() async {
    try {
      await _sink.close();
    } catch (error, stack) {
      _failure ??= (error, stack);
    }
    await _done;
    _throwIfFailed();
  }

  /// סגירה בנתיב שכבר נכשל: לא מחליפה את הכשל המקורי.
  Future<void> closeAfterFailure() async {
    try {
      await _sink.close();
    } on Object {
      // הכשל שכבר בדרך הוא מה שנזרק.
    }
    await _done;
  }
}

/// Rethrows [error] as [StorageFullException] when it is a full drive,
/// otherwise unchanged; [fallbackDir] names the volume when [error] names none.
Never throwStorageAware(Object error, StackTrace stack, String fallbackDir) {
  if (!isStorageFull(error)) Error.throwWithStackTrace(error, stack);
  final path = error is FileSystemException ? error.path : null;
  Error.throwWithStackTrace(
    StorageFullException(
      dir: path == null || path.isEmpty ? fallbackDir : p.dirname(path),
      cause: error,
    ),
    stack,
  );
}

/// The native engine reports a full drive as `InsufficientDiskSpace`, or as an
/// `Internal` error whose text carries the OS code (`os error 112`).
StorageFullException? storageFullFromEngine(Object error, String dir) {
  if (error is! SemanticError) return null;
  if (error.kind == SemanticErrorKind.insufficientDiskSpace) {
    return StorageFullException(dir: dir, cause: error);
  }
  final code = RegExp(r'os error (\d+)').firstMatch(error.message)?.group(1);
  final errno = int.tryParse(code ?? '');
  return errno != null && isStorageFullErrno(errno)
      ? StorageFullException(dir: dir, cause: error)
      : null;
}
