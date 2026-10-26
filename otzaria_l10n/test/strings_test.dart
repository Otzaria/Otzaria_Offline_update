import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  test('ברירת המחדל היא עברית, ולא נגזרת משפת המערכת', () {
    expect(AppL10n.language, AppLanguage.hebrew);
    expect(AppL10n.strings, isA<HebrewStrings>());
  });

  test('נוסח החיפוש מבהיר את גבולות הסתרת המידע האישי', () {
    expect(const HebrewStrings().libraryDomain.semanticConsentText,
        contains('פרטים אישיים אחרים עלולים להישלח'));
    expect(const EnglishStrings().libraryDomain.semanticConsentText,
        contains('other personal details may still be sent'));
  });

  test('"באתר יש חדש" ברכיב כבוי — יחיד, רבים ורשימה', () {
    const he = HebrewStrings();
    const en = EnglishStrings();
    expect(
      he.guide.syncOffOnlyNote(app: false, library: true, plugins: false),
      'באתר יש גרסה חדשה של ספריית אוצריא, אבל ההורדה שלה כבויה בהגדרות.',
    );
    expect(
      he.guide.syncOffOnlyNote(app: false, library: false, plugins: true),
      contains('ההורדה שלהם'),
    );
    expect(
      he.guide.syncOffOnlyNote(
        app: false,
        library: true,
        plugins: false,
        libraryFilesOnly: true,
      ),
      'באתר יש קבצים חדשים לספריית אוצריא, אבל ההורדה שלהם כבויה בהגדרות.',
    );
    expect(
      en.guide.syncOffOnlyNote(
        app: false,
        library: true,
        plugins: false,
        libraryFilesOnly: true,
      ),
      'There are new Otzaria library files online, but their download is turned off '
      'in the settings.',
    );
    expect(
      he.guide.syncOffOnlyNote(app: true, library: true, plugins: true),
      'באתר יש חדש בתוכנה, בספריית אוצריא ובתוספים, אבל ההורדה שלהם כבויה בהגדרות.',
    );
    expect(
      en.guide.syncOffOnlyNote(app: true, library: true, plugins: false),
      'There is something new online for the program and the Otzaria library, but '
      'their download is turned off in the settings.',
    );
  });

  test('כפתור השער אינו "Enter" — שם המקש, לא פעולה', () {
    expect(const EnglishStrings().saferMode.enterButton, 'Unlock');
    expect(const HebrewStrings().saferMode.enterButton, 'כניסה');
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
