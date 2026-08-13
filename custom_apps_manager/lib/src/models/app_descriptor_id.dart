/// אימות המזהה של תוסף תוכנה.
///
/// המזהה **הופך לשם תיקייה** תחת `OtzariaData/apps/` ותחת `mirror/apps/`,
/// ולכן הוא לא סתם מחרוזת: מזהה כמו `../../windows` היה כותב מחוץ לתיקיית
/// הנתונים. התוסף מגיע מגורם חיצוני, ולכן האימות הזה הוא גבול אמיתי ולא
/// ניקיון.
abstract final class AppDescriptorId {
  /// אותיות קטנות, ספרות, נקודה, מקף וקו תחתון בלבד — קבוצה שבטוחה כשם
  /// תיקייה בשתי הפלטפורמות.
  static final RegExp _allowed = RegExp(r'^[a-z0-9._-]+$');

  static const int maxLength = 64;

  /// שמות התקנים שמורים בווינדוס. תיקייה בשם כזה פשוט אינה ניתנת ליצירה,
  /// והכשל מגיע מאוחר ובלי הסבר — עדיף לפסול כאן.
  static const Set<String> _windowsReserved = {
    'con',
    'prn',
    'aux',
    'nul',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
  };

  /// `true` אם [id] בטוח לשימוש כשם תיקייה וכמפתח.
  static bool isValid(String id) {
    if (id.isEmpty || id.length > maxLength) return false;
    if (!_allowed.hasMatch(id)) return false;
    // `.` ו-`..` הם התיקייה עצמה וההורה שלה; `..` בתוך המחרוזת הוא טיפוס
    // למעלה גם כשהוא מוקף בתווים חוקיים.
    if (id.contains('..')) return false;
    if (id.startsWith('.') || id.endsWith('.')) return false;
    // ווינדוס מתעלמת מסיומת בבדיקת שם שמור, ולכן `con.exe` שמור כמו `con`.
    final base = id.split('.').first;
    if (_windowsReserved.contains(base)) return false;
    return true;
  }
}
