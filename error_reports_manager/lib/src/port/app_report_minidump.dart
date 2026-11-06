import 'dart:convert';
import 'dart:typed_data';

class AppReportMinidump {
  const AppReportMinidump({required this.gzipBytes, required this.fileName});

  static const int maxRawBytes = 10 * 1024 * 1024;
  static const int legacyMaxRawBytes = 16 * 1024 * 1024;
  // gzip can grow for incompressible input at the exact raw file limit.
  static const int compressionAllowance = 64 * 1024;

  /// הנפח המרבי בגוף הבקשה: base64 של dump שלא התכווץ, ועוד השם.
  static const int maxPayloadBytes =
      (maxRawBytes + compressionAllowance + 2) ~/ 3 * 4 + 1024;

  static const int maxFileNameLength = 200;

  final Uint8List gzipBytes;
  final String fileName;

  int? get rawByteLength {
    if (gzipBytes.length < 18 ||
        gzipBytes[0] != 0x1f ||
        gzipBytes[1] != 0x8b ||
        gzipBytes[2] != 8) {
      return null;
    }
    return ByteData.sublistView(gzipBytes).getUint32(
      gzipBytes.length - 4,
      Endian.little,
    );
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'data': base64Encode(gzipBytes),
      };

  static AppReportMinidump? fromJson(Object? json) {
    if (json is! Map) return null;
    final data = json['data'];
    if (data is! String) return null;
    try {
      return AppReportMinidump(
        gzipBytes: base64Decode(data),
        fileName: json['fileName'] is String ? json['fileName'] as String : '',
      );
    } on FormatException {
      return null;
    }
  }
}
