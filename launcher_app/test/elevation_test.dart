import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/elevation.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

/// הזיהוי כאן הוא מה שמפעיל את ההצעה "להפעיל כמנהל" (הצעה #25 בגיטהאב, אבל
/// לתקלה אחרת: אוצריא מותקנת ב-`Program Files` והלאנצ'ר אינו מורשה לכתוב
/// שם). זיהוי שגוי בשני הכיוונים מזיק: הצעה מיותרת אחרי כל תקלה, או שגיאה
/// גולמית של מערכת ההפעלה בלי לומר מה לעשות.
void main() {
  tearDown(() => AppL10n.use(AppLanguage.hebrew));

  group('Elevation.isAccessDenied', () {
    test('סירוב הרשאה של מערכת ההפעלה מזוהה', () {
      final denied = FileSystemException(
        'Access is denied',
        r'C:\Program Files\Otzaria\seforim.db',
        OSError('Access is denied', Platform.isWindows ? 5 : 13),
      );

      expect(Elevation.isAccessDenied(denied), isTrue);
    });

    test('קובץ בשימוש אינו סירוב הרשאה — הרמה לא תעזור לו', () {
      // 32 = ERROR_SHARING_VIOLATION. אוצריא פתוחה על המסד היא בדיוק זה,
      // ולהציע עליה "הפעל כמנהל" זה לשלוח את המשתמש לסיבוב מיותר.
      const locked = FileSystemException(
        'The process cannot access the file',
        r'C:\Otzaria\seforim.db',
        OSError('sharing violation', 32),
      );

      expect(Elevation.isAccessDenied(locked), isFalse);
    });

    test('שגיאה בלי OSError אינה מזוהה כסירוב הרשאה', () {
      expect(
        Elevation.isAccessDenied(
          const FileSystemException('לא נמצא', '/x'),
        ),
        isFalse,
      );
    });

    test('מסד לקריאה בלבד מזוהה גם כשהשגיאה באה מ-sqlite ולא מ-dart:io', () {
      // המסלול הזה אינו זורק FileSystemException בכלל, ולכן הזיהוי לפי
      // הטקסט של sqlite עצמו — שאינו מתורגם.
      expect(
        Elevation.isAccessDenied(
          StateError('SqliteException(8): attempt to write a readonly '
              'database, attempt to write a readonly database'),
        ),
        isTrue,
      );
    });

    test('תקלה רגילה אינה מזוהה', () {
      expect(Elevation.isAccessDenied(StateError('המראה ריקה')), isFalse);
    });
  });

  group('Elevation.describe', () {
    test('שגיאת הרשאות מקבלת את ההסבר, וההודעה המקורית נשמרת', () {
      final denied = FileSystemException(
        'Access is denied',
        r'C:\Program Files\Otzaria',
        OSError('Access is denied', Platform.isWindows ? 5 : 13),
      );

      final described = Elevation.describe(denied);

      expect(described, contains('Access is denied'));
      expect(described, contains(AppL10n.strings.elevation.hint));
    });

    test('שגיאה אחרת נשארת מילה במילה', () {
      final other = StateError('המראה ריקה');
      expect(Elevation.describe(other), other.toString());
    });

    test('ההסבר מגיע מ-otzaria_l10n בשפה שנבחרה', () {
      AppL10n.use(AppLanguage.english);
      final denied = FileSystemException(
        'denied',
        '/x',
        OSError('denied', Platform.isWindows ? 5 : 13),
      );

      expect(
        Elevation.describe(denied),
        contains(AppL10n.stringsFor(AppLanguage.english).elevation.hint),
      );
    });
  });

  group('Elevation.restartElevated', () {
    test('מרים דרך PowerShell עם -Verb RunAs, ורק אז סוגר', () async {
      String? executable;
      List<String>? arguments;
      var quit = false;

      final failure = await Elevation.restartElevated(
        startDetached: (exe, args) async {
          executable = exe;
          arguments = args;
          // הסגירה חייבת לבוא **אחרי** ההפעלה, אחרת אין מי שיפעיל.
          expect(quit, isFalse);
        },
        quit: () => quit = true,
      );

      expect(failure, isNull);
      expect(executable, 'powershell');
      expect(arguments, contains('-NoProfile'));
      expect(
        arguments!.last,
        allOf(
          startsWith('Start-Process -FilePath '),
          contains(Platform.resolvedExecutable),
          endsWith('-Verb RunAs'),
        ),
      );
      expect(quit, isTrue);
    }, skip: !Platform.isWindows);

    test('כשל בהפעלה מוחזר ואינו סוגר את התוכנה', () async {
      var quit = false;

      final failure = await Elevation.restartElevated(
        startDetached: (exe, args) async => throw const ProcessException(
          'powershell',
          [],
          'חסום',
        ),
        quit: () => quit = true,
      );

      expect(failure, isA<ProcessException>());
      expect(quit, isFalse);
    }, skip: !Platform.isWindows);

    test('בפלטפורמה שאינה ווינדוס אין הרמה בכלל', () async {
      var started = false;

      final failure = await Elevation.restartElevated(
        startDetached: (exe, args) async => started = true,
        quit: () {},
      );

      expect(failure, isNotNull);
      expect(started, isFalse);
    }, skip: Platform.isWindows);
  });
}
