import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:path/path.dart' as p;

/// טיוטה של טופס הדיווח על התוכנה, כפי שהמשתמש הקליד אותה — כמו
/// `AppReportDraft` של אוצריא. ההסתרה נעשית רק בשליחה.
class AppReportDraft {
  const AppReportDraft({
    this.type,
    this.title = '',
    this.description = '',
    this.steps = '',
    this.includeDiagnostics = true,
    this.includeErrorLog = true,
    this.images = const [],
  });

  final AppReportType? type;
  final String title;
  final String description;
  final String steps;
  final bool includeDiagnostics;
  final bool includeErrorLog;
  final List<AppReportImage> images;

  bool get isEmpty =>
      type == null &&
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      steps.trim().isEmpty &&
      images.isEmpty;

  Map<String, dynamic> toJson() => {
        'type': type?.name,
        'title': title,
        'description': description,
        'steps': steps,
        'includeDiagnostics': includeDiagnostics,
        'includeErrorLog': includeErrorLog,
        'images': [for (final image in images) image.toJson()],
      };

  static AppReportDraft? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final type = json['type'];
    final images = json['images'];
    return AppReportDraft(
      type: type is String && AppReportType.values.any((t) => t.name == type)
          ? AppReportType.parse(type)
          : null,
      title: json['title'] is String ? json['title'] as String : '',
      description:
          json['description'] is String ? json['description'] as String : '',
      steps: json['steps'] is String ? json['steps'] as String : '',
      includeDiagnostics: json['includeDiagnostics'] != false,
      includeErrorLog: json['includeErrorLog'] != false,
      images: images is List
          ? [
              ...images
                  .map(AppReportImage.fromJson)
                  .whereType<AppReportImage>(),
            ]
          : const [],
    );
  }
}

/// הטיוטה היחידה של הדיווח הידני, ב-`<תיקיית המחשב>/reports/launcher-draft.json`
/// (ראו `AppReportsController.forState`). כשל קריאה הוא "אין טיוטה".
class AppReportDraftStore {
  AppReportDraftStore(this.path);

  factory AppReportDraftStore.inState(String stateDir) =>
      AppReportDraftStore(p.join(stateDir, 'reports', fileName));

  static const String fileName = 'launcher-draft.json';

  final String path;

  Future<AppReportDraft?> load() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final draft =
          AppReportDraft.fromJson(jsonDecode(await file.readAsString()));
      return draft == null || draft.isEmpty ? null : draft;
    } on Object {
      return null;
    }
  }

  /// טיוטה ריקה מוחקת את הקובץ, כדי שלא תיפתח "טיוטה" בלי תוכן.
  Future<void> save(AppReportDraft draft) async {
    if (draft.isEmpty) return discard();
    await File(path).parent.create(recursive: true);
    await writeStringAtomically(path, jsonEncode(draft.toJson()));
  }

  Future<void> discard() async {
    try {
      await File(path).delete();
    } on PathNotFoundException {
      return;
    }
  }
}
