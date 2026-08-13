/// כיצד מזהים שהתוכנה כבר מותקנת על **המחשב הזה**, ומה הגרסה שלה.
///
/// הזיהוי חייב להיעשות מחדש בכל מחשב: קובצי המצב יושבים ב-`OtzariaData`
/// שעל הכונן הנייד ונוסעים איתו, ולכן "מותקן" שנרשם במחשב אחד אינו עדות
/// לכלום במחשב הבא — אותו מוקש בדיוק כמו `otzaria_install_state.json`.
class AppDetectRules {
  const AppDetectRules({
    this.exeName,
    this.registryDisplayName,
    this.dirs = const [],
  });

  /// שם קובץ ההרצה, למשל `myapp.exe`. ממנו נקראת הגרסה המותקנת
  /// (ProductVersion ב-Windows), וממנו גם מופעלת התוכנה.
  final String? exeName;

  /// ביטוי רגולרי שמושווה ל-`DisplayName` ברג'יסטרי ההסרה. זה המסלול
  /// האמין ביותר בווינדוס: הוא מוצא התקנה גם בתיקייה שאיש לא ניחש.
  final String? registryDisplayName;

  /// תיקיות נוספות לחיפוש, כשאין רישום ברג'יסטרי.
  final List<String> dirs;

  /// האם יש כאן בכלל במה להשתמש. תוסף בלי שום כלל זיהוי יכול להתקין, אבל
  /// לעולם לא ידע מה מותקן — והממשק חייב לומר זאת ולא להציג "לא מותקן".
  bool get isEmpty =>
      (exeName == null || exeName!.isEmpty) &&
      (registryDisplayName == null || registryDisplayName!.isEmpty) &&
      dirs.isEmpty;

  factory AppDetectRules.fromJson(Map<String, dynamic> json) => AppDetectRules(
        exeName: json['exeName'] as String?,
        registryDisplayName: json['registryDisplayName'] as String?,
        dirs: (json['dirs'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        if (exeName != null) 'exeName': exeName,
        if (registryDisplayName != null)
          'registryDisplayName': registryDisplayName,
        if (dirs.isNotEmpty) 'dirs': dirs,
      };
}
