import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import 'dispose_guard.dart';
import 'progress_notifier.dart';

enum AndroidOperation {
  idle,
  checking,
  downloading,
  installing,
  exporting,
  tools
}

class AndroidModuleController extends ChangeNotifier
    with DisposeGuard, ProgressNotifier, SilentAfterDispose {
  AndroidModuleController({
    required String dataDir,
    required String stateDir,
    this.readOnly = false,
    AndroidUpdateManager? manager,
  }) : _manager = manager ??
            AndroidUpdateManager(
                dataDir: dataDir, stateDir: stateDir, readOnly: readOnly);

  final AndroidUpdateManager _manager;
  final bool readOnly;
  AndroidOperation operation = AndroidOperation.idle;
  AndroidMirroredRelease? release;
  List<AndroidDevice> devices = const [];
  AndroidDeviceInfo? deviceInfo;
  String? selectedSerial;
  String? toolsPath;
  Object? error;
  String? notice;
  String? stage;
  int? received;
  int? total;
  bool checked = false;
  AndroidCancellation? _cancellation;
  Future<void>? _pending;
  Future<void> Function()? _retry;

  bool Function()? blockedElsewhere;
  bool get actionsBlocked => isBusy || (blockedElsewhere?.call() ?? false);

  bool get isBusy => operation != AndroidOperation.idle;
  bool get isDownloading => operation == AndroidOperation.downloading;
  bool get canRetry => _retry != null && !actionsBlocked;
  AndroidUpdateFailure? get incompatibility {
    final apk = release?.info;
    final device = deviceInfo;
    if (apk == null || device == null) return null;
    try {
      device.requireCompatible(apk);
      return null;
    } on AndroidUpdateException catch (failure) {
      return failure.failure;
    }
  }

  bool get canInstall =>
      !actionsBlocked &&
      release != null &&
      deviceInfo != null &&
      selectedSerial == deviceInfo!.device.serial &&
      incompatibility == null &&
      (deviceInfo!.versionCode == null ||
          deviceInfo!.versionCode! < release!.info.versionCode);

  Future<void> refresh() => _perform(AndroidOperation.checking, (cancel) async {
        await _refresh(cancel);
      }, retry: refresh);

  Future<void> _refresh(AndroidCancellation cancel) async {
    deviceInfo = null;
    devices = const [];
    toolsPath = null;
    release = null;
    release = await _manager.loadMirror();
    toolsPath = await _manager.tools.resolve();
    devices = toolsPath == null ? const [] : await _manager.devices(cancel);
    final authorized = devices.where((d) => d.authorized).toList();
    if (!authorized.any((d) => d.serial == selectedSerial)) {
      selectedSerial = null;
    }
    if (selectedSerial == null && authorized.length == 1) {
      selectedSerial = authorized.single.serial;
    }
    if (selectedSerial != null) {
      deviceInfo = await _manager.inspectDevice(selectedSerial!, cancel);
    }
    checked = true;
  }

  Future<void> selectDevice(String serial) =>
      _perform(AndroidOperation.checking, (cancel) async {
        selectedSerial = serial;
        deviceInfo = null;
        deviceInfo = await _manager.inspectDevice(serial, cancel);
      }, retry: () => selectDevice(serial));

  Future<void> download() =>
      _perform(AndroidOperation.downloading, (cancel) async {
        if (readOnly) {
          throw const AndroidUpdateException(AndroidUpdateFailure.readOnly);
        }
        release =
            await _manager.downloadLatest(cancel, onProgress: (value, bound) {
          received = value;
          total = bound;
          notifyProgress();
        });
      }, retry: download);

  Future<void> install() {
    final serial = selectedSerial;
    if (serial == null) return Future.value();
    return _install(serial);
  }

  Future<void> _install(String serial) =>
      _perform(AndroidOperation.installing, (cancel) async {
        deviceInfo = null;
        deviceInfo = await _manager.install(serial, cancel, onStage: (value) {
          stage = value;
          notifyProgress();
        });
        notice = AppL10n.strings.android.installed;
      }, retry: () => _install(serial));

  Future<void> selectTools(String directory, {bool copyToDrive = false}) =>
      _perform(AndroidOperation.tools, (cancel) async {
        toolsPath = await _manager.selectTools(directory, cancel,
            copyToDrive: copyToDrive);
        await _refresh(cancel);
        notice = AppL10n.strings.android.toolsCopied;
      }, retry: () => selectTools(directory, copyToDrive: copyToDrive));

  Future<void> exportApk(String destination) =>
      _perform(AndroidOperation.exporting, (cancel) async {
        await _manager.exportApk(destination, cancel);
        notice = AppL10n.strings.android.exported;
      }, retry: () => exportApk(destination));

  Future<void> retry() => _retry?.call() ?? Future.value();

  Future<void> _perform(
      AndroidOperation next, Future<void> Function(AndroidCancellation) action,
      {required Future<void> Function() retry}) {
    if (actionsBlocked || isDisposed) return Future.value();
    final cancel = AndroidCancellation();
    _cancellation = cancel;
    operation = next;
    error = null;
    notice = null;
    stage = null;
    received = null;
    total = null;
    _retry = null;
    notifyListeners();
    final pending = _execute(cancel, action, retry);
    _pending = pending;
    return pending;
  }

  Future<void> _execute(
      AndroidCancellation cancel,
      Future<void> Function(AndroidCancellation) action,
      Future<void> Function() retry) async {
    try {
      await action(cancel);
    } on AndroidUpdateException catch (failure) {
      if (failure.failure == AndroidUpdateFailure.cancelled) {
        notice = '$failure';
      } else {
        error = failure;
        _retry = retry;
      }
    } catch (failure) {
      error = failure;
      _retry = retry;
    } finally {
      if (identical(_cancellation, cancel)) {
        _cancellation = null;
        _pending = null;
        operation = AndroidOperation.idle;
        notifyListeners();
      }
    }
  }

  Future<void> cancelAndWait() async {
    _cancellation?.cancel();
    await _pending;
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _manager.dispose();
    super.dispose();
  }
}
