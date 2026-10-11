import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

enum InstanceLockResult { acquired, heldElsewhere, unavailable }

abstract final class InstanceLock {
  static const String fileName = 'instance.lock';

  static const String windowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';

  static const String windowTitle =
      '\u05E2\u05D3\u05DB\u05D5\u05E0\u05D9 \u05D0\u05D5\u05E6\u05E8\u05D9\u05D0';

  static RandomAccessFile? _held;

  static Future<InstanceLockResult> acquire(
    String directory, {
    Duration wait = const Duration(seconds: 2),
    Duration retryInterval = const Duration(milliseconds: 250),
  }) async {
    if (_held != null) return InstanceLockResult.acquired;
    final deadline = DateTime.now().add(wait);
    while (true) {
      final result = await _tryAcquire(directory);
      if (result != InstanceLockResult.heldElsewhere ||
          !DateTime.now().isBefore(deadline)) {
        return result;
      }
      await Future<void>.delayed(retryInterval);
    }
  }

  static Future<void> release() async {
    final held = _held;
    _held = null;
    if (held == null) return;
    try {
      await held.close();
    } on FileSystemException {
      return;
    }
  }

  static Future<InstanceLockResult> _tryAcquire(String directory) async {
    final RandomAccessFile file;
    try {
      await Directory(directory).create(recursive: true);
      file =
          await File(p.join(directory, fileName)).open(mode: FileMode.append);
    } on FileSystemException {
      return InstanceLockResult.unavailable;
    }
    try {
      await file.lock(FileLock.exclusive);
      _held = file;
      return InstanceLockResult.acquired;
    } on FileSystemException catch (e) {
      try {
        await file.close();
      } on FileSystemException catch (_) {}
      return isContention(e.osError?.errorCode)
          ? InstanceLockResult.heldElsewhere
          : InstanceLockResult.unavailable;
    }
  }

  static bool isContention(
    int? errorCode, {
    bool? isWindows,
    bool? isMacOS,
  }) {
    if (errorCode == null) return false;
    if (isWindows ?? Platform.isWindows) return errorCode == 33;
    if (isMacOS ?? Platform.isMacOS) return errorCode == 35 || errorCode == 13;
    return errorCode == 11 || errorCode == 13;
  }

  static void focusOtherInstance() {
    if (!Platform.isWindows) return;
    final className = windowClassName.toNativeUtf16();
    final title = windowTitle.toNativeUtf16();
    final owner = calloc<Uint32>();
    try {
      var window = 0;
      while (true) {
        window = FindWindowEx(0, window, className, title);
        if (window == 0) return;
        GetWindowThreadProcessId(window, owner);
        if (owner.value == pid) continue;
        if (IsIconic(window) != 0) ShowWindow(window, SW_RESTORE);
        SetForegroundWindow(window);
        return;
      }
    } finally {
      free(owner);
      free(title);
      free(className);
    }
  }
}
