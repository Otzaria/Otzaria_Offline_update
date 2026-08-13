import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';
import 'package:test/test.dart';

import 'support.dart';

/// אתר מדומה מינימלי — ההצצה ניגשת ל-`/api/plugins` בלבד.
class _Site {
  _Site(this.plugins);

  final List<Map<String, dynamic>> plugins;
  final List<String> requests = [];

  http.Client build() => MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/api/plugins') return jsonResponse(plugins);
        if (request.url.path.endsWith('/download')) {
          return http.Response.bytes(
            pluginBytes('{"id":"manifest"}'),
            200,
            headers: {'content-type': 'application/zip'},
          );
        }
        return http.Response.bytes(
          const [137, 80, 78, 71],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
}

Map<String, dynamic> _plugin(String id, String version) => {
      'id': id,
      'name': 'תוסף $id',
      'version': version,
      'status': 'stable',
      'downloadUrl': '/api/plugins/$id/download',
    };

void main() {
  late Directory temp;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  PluginsManager manager(_Site site) => PluginsManager(
        resolveMirrorDir: () async => temp.path,
        baseUrl: 'https://otzaria.test',
        httpClient: site.build(),
      );

  Future<void> mirror(List<Map<String, dynamic>> plugins) async {
    final store = PluginMirrorStore(temp.path);
    await store.save(PluginCatalog(
      plugins: [
        for (final raw in plugins)
          StorePlugin.fromApi(raw, 'https://otzaria.test'),
      ],
    ));
  }

  group('הצצה לחנות שברשת', () {
    test('תוסף שאינו במראה נספר כחדש', () async {
      await mirror([_plugin('a', '1.0.0')]);
      final site = _Site([_plugin('a', '1.0.0'), _plugin('b', '2.0.0')]);

      final status = await manager(site).peekOnlineUpdates();

      expect(status.newPlugins, ['תוסף b']);
      expect(status.updatedPlugins, isEmpty);
      expect(status.totalOnline, 2);
      expect(status.hasUpdates, isTrue);
    });

    test('גרסה שונה מזו שבמראה נספרת כעדכון', () async {
      await mirror([_plugin('a', '1.0.0')]);
      final site = _Site([_plugin('a', '1.1.0')]);

      final status = await manager(site).peekOnlineUpdates();

      expect(status.newPlugins, isEmpty);
      expect(status.updatedPlugins, ['תוסף a']);
    });

    test('אותה גרסה והקבצים במקום — אין מה להוריד', () async {
      final catalog = [_plugin('a', '1.0.0'), _plugin('b', '2.0.0')];
      await manager(_Site(catalog)).sync();

      final status = await manager(_Site(catalog)).peekOnlineUpdates();

      expect(status.hasUpdates, isFalse);
      expect(status.totalOnline, 2);
    });

    test('מראה ריקה — הכול חדש, וזה מצב תקין לפני הסנכרון הראשון', () async {
      final site = _Site([_plugin('a', '1.0.0')]);

      final status = await manager(site).peekOnlineUpdates();

      expect(status.newCount, 1);
      expect(status.updatedCount, 0);
    });

    test('קובץ שנמחק מהתיקייה מדווח כחסר, גם כשהגרסה זהה', () async {
      final catalog = [_plugin('a', '1.0.0'), _plugin('b', '2.0.0')];
      await manager(_Site(catalog)).sync();

      final store = PluginMirrorStore(temp.path);
      File(store.absolutePath('files/a/plugin.otzplugin')).deleteSync();

      final status = await manager(_Site(catalog)).peekOnlineUpdates();

      expect(status.missingPlugins, ['תוסף a']);
      expect(status.newPlugins, isEmpty);
      expect(status.updatedPlugins, isEmpty);
      expect(status.hasUpdates, isTrue);
    });

    test('תוסף שאין לו downloadUrl אינו "חסר" — אין מה להביא לו', () async {
      await mirror([
        {'id': 'c', 'name': 'תוסף c', 'version': '1.0.0'},
      ]);
      final site = _Site([
        {'id': 'c', 'name': 'תוסף c', 'version': '1.0.0'},
      ]);

      expect((await manager(site).peekOnlineUpdates()).hasUpdates, isFalse);
    });

    test('תוסף שבקטלוג ומעולם לא ירד מדווח כחסר', () async {
      await mirror([_plugin('a', '1.0.0')]);
      final site = _Site([_plugin('a', '1.0.0')]);

      expect(
        (await manager(site).peekOnlineUpdates()).missingPlugins,
        ['תוסף a'],
      );
    });

    test('סנכרון שמשלים את החסר מנקה את הדיווח', () async {
      final catalog = [_plugin('a', '1.0.0')];
      await manager(_Site(catalog)).sync();
      File(PluginMirrorStore(temp.path)
              .absolutePath('files/a/plugin.otzplugin'))
          .deleteSync();

      final fixing = _Site(catalog);
      final outcome = await manager(fixing).sync();

      expect(outcome.fetched, 1);
      expect(
          fixing.requests.where((r) => r.endsWith('/download')), hasLength(1));
      expect(
        (await manager(_Site(catalog)).peekOnlineUpdates()).hasUpdates,
        isFalse,
      );
    });

    test('תוסף שירד מהאתר אינו נחשב עדכון', () async {
      await manager(_Site([_plugin('a', '1.0.0'), _plugin('b', '2.0.0')]))
          .sync();
      final site = _Site([_plugin('a', '1.0.0')]);

      expect((await manager(site).peekOnlineUpdates()).hasUpdates, isFalse);
    });

    test('ההצצה אינה מורידה נכסים ואינה נוגעת במראה', () async {
      await mirror([_plugin('a', '1.0.0')]);
      final store = PluginMirrorStore(temp.path);
      final before = File(store.catalogPath).readAsStringSync();

      final site = _Site([_plugin('a', '2.0.0')]);
      await manager(site).peekOnlineUpdates();

      expect(site.requests, ['/api/plugins']);
      expect(File(store.catalogPath).readAsStringSync(), before);
    });

    test('כשל רשת נזרק — הקורא הוא שמחליט שזה מצב תקין', () async {
      final failing = MockClient((_) async => http.Response('nope', 503));
      final broken = PluginsManager(
        resolveMirrorDir: () async => temp.path,
        baseUrl: 'https://otzaria.test',
        httpClient: failing,
      );

      await expectLater(
        broken.peekOnlineUpdates(),
        throwsA(isA<PluginStoreException>()),
      );
    });

    test('ההצצה מסכימה עם מה שסנכרון באמת יוריד', () async {
      final catalog = [_plugin('a', '1.0.0')];
      await manager(_Site(catalog)).sync();

      // אחרי סנכרון מלא אין מה להוריד...
      final same = _Site([_plugin('a', '1.0.0')]);
      expect((await manager(same).peekOnlineUpdates()).hasUpdates, isFalse);

      // ...ומה שההצצה מדווחת כעדכון הוא בדיוק מה שהסנכרון מושך.
      final newer = _Site([_plugin('a', '1.1.0')]);
      expect((await manager(newer).peekOnlineUpdates()).updatedCount, 1);

      final downloading = _Site([_plugin('a', '1.1.0')]);
      await manager(downloading).sync();
      expect(
        downloading.requests.where((r) => r.endsWith('/download')),
        hasLength(1),
      );
    });
  });

  group('תוכן מהאתר אינו מתורגם', () {
    tearDown(() => AppL10n.use(AppLanguage.hebrew));

    test('שמות התוספים בדיווח נשארים כמו שהאתר שלח', () async {
      AppL10n.use(AppLanguage.english);
      final site = _Site([_plugin('a', '1.0.0')]);

      expect((await manager(site).peekOnlineUpdates()).newPlugins, ['תוסף a']);
    });
  });
}
