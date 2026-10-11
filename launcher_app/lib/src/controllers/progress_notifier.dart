import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dispose_guard.dart';

mixin ProgressNotifier on DisposeGuard {
  static const Duration interval = Duration(milliseconds: 100);

  final _ProgressSignal _progress = _ProgressSignal();
  Stopwatch? _since;
  Timer? _pending;

  Listenable get progress => _progress;

  void notifyProgress() {
    if (isDisposed) return;
    final since = _since;
    if (since == null || since.elapsed >= interval) {
      _pending?.cancel();
      _pending = null;
      _since = Stopwatch()..start();
      _progress.fire();
      return;
    }
    _pending ??= Timer(interval - since.elapsed, () {
      _pending = null;
      if (isDisposed) return;
      _since = Stopwatch()..start();
      _progress.fire();
    });
  }

  @override
  void dispose() {
    _pending?.cancel();
    _pending = null;
    _progress.dispose();
    super.dispose();
  }
}

class _ProgressSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}
