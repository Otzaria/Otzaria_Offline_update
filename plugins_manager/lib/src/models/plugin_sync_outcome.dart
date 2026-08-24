import 'plugin_catalog.dart';

/// מה סנכרון אחד באמת עשה. הקטלוג לבדו לא ענה על זה: הוא נראה זהה בין
/// "הכול כבר היה מעודכן" לבין "ניסינו והכול נכשל".
class PluginSyncOutcome {
  const PluginSyncOutcome({
    required this.catalog,
    required this.fetched,
    required this.skipped,
    this.failed = const [],
    this.incompatible = const [],
  });

  final PluginCatalog catalog;

  /// כמה תוספים היה בהם משהו להוריד, ולכן טופלו בפועל.
  final int fetched;

  /// כמה דולגו לגמרי — כבר מעודכנים במראה, בלי לגעת ברשת.
  final int skipped;

  /// שמות התוספים שקובץ ההתקנה שלהם התבקש ולא ירד. המראה עדיין חסרה
  /// אותם, ולכן בדיקת הרשת הבאה תדווח עליהם שוב — וזה נכון.
  final List<String> failed;

  /// תוספים שאין להם אף בילד שירוץ על גרסת אוצריא שהכונן נושא, ולכן לא
  /// ירד להם קובץ. **לא כשל** ולא מוצג למשתמש — נכתב ליומן בלבד, כדי
  /// שיהיה אפשר לענות על "למה התוסף הזה לא בכונן".
  /// כל פריט הוא `שם התוסף (דורש X)`.
  final List<String> incompatible;

  bool get hasFailures => failed.isNotEmpty;
}
