import 'dart:ffi';
import 'dart:io';

import 'app_logger.dart';

/// מוריד את עדיפות ה-CPU וה-I/O של כל התהליך בזמן עבודה כבדה.
///
/// נכנס במצב ב-[acquire] הראשון ויוצא כשהאחרון משוחרר. לעולם אינו זורק.
class BackgroundPriority {
  BackgroundPriority({
    bool Function(bool enter)? platformSwitch,
    void Function(bool enter, bool ok)? onSwitch,
  })  : _switch = platformSwitch ?? _switchNative,
        _onSwitch = onSwitch ?? _logSwitch;

  final bool Function(bool enter) _switch;
  final void Function(bool enter, bool ok) _onSwitch;
  int _leases = 0;
  bool _inBackground = false;

  bool get isActive => _inBackground;
  int get leases => _leases;

  /// מחזיר פונקציית שחרור שאפשר לקרוא לה יותר מפעם אחת.
  void Function() acquire() {
    _leases++;
    if (_leases == 1) _enter();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _leases--;
      if (_leases == 0) _leave();
    };
  }

  Future<T> run<T>(Future<T> Function() body) async {
    final release = acquire();
    try {
      return await body();
    } finally {
      release();
    }
  }

  void _enter() {
    final ok = _call(true);
    if (ok) _inBackground = true;
    _report(true, ok);
  }

  void _leave() {
    if (!_inBackground) return;
    _inBackground = false;
    _report(false, _call(false));
  }

  void _report(bool enter, bool ok) => _safe(() => _onSwitch(enter, ok));

  static void _logSwitch(bool enter, bool ok) {
    if (enter && ok) {
      AppLogger.instance.info('עדיפות רקע: נכנס');
    } else if (enter) {
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

  bool _call(bool enter) {
    try {
      return _switch(enter);
    } catch (_) {
      return false;
    }
  }

  // מצב רקע חל רק על התהליך הנוכחי, ונכשל אם הוא כבר בו.
  static bool _switchNative(bool enter) {
    if (!Platform.isWindows) return true;
    final kernel = DynamicLibrary.open('kernel32.dll');
    final current = kernel.lookupFunction<IntPtr Function(), int Function()>(
      'GetCurrentProcess',
    );
    final setClass = kernel.lookupFunction<Int32 Function(IntPtr, Uint32),
        int Function(int, int)>('SetPriorityClass');
    return setClass(current(), enter ? 0x00100000 : 0x00200000) != 0;
  }
}
