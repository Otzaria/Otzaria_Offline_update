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
  static const int maxBytes = 5 * 1000 * 1000;
  static const int maxTotalBytes = 15 * 1000 * 1000;

  /// הנפח המרבי של התמונות בגוף הבקשה: base64 ועוד שם וסוג לכל תמונה.
  static const int maxPayloadBytes =
      (maxTotalBytes + 2) ~/ 3 * 4 + maxCount * 1024;

  /// אורך שם הקובץ בגוף הבקשה; נשמר הסוף, שבו הסיומת.
  static const int maxFileNameLength = 200;

  /// סיומות הקבצים שנקלטים מבחירת קובץ.
  static const List<String> supportedExtensions = ['png', 'jpg', 'jpeg', 'gif'];

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// סוג התוכן לפי סיומת הקובץ, או `null` כשהסיומת אינה נתמכת.
  static String? mimeTypeForPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    return switch (path.substring(dot + 1).toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      _ => null,
    };
  }

  /// סוג התמונה לפי הבייטים הראשונים (PNG, JPEG, GIF), או `null`. הסיומת
  /// אינה ראיה: קובץ שנקרא `a.png` עשוי להיות כל דבר, ו-[mimeType] נשלח לשרת.
  static String? sniffMimeType(List<int> head) {
    bool starts(List<int> magic) =>
        head.length >= magic.length &&
        [for (var i = 0; i < magic.length; i++) head[i] == magic[i]]
            .every((same) => same);
    if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    // GIF87a / GIF89a.
    if (starts(const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
        starts(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
      return 'image/gif';
    }
    return null;
  }

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

  AppReportImage withFileName(String name) =>
      AppReportImage(bytes: bytes, fileName: name, mimeType: mimeType);
}

/// הסיבה שחלק מהתמונות לא צורפו.
enum AppReportImageRejection { tooLarge, tooMany, totalTooLarge }

/// מצרף את [incoming] ל-[existing]: מדלג על תמונות גדולות מדי ועוצר במכסה.
({List<AppReportImage> images, AppReportImageRejection? rejection})
    mergeAppReportImages(
  List<AppReportImage> existing,
  List<AppReportImage> incoming,
) {
  AppReportImageRejection? rejection;
  final images = [...existing];
  var total = images.fold<int>(0, (sum, image) => sum + image.bytes.length);
  for (final image in incoming) {
    if (image.bytes.length > AppReportImage.maxBytes) {
      rejection ??= AppReportImageRejection.tooLarge;
      continue;
    }
    if (images.length >= AppReportImage.maxCount) {
      rejection = AppReportImageRejection.tooMany;
      break;
    }
    if (total + image.bytes.length > AppReportImage.maxTotalBytes) {
      rejection = AppReportImageRejection.totalTooLarge;
      continue;
    }
    images.add(image);
    total += image.bytes.length;
  }
  return (images: images, rejection: rejection);
}
