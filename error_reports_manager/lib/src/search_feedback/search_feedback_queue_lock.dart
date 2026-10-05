import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// נעילת flock לפי מתאר קובץ מגינה גם בין מנועי Flutter באותו תהליך.
/// נעילת FileLock ב-POSIX משותפת לתהליך ולכן אינה מפרידה בין isolates.
class SearchFeedbackQueueLock {
  SearchFeedbackQueueLock._(this._file, this._fd);
  final RandomAccessFile? _file;
  final int? _fd;

  static final _native = DynamicLibrary.process();
  static final _open = _native.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)>('open');
  static final _flock = _native
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
    'flock',
  );
  static final _close =
      _native.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _errno = _native
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
    Platform.isMacOS ? '__error' : '__errno_location',
  );

  static Future<SearchFeedbackQueueLock> acquire(String path) async {
    final file = await File(path).open(mode: FileMode.append);
    if (Platform.isWindows) {
      try {
        await file.lock(FileLock.blockingExclusive);
        return SearchFeedbackQueueLock._(file, null);
      } catch (_) {
        await file.close();
        rethrow;
      }
    }
    await file.close();
    final name = path.toNativeUtf8();
    late final int fd;
    try {
      fd = _open(name, 2); // הקובץ כבר נוצר; פתיחה לקריאה וכתיבה בלבד.
    } finally {
      calloc.free(name);
    }
    if (fd < 0) throw FileSystemException('open queue lock', path);
    try {
      while (_flock(fd, 6) != 0) {
        // ניסיון בלעדי שאינו חוסם את isolate של הממשק בזמן המתנה.
        final error = _errno().value;
        if (error != 4 && error != (Platform.isMacOS ? 35 : 11)) {
          throw FileSystemException('flock queue lock', path);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return SearchFeedbackQueueLock._(null, fd);
    } catch (_) {
      _close(fd);
      rethrow;
    }
  }

  Future<void> release() async {
    final file = _file;
    if (file != null) {
      try {
        await file.unlock();
      } finally {
        await file.close();
      }
    } else {
      try {
        _flock(_fd!, 8); // סגירת המתאר משחררת את הנעילה גם אחרי קריסה.
      } finally {
        _close(_fd!);
      }
    }
  }
}
