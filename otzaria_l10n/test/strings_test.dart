import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

/// דוגמית מייצגת מכל סעיף. מטרתה לתפוס את הטעות הקלה ביותר לעשות כאן:
/// מימוש אנגלי שהועתק מהעברי ונשאר בעברית.
List<String> _sample(AppStrings s) => [
      s.common.confirm,
      s.shell.appTitle,
      s.home.title,
      s.appScreen.stateCardTitle,
      s.libraryScreen.title,
      s.settings.title,
      s.plugins.syncButton,
      s.setupError.title,
      s.units.bytes(5),
      s.libraryDomain.updateCancelled,
      s.appDomain.mirrorEmptyRunDownload,
      s.pluginsDomain.syncDone,
    ];

final _hebrewLetter = RegExp(r'[֐-׿]');

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

  test('אין אותיות עבריות במימוש האנגלי', () {
    // חוץ מבורר השפה עצמו, שמציג כל שפה בשמה שלה.
    const en = EnglishStrings();
    expect(en.settings.languageHebrew, 'עברית');
    for (final value in _sample(en)) {
      expect(value, isNot(matches(_hebrewLetter)), reason: value);
    }
  });

  test('כל סעיף מנוסח אחרת בשתי השפות', () {
    final he = _sample(const HebrewStrings());
    final en = _sample(const EnglishStrings());
    for (var i = 0; i < he.length; i++) {
      expect(en[i], isNot(he[i]));
    }
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
}
