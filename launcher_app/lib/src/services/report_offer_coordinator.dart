import 'dart:async';

import 'report_offer_trigger.dart';

class ReportOfferCoordinator {
  ReportOfferCoordinator({
    required this.isTaskRunning,
    required this.isActive,
    required this.prepare,
    required this.runDialog,
    required this.perform,
    this.holdGrace = const Duration(seconds: 3),
  }) {
    _trigger = ReportOfferTrigger(_offer, isBusy: () => busy);
  }

  final bool Function() isTaskRunning;
  final bool Function() isActive;
  final Future<bool> Function() prepare;
  final Future<bool?> Function(Future<bool> Function() body) runDialog;
  final Future<void> Function() perform;
  final Duration holdGrace;

  late final ReportOfferTrigger _trigger;
  bool _uploadActive = false;
  int _holds = 0;
  Timer? _holdTimer;
  bool _disposed = false;

  bool get busy =>
      isTaskRunning() || _uploadActive || _holds > 0 || _holdTimer != null;

  void onRunningState({required bool running}) =>
      _trigger.onRunningState(running: running);

  Future<void> request() => _trigger.request();

  void resume() {
    if (!_disposed) _trigger.resume();
  }

  void setUploadActive(bool active) {
    _uploadActive = active;
    if (!active) resume();
  }

  Future<void> guardedUpload({
    required bool Function() blocked,
    required Future<void> Function(void Function(bool active) onActive) run,
  }) async {
    if (_uploadActive || blocked()) return;
    await run(setUploadActive);
  }

  Future<T> holdFor<T>(Future<T> Function() action) async {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holds++;
    try {
      return await action();
    } finally {
      _holds--;
      if (_holds == 0 && !_disposed) {
        _holdTimer = Timer(holdGrace, () {
          _holdTimer = null;
          resume();
        });
      }
    }
  }

  Future<void> _offer() async {
    if (!await prepare()) return;
    final ran = await runDialog(() async {
      if (busy) {
        _trigger.defer();
        return false;
      }
      await perform();
      return true;
    });
    if (ran == null && isActive()) _trigger.defer();
  }

  void dispose() {
    _disposed = true;
    _holdTimer?.cancel();
    _holdTimer = null;
  }
}
