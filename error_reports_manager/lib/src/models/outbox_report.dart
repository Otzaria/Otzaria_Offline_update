import 'dart:convert';
import 'dart:typed_data';

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
  }) =>
      {
        'format': format,
        'version': version,
        'report_id': reportId,
        'endpoint': endpoint,
        'book_title': bookTitle,
        'created_at': createdAt,
        'body': body,
      };

  final String reportId;

  final Uri endpoint;
  final String bookTitle;
  final DateTime? createdAt;

  final bool hasImages;

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
    );
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
      (!endpoint.hasPort || endpoint.port == 443);
}
