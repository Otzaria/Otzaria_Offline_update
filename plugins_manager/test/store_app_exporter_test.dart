import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

/// בונה מראה של תוספים + מראה של תוכנת החנות, ומחזיר את השתיים.
({PluginMirrorStore store, StoreAppMirror appMirror}) _mirrors(Directory dir) =>
    (
      store: PluginMirrorStore(p.join(dir.path, 'mirror')),
      appMirror:
          StoreAppMirror(mirrorDir: p.join(dir.path, 'mirror', 'store-app')),
    );

/// כותב קובץ הרצה מזויף ואת המטא-דאטה שמצביעה עליו — בדיוק מה ש-`sync`
/// היה משאיר.
Future<StoreAppRelease> _seedApp(StoreAppMirror mirror) async {
  const bytes = 'MZ-not-really-an-exe';
  final filePath =
      p.join(mirror.mirrorDir, 'files', 'v6', 'Otzaria-Plugin-Store.exe');
  File(filePath).parent.createSync(recursive: true);
  File(filePath).writeAsStringSync(bytes);

  final release = StoreAppRelease(
    tagName: 'v6',
    version: 6,
    assetName: 'Otzaria-Plugin-Store.exe',
    downloadUrl: 'https://example.invalid/v6.exe',
    sizeBytes: bytes.length,
    publishedAt: DateTime.utc(2026, 9, 4),
  );
  File(p.join(mirror.mirrorDir, 'latest-release.json')).writeAsStringSync(
    jsonEncode({
      'schemaVersion': 1,
      'release': release.toJson(),
      'filePath': 'files/v6/Otzaria-Plugin-Store.exe',
    }),
  );
  return release;
}

StorePlugin _plugin({
  required String id,
  required String name,
  String? imagePath,
  List<String> screenshots = const [],
  Map<String, PluginLocalFile> localFiles = const {},
}) =>
    StorePlugin(
      id: id,
      name: name,
      shortDescription: '',
      description: '',
      version: '1.0.0',
      status: 'stable',
      author: '',
      updatedAt: '',
      originalDate: '',
      compatibleWith: '',
      maxAppVersion: null,
      requiresNetwork: false,
      tags: const [],
      homepage: '',
      downloadCount: 0,
      supportsDirectInstall: true,
      isFeatured: false,
      remoteDownloadUrl: '',
      imagePath: imagePath,
      screenshotPaths: screenshots,
      localFiles: localFiles,
    );

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  group('StoreAppExporter', () {
    test('כותב Data\\ שהחנות יודעת לקרוא — בלי התחילית files/', () async {
      final (:store, :appMirror) = _mirrors(temp);
      await _seedApp(appMirror);

      // נכסים אמיתיים על הדיסק, במבנה שהסנכרון שלנו יוצר.
      final dir = Directory(store.pluginDir('abc'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'image.png')).writeAsStringSync('png');
      File(p.join(dir.path, 'screenshot-0.png')).writeAsStringSync('shot');
      File(p.join(dir.path, 'plugin-1.0.0.otzplugin')).writeAsStringSync('zip');

      await store.save(PluginCatalog(
        lastSync: DateTime.utc(2026, 9, 1),
        plugins: [
          _plugin(
            id: 'abc',
            name: 'תוסף',
            imagePath: 'files/abc/image.png',
            screenshots: const ['files/abc/screenshot-0.png'],
            localFiles: const {
              '1.0.0': PluginLocalFile(
                relativePath: 'files/abc/plugin-1.0.0.otzplugin',
                fileName: 'plugin.otzplugin',
                ext: '.otzplugin',
                size: 3,
              ),
            },
          ),
        ],
      ));

      final dest = p.join(temp.path, 'dest');
      final outcome = await StoreAppExporter(store: store, appMirror: appMirror)
          .exportTo(dest);

      expect(outcome.plugins, 1);
      expect(outcome.skipped, isEmpty);
      expect(
          File(p.join(dest, 'Otzaria-Plugin-Store.exe')).existsSync(), isTrue);

      // הקבצים יושבים תחת `Data\plugins\<id>\`, בלי שכבת `files`.
      final pluginDir = p.join(dest, 'Data', 'plugins', 'abc');
      expect(File(p.join(pluginDir, 'image.png')).existsSync(), isTrue);
      expect(File(p.join(pluginDir, 'screenshot-0.png')).existsSync(), isTrue);
      expect(
        File(p.join(pluginDir, 'plugin-1.0.0.otzplugin')).existsSync(),
        isTrue,
      );
      expect(Directory(p.join(dest, 'Data', 'files')).existsSync(), isFalse);

      // והקטלוג מצביע עליהם באותה צורה שהחנות כותבת בעצמה.
      final catalog = PluginCatalog.fromJson(jsonDecode(
        File(p.join(dest, 'Data', 'catalog.json')).readAsStringSync(),
      ) as Map<String, dynamic>);
      final exported = catalog.plugins.single;
      expect(exported.imagePath, 'abc/image.png');
      expect(exported.screenshotPaths, ['abc/screenshot-0.png']);
      expect(
        exported.localFiles['1.0.0']!.relativePath,
        'abc/plugin-1.0.0.otzplugin',
      );
      // שדות שאינם נתיבים עוברים כמות שהם — הסכמה זהה משני הצדדים.
      expect(exported.localFiles['1.0.0']!.fileName, 'plugin.otzplugin');
      expect(catalog.lastSync, DateTime.utc(2026, 9, 1));
    });

    test('תוסף שקובצו חסר מהדיסק מדווח כהושמט, והשאר נכתב', () async {
      final (:store, :appMirror) = _mirrors(temp);
      await _seedApp(appMirror);

      Directory(store.pluginDir('ok')).createSync(recursive: true);
      File(p.join(store.pluginDir('ok'), 'plugin-1.0.0.otzplugin'))
          .writeAsStringSync('zip');

      await store.save(PluginCatalog(plugins: [
        _plugin(
          id: 'ok',
          name: 'קיים',
          localFiles: const {
            '1.0.0': PluginLocalFile(
              relativePath: 'files/ok/plugin-1.0.0.otzplugin',
              fileName: 'a.otzplugin',
              ext: '.otzplugin',
              size: 3,
            ),
          },
        ),
        _plugin(
          id: 'gone',
          name: 'חסר',
          localFiles: const {
            '1.0.0': PluginLocalFile(
              relativePath: 'files/gone/plugin-1.0.0.otzplugin',
              fileName: 'b.otzplugin',
              ext: '.otzplugin',
              size: 3,
            ),
          },
        ),
      ]));

      final dest = p.join(temp.path, 'dest');
      final outcome = await StoreAppExporter(store: store, appMirror: appMirror)
          .exportTo(dest);

      expect(outcome.skipped, ['חסר']);
      // הרשומה נשארת בקטלוג בלי קובץ — בדיוק כמו במראה שלנו.
      final catalog = PluginCatalog.fromJson(jsonDecode(
        File(p.join(dest, 'Data', 'catalog.json')).readAsStringSync(),
      ) as Map<String, dynamic>);
      expect(catalog.plugins.length, 2);
      expect(
        catalog.plugins.firstWhere((x) => x.id == 'gone').localFiles,
        isEmpty,
      );
    });

    test('נתיב שיוצא מתיקיית הקבצים אינו מועתק', () async {
      final (:store, :appMirror) = _mirrors(temp);
      await _seedApp(appMirror);
      File(p.join(store.pluginsDir, 'secret.txt'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('nope');

      await store.save(PluginCatalog(plugins: [
        _plugin(id: 'evil', name: 'רע', imagePath: '../secret.txt'),
      ]));

      final dest = p.join(temp.path, 'dest');
      final outcome = await StoreAppExporter(store: store, appMirror: appMirror)
          .exportTo(dest);

      expect(outcome.skipped, ['רע']);
      expect(File(p.join(dest, 'Data', 'secret.txt')).existsSync(), isFalse);
      expect(
        File(p.join(dest, 'Data', 'plugins', 'secret.txt')).existsSync(),
        isFalse,
      );
    });

    test('בלי קובץ הרצה במראה — זורק ואינו כותב Data\\', () async {
      final (:store, :appMirror) = _mirrors(temp);
      await store.save(const PluginCatalog());

      final dest = p.join(temp.path, 'dest');
      await expectLater(
        StoreAppExporter(store: store, appMirror: appMirror).exportTo(dest),
        throwsA(isA<PluginStoreException>()),
      );
      expect(Directory(p.join(dest, 'Data')).existsSync(), isFalse);
    });

    test('קובץ הרצה שנעלם אחרי ההעתקה נכשל ואינו מדווח כהצלחה', () async {
      final (:store, :appMirror) = _mirrors(temp);
      final release = await _seedApp(appMirror);
      await store.save(const PluginCatalog());

      final dest = p.join(temp.path, 'dest');
      final exporter = StoreAppExporter(store: store, appMirror: appMirror);

      // מדמה אנטי-וירוס: הקובץ נמחק בזמן שהייצוא ממשיך הלאה. נתלים
      // ב-callback של ההתקדמות, שרץ בין העתקת ה-exe לכתיבת הקטלוג.
      await expectLater(
        exporter.exportTo(dest, onProgress: (progress) {
          if (progress.phase != StoreAppExportPhase.catalog) return;
          File(p.join(dest, release.assetName)).deleteSync();
        }),
        throwsA(isA<PluginStoreException>()),
      );
    });

    test('hasExistingStore מזהה exe או Data\\, ולא תיקייה ריקה', () async {
      final empty = Directory(p.join(temp.path, 'empty'))..createSync();
      expect(await StoreAppExporter.hasExistingStore(empty.path), isFalse);

      final withData = Directory(p.join(temp.path, 'with-data'))..createSync();
      Directory(p.join(withData.path, 'Data')).createSync();
      expect(await StoreAppExporter.hasExistingStore(withData.path), isTrue);

      final withExe = Directory(p.join(temp.path, 'with-exe'))..createSync();
      File(p.join(withExe.path, 'anything.exe')).writeAsStringSync('x');
      expect(await StoreAppExporter.hasExistingStore(withExe.path), isTrue);
    });
  });

  group('StoreAppReleaseClient', () {
    test('תג bundle נפסל, והגבוה מנצח את סדר הפרסום', () {
      expect(isStoreAppReleaseTag('bundle'), isFalse);
      expect(isStoreAppReleaseTag('v6'), isTrue);
      expect(storeAppVersionOf('v6'), 6);
      expect(storeAppVersionOf('v0.11.0'), isNull);
    });

    test('בוחר את ה-exe הבסיסי ולא את החבילה המלאה', () {
      expect(
        StoreAppReleaseClient.isBasicAppAsset('Otzaria-Plugin-Store.exe'),
        isTrue,
      );
      expect(
        StoreAppReleaseClient.isBasicAppAsset('Otzaria-Plugin-Store-Full.exe'),
        isFalse,
      );
      expect(StoreAppReleaseClient.isBasicAppAsset('notes.txt'), isFalse);
    });

    test('parse מדלג על release בלי אסט מתאים', () {
      expect(
        StoreAppReleaseClient.parse({
          'tag_name': 'v6',
          'assets': [
            {
              'name': 'Otzaria-Plugin-Store-Full.exe',
              'browser_download_url': 'https://x/full.exe',
              'size': 109481164,
            },
          ],
        }),
        isNull,
      );

      final release = StoreAppReleaseClient.parse({
        'tag_name': 'v6',
        'published_at': '2026-09-04T14:09:33Z',
        'assets': [
          {
            'name': 'Otzaria-Plugin-Store.exe',
            'browser_download_url': 'https://x/basic.exe',
            'size': 627200,
          },
        ],
      });
      expect(release!.version, 6);
      expect(release.sizeBytes, 627200);
      expect(release.publishedAt, DateTime.utc(2026, 9, 4, 14, 9, 33));
    });
  });

  group('StoreAppMirror', () {
    test('load מחזיר null כשהקובץ חסר או בגודל שגוי', () async {
      final (store: _, :appMirror) = _mirrors(temp);
      final release = await _seedApp(appMirror);
      expect((await appMirror.load())!.release.tagName, 'v6');

      // גודל שגוי = הורדה שנקטעה.
      File(p.join(appMirror.mirrorDir, 'files', 'v6', release.assetName))
          .writeAsStringSync('short');
      expect(await appMirror.load(), isNull);
    });
  });
}
