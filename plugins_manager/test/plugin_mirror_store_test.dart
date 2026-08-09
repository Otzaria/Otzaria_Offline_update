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
      StorePlugin.fromApi(
        {'id': id, 'name': name, 'version': '1.0.0'},
        'https://otzaria.org',
      ).copyWith(
        localFile: relativePath == null
            ? null
            : PluginLocalFile(
                relativePath: relativePath,
                fileName: 'plugin.otzplugin',
                ext: '.otzplugin',
                size: 1,
              ),
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
      for (final id in ['מפרשים', 'a b', 'שם עם רווח']) {
        final absolute = p.join(store.pluginDir(id), 'plugin.otzplugin');
        final relative = store.relativePath(absolute);

        expect(relative, 'files/$id/plugin.otzplugin');
        expect(store.absolutePath(relative), absolute);
      }
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
      File(store.catalogPath).writeAsStringSync(jsonEncode({
        'plugins': [
          'לא אובייקט',
          {'id': 'ok', 'name': 'תקין'},
        ],
        'categories': [
          {'name': 'בלי slug'},
          {'slug': 'study', 'name': 'כלי לימוד'},
        ],
      }));

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
      expect(File('${store.catalogPath}.tmp').existsSync(), isFalse);
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
  });

  group('hasLocalFile', () {
    test('רשומה בלי localFile אינה קובץ קיים', () async {
      expect(await store.hasLocalFile(plugin('abc')), isFalse);
    });

    test('מבדיל בין רשומה בקטלוג לקובץ שקיים בפועל', () async {
      final entry = plugin('abc', relativePath: 'files/abc/plugin.otzplugin');
      expect(await store.hasLocalFile(entry), isFalse);

      final file = File(store.absolutePath(entry.localFile!.relativePath));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pluginBytes('{"id":"real"}'));

      expect(await store.hasLocalFile(entry), isTrue);
    });

    test('קובץ תחת תיקייה בעברית נמצא', () async {
      final entry = plugin(
        'מפרשים',
        relativePath: 'files/מפרשים/plugin.otzplugin',
      );
      final file = File(store.absolutePath(entry.localFile!.relativePath));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pluginBytes('{"id":"real"}'));

      expect(await store.hasLocalFile(entry), isTrue);
    });
  });
}
