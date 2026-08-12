import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  /// יוצר `<root>/installed/<id>/current/manifest.json`, המבנה של אוצריא.
  void install(String root, String id, String manifest) {
    final dir = Directory(p.join(root, 'installed', id, 'current'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'manifest.json')).writeAsStringSync(manifest);
  }

  group('scan', () {
    test('מחזיר manifestId -> גרסה מותקנת', () async {
      install(temp.path, 'alpha', '{"id":"alpha","version":"1.2.3"}');
      install(temp.path, 'beta', '{"id":"beta","version":"0.9.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'alpha': '1.2.3', 'beta': '0.9.0'});
    });

    test('המפתח הוא שם התיקייה, לא ה-id שבתוך המניפסט', () async {
      // אוצריא מתקינה תחת installed/<manifest.id>/, וזה מה שצריך להשוות.
      install(temp.path, 'dir-name', '{"id":"other","version":"1.0.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'dir-name': '1.0.0'});
    });

    test('BOM במניפסט המותקן אינו מפיל את הקריאה', () async {
      install(temp.path, 'bom', '﻿{"id":"bom","version":"2.0.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'bom': '2.0.0'});
    });

    test('שם תיקייה בעברית נסרק כרגיל', () async {
      install(temp.path, 'מפרשים', '{"version":"1.0.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'מפרשים': '1.0.0'});
    });

    test('מניפסט פגום, בלי גרסה או עם גרסה שאינה מחרוזת מדולג בשקט', () async {
      install(temp.path, 'good', '{"version":"1.0.0"}');
      install(temp.path, 'broken', 'לא JSON');
      install(temp.path, 'no-version', '{"id":"no-version"}');
      install(temp.path, 'numeric', '{"version":3}');
      install(temp.path, 'empty-version', '{"version":""}');
      install(temp.path, 'array', '[1,2,3]');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'good': '1.0.0'});
    });

    test('תיקייה בלי current/manifest.json מדולגת', () async {
      Directory(p.join(temp.path, 'installed', 'half')).createSync(
        recursive: true,
      );
      install(temp.path, 'full', '{"version":"1.0.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'full': '1.0.0'});
    });

    test('קובץ (ולא תיקייה) בתוך installed מדולג', () async {
      final installed = Directory(p.join(temp.path, 'installed'))
        ..createSync(recursive: true);
      File(p.join(installed.path, 'registry.json')).writeAsStringSync('{}');
      install(temp.path, 'real', '{"version":"1.0.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'real': '1.0.0'});
    });

    test('תיקייה שאינה קיימת מחזירה מפה ריקה — אוצריא פשוט לא מותקנת',
        () async {
      final scanner = InstalledPluginsScanner(
        customPluginsDir: p.join(temp.path, 'אין-כזו'),
      );
      expect(await scanner.scan(), isEmpty);
    });

    test('installed ריקה מחזירה מפה ריקה', () async {
      Directory(p.join(temp.path, 'installed')).createSync(recursive: true);

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), isEmpty);
    });
  });

  group('resolveInstalledDir', () {
    test('נתיב תוספים רגיל מקבל installed בסופו', () {
      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(
        scanner.resolveInstalledDir(),
        p.join(temp.path, 'installed'),
      );
    });

    test('נתיב שכבר מצביע על installed אינו מוכפל', () {
      final installedDir = p.join(temp.path, 'installed');
      final scanner = InstalledPluginsScanner(customPluginsDir: installedDir);
      expect(scanner.resolveInstalledDir(), installedDir);
    });

    test('בלי דריסה — ברירת המחדל של הפלטפורמה', () {
      const scanner = InstalledPluginsScanner();
      final resolved = scanner.resolveInstalledDir();

      if (Platform.isWindows || Platform.isMacOS) {
        // הנתיב מתגלה ולא מונח: תמיד תחת תיקיית אוצריא של המשתמש.
        expect(resolved, isNotNull);
        expect(resolved, endsWith(p.join('otzaria', 'plugins', 'installed')));
        expect(
            resolved, startsWith(InstalledPluginsScanner.defaultPluginsDir()!));
      } else {
        expect(resolved, isNull);
      }
    });

    test('דריסה במחרוזת ריקה נופלת לברירת המחדל', () {
      const scanner = InstalledPluginsScanner(customPluginsDir: '');
      const fallback = InstalledPluginsScanner();
      expect(scanner.resolveInstalledDir(), fallback.resolveInstalledDir());
    });
  });

  group('התקנה ניידת', () {
    /// התקנה ניידת של אוצריא: קובץ הרצה, סימון, ותיקיית נתונים לידם.
    String portableInstall({bool marker = true, bool dataDir = true}) {
      final exe = p.join(temp.path, 'otzaria.exe');
      File(exe).writeAsStringSync('');
      if (marker) {
        File(p.join(temp.path, InstalledPluginsScanner.portableMarkerFileName))
            .writeAsStringSync('');
      }
      if (dataDir) {
        install(
          p.join(temp.path, InstalledPluginsScanner.portableDataFolderName,
              'plugins'),
          'nikud',
          '{"version":"1.4.0"}',
        );
      }
      return exe;
    }

    test('התוספים נקראים מתיקיית הנתונים שליד קובץ ההרצה, לא מ-%APPDATA%',
        () async {
      final scanner =
          InstalledPluginsScanner(otzariaLaunchPath: portableInstall());

      expect(
        scanner.resolvePluginsDir(),
        p.join(temp.path, 'otzaria_data', 'plugins'),
      );
      expect(await scanner.scan(), {'nikud': '1.4.0'});
    });

    test('תיקיית נתונים קיימת מתקבלת גם בלי קובץ הסימון', () async {
      final scanner = InstalledPluginsScanner(
        otzariaLaunchPath: portableInstall(marker: false),
      );

      expect(await scanner.scan(), {'nikud': '1.4.0'});
    });

    test('התקנה רגילה (בלי סימון ובלי תיקיית נתונים) נופלת לברירת המחדל', () {
      final scanner = InstalledPluginsScanner(
        otzariaLaunchPath: portableInstall(marker: false, dataDir: false),
      );
      const fallback = InstalledPluginsScanner();

      expect(scanner.resolveInstalledDir(), fallback.resolveInstalledDir());
    });

    test('נתיב מפורש מנצח את הזיהוי הניידת', () {
      final explicit = p.join(temp.path, 'בחירה-ידנית');
      final scanner = InstalledPluginsScanner(
        customPluginsDir: explicit,
        otzariaLaunchPath: portableInstall(),
      );

      expect(scanner.resolvePluginsDir(), explicit);
    });

    test('חבילת .app — הסימון והנתונים יושבים ב-Contents/MacOS', () async {
      final bundle = p.join(temp.path, 'אוצריא.app');
      final exeDir = p.join(bundle, 'Contents', 'MacOS');
      Directory(exeDir).createSync(recursive: true);
      File(p.join(exeDir, InstalledPluginsScanner.portableMarkerFileName))
          .writeAsStringSync('');
      install(p.join(exeDir, 'otzaria_data', 'plugins'), 'מפרשים',
          '{"version":"2.0.0"}');

      final scanner = InstalledPluginsScanner(otzariaLaunchPath: bundle);
      expect(await scanner.scan(), {'מפרשים': '2.0.0'});
    });

    test('בלי נתיב התקנה — התנהגות ברירת המחדל נשמרת', () {
      const scanner = InstalledPluginsScanner(otzariaLaunchPath: '');
      const fallback = InstalledPluginsScanner();
      expect(scanner.resolveInstalledDir(), fallback.resolveInstalledDir());
    });
  });
}
