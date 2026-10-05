import 'dart:convert';
import 'dart:typed_data';

/// תמונה שצורפה לדיווח על התוכנה (צילום מסך מודבק, קובץ שנגרר או נבחר).
class AppReportImage {
  const AppReportImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  /// מספר התמונות המרבי בדיווח אחד.
  static const int maxCount = 5;

  /// גבולות בבייטים; מחושבים ב-1000 כדי להישאר מתחת לגבול השרת (MiB).
  static const int maxTotalBytes = 15 * 1000 * 1000;

  /// הנפח המרבי של התמונות בגוף הבקשה: base64 ועוד שם וסוג לכל תמונה.
  static const int maxPayloadBytes =
      (maxTotalBytes + 2) ~/ 3 * 4 + maxCount * 1024;

  /// אורך שם הקובץ בגוף הבקשה; נשמר הסוף, שבו הסיומת.
  static const int maxFileNameLength = 200;

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// הרשומה בגוף הבקשה ובתור המקומי.
  Map<String, dynamic> toJson() => {
        'fileName': fileName.length <= maxFileNameLength
            ? fileName
            : fileName.substring(fileName.length - maxFileNameLength),
        'mimeType': mimeType,
        'data': base64Encode(bytes),
      };

  /// `null` לרשומה פגומה.
  static AppReportImage? fromJson(Object? json) {
    if (json is! Map) return null;
    final data = json['data'];
    if (data is! String) return null;
    try {
      return AppReportImage(
        bytes: base64Decode(data),
        fileName: json['fileName'] is String ? json['fileName'] as String : '',
        mimeType: json['mimeType'] is String
            ? json['mimeType'] as String
            : 'image/png',
      );
    } on FormatException {
      return null;
    }
  }
}
