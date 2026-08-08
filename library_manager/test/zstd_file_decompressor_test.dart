import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// בודק את החילוץ בזרימה מול libzstd **אמיתי**.
///
/// הבדיקה מדולגת כשאין ספריית zstd לטעינה (למשל לינוקס ב-CI, או הרצת
/// `flutter test` בלי שהפלאגין של הפלטפורמה נבנה) — בדיוק המצב שבו הקוד
/// שבייצור נופל למסלול הזיכרון. ב-Windows יש להריץ עם התיקייה של
/// `zstandard_windows.dll` ב-PATH; ראו library_manager/README.md.
void main() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();

  group('ZstdFileDecompressor', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('zstd-stream-test-');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('מחלץ קובץ גדול מרובה-צ׳אנקים בזהות בית-אחר-בית', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // 8MB — גדול בהרבה מ-ZSTD_DStreamOutSize (~128KB), ולכן מכריח את שתי
      // הלולאות (קלט וגם פלט) לרוץ הרבה סבבים. זה בדיוק מה שהמסלול
      // ה-one-shot לא בדק.
      final original = _pseudoRandomBytes(8 * 1024 * 1024);
      final compressedPath = '${tmp.path}/data.zst';
      final destPath = '${tmp.path}/data.bin';
      File(compressedPath).writeAsBytesSync(_compress(bindings, original));

      expect(
        await ZstdFileDecompressor.decompressFileToFile(
          compressedPath,
          destPath,
        ),
        isTrue,
      );
      expect(File(destPath).readAsBytesSync(), original);
    });

    test('קובץ קטוע נדחה במקום להשאיר DB חלקי', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressed = _compress(bindings, _pseudoRandomBytes(1 << 20));
      final truncatedPath = '${tmp.path}/truncated.zst';
      // חותכים את החצי השני: הצ׳אנקים הראשונים תקינים, אבל ה-frame לא נסגר.
      File(truncatedPath).writeAsBytesSync(
        Uint8List.sublistView(compressed, 0, compressed.length ~/ 2),
      );

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          truncatedPath,
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<ZstdStreamException>()),
      );
    });

    test('קובץ ריק נדחה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final emptyPath = '${tmp.path}/empty.zst';
      File(emptyPath).writeAsBytesSync(Uint8List(0));

      await expectLater(
        ZstdFileDecompressor.decompressFileToFile(
          emptyPath,
          '${tmp.path}/out.bin',
        ),
        throwsA(isA<ZstdStreamException>()),
      );
    });
  });
}

/// נתונים שנדחסים אבל לא לאפס — LCG פשוט, דטרמיניסטי, בלי `Random` כדי
/// שכשל יהיה משוחזר.
Uint8List _pseudoRandomBytes(int length) {
  final bytes = Uint8List(length);
  var state = 0x2545F491;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    // מיזוג עם תבנית חוזרת — אחרת התוכן חסר-דחיסה לגמרי ו-zstd שומר אותו כ-raw.
    bytes[i] = ((state >> 16) & 0xFF) & (i % 97 == 0 ? 0xFF : 0x3F);
  }
  return bytes;
}

Uint8List _compress(ZstandardNativeBindings zstd, Uint8List data) {
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
    expect(size, greaterThan(0), reason: 'הדחיסה עצמה נכשלה');
    return Uint8List.fromList(dst.asTypedList(size));
  } finally {
    malloc.free(src);
    malloc.free(dst);
  }
}
