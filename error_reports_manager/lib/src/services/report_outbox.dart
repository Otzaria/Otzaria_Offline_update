import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/outbox_report.dart';

/// תיבת היציאה: הדיווחים שנאספו וטרם נשלחו. ממשק, כדי שבדיקות הלאנצ'ר
/// ירוצו בלי `dart:io` (שאינו מסתיים בתוך `testWidgets`).
abstract interface class ReportOutbox {
  /// הדיווחים התקינים, מהישן לחדש. קובץ פגום מדולג ואינו זורק.
  Future<List<OutboxReport>> list();

  /// נשלח או נדחה סופית — ולכן יוצא מהתיבה.
  Future<void> remove(OutboxReport report);

  /// כותב (או דורס) את הקובץ של [reportId] — ראו [OutboxReport.fileJson].
  Future<void> write(String reportId, Map<String, dynamic> fileJson);

  /// מוחק קובץ שנכתב אבל לא הועבר באוצריא.
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
    final dir = Directory(directory);
    if (!await dir.exists()) return const [];
    final out = <OutboxReport>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is! Map<String, dynamic>) {
          throw FormatException('not a JSON object', entity.path);
        }
        out.add(OutboxReport.fromJson(json, filePath: entity.path));
      } catch (e) {
        onInvalid?.call(entity.path, e);
      }
    }
    out.sort(compareReports);
    return out;
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
  Future<void> write(String reportId, Map<String, dynamic> fileJson) async {
    await Directory(directory).create(recursive: true);
    final target = File(_pathFor(reportId));
    // זמני ואז rename: קובץ חצוי היה נדחה כפגום, והדיווח כבר סומן כנשלח.
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(fileJson), flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> discard(String reportId) async {
    final file = File(_pathFor(reportId));
    if (await file.exists()) await file.delete();
  }

  /// המזהה מגיע ממסד של אוצריא — רק תווים בטוחים לשם קובץ.
  String _pathFor(String reportId) {
    final safe = reportId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return p.join(directory, '$safe.json');
  }
}
