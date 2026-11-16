import 'dart:io';
import 'dart:typed_data';

/// ממיר DIB מהלוח של Windows (`CF_DIB`/`CF_DIBV5`, כולל כותרת) ל-PNG, או
/// `null` לפורמט שאינו נתמך (24 ו-32 ביט, בלי דחיסה) או לנתונים פגומים.
Uint8List? dibToPng(Uint8List dib) {
  if (dib.length < 40) return null;
  final d = ByteData.sublistView(dib);
  final headerSize = d.getUint32(0, Endian.little);
  if (headerSize != 40 &&
      headerSize != 52 &&
      headerSize != 56 &&
      headerSize != 108 &&
      headerSize != 124) {
    return null;
  }
  final width = d.getInt32(4, Endian.little);
  final rawHeight = d.getInt32(8, Endian.little);
  final bitCount = d.getUint16(14, Endian.little);
  final compression = d.getUint32(16, Endian.little);
  final clrUsed = d.getUint32(32, Endian.little);
  final height = rawHeight.abs();
  if (width <= 0 || height <= 0 || width > 32768 || height > 32768) {
    return null;
  }
  if (width * height > 64 * 1024 * 1024) return null;
  if (bitCount != 24 && bitCount != 32) return null;
  final bitfields = compression == 3;
  if (compression != 0 && !bitfields) return null;

  var r = 0x00FF0000, g = 0x0000FF00, b = 0x000000FF, a = 0;
  var offset = headerSize;
  if (bitfields && bitCount == 32) {
    if (headerSize == 40) {
      if (dib.length < 52) return null;
      r = d.getUint32(40, Endian.little);
      g = d.getUint32(44, Endian.little);
      b = d.getUint32(48, Endian.little);
      offset += 12;
    } else if (headerSize >= 52) {
      r = d.getUint32(40, Endian.little);
      g = d.getUint32(44, Endian.little);
      b = d.getUint32(48, Endian.little);
      if (headerSize >= 56) a = d.getUint32(52, Endian.little);
    }
  } else if (bitfields && headerSize == 40) {
    offset += 12;
  }
  offset += clrUsed * 4;

  final bytesPerPixel = bitCount ~/ 8;
  final stride = ((width * bitCount + 31) ~/ 32) * 4;
  if (offset < 0 || offset + stride * height > dib.length) return null;

  final channels = [
    _Channel(r),
    _Channel(g),
    _Channel(b),
  ];
  if (bitCount == 32 && channels.any((c) => c.mask == 0)) return null;
  final alpha = bitCount == 32 && a != 0 ? _Channel(a) : null;

  final rgba = Uint8List(width * height * 4);
  var anyAlpha = false;
  for (var y = 0; y < height; y++) {
    final srcRow = offset + (rawHeight > 0 ? height - 1 - y : y) * stride;
    var out = y * width * 4;
    for (var x = 0; x < width; x++) {
      final p = srcRow + x * bytesPerPixel;
      if (bitCount == 24) {
        rgba[out] = dib[p + 2];
        rgba[out + 1] = dib[p + 1];
        rgba[out + 2] = dib[p];
        rgba[out + 3] = 255;
      } else {
        final v = d.getUint32(p, Endian.little);
        rgba[out] = channels[0].extract(v);
        rgba[out + 1] = channels[1].extract(v);
        rgba[out + 2] = channels[2].extract(v);
        final av = alpha?.extract(v) ?? 255;
        if (av != 0) anyAlpha = true;
        rgba[out + 3] = av;
      }
      out += 4;
    }
  }
  // אלפא שכולו אפס אינו שקיפות מלאה אלא שדה שלא מולא (צילום מסך).
  final useAlpha = alpha != null && anyAlpha;
  return encodePng(width, height, rgba, useAlpha: useAlpha);
}

class _Channel {
  _Channel(this.mask) {
    var m = mask;
    while (m != 0 && m & 1 == 0) {
      m >>= 1;
      shift++;
    }
    while (m & 1 == 1) {
      m >>= 1;
      bits++;
    }
  }

  final int mask;
  int shift = 0;
  int bits = 0;

  int extract(int pixel) {
    final v = (pixel & mask) >> shift;
    if (bits == 8) return v;
    if (bits == 0) return 0;
    return v * 255 ~/ ((1 << bits) - 1);
  }
}

/// קודד PNG של [rgba] (ארבעה בתים לפיקסל). בלי אלפא נכתב RGB.
Uint8List encodePng(int width, int height, Uint8List rgba,
    {required bool useAlpha}) {
  final channels = useAlpha ? 4 : 3;
  final rowBytes = width * channels;
  final raw = Uint8List((rowBytes + 1) * height);
  for (var y = 0; y < height; y++) {
    var out = y * (rowBytes + 1) + 1; // בית הסינון נשאר 0
    var src = y * width * 4;
    for (var x = 0; x < width; x++) {
      raw[out++] = rgba[src];
      raw[out++] = rgba[src + 1];
      raw[out++] = rgba[src + 2];
      if (useAlpha) raw[out++] = rgba[src + 3];
      src += 4;
    }
  }
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, useAlpha ? 6 : 2);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', Uint8List.fromList(zlib.encode(raw)));
  _chunk(out, 'IEND', Uint8List(0));
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, Uint8List data) {
  final head = ByteData(8)..setUint32(0, data.length);
  final typeBytes = Uint8List.fromList(type.codeUnits);
  head.buffer.asUint8List().setRange(4, 8, typeBytes);
  out.add(head.buffer.asUint8List());
  out.add(data);
  var crc = _crc(typeBytes, 0xFFFFFFFF);
  crc = _crc(data, crc) ^ 0xFFFFFFFF;
  out.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(Uint8List bytes, int crc) {
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc;
}
