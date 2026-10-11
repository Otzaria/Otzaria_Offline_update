import 'dart:async';

class DialogQueue {
  DialogQueue({
    required this.isActive,
    required this.isBlocked,
    this.pollInterval = const Duration(milliseconds: 500),
    this.maxWaits = 120,
  });

  final bool Function() isActive;
  final bool Function() isBlocked;
  final Duration pollInterval;
  final int maxWaits;

  Future<void> _tail = Future<void>.value();
  Timer? _pauseTimer;
  Completer<void>? _pauseDone;

  Future<T?> run<T>(Future<T> Function() body, {bool forever = false}) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous;
      if (!await _waitUntilClear(forever: forever)) return null;
      return await body();
    } finally {
      done.complete();
    }
  }

  void dispose() {
    _pauseTimer?.cancel();
    if (_pauseDone case final done? when !done.isCompleted) done.complete();
  }

  Future<bool> _waitUntilClear({required bool forever}) async {
    var waits = 0;
    while (isActive() && isBlocked()) {
      if (!forever && ++waits > maxWaits) return false;
      await _pause(pollInterval);
    }
    return isActive();
  }

  Future<void> _pause(Duration duration) {
    final done = _pauseDone = Completer<void>();
    _pauseTimer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }
}
