import 'dart:typed_data';

import 'package:zstandard/zstandard.dart';

/// מספק את פונקציית החילוץ ש-`PatchDownloader` דורש (מוזרקת, כי החבילה
/// המקורית אגנוסטית לפלטפורמה/ספריית zstd).
///
/// משתמש ב-`package:zstandard` — אותה חבילה שאוצריא עצמה כבר משתמשת בה
/// היום ב-`main.dart:1112` (ראו PACKAGE_PLAN.md §2ג), עם binding native
/// אמיתי ל-libzstd לכל הפלטפורמות (כולל Windows). לא ה-decoder החלקי
/// (`archive`/`ZstdDecoder`) שנוסה כאן בטעות קודם — זה לא קיים בפועל
/// ב-`package:archive` (הוא תומך רק ב-zip/tar/bzip2/gzip/zlib).
class ZstdDecompressor {
  const ZstdDecompressor();

  Future<Uint8List?> call(Uint8List compressed) async {
    try {
      return await Zstandard().decompress(compressed);
    } catch (_) {
      return null;
    }
  }
}
