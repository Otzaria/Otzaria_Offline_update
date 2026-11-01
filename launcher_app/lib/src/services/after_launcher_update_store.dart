import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// מה הכפתור הראשי של הבית ממשיך לעשות אחרי עדכון הכלי.
enum AfterLauncherUpdate { download, updateHere }

/// הפעולה שהכפתור הראשי התחיל לפני שהכלי הוחלף והופעל מחדש, כדי שהגרסה
/// החדשה תמשיך בה. נקראת פעם אחת ונמחקת; ישנה מ-[maxAge] — מתעלמים ממנה.
class AfterLauncherUpdateStore {
  AfterLauncherUpdateStore(String dir)
      : _file = File(p.join(dir, 'after_launcher_update.json'));

  /// התקנה שנקטעה לפני ההפעלה מחדש לא תתחיל הורדה בפתיחה של מחר.
  static const Duration maxAge = Duration(minutes: 10);

  final File _file;

  /// `false` כשלא נכתב — ואז אין למה לחזור אחרי ההפעלה מחדש.
  Future<bool> save(AfterLauncherUpdate then, {DateTime? now}) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode({
          'then': then.name,
          'at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        }),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }

  Future<AfterLauncherUpdate?> take({DateTime? now}) async {
    try {
      if (!await _file.exists()) return null;
      final raw = await _file.readAsString();
      await _file.delete();
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final at = DateTime.tryParse('${json['at']}');
      if (at == null || (now ?? DateTime.now()).difference(at).abs() > maxAge) {
        return null;
      }
      return AfterLauncherUpdate.values.asNameMap()[json['then']];
    } catch (_) {
      return null;
    }
  }
}
