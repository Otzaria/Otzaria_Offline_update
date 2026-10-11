import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

class MemoryOutbox implements ReportOutbox {
  MemoryOutbox(Iterable<String> ids) {
    for (final id in ids) {
      add(reportJson(id), filePath: '$id.json');
    }
  }

  final List<OutboxReport> reports = [];
  final Map<String, Map<String, dynamic>> files = {};
  final List<String> bodyReads = [];

  void add(Map<String, dynamic> fileJson, {required String filePath}) {
    reports.add(OutboxReport.fromJson(fileJson, filePath: filePath));
    files[filePath] = fileJson;
  }

  Map<String, dynamic> bodyOf(OutboxReport report) =>
      files[report.filePath]!['body'] as Map<String, dynamic>;

  @override
  Future<List<OutboxReport>> list() async => List.of(reports);

  @override
  Future<Uint8List> requestBody(OutboxReport report) async {
    bodyReads.add(report.reportId);
    return OutboxReport.requestBodyOf(files[report.filePath]!);
  }

  @override
  Future<void> remove(OutboxReport report) async =>
      reports.removeWhere((r) => r.reportId == report.reportId);

  @override
  Future<void> write(String reportId, Uint8List fileBytes) async {
    await discard(reportId);
    add(
      jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>,
      filePath: reportId,
    );
  }

  @override
  Future<void> discard(String reportId) async =>
      reports.removeWhere((r) => r.reportId == reportId);
}
