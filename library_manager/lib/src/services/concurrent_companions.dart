import 'dart:async';

import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

import 'library_update_applier.dart';

typedef CompanionsRun<T> =
    Future<T> Function(
      bool Function() isCancelled,
      void Function(LibraryApplyProgress progress) emit,
      Future<void> Function() dbOutcome,
    );

/// Runs the companion install beside the DB's final step. It stages freely but
/// its commit waits for [dbOutcome]; progress and errors are held until [join].
class ConcurrentCompanions<T> {
  ConcurrentCompanions({
    required CompanionsRun<T> run,
    this.onProgress,
    this.isCancelled,
  }) : _run = run;

  final CompanionsRun<T> _run;
  final void Function(LibraryApplyProgress progress)? onProgress;
  final bool Function()? isCancelled;

  final _db = Completer<bool>();
  Future<({T? value, Object? error, StackTrace? stack})>? _result;
  bool _forward = false;
  bool _abort = false;
  bool _finished = false;

  bool get started => _result != null;

  /// True once the DB phase failed; a cancellation after it is not a warning.
  bool get aborted => _abort;

  void start() {
    if (_result != null) return;
    _result =
        _run(() => _abort || (isCancelled?.call() ?? false), (progress) {
          if (_forward) onProgress?.call(progress);
        }, _dbOutcome).then<({T? value, Object? error, StackTrace? stack})>(
          (value) {
            _finished = true;
            return (value: value, error: null, stack: null);
          },
          onError: (Object error, StackTrace stack) {
            _finished = true;
            return (value: null, error: error, stack: stack);
          },
        );
  }

  /// Completes when the DB succeeded; throws the cancellation when it did not.
  Future<void> _dbOutcome() async {
    if (!await _db.future) throw const PatchDownloadCancelled();
  }

  /// The DB phase succeeded: lets the install commit, waits and rethrows.
  Future<T> join() async {
    _forward = true;
    if (!_db.isCompleted) _db.complete(true);
    if (!_finished) {
      onProgress?.call(
        const LibraryApplyProgress(
          stage: LibraryApplyStage.installingCompanions,
        ),
      );
    }
    final result = await _result!;
    if (result.error != null) {
      Error.throwWithStackTrace(result.error!, result.stack!);
    }
    return result.value as T;
  }

  /// The DB phase failed: stops the install before any commit and waits.
  Future<void> abandon() async {
    _abort = true;
    if (!_db.isCompleted) _db.complete(false);
    await _result;
  }
}
