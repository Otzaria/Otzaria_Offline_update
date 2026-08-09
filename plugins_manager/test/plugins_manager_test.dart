import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late PluginMirrorStore store;
  final strings = AppL10n.strings.pluginsDomain;

  setUp(() {
    temp = createTempDir();
    store = PluginMirrorStore(temp.path);
  });
  tearDown(() => deleteTempDir(temp));

  PluginsManager manager({http.Client? client}) => PluginsManager(
        resolveMirrorDir: () async => temp.path,
        resolvePluginsDir: () async => p.join(temp.path, 'otzaria', 'plugins'),
        baseUrl: 'https://otzaria.test',
        httpClient: client ?? MockClient((_) async => http.Response('', 404)),
      );

  StorePlugin plugin({
    String id = 'a',
    String name = 'אלף',
    String downloadUrl = '',
    PluginLocalFile? localFile,
  }) =>
      StorePlugin.fromApi(
        {
          'id': id,
          'name': name,
          'version': '1.0.0',
          'downloadUrl': downloadUrl,
        },
        'https://otzaria.test',
      ).copyWith(localFile: localFile);

  /// כותב קובץ `.otzplugin` אמיתי במראה ומחזיר את הרשומה שמצביעה עליו.
  StorePlugin withLocalFile({String id = 'a'}) {
    final file = File(p.join(store.pluginDir(id), 'plugin.otzplugin'));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(pluginBytes('{"id":"manifest-$id"}'));

    return plugin(id: id).copyWith(
      localFile: PluginLocalFile(
        relativePath: store.relativePath(file.path),
        fileName: 'plugin.otzplugin',
        ext: '.otzplugin',
        size: file.lengthSync(),
      ),
    );
  }

  group('load', () {
    test('מראה ריקה נטענת בלי חריג', () async {
      final view = await manager().load();

      expect(view.catalog.plugins, isEmpty);
      expect(view.installed, isEmpty);
      expect(view.pluginsDir, store.pluginsDir);
    });

    test('מחזיר את הקטלוג מהמראה ואת המותקנים מהתקנת אוצריא', () async {
      await store.save(PluginCatalog(plugins: [plugin()]));
      final installed = Directory(
        p.join(temp.path, 'otzaria', 'plugins', 'installed', 'manifest-a',
            'current'),
      )..createSync(recursive: true);
      File(p.join(installed.path, 'manifest.json'))
          .writeAsStringSync('{"id":"manifest-a","version":"1.0.0"}');

      final view = await manager().load();

      expect(view.catalog.plugins.single.id, 'a');
      expect(view.installed, {'manifest-a': '1.0.0'});
    });
  });

  group('assetPath', () {
    test('נתיב ריק או חסר מחזיר null', () async {
      expect(await manager().assetPath(null), isNull);
      expect(await manager().assetPath(''), isNull);
    });

    test('נתיב יחסי מהקטלוג הופך למוחלט מול המראה הנוכחית', () async {
      expect(
        await manager().assetPath('files/a/image.png'),
        p.join(temp.path, 'plugins', 'files', 'a', 'image.png'),
      );
    });
  });

  group('suggestedFileName', () {
    test('משתמש בשם שהאתר החזיר ב-Content-Disposition', () {
      expect(
        manager().suggestedFileName(withLocalFile()),
        'plugin.otzplugin',
      );
    });

    test('בלי קובץ מקומי נבנה שם מהתוסף', () {
      expect(
        manager().suggestedFileName(plugin(name: 'מפרשים')),
        'מפרשים.otzplugin',
      );
    });
  });

  group('saveCopy', () {
    test('בלי קובץ מקומי מוחזר כשל מנוסח', () async {
      final result = await manager().saveCopy(
        plugin(),
        p.join(temp.path, 'out.otzplugin'),
      );

      expect(result.success, isFalse);
      expect(result.error, strings.fileNotAvailableSyncFirst);
    });

    test('רשומה שמצביעה על קובץ שאינו קיים מוחזרת ככשל', () async {
      final entry = plugin(
        localFile: const PluginLocalFile(
          relativePath: 'files/a/plugin.otzplugin',
          fileName: 'plugin.otzplugin',
          ext: '.otzplugin',
          size: 1,
        ),
      );

      final result = await manager().saveCopy(
        entry,
        p.join(temp.path, 'out.otzplugin'),
      );
      expect(result.error, strings.fileNotAvailableSyncFirst);
    });

    test('מעתיק את הקובץ ליעד שנבחר', () async {
      final entry = withLocalFile();
      final dest = p.join(temp.path, 'out.otzplugin');

      final result = await manager().saveCopy(entry, dest);

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(
        File(dest).readAsBytesSync(),
        File(store.absolutePath(entry.localFile!.relativePath))
            .readAsBytesSync(),
      );
    });

    test('יעד שאי אפשר לכתוב אליו מוחזר ככשל ולא כחריג', () async {
      final result = await manager().saveCopy(
        withLocalFile(),
        p.join(temp.path, 'אין-תיקייה', 'out.otzplugin'),
      );

      expect(result.success, isFalse);
      expect(result.error, startsWith(strings.saveFailed('')));
    });
  });

  group('directInstall', () {
    test('בלי קובץ ובלי כתובת הורדה — כשל מנוסח, בלי רשת', () async {
      final result = await manager().directInstall(plugin());

      expect(result.success, isFalse);
      expect(result.error, strings.pluginFileNotAvailable);
    });

    test('כשל בהשלמת הקובץ החסר מוחזר ככשל ולא כחריג', () async {
      final result = await manager(
        client: MockClient((_) async => http.Response('nope', 500)),
      ).directInstall(plugin(downloadUrl: '/api/plugins/a/download'));

      expect(result.success, isFalse);
      expect(result.error, strings.pluginFileNotAvailable);
    });

    test('קובץ חסר מושלם ונרשם בקטלוג לפני ההתקנה', () async {
      // האתר מחזיר סיומת .zip, ולכן ההתקנה נעצרת מיד אחרי ההשלמה —
      // כך אפשר לאמת את ההשלמה בלי להפעיל מטפל פרוטוקול אמיתי.
      final entry = plugin(downloadUrl: '/api/plugins/a/download');
      await store.save(PluginCatalog(plugins: [entry]));

      final result = await manager(
        client: MockClient((_) async => http.Response.bytes(
              pluginBytes('{"id":"manifest-a"}'),
              200,
              headers: {
                'content-disposition': 'attachment; filename="plugin.zip"',
              },
            )),
      ).directInstall(entry);

      expect(result.error, strings.badPluginExtension);

      final saved = (await store.load()).plugins.single;
      expect(saved.localFile?.relativePath, 'files/a/plugin.zip');
      expect(saved.manifestId, 'manifest-a');
      expect(
        File(store.absolutePath(saved.localFile!.relativePath)).existsSync(),
        isTrue,
      );
    });
  });

  group('networkTimeout', () {
    test('נכנס לתוקף בבקשה הבאה', () async {
      final slow = manager(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return jsonResponse(const []);
        }),
      )..networkTimeout = const Duration(milliseconds: 20);

      await expectLater(
        slow.sync(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          startsWith(strings.siteUnreachable('')),
        )),
      );
    });
  });
}
