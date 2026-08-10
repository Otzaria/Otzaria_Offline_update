import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  group('readId', () {
    test('מחלץ את ה-id מתוך ה-ZIP', () {
      final path = writePluginFile(
        temp,
        'a.otzplugin',
        '{"id":"real-id","version":"1.0.0"}',
      );
      expect(PluginManifestReader.readId(path), 'real-id');
    });

    test('BOM מוביל מוסר לפני הפענוח', () {
      // אותו טיפול בדיוק כמו ב-LogicalContentHasher — עורכים בווינדוס
      // שומרים JSON עם U+FEFF ו-jsonDecode נופל עליו.
      final path = writePluginFile(
        temp,
        'bom.otzplugin',
        '﻿{"id":"with-bom","version":"1.0.0"}',
      );
      expect(PluginManifestReader.readId(path), 'with-bom');
    });

    test('אותו manifest בלי BOM נקרא זהה', () {
      final withBom = writePluginFile(
        temp,
        'with.otzplugin',
        '﻿{"id":"same","version":"1.0.0"}',
      );
      final without = writePluginFile(
        temp,
        'without.otzplugin',
        '{"id":"same","version":"1.0.0"}',
      );
      expect(
        PluginManifestReader.readId(withBom),
        PluginManifestReader.readId(without),
      );
    });

    test('ההסרה אינה מעוגנת לתחילת הקובץ — U+FEFF ראשון בכל מקום יורד', () {
      // התנהגות קיימת של replaceFirst; מזיק רק אם ל-id יש U+FEFF בתוכו,
      // מה שלא קורה בפועל.
      final path = writePluginFile(temp, 'mid.otzplugin', '{"id":"a﻿b"}');
      expect(PluginManifestReader.readId(path), 'ab');
    });

    test('JSON פגום מחזיר null ולא זורק', () {
      final path = writePluginFile(temp, 'bad.otzplugin', '{"id": ');
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('manifest בלי id מחזיר null', () {
      final path = writePluginFile(temp, 'noid.otzplugin', '{"version":"1"}');
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('id שאינו מחרוזת נחשב חסר', () {
      final path = writePluginFile(temp, 'num.otzplugin', '{"id":7}');
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('id ריק או רווחים בלבד נחשב חסר', () {
      expect(
        PluginManifestReader.readId(
          writePluginFile(temp, 'empty.otzplugin', '{"id":""}'),
        ),
        isNull,
      );
      expect(
        PluginManifestReader.readId(
          writePluginFile(temp, 'spaces.otzplugin', '{"id":"   "}'),
        ),
        isNull,
      );
    });

    test('רווחים מסביב ל-id נחתכים', () {
      final path = writePluginFile(temp, 'trim.otzplugin', '{"id":"  x  "}');
      expect(PluginManifestReader.readId(path), 'x');
    });

    test('id בעברית נשמר כמו שהוא', () {
      final path = writePluginFile(temp, 'heb.otzplugin', '{"id":"מפרשים"}');
      expect(PluginManifestReader.readId(path), 'מפרשים');
    });

    test('ZIP בלי manifest.json מחזיר null', () {
      final archive = Archive()
        ..addFile(ArchiveFile('main.js', 3, utf8.encode('/**')));
      final path = p.join(temp.path, 'no-manifest.otzplugin');
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('manifest.json בתת-תיקייה אינו נספר — נדרש בשורש הארכיון', () {
      final path = p.join(temp.path, 'nested.otzplugin');
      File(path).writeAsBytesSync(
        pluginBytes('{"id":"nested"}', entryName: 'plugin/manifest.json'),
      );
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('קובץ שאינו ZIP מחזיר null ולא זורק', () {
      final path = p.join(temp.path, 'broken.otzplugin');
      File(path).writeAsStringSync('זה בכלל לא ארכיון');
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('קובץ ריק מחזיר null', () {
      final path = p.join(temp.path, 'zero.otzplugin');
      File(path).writeAsBytesSync(const []);
      expect(PluginManifestReader.readId(path), isNull);
    });

    test('קובץ שלא קיים מחזיר null', () {
      expect(
        PluginManifestReader.readId(p.join(temp.path, 'nope.otzplugin')),
        isNull,
      );
    });
  });

  group('read', () {
    test('מחזיר את ה-manifest כולו', () {
      final path = writePluginFile(
        temp,
        'full.otzplugin',
        '{"id":"x","version":"1.2.3","name":"תוסף"}',
      );
      final manifest = PluginManifestReader.read(path);

      expect(manifest?['version'], '1.2.3');
      expect(manifest?['name'], 'תוסף');
    });

    test('manifest שאינו אובייקט (מערך) מחזיר null', () {
      final path = writePluginFile(temp, 'arr.otzplugin', '[{"id":"x"}]');
      expect(PluginManifestReader.read(path), isNull);
    });
  });

  group('ההשוואה למותקן היא לפי manifestId ולא לפי id הקטלוג', () {
    test('manifestId מהקובץ הוא שמכריע', () {
      final path = writePluginFile(
        temp,
        'x.otzplugin',
        '{"id":"otzaria-real-id","version":"1.0.0"}',
      );
      final plugin = StorePlugin.fromJson({
        'id': 'cmdb1234website',
        'name': 'תוסף',
        'version': '2.0.0',
        'manifestId': PluginManifestReader.readId(path),
      });

      expect(plugin.manifestId, 'otzaria-real-id');
      expect(
        plugin.statusAgainst({'otzaria-real-id': '1.0.0'}),
        PluginInstallStatus.updateAvailable,
      );
      // המפה ממופתחת ב-id של האתר — בדיוק הרגרסיה שאסור לחזור אליה.
      expect(
        plugin.statusAgainst({'cmdb1234website': '1.0.0'}),
        PluginInstallStatus.notInstalled,
      );
    });
  });
}
