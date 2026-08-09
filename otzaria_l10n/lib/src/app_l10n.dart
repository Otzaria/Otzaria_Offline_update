import 'app_language.dart';
import 'app_strings.dart';
import 'strings_en.dart';
import 'strings_he.dart';

/// השפה הפעילה, כמצב גלובלי יחיד.
///
/// **למה גלובלי ולא הזרקה:** רוב המלל נוצר בחבילות התשתית — בתוך חריגים
/// וב-callbacks של התקדמות — שאין להן `BuildContext` ואינן אמורות לקבל
/// אובייקט שפה בכל בנאי. יש בדיוק לאנצ'ר אחד בתהליך, ולכן ערך יחיד מספיק.
/// הלאנצ'ר מציב אותו מ-`SettingsController` וקורא דרך `AppStringsScope`.
class AppL10n {
  const AppL10n._();

  static AppStrings _strings = const HebrewStrings();

  static AppStrings get strings => _strings;

  static AppLanguage get language => _strings.language;

  static void use(AppLanguage language) {
    _strings = stringsFor(language);
  }

  static AppStrings stringsFor(AppLanguage language) => switch (language) {
        AppLanguage.hebrew => const HebrewStrings(),
        AppLanguage.english => const EnglishStrings(),
      };
}
