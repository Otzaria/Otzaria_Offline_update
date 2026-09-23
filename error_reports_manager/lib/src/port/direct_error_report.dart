// פורט של `lib/models/direct_error_report.dart` באוצריא — רק בניית גוף הבקשה.
// ⚠️ שינוי שם חייב להגיע לכאן, אחרת נשלח גוף שאוצריא עצמה לא הייתה שולחת.
import 'dart:convert';

import 'canonical_json.dart';

enum DirectErrorReportKind {
  freeText('free_text'),
  textCorrection('text_correction');

  const DirectErrorReportKind(this.apiName);

  final String apiName;

  static DirectErrorReportKind fromApiName(Object? value) =>
      DirectErrorReportKind.values.firstWhere(
        (kind) => kind.apiName == value,
        orElse: () => DirectErrorReportKind.freeText,
      );
}

/// הצעת תיקון; השדות מדויקים. בחירה null = השורה כולה.
class TextCorrection {
  const TextCorrection._({
    required this.originalLine,
    required this.originalSelection,
    required this.selectionStart,
    required this.selectionEnd,
    required this.proposedText,
  });

  const TextCorrection.wholeLine({
    required String originalLine,
    String? proposedText,
  }) : this._(
          originalLine: originalLine,
          originalSelection: null,
          selectionStart: null,
          selectionEnd: null,
          proposedText: proposedText,
        );

  factory TextCorrection.selection({
    required String originalLine,
    required int start,
    required int end,
    String? proposedText,
  }) {
    RangeError.checkValidRange(start, end, originalLine.length);
    if (start == end) {
      throw ArgumentError.value(end, 'end', 'Empty selection');
    }
    return TextCorrection._(
      originalLine: originalLine,
      originalSelection: originalLine.substring(start, end),
      selectionStart: start,
      selectionEnd: end,
      proposedText: proposedText,
    );
  }

  final String originalLine;
  final String? originalSelection;
  final int? selectionStart;
  final int? selectionEnd;
  final String? proposedText;

  bool get hasSelection => originalSelection != null;
  String get target => originalSelection ?? originalLine;
  String get contextBefore =>
      hasSelection ? originalLine.substring(0, selectionStart) : '';
  String get contextAfter =>
      hasSelection ? originalLine.substring(selectionEnd!) : '';

  Map<String, dynamic>? get _apiSelectionOffset => hasSelection
      ? {
          'unit': 'utf16_code_units',
          'start': selectionStart,
          'end': selectionEnd,
        }
      : null;

  /// null כשהנתונים אינם עקביים — כמו באוצריא.
  static TextCorrection? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final line = raw['originalLine'];
    final proposed = raw['proposedText'];
    if (line is! String || (proposed != null && proposed is! String)) {
      return null;
    }
    final start = raw['selectionStart'];
    final end = raw['selectionEnd'];
    final isWholeLine =
        start == null && end == null && raw['originalSelection'] == null;
    if (isWholeLine) {
      return TextCorrection.wholeLine(
        originalLine: line,
        proposedText: proposed as String?,
      );
    }
    if (start is int && end is int) {
      try {
        final correction = TextCorrection.selection(
          originalLine: line,
          start: start,
          end: end,
          proposedText: proposed as String?,
        );
        final storedSelection = raw['originalSelection'];
        if (storedSelection != null &&
            storedSelection != correction.originalSelection) {
          return null;
        }
        return correction;
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// מצרף הצעה מרשומה פגומה כטקסט ל-[details].
  static String salvageMalformedInto(String details, Map raw) {
    final target = raw['originalSelection'] ?? raw['originalLine'];
    final proposed = raw['proposedText'];
    if (target is! String || (proposed != null && proposed is! String)) {
      return details;
    }
    return TextCorrection.wholeLine(
      originalLine: target,
      proposedText: proposed as String?,
    ).appendFallbackTo(details);
  }

  Map<String, dynamic> toApiPayload() => {
        'original_line': originalLine,
        'original_selection': originalSelection,
        'selection_offset': _apiSelectionOffset,
        'proposed_text': proposedText,
        'context_before': contextBefore,
        'context_after': contextAfter,
      };

  Map<String, dynamic> toDigestMap() => {
        'original_line': originalLine,
        'original_selection': originalSelection,
        'proposed_text': proposedText,
        'selection_offset': _apiSelectionOffset,
      };

  /// בלוק ה-fallback לאתר ישן שמתעלם מ-`correction` — הנוסח של אוצריא, מילה במילה.
  String get fallbackBlock {
    final proposed = switch (proposedText) {
      null => '(ללא הצעה)',
      '' => '(מחיקה)',
      final text => text,
    };
    return '--- הצעת תיקון ---\nמקור: $target\nמוצע: $proposed';
  }

  String appendFallbackTo(String details) =>
      details.isEmpty ? fallbackBlock : '$details\n\n$fallbackBlock';
}

class ReportLocation {
  const ReportLocation({
    this.lineIndex,
    this.bookId,
    this.libraryBuildId,
    this.heRef,
  });

  final int? lineIndex;
  final int? bookId;
  final String? libraryBuildId;
  final String? heRef;

  static ReportLocation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ReportLocation(
      lineIndex: raw['lineIndex'] as int?,
      bookId: raw['bookId'] as int?,
      libraryBuildId: raw['libraryBuildId'] as String?,
      heRef: raw['heRef'] as String?,
    );
  }

  Map<String, dynamic> toApiPayload() => {
        'line_index': lineIndex,
        'book_id': bookId,
        'library_build_id': libraryBuildId,
        'he_ref': heRef,
      };
}

class ReportClientInfo {
  const ReportClientInfo({required this.appVersion, required this.platform});

  final String appVersion;
  final String platform;

  static ReportClientInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ReportClientInfo(
      appVersion: (raw['appVersion'] as String?) ?? '',
      platform: (raw['platform'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toApiPayload() => {
        'app_version': appVersion,
        'platform': platform,
      };
}

/// דיווח טעות כפי שאוצריא שומרת אותו בתור (`payload_json`).
class DirectErrorReport {
  /// הגרסה החדשה ביותר שהפורט מכיר; דיווח חדש ממנה אינו נשלח.
  static const int currentSchemaVersion = 2;

  /// תקרת גוף הבקשה לפי החוזה: 256KB של UTF-8.
  static const int maxApiBodyBytes = 256 * 1024;

  const DirectErrorReport({
    required this.id,
    required this.senderEmail,
    required this.subject,
    required this.bookTitle,
    required this.currentRef,
    required this.lineNumber,
    required this.selectedText,
    required this.errorDetails,
    required this.contextText,
    required this.filePath,
    required this.sourceFolder,
    required this.libraryVersion,
    required this.createdAt,
    required this.schemaVersion,
    required this.reportKind,
    this.location,
    this.client,
    this.correction,
  });

  final String id;
  final String senderEmail;
  final String subject;
  final String bookTitle;
  final String currentRef;
  final int lineNumber;
  final String selectedText;
  final String errorDetails;
  final String contextText;
  final String filePath;
  final String sourceFolder;
  final String libraryVersion;
  final DateTime createdAt;
  final int schemaVersion;
  final DirectErrorReportKind reportKind;
  final ReportLocation? location;
  final ReportClientInfo? client;
  final TextCorrection? correction;

  /// זורק (TypeError/FormatException) על רשומה שאינה עומדת בחוזה, כמו באוצריא.
  factory DirectErrorReport.fromJson(Map<String, dynamic> json) {
    final rawCorrection = json['correction'];
    final correction = TextCorrection.fromJson(rawCorrection);
    final kind = correction == null
        ? DirectErrorReportKind.freeText
        : DirectErrorReportKind.fromApiName(json['reportKind']);
    var errorDetails = (json['errorDetails'] as String?) ?? '';
    if (correction == null && rawCorrection is Map) {
      errorDetails =
          TextCorrection.salvageMalformedInto(errorDetails, rawCorrection);
    }
    return DirectErrorReport(
      id: json['id'] as String,
      senderEmail: json['senderEmail'] as String,
      subject: json['subject'] as String,
      bookTitle: json['bookTitle'] as String,
      currentRef: json['currentRef'] as String,
      lineNumber: json['lineNumber'] as int,
      selectedText: (json['selectedText'] as String?) ?? '',
      errorDetails: errorDetails,
      contextText: (json['contextText'] as String?) ?? '',
      filePath: (json['filePath'] as String?) ?? '',
      sourceFolder: (json['sourceFolder'] as String?) ?? '',
      libraryVersion: (json['libraryVersion'] as String?) ?? 'unknown',
      createdAt: DateTime.parse(json['createdAt'] as String),
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
      reportKind: kind,
      location: ReportLocation.fromJson(json['location']),
      client: ReportClientInfo.fromJson(json['client']),
      correction:
          kind == DirectErrorReportKind.textCorrection ? correction : null,
    );
  }

  String get apiErrorDetails =>
      correction?.appendFallbackTo(errorDetails) ?? errorDetails;

  /// `content_digest` לפי חוזה §4.2, על הערכים שנשלחים בפועל.
  String get contentDigest => canonicalJsonSha256({
        'v': 1,
        'report_kind': reportKind.apiName,
        'book_title': bookTitle,
        'current_ref': currentRef,
        'line_index': location?.lineIndex,
        'selected_text': selectedText,
        'error_details': apiErrorDetails,
        'context_text': contextText,
        'source_folder': sourceFolder,
        'file_path': filePath,
        'library_version': libraryVersion,
        'correction': correction?.toDigestMap(),
      });

  String get apiBody => jsonEncode(toApiPayload());

  /// מה שאוצריא עצמה מסננת לפני ייצוא לשליחה ממחשב אחר
  /// (`buildOfflineSendScript`), ועוד תקרת הגוף שהשרת דוחה מעליה.
  bool get isSendable {
    if (schemaVersion > currentSchemaVersion) return false;
    try {
      contentDigest;
    } on ArgumentError {
      return false;
    }
    return utf8.encode(apiBody).length <= maxApiBodyBytes;
  }

  Map<String, dynamic> toApiPayload() {
    final payload = <String, dynamic>{
      'report_id': id,
      'sender_email': senderEmail,
      'subject': subject,
      'book_title': bookTitle,
      'current_ref': currentRef,
      'line_number': lineNumber,
      'selected_text': selectedText,
      'error_details': errorDetails,
      'context_text': contextText,
      'file_path': filePath,
      'source_folder': sourceFolder,
      'library_version': libraryVersion,
      'created_at': createdAt.toIso8601String(),
    };
    if (schemaVersion < 2) return payload;

    payload
      ..['error_details'] = apiErrorDetails
      ..['schema_version'] = currentSchemaVersion
      ..['report_kind'] = reportKind.apiName
      ..['content_digest'] = contentDigest
      ..['location'] = (location ?? const ReportLocation()).toApiPayload()
      ..['source_hint'] = {
        'source_folder': sourceFolder,
        'library_relative_path': filePath,
        'repo_path': null,
      }
      ..['client'] = client?.toApiPayload();
    final correction = this.correction;
    if (correction != null) payload['correction'] = correction.toApiPayload();
    return payload;
  }
}
