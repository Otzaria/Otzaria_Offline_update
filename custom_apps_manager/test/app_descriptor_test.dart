import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

/// תוסף מינימלי תקין, כמחרוזת — כך נראה קובץ `.otzupdate` אמיתי.
const _minimal = '''
{
  "id": "org.example.myapp",
  "name": "התוכנה שלי",
  "install": { "kind": "inno" }
}
''';

void main() {
  group('אימות המזהה', () {
    test('מזהים תקינים מתקבלים', () {
      for (final id in [
        'org.example.myapp',
        'myapp',
        'my-app_2',
        'a',
      ]) {
        expect(AppDescriptorId.isValid(id), isTrue, reason: id);
      }
    });

    // המזהה הופך לשם תיקייה — זה הגבול, לא ניקיון.
    test('טיפוס מחוץ לתיקייה נחסם', () {
      for (final id in [
        '..',
        '../evil',
        'a/../../b',
        'a..b',
        '.hidden',
        'trailing.',
      ]) {
        expect(AppDescriptorId.isValid(id), isFalse, reason: id);
      }
    });

    test('תווים שאינם חוקיים כשם תיקייה נחסמים', () {
      for (final id in [
        'my app',
        'My.App',
        r'a\b',
        'a/b',
        'a:b',
        'שם',
        '',
      ]) {
        expect(AppDescriptorId.isValid(id), isFalse, reason: id);
      }
    });

    test('שמות התקנים שמורים בווינדוס נחסמים, גם עם סיומת', () {
      for (final id in ['con', 'nul', 'com1', 'lpt9', 'con.exe']) {
        expect(AppDescriptorId.isValid(id), isFalse, reason: id);
      }
    });

    test('מזהה ארוך מדי נחסם', () {
      expect(AppDescriptorId.isValid('a' * 64), isTrue);
      expect(AppDescriptorId.isValid('a' * 65), isFalse);
    });
  });

  group('פענוח תוסף', () {
    test('תוסף מינימלי — ברירות המחדל נכונות', () {
      final d = AppDescriptor.parse(_minimal);

      expect(d.id, 'org.example.myapp');
      expect(d.name, 'התוכנה שלי');
      // מקור חסר נחשב manual — הקובץ שנכתב ביד מתכוון לזה.
      expect(d.sourceKind, AppSourceKind.manual);
      // בלי מיקום מוצהר — המתקין מחליט.
      expect(d.installDir, isNull);
      expect(d.detect.isEmpty, isTrue);
    });

    test('תוסף מלא', () {
      final d = AppDescriptor.parse('''
{
  "schemaVersion": 1,
  "id": "org.example.full",
  "name": "מלא",
  "publisher": "מישהו",
  "source": { "kind": "manual" },
  "install": { "kind": "nsis", "dir": "C:\\\\Apps\\\\Full" },
  "detect": {
    "exeName": "full.exe",
    "registryDisplayName": "Full App",
    "dirs": ["C:\\\\Apps\\\\Full"]
  }
}
''');

      expect(d.publisher, 'מישהו');
      expect(d.installDir, r'C:\Apps\Full');
      expect(d.detect.exeName, 'full.exe');
      expect(d.detect.registryDisplayName, 'Full App');
      expect(d.detect.dirs, [r'C:\Apps\Full']);
      expect(d.detect.isEmpty, isFalse);
    });

    test('הלוך ושוב דרך JSON שומר על הכול', () {
      final original = AppDescriptor.parse('''
{
  "id": "org.example.round",
  "name": "הלוך ושוב",
  "publisher": "מפרסם",
  "install": { "kind": "msi", "dir": "D:\\\\X" },
  "detect": { "exeName": "r.exe", "dirs": ["D:\\\\X"] }
}
''');
      final again = AppDescriptor.parse(original.encode());

      expect(again.id, original.id);
      expect(again.name, original.name);
      expect(again.publisher, original.publisher);
      expect(again.installDir, original.installDir);
      expect(again.detect.exeName, original.detect.exeName);
      expect(again.detect.dirs, original.detect.dirs);
    });

    test('הקובץ הכתוב קריא לבן אדם', () {
      expect(AppDescriptor.parse(_minimal).encode(), contains('\n  "id"'));
    });
  });

  group('מקור GitHub', () {
    const withGithub = '''
{
  "id": "org.example.gh",
  "name": "מריפו",
  "description": "תיאור קצר",
  "source": {
    "kind": "github",
    "owner": "someone",
    "repo": "their-app",
    "asset": "^App\\\\-\\\\d+\\\\.exe\$"
  },
  "install": { "kind": "inno" }
}
''';

    test('נקרא במלואו', () {
      final d = AppDescriptor.parse(withGithub);

      expect(d.sourceKind, AppSourceKind.github);
      expect(d.description, 'תיאור קצר');
      expect(d.github, isNotNull);
      expect(d.github!.owner, 'someone');
      expect(d.github!.repo, 'their-app');
      expect(d.github!.assetPattern, r'^App\-\d+\.exe$');
    });

    test('הלוך ושוב שומר על הריפו ועל התבנית', () {
      final again =
          AppDescriptor.parse(AppDescriptor.parse(withGithub).encode());

      expect(again.github!.owner, 'someone');
      expect(again.github!.assetPattern, r'^App\-\d+\.exe$');
      expect(again.description, 'תיאור קצר');
    });

    test('במקור ידני אין ריפו כלל', () {
      expect(AppDescriptor.parse(_minimal).github, isNull);
    });
  });

  group('קובץ פגום — ההודעה חייבת להסביר מה לא בסדר', () {
    void expectRejected(String source, Pattern expected) {
      expect(
        () => AppDescriptor.parse(source),
        throwsA(
          isA<AppDescriptorException>()
              .having((e) => e.message, 'message', contains(expected)),
        ),
      );
    }

    test('אינו JSON', () {
      expectRejected('לא JSON בכלל', 'JSON');
    });

    test('JSON שאינו אובייקט', () {
      expectRejected('[1, 2, 3]', 'JSON');
    });

    test('שדה חובה חסר — ההודעה נוקבת בשמו', () {
      expectRejected('{"name": "בלי מזהה", "install": {"kind": "inno"}}', 'id');
      expectRejected('{"id": "a.b", "install": {"kind": "inno"}}', 'name');
    });

    test('שדה חובה ריק נחשב חסר', () {
      expectRejected(
          '{"id": "a.b", "name": "   ", "install": {"kind": "inno"}}', 'name');
    });

    test('מזהה מסוכן נדחה בהודעה שמצטטת אותו', () {
      expectRejected(
        '{"id": "../../evil", "name": "x", "install": {"kind": "inno"}}',
        '../../evil',
      );
    });

    // סוג ההתקנה אינו נקרא מהרשומה יותר — הוא נגזר מהקובץ בזמן ההתקנה,
    // ולכן ערך ישן או מומצא בשדה הזה פשוט מדולג.
    test('שדה install.kind ישן אינו מפריע ואינו נקרא', () {
      final d = AppDescriptor.parse(
        '{"id": "a.b", "name": "x", "install": {"kind": "מתקין מומצא"}}',
      );
      expect(d.name, 'x');
    });

    test('מקור לא מוכר נדחה', () {
      expectRejected(
        '{"id": "a.b", "name": "x", "source": {"kind": "פייסבוק"}, '
            '"install": {"kind": "inno"}}',
        'manual',
      );
    });

    test('מקור GitHub בלי ריפו נדחה — אין מה לבדוק בלעדיו', () {
      expectRejected(
        '{"id": "a.b", "name": "x", "source": {"kind": "github"}, '
            '"install": {"kind": "inno"}}',
        'source.repo',
      );
    });

    test('פורמט חדש מדי נדחה במפורש ולא מנוחש', () {
      expectRejected(
        '{"schemaVersion": 99, "id": "a.b", "name": "x", '
            '"install": {"kind": "inno"}}',
        '99',
      );
    });
  });
}
