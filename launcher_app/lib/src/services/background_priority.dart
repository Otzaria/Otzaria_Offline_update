import 'dart:ffi';
import 'dart:io';

import 'app_logger.dart';

/// Lowers the CPU priority class while a lease is held; lifted around
/// [aroundChildStart]. Never throws.
class BackgroundPriority {
  BackgroundPriority({
    bool Function(bool lower)? platformSwitch,
    void Function(bool lower, bool ok)? onSwitch,
  })  : _switch = platformSwitch ?? _switchNative,
        _onSwitch = onSwitch ?? _logSwitch;

  /// The one the app uses; `main` routes `aroundChildStart` to it.
  static BackgroundPriority instance = BackgroundPriority();

  final bool Function(bool lower) _switch;
  final void Function(bool lower, bool ok) _onSwitch;
  int _leases = 0;
  int _starting = 0;
  bool _lowered = false;

  bool get isActive => _lowered;
  int get leases => _leases;

  /// Returns a release function that may be called more than once.
  void Function() acquire() {
    if (_leases++ == 0) _report(true, true);
    _sync();
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_leases == 0) _report(false, true);
      _sync();
    };
  }

  /// Starts a program the user keeps using at the normal class: Windows gives
  /// a child the below-normal class of its parent for its whole life.
  Future<T> aroundChildStart<T>(Future<T> Function() start) async {
    _starting++;
    _sync();
    try {
      return await start();
    } finally {
      _starting--;
      _sync();
    }
  }

  // The log follows the leases; a platform switch is logged only when it fails.
  void _sync() {
    final want = _leases > 0 && _starting == 0;
    if (want == _lowered) return;
    final ok = _call(want);
    if (ok) {
      _lowered = want;
    } else {
      _report(want, false);
    }
  }

  void _report(bool lower, bool ok) => _safe(() => _onSwitch(lower, ok));

  static void _logSwitch(bool lower, bool ok) {
    if (lower && ok) {
      AppLogger.instance.info('עדיפות רקע: נכנס');
    } else if (lower) {
      AppLogger.instance.warn('עדיפות רקע: הכניסה נכשלה');
    } else if (ok) {
      AppLogger.instance.info('עדיפות רקע: יצא');
    } else {
      AppLogger.instance.warn('עדיפות רקע: היציאה נכשלה');
    }
  }

  static void _safe(void Function() write) {
    try {
      write();
    } catch (_) {}
  }

  bool _call(bool lower) {
    try {
      return _switch(lower);
    } catch (_) {
      return false;
    }
  }

  static const _idle = 0x40;
  static const _belowNormal = 0x4000;
  static int? _restoreClass;

  // Not PROCESS_MODE_BACKGROUND_BEGIN: it trims the working set to ~32MB,
  // which makes a multi-GB SQLite apply and hash page-fault constantly.
  static bool _switchNative(bool lower) {
    if (!Platform.isWindows) return true;
    final kernel = DynamicLibrary.open('kernel32.dll');
    final current = kernel.lookupFunction<IntPtr Function(), int Function()>(
      'GetCurrentProcess',
    );
    final setClass = kernel.lookupFunction<Int32 Function(IntPtr, Uint32),
        int Function(int, int)>('SetPriorityClass');
    if (!lower) {
      final restore = _restoreClass;
      if (restore == null) return true;
      if (setClass(current(), restore) == 0) return false;
      _restoreClass = null;
      return true;
    }
    final getClass =
        kernel.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
            'GetPriorityClass');
    final now = getClass(current());
    if (now == 0) return false;
    if (now == _idle || now == _belowNormal) return true;
    if (setClass(current(), _belowNormal) == 0) return false;
    _restoreClass = now;
    return true;
  }
}
