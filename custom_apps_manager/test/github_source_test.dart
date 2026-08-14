import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

void main() {
  group('פענוח כתובת ריפו — מה שאנשים באמת מדביקים', () {
    void expectParsed(String raw, String owner, String repo) {
      final parsed = GithubSource.parseUrl(raw);
      expect(parsed, isNotNull, reason: raw);
      expect(parsed!.owner, owner, reason: raw);
      expect(parsed.repo, repo, reason: raw);
    }

    test('כתובת מלאה', () {
      expectParsed('https://github.com/Otzaria/otzaria', 'Otzaria', 'otzaria');
    });

    test('בלי סכימה, עם www, עם לוכסן מסיים', () {
      expectParsed('www.github.com/Otzaria/otzaria/', 'Otzaria', 'otzaria');
      expectParsed('github.com/Otzaria/otzaria', 'Otzaria', 'otzaria');
    });

    test('כתובת של עמוד ה-releases — מה שמעתיקים בפועל', () {
      expectParsed(
        'https://github.com/Otzaria/otzaria/releases/tag/v1.2.3',
        'Otzaria',
        'otzaria',
      );
    });

    test('סיומת .git', () {
      expectParsed('https://github.com/a/b.git', 'a', 'b');
    });

    test('owner/repo יבש',
        () => expectParsed('Otzaria/otzaria', 'Otzaria', 'otzaria'));

    test('רווחים מסביב', () {
      expectParsed('  https://github.com/a/b  ', 'a', 'b');
    });

    test('קלט שאינו ריפו נדחה', () {
      for (final raw in ['', '   ', 'github.com', 'https://example.com', 'a']) {
        expect(GithubSource.parseUrl(raw), isNull, reason: raw);
      }
    });
  });

  group('תבנית הקובץ — חייבת לשרוד את הגרסה הבאה', () {
    test('מספרי גרסה מוחלפים', () {
      final pattern = GithubAssetPattern.fromAssetName('MyApp-Setup-1.4.2.exe');
      expect(
          GithubAssetPattern.matches(pattern, 'MyApp-Setup-1.4.2.exe'), isTrue);
      // זה כל העניין: הגרסה הבאה עדיין מתאימה.
      expect(
          GithubAssetPattern.matches(pattern, 'MyApp-Setup-2.0.0.exe'), isTrue);
      expect(GithubAssetPattern.matches(pattern, 'MyApp-Setup-10.20.30.exe'),
          isTrue);
    });

    // המלכודת: ספרה שהיא חלק מהשם ולא מהגרסה.
    test('x64 אינו הופך לתבנית שתופסת גם x86', () {
      final pattern =
          GithubAssetPattern.fromAssetName('npp.8.6.Installer.x64.exe');
      expect(
        GithubAssetPattern.matches(pattern, 'npp.8.7.Installer.x64.exe'),
        isTrue,
      );
      expect(
        GithubAssetPattern.matches(pattern, 'npp.8.7.Installer.x86.exe'),
        isFalse,
      );
    });

    /// ⚠️ נמצא מול ריפו אמיתי — `KleiKodesh/KleiKodeshProject`. הספרה שאחרי
    /// `v` נחשבה חלק מהשם לפי כלל ה"ספרה שאחרי אות", ולכן התבנית קפאה על
    /// `v9`: בגרסה 10 התוכנה הייתה מדווחת "אין קובץ מתאים" לנצח.
    group('`v` לפני מספר הגרסה — הריפו האמיתי שחשף את הבאג', () {
      const chosen = 'KleiKodeshSetup-v9.0.1-x64.exe';

      test('גרסה עוקבת מתאימה, וגם מעבר לספרה אחת', () {
        final pattern = GithubAssetPattern.fromAssetName(chosen);

        expect(GithubAssetPattern.matches(pattern, chosen), isTrue);
        expect(
          GithubAssetPattern.matches(pattern, 'KleiKodeshSetup-v9.0.2-x64.exe'),
          isTrue,
        );
        // זה מה שנשבר לפני התיקון.
        expect(
          GithubAssetPattern.matches(
              pattern, 'KleiKodeshSetup-v10.0.0-x64.exe'),
          isTrue,
        );
      });

      /// ל-release הזה יש ארבעה קבצים, ו"הראשון ברשימה" הוא ה-zip הנייד —
      /// בדיוק הבאג שהתבנית קיימת כדי למנוע.
      test('שלושת האחים באותו release אינם נתפסים', () {
        final pattern = GithubAssetPattern.fromAssetName(chosen);

        for (final sibling in [
          'KleiKodeshSetup-v9.0.1-x86.exe',
          'KleiKodeshSetup-v9.0.1.exe',
          'KitveiHakodeshPortable-v9.0.1.zip',
          'KleiKodeshSetup.exe',
        ]) {
          expect(
            GithubAssetPattern.matches(pattern, sibling),
            isFalse,
            reason: sibling,
          );
        }
      });

      test('ה-zip הנייד נבחר — גם הוא שורד את הגרסה הבאה', () {
        final pattern = GithubAssetPattern.fromAssetName(
          'KitveiHakodeshPortable-v9.0.1.zip',
        );
        expect(
          GithubAssetPattern.matches(
              pattern, 'KitveiHakodeshPortable-v10.1.0.zip'),
          isTrue,
        );
        expect(
          GithubAssetPattern.matches(
              pattern, 'KleiKodeshSetup-v10.1.0-x64.exe'),
          isFalse,
        );
      });

      // ה-`v` חייב לבוא אחרי מפריד, אחרת כל ספרה שאחרי אות `v` באמצע מילה
      // הייתה נחשבת גרסה.
      test('`v` שבתוך מילה אינו סימן גרסה', () {
        final pattern = GithubAssetPattern.fromAssetName('Rev9-tool-1.0.exe');
        expect(
          GithubAssetPattern.matches(pattern, 'Rev9-tool-2.0.exe'),
          isTrue,
        );
        expect(
          GithubAssetPattern.matches(pattern, 'Rev8-tool-2.0.exe'),
          isFalse,
        );
      });

      test('הכתובת שהמשתמש מדביק בפועל — עם /releases בסוף', () {
        final parsed = GithubSource.parseUrl(
          'https://github.com/KleiKodesh/KleiKodeshProject/releases',
        );
        expect(parsed!.owner, 'KleiKodesh');
        expect(parsed.repo, 'KleiKodeshProject');
      });
    });

    test('win32 ו-amd64 נשמרים כלשונם', () {
      final pattern = GithubAssetPattern.fromAssetName('tool-win32-1.0.zip');
      expect(GithubAssetPattern.matches(pattern, 'tool-win32-2.5.zip'), isTrue);
      expect(
          GithubAssetPattern.matches(pattern, 'tool-win64-2.5.zip'), isFalse);
    });

    test('התבנית מעוגנת — לא תופסת שם ארוך יותר', () {
      final pattern = GithubAssetPattern.fromAssetName('app-1.0.exe');
      expect(GithubAssetPattern.matches(pattern, 'app-1.0.exe'), isTrue);
      expect(GithubAssetPattern.matches(pattern, 'other-app-1.0.exe'), isFalse);
      expect(
          GithubAssetPattern.matches(pattern, 'app-1.0.exe.sha256'), isFalse);
    });

    test('שם בלי ספרות כלל נשמר כמות שהוא', () {
      final pattern = GithubAssetPattern.fromAssetName('setup.exe');
      expect(GithubAssetPattern.matches(pattern, 'setup.exe'), isTrue);
      expect(GithubAssetPattern.matches(pattern, 'setup-x.exe'), isFalse);
    });

    test('תווים מיוחדים בשם אינם נחשבים כרגקס', () {
      final pattern = GithubAssetPattern.fromAssetName('app+tool(1).exe');
      expect(GithubAssetPattern.matches(pattern, 'app+tool(2).exe'), isTrue);
      expect(GithubAssetPattern.matches(pattern, 'appXtool(2).exe'), isFalse);
    });

    test('תבנית ריקה או פגומה אינה מתאימה לכלום ואינה זורקת', () {
      expect(GithubAssetPattern.matches('', 'a.exe'), isFalse);
      expect(GithubAssetPattern.matches('([', 'a.exe'), isFalse);
    });
  });
}
