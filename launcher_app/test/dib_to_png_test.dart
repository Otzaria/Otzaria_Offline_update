import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/dib_to_png.dart';

/// פענוח PNG מינימלי של הקידוד שלנו: בודק CRC של כל קטע ומחזיר פיקסלים.
({int width, int height, int colorType, Uint8List pixels}) _decode(
  Uint8List png,
) {
  expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final d = ByteData.sublistView(png);
  var pos = 8;
  int? width, height, colorType;
  final idat = BytesBuilder();
  while (pos < png.length) {
    final length = d.getUint32(pos);
    final type = String.fromCharCodes(png.sublist(pos + 4, pos + 8));
    final data = png.sublist(pos + 8, pos + 8 + length);
    var crc = 0xFFFFFFFF;
    for (final b in [...png.sublist(pos + 4, pos + 8), ...data]) {
      crc ^= b;
      for (var k = 0; k < 8; k++) {
        crc = crc & 1 == 1 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    expect(d.getUint32(pos + 8 + length), crc ^ 0xFFFFFFFF, reason: type);
    if (type == 'IHDR') {
      width = d.getUint32(pos + 8);
      height = d.getUint32(pos + 12);
      colorType = data[9];
    } else if (type == 'IDAT') {
      idat.add(data);
    }
    pos += 12 + length;
  }
  final raw = Uint8List.fromList(zlib.decode(idat.takeBytes()));
  final channels = colorType == 6 ? 4 : 3;
  final row = width! * channels;
  final pixels = BytesBuilder();
  for (var y = 0; y < height!; y++) {
    expect(raw[y * (row + 1)], 0);
    pixels.add(raw.sublist(y * (row + 1) + 1, (y + 1) * (row + 1)));
  }
  return (
    width: width,
    height: height,
    colorType: colorType!,
    pixels: pixels.takeBytes(),
  );
}

Uint8List _header(
  int size, {
  required int width,
  required int height,
  required int bits,
  int compression = 0,
}) {
  final h = ByteData(size)
    ..setUint32(0, size, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, bits, Endian.little)
    ..setUint32(16, compression, Endian.little);
  return h.buffer.asUint8List();
}

void main() {
  flutterDecoderTest();
  test('24 ביט מלמטה למעלה, עם ריפוד שורות: סדר שורות וצבעים נכון', () {
    // 3x2: שורת תחתית (ראשונה בקובץ) אדום/ירוק/כחול, עליונה לבן/שחור/אפור.
    // BGR, ושורה של 9 בתים מרופדת ל-12.
    final dib = BytesBuilder()
      ..add(_header(40, width: 3, height: 2, bits: 24))
      ..add([0, 0, 255, 0, 255, 0, 255, 0, 0, 9, 9, 9])
      ..add([255, 255, 255, 0, 0, 0, 128, 128, 128, 9, 9, 9]);
    final png = decode(dibToPng(dib.takeBytes()));
    expect(png.width, 3);
    expect(png.height, 2);
    expect(png.colorType, 2);
    expect(png.pixels, [
      255, 255, 255, 0, 0, 0, 128, 128, 128, // עליונה
      255, 0, 0, 0, 255, 0, 0, 0, 255, // תחתונה
    ]);
  });

  test('24 ביט מלמעלה למטה (גובה שלילי)', () {
    final dib = BytesBuilder()
      ..add(_header(40, width: 1, height: -2, bits: 24))
      ..add([0, 0, 255, 0]) // אדום, ריפוד
      ..add([255, 0, 0, 0]); // כחול
    final png = decode(dibToPng(dib.takeBytes()));
    expect(png.pixels, [255, 0, 0, 0, 0, 255]);
  });

  test('32 ביט בלי אלפא (BI_RGB): אטום, גם כשבית האלפא אפס', () {
    final dib = BytesBuilder()
      ..add(_header(40, width: 2, height: 1, bits: 32))
      ..add([10, 20, 30, 0, 40, 50, 60, 0]); // BGRX
    final png = decode(dibToPng(dib.takeBytes()));
    expect(png.colorType, 2);
    expect(png.pixels, [30, 20, 10, 60, 50, 40]);
  });

  test('32 ביט BI_BITFIELDS עם כותרת V5 ואלפא: RGBA', () {
    final header = _header(124, width: 1, height: 1, bits: 32, compression: 3);
    final hd = ByteData.sublistView(header)
      ..setUint32(40, 0x00FF0000, Endian.little)
      ..setUint32(44, 0x0000FF00, Endian.little)
      ..setUint32(48, 0x000000FF, Endian.little)
      ..setUint32(52, 0xFF000000, Endian.little);
    expect(hd.getUint32(52, Endian.little), 0xFF000000);
    final dib = BytesBuilder()
      ..add(header)
      ..add([10, 20, 30, 128]);
    final png = decode(dibToPng(dib.takeBytes()));
    expect(png.colorType, 6);
    expect(png.pixels, [30, 20, 10, 128]);
  });

  test('32 ביט BITFIELDS בכותרת 40: שלוש המסכות אחרי הכותרת', () {
    final dib = BytesBuilder()
      ..add(_header(40, width: 1, height: 1, bits: 32, compression: 3));
    final masks = ByteData(12)
      ..setUint32(0, 0x000000FF, Endian.little) // R בבית הנמוך
      ..setUint32(4, 0x0000FF00, Endian.little)
      ..setUint32(8, 0x00FF0000, Endian.little);
    dib
      ..add(masks.buffer.asUint8List())
      ..add([1, 2, 3, 0]);
    final png = decode(dibToPng(dib.takeBytes()));
    expect(png.pixels, [1, 2, 3]);
  });

  test('נתונים קצרים, פורמט שאינו נתמך או ממדים אפסיים: null', () {
    expect(dibToPng(Uint8List(10)), isNull);
    expect(
      dibToPng(Uint8List.fromList(_header(40, width: 4, height: 4, bits: 8))),
      isNull,
    );
    expect(
      dibToPng(Uint8List.fromList(_header(40, width: 0, height: 4, bits: 24))),
      isNull,
    );
    // כותרת של 2x2 בלי נתוני פיקסלים
    expect(
      dibToPng(Uint8List.fromList(_header(40, width: 2, height: 2, bits: 24))),
      isNull,
    );
  });
}

({int width, int height, int colorType, Uint8List pixels}) decode(
  Uint8List? png,
) {
  expect(png, isNotNull);
  return _decode(png!);
}

void flutterDecoderTest() {
  testWidgets('Flutter מפענח את ה-PNG שנוצר', (tester) async {
    final dib = BytesBuilder()
      ..add(_header(40, width: 3, height: 2, bits: 24))
      ..add(List.filled(24, 100));
    final png = dibToPng(dib.takeBytes())!;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 3);
      expect(frame.image.height, 2);
    });
  });
}
