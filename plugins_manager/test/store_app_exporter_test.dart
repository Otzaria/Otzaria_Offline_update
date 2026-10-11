import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  const mirrored = 'Otzaria-Plugin-Store.exe';
  final filePath = p.join(mirror.mirrorDir, 'files', 'v6', mirrored);
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
      'filePath': 'files/v6/$mirrored',
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

    Map<String, Object?> releaseJson(
      String tag, {
      String asset = 'Otzaria-Plugin-Store.exe',
      bool draft = false,
      bool prerelease = false,
    }) =>
        {
          'tag_name': tag,
          'draft': draft,
          'prerelease': prerelease,
          'assets': [
            {
              'name': asset,
              'browser_download_url': 'https://x/$tag/$asset',
              'size': 100,
            },
          ],
        };

    test('fetchLatestStable מדלג על draft, prerelease ו-bundle ובוחר את הגבוה',
        () async {
      final requests = <http.Request>[];
      final client = StoreAppReleaseClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return jsonResponse([
            releaseJson('v9', draft: true),
            releaseJson('v8', prerelease: true),
            releaseJson('bundle'),
            releaseJson('v7', asset: 'Otzaria-Plugin-Store-Full.exe'),
            releaseJson('v5'),
            releaseJson('v6'),
            'not a release',
          ]);
        }),
      );
      try {
        final latest = await client.fetchLatestStable();
        expect(latest!.tagName, 'v6');
        expect(latest.version, 6);
        expect(latest.downloadUrl, 'https://x/v6/Otzaria-Plugin-Store.exe');
        expect(latest.pageUrl, StoreAppReleaseClient.releasesPageUrl);
      } finally {
        client.dispose();
      }
      expect(requests, hasLength(1));
      expect(
        requests.single.url.path,
        '/repos/Otzaria/otzaria-plugin-store/releases',
      );
      expect(requests.single.headers['User-Agent'], 'otzaria-launcher');
    });

    test('fetchLatestStable מחזיר null כשאין release יציב מתאים', () async {
      final client = StoreAppReleaseClient(
        httpClient: MockClient(
          (_) async => jsonResponse([
            releaseJson('v8', prerelease: true),
            releaseJson('bundle'),
          ]),
        ),
      );
      try {
        expect(await client.fetchLatestStable(), isNull);
      } finally {
        client.dispose();
      }
    });

    test('fetchLatestStable: סטטוס שגוי, תשובה שאינה רשימה וכשל רשת זורקים',
        () async {
      for (final handler in <MockClientHandler>[
        (_) async => http.Response('nope', 503),
        (_) async => jsonResponse({'message': 'Not Found'}),
        (request) async => throw http.ClientException('offline', request.url),
      ]) {
        final client = StoreAppReleaseClient(httpClient: MockClient(handler));
        try {
          await expectLater(
            client.fetchLatestStable(),
            throwsA(isA<PluginStoreException>()),
          );
        } finally {
          client.dispose();
        }
      }
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

    test('מבחין בין "לא הורד" לבין "הורד ונמחק"', () async {
      final (store: _, :appMirror) = _mirrors(temp);
      expect(await appMirror.wasRemoved, isFalse);

      final release = await _seedApp(appMirror);
      expect(await appMirror.wasRemoved, isFalse);

      // מדמה אנטי-וירוס שמחק את הקובץ והשאיר את המטא-דאטה.
      File(p.join(appMirror.mirrorDir, 'files', 'v6', release.assetName))
          .deleteSync();
      expect(await appMirror.load(), isNull);
      expect(await appMirror.wasRemoved, isTrue);
    });

    StoreAppRelease v7({int? sizeBytes}) => StoreAppRelease(
          tagName: 'v7',
          version: 7,
          assetName: 'Otzaria-Plugin-Store.exe',
          downloadUrl: 'https://example.invalid/v7.exe',
          sizeBytes: sizeBytes ?? 'MZ-v7-bytes'.length,
        );

    test('sync מוריד, כותב מטא-דאטה ומנקה את הגרסה הקודמת', () async {
      final mirrorDir = p.join(temp.path, 'mirror', 'store-app');
      await _seedApp(StoreAppMirror(mirrorDir: mirrorDir));
      var requests = 0;
      final mirror = StoreAppMirror(
        mirrorDir: mirrorDir,
        httpClient: MockClient((request) async {
          requests++;
          expect(request.url.toString(), 'https://example.invalid/v7.exe');
          return http.Response.bytes(utf8.encode('MZ-v7-bytes'), 200);
        }),
      );
      try {
        final progress = <int>[];
        final synced = await mirror.sync(
          v7(),
          onProgress: (received, _) => progress.add(received),
        );
        expect(File(synced.filePath).readAsStringSync(), 'MZ-v7-bytes');
        expect(progress.last, 'MZ-v7-bytes'.length);

        final loaded = await mirror.load();
        expect(loaded!.release.tagName, 'v7');
        expect(loaded.filePath, synced.filePath);
        expect(
          Directory(p.join(mirrorDir, 'files', 'v6')).existsSync(),
          isFalse,
        );
        final metadata = jsonDecode(
          File(p.join(mirrorDir, 'latest-release.json')).readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(metadata['filePath'], 'files/v7/Otzaria-Plugin-Store.exe');

        await mirror.sync(v7());
        expect(requests, 1);
      } finally {
        mirror.dispose();
      }
    });

    test('sync שהקובץ שלו בגודל שגוי נכשל ומשאיר את המראה הקודמת', () async {
      final mirrorDir = p.join(temp.path, 'mirror', 'store-app');
      await _seedApp(StoreAppMirror(mirrorDir: mirrorDir));
      final mirror = StoreAppMirror(
        mirrorDir: mirrorDir,
        httpClient: MockClient(
          (_) async => http.Response.bytes(utf8.encode('short'), 200),
        ),
      );
      try {
        await expectLater(
          mirror.sync(v7(sizeBytes: 4096)),
          throwsA(isA<PluginStoreException>()),
        );
        expect((await mirror.load())!.release.tagName, 'v6');
        expect(await mirror.wasRemoved, isFalse);
      } finally {
        mirror.dispose();
      }
    });
  });
}
