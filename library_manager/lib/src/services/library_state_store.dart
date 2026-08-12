import 'dart:convert';
import 'dart:io';

/// שומר/טוען הגדרות מתמשכות של מודול הספרייה: נתיב DB מותאם אישית (למקרה
/// שהמשתמש הצביע ידנית על תיקיית ספרייה שאינה ברירת המחדל של אוצריא), וכן
/// נתיב "מראה מקומית" (offline) אם המשתמש בחר לעדכן מתיקייה מקומית/USB
/// במקום מהענן. קובץ state נפרד מזה של [OtzariaStateStore] — שני מודולים
/// שונים, שני קבצים.
class LibraryStateStore {
  const LibraryStateStore(this.stateFilePath);

  final String stateFilePath;

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

  /// מחזיר null אם לא הוגדר נתיב מותאם אישית (או שהקובץ פגום/לא קריא —
  /// מתייחסים לזה כ"לא הוגדר" ולא זורקים).
  Future<String?> loadCustomDbPath() async {
    final json = await _readAll();
    return json['customDbPath'] as String?;
  }

  Future<void> saveCustomDbPath(String dbPath) async {
    final json = await _readAll();
    json['customDbPath'] = dbPath;
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
  Future<void> recordKnownDbVersion(String machineKey, int version) async {
    final json = await _readAll();
    final versions = <String, dynamic>{
      ...await loadKnownDbVersions(),
      machineKey: version,
    };
    json['knownDbVersions'] = versions;
    await _writeAll(json);
  }
}
