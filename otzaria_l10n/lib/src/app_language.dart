/// שפות הממשק. עברית היא ברירת המחדל ואינה תלויה בשפת המערכת — רוב
/// המשתמשים הם דוברי עברית, ומעבר לאנגלית הוא בחירה מפורשת בהגדרות.
enum AppLanguage {
  hebrew('he', isRtl: true),
  english('en', isRtl: false);

  const AppLanguage(this.code, {required this.isRtl});

  /// קוד ISO-639 — גם המפתח שנשמר בקובץ ההגדרות.
  final String code;

  final bool isRtl;

  /// קורא ערך שנשמר בהגדרות. ערך לא מוכר נופל לעברית, כמו כל שאר השדות.
  static AppLanguage fromCode(Object? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return AppLanguage.hebrew;
  }
}
