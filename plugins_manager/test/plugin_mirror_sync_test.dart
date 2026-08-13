import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

/// אתר מדומה של החנות. כל נתיב יכול לקבל סטטוס שגיאה בנפרד, כדי לבדוק
/// שכשל בחלק אחד אינו מפיל את השאר.
class _Site {
  _Site({List<Map<String, dynamic>>? plugins})
      : plugins = plugins ?? defaultPlugins();

  static List<Map<String, dynamic>> defaultPlugins({
    String versionA = '1.0.0',
    List<String>? screenshots,
  }) =>
      [
        {
          'id': 'a',
          'name': 'אלף',
          'version': versionA,
          'status': 'stable',
          'isPinned': true,
          'image': '/api/plugins/a/image',
          'screenshots': screenshots ?? const [],
          'downloadUrl': '/api/plugins/a/download',
        },
        {
          'id': 'b',
          'name': 'בית',
          'version': '2.0.0',
          'status': 'beta',
          'downloadUrl': '/api/plugins/b/download',
        },
      ];

  List<Map<String, dynamic>> plugins;

  /// דף הבית מחזיר תוספים רק לקטגוריות שמסומנות להצגה בו.
  Map<String, dynamic> storeHome = {
    'settings': {
      'homeTitle': 'חנות התוספים של אוצריא',
      'homeSubtitle': 'תוספים שמרחיבים את הלימוד',
    },
    'featured': [
      {'id': 'a'}
    ],
    'categories': [
      {
        'slug': 'study',
        'name': 'כלי לימוד',
        'description': 'תוספים שמסייעים בלימוד',
        'showOnHome': true,
        'homeLimit': 4,
        'plugins': [
          {'id': 'a'}
        ],
      },
    ],
    'totalPublicPlugins': 2,
  };

  /// דף הקטגוריה — הסדר הידני המלא, כולל מזהה "רפאים" שאינו בקטלוג.
  Map<String, dynamic> category = {
    'slug': 'study',
    'name': 'כלי לימוד',
    'plugins': [
      {'id': 'b'},
      {'id': 'a'},
      {'id': 'נמחק'},
    ],
    'total': 3,
  };

  /// נתיב -> סטטוס שגיאה שיוחזר במקום התשובה התקינה.
  final Map<String, int> failures = {};
  final List<String> requests = [];

  List<String> requestsMatching(String suffix) =>
      requests.where((r) => r.endsWith(suffix)).toList();

  http.Client build() => MockClient((request) async {
        final path = request.url.path;
        requests.add(path);

        final failure = failures[path];
        if (failure != null) return http.Response('nope', failure);

        if (path == '/api/plugins') return jsonResponse(plugins);
        if (path == '/api/plugins/store-home') return jsonResponse(storeHome);
        if (path.startsWith('/api/plugins/categories/')) {
          return jsonResponse(category);
        }
        if (path.endsWith('/download')) {
          return http.Response.bytes(
            pluginBytes('{"id":"manifest-${path.split('/')[3]}"}'),
            200,
            headers: {
              'content-disposition':
                  "attachment; filename*=UTF-8''plugin.otzplugin",
            },
          );
        }
        // תמונות וצילומי מסך.
        return http.Response.bytes(
          const [137, 80, 78, 71],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
}

void main() {
  late Directory temp;
  final strings = AppL10n.strings.pluginsDomain;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  PluginsManager manager(_Site site) => PluginsManager(
        resolveMirrorDir: () async => temp.path,
        resolvePluginsDir: () async => p.join(temp.path, 'otzaria', 'plugins'),
        baseUrl: 'https://otzaria.test',
        httpClient: site.build(),
      );

  List<String> warningsOf(List<PluginSyncProgress> events) => [
        for (final e in events)
          if (e.phase == PluginSyncPhase.warning) e.message,
      ];

  Future<PluginSyncOutcome> syncOutcome(
    _Site site, {
    List<PluginSyncProgress>? events,
    bool Function()? isCancelled,
  }) =>
      manager(site).sync(
        onProgress: events?.add,
        isCancelled: isCancelled,
      );

  Future<PluginCatalog> sync(
    _Site site, {
    List<PluginSyncProgress>? events,
    bool Function()? isCancelled,
  }) async =>
      (await syncOutcome(site, events: events, isCancelled: isCancelled))
          .catalog;

  group('סנכרון מלא', () {
    test('מושך תוספים, קטגוריות וטקסטים של דף הבית', () async {
      final site = _Site(
        plugins: _Site.defaultPlugins(
          screenshots: ['/api/plugins/a/shot-0', '/api/plugins/a/shot-1'],
        ),
      );
      final catalog = await sync(site);

      expect(catalog.plugins.map((e) => e.id), ['a', 'b']);
      expect(catalog.home.title, 'חנות התוספים של אוצריא');
      expect(catalog.home.subtitle, 'תוספים שמרחיבים את הלימוד');
      expect(catalog.lastSync, isNotNull);

      final category = catalog.categories.single;
      expect(category.slug, 'study');
      // הסיכום (כולל שורת דף-הבית) מגיע מ-store-home...
      expect(category.showOnHome, isTrue);
      expect(category.homeLimit, 4);
      // ...והסדר הידני מדף הקטגוריה; מזהה שאינו בקטלוג יורד בשקט.
      expect(category.pluginIds, ['b', 'a']);

      final featured = catalog.plugins.first;
      expect(featured.isFeatured, isTrue);
      expect(featured.categorySlugs, ['study']);
      expect(featured.manifestId, 'manifest-a');
      expect(featured.imagePath, 'files/a/image.png');
      expect(featured.screenshotPaths, [
        'files/a/screenshot-0.png',
        'files/a/screenshot-1.png',
      ]);
      expect(featured.localFile?.fileName, 'plugin.otzplugin');
      expect(featured.localFile?.ext, '.otzplugin');
      expect(featured.remoteDownloadUrl,
          'https://otzaria.test/api/plugins/a/download');
    });

    test('הקטלוג והקבצים נכתבים למראה ונקראים ממנה בלי רשת', () async {
      await sync(_Site());

      final store = PluginMirrorStore(temp.path);
      final catalog = await store.load();

      expect(catalog.plugins.length, 2);
      expect(
        File(store.absolutePath('files/a/plugin.otzplugin')).existsSync(),
        isTrue,
      );
      expect(File(store.catalogPath).existsSync(), isTrue);
    });

    test('תוסף שאין לו downloadUrl אינו מוריד כלום ונשאר בקטלוג', () async {
      final site = _Site(plugins: [
        {'id': 'c', 'name': 'גימל', 'version': '1.0.0'},
      ]);
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(catalog.plugins.single.id, 'c');
      expect(catalog.plugins.single.localFile, isNull);
      expect(site.requestsMatching('/download'), isEmpty);
      expect(warningsOf(events), isEmpty);
    });
  });

  group('כשל במבנה החנות אינו מפיל את הסנכרון', () {
    test('store-home שנופל משאיר את הקטגוריות והטקסטים שכבר במראה', () async {
      await sync(_Site());

      final site = _Site()..failures['/api/plugins/store-home'] = 404;
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(catalog.categories.single.pluginIds, ['b', 'a']);
      expect(catalog.categories.single.name, 'כלי לימוד');
      expect(catalog.home.title, 'חנות התוספים של אוצריא');
      expect(catalog.plugins.first.categorySlugs, ['study']);
      expect(catalog.plugins.length, 2);
      expect(
        warningsOf(events).single,
        strings.syncStructureFailed(
          strings.loadFailed(strings.whatStoreStructure, 404),
        ),
      );
      // בלי דף הבית אין את מי לשאול על חברות בקטגוריה.
      expect(
        site.requests.where((r) => r.startsWith('/api/plugins/categories')),
        isEmpty,
      );
    });

    test('store-home שנופל בסנכרון ראשון מסתיים בלי קטגוריות ובלי חריג',
        () async {
      final site = _Site()..failures['/api/plugins/store-home'] = 500;
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(catalog.plugins.length, 2);
      expect(catalog.categories, isEmpty);
      expect(catalog.home, PluginStoreHome.empty);
      expect(warningsOf(events), hasLength(1));
      expect(events.last.phase, PluginSyncPhase.done);
    });

    test('דף קטגוריה שנופל שומר את החברות הקודמת מהמראה', () async {
      await sync(_Site());

      final site = _Site()..failures['/api/plugins/categories/study'] = 500;
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(catalog.categories.single.pluginIds, ['b', 'a']);
      expect(
        warningsOf(events).single,
        strings.syncCategoryFailed(
          'כלי לימוד',
          strings.loadFailed(strings.whatCategory('study'), 500),
        ),
      );
    });

    test('דף קטגוריה שנופל בסנכרון ראשון נופל לסיכום של דף הבית', () async {
      final site = _Site()..failures['/api/plugins/categories/study'] = 404;
      final catalog = await sync(site);

      // דף הבית החזיר רק את a — פחות מהחברות המלאה, אבל לא ריק.
      expect(catalog.categories.single.pluginIds, ['a']);
      expect(catalog.plugins.first.categorySlugs, ['study']);
      expect(catalog.plugins.last.categorySlugs, isEmpty);
    });

    test('קטגוריה בלי slug בדף הבית מדולגת', () async {
      final site = _Site()
        ..storeHome = {
          'settings': const {'homeTitle': 'החנות'},
          'categories': [
            {'name': 'בלי slug'},
            'זבל',
          ],
        };
      final catalog = await sync(site);

      expect(catalog.categories, isEmpty);
      expect(catalog.home.title, 'החנות');
    });
  });

  group('כשל ברשימת התוספים עצמה כן עוצר', () {
    test('סטטוס שגיאה ב-/api/plugins זורק ואינו נוגע בקטלוג הקיים', () async {
      await sync(_Site());
      final before =
          File(PluginMirrorStore(temp.path).catalogPath).readAsStringSync();

      final site = _Site()..failures['/api/plugins'] = 503;

      await expectLater(
        sync(site),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.loadFailed(strings.whatPluginList, 503),
        )),
      );
      expect(
        File(PluginMirrorStore(temp.path).catalogPath).readAsStringSync(),
        before,
      );
    });

    test('תשובה שאינה רשימה זורקת', () async {
      final broken = MockClient((_) async => jsonResponse({'plugins': []}));
      final manager = PluginsManager(
        resolveMirrorDir: () async => temp.path,
        baseUrl: 'https://otzaria.test',
        httpClient: broken,
      );

      await expectLater(
        manager.sync(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.responseNotPluginList,
        )),
      );
    });
  });

  group('כשל בנכס בודד', () {
    test('תמונה שנכשלה מדווחת כאזהרה והתוסף נשאר', () async {
      final site = _Site()..failures['/api/plugins/a/image'] = 404;
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(catalog.plugins.length, 2);
      expect(catalog.plugins.first.imagePath, isNull);
      expect(
        warningsOf(events).single,
        strings.syncImageFailed(
          'אלף',
          strings.httpStatusFor(404, '/api/plugins/a/image'),
        ),
      );
    });

    test('צילום מסך אחד שנכשל אינו מוחק את השאר', () async {
      final site = _Site(
        plugins: _Site.defaultPlugins(
          screenshots: ['/api/plugins/a/shot-0', '/api/plugins/a/shot-1'],
        ),
      )..failures['/api/plugins/a/shot-1'] = 500;
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(
          catalog.plugins.first.screenshotPaths, ['files/a/screenshot-0.png']);
      expect(
        warningsOf(events).single,
        strings.syncScreenshotFailed(
          'אלף',
          strings.httpStatusFor(500, '/api/plugins/a/shot-1'),
        ),
      );
    });

    test('קובץ תוסף שלא ירד — התוסף נשאר במצב unknown, וזה תקין', () async {
      final site = _Site()..failures['/api/plugins/a/download'] = 500;
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      final plugin = catalog.plugins.first;
      expect(plugin.localFile, isNull);
      expect(plugin.manifestId, isNull);
      // בלי הקובץ אין manifestId, ולכן אין מול מה להשוות — לא שגיאה.
      expect(
        plugin.statusAgainst({'manifest-a': '1.0.0'}),
        PluginInstallStatus.unknown,
      );
      expect(
        warningsOf(events).single,
        strings.syncPluginFileFailed(
          'אלף',
          // הכתובת המלאה כפי שנשמרה בקטלוג — ממנה מנסים להוריד.
          strings.httpStatusFor(
              500, 'https://otzaria.test/api/plugins/a/download'),
        ),
      );
      expect(events.last.phase, PluginSyncPhase.done);
    });
  });

  group('תשובה ריקה אינה מרוקנת מראה קיימת', () {
    test('רשימת תוספים ריקה מול קטלוג קיים — נזרק, והמראה נשארת', () async {
      await sync(_Site());

      await expectLater(
        sync(_Site(plugins: [])),
        throwsA(isA<StateError>()),
      );
      final onDisk = await PluginMirrorStore(temp.path).load();
      expect(onDisk.plugins.map((e) => e.id), ['a', 'b']);
      expect(onDisk.categories, isNotEmpty);
    });

    test('רשימה ריקה בסנכרון ראשון תקינה — אין מה לאבד', () async {
      final catalog = await sync(_Site(plugins: []));
      expect(catalog.plugins, isEmpty);
    });

    test('דף בית בלי קטגוריות אינו מוחק את אלה שכבר במראה', () async {
      await sync(_Site());

      final site = _Site()..storeHome = {'settings': {}, 'categories': []};
      final events = <PluginSyncProgress>[];
      final catalog = await sync(site, events: events);

      expect(catalog.categories, hasLength(1));
      expect(catalog.categories.single.slug, 'study');
      expect(catalog.home.title, 'חנות התוספים של אוצריא');
      expect(
        warningsOf(events),
        contains(strings.syncStructureFailed(strings.syncStructureEmpty)),
      );
    });
  });

  group('דילוג על הורדה חוזרת', () {
    test('שום דבר לא השתנה — לא הקובץ, לא התמונה ולא צילומי המסך', () async {
      final shots = ['/api/plugins/a/shot-0', '/api/plugins/a/shot-1'];
      await sync(_Site(plugins: _Site.defaultPlugins(screenshots: shots)));

      final second = _Site(plugins: _Site.defaultPlugins(screenshots: shots));
      final events = <PluginSyncProgress>[];
      final outcome = await syncOutcome(second, events: events);
      final catalog = outcome.catalog;

      expect(second.requestsMatching('/download'), isEmpty);
      expect(second.requestsMatching('/image'), isEmpty);
      expect(second.requests.where((r) => r.contains('shot-')), isEmpty);
      // הנתיבים שכבר במראה נשארים בקטלוג, אחרת הדילוג היה מוחק אותם.
      expect(catalog.plugins.first.imagePath, 'files/a/image.png');
      expect(catalog.plugins.first.screenshotPaths, hasLength(2));
      // ולא רק שלא ירד כלום — התוספים האלה לא נכנסו לסבב בכלל.
      expect(outcome.fetched, 0);
      expect(outcome.skipped, 2);
      expect(
        events.where(
            (e) => e.phase == PluginSyncPhase.plugin && e.current != null),
        isEmpty,
      );
    });

    test('קטלוג ישן בלי כתובות הנכסים אינו מוריד את התמונות מחדש', () async {
      final shots = ['/api/plugins/a/shot-0'];
      await sync(_Site(plugins: _Site.defaultPlugins(screenshots: shots)));

      // מדמה קטלוג שנכתב לפני שכתובות הנכסים נכנסו אליו.
      final store = PluginMirrorStore(temp.path);
      final old = await store.load();
      await store.save(PluginCatalog(
        lastSync: old.lastSync,
        categories: old.categories,
        home: old.home,
        plugins: [
          for (final plugin in old.plugins)
            StorePlugin.fromJson(plugin.toJson()
              ..remove('remoteImageUrl')
              ..remove('remoteScreenshotUrls')),
        ],
      ));

      final second = _Site(plugins: _Site.defaultPlugins(screenshots: shots));
      final outcome = await syncOutcome(second);

      // הכתובות נכתבות לקטלוג גם בלי הורדה, ולכן ההגירה נסגרת מעצמה.
      expect(second.requestsMatching('/image'), isEmpty);
      expect(second.requests.where((r) => r.contains('shot-')), isEmpty);
      expect(outcome.fetched, 0);
      expect(
        outcome.catalog.plugins.first.remoteImageUrl,
        '/api/plugins/a/image',
      );
    });

    test('המונה סופר רק את מי שיש בו מה להוריד, לא את כל החנות', () async {
      await sync(_Site());

      // רק a התעדכן; b כבר במראה ולא אמור להיספר.
      final second = _Site(plugins: _Site.defaultPlugins(versionA: '1.1.0'));
      final events = <PluginSyncProgress>[];
      final outcome = await syncOutcome(second, events: events);

      expect(outcome.fetched, 1);
      expect(outcome.skipped, 1);
      expect(outcome.failed, isEmpty);
      final counted = [
        for (final e in events)
          if (e.phase == PluginSyncPhase.plugin && e.current != null) e,
      ];
      expect(counted.single.message, strings.syncPlugin('אלף', 1, 1));
      expect(events.last.message, strings.syncDoneCounts(1, 1));
    });

    test('קובץ שנכשל נספר ככישלון — המראה עדיין חסרה אותו', () async {
      final site = _Site()..failures['/api/plugins/a/download'] = 500;
      final outcome = await syncOutcome(site);

      expect(outcome.failed, ['אלף']);
      expect(outcome.hasFailures, isTrue);
    });

    test('תמונה שהוחלפה באתר יורדת מחדש — לבדה', () async {
      await sync(_Site());

      final second = _Site()
        ..plugins.first['image'] = '/api/plugins/a/image-v2';
      final catalog = await sync(second);

      expect(second.requestsMatching('image-v2'), hasLength(1));
      expect(second.requestsMatching('/download'), isEmpty);
      // שם הקובץ במראה קבוע; מה שהשתנה הוא רק המקור שממנו הוא נמשך.
      expect(catalog.plugins.first.imagePath, 'files/a/image.png');
    });

    test('updatedAt שהשתנה מוריד את התמונה מחדש מאותה כתובת', () async {
      await sync(_Site());

      final second = _Site()..plugins.first['updatedAt'] = '2026-08-13';
      await sync(second);

      expect(second.requestsMatching('/image'), hasLength(1));
      expect(second.requestsMatching('/download'), isEmpty);
    });

    test('תמונה שנמחקה מהמראה יורדת שוב', () async {
      await sync(_Site());
      File(PluginMirrorStore(temp.path).absolutePath('files/a/image.png'))
          .deleteSync();

      final second = _Site();
      await sync(second);

      expect(second.requestsMatching('/image'), hasLength(1));
    });

    test('צילום מסך שנוסף מוריד את כל הסדרה, כי השמות לפי אינדקס', () async {
      await sync(_Site(
        plugins: _Site.defaultPlugins(screenshots: ['/api/plugins/a/shot-0']),
      ));

      final second = _Site(
        plugins: _Site.defaultPlugins(
          screenshots: ['/api/plugins/a/shot-new', '/api/plugins/a/shot-0'],
        ),
      );
      final catalog = await sync(second);

      expect(second.requests.where((r) => r.contains('shot-')), hasLength(2));
      expect(catalog.plugins.first.screenshotPaths, [
        'files/a/screenshot-0.png',
        'files/a/screenshot-1.png',
      ]);
    });

    test('כתובת הורדה שהשתנתה מורידה מחדש גם באותה גרסה', () async {
      await sync(_Site());

      final second = _Site()
        ..plugins.first['downloadUrl'] = '/api/plugins/a/download?v=2';
      await sync(second);

      expect(second.requestsMatching('/download'), hasLength(1));
    });

    test('הורדה שנכשלה — הגרסה בקטלוג נשארת של הקובץ שבמראה, ויורד בסבב הבא',
        () async {
      await sync(_Site());

      // גרסה חדשה באתר, אבל ההורדה נופלת: הקטלוג חייב להמשיך לתאר את 1.0.0,
      // אחרת בדיקת ה-unchanged תתאים לנצח והקובץ החדש לא יירד לעולם.
      final failing = _Site(plugins: _Site.defaultPlugins(versionA: '1.1.0'))
        ..failures['/api/plugins/a/download'] = 500;
      final afterFailure = await sync(failing);
      expect(afterFailure.plugins.first.version, '1.0.0');

      final retry = _Site(plugins: _Site.defaultPlugins(versionA: '1.1.0'));
      final catalog = await sync(retry);
      expect(retry.requestsMatching('/download'), ['/api/plugins/a/download']);
      expect(catalog.plugins.first.version, '1.1.0');
    });

    test('גרסה שהשתנתה מורידה מחדש', () async {
      await sync(_Site());

      final second = _Site(plugins: _Site.defaultPlugins(versionA: '1.1.0'));
      final catalog = await sync(second);

      expect(second.requestsMatching('/download'), ['/api/plugins/a/download']);
      expect(catalog.plugins.first.version, '1.1.0');
      expect(catalog.plugins.first.manifestId, 'manifest-a');
    });

    test('manifestId חסר מקטלוג ישן מחולץ מהקובץ הקיים בלי הורדה', () async {
      await sync(_Site());

      // מדמה קטלוג שנכתב לפני שה-manifestId נכנס אליו.
      final store = PluginMirrorStore(temp.path);
      final old = await store.load();
      await store.save(PluginCatalog(
        lastSync: old.lastSync,
        categories: old.categories,
        home: old.home,
        plugins: [
          for (final plugin in old.plugins)
            StorePlugin.fromJson(plugin.toJson()..remove('manifestId')),
        ],
      ));
      expect((await store.load()).plugins.first.manifestId, isNull);

      final second = _Site();
      final catalog = await sync(second);

      expect(catalog.plugins.first.manifestId, 'manifest-a');
      expect(second.requestsMatching('/download'), isEmpty);
    });
  });

  group('ביטול', () {
    test('סנכרון שבוטל אינו מושך מבנה חדש ושומר את הקודם', () async {
      await sync(_Site());

      var calls = 0;
      // שני התוספים התחדשו, ולכן לשניהם יש מה להוריד — והביטול תופס באמצע.
      final bumped = _Site.defaultPlugins(versionA: '1.1.0');
      bumped[1]['version'] = '2.1.0';
      final site = _Site(plugins: bumped);
      final catalog = await sync(site, isCancelled: () => ++calls > 1);

      // מה שהספיק להסתנכרן מתעדכן, ומה שכבר היה במראה נשמר — אחרת תוספים
      // שקבצים שלהם על הדיסק היו נעלמים מהמחשב המנותק עד סנכרון מלא.
      expect(catalog.plugins.map((e) => e.id), ['a', 'b']);
      expect(catalog.plugins.first.version, '1.1.0');
      // b לא הגיע תורו: הקטלוג חייב להמשיך לתאר את הקובץ שבמראה, אחרת
      // התכנון הבא היה מדלג עליו והגרסה החדשה לא הייתה יורדת לעולם.
      expect(catalog.plugins.last.version, '2.0.0');
      expect(catalog.categories.single.pluginIds, ['b', 'a']);
      expect(catalog.home.title, 'חנות התוספים של אוצריא');
      expect(site.requests, isNot(contains('/api/plugins/store-home')));
    });
  });

  group('דיווח התקדמות', () {
    test('הסדר: start, תוסף אחר תוסף, done — ומונוטוני', () async {
      final events = <PluginSyncProgress>[];
      await sync(_Site(), events: events);

      expect(events.first.phase, PluginSyncPhase.start);
      expect(events.first.message, strings.syncLoadingCatalog);
      expect(events.last.phase, PluginSyncPhase.done);
      expect(events.last.message, strings.syncDoneCounts(2, 0));
      expect(events.last.fraction, 1.0);

      final counted = [
        for (final e in events)
          if (e.current != null) e,
      ];
      expect(counted.map((e) => e.current), [1, 2, 2]);
      for (final event in counted) {
        expect(event.total, 2);
        expect(event.fraction, inInclusiveRange(0, 1));
      }

      final pluginEvents = events
          .where((e) => e.phase == PluginSyncPhase.plugin && e.current != null)
          .toList();
      expect(pluginEvents.first.message, strings.syncPlugin('אלף', 1, 2));
      expect(pluginEvents.last.message, strings.syncPlugin('בית', 2, 2));
      expect(
        events.map((e) => e.message),
        contains(strings.syncCategories),
      );
    });
  });

  group('תוכן מהאתר אינו מתורגם', () {
    tearDown(() => AppL10n.use(AppLanguage.hebrew));

    test('שמות, תיאורים וטקסטי דף הבית נשמרים כמו שהם גם באנגלית', () async {
      AppL10n.use(AppLanguage.english);
      final english = AppL10n.strings.pluginsDomain;

      final events = <PluginSyncProgress>[];
      final catalog = await sync(_Site(), events: events);

      // התוכן — כמו שהאתר שלח.
      expect(catalog.plugins.first.name, 'אלף');
      expect(catalog.categories.single.name, 'כלי לימוד');
      expect(catalog.categories.single.description, 'תוספים שמסייעים בלימוד');
      expect(catalog.home.title, 'חנות התוספים של אוצריא');
      // המסגרת סביבו — מתורגמת.
      expect(events.last.message, english.syncDoneCounts(2, 0));
      expect(events.first.message, english.syncLoadingCatalog);
    });

    test('כותרת ריקה נשארת ריקה — הנפילה לברירת מחדל היא של הממשק', () async {
      final site = _Site()
        ..storeHome = {
          'settings': const {},
          'categories': const [],
        };
      final catalog = await sync(site);

      expect(catalog.home.title, '');
      expect(catalog.home.isEmpty, isTrue);
    });
  });

  group('זיהוי מותקן אחרי סנכרון', () {
    test('ההשוואה נעשית מול manifestId שחולץ מהקובץ שירד', () async {
      final site = _Site();
      await sync(site);

      // אוצריא מתקינה תחת installed/<manifest.id>/, לא תחת ה-id של האתר.
      final installed = Directory(
        p.join(temp.path, 'otzaria', 'plugins', 'installed', 'manifest-a',
            'current'),
      )..createSync(recursive: true);
      File(p.join(installed.path, 'manifest.json'))
          .writeAsStringSync('{"id":"manifest-a","version":"0.9.0"}');

      final view = await manager(site).load();
      final plugin = view.catalog.plugins.firstWhere((e) => e.id == 'a');

      expect(view.installed, {'manifest-a': '0.9.0'});
      expect(
        plugin.statusAgainst(view.installed),
        PluginInstallStatus.updateAvailable,
      );
      // מפה שממופתחת ב-id של הקטלוג לא מזהה כלום.
      expect(
        plugin.statusAgainst({'a': '0.9.0'}),
        PluginInstallStatus.notInstalled,
      );
    });
  });
}
