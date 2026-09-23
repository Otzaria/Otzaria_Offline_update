import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:path/path.dart' as p;

/// קובץ דיווח תקין לפי החוזה, עם שדות שניתן לשנות לבדיקה.
Map<String, dynamic> reportJson(
  String id, {
  String endpoint = 'https://otzaria.org/api/reportingerrors',
  String createdAt = '2026-09-01T10:00:00Z',
}) =>
    {
      'format': 'otzaria-report',
      'version': 1,
      'report_id': id,
      'endpoint': endpoint,
      'book_title': 'ספר $id',
      'created_at': createdAt,
      'body': {'id': id, 'text': 'טעות'},
    };

void writeReport(String dir, Map<String, dynamic> json, {String? name}) {
  Directory(dir).createSync(recursive: true);
  File(p.join(dir, name ?? '${json['report_id']}.json'))
      .writeAsStringSync(jsonEncode(json));
}

/// תיבת יציאה בזיכרון — כמו זו שבבדיקות הלאנצ'ר.
class MemoryOutbox implements ReportOutbox {
  MemoryOutbox(Iterable<String> ids)
      : reports = [
          for (final id in ids)
            OutboxReport.fromJson(reportJson(id), filePath: '$id.json'),
        ];

  final List<OutboxReport> reports;

  @override
  Future<List<OutboxReport>> list() async => List.of(reports);

  @override
  Future<void> remove(OutboxReport report) async =>
      reports.removeWhere((r) => r.reportId == report.reportId);

  @override
  Future<void> write(String reportId, Map<String, dynamic> fileJson) async {
    await discard(reportId);
    reports.add(OutboxReport.fromJson(fileJson, filePath: reportId));
  }

  @override
  Future<void> discard(String reportId) async =>
      reports.removeWhere((r) => r.reportId == reportId);
}
