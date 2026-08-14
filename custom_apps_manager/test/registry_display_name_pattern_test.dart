import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

void main() {
  String patternOf(String displayName) =>
      RegistryDisplayNamePattern.fromDisplayName(displayName);

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
}
