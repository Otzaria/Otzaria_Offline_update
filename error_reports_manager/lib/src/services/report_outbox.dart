import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/outbox_report.dart';

abstract interface class ReportOutbox {
  Future<List<OutboxReport>> list();

  Future<Uint8List> requestBody(OutboxReport report);

  Future<void> remove(OutboxReport report);

  Future<void> write(String reportId, Uint8List fileBytes);

  Future<void> discard(String reportId);
}

/// `<stateDir>/reports/outbox` — **לא** תחת `mirror/`, כדי שניקוי המראה
/// וביטול הורדה לעולם לא ימחקו דיווח שעוד לא נשלח.
class DirectoryReportOutbox implements ReportOutbox {
  DirectoryReportOutbox(this.directory, {this.onInvalid});

  /// הנתיב המקובל בתוך תיקיית המצב.
  static String dirIn(String stateDir) => p.join(stateDir, 'reports', 'outbox');

  final String directory;

  /// קובץ שדולג — ליומן בלבד.
  final void Function(String path, Object error)? onInvalid;

  @override
  Future<List<OutboxReport>> list() async {
    final dir = directory;
    if (!await Directory(dir).exists()) return const [];
    final listed = await Isolate.run(() => _listIn(dir));
    for (final (path, error) in listed.invalid) {
      onInvalid?.call(path, error);
    }
    return listed.reports;
  }

  static Future<({List<OutboxReport> reports, List<(String, String)> invalid})>
      _listIn(String directory) async {
    final out = <OutboxReport>[];
    final invalid = <(String, String)>[];
    await for (final entity in Directory(directory).list()) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (lower.endsWith('.json.tmp')) {
        await _deleteIfStale(entity);
        continue;
      }
      if (!lower.endsWith('.json')) continue;
      try {
        out.add(OutboxReport.fromJson(
          await _readJson(entity.path),
          filePath: entity.path,
        ));
      } catch (e) {
        invalid.add((entity.path, '$e'));
      }
    }
    out.sort(compareReports);
    return (reports: out, invalid: invalid);
  }

  static Future<Map<String, dynamic>> _readJson(String path) async {
    final json = jsonDecode(await File(path).readAsString());
    if (json is! Map<String, dynamic>) {
      throw FormatException('not a JSON object', path);
    }
    return json;
  }

  @override
  Future<Uint8List> requestBody(OutboxReport report) {
    final path = report.filePath;
    return Isolate.run(() async {
      final json = await _readJson(path);
      OutboxReport.fromJson(json, filePath: path);
      return OutboxReport.requestBodyOf(json);
    });
  }

  /// מהישן לחדש; בלי זמן יצירה — בסוף. שם הקובץ מכריע תיקו, כך שהסדר עקבי.
  static int compareReports(OutboxReport a, OutboxReport b) {
    final at = a.createdAt, bt = b.createdAt;
    if (at != null && bt != null) {
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }
    return a.filePath.compareTo(b.filePath);
  }

  @override
  Future<void> remove(OutboxReport report) async {
    final file = File(report.filePath);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {
    await Directory(directory).create(recursive: true);
    final target = File(_pathFor(reportId));
    final temp = File(_tempFor(target.path));
    await temp.writeAsBytes(fileBytes, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> discard(String reportId) async {
    final path = _pathFor(reportId);
    for (final file in [File(path), File(_tempFor(path))]) {
      if (await file.exists()) await file.delete();
    }
  }

  static const staleTempAge = Duration(hours: 1);

  static String _tempFor(String path) => '$path.tmp';

  static Future<void> _deleteIfStale(File temp) async {
    try {
      final age = DateTime.now().difference(await temp.lastModified());
      if (age > staleTempAge) await temp.delete();
    } on FileSystemException {
      return;
    }
  }

  /// המזהה מגיע ממסד של אוצריא — רק תווים בטוחים לשם קובץ.
  String _pathFor(String reportId) {
    final safe = reportId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return p.join(directory, '$safe.json');
  }
}
