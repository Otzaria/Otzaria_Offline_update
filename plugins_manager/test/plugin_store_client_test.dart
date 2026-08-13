import 'dart:async';
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
  final strings = AppL10n.strings.pluginsDomain;

  setUp(() => temp = createTempDir());
  tearDown(() => deleteTempDir(temp));

  PluginStoreClient clientFor(
    Future<http.Response> Function(http.Request request) handler, {
    Duration timeout = const Duration(seconds: 20),
  }) =>
      PluginStoreClient(
        baseUrl: 'https://otzaria.test',
        client: MockClient(handler),
        timeout: timeout,
      );

  group('כתובות', () {
    test('סלאש מיותר בסוף baseUrl נחתך', () {
      final client = clientFor((_) async => jsonResponse(const []));
      expect(
        PluginStoreClient(
          baseUrl: 'https://otzaria.org/',
          client: MockClient((_) async => http.Response('', 200)),
        ).baseUrl,
        'https://otzaria.org',
      );
      expect(PluginStoreClient.defaultBaseUrl, 'https://otzaria.org');
      client.dispose();
    });

    test('absolute משלים נתיב יחסי ומשאיר כתובת מלאה', () {
      final client = clientFor((_) async => jsonResponse(const []));

      expect(client.absolute('/a/b.png'), 'https://otzaria.test/a/b.png');
      expect(client.absolute('https://cdn.example/x'), 'https://cdn.example/x');
      expect(client.absolute('http://cdn.example/x'), 'http://cdn.example/x');
    });
  });

  group('fetchCatalog', () {
    test('מחזיר את הרשימה בסדר שהאתר שלח ומסנן רשומות שאינן אובייקט', () async {
      final client = clientFor((request) async {
        expect(request.url.toString(), 'https://otzaria.test/api/plugins');
        return jsonResponse([
          {'id': 'a', 'name': 'אלף'},
          'זבל',
          {'id': 'b', 'name': 'בית'},
        ]);
      });

      final catalog = await client.fetchCatalog();
      expect(catalog.map((e) => e['id']), ['a', 'b']);
      expect(catalog.first['name'], 'אלף');
    });

    test('תשובה שאינה רשימה זורקת', () async {
      final client = clientFor((_) async => jsonResponse({'plugins': []}));

      expect(
        () => client.fetchCatalog(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.responseNotPluginList,
        )),
      );
    });

    test('סטטוס שאינו 200 זורק עם ההודעה מ-l10n', () async {
      final client = clientFor((_) async => http.Response('boom', 503));

      expect(
        () => client.fetchCatalog(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.loadFailed(strings.whatPluginList, 503),
        )),
      );
    });

    test('תשובה שאינה JSON זורקת', () async {
      final client = clientFor((_) async => http.Response('<html>', 200));

      expect(
        () => client.fetchCatalog(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.responseNotJson(strings.whatPluginList),
        )),
      );
    });

    test('כשל רשת נעטף כ-PluginStoreException', () async {
      final client = clientFor(
        (_) async => throw const SocketException('אין רשת'),
      );

      expect(
        () => client.fetchCatalog(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          startsWith(strings.siteUnreachable('')),
        )),
      );
    });

    test('בקשה שנתקעת נחתכת לפי ה-timeout, בהודעה מתורגמת', () async {
      final client = clientFor(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return jsonResponse(const []);
        },
        timeout: const Duration(milliseconds: 20),
      );

      expect(
        () => client.fetchCatalog(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          // ולא "TimeoutException after ...: Future not completed".
          strings.siteUnreachable(strings.networkTimedOut),
        )),
      );
    });

    test('גוף התשובה מפוענח כ-UTF-8 גם בלי charset בכותרת', () async {
      final client = clientFor((_) async => http.Response.bytes(
            utf8.encode(jsonEncode([
              {'id': 'a', 'name': 'מפרשים'}
            ])),
            200,
          ));

      expect((await client.fetchCatalog()).single['name'], 'מפרשים');
    });
  });

  group('fetchStoreHome', () {
    test('מחזיר את המפה כמו שהיא', () async {
      final client = clientFor((request) async {
        expect(request.url.path, '/api/plugins/store-home');
        return jsonResponse({
          'settings': {'homeTitle': 'החנות', 'homeSubtitle': 'תקציר'},
          'categories': [
            {'slug': 'study', 'name': 'כלי לימוד'}
          ],
        });
      });

      final home = await client.fetchStoreHome();
      expect(home['settings'], isA<Map>());
      expect((home['categories'] as List).length, 1);
    });

    test('אתר ישן בלי הנתיב מחזיר 404 — הלקוח זורק, הסנכרון הוא שסופג',
        () async {
      final client = clientFor((_) async => http.Response('Not found', 404));

      expect(
        () => client.fetchStoreHome(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.loadFailed(strings.whatStoreStructure, 404),
        )),
      );
    });

    test('תשובה שאינה אובייקט זורקת', () async {
      final client = clientFor((_) async => jsonResponse(const []));

      expect(
        () => client.fetchStoreHome(),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.responseUnexpectedShape,
        )),
      );
    });

    test('תשובה של אתר ישן בלי שדות העיצוב מחדש נטענת לברירות מחדל', () async {
      final client = clientFor((_) async => jsonResponse({'categories': []}));
      final home = await client.fetchStoreHome();

      expect(PluginStoreHome.fromApi(const {}).isEmpty, isTrue);
      expect(home['settings'], isNull);
      expect(home['featured'], isNull);
    });
  });

  group('fetchCategory', () {
    test('slug מקודד בכתובת', () async {
      late Uri requested;
      final client = clientFor((request) async {
        requested = request.url;
        return jsonResponse({'slug': 'הלכה', 'name': 'הלכה'});
      });

      final category = await client.fetchCategory('הלכה');

      expect(requested.toString(), contains('%D7%94%D7%9C%D7%9B%D7%94'));
      expect(requested.pathSegments.last, 'הלכה');
      expect(category['slug'], 'הלכה');
    });

    test('כשל בקטגוריה מדווח עם שם הקטגוריה בהודעה', () async {
      final client = clientFor((_) async => http.Response('nope', 500));

      expect(
        () => client.fetchCategory('study'),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.loadFailed(strings.whatCategory('study'), 500),
        )),
      );
    });
  });

  group('downloadAsset', () {
    http.Response asset(List<int> bytes, Map<String, String> headers) =>
        http.Response.bytes(bytes, 200, headers: headers);

    /// לקוח שהתשובה שלו זורמת — כך נבדק הזמן הקצוב על הגוף ולא על הכותרות.
    PluginStoreClient streamingClientFor(
      Stream<List<int>> body, {
      required Duration stallTimeout,
    }) =>
        PluginStoreClient(
          baseUrl: 'https://otzaria.test',
          client: MockClient.streaming(
            (_, __) async => http.StreamedResponse(body, 200),
          ),
          stallTimeout: stallTimeout,
        );

    test('הסיומת נלקחת מ-Content-Disposition, כולל שם עברי', () async {
      final client = clientFor((_) async => asset(pluginBytes('{"id":"x"}'), {
            'content-disposition':
                "attachment; filename*=UTF-8''%D7%9E%D7%A4%D7%A8%D7%A9%D7%99%D7%9D.otzplugin",
          }));

      final downloaded = await client.downloadAsset(
        '/api/plugins/a/download',
        p.join(temp.path, 'plugin'),
        preferredExt: '.otzplugin',
      );

      expect(downloaded.ext, '.otzplugin');
      expect(downloaded.originalName, 'מפרשים.otzplugin');
      expect(downloaded.path, p.join(temp.path, 'plugin.otzplugin'));
      expect(File(downloaded.path).existsSync(), isTrue);
      expect(downloaded.size, File(downloaded.path).lengthSync());
    });

    test('בלי Content-Disposition הסיומת נגזרת מ-Content-Type', () async {
      final client = clientFor(
        (_) async =>
            asset(const [137, 80, 78, 71], {'content-type': 'image/png'}),
      );

      final downloaded = await client.downloadAsset(
        '/api/plugins/a/image',
        p.join(temp.path, 'image'),
      );

      expect(downloaded.ext, '.png');
      expect(downloaded.originalName, isNull);
      expect(downloaded.path, endsWith('image.png'));
    });

    test('Content-Type עם charset עדיין ממופה', () async {
      final client = clientFor((_) async => asset(
            const [1, 2],
            {'content-type': 'image/jpeg; charset=binary'},
          ));

      final downloaded = await client.downloadAsset(
        '/x',
        p.join(temp.path, 'a'),
      );
      expect(downloaded.ext, '.jpg');
    });

    test('סוג לא מוכר נופל ל-preferredExt, ובלעדיו נשאר בלי סיומת', () async {
      final client = clientFor(
        (_) async => asset(const [1], {'content-type': 'application/zip'}),
      );

      expect(
        (await client.downloadAsset(
          '/x',
          p.join(temp.path, 'a'),
          preferredExt: '.otzplugin',
        ))
            .ext,
        '.otzplugin',
      );
      expect(
        (await client.downloadAsset('/x', p.join(temp.path, 'b'))).ext,
        '',
      );
    });

    test('תיקיית היעד נוצרת לבד', () async {
      final client = clientFor(
        (_) async => asset(const [1], {'content-type': 'image/png'}),
      );

      final downloaded = await client.downloadAsset(
        '/x',
        p.join(temp.path, 'files', 'abc', 'image'),
      );

      expect(File(downloaded.path).existsSync(), isTrue);
    });

    test('סטטוס שאינו 200 זורק עם הכתובת בהודעה', () async {
      final client = clientFor((_) async => http.Response('nope', 404));

      expect(
        () => client.downloadAsset(
            '/api/plugins/a/image', p.join(temp.path, 'i')),
        throwsA(isA<PluginStoreException>().having(
          (e) => e.message,
          'message',
          strings.httpStatusFor(404, '/api/plugins/a/image'),
        )),
      );
    });

    test('הורדה איטית שמתקדמת אינה נחתכת — הקצוב הוא על תקיעה, לא על משך',
        () async {
      Stream<List<int>> trickle() async* {
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          yield [i];
        }
      }

      final client = streamingClientFor(
        trickle(),
        stallTimeout: const Duration(milliseconds: 150),
      );

      // 200ms סה"כ מול קצוב של 150ms — לפני התיקון זה היה נכשל.
      final downloaded =
          await client.downloadAsset('/x', p.join(temp.path, 'a'));
      expect(downloaded.size, 5);
      expect(File(downloaded.path).lengthSync(), 5);
    });

    test('גוף שנתקע נחתך, בלי קובץ חלקי ובלי לפגוע בקובץ הקודם', () async {
      final stuck = StreamController<List<int>>();
      stuck.add(const [1, 2, 3]); // מנה אחת, ואז שקט
      final client = streamingClientFor(
        stuck.stream,
        stallTimeout: const Duration(milliseconds: 30),
      );
      final dest = File(p.join(temp.path, 'a.otzplugin'))
        ..writeAsBytesSync(const [9, 9]);

      await expectLater(
        client.downloadAsset(
          '/x',
          p.join(temp.path, 'a'),
          preferredExt: '.otzplugin',
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(dest.readAsBytesSync(), const [9, 9]);
      expect(File('${dest.path}.part').existsSync(), isFalse);
      await stuck.close();
    });

    test('כתובת מוחלטת אינה מקבלת את baseUrl כקידומת', () async {
      late Uri requested;
      final client = clientFor((request) async {
        requested = request.url;
        return asset(const [1], {'content-type': 'image/png'});
      });

      await client.downloadAsset(
        'https://cdn.example/img.png',
        p.join(temp.path, 'i'),
      );
      expect(requested.toString(), 'https://cdn.example/img.png');
    });
  });

  group('parseContentDisposition', () {
    test('צורת UTF-8 מפוענחת (שמות עבריים)', () {
      final parsed = PluginStoreClient.parseContentDisposition(
        "attachment; filename*=UTF-8''%D7%9E%D7%A4%D7%A8%D7%A9%D7%99%D7%9D.otzplugin",
      );
      expect(parsed?.name, 'מפרשים.otzplugin');
      expect(parsed?.ext, '.otzplugin');
    });

    test('צורת filename פשוטה, עם מרכאות ובלעדיהן', () {
      expect(
        PluginStoreClient.parseContentDisposition(
          'attachment; filename="my-plugin.otzplugin"',
        )?.name,
        'my-plugin.otzplugin',
      );
      expect(
        PluginStoreClient.parseContentDisposition(
          'attachment; filename=my-plugin.otzplugin',
        )?.name,
        'my-plugin.otzplugin',
      );
    });

    test('שם בלי סיומת מחזיר סיומת ריקה', () {
      final parsed = PluginStoreClient.parseContentDisposition(
        'attachment; filename="plugin"',
      );
      expect(parsed?.name, 'plugin');
      expect(parsed?.ext, '');
    });

    test('קידוד אחוזים פגום מחזיר null — הסיומת תגיע מ-preferredExt', () {
      // הצורה הפשוטה דורשת `filename=` ולכן אינה חלה על `filename*=`.
      expect(
        PluginStoreClient.parseContentDisposition(
          "attachment; filename*=UTF-8''%E0%A4.otzplugin",
        ),
        isNull,
      );
    });

    test('כותרת חסרה, ריקה או בלי filename מחזירה null', () {
      expect(PluginStoreClient.parseContentDisposition(null), isNull);
      expect(PluginStoreClient.parseContentDisposition(''), isNull);
      expect(PluginStoreClient.parseContentDisposition('inline'), isNull);
    });
  });
}
