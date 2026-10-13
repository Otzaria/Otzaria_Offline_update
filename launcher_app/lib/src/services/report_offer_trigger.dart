import 'dart:async';

class ReportOfferTrigger {
  ReportOfferTrigger(this._offer, {bool Function()? isBusy})
      : _isBusy = isBusy ?? (() => false);

  final Future<void> Function() _offer;
  final bool Function() _isBusy;
  bool _wasRunning = false;
  bool _active = false;
  bool _again = false;
  bool _deferred = false;

  void onRunningState({required bool running}) {
    final closed = _wasRunning && !running;
    _wasRunning = running;
    if (closed) unawaited(request());
  }

  void defer() => _deferred = true;

  void resume() {
    if (_deferred && !_isBusy()) unawaited(request());
  }

  Future<void> request() async {
    if (_isBusy()) {
      _deferred = true;
      return;
    }
    _deferred = false;
    if (_active) {
      _again = true;
      return;
    }
    _active = true;
    try {
      do {
        _again = false;
        await _offer();
      } while (_again);
    } finally {
      _active = false;
    }
  }
}
