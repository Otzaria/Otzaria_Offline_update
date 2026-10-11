import 'dart:convert';
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
  }) => StorePlugin.fromApi(
    {'id': id, 'name': name, 'version': '1.0.0', 'downloadUrl': downloadUrl},
    'https://otzaria.test',
  ).copyWith(localFiles: localFile == null ? const {} : {'1.0.0': localFile});

  /// כותב קובץ `.otzplugin` אמיתי במראה ומחזיר את הרשומה שמצביעה עליו.
  StorePlugin withLocalFile({String id = 'a'}) {
    final file = File(p.join(store.pluginDir(id), 'plugin.otzplugin'));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(pluginBytes('{"id":"manifest-$id"}'));

    return plugin(id: id).copyWith(
      localFiles: {
        '1.0.0': PluginLocalFile(
          relativePath: store.relativePath(file.path),
          fileName: 'plugin.otzplugin',
          ext: '.otzplugin',
          size: file.lengthSync(),
        ),
      },
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
        p.join(
          temp.path,
          'otzaria',
          'plugins',
          'installed',
          'manifest-a',
          'current',
        ),
      )..createSync(recursive: true);
      File(p.join(installed.path, 'manifest.json'))
          .writeAsStringSync('{"id":"manifest-a","version":"1.0.0"}');

      final view = await manager().load();

      expect(view.catalog.plugins.single.id, 'a');
      expect(view.installed, {'manifest-a': '1.0.0'});
    });
  });

  group('otzariaLaunchPath', () {
    /// התקנה ניידת של אוצריא עם תוסף מותקן בתיקיית הנתונים שלידה.
    String portableInstall() {
      final exeDir = Directory(p.join(temp.path, 'app'))
        ..createSync(recursive: true);
      final exe = p.join(exeDir.path, 'otzaria.exe');
      File(exe).writeAsStringSync('');
      File(p.join(exeDir.path, InstalledPluginsScanner.portableMarkerFileName))
          .writeAsStringSync('');

      final installed = Directory(
        p.join(
          exeDir.path,
          InstalledPluginsScanner.portableDataFolderName,
          'plugins',
          'installed',
          'manifest-a',
          'current',
        ),
      )..createSync(recursive: true);
      File(p.join(installed.path, 'manifest.json'))
          .writeAsStringSync('{"id":"manifest-a","version":"2.5.0"}');
      return exe;
    }

    PluginsManager portableManager(String exe) => PluginsManager(
      resolveMirrorDir: () async => temp.path,
      otzariaLaunchPath: () async => exe,
      baseUrl: 'https://otzaria.test',
      httpClient: MockClient((_) async => http.Response('', 404)),
    );

    test(
      'בלי נתיב מפורש הסריקה נגזרת מההתקנה שזוהתה, לא מ-%APPDATA%',
      () async {
        final view = await portableManager(portableInstall()).load();

        expect(view.installed, {'manifest-a': '2.5.0'});
      },
    );

    test('scanInstalled מחזיר את אותה מפה בלי לקרוא את הקטלוג', () async {
      final manager = portableManager(portableInstall());
      await store.save(PluginCatalog(plugins: [plugin()]));

      expect(await manager.scanInstalled(), (await manager.load()).installed);
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
      expect(manager().suggestedFileName(withLocalFile()), 'plugin.otzplugin');
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
        File(store.absolutePath(entry.anyLocalFile!.relativePath))
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
      final reported = <StorePlugin>[];
      final result =
          await manager(
            client: MockClient((_) async => http.Response('nope', 500)),
          ).directInstall(
            plugin(downloadUrl: '/api/plugins/a/download'),
            onPluginUpdated: reported.add,
          );

      expect(result.success, isFalse);
      expect(result.error, strings.pluginFileNotAvailable);
      expect(reported, isEmpty);
    });

    test('דף HTML במקום קובץ תוסף אינו נרשם בקטלוג ואינו נשאר בדיסק', () async {
      final entry = plugin(downloadUrl: '/api/plugins/a/download');
      await store.save(PluginCatalog(plugins: [entry]));

      final result = await manager(
        client: MockClient((_) async => http.Response('<html></html>', 200)),
      ).directInstall(entry);

      expect(result.success, isFalse);
      expect(result.error, strings.pluginFileNotAvailable);
      expect((await store.load()).plugins.single.localFiles, isEmpty);
      expect(
        Directory(store.pluginDir('a'))
            .listSync()
            .where((e) => p.basename(e.path).startsWith('plugin-1.0.0')),
        isEmpty,
      );
    });

    test('קובץ חסר מושלם ונרשם בקטלוג לפני ההתקנה', () async {
      final entry = plugin(downloadUrl: '/api/plugins/a/download');
      await store.save(PluginCatalog(plugins: [entry]));
      var reachedInstall = false;
      final reported = <StorePlugin>[];

      await expectLater(
        PluginsManager(
          resolveMirrorDir: () async => temp.path,
          resolvePluginsDir: () async =>
              p.join(temp.path, 'otzaria', 'plugins'),
          baseUrl: 'https://otzaria.test',
          httpClient: MockClient(
            (_) async => http.Response.bytes(
              pluginBytes('{"id":"manifest-a"}'),
              200,
              headers: {
                'content-disposition': 'attachment; filename="plugin.zip"',
              },
            ),
          ),
          otzariaLaunchPath: () async {
            reachedInstall = true;
            throw const _StopBeforeLaunch();
          },
        ).directInstall(entry, onPluginUpdated: reported.add),
        throwsA(isA<_StopBeforeLaunch>()),
      );

      expect(reachedInstall, isTrue);
      expect(reported, hasLength(1));
      expect(reported.single.manifestId, 'manifest-a');
      expect(
        reported.single.localFileFor('1.0.0')?.relativePath,
        'files/a/plugin-1.0.0.otzplugin',
      );
      final saved = (await store.load()).plugins.single;
      expect(
        saved.anyLocalFile?.relativePath,
        'files/a/plugin-1.0.0.otzplugin',
      );
      expect(saved.anyLocalFile?.fileName, 'plugin.otzplugin');
      expect(saved.manifestId, 'manifest-a');
      expect(await store.hasFileFor(saved, '1.0.0'), isTrue);
      expect(
        File(store.absolutePath(saved.anyLocalFile!.relativePath)).existsSync(),
        isTrue,
      );
    });

    test('קטלוג פגום נשמר אחרי השלמת קובץ בסיומת התקינה', () async {
      const torn = '{"plugins": [{"id": "a", "na';
      await store.ensureDirs();
      File(store.catalogPath).writeAsStringSync(torn);

      await expectLater(
        PluginsManager(
          resolveMirrorDir: () async => temp.path,
          resolvePluginsDir: () async =>
              p.join(temp.path, 'otzaria', 'plugins'),
          baseUrl: 'https://otzaria.test',
          httpClient: MockClient(
            (_) async => http.Response.bytes(
              pluginBytes('{"id":"manifest-a"}'),
              200,
              headers: {
                'content-disposition': 'attachment; filename="plugin.zip"',
              },
            ),
          ),
          otzariaLaunchPath: () async => throw const _StopBeforeLaunch(),
        ).directInstall(plugin(downloadUrl: '/api/plugins/a/download')),
        throwsA(isA<_StopBeforeLaunch>()),
      );

      expect(
        File(p.join(store.pluginDir('a'), 'plugin-1.0.0.otzplugin'))
            .existsSync(),
        isTrue,
      );
      expect(File(store.catalogPath).readAsStringSync(), torn);
    });
  });

  group('mirrorDirsIn', () {
    test('תוכנת החנות נקראת מהתיקייה ש-mirrorDirsIn מכריז עליה', () async {
      final storeAppDir = PluginsManager.storeAppDirIn(temp.path);
      expect(PluginsManager.mirrorDirsIn(temp.path), [
        store.pluginsDir,
        storeAppDir,
      ]);

      const bytes = 'MZ';
      final exe = File(p.join(storeAppDir, 'files', 'v6', 'Store.exe'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(bytes);
      final release = StoreAppRelease(
        tagName: 'v6',
        version: 6,
        assetName: 'Store.exe',
        downloadUrl: 'https://example.invalid/v6.exe',
        sizeBytes: bytes.length,
        publishedAt: DateTime.utc(2026, 9, 4),
      );
      File(p.join(storeAppDir, 'latest-release.json')).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'release': release.toJson(),
          'filePath': 'files/v6/Store.exe',
        }),
      );

      final loaded = await manager().loadStoreApp();

      expect(loaded?.filePath, exe.path);
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
        throwsA(
          isA<PluginStoreException>().having(
            (e) => e.message,
            'message',
            startsWith(strings.siteUnreachable('')),
          ),
        ),
      );
    });
  });
}

class _StopBeforeLaunch implements Exception {
  const _StopBeforeLaunch();
}
