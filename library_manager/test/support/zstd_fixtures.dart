import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// יצירת קובצי `.zst` **אמיתיים** לבדיקות — מול אותה libzstd שהקוד בייצור
/// מחלץ איתה, כדי שהבדיקות לא יאמתו פורמט מדומה.

/// דוחס [data] דרך ה-one-shot של libzstd. משותף לכל הבדיקות שצריכות קלט דחוס.
Uint8List compressWithZstd(ZstandardNativeBindings zstd, Uint8List data) {
  final srcSize = data.lengthInBytes;
  final src = malloc.allocate<Uint8>(srcSize);
  src.asTypedList(srcSize).setAll(0, data);
  final dstCapacity = zstd.ZSTD_compressBound(srcSize);
  final dst = malloc.allocate<Uint8>(dstCapacity);
  try {
    final size = zstd.ZSTD_compress(
      dst.cast<Void>(),
      dstCapacity,
      src.cast<Void>(),
      srcSize,
      3,
    );
    if (size <= 0) throw StateError('הדחיסה עצמה נכשלה (code $size)');
    return Uint8List.fromList(dst.asTypedList(size));
  } finally {
    malloc.free(src);
    malloc.free(dst);
  }
}

/// נתונים שנדחסים אבל לא לאפס — LCG פשוט, דטרמיניסטי, בלי `Random` כדי
/// שכשל יהיה משוחזר.
Uint8List pseudoRandomBytes(int length) {
  final bytes = Uint8List(length);
  var state = 0x2545F491;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    // מיזוג עם תבנית חוזרת — אחרת התוכן חסר-דחיסה לגמרי ו-zstd שומר אותו כ-raw.
    bytes[i] = ((state >> 16) & 0xFF) & (i % 97 == 0 ? 0xFF : 0x3F);
  }
  return bytes;
}
