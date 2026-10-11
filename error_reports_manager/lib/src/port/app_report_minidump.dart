import 'dart:convert';
import 'dart:typed_data';

class AppReportMinidump {
  const AppReportMinidump({required this.gzipBytes, required this.fileName});

  static const int maxRawBytes = 16 * 1000 * 1000;

  static const int maxPayloadBytes = (maxRawBytes + 2) ~/ 3 * 4 + 1024;

  static const int maxFileNameLength = 200;

  final Uint8List gzipBytes;
  final String fileName;

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
