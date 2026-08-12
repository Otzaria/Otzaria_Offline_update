import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';

import 'support/zstd_fixtures.dart';

/// החילוץ **בזיכרון** — מוזרק ל-`PatchDownloader` (קובצי patch, עשרות MB)
/// ומשמש כמסלול גיבוי ל-DB המלא. החוזה שלו הוא "מחזיר null בכשל, לא זורק":
/// המוריד מתרגם זאת להודעת אימות במקום לחריג native.
void main() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();
  const decompress = ZstdDecompressor();

  group('ZstdDecompressor', () {
    test('סבב דחיסה/חילוץ מחזיר בית-בית את המקור', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final original = pseudoRandomBytes(256 * 1024);
      final extracted = await decompress(compressWithZstd(bindings, original));

      expect(extracted, original);
    });

    test('קלט פגום מחזיר null במקום לזרוק', () async {
      final extracted = await decompress(
        Uint8List.fromList([0x28, 0xB5, 0x2F, 0xFD, 9, 9, 9, 9, 9]),
      );

      expect(extracted, isNull);
    });

    test('קלט שאינו zstd בכלל מחזיר null', () async {
      final extracted =
          await decompress(Uint8List.fromList('לא קובץ דחוס'.codeUnits));

      expect(extracted, isNull);
    });

    test('קלט קטוע מחזיר null ולא פלט חלקי', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressed = compressWithZstd(bindings, pseudoRandomBytes(1 << 18));
      final truncated =
          Uint8List.sublistView(compressed, 0, compressed.length ~/ 2);

      expect(await decompress(truncated), isNull);
    });

    test('קלט ריק מחזיר פלט ריק — הקוראים בודקים isEmpty, לא רק null',
        () async {
      // בלי הספרייה כל חילוץ מחזיר null, כולל זה — כמו שאר הבדיקות כאן.
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // חשוב: זה **לא** null. `PatchDownloader` ו-`LibraryUpdateApplier`
      // בודקים שניהם `== null || isEmpty` בדיוק בגלל זה.
      final extracted = await decompress(Uint8List(0));

      expect(extracted, isNotNull);
      expect(extracted, isEmpty);
    });
  });
}
