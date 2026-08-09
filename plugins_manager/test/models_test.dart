import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

void main() {
  group('StorePlugin.statusAgainst', () {
    StorePlugin plugin({String? manifestId, String version = '2.0.0'}) =>
        StorePlugin.fromJson({
          'id': 'db-id',
          'name': 'תוסף',
          'version': version,
          'manifestId': manifestId,
        });

    test('בלי manifestId המצב unknown — אין מול מה להשוות', () {
      expect(
        plugin().statusAgainst({'anything': '1.0.0'}),
        PluginInstallStatus.unknown,
      );
    });

    test('תוסף שקובץ ההתקנה שלו עוד לא ירד הוא unknown, וזה מצב תקין', () {
      final notDownloaded = StorePlugin.fromApi(
        const {'id': 'a', 'name': 'אלף', 'version': '1.0.0'},
        'https://otzaria.org',
      );

      expect(notDownloaded.localFile, isNull);
      expect(notDownloaded.manifestId, isNull);
      expect(
        notDownloaded.statusAgainst({'a': '1.0.0'}),
        PluginInstallStatus.unknown,
      );
    });

    test('manifestId ריק נחשב חסר', () {
      const empty = StorePlugin(
        id: 'db-id',
        name: 'תוסף',
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
        tags: [],
        homepage: '',
        downloadCount: 0,
        supportsDirectInstall: false,
        isFeatured: false,
        remoteDownloadUrl: '',
        manifestId: '',
      );

      expect(empty.statusAgainst(const {}), PluginInstallStatus.unknown);
    });

    test('לא מותקן', () {
      expect(
        plugin(manifestId: 'real-id').statusAgainst({}),
        PluginInstallStatus.notInstalled,
      );
    });

    test('עדכון זמין כשהגרסה בחנות חדשה יותר', () {
      expect(
        plugin(manifestId: 'real-id').statusAgainst({'real-id': '1.0.0'}),
        PluginInstallStatus.updateAvailable,
      );
    });

    test('מעודכן כשהגרסאות זהות', () {
      expect(
        plugin(manifestId: 'real-id').statusAgainst({'real-id': '2.0.0'}),
        PluginInstallStatus.upToDate,
      );
    });

    test('גרסה מותקנת חדשה מזו שבחנות נחשבת מעודכנת', () {
      expect(
        plugin(manifestId: 'real-id').statusAgainst({'real-id': '3.0.0'}),
        PluginInstallStatus.upToDate,
      );
    });

    test('ההשוואה היא לפי manifestId ולא לפי id הקטלוג', () {
      // המפה ממופתחת ב-id של הקטלוג — בדיוק הטעות שהיה צריך לתקן במקור.
      expect(
        plugin(manifestId: 'real-id').statusAgainst({'db-id': '1.0.0'}),
        PluginInstallStatus.notInstalled,
      );
    });
  });

  group('StorePlugin.fromApi', () {
    test('הופך downloadUrl יחסי לכתובת מוחלטת', () {
      final plugin = StorePlugin.fromApi(
        {'id': 'x', 'downloadUrl': '/api/plugins/x/download'},
        'https://otzaria.org',
      );
      expect(
        plugin.remoteDownloadUrl,
        'https://otzaria.org/api/plugins/x/download',
      );
    });

    test('כתובת מוחלטת נשארת כמו שהיא', () {
      final plugin = StorePlugin.fromApi(
        {'id': 'x', 'downloadUrl': 'https://cdn.example/x.otzplugin'},
        'https://otzaria.org',
      );
      expect(plugin.remoteDownloadUrl, 'https://cdn.example/x.otzplugin');
    });

    test('תשובה ריקה נופלת לברירות מחדל בלי לזרוק', () {
      final plugin = StorePlugin.fromApi(const {}, 'https://otzaria.org');

      expect(plugin.id, '');
      expect(plugin.name, '');
      expect(plugin.tags, isEmpty);
      expect(plugin.maxAppVersion, isNull);
      expect(plugin.requiresNetwork, isFalse);
      expect(plugin.supportsDirectInstall, isFalse);
      expect(plugin.isFeatured, isFalse);
      expect(plugin.downloadCount, 0);
      expect(plugin.remoteDownloadUrl, '');
      expect(plugin.imagePath, isNull);
      expect(plugin.screenshotPaths, isEmpty);
      expect(plugin.categorySlugs, isEmpty);
    });

    test('שדות null או מטיפוס לא צפוי נופלים לברירת המחדל', () {
      final plugin = StorePlugin.fromApi(const {
        'id': 'x',
        'name': null,
        'downloadCount': '42',
        'requiresNetwork': 'true',
        'maxAppVersion': 3,
        'tags': ['תגית', 7, null],
        'שדה-לא-מוכר': 'לא מפריע',
      }, 'https://otzaria.org');

      expect(plugin.name, '');
      expect(plugin.downloadCount, 0);
      expect(plugin.requiresNetwork, isFalse);
      expect(plugin.maxAppVersion, isNull);
      expect(plugin.tags, ['תגית']);
    });

    test('tags שאינו רשימה מוחזר ריק', () {
      final plugin = StorePlugin.fromApi(
        const {'id': 'x', 'tags': 'לימוד'},
        'https://otzaria.org',
      );
      expect(plugin.tags, isEmpty);
    });
  });

  group('StorePlugin.fromJson / toJson', () {
    test('manifestId ריק נקרא כ-null', () {
      expect(
          StorePlugin.fromJson(const {'id': 'x', 'manifestId': ''}).manifestId,
          isNull);
      expect(
        StorePlugin.fromJson(const {'id': 'x', 'manifestId': 7}).manifestId,
        isNull,
      );
    });

    test('copyWith אינו מאפס שדות קיימים', () {
      final plugin = StorePlugin.fromJson(const {
        'id': 'x',
        'image': 'files/x/image.png',
        'manifestId': 'real',
      });

      final copy = plugin.copyWith(categorySlugs: const ['study']);
      expect(copy.imagePath, 'files/x/image.png');
      expect(copy.manifestId, 'real');
      expect(copy.categorySlugs, ['study']);
    });

    test('שוויון נקבע לפי הזהות והמצב המקומי', () {
      final base = StorePlugin.fromJson(const {'id': 'x', 'version': '1.0.0'});
      final same = StorePlugin.fromJson(const {
        'id': 'x',
        'version': '1.0.0',
        'name': 'שם אחר לגמרי',
      });
      final other = StorePlugin.fromJson(const {'id': 'x', 'version': '1.0.1'});

      expect(base, same);
      expect(base, isNot(other));
    });
  });

  group('PluginLocalFile', () {
    test('round-trip שומר את כל השדות', () {
      const file = PluginLocalFile(
        relativePath: 'files/abc/plugin.otzplugin',
        fileName: 'מפרשים.otzplugin',
        ext: '.otzplugin',
        size: 1234,
      );

      expect(PluginLocalFile.fromJson(file.toJson()), file);
    });

    test('בלי path אין רשומה', () {
      expect(PluginLocalFile.fromJson(null), isNull);
      expect(PluginLocalFile.fromJson('files/a'), isNull);
      expect(PluginLocalFile.fromJson(const {}), isNull);
      expect(PluginLocalFile.fromJson(const {'path': ''}), isNull);
    });

    test('שדות חסרים נופלים לברירת מחדל', () {
      final file = PluginLocalFile.fromJson(const {'path': 'files/a/p.zip'})!;

      expect(file.fileName, 'files/a/p.zip');
      expect(file.ext, '');
      expect(file.size, 0);
    });
  });

  group('PluginCatalog', () {
    test('round-trip שומר את כל השדות המשמעותיים', () {
      final original = PluginCatalog(
        lastSync: DateTime.utc(2026, 8, 6, 12, 30),
        plugins: [
          StorePlugin.fromApi({
            'id': 'abc',
            'name': 'תוסף בדיקה',
            'shortDescription': 'תקציר',
            'description': 'תיאור ארוך',
            'version': '1.2.3',
            'status': 'stable',
            'author': 'מחבר',
            'tags': ['תגית א', 'תגית ב'],
            'requiresNetwork': true,
            'supportsDirectInstall': true,
            'isPinned': true,
            'downloadCount': 42,
            'downloadUrl': '/api/plugins/abc/download',
          }, 'https://otzaria.org')
              .copyWith(
            imagePath: 'files/abc/image.png',
            screenshotPaths: ['files/abc/screenshot-0.png'],
            localFile: const PluginLocalFile(
              relativePath: 'files/abc/plugin.otzplugin',
              fileName: 'tosef.otzplugin',
              ext: '.otzplugin',
              size: 1234,
            ),
            manifestId: 'real-abc',
            categorySlugs: ['study-tools'],
          ),
        ],
        categories: const [
          PluginStoreCategory(
            slug: 'study-tools',
            name: 'כלי לימוד',
            description: 'תוספים שמסייעים בלימוד',
            showOnHome: true,
            homeLimit: 4,
            pluginIds: ['abc'],
          ),
        ],
        home: const PluginStoreHome(
          title: 'חנות התוספים',
          subtitle: 'תוספים שמרחיבים את אוצריא',
        ),
      );

      final restored = PluginCatalog.fromJson(original.toJson());
      final plugin = restored.plugins.single;

      expect(restored.lastSync, original.lastSync);
      expect(plugin.name, 'תוסף בדיקה');
      expect(plugin.version, '1.2.3');
      expect(plugin.tags, ['תגית א', 'תגית ב']);
      expect(plugin.requiresNetwork, isTrue);
      expect(plugin.supportsDirectInstall, isTrue);
      expect(plugin.isFeatured, isTrue);
      expect(plugin.categorySlugs, ['study-tools']);
      expect(restored.categories.single.name, 'כלי לימוד');
      expect(restored.categories.single.showOnHome, isTrue);
      expect(restored.categories.single.homeLimit, 4);
      expect(restored.categories.single.pluginIds, ['abc']);
      expect(restored.categoryBySlug('study-tools')?.pluginCount, 1);
      expect(restored.home.title, 'חנות התוספים');
      expect(restored.home.subtitle, 'תוספים שמרחיבים את אוצריא');
      expect(plugin.downloadCount, 42);
      expect(plugin.imagePath, 'files/abc/image.png');
      expect(plugin.screenshotPaths, ['files/abc/screenshot-0.png']);
      expect(plugin.localFile?.fileName, 'tosef.otzplugin');
      expect(plugin.localFile?.size, 1234);
      expect(plugin.manifestId, 'real-abc');
      expect(
        plugin.remoteDownloadUrl,
        'https://otzaria.org/api/plugins/abc/download',
      );
    });

    test('רשומה פגומה מדולגת, השאר נשמר', () {
      final catalog = PluginCatalog.fromJson({
        'lastSync': 'לא תאריך',
        'plugins': [
          'לא אובייקט',
          {'id': 'ok', 'name': 'תקין'},
        ],
      });

      expect(catalog.lastSync, isNull);
      expect(catalog.plugins.single.id, 'ok');
    });

    test('קטלוג בלי שדה plugins מחזיר רשימה ריקה', () {
      expect(PluginCatalog.fromJson({}).plugins, isEmpty);
    });

    test('plugins שאינו רשימה מחזיר רשימה ריקה', () {
      expect(PluginCatalog.fromJson({'plugins': {}}).plugins, isEmpty);
      expect(PluginCatalog.fromJson({'categories': 7}).categories, isEmpty);
    });

    test('קטלוג ישן בלי קטגוריות נטען כרגיל', () {
      final catalog = PluginCatalog.fromJson({
        'plugins': [
          {'id': 'ok', 'name': 'תקין'},
        ],
      });

      expect(catalog.categories, isEmpty);
      expect(catalog.home, PluginStoreHome.empty);
      expect(catalog.plugins.single.categorySlugs, isEmpty);
    });

    test('קטגוריה בלי slug מדולגת — אין לפיה סינון', () {
      final catalog = PluginCatalog.fromJson({
        'categories': [
          {'name': 'בלי slug'},
          {'slug': 'ok', 'name': 'תקינה'},
        ],
      });

      expect(catalog.categories.single.slug, 'ok');
    });

    test('categoryBySlug מחזיר null לקטגוריה שאינה קיימת', () {
      expect(PluginCatalog.empty.categoryBySlug('nope'), isNull);
      expect(PluginCatalog.empty.plugins, isEmpty);
    });

    test('סדר התוספים נשמר כמו שהאתר החזיר', () {
      final catalog = PluginCatalog.fromJson({
        'plugins': [
          {'id': 'c'},
          {'id': 'a'},
          {'id': 'b'},
        ],
      });

      expect(catalog.plugins.map((e) => e.id), ['c', 'a', 'b']);
    });
  });

  group('PluginStoreCategory', () {
    test('fromApi קורא את מזהי התוספים בסדר שהאתר החזיר', () {
      final category = PluginStoreCategory.fromApi(const {
        'slug': 'study-tools',
        'name': 'כלי לימוד',
        'description': 'תיאור',
        'plugins': [
          {'id': 'b'},
          {'id': 'a'},
          {'name': 'בלי id'},
          {'id': ''},
          'לא אובייקט',
        ],
      });

      expect(category.pluginIds, ['b', 'a']);
      expect(category.pluginCount, 2);
    });

    test('קטגוריה בלי רשימת תוספים (סיכום מדף הבית) יוצאת ריקה', () {
      final category = PluginStoreCategory.fromApi(const {
        'slug': 'x',
        'name': 'קטגוריה',
        'pluginCount': 7,
      });

      expect(category.pluginIds, isEmpty);
    });

    test('שדות שורת דף-הבית נקראים, עם ברירת מחדל ל-homeLimit', () {
      final onHome = PluginStoreCategory.fromApi(const {
        'slug': 'x',
        'name': 'קטגוריה',
        'showOnHome': true,
        'homeLimit': 3,
      });
      expect(onHome.showOnHome, isTrue);
      expect(onHome.homeLimit, 3);

      final plain = PluginStoreCategory.fromApi(const {'slug': 'y'});
      expect(plain.showOnHome, isFalse);
      expect(plain.homeLimit, PluginStoreCategory.defaultHomeLimit);
    });

    test('homeLimit לא חוקי נופל לברירת המחדל של האתר', () {
      for (final value in [0, -1, '4', null]) {
        expect(
          PluginStoreCategory.fromApi({'slug': 'x', 'homeLimit': value})
              .homeLimit,
          PluginStoreCategory.defaultHomeLimit,
        );
      }
    });

    test('fromJson נופל לשם ה-slug כשאין שם', () {
      final category = PluginStoreCategory.fromJson(const {'slug': 'study'})!;

      expect(category.name, 'study');
      expect(category.description, '');
      expect(category.pluginIds, isEmpty);
    });

    test('fromJson מדלג על רשומה שאינה אובייקט או בלי slug', () {
      expect(PluginStoreCategory.fromJson(null), isNull);
      expect(PluginStoreCategory.fromJson('study'), isNull);
      expect(PluginStoreCategory.fromJson(const {'name': 'בלי slug'}), isNull);
      expect(PluginStoreCategory.fromJson(const {'slug': ''}), isNull);
    });

    test('copyWith מחליף רק את רשימת התוספים', () {
      const category = PluginStoreCategory(
        slug: 'study',
        name: 'כלי לימוד',
        showOnHome: true,
        homeLimit: 3,
        pluginIds: ['a'],
      );

      final copy = category.copyWith(pluginIds: const ['b', 'a']);
      expect(copy.pluginIds, ['b', 'a']);
      expect(copy.showOnHome, isTrue);
      expect(copy.homeLimit, 3);
      expect(copy.name, 'כלי לימוד');
    });
  });

  group('PluginStoreHome', () {
    test('fromApi קורא את הטקסטים שנאצרו באתר', () {
      final home = PluginStoreHome.fromApi(const {
        'homeTitle': 'חנות התוספים',
        'homeSubtitle': 'תקציר',
        'שדה-נוסף': 1,
      });

      expect(home.title, 'חנות התוספים');
      expect(home.subtitle, 'תקציר');
      expect(home.isEmpty, isFalse);
    });

    test('שדות חסרים או מטיפוס אחר נותנים ריק — הממשק הוא שנופל לברירת מחדל',
        () {
      expect(PluginStoreHome.fromApi(const {}), PluginStoreHome.empty);
      expect(
        PluginStoreHome.fromApi(const {'homeTitle': 7}),
        PluginStoreHome.empty,
      );
      expect(PluginStoreHome.empty.isEmpty, isTrue);
    });

    test('fromJson של ערך שאינו אובייקט מחזיר ריק', () {
      expect(PluginStoreHome.fromJson(null), PluginStoreHome.empty);
      expect(PluginStoreHome.fromJson('טקסט'), PluginStoreHome.empty);
      expect(
        PluginStoreHome.fromJson(const {'title': 'א', 'subtitle': 'ב'}),
        const PluginStoreHome(title: 'א', subtitle: 'ב'),
      );
    });
  });

  group('PluginSyncProgress', () {
    test('fraction מחושב רק כשידוע היעד', () {
      const known = PluginSyncProgress(
        phase: PluginSyncPhase.plugin,
        message: '',
        current: 1,
        total: 4,
      );
      expect(known.fraction, 0.25);

      const noTotal = PluginSyncProgress(
        phase: PluginSyncPhase.plugin,
        message: '',
        current: 1,
      );
      expect(noTotal.fraction, isNull);

      const zeroTotal = PluginSyncProgress(
        phase: PluginSyncPhase.plugin,
        message: '',
        current: 0,
        total: 0,
      );
      expect(zeroTotal.fraction, isNull);

      const start = PluginSyncProgress(
        phase: PluginSyncPhase.start,
        message: '',
      );
      expect(start.fraction, isNull);
    });
  });

  group('תאימות לאחור של "תוסף נבחר"', () {
    test('האתר עדיין שולח isPinned, ומשמעותו נבחר', () {
      final plugin = StorePlugin.fromApi(
        const {'id': 'x', 'isPinned': true},
        'https://otzaria.org',
      );
      expect(plugin.isFeatured, isTrue);
    });

    test('קטלוג שנכתב בגרסה קודמת נקרא גם הוא כנבחר', () {
      expect(
        StorePlugin.fromJson(const {'id': 'x', 'isPinned': true}).isFeatured,
        isTrue,
      );
      expect(
        StorePlugin.fromJson(const {'id': 'x', 'isFeatured': true}).isFeatured,
        isTrue,
      );
      expect(StorePlugin.fromJson(const {'id': 'x'}).isFeatured, isFalse);
    });
  });

  group('matchesQuery', () {
    final plugin = StorePlugin.fromApi({
      'id': 'x',
      'name': 'מפרשים',
      'shortDescription': 'הוספת מפרשים',
      'description': 'תוסף שמוסיף פירושים',
      'author': 'Yehuda',
      'tags': ['לימוד', 'Study'],
    }, 'https://otzaria.org');

    test('חיפוש ריק מחזיר הכול', () {
      expect(plugin.matchesQuery('  '), isTrue);
      expect(plugin.matchesQuery(''), isTrue);
    });

    test('מוצא לפי שם, תיאור, מפתח ותגית', () {
      expect(plugin.matchesQuery('מפרש'), isTrue);
      expect(plugin.matchesQuery('פירושים'), isTrue);
      expect(plugin.matchesQuery('לימוד'), isTrue);
      expect(plugin.matchesQuery('yehuda'), isTrue);
      expect(plugin.matchesQuery('אין כזה'), isFalse);
    });

    test('החיפוש אינו תלוי רישיות', () {
      expect(plugin.matchesQuery('STUDY'), isTrue);
      expect(plugin.matchesQuery('YEHUDA'), isTrue);
    });
  });
}
