/// שפות הממשק בפועל. *הבחירה* בהגדרות היא `AppLanguagePreference` שבלאנצ'ר,
/// וברירת המחדל שלה היא לפי שפת המערכת (ראו [forLanguageCode]).
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

  /// ממפה קוד locale של מערכת ההפעלה (`he`, `he-IL`, `en_US.UTF-8`) לשפה
  /// שהלאנצ'ר מדבר. הנפילה כאן היא לאנגלית ולא לעברית כמו ב-[fromCode]:
  /// מחשב בצרפתית אינו מחשב בעברית, ואנגלית קרובה לו יותר.
  static AppLanguage forLanguageCode(String? languageCode) {
    final code =
        (languageCode ?? '').split(RegExp('[-_.]')).first.toLowerCase();
    if (code == 'iw') return AppLanguage.hebrew; // הקוד הישן לעברית, עוד מדווח
    for (final language in values) {
      if (language.code == code) return language;
    }
    return AppLanguage.english;
  }
}
