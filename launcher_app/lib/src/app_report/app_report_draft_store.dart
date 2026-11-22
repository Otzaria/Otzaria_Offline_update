import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
    this.email,
    this.revision = '',
    this.includeDiagnostics = true,
    this.includeErrorLog = true,
    this.images = const [],
  });

  final AppReportType? type;
  final String title;
  final String description;
  final String steps;
  final String? email;
  final String revision;
  final bool includeDiagnostics;
  final bool includeErrorLog;
  final List<AppReportImage> images;

  bool get isEmpty =>
      type == null &&
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      steps.trim().isEmpty &&
      email == null &&
      includeDiagnostics &&
      includeErrorLog &&
      images.isEmpty;

  Map<String, dynamic> toJson() => {
        'type': type?.name,
        'title': title,
        'description': description,
        'steps': steps,
        if (email != null) 'email': email,
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
      email: json['email'] is String ? json['email'] as String : null,
      revision: json['revision'] is String ? json['revision'] as String : '',
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

  static const _revisionPrefix = '{"revision":"';

  // POSIX file locks exclude other processes. This queue also excludes other
  // stores created in the launcher isolate.
  static Future<void> _mutationTail = Future<void>.value();

  final String path;

  Future<AppReportDraft?> load() async {
    try {
      if (!await File(path).exists()) return null;
      return await _decode(path);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static Future<AppReportDraft?> _decode(String path) => Isolate.run(() {
        final draft = AppReportDraft.fromJson(
          jsonDecode(File(path).readAsStringSync()),
        );
        return draft == null || draft.isEmpty ? null : draft;
      });

  Future<String> save(AppReportDraft draft) async {
    final revision = AppReport.generateReportId();
    final bytes = await _encode(draft, revision);
    await _mutate(() => writeBytesAtomically(path, bytes));
    return revision;
  }

  static Future<Uint8List> _encode(AppReportDraft draft, String revision) =>
      Isolate.run(() => utf8.encode(
            jsonEncode({'revision': revision, ...draft.toJson()}),
          ));

  /// Returns false if another launcher has saved a newer draft.
  Future<bool> discard(String revision) => _mutate(() async {
        try {
          final file = File(path);
          if (!await _matchesRevision(file, revision)) return false;
          await file.delete();
        } on PathNotFoundException {
          return true;
        }
        return true;
      });

  static Future<bool> _matchesRevision(File file, String revision) async {
    // The revision comes first in the JSON so deleting needn't decode images.
    final expected =
        revision.isEmpty ? _revisionPrefix : '$_revisionPrefix$revision",';
    final reader = await file.open();
    try {
      final prefix = String.fromCharCodes(await reader.read(expected.length));
      return revision.isEmpty ? prefix != expected : prefix == expected;
    } finally {
      await reader.close();
    }
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) async {
      final lockFile = File('$path.lock');
      await lockFile.parent.create(recursive: true);
      final lock = await lockFile.open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
        return await operation();
      } finally {
        await lock.close();
      }
    });
    _mutationTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
