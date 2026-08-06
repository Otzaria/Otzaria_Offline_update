import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

void main() {
  group('comparePluginVersions', () {
    test('משווה לפי מקטעים מספריים', () {
      expect(comparePluginVersions('1.2.0', '1.1.9'), 1);
      expect(comparePluginVersions('1.1.9', '1.2.0'), -1);
      expect(comparePluginVersions('2.0.0', '2.0.0'), 0);
      expect(comparePluginVersions('1.10.0', '1.9.0'), 1);
    });

    test('אורך שונה מרופד באפסים', () {
      expect(comparePluginVersions('1.2', '1.2.0'), 0);
      expect(comparePluginVersions('1.2.1', '1.2'), 1);
    });

    test('null ומקטע לא-מספרי נחשבים אפס', () {
      expect(comparePluginVersions(null, '0'), 0);
      expect(comparePluginVersions('1.x.0', '1.0.0'), 0);
      expect(comparePluginVersions('1.0', null), 1);
    });
  });

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
          ),
        ],
      );

      final restored = PluginCatalog.fromJson(original.toJson());
      final plugin = restored.plugins.single;

      expect(restored.lastSync, original.lastSync);
      expect(plugin.name, 'תוסף בדיקה');
      expect(plugin.version, '1.2.3');
      expect(plugin.tags, ['תגית א', 'תגית ב']);
      expect(plugin.requiresNetwork, isTrue);
      expect(plugin.supportsDirectInstall, isTrue);
      expect(plugin.isPinned, isTrue);
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
  });

  group('matchesQuery', () {
    final plugin = StorePlugin.fromApi({
      'id': 'x',
      'name': 'מפרשים',
      'shortDescription': 'הוספת מפרשים',
      'description': 'תוסף שמוסיף פירושים',
      'tags': ['לימוד'],
    }, 'https://otzaria.org');

    test('חיפוש ריק מחזיר הכול', () {
      expect(plugin.matchesQuery('  '), isTrue);
    });

    test('מוצא לפי שם, תיאור ותגית', () {
      expect(plugin.matchesQuery('מפרש'), isTrue);
      expect(plugin.matchesQuery('פירושים'), isTrue);
      expect(plugin.matchesQuery('לימוד'), isTrue);
      expect(plugin.matchesQuery('אין כזה'), isFalse);
    });
  });
}
