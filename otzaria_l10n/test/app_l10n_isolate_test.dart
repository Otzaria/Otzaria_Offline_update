@TestOn('vm')
library;

import 'dart:isolate';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

/// מתעד בקוד את החוזה שנשבר כבר פעם אחת: `Isolate.run` אינו יורש את
/// [AppL10n]. סטטיים הם פר-איזולט, ולכן מלל שנבנה בתוך איזולט חוזר לעברית
/// אלא אם השפה הועברה כארגומנט ו-`AppL10n.use` נקרא שם ראשון.

/// חייבת להיות פונקציה ברמה העליונה — סגירה שנוגעת בשדה מופע לוכדת `this`
/// והמשלוח לאיזולט נכשל ב-"object is unsendable".
String _languageCodeInIsolate() => AppL10n.language.code;

String _appTitleInIsolate(String languageCode) {
  AppL10n.use(AppLanguage.fromCode(languageCode));
  return AppL10n.strings.shell.appTitle;
}

void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  test('איזולט אינו יורש את השפה — הוא נופל לעברית', () async {
    AppL10n.use(AppLanguage.english);
    expect(AppL10n.language, AppLanguage.english);

    expect(await Isolate.run(_languageCodeInIsolate), AppLanguage.hebrew.code);
  });

  test('העברת השפה כארגומנט + AppL10n.use מחזירה את המלל הנכון', () async {
    for (final language in AppLanguage.values) {
      expect(
        await Isolate.run(() => _appTitleInIsolate(language.code)),
        AppL10n.stringsFor(language).shell.appTitle,
      );
    }
  });

  test('שינוי השפה באיזולט אינו מדליף חזרה לאיזולט הראשי', () async {
    AppL10n.use(AppLanguage.hebrew);
    await Isolate.run(() => _appTitleInIsolate(AppLanguage.english.code));
    expect(AppL10n.language, AppLanguage.hebrew);
  });

  test('stringsFor מחזיר מימוש לכל שפה, ו-language עקבי איתו', () {
    for (final language in AppLanguage.values) {
      final strings = AppL10n.stringsFor(language);
      expect(strings.language, language);
      AppL10n.use(language);
      expect(AppL10n.strings.language, language);
      expect(AppL10n.language, language);
    }
  });
}
