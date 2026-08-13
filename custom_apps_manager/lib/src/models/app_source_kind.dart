/// מאיפה מגיעה חבילת ההתקנה של תוכנה נוספת.
enum AppSourceKind {
  /// ריפו GitHub. זה המסלול הראשי: הוא מה שנותן לתוכנה הנוספת להתנהג כמו
  /// אוצריא והספרייה — בדיקה, "יש גרסה חדשה", והורדה אל הכונן.
  github('github'),

  /// המשתמש מספק את קובץ ההתקנה בעצמו. לתוכנה שאינה ב-GitHub, ואין לה שום
  /// מקור גרסאות אוטומטי — מצב נפוץ מאוד אצל הקהל של הלאנצ'ר. "עדכון"
  /// פירושו שהמשתמש הכניס קובץ חדש יותר.
  manual('manual');

  const AppSourceKind(this.id);

  final String id;

  static AppSourceKind? byId(String id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  static List<String> get allIds => [for (final k in values) k.id];
}
