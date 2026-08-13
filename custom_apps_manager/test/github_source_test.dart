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
