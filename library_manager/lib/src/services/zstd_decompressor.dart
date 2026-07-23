import 'dart:typed_data';

import 'package:archive/archive.dart';

/// מספק את פונקציית החילוץ ש-`PatchDownloader` דורש (מוזרקת, כי החבילה
/// המקורית אגנוסטית לפלטפורמה/ספריית zstd).
///
/// ⚠️ **לא נבדק בפועל** (אין כאן סביבת Windows/Flutter להרצה) — כדאי
/// לוודא ש-`ZstdDecoder` ב-`package:archive` בגרסה הנעולה אכן קיים
/// ומתנהג כמצופה (חילוץ zstd גנרי, בלי תלות ב-frame dictionary מיוחד).
/// אם זה לא עובד, חלופה: `package:zstandard`/binding native ל-libzstd.
class ZstdDecompressor {
  const ZstdDecompressor();

  Future<Uint8List?> call(Uint8List compressed) async {
    try {
      final decoded = const ZstdDecoder().decodeBytes(compressed);
      return Uint8List.fromList(decoded);
    } catch (_) {
      return null;
    }
  }
}
