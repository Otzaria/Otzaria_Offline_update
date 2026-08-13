import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('יצירת מזהה', () {
    test('שם קובץ לטיני הופך לסלאג', () {
      expect(AppDescriptorIdGenerator.from('MyApp'), 'myapp');
      expect(AppDescriptorIdGenerator.from('My App Setup'), 'my-app-setup');
      expect(AppDescriptorIdGenerator.from('npp.8.6.Installer'),
          'npp-8-6-installer');
    });

    test('שם בעברית — נופל לברירת מחדל ולא לזבל', () {
      expect(AppDescriptorIdGenerator.from('התוכנה שלי'),
          AppDescriptorIdGenerator.fallback);
    });

    test('שם מעורב שומר רק את החלק הלטיני', () {
      expect(AppDescriptorIdGenerator.from('תוכנה MyApp גרסה 2'), 'myapp-2');
    });

    test('מפרידים כפולים אינם מצטברים', () {
      expect(AppDescriptorIdGenerator.from('a   ---   b'), 'a-b');
      expect(AppDescriptorIdGenerator.from('---a---'), 'a');
    });

    test('התוצאה תמיד עוברת את המאמת', () {
      for (final source in [
        'MyApp',
        'התוכנה שלי',
        '...',
        '   ',
        '',
        'a' * 200,
        r'C:\Program Files\App',
      ]) {
        final id = AppDescriptorIdGenerator.from(source);
        expect(AppDescriptorId.isValid(id), isTrue, reason: '$source → $id');
      }
    });

    // שם התקן שמור לא יכול לחמוק דרך המחולל.
    test('שם שמור בווינדוס נופל לברירת מחדל', () {
      expect(AppDescriptorIdGenerator.from('con'),
          AppDescriptorIdGenerator.fallback);
      expect(AppDescriptorIdGenerator.from('LPT1'),
          AppDescriptorIdGenerator.fallback);
    });

    test('מזהה תפוס מקבל סיומת מספרית', () {
      expect(
        AppDescriptorIdGenerator.from('MyApp', taken: {'myapp'}),
        'myapp-2',
      );
      expect(
        AppDescriptorIdGenerator.from('MyApp', taken: {'myapp', 'myapp-2'}),
        'myapp-3',
      );
    });

    test('שם ארוך נגזם ואינו מסתיים במקף', () {
      final id = AppDescriptorIdGenerator.from('${'ab-' * 40}end');
      expect(id.length, lessThanOrEqualTo(AppDescriptorId.maxLength));
      expect(id.endsWith('-'), isFalse);
    });
  });

  group('זיהוי סוג ההתקנה מהקובץ', () {
    late String root;
    const sniffer = InstallerKindSniffer();

    setUp(() => root = tempMirrorRoot());

    String writeBytes(String name, List<int> bytes) {
      final path = p.join(root, name);
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return path;
    }

    test('MSI מזוהה לפי חתימת OLE', () async {
      final path = writeBytes(
        'app.msi',
        [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0],
      );
      expect(await sniffer.sniff(path), CustomInstallerKind.msi);
    });

    test('ZIP מזוהה לפי החתימה שלו', () async {
      final path = writeBytes('app.zip', [0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
      expect(await sniffer.sniff(path), CustomInstallerKind.zipPortable);
    });

    test('Inno Setup מזוהה לפי הסימן בגוף הקובץ', () async {
      final path = writeBytes(
        'setup.exe',
        [...'MZ'.codeUnits, ...List.filled(500, 0), ...'Inno Setup'.codeUnits],
      );
      expect(await sniffer.sniff(path), CustomInstallerKind.innoSetup);
    });

    test('NSIS מזוהה לפי הסימן שלו', () async {
      final path = writeBytes(
        'setup.exe',
        [...'MZ'.codeUnits, ...List.filled(500, 0), ...'Nullsoft'.codeUnits],
      );
      expect(await sniffer.sniff(path), CustomInstallerKind.nsis);
    });

    // בלי חפיפה בין צ'אנקים, סימן שנופל על הגבול היה מוחמץ.
    test('סימן שנופל בדיוק על גבול צ\'אנק נתפס', () async {
      const marker = 'Inno Setup';
      final padding = InstallerKindSniffer.chunkSize - 4;
      final path = writeBytes(
        'setup.exe',
        [...List.filled(padding, 0x41), ...marker.codeUnits],
      );
      expect(await sniffer.sniff(path), CustomInstallerKind.innoSetup);
    });

    test('קובץ שאין בו סימן — null, כלומר "תבחר בעצמך"', () async {
      final path = writeBytes('mystery.exe', List.filled(2048, 0x41));
      expect(await sniffer.sniff(path), isNull);
    });

    test('קובץ שאינו קיים — null ולא שגיאה', () async {
      expect(await sniffer.sniff(p.join(root, 'אין-כזה.exe')), isNull);
    });

    test('קובץ ריק — null ולא קריסה', () async {
      expect(await sniffer.sniff(writeBytes('empty.exe', [])), isNull);
    });
  });
}
