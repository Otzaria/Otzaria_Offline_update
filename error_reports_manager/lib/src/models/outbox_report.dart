import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// דיווח טעות אחד שנאסף מהתור של אוצריא, כפי שהוא יושב בתיבת היציאה עד
/// שיישלח.
class OutboxReport {
  const OutboxReport({
    required this.reportId,
    required this.endpoint,
    required this.bookTitle,
    required this.filePath,
    this.createdAt,
    this.hasImages = false,
    this.hasMinidump = false,
    this.autoUpload = false,
  });

  static const String format = 'otzaria-report';
  static const int version = 1;

  /// הכתובת היחידה שהאיסוף כותב — זו שאוצריא שולחת אליה.
  static const String reportingEndpoint =
      'https://otzaria.org/api/reportingerrors';
  static const String appReportingEndpoint =
      'https://otzaria.org/api/app-reports';
  static const String pluginReportingEndpoint =
      'https://otzaria.org/api/plugin-reports';

  /// תוכן הקובץ שהאיסוף כותב, בפורמט ש-[OutboxReport.fromJson] קורא.
  static Map<String, dynamic> fileJson({
    required String reportId,
    required String bookTitle,
    required String createdAt,
    required Map<String, dynamic> body,
    String endpoint = reportingEndpoint,
    bool autoUpload = false,
  }) =>
      {
        'format': format,
        'version': version,
        'report_id': reportId,
        'endpoint': endpoint,
        'book_title': bookTitle,
        'created_at': createdAt,
        'body': body,
        if (autoUpload) 'auto_upload': true,
      };

  final String reportId;

  final Uri endpoint;
  final String bookTitle;
  final DateTime? createdAt;

  final bool hasImages;
  final bool hasMinidump;
  final bool autoUpload;

  /// הקובץ בתיבת היציאה — נמחק כשהדיווח נשלח או נדחה סופית.
  final String filePath;

  factory OutboxReport.fromJson(
    Map<String, dynamic> json, {
    required String filePath,
  }) {
    if (json['format'] != format || json['version'] != version) {
      throw FormatException('not an $format v$version file', filePath);
    }
    final id = json['report_id'];
    final endpoint = json['endpoint'];
    final body = json['body'];
    if (id is! String || id.isEmpty) {
      throw FormatException('missing report_id', filePath);
    }
    if (endpoint is! String) {
      throw FormatException('missing endpoint', filePath);
    }
    if (body is! Map<String, dynamic>) {
      throw FormatException('missing body', filePath);
    }
    final title = json['book_title'];
    final created = json['created_at'];
    final attachments = body['attachments'];
    final images = attachments is Map ? attachments['images'] : null;
    return OutboxReport(
      reportId: id,
      endpoint: Uri.parse(endpoint),
      bookTitle: title is String ? title : '',
      createdAt: created is String ? DateTime.tryParse(created) : null,
      filePath: filePath,
      hasImages: images is List && images.isNotEmpty,
      hasMinidump: attachments is Map && attachments['minidump'] != null,
      autoUpload: json['auto_upload'] == true,
    );
  }

  /// הקידומת של מזהה הקובץ בתיבה, כמו באיסוף: `app-`/`plugin-`, ובלי קידומת
  /// לדיווח על ספר.
  static String idPrefixFor(Uri endpoint) => switch (endpoint.path) {
        '/api/app-reports' => 'app-',
        '/api/plugin-reports' => 'plugin-',
        _ => '',
      };

  /// טביעה של תוכן הדיווח בלי המזהה שלו — זהה לשני העותקים שנשארים אחרי
  /// קריסה בין כתיבת המזהה החדש (409) למחיקת הישן.
  static String? contentKeyOf(Map<String, dynamic> fileJson) {
    final body = fileJson['body'];
    if (body is! Map<String, dynamic>) return null;
    final idKey = body.containsKey('report_id') ? 'report_id' : 'reportId';
    if (body[idKey] is! String) return null;
    final content = Map.of(body)
      ..remove(idKey)
      ..remove('product');
    return sha256
        .convert(utf8.encode('${fileJson['endpoint']}\n${jsonEncode(content)}'))
        .toString();
  }

  static Uint8List encodeFile(Map<String, dynamic> fileJson) =>
      utf8.encode(jsonEncode(fileJson));

  static Uint8List requestBodyOf(Map<String, dynamic> fileJson) {
    final body = fileJson['body'] as Map<String, dynamic>;
    return utf8.encode(jsonEncode(
      body.containsKey('product') ? (Map.of(body)..remove('product')) : body,
    ));
  }

  /// רק https לשרת של אוצריא עצמו. קובץ על הכונן יכול להגיע מכל מקום, ולכן
  /// כתובת אחרת אינה נשלחת לעולם.
  bool get isAllowedEndpoint =>
      endpoint.scheme == 'https' &&
      endpoint.host.toLowerCase() == 'otzaria.org' &&
      endpoint.userInfo.isEmpty &&
      (!endpoint.hasPort || endpoint.port == 443) &&
      !endpoint.hasQuery &&
      !endpoint.hasFragment &&
      _allowedPaths.contains(endpoint.path);

  static final Set<String> _allowedPaths = {
    for (final url in [
      reportingEndpoint,
      appReportingEndpoint,
      pluginReportingEndpoint,
    ])
      Uri.parse(url).path,
  };
}
