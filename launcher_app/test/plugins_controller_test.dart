import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart' show OtzariaCapabilities;
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_support.dart';

/// בדיקות ל-[PluginsModuleController] — הכול מהמראה המקומית, תחת חסימת
/// רשת מלאה. `load` חייב לעבוד בלי רשת; `sync` היא הפעולה היחידה שדורשת
/// אותה, וכשלונה הוא מצב שגיאה מוצג ולא קריסה.
void main() {
  late Directory tempDir;
  late PluginsModuleController controller;

  StorePlugin plugin(
    String id,
    String name, {
    String status = 'stable',
    String version = '1.0.0',
    List<String> tags = const [],
    bool featured = false,
    String shortDescription = '',
    String author = '',
    String? manifestId,
    String? publishedAt,
    String? fileUpdatedAt,
  }) =>
      StorePlugin.fromApi({
        'id': id,
        'name': name,
        'status': status,
        'version': version,
        'tags': tags,
        'isPinned': featured,
        'shortDescription': shortDescription,
        'author': author,
        'publishedAt': publishedAt,
        'fileUpdatedAt': fileUpdatedAt,
      }, 'https://otzaria.org')
          .copyWith(manifestId: manifestId);

  Future<void> saveCatalog(PluginCatalog catalog) =>
      PluginMirrorStore(p.join(tempDir.path, 'mirror')).save(catalog);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugins-ctrl-');
    HttpOverrides.global = NoNetworkHttpOverrides();
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
    controller = PluginsModuleController(
      mirrorRootDir: p.join(tempDir.path, 'mirror'),
    );
    AppL10n.use(AppLanguage.hebrew);
  });

  tearDown(() async {
    controller.dispose();
    HttpOverrides.global = null;
    AppL10n.use(AppLanguage.hebrew);
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  group('תוספים חדשים — פעם אחת בכל מחשב', () {
    PluginsModuleController withState() => PluginsModuleController(
          mirrorRootDir: p.join(tempDir.path, 'mirror'),
          stateDir: p.join(tempDir.path, 'state'),
        );

    test('הטעינה הראשונה קובעת נקודת התחלה: שום דבר אינו חדש', () async {
      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'א', manifestId: 'a'),
            plugin('b', 'ב', manifestId: 'b'),
          ],
        ),
      );
      final c = withState();
      addTearDown(c.dispose);

      await c.load();

      expect(c.newPlugins, isEmpty);
      expect(c.newPluginsForHome, isEmpty);
    });

    test(
      'קטלוג ריק אינו נקודת התחלה — הסנכרון הראשון לא מכריז על כולו',
      () async {
        final first = withState();
        addTearDown(first.dispose);
        await first.load();

        await saveCatalog(
          PluginCatalog(
            plugins: [
              plugin('a', 'א', manifestId: 'a'),
              plugin('b', 'ב', manifestId: 'b'),
            ],
          ),
        );
        final second = withState();
        addTearDown(second.dispose);
        await second.load();

        expect(second.newPlugins, isEmpty);
      },
    );

    test('תוסף שנוסף אחרי נקודת ההתחלה הוא חדש, ונאמר פעם אחת', () async {
      await saveCatalog(
        PluginCatalog(plugins: [plugin('a', 'א', manifestId: 'a')]),
      );
      final first = withState();
      addTearDown(first.dispose);
      await first.load();

      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'א', manifestId: 'a'),
            plugin('b', 'ב', manifestId: 'b'),
          ],
        ),
      );
      final second = withState();
      addTearDown(second.dispose);
      await second.load();

      expect(second.newPlugins.map((x) => x.id), ['b']);
      await second.markNewSeen(second.newPlugins);
      expect(second.newPlugins, isEmpty);

      final third = withState();
      addTearDown(third.dispose);
      await third.load();
      expect(third.newPlugins, isEmpty);
    });

    test('הטוסט והחלון שבמסך הראשי נרשמים בנפרד', () async {
      await saveCatalog(
        PluginCatalog(plugins: [plugin('a', 'א', manifestId: 'a')]),
      );
      final first = withState();
      addTearDown(first.dispose);
      await first.load();

      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'א', manifestId: 'a'),
            plugin('b', 'ב', manifestId: 'b'),
          ],
        ),
      );
      final c = withState();
      addTearDown(c.dispose);
      await c.load();

      await c.markHomeNotified(c.newPluginsForHome);

      expect(c.newPluginsForHome, isEmpty);
      expect(c.newPlugins.map((x) => x.id), ['b']);
    });

    test('תוסף שכבר נראה בחנות אינו מוזכר שוב במסך הראשי', () async {
      await saveCatalog(
        PluginCatalog(plugins: [plugin('a', 'א', manifestId: 'a')]),
      );
      final first = withState();
      addTearDown(first.dispose);
      await first.load();

      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'א', manifestId: 'a'),
            plugin('b', 'ב', manifestId: 'b'),
          ],
        ),
      );
      final c = withState();
      addTearDown(c.dispose);
      await c.load();

      await c.markNewSeen(c.newPlugins);

      expect(c.newPluginsForHome, isEmpty);
    });

    test('תוסף שכבר מותקן כאן אינו חדש', () async {
      await saveCatalog(
        PluginCatalog(plugins: [plugin('a', 'א', manifestId: 'a')]),
      );
      final first = withState();
      addTearDown(first.dispose);
      await first.load();

      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'א', manifestId: 'a'),
            plugin('b', 'ב', manifestId: 'b'),
          ],
        ),
      );
      final c = withState();
      addTearDown(c.dispose);
      await c.load();
      c.installed = {'b': '1.0.0'};

      expect(c.newPlugins, isEmpty);
    });

    test('בלי תיקיית כתיבה אין הודעות בכלל', () async {
      await saveCatalog(
        PluginCatalog(plugins: [plugin('a', 'א', manifestId: 'a')]),
      );
      await controller.load();

      expect(controller.newPlugins, isEmpty);
      expect(controller.newPluginsForHome, isEmpty);
    });
  });

  group('load — מהמראה בלבד', () {
    test('מראה ריקה: קטלוג ריק, מצב ready, בלי שגיאה', () async {
      await controller.load();

      expect(controller.status, PluginsModuleStatus.ready);
      expect(controller.errorMessage, isNull);
      expect(controller.plugins, isEmpty);
      expect(controller.categories, isEmpty);
      expect(controller.lastSync, isNull);
      expect(controller.pluginsDir, p.join(tempDir.path, 'mirror', 'plugins'));
    });

    test('תגית שנעלמה מהחנות אינה נשארת מסנן פעיל ובלתי נראה', () async {
      await saveCatalog(PluginCatalog(plugins: [
        plugin('a', 'תוסף', tags: ['ישנה']),
        plugin('b', 'אחר', tags: ['נשארת']),
      ]));
      await controller.load();
      controller.setTagFilter('ישנה');
      expect(controller.moreFiltersCount, 1);

      await saveCatalog(PluginCatalog(plugins: [
        plugin('a', 'תוסף', tags: ['נשארת']),
        plugin('b', 'אחר', tags: ['נשארת']),
      ]));
      await controller.load();

      expect(controller.tagFilter, isNull);
      expect(controller.moreFiltersCount, 0);
      expect(controller.filtered.map((p) => p.id), ['a', 'b']);

      // תגית שעדיין קיימת נשמרת גם אחרי טעינה מחדש.
      controller.setTagFilter('נשארת');
      await controller.load();
      expect(controller.tagFilter, 'נשארת');
    });

    test('שבב קטגוריה שנעלמה מהחנות מתאפס ל"הכול"', () async {
      await saveCatalog(
        PluginCatalog(
          plugins: [plugin('a', 'תוסף')],
          categories: const [
            PluginStoreCategory(
              slug: 'study',
              name: 'לימוד',
              pluginIds: ['a'],
            ),
          ],
        ),
      );
      await controller.load();
      controller.setCategory('study');
      expect(controller.categoryFilter, 'study');

      await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));
      await controller.load();

      expect(controller.categoryFilter, isNull);
      expect(controller.filtered.map((p) => p.id), ['a']);
    });
  });

  test('a failed installed-plugin scan still refreshes app compatibility',
      () async {
    final c = PluginsModuleController(
      mirrorRootDir: p.join(tempDir.path, 'mirror'),
      otzariaLaunchPath: () async =>
          throw const FileSystemException('unreadable'),
      installedAppVersion: () async => '0.9.97',
    )
      ..status = PluginsModuleStatus.ready
      ..appVersion = '0.9.96'
      ..installed = {'known': '1.0.0'};
    addTearDown(c.dispose);

    await c.refreshInstalled();

    expect(c.appVersion, '0.9.97');
    expect(c.installed, {'known': '1.0.0'});
  });

  group('סינון', () {
    setUp(() async {
      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin(
              'a',
              'מפתח ראשי',
              tags: ['לימוד'],
              author: 'שרה',
              shortDescription: 'תקציר א',
            ),
            plugin('b', 'תוסף בטא', status: 'beta', tags: ['עיצוב']),
            plugin('c', 'תוסף ניסיוני', status: 'experimental'),
          ],
        ),
      );
      await controller.load();
      // ההתקנה האמיתית של המכונה המריצה לא אמורה להשפיע על התוצאה.
      controller.installed = const {};
    });

    test('search reuses catalog normalization across queries and filters', () {
      final entry = _SearchPlugin('a', 'תיאור ארוך');
      controller.plugins = [entry];
      controller.setSearch('לא נמצא');
      expect(controller.filtered, isEmpty);
      final reads = entry.descriptionReads;
      expect(reads, greaterThan(0));

      controller.setSearch('עדיין לא נמצא');
      expect(controller.filtered, isEmpty);
      controller.setSortMode(PluginSortMode.newest);
      expect(controller.filtered, isEmpty);
      controller.setStatusFilter(PluginStatusFilter.stable);
      expect(controller.filtered, isEmpty);
      expect(entry.descriptionReads, reads);

      final changed = _SearchPlugin('a', 'התיאור החדש');
      expect(changed, entry);
      controller.plugins = [changed];
      controller.setSearch('החדש');
      expect(controller.filtered, [changed]);
      expect(changed.descriptionReads, greaterThan(0));
      controller.setSearch('ארוך');
      expect(controller.filtered, isEmpty);
    });

    test('equal catalog identities keep separate search fields', () {
      final first = _SearchPlugin('a', 'תיאור ראשון');
      final second = _SearchPlugin('a', 'תיאור שני');
      expect(first, second);
      controller.plugins = [first, second];
      controller.setSearch('שני');
      expect(controller.filtered.single, same(second));
      controller.setSearch('ראשון');
      expect(controller.filtered.single, same(first));
      controller.setSearch('לוח תיאור');
      expect(controller.filtered, isEmpty);
    });

    test('בלי סינון — הכול, כולל בטא וניסיוני', () {
      expect(controller.filtered.map((p) => p.id), ['a', 'b', 'c']);
    });

    test('חיפוש חופשי מתאים לשם, לתקציר, למחבר ולתגיות', () {
      controller.setSearch('שרה');
      expect(controller.filtered.map((p) => p.id), ['a']);

      controller.setSearch('לימוד');
      expect(controller.filtered.map((p) => p.id), ['a']);

      controller.setSearch('תקציר א');
      expect(controller.filtered.map((p) => p.id), ['a']);

      controller.setSearch('   ');
      expect(controller.filtered, hasLength(3));
    });

    test('סינון יציבות: "ניסיוני" כולל גם בטא', () {
      controller.setStatusFilter(PluginStatusFilter.experimental);
      expect(controller.filtered.map((p) => p.id), ['b', 'c']);

      controller.setStatusFilter(PluginStatusFilter.stable);
      expect(controller.filtered.map((p) => p.id), ['a']);

      controller.setStatusFilter(PluginStatusFilter.all);
      expect(controller.filtered, hasLength(3));
    });

    test('סינון תגית, וכל התגיות ממוינות', () {
      expect(controller.allTags, ['לימוד', 'עיצוב']);

      controller.setTagFilter('עיצוב');
      expect(controller.filtered.map((p) => p.id), ['b']);

      controller.setTagFilter(null);
      expect(controller.filtered, hasLength(3));
    });

    test('הצבת אותו ערך אינה מודיעה למאזינים', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setSearch('');
      controller.setStatusFilter(PluginStatusFilter.all);
      controller.setTagFilter(null);
      controller.setInstallFilter(controller.installFilter);
      controller.setCategory(null);

      expect(notifications, 0);
    });

    test('שינוי סינון מודיע ומרענן את התוצר המחושב', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.filtered, hasLength(3));
      controller.setSearch('בטא');

      expect(notifications, 1);
      expect(controller.filtered, hasLength(1));
    });
  });

  group('מיון', () {
    setUp(() async {
      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin(
              'featured',
              'נבחר',
              featured: true,
              publishedAt: '2026-01-01T00:00:00.000Z',
              fileUpdatedAt: '2026-01-02',
            ),
            plugin(
              'new',
              'חדש',
              publishedAt: '2026-05-01T00:00:00.000Z',
              fileUpdatedAt: '2026-05-01',
            ),
            plugin(
              'old',
              'ישן',
              publishedAt: '2025-03-01T00:00:00.000Z',
              fileUpdatedAt: '2026-09-01',
            ),
            plugin('legacy', 'קטלוג ישן'),
            plugin(
              'same-day',
              'אותו יום',
              publishedAt: '2026-05-01T00:00:00.000Z',
              fileUpdatedAt: '2026-05-01',
            ),
          ],
        ),
      );
      await controller.load();
      controller.installed = const {};
    });

    test('מומלצים — סדר הקטלוג', () {
      expect(
        controller.filtered.map((p) => p.id),
        ['featured', 'new', 'old', 'legacy', 'same-day'],
      );
    });

    test('החדשים ביותר ועודכנו לאחרונה; בלי תאריך בסוף, שוויון לפי הקטלוג', () {
      controller.setSortMode(PluginSortMode.newest);
      expect(
        controller.filtered.map((p) => p.id),
        ['new', 'same-day', 'featured', 'old', 'legacy'],
      );

      controller.setSortMode(PluginSortMode.updated);
      expect(
        controller.filtered.map((p) => p.id),
        ['old', 'new', 'same-day', 'featured', 'legacy'],
      );
    });

    test('המיון חל אחרי הסינון', () {
      controller.setSortMode(PluginSortMode.updated);
      controller.setSearch('חדש');
      expect(controller.filtered.map((p) => p.id), ['new']);
    });
  });

  group('זיהוי מותקנים — לפי manifestId, לא לפי מזהה הקטלוג', () {
    setUp(() async {
      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin(
              'db-1',
              'מותקן ומעודכן',
              version: '1.0.0',
              manifestId: 'com.example.one',
            ),
            plugin(
              'db-2',
              'מותקן וישן',
              version: '2.0.0',
              manifestId: 'com.example.two',
            ),
            plugin(
              'db-3',
              'לא מותקן',
              version: '1.0.0',
              manifestId: 'com.example.three',
            ),
            plugin('db-4', 'קובץ טרם ירד'),
          ],
        ),
      );
      await controller.load();
    });

    test('byId עונה מהקטלוג הנוכחי גם אחרי שהוחלף', () {
      expect(controller.byId('db-1')!.name, 'מותקן ומעודכן');
      expect(controller.byId('missing'), isNull);

      controller.plugins = [plugin('db-1', 'שם חדש')];

      expect(controller.byId('db-1')!.name, 'שם חדש');
      expect(controller.byId('db-2'), isNull);
    });

    test('במזהה כפול byId ו-pluginsIn מחזירים את הראשון בקטלוג', () {
      controller.plugins = [
        plugin('dup', 'ראשון'),
        plugin('other', 'אחר'),
        plugin('dup', 'שני'),
      ];

      expect(controller.byId('dup')!.name, 'ראשון');
      expect(
        controller
            .pluginsIn(
              const PluginStoreCategory(
                slug: 's',
                name: 's',
                pluginIds: ['dup'],
              ),
            )
            .single
            .name,
        'ראשון',
      );
    });

    test('ההשוואה היא מול manifestId — מזהה הקטלוג אינו מזוהה כמותקן', () {
      controller.installed = const {'db-1': '1.0.0'};

      expect(
        controller.statusOf(controller.byId('db-1')!),
        PluginInstallStatus.notInstalled,
      );
    });

    test('מותקן/עדכון/לא מותקן/לא ידוע', () {
      controller.installed = const {
        'com.example.one': '1.0.0',
        'com.example.two': '1.5.0',
      };

      expect(
        controller.statusOf(controller.byId('db-1')!),
        PluginInstallStatus.upToDate,
      );
      expect(
        controller.statusOf(controller.byId('db-2')!),
        PluginInstallStatus.updateAvailable,
      );
      expect(
        controller.statusOf(controller.byId('db-3')!),
        PluginInstallStatus.notInstalled,
      );
      // תוסף שקובץ ה-.otzplugin שלו טרם ירד — מצב תקין, לא שגיאה.
      expect(
        controller.statusOf(controller.byId('db-4')!),
        PluginInstallStatus.unknown,
      );

      expect(controller.updatablePlugins.map((p) => p.id), ['db-2']);
      expect(controller.installedVersionOf(controller.byId('db-2')!), '1.5.0');
      expect(controller.installedVersionOf(controller.byId('db-4')!), isNull);
      expect(controller.installedCount, 2);
    });

    test('בורר המותקנים: הכול / מותקנים / לא מותקנים', () {
      controller.installed = const {
        'com.example.one': '1.0.0',
        'com.example.two': '1.5.0',
      };

      // ברירת המחדל "הכול" — המשתמש בא לראות מה קיים.
      expect(controller.installFilter, PluginInstallFilter.all);
      expect(controller.filtered, hasLength(4));

      controller.setInstallFilter(PluginInstallFilter.installed);
      expect(controller.filtered.map((p) => p.id), ['db-1', 'db-2']);

      controller.setInstallFilter(PluginInstallFilter.notInstalled);
      expect(controller.filtered.map((p) => p.id), ['db-3', 'db-4']);
    });
  });

  group('קטגוריות', () {
    setUp(() async {
      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'ראשון', manifestId: 'm.a'),
            plugin('b', 'שני', manifestId: 'm.b'),
            plugin('c', 'שלישי', manifestId: 'm.c'),
          ],
          categories: const [
            PluginStoreCategory(
              slug: 'study',
              name: 'כלי לימוד',
              description: 'תיאור',
              pluginIds: ['c', 'a', 'לא-קיים'],
            ),
            PluginStoreCategory(slug: 'empty', name: 'ריקה'),
          ],
        ),
      );
      await controller.load();
      controller.installed = const {};
    });

    test('תוספי קטגוריה בסדר האתר, ומזהה שאינו בקטלוג מדולג', () {
      final category = controller.categoryBySlug('study')!;
      expect(controller.pluginsIn(category).map((p) => p.id), ['c', 'a']);
      expect(controller.categoryName('study'), 'כלי לימוד');
      // slug לא מוכר מחזיר את עצמו, ולא נופל.
      expect(controller.categoryName('אין-כזו'), 'אין-כזו');
    });

    test('קטגוריה ריקה אינה מקבלת שבב', () {
      expect(controller.shownCategories.map((c) => c.slug), ['study']);
    });

    test('שבב קטגוריה מצמצם, ומשתלב עם בורר המותקנים', () {
      controller.setCategory('study');
      expect(controller.filtered.map((p) => p.id), ['a', 'c']);

      controller.installed = const {'m.a': '1.0.0'};
      controller.setInstallFilter(PluginInstallFilter.notInstalled);
      expect(controller.filtered.map((p) => p.id), ['c']);
    });

    // התוצרים ממוזנים, ולכן קריאה **לפני** שינוי מצב חייבת להתבטל אחריו.
    test('filtered מתעדכן אחרי שינוי מצב, ולא נשאר על cache', () {
      controller.setInstallFilter(PluginInstallFilter.installed);
      expect(controller.filtered, isEmpty);

      controller.installed = const {'m.b': '1.0.0'};
      expect(controller.filtered.map((p) => p.id), ['b']);
    });

    test('"ניקוי החיפוש והסינון" מאפס הכול בבת אחת', () {
      controller
        ..setSearch('שני')
        ..setCategory('study')
        ..setStatusFilter(PluginStatusFilter.experimental)
        ..setTagFilter('תגית')
        ..setInstallFilter(PluginInstallFilter.installed);
      expect(controller.moreFiltersCount, 2);

      controller.clearFilters();

      expect(controller.search, isEmpty);
      expect(controller.categoryFilter, isNull);
      expect(controller.statusFilter, PluginStatusFilter.all);
      expect(controller.tagFilter, isNull);
      expect(controller.installFilter, PluginInstallFilter.all);
      expect(controller.moreFiltersCount, 0);
      expect(controller.filtered, hasLength(3));
    });
  });

  group('נכסים וכותרות', () {
    test('assetPath מרכיב נתיב מוחלט, ומחזיר null כשאין נכס', () async {
      await controller.load();

      expect(controller.assetPath(null), isNull);
      expect(controller.assetPath(''), isNull);
      expect(
        controller.assetPath('files/a.png'),
        p.join(tempDir.path, 'mirror', 'plugins', 'files', 'a.png'),
      );
    });

    test('byId מחזיר null למזהה שאינו בקטלוג', () async {
      await controller.load();

      expect(controller.byId('אין-כזה'), isNull);
    });
  });

  group('תיקיית התוספים נגזרת מההתקנה שזוהתה', () {
    const pluginId = 'launcher-test-plugin';
    late String exe;
    String? launchPath;

    PluginsModuleController portableController() {
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => launchPath,
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      // התקנה ניידת של אוצריא: קובץ הרצה, קובץ הסימון, ותיקיית הנתונים
      // שלידם — בדיוק המבנה שבו `%APPDATA%` אינו רלוונטי.
      final dir = p.join(tempDir.path, 'ניידת');
      exe = p.join(dir, 'otzaria.exe');
      File(exe).createSync(recursive: true);
      File(p.join(dir, InstalledPluginsScanner.portableMarkerFileName))
          .writeAsStringSync('');
      File(
        p.join(
          dir,
          InstalledPluginsScanner.portableDataFolderName,
          'plugins',
          'installed',
          pluginId,
          'current',
          'manifest.json',
        ),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('{"id":"$pluginId","version":"1.4.0"}');
      launchPath = null;
    });

    test('load קורא את התוספים של ההתקנה הניידת', () async {
      launchPath = exe;
      final c = portableController();

      await c.load();

      expect(c.installed, {pluginId: '1.4.0'});
    });

    test('רישום ההתקנות של אוצריא גובר על מבנה התיקיות', () async {
      launchPath = exe;
      final dbPath = p.join(
        p.dirname(exe),
        InstalledPluginsScanner.portableDataFolderName,
        'databases',
        pluginsRegistryFileName,
      );
      Directory(p.dirname(dbPath)).createSync(recursive: true);
      sqlite3.open(dbPath)
        ..execute(
          'CREATE TABLE plugin_installation '
          '(plugin_id TEXT PRIMARY KEY, version TEXT NOT NULL)',
        )
        ..execute('INSERT INTO plugin_installation VALUES (?, ?)', [
          pluginId,
          '1.5.0',
        ])
        ..close();
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => launchPath,
        locatePluginsDb: PluginsModuleController.locateOtzariaPluginsDb,
      );
      addTearDown(c.dispose);

      await c.load();

      expect(c.installed, {pluginId: '1.5.0'});
    });

    test('תוסף מושבת ותוסף בפיתוח באוצריא מזוהים מהרישום', () async {
      launchPath = exe;
      final dbPath = p.join(
        p.dirname(exe),
        InstalledPluginsScanner.portableDataFolderName,
        'databases',
        pluginsRegistryFileName,
      );
      Directory(p.dirname(dbPath)).createSync(recursive: true);
      sqlite3.open(dbPath)
        ..execute(
          'CREATE TABLE plugin_installation (plugin_id TEXT PRIMARY KEY, '
          'version TEXT NOT NULL, enabled INTEGER NOT NULL, source_type TEXT)',
        )
        ..execute(
          'INSERT INTO plugin_installation VALUES (?, ?, 0, ?), (?, ?, 1, ?)',
          ['off', '1.0.0', 'packaged', 'dev', '0.1.0', 'development'],
        )
        ..close();
      await saveCatalog(
        PluginCatalog(
          plugins: [
            plugin('a', 'א', version: '2.0.0', manifestId: 'off'),
            plugin('b', 'ב', version: '2.0.0', manifestId: 'dev'),
          ],
        ),
      );
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => launchPath,
        locatePluginsDb: PluginsModuleController.locateOtzariaPluginsDb,
      );
      addTearDown(c.dispose);

      await c.load();
      final off = c.byId('a')!;
      final dev = c.byId('b')!;

      expect(c.isDisabledInOtzaria(off), isTrue);
      expect(c.statusOf(off), PluginInstallStatus.updateAvailable);
      expect(c.isDevelopmentInOtzaria(dev), isTrue);
      expect(c.statusOf(dev), PluginInstallStatus.upToDate);
      expect(c.updatablePlugins.map((p) => p.id), ['a']);
    });

    test('refreshInstalled סורק מחדש אחרי שנתיב ההתקנה התברר', () async {
      final c = portableController();
      await c.load();
      // לפני הזיהוי אין נתיב, והסריקה נפלה לברירת המחדל של הפלטפורמה.
      expect(c.installed.containsKey(pluginId), isFalse);

      launchPath = exe;
      await c.refreshInstalled();

      expect(c.installed[pluginId], '1.4.0');
      expect(c.status, PluginsModuleStatus.ready);
    });

    test('refreshInstalled בזמן טעינה ממתינה לה ולא מדלגת', () async {
      launchPath = exe;
      final c = portableController();

      final loading = c.load();
      await Future.wait([loading, c.refreshInstalled()]);

      expect(c.installed[pluginId], '1.4.0');
    });

    test('סריקות חופפות מתאחדות לסריקה אחת ועוד אחת, ולא נערמות', () async {
      launchPath = exe;
      Completer<void>? gate;
      var calls = 0;
      var inFlight = 0;
      var maxInFlight = 0;
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => launchPath,
        installedAppVersion: () async {
          calls++;
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await gate?.future;
          inFlight--;
          return null;
        },
      );
      addTearDown(c.dispose);
      await c.load();
      calls = 0;
      maxInFlight = 0;

      final release = gate = Completer<void>();
      final scans = [for (var i = 0; i < 5; i++) c.refreshInstalled()];
      await Future<void>.delayed(const Duration(milliseconds: 100));
      release.complete();
      await Future.wait(scans);

      expect(maxInFlight, 1);
      expect(calls, 2);
      expect(c.installed[pluginId], '1.4.0');
    });
  });

  group('סיום ההתקנה באוצריא מזוהה מאליו', () {
    const manifestId = 'launcher-fresh-plugin';
    late String exe;
    late String installedDir;

    PluginsModuleController watching({Duration? timeout}) {
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => exe,
        installWatchInterval: const Duration(milliseconds: 10),
        installWatchTimeout: timeout ?? const Duration(minutes: 5),
      );
      addTearDown(c.dispose);
      return c;
    }

    /// מה שאוצריא כותבת לדיסק כשהיא מסיימת להתקין.
    void otzariaFinishes(String version) {
      File(p.join(installedDir, manifestId, 'current', 'manifest.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"id":"$manifestId","version":"$version"}');
    }

    setUp(() {
      final dir = p.join(tempDir.path, 'ניידת-המתנה');
      exe = p.join(dir, 'otzaria.exe');
      File(exe).createSync(recursive: true);
      File(p.join(dir, InstalledPluginsScanner.portableMarkerFileName))
          .writeAsStringSync('');
      installedDir = p.join(
        dir,
        InstalledPluginsScanner.portableDataFolderName,
        'plugins',
        'installed',
      );
      Directory(installedDir).createSync(recursive: true);
    });

    test(
      'הסריקה החוזרת מזהה את ההתקנה ומודיעה עליה, בלי בדיקה ידנית',
      () async {
        final c = watching();
        await c.load();
        final target = plugin('חדש', 'תוסף חדש', manifestId: manifestId);

        final announced = c.installCompletions.first;
        c.watchForInstall(target);
        expect(c.isAwaitingInstallOf(target), isTrue);

        otzariaFinishes('2.0.0');

        expect(await announced, 'תוסף חדש');
        expect(c.installed[manifestId], '2.0.0');
        expect(c.isAwaitingInstall, isFalse);
      },
    );

    test('גם עדכון מזוהה — הגרסה שעל הדיסק היא שהשתנתה', () async {
      otzariaFinishes('1.0.0');
      final c = watching();
      await c.load();
      final target = plugin('חדש', 'תוסף', manifestId: manifestId);

      final announced = c.installCompletions.first;
      c.watchForInstall(target);
      otzariaFinishes('1.1.0');

      expect(await announced, 'תוסף');
      expect(c.installed[manifestId], '1.1.0');
    });

    test('פסק זמן סוגר את ההמתנה בלי להודיע על הצלחה', () async {
      final c = watching(timeout: Duration.zero);
      await c.load();
      var announced = false;
      c.installCompletions.listen((_) => announced = true);

      c.watchForInstall(plugin('חדש', 'תוסף', manifestId: manifestId));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(c.isAwaitingInstall, isFalse);
      expect(announced, isFalse);
    });

    group('תוצאת ההתקנה שאוצריא כותבת (C2)', () {
      late String dataRoot;
      late String delivered;

      setUp(() {
        dataRoot = p.dirname(p.dirname(installedDir));
        delivered = p.join(tempDir.path, 'plugin-1.0.0.otzplugin');
      });

      void capabilities(int pluginInstallResults) => File(
            p.join(dataRoot, OtzariaCapabilities.fileName),
          ).writeAsStringSync(
            jsonEncode({
              'formatVersion': 1,
              'pluginInstallResults': pluginInstallResults,
            }),
          );

      void otzariaReports(String outcome, {String? message}) {
        final line = jsonEncode({
          'path': delivered,
          'pluginId': manifestId,
          'version': '2.0.0',
          'outcome': outcome,
          'message': message,
          'at': DateTime.now().toUtc().toIso8601String(),
        });
        File(p.join(dataRoot, PluginInstallResults.fileName))
            .writeAsStringSync('$line\n', mode: FileMode.append);
      }

      test('ביטול באוצריא נסגר מיד ומדווח, בלי לחכות לפסק הזמן', () async {
        capabilities(1);
        final c = watching();
        await c.load();
        final rejected = c.installRejections.first;
        var succeeded = false;
        c.installCompletions.listen((_) => succeeded = true);

        c.watchForInstall(
          plugin('חדש', 'תוסף', manifestId: manifestId),
          deliveredPath: delivered,
          handedOffAt: DateTime.now(),
        );
        otzariaReports('cancelled');

        final entry = await rejected;
        expect(entry.name, 'תוסף');
        expect(entry.report.cancelled, isTrue);
        expect(c.isAwaitingInstall, isFalse);
        expect(succeeded, isFalse);
      });

      test('כשל עם הודעה מאוצריא עובר הלאה', () async {
        capabilities(1);
        final c = watching();
        await c.load();
        final rejected = c.installRejections.first;

        c.watchForInstall(
          plugin('חדש', 'תוסף', manifestId: manifestId),
          deliveredPath: delivered,
          handedOffAt: DateTime.now(),
        );
        otzariaReports('rejected_incompatible', message: 'דורש 0.9.99');

        expect((await rejected).report.message, 'דורש 0.9.99');
      });

      test('הצלחה מהקובץ מודיעה כמו הסריקה', () async {
        capabilities(1);
        final c = watching();
        await c.load();
        final announced = c.installCompletions.first;

        c.watchForInstall(
          plugin('חדש', 'תוסף', manifestId: manifestId),
          deliveredPath: delivered,
          handedOffAt: DateTime.now(),
        );
        otzariaReports('installed');

        expect(await announced, 'תוסף');
      });

      test('אוצריא ישנה בלי היכולת — הקובץ אינו נקרא, הסריקה ממשיכה', () async {
        final c = watching(timeout: const Duration(milliseconds: 150));
        await c.load();
        var rejected = false;
        c.installRejections.listen((_) => rejected = true);

        c.watchForInstall(
          plugin('חדש', 'תוסף', manifestId: manifestId),
          deliveredPath: delivered,
          handedOffAt: DateTime.now(),
        );
        otzariaReports('cancelled');
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(c.isAwaitingInstall, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(rejected, isFalse);
      });
    });

    test('תוסף בלי מזהה מניפסט אינו נכנס להמתנה', () async {
      final c = watching();
      await c.load();

      c.watchForInstall(plugin('חדש', 'תוסף'));

      expect(c.isAwaitingInstall, isFalse);
    });
  });

  group('התקנה ישירה של בילד שטרם ירד', () {
    const manifestId = 'downloaded-manifest';
    late HttpServer server;
    late String fileName;

    List<int> storedZip(String name, List<int> content) {
      final nameBytes = utf8.encode(name);
      final localBytes = [
        ..._le32(0x04034b50),
        ..._le16(20),
        ..._le16(0),
        ..._le16(0),
        ..._le32(0),
        ..._le32(0),
        ..._le32(content.length),
        ..._le32(content.length),
        ..._le16(nameBytes.length),
        ..._le16(0),
        ...nameBytes,
        ...content,
      ];
      final centralBytes = [
        ..._le32(0x02014b50),
        ..._le16(20),
        ..._le16(20),
        ..._le16(0),
        ..._le16(0),
        ..._le32(0),
        ..._le32(0),
        ..._le32(content.length),
        ..._le32(content.length),
        ..._le16(nameBytes.length),
        ..._le16(0),
        ..._le16(0),
        ..._le16(0),
        ..._le16(0),
        ..._le32(0),
        ..._le32(0),
        ...nameBytes,
      ];
      return [
        ...localBytes,
        ...centralBytes,
        ..._le32(0x06054b50),
        ..._le16(0),
        ..._le16(0),
        ..._le16(1),
        ..._le16(1),
        ..._le32(centralBytes.length),
        ..._le32(localBytes.length),
        ..._le16(0),
      ];
    }

    setUp(() async {
      HttpOverrides.global = null;
      fileName = 'plugin.otzplugin';
      final body = storedZip(
        'manifest.json',
        utf8.encode('{"id":"$manifestId","version":"1.0.0"}'),
      );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="$fileName"',
        );
        request.response.add(body);
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    StorePlugin remote() => StorePlugin.fromApi({
          'id': 'remote',
          'name': 'תוסף מרוחק',
          'version': '1.0.0',
          'supportsDirectInstall': true,
          'downloadUrl': 'http://127.0.0.1:${server.port}/download',
        }, 'https://otzaria.org');

    test('הרשומה בזיכרון מתעדכנת גם כשהמסירה נכשלה', () async {
      fileName = 'plugin.zip';
      final notExecutable = p.join(tempDir.path, 'not-otzaria.txt');
      File(notExecutable).writeAsStringSync('not a program');
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => notExecutable,
      );
      addTearDown(c.dispose);
      await saveCatalog(PluginCatalog(plugins: [remote()]));
      await c.load();
      final stale = c.byId('remote')!;
      expect(c.hasFileFor(stale), isFalse);

      final result = await c.directInstall(stale);

      expect(result.success, isFalse);
      expect(
        result.error,
        startsWith(AppL10n.strings.pluginsDomain.otzariaOpenFailed('')),
      );
      final fresh = c.byId('remote')!;
      expect(c.hasFileFor(fresh), isTrue);
      expect(fresh.manifestId, manifestId);
      expect(c.isAwaitingInstall, isFalse);
    });

    test('מסירה שהצליחה ממתינה להתקנה לפי המניפסט שירד', () async {
      final exe = p.join(tempDir.path, 'otzaria-stub');
      File(exe).writeAsStringSync('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', ['+x', exe]);
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        otzariaLaunchPath: () async => exe,
      );
      addTearDown(c.dispose);
      await saveCatalog(PluginCatalog(plugins: [remote()]));
      await c.load();

      final result = await c.directInstall(c.byId('remote')!);

      expect(result.success, isTrue, reason: result.error);
      expect(c.isAwaitingInstallOf(c.byId('remote')!), isTrue);
      expect(c.byId('remote')!.manifestId, manifestId);
    }, skip: Platform.isWindows);
  });

  group('canDirectInstall', () {
    test('נקבע לפי הבילד שיותקן ולא לפי הבילד החי', () {
      final entry = StorePlugin.fromApi(const {
        'id': 'v',
        'name': 'גרסאות',
        'version': '2.0.0',
        'supportsDirectInstall': true,
        'versions': [
          {
            'version': '2.0.0',
            'compatibleWith': '9.0.0',
            'supportsDirectInstall': true,
          },
          {
            'version': '1.0.0',
            'compatibleWith': '1.0.0',
            'supportsDirectInstall': false,
          },
        ],
      }, 'https://otzaria.org');
      controller.appVersion = '1.5.0';

      expect(controller.targetOf(entry)?.version, '1.0.0');
      expect(controller.canDirectInstall(entry), isFalse);
    });
  });

  group('sync — הפעולה היחידה שדורשת רשת', () {
    test('בלי חיבור: מצב שגיאה עם הודעה, בלי קריסה', () async {
      await controller.sync();

      expect(controller.status, PluginsModuleStatus.error);
      expect(controller.errorMessage, isNotNull);
      expect(controller.syncWarnings, isEmpty);
    });

    test('plugin files that did not download count as a failed sync', () {
      expect(controller.lastSyncFailed, isFalse);

      controller.lastSyncOutcome = const PluginSyncOutcome(
        catalog: PluginCatalog.empty,
        fetched: 0,
        skipped: 0,
        failed: ['a', 'b', 'c'],
      );

      expect(controller.errorMessage, isNull);
      expect(controller.lastSyncFailed, isTrue);
    });

    test('isSyncing is already true in the first notification', () async {
      final seen = <bool>[];
      controller.addListener(() => seen.add(controller.isSyncing));

      final run = controller.sync();
      await run;

      expect(seen, isNotEmpty);
      expect(seen.first, isTrue);
      expect(controller.isSyncing, isFalse);
    });

    test('a successful sync after Shabbat drops the Shabbat closure', () async {
      final open = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([]),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(open.dispose);
      await open.load();
      open
        ..onlineCheckError = 'closed'
        ..onlineClosedForShabbat = true;

      await open.sync();

      expect(open.lastSyncFailed, isFalse);
      expect(open.onlineCheckError, isNull);
      expect(open.onlineClosedForShabbat, isFalse);
    });

    test('a re-check keeps the previous errors until the new answer', () async {
      controller
        ..onlineCheckError = 'old catalog'
        ..storeAppCheckError = 'old store';
      final seen = <(String?, String?)>[];
      controller.addListener(
        () => seen.add(
          (controller.onlineCheckError, controller.storeAppCheckError),
        ),
      );

      await controller.checkOnline();

      expect(seen.first, ('old catalog', 'old store'));
    });

    test('a second sync while one runs joins the same run', () async {
      final first = controller.sync();
      final second = controller.sync();

      expect(identical(first, second), isTrue);
      await first;
      expect(controller.isSyncing, isFalse);
    });

    test('שבת בבדיקה הקלה — הודעת השבת, והמראה אינה נחשבת מעודכנת', () async {
      final closed = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'shabbat'}),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(closed.dispose);
      await closed.load();

      await closed.checkOnline();

      expect(closed.status, PluginsModuleStatus.ready);
      expect(
        closed.onlineCheckError,
        AppL10n.strings.pluginsDomain.siteClosedForShabbat,
      );
      // לבית: לא נבדק, אבל לא כשל — ונשמר גם בשחזור אחרי ביטול.
      expect(closed.onlineClosedForShabbat, isTrue);
      final answers = closed.catalogOnlineAnswers;
      closed.onlineClosedForShabbat = false;
      closed.restoreCatalogOnlineAnswers(answers);
      expect(closed.onlineClosedForShabbat, isTrue);
    });

    test('שבת: המראה הקיימת נשארת מוכנה, עם הודעה ייעודית ובלי שגיאה',
        () async {
      await saveCatalog(PluginCatalog(plugins: [plugin('a', 'א')]));
      final closed = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'shabbat', 'message': 'x'}),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(closed.dispose);
      await closed.load();

      await closed.sync();

      expect(closed.status, PluginsModuleStatus.ready);
      expect(closed.errorMessage, isNull);
      expect(
        closed.shabbatNotice,
        AppL10n.strings.pluginsDomain.siteClosedForShabbat,
      );
      expect(closed.plugins.map((plugin) => plugin.id), ['a']);
      expect(closed.lastSyncFailed, isTrue);
    });

    test('a new sync drops the previous outcome', () async {
      controller.lastSyncOutcome = const PluginSyncOutcome(
        catalog: PluginCatalog.empty,
        fetched: 0,
        skipped: 0,
        failed: ['a'],
      );

      await controller.sync();

      expect(controller.lastSyncOutcome, isNull);
      expect(controller.lastSyncFailed, isTrue);
    });
  });

  group('checkOnline — בדיקה קלה, כשל בה אינו שגיאה', () {
    test('בלי חיבור: נרשמת הודעה, המצב אינו הופך לשגיאה', () async {
      await controller.load();
      await controller.checkOnline();

      expect(controller.onlineCheckError, isNotNull);
      expect(controller.onlineCheckedAt, isNotNull);
      expect(controller.onlineStatus, isNull);
      expect(controller.hasOnlineUpdate, isFalse);
      // הבדיקה הקלה נפרדת ממצב החנות עצמה — היא לא הופכת אותה לשבורה.
      expect(controller.status, PluginsModuleStatus.ready);
      expect(controller.errorMessage, isNull);
    });

    test('ההצצה ממתינה לבדיקה המקומית לפני שהיא שואלת על הגרסאות', () async {
      // הבדיקה המקומית והקלה יוצאות יחד בעלייה. תשובה לפני שהיא הסתיימה
      // הייתה רשימת גרסאות ריקה, ואז ההצצה שואלת על הבילד החי של כל תוסף
      // ומדווחת "חסר" על מה שההורדה לעולם לא תביא.
      final calls = <String>[];
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        ensureAppVersionsKnown: () async {
          await Future<void>.delayed(Duration.zero);
          calls.add('ensure');
        },
        mirroredAppVersions: () async {
          calls.add('mirrored');
          return const ['0.9.96'];
        },
        installedAppVersion: () async {
          calls.add('installed');
          return '0.9.96';
        },
      );
      addTearDown(c.dispose);

      await c.checkOnline();

      expect(calls.first, 'ensure');
      expect(calls, containsAll(['mirrored', 'installed']));
    });

    test('תוצאה עם חדשים/מעודכנים מדליקה את הדגל', () async {
      controller.onlineStatus = const PluginsOnlineStatus(
        newPlugins: ['תוסף חדש'],
        totalOnline: 3,
      );
      expect(controller.hasOnlineUpdate, isTrue);

      controller.onlineStatus = const PluginsOnlineStatus(
        updatedPlugins: ['תוסף מעודכן'],
        totalOnline: 3,
      );
      expect(controller.hasOnlineUpdate, isTrue);

      controller.onlineStatus = const PluginsOnlineStatus(
        removedPlugins: ['תוסף שהוסר'],
        totalOnline: 3,
      );
      expect(controller.hasCatalogOnlineUpdate, isTrue);

      controller.onlineStatus = PluginsOnlineStatus.empty;
      expect(controller.hasOnlineUpdate, isFalse);
    });

    test('סנכרון שנכשל אינו מוחק את תוצאת הבדיקה', () async {
      controller.onlineStatus = const PluginsOnlineStatus(
        newPlugins: ['תוסף חדש'],
      );

      await controller.sync();

      expect(controller.status, PluginsModuleStatus.error);
      expect(controller.hasOnlineUpdate, isTrue);
    });
  });

  group('בחירת בילד לפי גרסת אוצריא', () {
    /// תוסף עם שני בילדים, ושני הקבצים כבר במראה — כמו כונן שהוריד עבור
    /// הגרסה היציבה והלא-יציבה גם יחד.
    StorePlugin versioned({Map<String, String> files = const {}}) =>
        StorePlugin.fromApi(const {
          'id': 'db-1',
          'name': 'תוסף',
          'version': '2.0.0',
          'compatibleWith': '0.9.97',
          'downloadUrl': '/api/plugins/db-1/download',
          'versions': [
            {
              'version': '2.0.0',
              'compatibleWith': '0.9.97',
              'downloadUrl': '/api/plugins/db-1/download',
              'isLatest': true,
            },
            {
              'version': '1.5.0',
              'compatibleWith': '0.9.95',
              'downloadUrl': '/api/plugins/db-1@1.5.0/download',
            },
          ],
        }, 'https://otzaria.org')
            .copyWith(
          manifestId: 'com.example.one',
          localFiles: {
            for (final entry in files.entries)
              entry.key: PluginLocalFile(
                relativePath: entry.value,
                fileName: 'plugin.otzplugin',
                ext: '.otzplugin',
                size: 1,
              ),
          },
        );

    Future<PluginsModuleController> controllerFor(String? appVersion) async {
      await saveCatalog(
        PluginCatalog(
          plugins: [
            versioned(
              files: {
                '2.0.0': 'files/db-1/plugin-2.0.0.otzplugin',
                '1.5.0': 'files/db-1/plugin-1.5.0.otzplugin',
              },
            ),
          ],
        ),
      );
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        installedAppVersion: () async => appVersion,
      );
      addTearDown(c.dispose);
      await c.load();
      return c;
    }

    test('אותה מראה מציגה בילד אחר לכל גרסת אוצריא', () async {
      final newer = await controllerFor('0.9.97');
      expect(newer.versionOf(newer.plugins.single), '2.0.0');

      final older = await controllerFor('0.9.96');
      expect(older.versionOf(older.plugins.single), '1.5.0');
      expect(older.hasFileFor(older.plugins.single), isTrue);
    });

    test('"מעודכן" נמדד מול הבילד שירוץ כאן, לא מול האחרון שפורסם', () async {
      final c = await controllerFor('0.9.96');
      c.installed = const {'com.example.one': '1.5.0'};

      expect(c.statusOf(c.plugins.single), PluginInstallStatus.upToDate);
      expect(c.updatablePlugins, isEmpty);
    });

    test('אין בילד תואם — incompatible, וזה לא שגיאה', () async {
      final c = await controllerFor('0.9.80');

      expect(c.statusOf(c.plugins.single), PluginInstallStatus.incompatible);
      expect(c.targetOf(c.plugins.single), isNull);
      expect(c.status, PluginsModuleStatus.ready);
    });

    test('בלי גרסה ידועה נבחר הבילד החי, כמו קודם', () async {
      final c = await controllerFor(null);

      expect(c.versionOf(c.plugins.single), '2.0.0');
    });

    test('הטעינה ממתינה לבדיקה המקומית לפני שהיא קוראת את הגרסה', () async {
      // התלונה שהתיקון הזה בא בשבילה: `load` יצאה לדרך בעלייה, לפני שאוצריא
      // זוהתה, וגרסה לא ידועה מכשירה **כל** בילד שבמראה — גם זה שירד עבור
      // הגרסה השנייה שהכונן נושא. הודעת הכניסה לחנות נפתחה אז על "עדכון"
      // שהתהפך ל"מעודכן" ברגע שהזיהוי נחת.
      await saveCatalog(
        PluginCatalog(
          plugins: [
            versioned(
              files: {
                '2.0.0': 'files/db-1/plugin-2.0.0.otzplugin',
                '1.5.0': 'files/db-1/plugin-1.5.0.otzplugin',
              },
            ),
          ],
        ),
      );
      final calls = <String>[];
      var detected = false;
      final c = PluginsModuleController(
        mirrorRootDir: p.join(tempDir.path, 'mirror'),
        ensureAppVersionsKnown: () async {
          await Future<void>.delayed(Duration.zero);
          detected = true;
          calls.add('ensure');
        },
        installedAppVersion: () async {
          calls.add('installed');
          return detected ? '0.9.96' : null;
        },
      );
      addTearDown(c.dispose);

      await c.load();
      c.installed = const {'com.example.one': '1.5.0'};

      expect(calls, ['ensure', 'installed']);
      expect(c.appVersion, '0.9.96');
      // הבילד שירוץ כאן הוא זה שכבר מותקן — ולכן אין מה להודיע עליו.
      expect(c.statusOf(c.plugins.single), PluginInstallStatus.upToDate);
      expect(c.updatablePlugins, isEmpty);
    });
  });

  group('תוכנת החנות העצמאית', () {
    /// כותב מראה של תוכנת החנות, כמו ש-`StoreAppMirror.sync` משאיר.
    Future<void> seedStoreApp() async {
      const bytes = 'exe';
      final dir = p.join(tempDir.path, 'mirror', 'store-app');
      final file = File(p.join(dir, 'files', 'v6', 'Store.exe'));
      await file.parent.create(recursive: true);
      await file.writeAsString(bytes);
      await File(p.join(dir, 'latest-release.json')).writeAsString(
        '{"schemaVersion":1,"release":{"tagName":"v6","version":6,'
        '"assetName":"Store.exe","downloadUrl":"https://x/v6.exe",'
        '"sizeBytes":${bytes.length}},"filePath":"files/v6/Store.exe"}',
      );
    }

    test('בלי קובץ הרצה במראה אין מה להעתיק', () async {
      await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));
      await controller.load();

      expect(controller.storeApp, isNull);
      expect(controller.canExportStoreApp, isFalse);
    });

    test('עם קובץ הרצה אבל בלי תוספים עדיין אין מה להעתיק', () async {
      await seedStoreApp();
      await saveCatalog(const PluginCatalog());
      await controller.load();

      expect(controller.storeApp, isNotNull);
      expect(controller.canExportStoreApp, isFalse);
    });

    test('בלי גרסה חדשה שנמצאה — ההורדה אינה נוגעת ברשת', () async {
      await saveCatalog(const PluginCatalog());
      await controller.load();

      // `storeAppOnline` הוא `null` (לא רצה בדיקה קלה), ולכן אין מה להוריד
      // — וחשוב מכך, אין אף פנייה לגיטהאב. הרשת חסומה כאן, וקריאה כזו
      // הייתה זורקת.
      expect(controller.hasStoreAppOnlineUpdate, isFalse);
      await controller.syncStoreApp();
      expect(controller.storeApp, isNull);
    });

    test('גרסה חדשה מדווחת ככפתור הורדה, וגם הקטלוג נשאר נפרד', () async {
      await saveCatalog(const PluginCatalog());
      await controller.load();
      expect(controller.hasOnlineUpdate, isFalse);

      controller.storeAppOnline = const StoreAppRelease(
        tagName: 'v7',
        version: 7,
        assetName: 'Store.exe',
        downloadUrl: 'https://x/v7.exe',
        sizeBytes: 3,
      );

      // דף הבית קורא את המאוחד, ו-`downloadAll` את כל אחד בנפרד.
      expect(controller.hasOnlineUpdate, isTrue);
      expect(controller.hasCatalogOnlineUpdate, isFalse);
      expect(controller.hasStoreAppOnlineUpdate, isTrue);
    });

    test('עם שניהם — הייצוא כותב את היעד שנבחר', () async {
      await seedStoreApp();
      await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));
      await controller.load();
      expect(controller.canExportStoreApp, isTrue);

      final dest = p.join(tempDir.path, 'dest');
      final outcome = await controller.exportStoreApp(dest);

      expect(outcome.plugins, 1);
      expect(File(p.join(dest, 'Store.exe')).existsSync(), isTrue);
      expect(File(p.join(dest, 'Data', 'catalog.json')).existsSync(), isTrue);
      // הדגל מתאפס גם בהצלחה — אחרת השכבה החוסמת נשארת על המסך.
      expect(controller.isExporting, isFalse);
    });

    group('זכירת תיקיית החנות', () {
      PluginsModuleController withState() => PluginsModuleController(
            mirrorRootDir: p.join(tempDir.path, 'mirror'),
            stateDir: p.join(tempDir.path, 'state'),
          );

      Future<String> exportOnce(PluginsModuleController c) async {
        await seedStoreApp();
        await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));
        await c.load();
        final dest = p.join(tempDir.path, 'dest');
        await c.exportStoreApp(dest);
        return dest;
      }

      test('אחרי ייצוא התיקייה נזכרת ואין עדכון ממתין', () async {
        final c = withState();
        addTearDown(c.dispose);
        final dest = await exportOnce(c);

        expect(c.rememberedStoreDir, dest);
        expect(c.storeAppUpdatePending, isFalse);
      });

      test('טעינה חדשה זוכרת, וגרסה חדשה במראה מסמנת עדכון', () async {
        final first = withState();
        addTearDown(first.dispose);
        final dest = await exportOnce(first);

        // מראה עם גרסה חדשה יותר.
        final dir = p.join(tempDir.path, 'mirror', 'store-app');
        await File(p.join(dir, 'files', 'v6', 'Store.exe'))
            .copy(p.join(dir, 'files', 'Store7.exe'));
        await File(p.join(dir, 'latest-release.json')).writeAsString(
          '{"schemaVersion":1,"release":{"tagName":"v7","version":7,'
          '"assetName":"Store.exe","downloadUrl":"https://x/v7.exe",'
          '"sizeBytes":3},"filePath":"files/Store7.exe"}',
        );
        final second = withState();
        addTearDown(second.dispose);
        await second.load();

        expect(second.rememberedStoreDir, dest);
        expect(second.storeAppUpdatePending, isTrue);
      });

      test('תיקייה שנמחקה אינה נזכרת', () async {
        final first = withState();
        addTearDown(first.dispose);
        final dest = await exportOnce(first);
        Directory(dest).deleteSync(recursive: true);

        final second = withState();
        addTearDown(second.dispose);
        await second.load();

        expect(second.rememberedStoreDir, isNull);
        expect(second.storeAppUpdatePending, isFalse);
      });

      test('בלי תיקיית מצב אין זיכרון ואין קריסה', () async {
        await seedStoreApp();
        await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));
        await controller.load();
        await controller.exportStoreApp(p.join(tempDir.path, 'dest'));

        expect(controller.storeAppUpdatePending, isFalse);
      });
    });
  });
}

List<int> _le16(int value) => [value & 0xff, (value >> 8) & 0xff];

List<int> _le32(int value) => [
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

class _SearchPlugin extends StorePlugin {
  _SearchPlugin(String id, this.text)
      : super(
          id: id,
          name: 'לוח',
          shortDescription: '',
          description: '',
          version: '1.0.0',
          status: 'stable',
          author: '',
          updatedAt: '',
          originalDate: '',
          compatibleWith: '',
          maxAppVersion: '',
          requiresNetwork: false,
          tags: const [],
          homepage: '',
          downloadCount: 0,
          supportsDirectInstall: false,
          isFeatured: false,
          remoteDownloadUrl: '',
        );

  final String text;
  final _descriptionReads = [0];
  int get descriptionReads => _descriptionReads.single;

  @override
  String get description {
    _descriptionReads[0]++;
    return text;
  }
}
