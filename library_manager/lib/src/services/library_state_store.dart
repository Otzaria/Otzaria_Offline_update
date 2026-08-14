import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// שומר/טוען הגדרות מתמשכות של מודול הספרייה: נתיב DB מותאם אישית (למקרה
/// שהמשתמש הצביע ידנית על תיקיית ספרייה שאינה ברירת המחדל של אוצריא), וכן
/// נתיב "מראה מקומית" (offline) אם המשתמש בחר לעדכן מתיקייה מקומית/USB
/// במקום מהענן. קובץ state נפרד מזה של [OtzariaStateStore] — שני מודולים
/// שונים, שני קבצים.
///
/// **הקובץ יושב ב-`OtzariaData/`, כלומר על הכונן הנייד, ולכן הוא נוסע לכל
/// מחשב שהכונן מגיע אליו.** כל נתיב מוחלט שנשמר בו הוא לכן פר-מחשב — ראו
/// [loadCustomDbPath].
class LibraryStateStore {
  const LibraryStateStore(this.stateFilePath);

  final String stateFilePath;

  /// מזהה המחשב+החשבון שרשומות פר-מחשב נשמרות תחתיו. שם המחשב לבדו אינו
  /// מספיק: שני חשבונות באותו מחשב הם שני `%APPDATA%` שונים.
  static String currentMachineKey() {
    var host = 'unknown';
    try {
      host = Platform.localHostname;
    } catch (_) {}
    final env = Platform.environment;
    final account = env['USERNAME'] ?? env['USER'] ?? '';
    return '$host|$account';
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = File(stateFilePath);
    if (!await file.exists()) return {};
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> json) async {
    final file = File(stateFilePath);
    await file.parent.create(recursive: true);
    final tmp = File('$stateFilePath.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(stateFilePath);
  }

  /// הנתיב שנבחר **במחשב הזה**, או null כשלא הוגדר (וגם כשהקובץ פגום/לא
  /// קריא — מתייחסים לזה כ"לא הוגדר" ולא זורקים).
  ///
  /// **פר-מחשב, כי הקובץ נוסע עם הכונן** (issue #23): רשומה גלובלית אחת
  /// הצביעה במחשב השני על `C:\Users\<שם המשתמש של המחשב הראשון>`, ושם אי אפשר
  /// ליצור תיקייה — הספרייה סירבה להותקן עד שנבחר מיקום ידנית.
  ///
  /// רשומה מגרסה קודמת (מפתח יחיד, בלי מזהה מחשב) נחשבת רק אם היא נתיב מוחלט
  /// **בפלטפורמה הזו**, תיקיית האם שלו קיימת כאן, **והוא אינו יושב בתוך תיקיית
  /// הנתונים שעל הכונן**. התנאי האחרון הוא מה שסוגר את הכוננים שכבר בשטח:
  /// גרסאות עד 0.1.8 רשמו כאן, אחרי כל התקנה טרייה, את
  /// `<dataDir>/library/seforim.db` — ותיקיית האם של נתיב כזה נוסעת עם הכונן
  /// ולכן קיימת *תמיד*, כך שמסננת ה"תיקיית האם קיימת" לא פסלה אותה. התוצאה
  /// הייתה ~5.5GB שממשיכים להיכתב על הכונן, בזמן שאוצריא קוראת מ-`%APPDATA%`
  /// ואינה רואה דבר.
  Future<String?> loadCustomDbPath() async {
    final json = await _readAll();

    final perMachine = json['customDbPaths'];
    if (perMachine is Map) {
      final own = perMachine[currentMachineKey()];
      if (own is String && own.isNotEmpty) return own;
    }

    final legacy = json['customDbPath'];
    if (legacy is! String || legacy.isEmpty || !p.isAbsolute(legacy)) {
      return null;
    }
    if (isInsideDataDir(legacy)) return null;
    return await Directory(p.dirname(legacy)).exists() ? legacy : null;
  }

  /// `true` אם [path] יושב בתוך תיקיית הנתונים שקובץ ה-state הזה חי בה —
  /// כלומר על הכונן הנייד עצמו. ציבורי כדי שבדיקות יוכלו לפנות אליו ישירות.
  bool isInsideDataDir(String path) {
    final dataDir = p.dirname(stateFilePath);
    final context = Platform.isWindows ? p.windows : p.posix;
    try {
      return context.equals(dataDir, path) ||
          context.isWithin(dataDir, context.normalize(path));
    } catch (_) {
      return false;
    }
  }

  Future<void> saveCustomDbPath(String dbPath) async {
    final json = await _readAll();
    final paths = <String, dynamic>{};
    final existing = json['customDbPaths'];
    if (existing is Map) {
      existing.forEach((key, value) {
        if (key is String && value is String) paths[key] = value;
      });
    }
    paths[currentMachineKey()] = dbPath;
    json['customDbPaths'] = paths;
    // הרשומה הישנה נשארת כמו שהיא: היא עשויה להיות הבחירה של מחשב אחר,
    // ו-[loadCustomDbPath] כבר מסננת אותה לפי המחשב שקורא.
    await _writeAll(json);
  }

  /// ה-release שממנו הגיע תוכן ה-DB המותקן כרגע, או null אם ה-DB לא הותקן
  /// דרך הלאנצ'ר הזה. מאפשר לזהות מסד שפורסם מחדש באותו `db_version` —
  /// ראו `LibraryUpdatePlanner`.
  Future<String?> loadAppliedReleaseTag() async {
    final json = await _readAll();
    final tag = json['appliedReleaseTag'];
    return tag is String && tag.isNotEmpty ? tag : null;
  }

  Future<void> saveAppliedReleaseTag(String tag) async {
    final json = await _readAll();
    json['appliedReleaseTag'] = tag;
    await _writeAll(json);
  }

  /// גרסת ה-DB של כל מחשב שנרשמה בו גרסה, לפי מזהה מחשב. נכתבת **רק** בלחיצה
  /// על "זהה את גרסת המסד שלי" ואחרי עדכון שהוחל כאן — לא בבדיקה שגרתית.
  /// נוסעת עם הכונן, וזה מה שמאפשר למחשב **המקוון** לדעת מאיזו גרסה להוריד
  /// במצב "עדכון אישי", בלי לקרוא שום מסד אצלו.
  ///
  /// **רשומה לכל מחשב, ולא מספר אחד:** מי שלחץ גם במחשב הלא-מקוון (גרסה 20)
  /// וגם במקוון (גרסה 22) היה דורס מספר בודד ל-22, ההורדה הייתה מביאה patches
  /// מ-22 ומעלה, והמחשב הלא-מקוון היה נשאר בלי מסלול. לכן כל מחשב שומר את
  /// שלו, וההורדה יוצאת מהנמוכה שבהן — ראו [lowestKnownDbVersion].
  ///
  /// לא נסמכים על זה לשום החלטה על ה-DB עצמו: שם הגרסה נקראת מהקובץ בפועל.
  Future<Map<String, int>> loadKnownDbVersions() async {
    final json = await _readAll();
    final raw = json['knownDbVersions'];
    if (raw is! Map) return const {};
    final versions = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is int && value > 0) versions[key] = value;
    });
    return versions;
  }

  /// הגרסה הנמוכה מבין כל המחשבים שנרשמו, או `null` כשאין רשומה כלל.
  /// זו הגרסה שהורדה במצב אישי חייבת לצאת ממנה, כדי שתשרת את כולם.
  Future<int?> lowestKnownDbVersion() async {
    final versions = await loadKnownDbVersions();
    if (versions.isEmpty) return null;
    return versions.values.reduce((a, b) => a < b ? a : b);
  }

  /// רושם/מעדכן את הגרסה של [machineKey]. דריסה של אותו מפתח היא הכוונה:
  /// מחשב שמעדכן את המסד שלו מפסיק למשוך את המינימום למטה בהרצה הבאה שלו.
  ///
  /// רשומות מגרסה קודמת של אותו מחשב נמחקות כאן. הן היו ממופתחות בנתיב המסד
  /// המוחלט, ולכן מסד שעבר מקום (בחירה ידנית, שינוי בהגדרות אוצריא) יצר רשומה
  /// **שנייה** לאותו מחשב, הישנה נשארה לנצח, ו"הנמוכה מנצחת" הקפיא את ההורדה
  /// האישית על גרסה שהמחשב מזמן עבר. בדרך זה גם מוציא מהקובץ שנוסע על הכונן
  /// נתיב מוחלט שכולל את שם החשבון.
  Future<void> recordKnownDbVersion(String machineKey, int version) async {
    final json = await _readAll();
    final existing = await loadKnownDbVersions();
    final host = machineKey.split('|').first;
    final versions = <String, dynamic>{};
    existing.forEach((key, value) {
      final sameMachine = key == machineKey || key.startsWith('$host|');
      if (!sameMachine) versions[key] = value;
    });
    versions[machineKey] = version;
    json['knownDbVersions'] = versions;
    await _writeAll(json);
  }
}
