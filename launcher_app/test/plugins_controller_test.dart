import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

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
      }, 'https://otzaria.org')
          .copyWith(manifestId: manifestId);

  Future<void> saveCatalog(PluginCatalog catalog) =>
      PluginMirrorStore(p.join(tempDir.path, 'mirror')).save(catalog);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugins-ctrl-');
    HttpOverrides.global = NoNetworkHttpOverrides();
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
    controller =
        PluginsModuleController(mirrorRootDir: p.join(tempDir.path, 'mirror'));
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

    test('בלי אצירה אין דף בית — נפתחת ישר "כל התוספים"', () async {
      await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));

      await controller.load();

      expect(controller.hasCuratedHome, isFalse);
      expect(controller.view, PluginStorePage.all);
    });

    test('יש אצירה — נשארים בדף הבית', () async {
      await saveCatalog(PluginCatalog(
        plugins: [plugin('a', 'תוסף נבחר', featured: true)],
        home: const PluginStoreHome(title: 'החנות', subtitle: 'תקציר'),
      ));

      await controller.load();

      expect(controller.hasCuratedHome, isTrue);
      expect(controller.view, PluginStorePage.home);
      expect(controller.homeTitle, 'החנות');
      expect(controller.homeSubtitle, 'תקציר');
    });

    test('קטגוריה שנעלמה מהחנות אינה נשארת פתוחה', () async {
      await saveCatalog(PluginCatalog(
        plugins: [plugin('a', 'תוסף')],
        categories: const [PluginStoreCategory(slug: 'study', name: 'לימוד')],
      ));
      await controller.load();
      controller.showCategory('study');
      expect(controller.view, PluginStorePage.category);

      await saveCatalog(PluginCatalog(plugins: [plugin('a', 'תוסף')]));
      await controller.load();

      expect(controller.view, PluginStorePage.all);
      expect(controller.openCategorySlug, isNull);
      expect(controller.openCategory, isNull);
    });
  });

  group('סינון', () {
    setUp(() async {
      await saveCatalog(PluginCatalog(
        plugins: [
          plugin('a', 'מפתח ראשי',
              tags: ['לימוד'], author: 'שרה', shortDescription: 'תקציר א'),
          plugin('b', 'תוסף בטא', status: 'beta', tags: ['עיצוב']),
          plugin('c', 'תוסף ניסיוני', status: 'experimental'),
        ],
      ));
      await controller.load();
      // ההתקנה האמיתית של המכונה המריצה לא אמורה להשפיע על התוצאה.
      controller.installed = const {};
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

    test('סינון סטטוס', () {
      controller.setStatusFilter(PluginStatusFilter.beta);
      expect(controller.filtered.map((p) => p.id), ['b']);

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
      controller.setHideInstalled(controller.hideInstalled);

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

  group('זיהוי מותקנים — לפי manifestId, לא לפי מזהה הקטלוג', () {
    setUp(() async {
      await saveCatalog(PluginCatalog(
        plugins: [
          plugin('db-1', 'מותקן ומעודכן',
              version: '1.0.0', manifestId: 'com.example.one'),
          plugin('db-2', 'מותקן וישן',
              version: '2.0.0', manifestId: 'com.example.two'),
          plugin('db-3', 'לא מותקן',
              version: '1.0.0', manifestId: 'com.example.three'),
          plugin('db-4', 'קובץ טרם ירד'),
        ],
      ));
      await controller.load();
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

      expect(controller.statusOf(controller.byId('db-1')!),
          PluginInstallStatus.upToDate);
      expect(controller.statusOf(controller.byId('db-2')!),
          PluginInstallStatus.updateAvailable);
      expect(controller.statusOf(controller.byId('db-3')!),
          PluginInstallStatus.notInstalled);
      // תוסף שקובץ ה-.otzplugin שלו טרם ירד — מצב תקין, לא שגיאה.
      expect(controller.statusOf(controller.byId('db-4')!),
          PluginInstallStatus.unknown);

      expect(controller.updatablePlugins.map((p) => p.id), ['db-2']);
      expect(controller.installedVersionOf(controller.byId('db-2')!), '1.5.0');
      expect(controller.installedVersionOf(controller.byId('db-4')!), isNull);
      expect(controller.installedCount, 2);
    });

    test('מתג "רק מה שלא מותקן" מסתיר את המעודכן בלבד', () {
      controller.installed = const {
        'com.example.one': '1.0.0',
        'com.example.two': '1.5.0',
      };

      expect(controller.hideInstalled, isTrue);
      expect(controller.filtered.map((p) => p.id), ['db-2', 'db-3', 'db-4']);

      controller.setHideInstalled(false);
      expect(controller.filtered, hasLength(4));
    });
  });

  group('אצירה — נבחרים, קטגוריות ודף הבית', () {
    setUp(() async {
      await saveCatalog(PluginCatalog(
        plugins: [
          plugin('a', 'ראשון', featured: true, manifestId: 'm.a'),
          plugin('b', 'שני', manifestId: 'm.b'),
          plugin('c', 'שלישי', manifestId: 'm.c'),
        ],
        categories: const [
          PluginStoreCategory(
            slug: 'study',
            name: 'כלי לימוד',
            description: 'תיאור',
            showOnHome: true,
            homeLimit: 2,
            pluginIds: ['a', 'b', 'c', 'לא-קיים'],
          ),
          PluginStoreCategory(
            slug: 'hidden',
            name: 'לא בדף הבית',
            pluginIds: ['c'],
          ),
        ],
      ));
      await controller.load();
      controller.installed = const {};
    });

    test('נבחרים בסדר הקטלוג, קטגוריות דף-הבית ומגבלת השורה', () {
      expect(controller.featured.map((p) => p.id), ['a']);
      expect(controller.homeCategories.map((c) => c.slug), ['study']);

      final category = controller.categoryBySlug('study')!;
      expect(controller.pluginsIn(category).map((p) => p.id), ['a', 'b', 'c']);
      expect(
        controller
            .pluginsIn(category, limit: category.homeLimit)
            .map((p) => p.id),
        ['a', 'b'],
      );
      expect(controller.categoryName('study'), 'כלי לימוד');
      // slug לא מוכר מחזיר את עצמו, ולא נופל.
      expect(controller.categoryName('אין-כזו'), 'אין-כזו');
    });

    test('hasCuratedHome נמדד על המבנה — גם כשהמתג ריקן את הכרטיסים', () {
      controller.installed = const {
        'm.a': '1.0.0',
        'm.b': '1.0.0',
        'm.c': '1.0.0'
      };

      expect(controller.featured, isEmpty);
      expect(controller.homeCategories, isEmpty);
      // ובכל זאת יש דף בית — אחרת כיבוי הכרטיסים היה נראה כחנות ריקה.
      expect(controller.hasCuratedHome, isTrue);
    });
  });

  group('ניווט בין מסכי החנות', () {
    setUp(() async {
      await saveCatalog(PluginCatalog(
        plugins: [plugin('a', 'תוסף', featured: true)],
        categories: const [
          PluginStoreCategory(slug: 'study', name: 'לימוד', pluginIds: ['a']),
        ],
      ));
      await controller.load();
    });

    test('מעבר לקטגוריה ובחזרה מנקה את ה-slug', () {
      controller.showCategory('study');
      expect(controller.view, PluginStorePage.category);
      expect(controller.openCategory?.name, 'לימוד');

      controller.showHome();
      expect(controller.view, PluginStorePage.home);
      expect(controller.openCategorySlug, isNull);
    });

    test('חיפוש מה-hero מוביל ל"כל התוספים" עם המילה בתיבה', () {
      controller.showAllPlugins(query: 'תוסף');

      expect(controller.view, PluginStorePage.all);
      expect(controller.search, 'תוסף');
    });

    test('מעבר בלי query אינו מוחק חיפוש קיים', () {
      controller.setSearch('קיים');
      controller.showAllPlugins();

      expect(controller.search, 'קיים');
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

    test('כותרת ברירת המחדל מגיעה מ-otzaria_l10n בשתי השפות', () async {
      await controller.load();

      expect(
          controller.homeTitle, AppL10n.strings.plugins.catalogTitleFallback);
      expect(controller.homeSubtitle,
          AppL10n.strings.plugins.catalogSubtitleFallback);

      AppL10n.use(AppLanguage.english);
      expect(
          controller.homeTitle, AppL10n.strings.plugins.catalogTitleFallback);
      expect(controller.homeTitle, isNot(contains('אוצריא')));
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
      File(p.join(
        dir,
        InstalledPluginsScanner.portableDataFolderName,
        'plugins',
        'installed',
        pluginId,
        'current',
        'manifest.json',
      ))
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
  });

  group('sync — הפעולה היחידה שדורשת רשת', () {
    test('בלי חיבור: מצב שגיאה עם הודעה, בלי קריסה', () async {
      await controller.sync();

      expect(controller.status, PluginsModuleStatus.error);
      expect(controller.errorMessage, isNotNull);
      expect(controller.syncWarnings, isEmpty);
    });
  });
}
