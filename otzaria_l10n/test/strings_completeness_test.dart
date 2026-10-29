@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:test/test.dart';

/// סורק את *כל* חוזה [AppStrings] ברפלקציה, במקום לדגום ידנית.
/// כך שדה חדש נבדק מעצמו, בלי שמישהו יזכור להוסיף אותו לרשימה כאן.
///
/// רפלקציה עובדת פה כי זו חבילת Dart טהורה שרצה ב-VM; ב-`flutter test`
/// `dart:mirrors` אינו זמין, ולכן הבדיקה הזו חיה דווקא בחבילה הזו.

/// ערך יחיד שנדגם: הנתיב בחוזה, הטקסט שחזר, והארגומנטים שהוזרקו.
class _Sampled {
  _Sampled(this.path, this.value, this.args);

  final String path;
  final String value;
  final List<Object?> args;
}

/// ערכי-בדיקה ייחודיים לכל מיקום, כדי שאפשר יהיה לזהות איזה ארגומנט נבלע.
/// המספרים גדולים מ-1 בכוונה — כמה שדות באנגלית מסתעפים על יחיד/רבים.
Object _sentinel(TypeMirror type, int index) {
  final name = MirrorSystem.getName(type.simpleName);
  return switch (name) {
    'String' => 'ARG$index',
    'int' => 1000 + index,
    'bool' => true,
    'List' => ['LIST${index}A', 'LIST${index}B'],
    _ => throw StateError(
        'טיפוס פרמטר לא מוכר בחוזה: $name. הוסיפו לו ערך-בדיקה כאן.'),
  };
}

/// הסעיפים של [AppStrings] — כל getter שמחזיר טיפוס `*Strings`.
Iterable<MethodMirror> _sectionGetters() => reflectClass(AppStrings)
    .declarations
    .values
    .whereType<MethodMirror>()
    .where(
      (d) =>
          d.isGetter &&
          d.returnType is ClassMirror &&
          MirrorSystem.getName(d.returnType.simpleName).endsWith('Strings'),
    );

/// כל חברי-הסעיף שמחזירים `String` — getters ומתודות כאחד.
Iterable<MethodMirror> _stringMembers(ClassMirror section) =>
    section.declarations.values.whereType<MethodMirror>().where(
          (m) =>
              !m.isConstructor &&
              !m.isStatic &&
              MirrorSystem.getName(m.returnType.simpleName) == 'String',
        );

/// דוגם את כל החוזה על מימוש אחד. `overrides` מחליף ארגומנט בודד לפי
/// אינדקס — כך אותה הליכה משמשת גם לבדיקת ענפי ה-null.
Map<String, _Sampled> _walk(AppStrings strings) {
  final out = <String, _Sampled>{};
  final root = reflect(strings);

  for (final sectionGetter in _sectionGetters()) {
    final sectionName = MirrorSystem.getName(sectionGetter.simpleName);
    final sectionType = sectionGetter.returnType as ClassMirror;
    final section = root.getField(sectionGetter.simpleName);

    for (final member in _stringMembers(sectionType)) {
      final path = '$sectionName.${MirrorSystem.getName(member.simpleName)}';
      if (member.isGetter) {
        out[path] = _Sampled(
          path,
          section.getField(member.simpleName).reflectee as String,
          const [],
        );
        continue;
      }
      final (positional, named, args) = _buildArgs(member);
      out[path] = _Sampled(
        path,
        section.invoke(member.simpleName, positional, named).reflectee
            as String,
        args,
      );
    }
  }
  return out;
}

/// בונה ערכי-בדיקה לפי חתימת המתודה, ומחזיר גם רשימה שטוחה לבדיקת שיקוף.
(List<Object?>, Map<Symbol, Object?>, List<Object?>) _buildArgs(
  MethodMirror member, {
  int? nullAt,
}) {
  final positional = <Object?>[];
  final named = <Symbol, Object?>{};
  final flat = <Object?>[];

  for (var i = 0; i < member.parameters.length; i++) {
    final parameter = member.parameters[i];
    final value = i == nullAt ? null : _sentinel(parameter.type, i);
    flat.add(value);
    if (parameter.isNamed) {
      named[parameter.simpleName] = value;
    } else {
      positional.add(value);
    }
  }
  return (positional, named, flat);
}

final _hebrewLetter = RegExp(r'[֐-׿]');

/// חריגים מכוונים, ולא ליקויי תרגום. רשימה מפורשת היא מה שהופך את
/// הבדיקות למשמעותיות: שדה שיישכח בלי תרגום ייפול, ולא ייבלע ברעש.
const _sameInBothLanguages = {
  'plugins.reportEmailPlaceholder', // Example email address, as on the website.
  'common.emptyValue', // מקף — אין מה לתרגם
  'settings.languageHebrew', // כל שפה מוצגת בשמה שלה
  'settings.languageEnglish',
  'plugins.localFileDescription', // מחרוזת פורמט טהורה: "קובץ (גודל)"
  'plugins.ratingBadge', // מחרוזת פורמט טהורה: "4.5 (128)"
  // מחרוזת פורמט טהורה: שם שלב (כבר מתורגם) ולצידו mm:ss.
  'libraryDomain.applyStageElapsed',
};
const _hebrewLettersInEnglish = {'settings.languageHebrew'};

/// ארגומנטים שבוחרים ניסוח ואינם מוצגים — בדיוק כמו בוליאני. המפתח הוא
/// `נתיב#אינדקס`, כדי שהפטור יחול על הפרמטר האחד ולא על השדה כולו.
const _selectorArgs = {
  'libraryDomain.applyPatchStage#0',
  'libraryDomain.applyVerifyStage#0',
  'units.longDate#1', // החודש מוצג בשמו
};
const _noHebrewLettersInHebrew = {
  'plugins.reportEmailPlaceholder',
  'common.emptyValue',
  // שם המחשב כפי שהוא, רק מבודד בכיוון.
  'settings.personalMachineName',
  // יחידות הגודל לטיניות גם בעברית, כמו במוקאפ — רק מבודדות בכיוון.
  'units.kilobytes',
  'units.megabytes',
  'units.gigabytes',
  'units.perSecond',
  'libraryDomain.applyStageElapsed',
  'settings.languageEnglish',
  'plugins.localFileDescription',
  'plugins.ratingBadge',
};

/// מונים שהיחיד שלהם מנוסח במילים ("תוסף אחד"), לפי `plural`. ב-1 הפלט חייב
/// להיות שונה מהפלט ב-2 ובלי אף מונה כמספר; ב-0, 2 ו-1000 הספרה עדיין חובה.
/// חריג שאינו רשום כאן נופל — כך מונה שנבלע עדיין נתפס.
const _spelledOne = {
  'task.minutesLeft#0',
  'task.donePluginsValue#0',
  'task.pluginsWaiting#0',
  'pages.repSendStoredButton#0',
  'task.libraryBody#0',
  'pages.libFullMeta#0',
  'plugins.updatesAvailable#0',
  'plugins.updatesSentSnack#0',
  'plugins.updateAllPartlySentSnack#0',
  'plugins.updateAllStoppedSnack#0',
  'libraryScreen.personalCardThisAndOthers#0',
  'libraryScreen.personalCardOthers#0',
  'libraryScreen.personalDownloadItem#0',
  'libraryScreen.personalDownloadNote#0',
};

/// הזוגי העברי ("שתי דקות") — אותו כלל ב-2, בעברית בלבד.
const _spelledTwoInHebrew = {
  'task.minutesLeft#0',
  'task.donePluginsValue#0',
  'task.pluginsWaiting#0',
  'task.libraryBody#0',
  'pages.libFullMeta#0',
  'libraryScreen.personalCardThisAndOthers#0',
  'libraryScreen.personalCardOthers#0',
  'libraryScreen.personalDownloadItem#0',
  'libraryScreen.personalDownloadNote#0',
};

/// המונה כמספר עומד בפני עצמו — "1" בתוך "ARG1" אינו נחשב.
bool _hasNumber(String value, int n) =>
    RegExp('(?<![\\w.])$n(?![\\w.])').hasMatch(value);

void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  final he = _walk(const HebrewStrings());
  final en = _walk(const EnglishStrings());

  test('הסורק אכן מוצא את כל החוזה, ולא עובר בשקט על כלום', () {
    // הסכנה בבדיקת רפלקציה היא שתעבור מבלי לבדוק דבר.
    expect(_sectionGetters(), hasLength(greaterThanOrEqualTo(12)));
    expect(he, hasLength(greaterThanOrEqualTo(400)));
    expect(en.keys, unorderedEquals(he.keys));
  });

  test('אין שדה ריק באף שפה', () {
    for (final sampled in [...he.values, ...en.values]) {
      expect(sampled.value.trim(), isNotEmpty, reason: sampled.path);
    }
  });

  test('כל שדה מנוסח אחרת בשתי השפות', () {
    for (final path in he.keys) {
      if (_sameInBothLanguages.contains(path)) {
        expect(en[path]!.value, he[path]!.value, reason: '$path — חריג מוכר');
        continue;
      }
      expect(en[path]!.value, isNot(he[path]!.value), reason: path);
    }
  });

  test('אין אותיות עבריות במימוש האנגלי', () {
    for (final sampled in en.values) {
      final hasHebrew = _hebrewLetter.hasMatch(sampled.value);
      expect(
        hasHebrew,
        _hebrewLettersInEnglish.contains(sampled.path),
        reason: '${sampled.path} = ${sampled.value}',
      );
    }
  });

  test('אין מחרוזת עברית שנשארה באנגלית', () {
    for (final sampled in he.values) {
      final hasHebrew = _hebrewLetter.hasMatch(sampled.value);
      expect(
        hasHebrew,
        !_noHebrewLettersInHebrew.contains(sampled.path),
        reason: '${sampled.path} = ${sampled.value}',
      );
    }
  });

  test('כל ארגומנט מופיע בטקסט, בשתי השפות', () {
    // תרגום שבולע ערך משוקלל הוא באג שקט: המשתמש רואה משפט תקין בלי המספר.
    for (final sampled in [...he.values, ...en.values]) {
      for (var i = 0; i < sampled.args.length; i++) {
        final arg = sampled.args[i];
        if (arg is bool) continue; // בוליאני בוחר ניסוח, אינו מוצג
        final expected = arg is List ? arg.first as String : '$arg';
        expect(
          sampled.value.contains(expected),
          !_selectorArgs.contains('${sampled.path}#$i'),
          reason: '${sampled.path} = ${sampled.value}',
        );
      }
    }
  });

  test('ענפי ה-null של פרמטרים אופציונליים מחזירים טקסט תקין', () {
    for (final strings in [const HebrewStrings(), const EnglishStrings()]) {
      final root = reflect(strings);
      for (final sectionGetter in _sectionGetters()) {
        final sectionType = sectionGetter.returnType as ClassMirror;
        final section = root.getField(sectionGetter.simpleName);
        for (final member in _stringMembers(sectionType)) {
          if (member.isGetter) continue;
          for (var i = 0; i < member.parameters.length; i++) {
            final (positional, named, _) = _buildArgs(member, nullAt: i);
            String value;
            try {
              value = section
                  .invoke(member.simpleName, positional, named)
                  .reflectee as String;
            } on TypeError {
              continue; // פרמטר לא-null — אין ענף כזה לבדוק
            }
            expect(
              value.trim(),
              isNotEmpty,
              reason: '${MirrorSystem.getName(sectionGetter.simpleName)}.'
                  '${MirrorSystem.getName(member.simpleName)} עם null במקום $i',
            );
          }
        }
      }
    }
  });

  test('שדות עם מונה מחזירים טקסט תקין גם ב-0, 1, 2 ו-1000', () {
    // ריבוי באנגלית מסתעף על 1; אפס ואחד הם בדיוק המקומות שנשכחים.
    for (final strings in [const HebrewStrings(), const EnglishStrings()]) {
      final hebrew = strings is HebrewStrings;
      final root = reflect(strings);
      for (final sectionGetter in _sectionGetters()) {
        final sectionType = sectionGetter.returnType as ClassMirror;
        final section = root.getField(sectionGetter.simpleName);
        for (final member in _stringMembers(sectionType)) {
          if (member.isGetter) continue;
          final hasInt = member.parameters.any(
            (p) => MirrorSystem.getName(p.type.simpleName) == 'int',
          );
          if (!hasInt) continue;
          final path = '${MirrorSystem.getName(sectionGetter.simpleName)}.'
              '${MirrorSystem.getName(member.simpleName)}';

          String valueAt(int count) {
            final positional = <Object?>[];
            final named = <Symbol, Object?>{};
            for (var i = 0; i < member.parameters.length; i++) {
              final parameter = member.parameters[i];
              final isInt =
                  MirrorSystem.getName(parameter.type.simpleName) == 'int';
              final value = isInt ? count : _sentinel(parameter.type, i);
              if (parameter.isNamed) {
                named[parameter.simpleName] = value;
              } else {
                positional.add(value);
              }
            }
            return section
                .invoke(member.simpleName, positional, named)
                .reflectee as String;
          }

          final byCount = {
            for (final n in [0, 1, 2, 1000]) n: valueAt(n)
          };
          for (final MapEntry(key: count, value: value) in byCount.entries) {
            final reason = '$path($count) = $value';
            expect(value.trim(), isNotEmpty, reason: reason);
            final spelled = switch (count) {
              1 => _spelledOne.any((key) => key.startsWith('$path#')),
              2 => hebrew &&
                  _spelledTwoInHebrew.any((key) => key.startsWith('$path#')),
              _ => false,
            };
            if (!spelled) {
              expect(value, contains('$count'), reason: reason);
              continue;
            }
            final others = byCount.keys.where((n) => n != count);
            for (final other in others) {
              expect(value, isNot(byCount[other]), reason: reason);
            }
            for (final n in byCount.keys) {
              expect(_hasNumber(value, n), isFalse, reason: reason);
            }
          }
        }
      }
    }
  });
}
