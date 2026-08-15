import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:test/test.dart';

void main() {
  group('דגלי התקנה שקטה', () {
    test('Inno Setup — הדגלים שאומתו מול המתקין האמיתי של אוצריא', () {
      final command = CustomInstallerKind.innoSetup.silentCommand(
        installerPath: r'C:\mirror\setup.exe',
        installDir: r'C:\Program Files\MyApp',
      )!;

      expect(command.executable, r'C:\mirror\setup.exe');
      expect(command.arguments, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        r'/DIR=C:\Program Files\MyApp',
      ]);
    });

    test('בלי מיקום התקנה — המתקין מחליט בעצמו, וזו ברירת המחדל הרצויה', () {
      final command = CustomInstallerKind.innoSetup
          .silentCommand(installerPath: 'setup.exe')!;
      expect(command.arguments, isNot(contains(startsWith('/DIR='))));
    });

    test('מחרוזת ריקה למיקום התקנה נחשבת כמו היעדרו', () {
      final command = CustomInstallerKind.innoSetup
          .silentCommand(installerPath: 'setup.exe', installDir: '')!;
      expect(command.arguments, isNot(contains(startsWith('/DIR='))));
    });

    // ⚠️ המוקש האמיתי של NSIS: `/D=` בולע כל מה שאחריו.
    test('NSIS — /D= הוא תמיד הארגומנט האחרון', () {
      final command = CustomInstallerKind.nsis.silentCommand(
        installerPath: 'setup.exe',
        installDir: r'C:\Program Files\My App',
      )!;

      expect(command.arguments.first, '/S');
      expect(command.arguments.last, r'/D=C:\Program Files\My App');
    });

    test('NSIS — הנתיב אינו עטוף במרכאות גם כשיש בו רווחים', () {
      final command = CustomInstallerKind.nsis.silentCommand(
        installerPath: 'setup.exe',
        installDir: r'C:\Program Files\My App',
      )!;
      expect(command.arguments.last, isNot(contains('"')));
    });

    test('MSI מורץ דרך msiexec ולא ישירות — הוא אינו קובץ הרצה', () {
      final command = CustomInstallerKind.msi.silentCommand(
        installerPath: r'C:\mirror\app.msi',
        installDir: r'C:\Apps\MyApp',
      )!;

      expect(command.executable, 'msiexec');
      expect(command.arguments.take(3), ['/i', r'C:\mirror\app.msi', '/qn']);
      expect(command.arguments, contains(r'INSTALLDIR=C:\Apps\MyApp'));
    });

    test('ZIP נייד — אין מה להריץ', () {
      expect(CustomInstallerKind.zipPortable.isArchive, isTrue);
      expect(
        CustomInstallerKind.zipPortable.silentCommand(installerPath: 'a.zip'),
        isNull,
      );
    });

    test('כל הסוגים חוץ מהמעתיקים מייצרים פקודה', () {
      for (final kind in CustomInstallerKind.values) {
        final command = kind.silentCommand(installerPath: 'x');
        expect(command == null, kind.isCopyOnly, reason: kind.id);
      }
    });

    test('המזהים יציבים — הם נכתבים לקובצי תוסף של משתמשים', () {
      expect(CustomInstallerKind.allIds,
          ['inno', 'nsis', 'msi', 'zip', 'file', 'interactive']);
      expect(CustomInstallerKind.byId('inno'), CustomInstallerKind.innoSetup);
      expect(CustomInstallerKind.byId('אין כזה'), isNull);
    });
  });
}
