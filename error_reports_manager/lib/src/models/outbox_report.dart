/// דיווח טעות אחד שנאסף מהתור של אוצריא, כפי שהוא יושב בתיבת היציאה עד
/// שיישלח.
class OutboxReport {
  const OutboxReport({
    required this.reportId,
    required this.endpoint,
    required this.bookTitle,
    required this.body,
    required this.filePath,
    this.createdAt,
  });

  static const String format = 'otzaria-report';
  static const int version = 1;

  /// הכתובת היחידה שהאיסוף כותב — זו שאוצריא שולחת אליה.
  static const String reportingEndpoint =
      'https://otzaria.org/api/reportingerrors';

  /// תוכן הקובץ שהאיסוף כותב, בפורמט ש-[OutboxReport.fromJson] קורא.
  static Map<String, dynamic> fileJson({
    required String reportId,
    required String bookTitle,
    required String createdAt,
    required Map<String, dynamic> body,
  }) =>
      {
        'format': format,
        'version': version,
        'report_id': reportId,
        'endpoint': reportingEndpoint,
        'book_title': bookTitle,
        'created_at': createdAt,
        'body': body,
      };

  final String reportId;

  /// הכתובת שאליה נשלח [body]. נבדקת מול [isAllowedEndpoint] לפני כל שליחה.
  final Uri endpoint;
  final String bookTitle;
  final DateTime? createdAt;

  /// גוף הבקשה כפי שנבנה באיסוף (`toApiPayload`) — נשלח כמות שהוא.
  final Map<String, dynamic> body;

  /// הקובץ בתיבת היציאה — נמחק כשהדיווח נשלח או נדחה סופית.
  final String filePath;

  /// זורק [FormatException] על קובץ שאינו עומד בחוזה; הקורא מדלג עליו.
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
    return OutboxReport(
      reportId: id,
      endpoint: Uri.parse(endpoint),
      bookTitle: title is String ? title : '',
      createdAt: created is String ? DateTime.tryParse(created) : null,
      body: body,
      filePath: filePath,
    );
  }

  /// רק https לשרת של אוצריא עצמו. קובץ על הכונן יכול להגיע מכל מקום, ולכן
  /// כתובת אחרת אינה נשלחת לעולם.
  bool get isAllowedEndpoint =>
      endpoint.scheme == 'https' &&
      endpoint.host.toLowerCase() == 'otzaria.org' &&
      endpoint.userInfo.isEmpty &&
      (!endpoint.hasPort || endpoint.port == 443);
}
