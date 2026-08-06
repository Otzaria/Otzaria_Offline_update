import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

/// בונה קובץ `.otzplugin` אמיתי (ZIP) עם התוכן שנמסר ל-`manifest.json`.
String _writePluginFile(Directory dir, String name, String manifestText) {
  final archive = Archive()
    ..addFile(ArchiveFile(
      'manifest.json',
      utf8.encode(manifestText).length,
      utf8.encode(manifestText),
    ))
    ..addFile(ArchiveFile('main.js', 3, utf8.encode('/**')));

  final path = p.join(dir.path, name);
  File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);
  return path;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('plugins_manager_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('PluginManifestReader', () {
    test('מחלץ את ה-id מתוך ה-ZIP', () {
      final path = _writePluginFile(
        temp,
        'a.otzplugin',
        '{"id":"real-id","version":"1.0.0"}',
      );
      expect(PluginManifestReader.readId(path), 'real-id');
    });

    test('מתעלם מ-BOM מוביל', () {
      final path = _writePluginFile(
        temp,
        'bom.otzplugin',
        '﻿{"id":"with-bom","version":"1.0.0"}',
      );
      expect(PluginManifestReader.readId(path), 'with-bom');
    });

    test('קובץ שאינו ZIP מחזיר null ולא זורק', () {
      final path = p.join(temp.path, 'broken.otzplugin');
      File(path).writeAsStringSync('זה בכלל לא ארכיון');
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('ZIP בלי manifest.json מחזיר null', () {
      final archive = Archive()
        ..addFile(ArchiveFile('main.js', 3, utf8.encode('/**')));
      final path = p.join(temp.path, 'no-manifest.otzplugin');
      File(path).writeAsBytesSync(ZipEncoder().encode(archive)!);
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('id ריק נחשב חסר', () {
      final path = _writePluginFile(temp, 'empty.otzplugin', '{"id":"   "}');
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('קובץ שלא קיים מחזיר null', () {
      expect(
        PluginManifestReader.readId(p.join(temp.path, 'nope.otzplugin')),
        isNull,
      );
    });
  });

  group('PluginStoreClient.parseContentDisposition', () {
    test('צורת UTF-8 מפוענחת (שמות עבריים)', () {
      final parsed = PluginStoreClient.parseContentDisposition(
        "attachment; filename*=UTF-8''%D7%9E%D7%A4%D7%A8%D7%A9%D7%99%D7%9D.otzplugin",
      );
      expect(parsed?.name, 'מפרשים.otzplugin');
      expect(parsed?.ext, '.otzplugin');
    });

    test('צורת filename פשוטה', () {
      final parsed = PluginStoreClient.parseContentDisposition(
        'attachment; filename="my-plugin.otzplugin"',
      );
      expect(parsed?.name, 'my-plugin.otzplugin');
      expect(parsed?.ext, '.otzplugin');
    });

    test('כותרת חסרה או בלי filename מחזירה null', () {
      expect(PluginStoreClient.parseContentDisposition(null), isNull);
      expect(PluginStoreClient.parseContentDisposition('inline'), isNull);
    });
  });

  group('InstalledPluginsScanner', () {
    /// יוצר `<root>/installed/<id>/current/manifest.json`.
    void install(String root, String id, String manifest) {
      final dir = Directory(p.join(root, 'installed', id, 'current'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'manifest.json')).writeAsStringSync(manifest);
    }

    test('מחזיר manifestId -> גרסה מותקנת', () async {
      install(temp.path, 'alpha', '{"id":"alpha","version":"1.2.3"}');
      install(temp.path, 'beta', '{"id":"beta","version":"0.9.0"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'alpha': '1.2.3', 'beta': '0.9.0'});
    });

    test('מניפסט פגום או בלי גרסה מדולג בשקט', () async {
      install(temp.path, 'good', '{"version":"1.0.0"}');
      install(temp.path, 'broken', 'לא JSON');
      install(temp.path, 'no-version', '{"id":"no-version"}');

      final scanner = InstalledPluginsScanner(customPluginsDir: temp.path);
      expect(await scanner.scan(), {'good': '1.0.0'});
    });

    test('תיקייה שאינה קיימת מחזירה מפה ריקה', () async {
      final scanner = InstalledPluginsScanner(
        customPluginsDir: p.join(temp.path, 'אין-כזו'),
      );
      expect(await scanner.scan(), isEmpty);
    });

    test('נתיב שכבר מצביע על installed אינו מוכפל', () {
      final installedDir = p.join(temp.path, 'installed');
      final scanner = InstalledPluginsScanner(customPluginsDir: installedDir);
      expect(scanner.resolveInstalledDir(), installedDir);
    });
  });

  group('PluginMirrorStore', () {
    test('נתיבים יחסיים לשורש plugins/ נשמרים תמיד עם /', () {
      final store = PluginMirrorStore(temp.path);
      final absolute = p.join(store.filesDir, 'abc', 'plugin.otzplugin');

      // גם בווינדוס — כדי שקטלוג שנכתב שם ייקרא נכון גם ב-macOS.
      expect(store.relativePath(absolute), 'files/abc/plugin.otzplugin');
      expect(store.absolutePath(store.relativePath(absolute)), absolute);
    });

    test('קטלוג חסר מחזיר קטלוג ריק', () async {
      final store = PluginMirrorStore(temp.path);
      final catalog = await store.load();
      expect(catalog.plugins, isEmpty);
      expect(catalog.lastSync, isNull);
    });

    test('קטלוג פגום מחזיר קטלוג ריק ולא זורק', () async {
      final store = PluginMirrorStore(temp.path);
      await store.ensureDirs();
      File(store.catalogPath).writeAsStringSync('{ פגום');
      expect((await store.load()).plugins, isEmpty);
    });

    test('save ואז load מחזירים את אותו קטלוג', () async {
      final store = PluginMirrorStore(temp.path);
      final catalog = PluginCatalog(
        lastSync: DateTime.utc(2026, 8, 6),
        plugins: [
          StorePlugin.fromApi(
            {'id': 'abc', 'name': 'תוסף', 'version': '1.0.0'},
            'https://otzaria.org',
          ),
        ],
      );

      await store.save(catalog);
      final loaded = await store.load();

      expect(loaded.lastSync, catalog.lastSync);
      expect(loaded.plugins.single.name, 'תוסף');
      // הקטלוג יושב בתוך תת-התיקייה plugins/ של המראה, לא בשורש שלה —
      // כדי לא להתנגש עם releases.json של הספרייה.
      expect(store.catalogPath, p.join(temp.path, 'plugins', 'catalog.json'));
    });

    test('hasLocalFile מבדיל בין רשומה בקטלוג לקובץ שקיים בפועל', () async {
      final store = PluginMirrorStore(temp.path);
      await store.ensureDirs();

      final plugin = StorePlugin.fromApi(
        {'id': 'abc', 'name': 'תוסף'},
        'https://otzaria.org',
      ).copyWith(
        localFile: const PluginLocalFile(
          relativePath: 'files/abc/plugin.otzplugin',
          fileName: 'plugin.otzplugin',
          ext: '.otzplugin',
          size: 1,
        ),
      );

      expect(await store.hasLocalFile(plugin), isFalse);

      final file = File(store.absolutePath(plugin.localFile!.relativePath));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('x');
      expect(await store.hasLocalFile(plugin), isTrue);
    });
  });

  group('PluginDirectInstaller', () {
    test('קובץ חסר מוחזר ככשל, לא כחריג', () async {
      final result = await PluginDirectInstaller.install(
        p.join(temp.path, 'nope.otzplugin'),
      );
      expect(result.success, isFalse);
      expect(result.error, contains('חסר'));
    });

    test('סיומת שאינה otzplugin נדחית', () async {
      final path = p.join(temp.path, 'file.zip');
      File(path).writeAsStringSync('x');

      final result = await PluginDirectInstaller.install(path);
      expect(result.success, isFalse);
      expect(result.error, contains('otzplugin'));
    });
  });
}
