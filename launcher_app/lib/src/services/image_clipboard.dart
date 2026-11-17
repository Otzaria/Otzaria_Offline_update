import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:ffi/ffi.dart';

import 'app_logger.dart';
import 'dib_to_png.dart';

/// מה שנמצא בלוח כתמונה: בייטים של תמונה מקודדת, ו/או נתיבי קבצי תמונה
/// שהועתקו ב-Explorer.
class ClipboardImages {
  const ClipboardImages(
      {this.bytes, this.paths = const [], this.tooLarge = false});

  final Uint8List? bytes;
  final List<String> paths;

  /// התמונה בלוח גדולה מכדי להיקרא; אינה נטענת לזיכרון.
  final bool tooLarge;
}

/// גישה ללוח לתמונות. מוזרק בבדיקות — בלוח האמיתי לא נוגעים שם.
abstract class ImageClipboard {
  const ImageClipboard();

  /// האם יש במכשיר דרך לקרוא תמונה מהלוח.
  bool get isSupported;

  /// סינכרוני וזול: הלוח מחזיק תמונה **ואין בו טקסט**. טקסט גובר, כי
  /// העתקה מ-Word או Excel מכניסה לשם גם תמונה, והשדה צריך את הטקסט.
  bool get holdsImageWithoutText;

  /// `null` כשאין בלוח תמונה.
  Future<ClipboardImages?> read();
}

/// ברירת מחדל: Windows בלבד. ב-macOS אין דרך בלי תוסף נייטיב, ולכן ההדבקה
/// אינה מוצעת שם.
class SystemImageClipboard extends ImageClipboard {
  const SystemImageClipboard();

  @override
  bool get isSupported => Platform.isWindows;

  @override
  bool get holdsImageWithoutText {
    if (!isSupported) return false;
    try {
      return _WinClipboard.instance.holdsImageWithoutText();
    } catch (error, stack) {
      AppLogger.maybeInstance?.error('בדיקת תמונה בלוח נכשלה', error, stack);
      return false;
    }
  }

  @override
  Future<ClipboardImages?> read() async {
    if (!isSupported) return null;
    final raw = await _WinClipboard.instance.read();
    if (raw == null) return null;
    if (raw.dib != null) {
      final png = await Isolate.run(() => dibToPng(raw.dib!));
      if (png == null) return null;
      return ClipboardImages(bytes: png);
    }
    return ClipboardImages(
      bytes: raw.bytes,
      paths: raw.paths,
      tooLarge: raw.tooLarge,
    );
  }
}

class _RawClipboard {
  _RawClipboard(
      {this.bytes, this.dib, this.paths = const [], this.tooLarge = false});

  final Uint8List? bytes;
  final Uint8List? dib;
  final List<String> paths;
  final bool tooLarge;
}

const _cfUnicodeText = 13;
const _cfText = 1;
const _cfDib = 8;
const _cfDibV5 = 17;
const _cfHdrop = 15;

/// מעל זה תמונה אינה נקראת: ממילא תידחה כגדולה מדי.
const _maxReadBytes = 64 * 1024 * 1024;

typedef _BoolU32 = Int32 Function(Uint32);
typedef _BoolU32D = int Function(int);

class _WinClipboard {
  _WinClipboard._() {
    final user = DynamicLibrary.open('user32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final shell = DynamicLibrary.open('shell32.dll');
    _open = user.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'OpenClipboard');
    _close =
        user.lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
    _available =
        user.lookupFunction<_BoolU32, _BoolU32D>('IsClipboardFormatAvailable');
    _get = user.lookupFunction<IntPtr Function(Uint32), int Function(int)>(
        'GetClipboardData');
    _register = user.lookupFunction<Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('RegisterClipboardFormatW');
    _lock = kernel.lookupFunction<Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)>('GlobalLock');
    _unlock = kernel.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'GlobalUnlock');
    _size = kernel.lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
        'GlobalSize');
    _drag = shell.lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer<Utf16>, Uint32),
        int Function(int, int, Pointer<Utf16>, int)>('DragQueryFileW');
    final name = 'PNG'.toNativeUtf16();
    try {
      _pngFormat = _register(name);
    } finally {
      calloc.free(name);
    }
  }

  static final _WinClipboard instance = _WinClipboard._();

  late final int Function(int) _open;
  late final int Function() _close;
  late final _BoolU32D _available;
  late final int Function(int) _get;
  late final int Function(Pointer<Utf16>) _register;
  late final Pointer<Void> Function(int) _lock;
  late final int Function(int) _unlock;
  late final int Function(int) _size;
  late final int Function(int, int, Pointer<Utf16>, int) _drag;
  late final int _pngFormat;

  bool _has(int format) => format != 0 && _available(format) != 0;

  bool holdsImageWithoutText() {
    if (_has(_cfUnicodeText) || _has(_cfText)) return false;
    if (_has(_pngFormat) || _has(_cfDib) || _has(_cfDibV5)) return true;
    if (!_has(_cfHdrop)) return false;
    if (_open(0) == 0) return false;
    try {
      return _hdropPaths().isNotEmpty;
    } finally {
      _close();
    }
  }

  Future<_RawClipboard?> read() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      if (_open(0) != 0) {
        try {
          return _readOpen();
        } finally {
          _close();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    throw const FileSystemException('clipboard is busy');
  }

  _RawClipboard? _readOpen() {
    if (_has(_pngFormat)) {
      final r = _copy(_pngFormat);
      if (r != null) return r;
    }
    if (_has(_cfHdrop)) {
      final paths = _hdropPaths();
      if (paths.isNotEmpty) return _RawClipboard(paths: paths);
    }
    for (final format in [_cfDib, _cfDibV5]) {
      if (!_has(format)) continue;
      final r = _copy(format, asDib: true);
      if (r != null) return r;
    }
    return null;
  }

  _RawClipboard? _copy(int format, {bool asDib = false}) {
    final handle = _get(format);
    if (handle == 0) return null;
    final size = _size(handle);
    if (size <= 0) return null;
    if (size > _maxReadBytes) return _RawClipboard(tooLarge: true);
    final pointer = _lock(handle);
    if (pointer == nullptr) return null;
    try {
      final bytes = Uint8List.fromList(pointer.cast<Uint8>().asTypedList(size));
      return asDib ? _RawClipboard(dib: bytes) : _RawClipboard(bytes: bytes);
    } finally {
      _unlock(handle);
    }
  }

  List<String> _hdropPaths() {
    final handle = _get(_cfHdrop);
    if (handle == 0) return const [];
    final count = _drag(handle, 0xFFFFFFFF, nullptr, 0);
    final paths = <String>[];
    for (var i = 0; i < count && i < 50; i++) {
      final length = _drag(handle, i, nullptr, 0);
      if (length <= 0) continue;
      final buffer = calloc<Uint16>(length + 1).cast<Utf16>();
      try {
        _drag(handle, i, buffer, length + 1);
        final path = buffer.toDartString();
        if (AppReportImage.mimeTypeForPath(path) != null) paths.add(path);
      } finally {
        calloc.free(buffer);
      }
    }
    return paths;
  }
}
