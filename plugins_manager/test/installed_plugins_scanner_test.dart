import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  /// יוצר `<root>/installed/<id>/<release>/manifest.json`, המבנה של אוצריא.
  void install(String root, String id, String manifest,
      {String release = 'current'}) {
    final dir = Directory(p.join(root, 'installed', id, release))
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

    test('המבנה החדש — .release-<hash> — מזוהה כמותקן', () async {
      // הרגרסיה: אוצריא החדשה פורשת ל-`.release-<hash>` ואין `current`,
      // ולכן תוסף מותקן נראה בחנות כאילו לא הותקן מעולם.
      install(temp.path, 'com.otzaria-marker', '{"version":"0.9.2"}',
          release: '.release-fe601d89');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'com.otzaria-marker': '0.9.2'});
    });

    test('שני המבנים יחד נסרקים באותה סריקה', () async {
      install(temp.path, 'old', '{"version":"1.0.0"}');
      install(temp.path, 'new', '{"version":"2.0.0"}',
          release: '.release-abc123');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'old': '1.0.0', 'new': '2.0.0'});
    });

    test('current גוברת על .release כששתיהן קיימות', () async {
      install(temp.path, 'both', '{"version":"1.0.0"}');
      install(temp.path, 'both', '{"version":"9.9.9"}',
          release: '.release-stale');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'both': '1.0.0'});
    });

    test('מכמה .release נבחרת זו שנכתבה אחרונה', () async {
      install(temp.path, 'many', '{"version":"1.0.0"}',
          release: '.release-aaaaaa');
      install(temp.path, 'many', '{"version":"2.0.0"}',
          release: '.release-zzzzzz');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'many': '2.0.0'});
    });

    test('.release פגומה נופלת לזו שאחריה', () async {
      install(temp.path, 'fallback', 'לא JSON', release: '.release-zzzzzz');
      install(temp.path, 'fallback', '{"version":"1.0.0"}',
          release: '.release-aaaaaa');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'fallback': '1.0.0'});
    });

    test('תיקיית משנה שאינה current או .release אינה נספרת', () async {
      install(temp.path, 'data-only', '{"version":"1.0.0"}', release: 'data');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), isEmpty);
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

  group('scan מול רישום ההתקנות של אוצריא', () {
    late String pluginsDir;
    late String dbPath;

    setUp(() {
      pluginsDir = p.join(temp.path, 'plugins');
      dbPath = p.join(temp.path, 'databases', pluginsRegistryFileName);
      Directory(p.dirname(dbPath)).createSync(recursive: true);
    });

    Database openRegistry(Map<String, String> rows) {
      final db = sqlite3.open(dbPath)
        ..execute('PRAGMA journal_mode=WAL')
        ..execute(
          'CREATE TABLE plugin_installation ('
          'plugin_id TEXT PRIMARY KEY, name TEXT NOT NULL, '
          'version TEXT NOT NULL, install_path TEXT NOT NULL)',
        );
      for (final row in rows.entries) {
        db.execute(
          'INSERT INTO plugin_installation VALUES (?, ?, ?, ?)',
          [row.key, row.key, row.value, p.join(pluginsDir, row.key)],
        );
      }
      return db;
    }

    test('הרישום גובר על תיקיות שנשארו אחרי מחיקה או התקנה שנקטעה', () async {
      install(pluginsDir, 'updated', '{"version":"1.0.0"}');
      install(pluginsDir, 'updated', '{"version":"2.0.0"}',
          release: '.release-new');
      install(pluginsDir, 'removed', '{"version":"1.0.0"}',
          release: '.release-old');
      install(pluginsDir, 'half', '{"version":"1.0.0"}',
          release: '.release-old');
      install(pluginsDir, 'half', '{"version":"3.0.0"}',
          release: '.release-staged');
      final writer = openRegistry({'updated': '2.0.0', 'half': '1.0.0'});
      addTearDown(writer.close);

      String? askedRoot;
      final scanner = InstalledPluginsScanner(
        customPluginsDir: pluginsDir,
        locatePluginsDb: (dataRoot) async {
          askedRoot = dataRoot;
          return dbPath;
        },
      );

      expect(await scanner.scan(), {'updated': '2.0.0', 'half': '1.0.0'});
      expect(askedRoot, temp.path);
    });

    test('רישום ריק פירושו שאין תוספים, גם כשתיקיות נשארו', () async {
      install(pluginsDir, 'leftover', '{"version":"1.0.0"}');
      openRegistry(const {}).close();

      final scanner = InstalledPluginsScanner(
        customPluginsDir: pluginsDir,
        locatePluginsDb: (_) async => dbPath,
      );
      expect(await scanner.scan(), isEmpty);
    });

    test('בלי רישום קריא חוזרים לסריקת התיקיות', () async {
      install(pluginsDir, 'alpha', '{"version":"1.2.3"}');

      Future<Map<String, String>> scanWith(
              Future<String?> Function(String) locate) =>
          InstalledPluginsScanner(
            customPluginsDir: pluginsDir,
            locatePluginsDb: locate,
          ).scan();

      expect(await scanWith((_) async => null), {'alpha': '1.2.3'});
      expect(await scanWith((_) async => dbPath), {'alpha': '1.2.3'});
      expect(await scanWith((_) => throw StateError('x')), {'alpha': '1.2.3'});

      File(dbPath).writeAsStringSync('לא מסד נתונים');
      expect(await scanWith((_) async => dbPath), {'alpha': '1.2.3'});

      File(dbPath).deleteSync();
      sqlite3.open(dbPath)
        ..execute('CREATE TABLE other (x)')
        ..close();
      expect(await scanWith((_) async => dbPath), {'alpha': '1.2.3'});
    });
  });

  group('scan כשקריאת התיקייה נכשלת', () {
    test('תיקיית installed שאי אפשר לקרוא מחזירה מפה ריקה ולא זורקת', () async {
      install(temp.path, 'alpha', '{"version":"1.0.0"}');
      final installed = p.join(temp.path, 'installed');
      Process.runSync('chmod', ['000', installed]);
      addTearDown(() => Process.runSync('chmod', ['755', installed]));

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), isEmpty);
    }, skip: Platform.isWindows ? 'chmod אינו קיים בווינדוס' : false);
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
