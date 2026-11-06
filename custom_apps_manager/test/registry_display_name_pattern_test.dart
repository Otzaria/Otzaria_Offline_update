import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

void main() {
  String patternOf(String displayName) =>
      RegistryDisplayNamePattern.fromDisplayName(displayName);

  group('זיהוי לפי שמות מלאים בלי כללים שנלמדו', () {
    test('שם עברי ושם הריפו הם זהויות חלופיות', () {
      final pattern = RegistryDisplayNamePattern.forAppNames(['זית', 'Zayit'])!;

      for (final displayName in ['זית', 'ZAYIT', 'Zayit 1.2 (x64)', 'זית v2']) {
        expect(pattern.hasMatch(displayName), isTrue, reason: displayName);
      }
      for (final displayName in ['זיתים', 'Zayit Pro', 'Other Zayit']) {
        expect(pattern.hasMatch(displayName), isFalse, reason: displayName);
      }
    });

    test('הרווחים סביב הזהויות נחתכים', () {
      final pattern = RegistryDisplayNamePattern.forAppNames(['  Zayit  '])!;

      expect(pattern.hasMatch('Zayit'), isTrue);
      expect(pattern.hasMatch('Zayit\tv1.2 beta'), isTrue);
      expect(pattern.hasMatch('Zayit vNext'), isFalse);
      expect(pattern.hasMatch('Zayit(x64)'), isFalse);
    });

    test('תווי רגקס בזהות מותאמים כלשונם', () {
      final pattern =
          RegistryDisplayNamePattern.forAppNames(['Notepad++ (x64)', 'A.B'])!;

      expect(pattern.hasMatch('Notepad++ (x64) 8.6'), isTrue);
      expect(pattern.hasMatch('NotepadXX (x64) 8.6'), isFalse);
      expect(pattern.hasMatch('A.B'), isTrue);
      expect(pattern.hasMatch('AxB'), isFalse);
    });

    test('איחוד זהויות אינו בוחר בין רישומים תואמים', () {
      final pattern = RegistryDisplayNamePattern.forAppNames(['Foo', 'Bar'])!;
      final names = ['Foo 1.0', 'Bar 2.0', 'Other'];

      expect(names.where(pattern.hasMatch), ['Foo 1.0', 'Bar 2.0']);
    });

    test('אין זהויות שמישות — אין תבנית', () {
      expect(RegistryDisplayNamePattern.forAppNames([]), isNull);
      expect(RegistryDisplayNamePattern.forAppNames(['', ' ', '7z', 'אב']),
          isNull);
      final pattern =
          RegistryDisplayNamePattern.forAppNames(['', '7z', 'Zayit'])!;
      expect(pattern.hasMatch('7z'), isFalse);
      expect(pattern.hasMatch('Zayit'), isTrue);
    });

    test('Git אינו מתאים לתוכנה אחרת ששמה מכיל אותו', () {
      final pattern = RegistryDisplayNamePattern.forAppNames(['Git'])!;

      expect(pattern.hasMatch('Git'), isTrue);
      expect(pattern.hasMatch('git V2.44.0.windows.1'), isTrue);
      for (final displayName in [
        'GitHub Desktop',
        'Git Extensions',
        'Digital'
      ]) {
        expect(pattern.hasMatch(displayName), isFalse, reason: displayName);
      }
    });

    test('שם קצר מהזהות אינו מתאים', () {
      final pattern = RegistryDisplayNamePattern.forAppNames(['Foobar'])!;

      expect(pattern.hasMatch('Foo'), isFalse);
      expect(pattern.hasMatch('Foo 1.0'), isFalse);
      expect(pattern.hasMatch('Foobar 2.0'), isTrue);
    });
  });

  group('התבנית שורדת עדכון גרסה', () {
    test('הגרסה נחתכת, ולכן הגרסה הבאה עדיין מתאימה', () {
      final pattern = patternOf('MyApp 1.4.2');

      expect(
          RegistryDisplayNamePattern.matches(pattern, 'MyApp 1.4.2'), isTrue);
      expect(RegistryDisplayNamePattern.matches(pattern, 'MyApp 1.5'), isTrue);
      expect(
          RegistryDisplayNamePattern.matches(pattern, 'MyApp 2.0.0'), isTrue);
    });

    test('גם `v` לפני המספר נחתך', () {
      expect(
        RegistryDisplayNamePattern.matches(
            patternOf('MyApp v1.4.2'), 'MyApp v2'),
        isTrue,
      );
    });

    test('מה שבא אחרי הגרסה נחתך גם הוא', () {
      final pattern = patternOf('Python 3.12.1 (64-bit)');
      expect(
          RegistryDisplayNamePattern.matches(pattern, 'Python 3.13.0'), isTrue);
    });

    test('DisplayName בעברית — הגרסה נחתכת בדיוק כמו באנגלית', () {
      final pattern = patternOf('אוצריא גירסה 0.9.96');
      expect(
        RegistryDisplayNamePattern.matches(pattern, 'אוצריא גירסה 0.10.0'),
        isTrue,
      );
    });
  });

  // זו החצי השנייה של הבאג: `DisplayName` אמיתי מכיל תווי רגקס.
  group('תווי רגקס בשם אינם שוברים דבר', () {
    test('סוגריים ונקודות מוברחים', () {
      final pattern = patternOf('Notepad++ (64-bit x64)');

      expect(RegistryDisplayNamePattern.compile(pattern), isNotNull);
      expect(
        RegistryDisplayNamePattern.matches(pattern, 'Notepad++ (64-bit x64)'),
        isTrue,
      );
      // בלי ההברחה, `.` היה תופס כל תו.
      expect(
        RegistryDisplayNamePattern.matches(pattern, 'NotepadXX (64-bit x64)'),
        isFalse,
      );
    });
  });

  group('ספרות שאינן גרסה נשארות בשם', () {
    // אותו כלל שמונע מתבנית של x64 להתאים ל-x86 ב-`GithubAssetPattern`.
    test('ספרה שדבוקה לאות אינה גרסה', () {
      final pattern = patternOf('7-Zip 24.09');
      expect(
          RegistryDisplayNamePattern.matches(pattern, '7-Zip 25.00'), isTrue);
      expect(
          RegistryDisplayNamePattern.matches(pattern, '8-Zip 25.00'), isFalse);
    });

    test('שם שכולו בלי גרסה נשמר במלואו', () {
      final pattern = patternOf('Microsoft Edge WebView2 Runtime');
      expect(
        RegistryDisplayNamePattern.matches(
            pattern, 'Microsoft Edge WebView2 Runtime'),
        isTrue,
      );
    });
  });

  // קידומת היא "מתחיל ב-", ובלי הגבלה היא הייתה תופסת תוכנות אחרות.
  group('הקידומת אינה בולעת שמות אחרים', () {
    test('Git אינו תופס את GitHub Desktop', () {
      final pattern = patternOf('Git 2.43.0');
      expect(RegistryDisplayNamePattern.matches(pattern, 'Git 2.44.0'), isTrue);
      expect(
        RegistryDisplayNamePattern.matches(pattern, 'GitHub Desktop 3.3.0'),
        isFalse,
      );
    });

    test('קידומת קצרה מדי — נשמר השם השלם ולא קידומת שתתפוס הכול', () {
      // `A` לבדה הייתה תבנית שמתאימה לכל תוכנה שמתחילה ב-A.
      final pattern = patternOf('A 1.0');
      expect(RegistryDisplayNamePattern.matches(pattern, 'A 1.0'), isTrue);
      expect(
          RegistryDisplayNamePattern.matches(pattern, 'Acrobat 1.0'), isFalse);
    });
  });

  group('הידור בטוח', () {
    // ⚠️ הבאג שהיה: `RegExp(...)` ישיר בתוך הזיהוי זרק על תבנית פגומה,
    // ה-throw נבלע, והתוכנה דיווחה "אינה מותקנת" לנצח.
    test('תבנית פגומה מחזירה null ואינה זורקת', () {
      expect(RegistryDisplayNamePattern.compile('MyApp ('), isNull);
      expect(RegistryDisplayNamePattern.matches('MyApp (', 'MyApp'), isFalse);
    });

    test('תבנית ריקה או null אינה מתאימה לכלום', () {
      expect(RegistryDisplayNamePattern.compile(''), isNull);
      expect(RegistryDisplayNamePattern.compile(null), isNull);
      expect(patternOf('   '), isEmpty);
    });

    test('ההשוואה אינה תלוית רישיות', () {
      expect(
        RegistryDisplayNamePattern.matches(patternOf('MyApp 1.0'), 'myapp 2.0'),
        isTrue,
      );
    });
  });

  test('ההמשך העברי חוסם: "קול" אינו מתאים ל"קולמוס"', () {
    final pattern = RegistryDisplayNamePattern.fromDisplayName('קול 2.1');
    expect(RegistryDisplayNamePattern.matches(pattern, 'קולמוס 3'), isFalse);
    expect(RegistryDisplayNamePattern.matches(pattern, 'קול 2.4'), isTrue);
  });
}
