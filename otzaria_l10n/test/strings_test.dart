import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  test('ברירת המחדל היא עברית, ולא נגזרת משפת המערכת', () {
    expect(AppL10n.language, AppLanguage.hebrew);
    expect(AppL10n.strings, isA<HebrewStrings>());
  });

  test('AppL10n.use מחליף את כל המחרוזות', () {
    AppL10n.use(AppLanguage.english);
    expect(AppL10n.strings.shell.appTitle, 'Otzaria Updates');
    AppL10n.use(AppLanguage.hebrew);
    expect(AppL10n.strings.shell.appTitle, 'עדכוני אוצריא');
  });

  test('קוד השפה נשמר ונקרא חזרה, וערך לא מוכר נופל לעברית', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromCode(language.code), language);
    }
    expect(AppLanguage.fromCode('fr'), AppLanguage.hebrew);
    expect(AppLanguage.fromCode(null), AppLanguage.hebrew);
    expect(AppLanguage.hebrew.isRtl, isTrue);
    expect(AppLanguage.english.isRtl, isFalse);
  });

  test('locale של מערכת ההפעלה ממופה לשפה שהלאנצ\'ר מדבר', () {
    for (final code in ['he', 'he-IL', 'he_IL.UTF-8', 'HE', 'iw', 'iw-IL']) {
      expect(AppLanguage.forLanguageCode(code), AppLanguage.hebrew,
          reason: code);
    }
    for (final code in ['en', 'en-US', 'en_GB.UTF-8']) {
      expect(AppLanguage.forLanguageCode(code), AppLanguage.english,
          reason: code);
    }
    for (final code in ['fr', 'ru-RU', 'yi', '', null]) {
      expect(AppLanguage.forLanguageCode(code), AppLanguage.english,
          reason: '$code');
    }
  });
}
