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
}
