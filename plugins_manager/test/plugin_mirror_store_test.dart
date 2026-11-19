import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late PluginMirrorStore store;

  setUp(() {
    temp = createTempDir();
    store = PluginMirrorStore(temp.path);
  });
  tearDown(() => deleteTempDir(temp));

  StorePlugin plugin(String id, {String name = 'תוסף', String? relativePath}) =>
      StorePlugin.fromApi({
        'id': id,
        'name': name,
        'version': '1.0.0',
      }, 'https://otzaria.org')
          .copyWith(
        localFiles: relativePath == null
            ? const {}
            : {
                '1.0.0': PluginLocalFile(
                  relativePath: relativePath,
                  fileName: 'plugin.otzplugin',
                  ext: '.otzplugin',
                  size: 1,
                ),
              },
      );

  group('נתיבים', () {
    test('החנות יושבת תחת plugins/ בתוך המראה של הספרייה', () {
      expect(store.pluginsDir, p.join(temp.path, 'plugins'));
      expect(store.filesDir, p.join(temp.path, 'plugins', 'files'));
      expect(store.catalogPath, p.join(temp.path, 'plugins', 'catalog.json'));
      expect(store.pluginDir('abc'), p.join(store.filesDir, 'abc'));
    });

    test('נתיבים יחסיים נשמרים תמיד עם /', () {
      final absolute = p.join(store.filesDir, 'abc', 'plugin.otzplugin');

      // גם בווינדוס — כדי שקטלוג שנכתב שם ייקרא נכון גם ב-macOS.
      expect(store.relativePath(absolute), 'files/abc/plugin.otzplugin');
      expect(store.absolutePath(store.relativePath(absolute)), absolute);
    });

    test('מזהה בעברית או עם רווחים עובר round-trip', () {
      for (final id in ['my-plugin', 'a.b_c', 'X1']) {
        final absolute = p.join(store.pluginDir(id), 'plugin.otzplugin');
        final relative = store.relativePath(absolute);

        expect(relative, 'files/$id/plugin.otzplugin');
        expect(store.absolutePath(relative), absolute);
      }
    });

    test('מזהה תוסף לא בטוח נדחה כמקטע נתיב', () {
      for (final id in [
        '',
        '..',
        'a..b',
        '../x',
        'a/b',
        'a\\b',
        'C:',
        'מפרשים',
        'a b',
        'x' * 65,
      ]) {
        expect(StorePlugin.isValidId(id), isFalse, reason: id);
        expect(() => store.pluginDir(id), throwsArgumentError, reason: id);
      }
      expect(StorePlugin.isValidId('x' * 64), isTrue);
    });

    test('resolveAgainst דוחה בריחה מהשורש', () {
      for (final path in [
        '../outside',
        'files/../../outside',
        '/etc/passwd/../../x',
        'files\\..\\x',
        'C:/x',
      ]) {
        expect(
          () => PluginMirrorStore.resolveAgainst('/root', path),
          throwsArgumentError,
          reason: path,
        );
        expect(() => store.absolutePath(path), throwsArgumentError);
      }
    });

    test('hasAsset מחזיר false לנתיב בורח במקום לזרוק', () async {
      expect(await store.hasAsset('../../x'), isFalse);
    });

    test('resolveAgainst מתעלם ממקטעים ריקים בנתיב היחסי', () {
      expect(
        PluginMirrorStore.resolveAgainst('/root', 'files//abc/image.png'),
        p.join('/root', 'files', 'abc', 'image.png'),
      );
      expect(PluginMirrorStore.resolveAgainst('/root', ''), '/root');
    });
  });

  group('load', () {
    test('קטלוג חסר מחזיר קטלוג ריק — המצב לפני הסנכרון הראשון', () async {
      final catalog = await store.load();

      expect(catalog.plugins, isEmpty);
      expect(catalog.categories, isEmpty);
      expect(catalog.home, PluginStoreHome.empty);
      expect(catalog.lastSync, isNull);
    });

    test('קטלוג פגום מחזיר קטלוג ריק ולא זורק', () async {
      await store.ensureDirs();
      File(store.catalogPath).writeAsStringSync('{ פגום');

      expect((await store.load()).plugins, isEmpty);
    });

    test('קטלוג שהוא מערך (ולא אובייקט) מחזיר קטלוג ריק', () async {
      await store.ensureDirs();
      File(store.catalogPath).writeAsStringSync('[]');

      expect((await store.load()).plugins, isEmpty);
    });

    test('קטלוג חצי-פגום שומר את הרשומות התקינות', () async {
      await store.ensureDirs();
      File(store.catalogPath).writeAsStringSync(
        jsonEncode({
          'plugins': [
            'לא אובייקט',
            {'id': 'ok', 'name': 'תקין'},
          ],
          'categories': [
            {'name': 'בלי slug'},
            {'slug': 'study', 'name': 'כלי לימוד'},
          ],
        }),
      );

      final catalog = await store.load();
      expect(catalog.plugins.single.id, 'ok');
      expect(catalog.categories.single.slug, 'study');
    });
  });

  group('save', () {
    test('save ואז load מחזירים את אותו קטלוג', () async {
      final catalog = PluginCatalog(
        lastSync: DateTime.utc(2026, 8, 6),
        plugins: [plugin('abc')],
        categories: const [
          PluginStoreCategory(slug: 'study', name: 'כלי לימוד'),
        ],
        home: const PluginStoreHome(title: 'החנות', subtitle: 'תקציר'),
      );

      await store.save(catalog);
      final loaded = await store.load();

      expect(loaded.lastSync, catalog.lastSync);
      expect(loaded.plugins.single.name, 'תוסף');
      expect(loaded.categories.single.slug, 'study');
      expect(loaded.home.title, 'החנות');
    });

    test('save יוצר את תיקיית files ואינו משאיר קובץ tmp', () async {
      await store.save(PluginCatalog.empty);

      expect(Directory(store.filesDir).existsSync(), isTrue);
      expect(
        Directory(store.pluginsDir)
            .listSync()
            .whereType<File>()
            .map((e) => e.path),
        [store.catalogPath],
      );
    });

    test('שמירות במקביל אינן מתנגשות על קובץ זמני משותף', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          store.save(PluginCatalog(plugins: [plugin('p$i')])),
      ]);

      expect((await store.load()).plugins, hasLength(1));
      expect(
        Directory(store.pluginsDir)
            .listSync()
            .whereType<File>()
            .map((e) => e.path),
        [store.catalogPath],
      );
    });

    test('שמירה חוזרת דורסת את הקטלוג הקודם', () async {
      await store.save(PluginCatalog(plugins: [plugin('first')]));
      await store.save(PluginCatalog(plugins: [plugin('second')]));

      expect((await store.load()).plugins.single.id, 'second');
    });

    test('הקטלוג נשמר כ-JSON קריא ובעברית תקינה', () async {
      await store.save(PluginCatalog(plugins: [plugin('abc', name: 'מפרשים')]));

      final text = File(store.catalogPath).readAsStringSync();
      expect(text, contains('מפרשים'));
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
    });

    test('ניקוי מוחק תמונה וצילומי מסך מיושנים ושומר את הרשומים בקטלוג',
        () async {
      final entry = plugin('abc').copyWith(
        imagePath: 'files/abc/image.jpg',
        screenshotPaths: ['files/abc/screenshot-0.png'],
      );
      final dir = Directory(store.pluginDir('abc'))
        ..createSync(recursive: true);
      for (final name in [
        'image.jpg',
        'image.png',
        'image.exe',
        'screenshot-0.png',
        'screenshot-0.gif',
        'screenshot-3.png',
        'notes.txt',
      ]) {
        File(p.join(dir.path, name)).writeAsStringSync('x');
      }

      expect(await store.pruneUnusedFiles(entry), 4);

      expect(
        dir.listSync().map((e) => p.basename(e.path)).toSet(),
        {'image.jpg', 'screenshot-0.png', 'notes.txt'},
      );
    });
  });

  group('hasFileFor', () {
    test('ניקוי שומר הורדה חלקית למקור קיים ומוחק חלקי שהתיישן', () async {
      final entry = plugin('abc');
      final dir = Directory(store.pluginDir(entry.id))
        ..createSync(recursive: true);
      final path = p.join(dir.path, 'plugin-1.0.0.download');
      File('$path.part').writeAsStringSync('abc');
      File('$path.resume').writeAsStringSync(
        jsonEncode({
          'url': entry.remoteDownloadUrl,
          'etag': '"v1"',
          'total': 6,
        }),
      );
      expect(await store.pruneUnusedFiles(entry), 0);
      expect(File('$path.part').existsSync(), isTrue);
      expect(await store.hasFileFor(entry, '1.0.0'), isFalse);

      File('$path.resume').writeAsStringSync(
        jsonEncode({
          'url': 'https://example.test/obsolete',
          'etag': '"old"',
          'total': 6,
        }),
      );
      expect(await store.pruneUnusedFiles(entry), 2);
      expect(File('$path.part').existsSync(), isFalse);
    });

    test('רשומה בלי קובץ אינה קובץ קיים', () async {
      expect(await store.hasFileFor(plugin('abc'), '1.0.0'), isFalse);
    });

    test('מבדיל בין רשומה בקטלוג לקובץ שקיים בפועל', () async {
      final entry = plugin('abc', relativePath: 'files/abc/plugin.otzplugin');
      expect(await store.hasFileFor(entry, '1.0.0'), isFalse);

      final file = File(
        store.absolutePath(entry.localFileFor('1.0.0')!.relativePath),
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pluginBytes('{"id":"real"}'));

      expect(await store.hasFileFor(entry, '1.0.0'), isTrue);
    });

    test('בילד שנשמר בסיומת אחרת מ-.otzplugin נחשב חסר', () async {
      final entry = plugin('abc', relativePath: 'files/abc/plugin-1.0.0.zip');
      final file = File(
        store.absolutePath(entry.localFileFor('1.0.0')!.relativePath),
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pluginBytes('{"id":"real"}'));

      expect(await store.hasFileFor(entry, '1.0.0'), isFalse);
    });

    test('קובץ תחת תיקייה בעברית נמצא', () async {
      final entry = plugin(
        'מפרשים',
        relativePath: 'files/מפרשים/plugin.otzplugin',
      );
      final file = File(
        store.absolutePath(entry.localFileFor('1.0.0')!.relativePath),
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pluginBytes('{"id":"real"}'));

      expect(await store.hasFileFor(entry, '1.0.0'), isTrue);
    });
  });

  group('hasInstallableBuild', () {
    PluginLocalFile local(String path, int size) => PluginLocalFile(
          relativePath: path,
          fileName: p.basename(path),
          ext: p.extension(path),
          size: size,
        );

    test('בילד חסר, נתיב לא בטוח ותיקייה אינם קובץ להתקנה', () async {
      final directory = 'files/a/directory.otzplugin';
      Directory(store.absolutePath(directory)).createSync(recursive: true);

      for (final build in [
        null,
        local('', 0),
        local('../outside.otzplugin', 0),
        local(r'files\..\outside.otzplugin', 0),
        local('files/a/missing.otzplugin', 0),
        local(directory, 0),
      ]) {
        expect(await store.hasInstallableBuild(build), isFalse);
        expect(await store.hasBuild(build), isFalse);
      }
    });

    test('גודל ידוע חייב להתאים וגודל חסר מאפשר קובץ קיים', () async {
      const path = 'files/a/plugin.OTZPLUGIN';
      final file = File(store.absolutePath(path));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([1, 2, 3]);

      for (final (size, expected) in [
        (3, true),
        (2, false),
        (0, true),
        (-1, true)
      ]) {
        final build = local(path, size);
        expect(await store.hasInstallableBuild(build), expected);
        expect(await store.hasBuild(build), expected);
      }
      final entry = plugin('a').copyWith(localFiles: {'1.0.0': local(path, 2)});
      expect(await store.hasFileFor(entry, '1.0.0'), isTrue);
    });

    test('hasBuild נשאר בלתי תלוי בסיומת אך התקנה דורשת otzplugin', () async {
      const path = 'files/a/plugin.zip';
      final file = File(store.absolutePath(path));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([1, 2, 3]);

      final build = local(path, 3);
      expect(await store.hasBuild(build), isTrue);
      expect(await store.hasInstallableBuild(build), isFalse);
    });
  });
}
