import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// זוכר **איפה נמצאה התוכנה בכל מחשב** שהכונן ביקר בו, ומדרג את המיקומים
/// לפי כמה מחשבים ראו אותם.
///
/// ⚠️ ההבחנה שמצילה כאן מבאג מוכר: הקובץ הזה נוסע על הכונן, ולכן הוא שומר
/// **איפה לחפש** ולא **מה מותקן**. מיקום שנלמד במחשב אחד הוא רק רמז לאן
/// להסתכל במחשב הבא — הזיהוי עצמו עדיין דורש שקובץ ההרצה יימצא שם בפועל.
/// זו בדיוק המחלה שתועדה ב-AGENTS.md לגבי `otzaria_install_state.json`,
/// שהכריז "מותקן" במחשב שלא היה בו כלום.
///
/// המפתח הוא שם המחשב, בדיוק כמו `LibraryStateStore.knownDbVersions` —
/// כך משתמש שמריץ על חמישה מחשבים מקבל רשימה שמשרתת את כולם.
class KnownLocationsStore {
  const KnownLocationsStore(this.filePath);

  final String filePath;

  /// `שם מחשב -> תיקיית ההתקנה שנמצאה בו`.
  Future<Map<String, String>> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return const {};

      final seen = json['seen'];
      if (seen is! Map) return const {};
      return {
        for (final entry in seen.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      // קובץ פגום אינו שובר את הזיהוי — פשוט אין ממה ללמוד.
      return const {};
    }
  }

  /// רושם שהתוכנה נמצאה ב-[installDir] במחשב הזה.
  Future<void> record(String installDir, {String? hostName}) async {
    final host = hostName ?? _hostName();
    if (host.isEmpty) return;

    final seen = Map<String, String>.from(await load());
    if (seen[host] == installDir) return;

    seen[host] = installDir;
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'seen': seen}));
  }

  /// המיקומים שנלמדו, **מהנפוץ לנדיר**: תיקייה שנמצאה בשלושה מחשבים
  /// נבדקת לפני אחת שנמצאה באחד. זה מה שהופך "המיקום שחוזר על עצמו"
  /// למיקום ברירת המחדל בפועל.
  ///
  /// שוויון נשבר לפי סדר אלפביתי, כדי שהתשובה תהיה זהה בכל מחשב.
  static List<String> rank(Map<String, String> seen) {
    final counts = <String, int>{};
    for (final dir in seen.values) {
      counts[dir] = (counts[dir] ?? 0) + 1;
    }
    final dirs = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return dirs;
  }

  static String _hostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  /// שם הקובץ בתוך תיקיית התוכנה.
  static String pathIn(String appDir) => p.join(appDir, 'locations.json');
}
