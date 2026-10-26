import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/recent_library_releases_client.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

class _FakeGuard extends OtzariaProcessGuard {
  _FakeGuard({required this.running});

  bool running;
  final asked = <List<String>>[];

  @override
  Future<bool> isAnyRunning(List<String> processNames) async {
    asked.add(processNames);
    return running;
  }
}

class _FixedSettingsReader extends OtzariaSettingsReader {
  const _FixedSettingsReader(this.settings);

  final OtzariaSettings settings;

  @override
  Future<OtzariaSettings?> read(String dataRootPath) async => settings;
}

class _TrackingClient extends http.BaseClient {
  _TrackingClient(this._inner);

  final http.Client _inner;
  var closed = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => closed++;
}

Map<String, dynamic> _release(
  String tag,
  List<String> assets, {
  bool prerelease = false,
  bool draft = false,
}) => {
  'tag_name': tag,
  'prerelease': prerelease,
  'draft': draft,
  'published_at': '2026-06-27T21:00:00Z',
  'assets': [
    for (final name in assets)
      {
        'name': name,
        'browser_download_url': 'https://lib/$tag/$name',
        'size': 1,
        'id': '$tag/$name'.hashCode.abs(),
      },
  ],
};

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('library-manager-seams-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  group('peek through an injected release client', () {
    late List<Map<String, dynamic>> releases;
    late int status;
    late List<Uri> requests;
    late RecentLibraryReleasesClient client;

    setUp(() {
      releases = [];
      status = 200;
      requests = [];
      client = RecentLibraryReleasesClient(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          if (status != 200) return http.Response('', status);
          final page = request.url.queryParameters['page'];
          return http.Response(
            jsonEncode(page == '1' ? releases : const []),
            200,
          );
        }),
      );
    });

    LibraryManager manager({bool allowPrerelease = false}) {
      final manager = LibraryManager(
        dataDir: p.join(temporary.path, 'drive'),
        environment: const {},
        allowPrerelease: allowPrerelease,
        processGuard: _FakeGuard(running: false),
        releaseClient: client,
      );
      addTearDown(manager.dispose);
      return manager;
    }

    test('the newest release that carries library content wins', () async {
      releases = [
        _release('v9-20261011', ['notes.txt']),
        _release('v8-20261011', [
          'patch-v7-v8.db.zst.manifest.json',
          'patch-v7-v8.db.zst',
        ]),
        _release('v6-20261011', ['seforim.db.zst']),
      ];

      expect(await manager().peekLatestOnlineVersion(), 8);
      expect(requests, hasLength(1));
      expect(requests.single.host, 'api.github.com');
    });

    test('a pre-release counts only on the pre-release channel', () async {
      releases = [
        _release('v5-20261011', [
          'patch-v4-v5.db.zst.manifest.json',
        ], prerelease: true),
        _release('v4-20261011', ['seforim.db.zst']),
        _release('v7-20261011', ['seforim.db.zst'], draft: true),
      ];

      expect(await manager().peekLatestOnlineVersion(), 4);
      expect(await manager(allowPrerelease: true).peekLatestOnlineVersion(), 5);
    });

    test('no release with library content means no version and no smart-search '
        'peek', () async {
      releases = [
        _release('v3-20261011', ['notes.txt']),
      ];
      final library = manager();

      expect(await library.peekLatestOnlineVersion(), isNull);
      expect(await library.peekPendingSemanticSearch(), isFalse);
      expect(requests, hasLength(2));
    });

    test('a failed peek forgets the previous tag', () async {
      releases = [
        _release('v3-20261011', ['seforim.db.zst']),
      ];
      final library = manager();
      expect(await library.peekLatestOnlineVersion(), 3);

      status = 500;
      await expectLater(library.peekLatestOnlineVersion(), throwsException);
      await expectLater(library.peekPendingSemanticSearch(), throwsException);
      expect(requests, hasLength(3));
    });

    test('the network timeout reaches the injected client', () {
      final library = manager();
      library.networkTimeout = const Duration(seconds: 3);
      expect(client.timeout, const Duration(seconds: 3));
    });
  });

  group('peekedDownloadBytesBound — the size shown before a click', () {
    late List<Map<String, dynamic>> releases;
    late bool companionsDown;
    late int releaseRequests;

    Map<String, dynamic> release(String tag, Map<String, int> assets) => {
      'tag_name': tag,
      'prerelease': false,
      'draft': false,
      'published_at': '2026-06-27T21:00:00Z',
      'assets': [
        for (final MapEntry(key: name, value: size) in assets.entries)
          {
            'name': name,
            'browser_download_url': 'https://lib/$tag/$name',
            'size': size,
            'id': '$tag/$name'.hashCode.abs(),
          },
      ],
    };

    Map<String, dynamic> companionAsset(String name, int size) => {
      'name': name,
      'browser_download_url': 'https://x/$name',
      'size': size,
      'id': name.hashCode.abs(),
    };

    final companionsApi = MockClient((request) async {
      final url = request.url.toString();
      if (companionsDown) return http.Response('', 503);
      if (url.contains('/repos/Otzaria/otzaria-library/')) {
        return http.Response(
          jsonEncode({
            'tag_name': 'lib-v9',
            'assets': [companionAsset('talmud_bavli_latest.tar.zst', 400)],
          }),
          200,
        );
      }
      if (url.contains('/repos/Otzaria/otzar-HB_catalog/')) {
        return http.Response(
          jsonEncode({
            'tag_name': 'cat-v3',
            'assets': [
              companionAsset('otzar-HB_catalog.db.zst', 30),
              companionAsset('version.txt', 2),
            ],
          }),
          200,
        );
      }
      if (url.contains('/repos/Otzaria/SeforimMagicIndexer/')) {
        return http.Response(
          jsonEncode({
            'tag_name': 'dict-v7',
            'assets': [companionAsset('lexical.db', 20)],
          }),
          200,
        );
      }
      return http.Response('55', 200);
    });

    setUp(() {
      companionsDown = false;
      releaseRequests = 0;
      releases = [
        release('v8-20261011', {
          'patch-v7-v8.db.zst.manifest.json': 2,
          'patch-v7-v8.db.zst': 100,
          'seforim.db.zst': 1000,
          'notes.txt': 7,
        }),
        release('v7-20261011', {
          'patch-v6-v7.db.zst.manifest.json': 2,
          'patch-v6-v7.db.zst': 50,
          'seforim.db.zst': 900,
        }),
      ];
    });

    LibraryManager manager({bool personal = false}) {
      final manager = LibraryManager(
        dataDir: p.join(temporary.path, 'drive'),
        environment: const {},
        personalUpdateMode: personal,
        processGuard: _FakeGuard(running: false),
        releaseClient: RecentLibraryReleasesClient(
          httpClient: MockClient((request) async {
            releaseRequests++;
            final page = request.url.queryParameters['page'];
            return http.Response(
              jsonEncode(page == '1' ? releases : const []),
              200,
            );
          }),
        ),
      );
      addTearDown(manager.dispose);
      return manager;
    }

    Future<int?> peekAndBound(LibraryManager library) =>
        http.runWithClient(() async {
          await library.peekLatestOnlineVersion();
          try {
            await library.peekPendingCompanions();
          } catch (_) {}
          return library.peekedDownloadBytesBound();
        }, () => companionsApi);

    test('newest full DB, every patch and the pending companions — the older '
        'full DB and unrelated assets do not count', () async {
      final library = manager();
      expect(await peekAndBound(library), 2 + 100 + 1000 + 2 + 50 + 450);

      // החישוב עצמו אינו פונה לרשת — רק ההצצות שלפניו.
      final before = releaseRequests;
      final again = await http.runWithClient(
        library.peekedDownloadBytesBound,
        () => MockClient((request) async => fail('network: ${request.url}')),
      );
      expect(again, 2 + 100 + 1000 + 2 + 50 + 450);
      expect(releaseRequests, before);
    });

    test('assets already complete in the mirror are left out', () async {
      final library = manager();
      final mirror = Directory(library.mirrorDir)..createSync(recursive: true);
      String held(String tag, String name, int size) {
        final relative = 'assets/$tag/$name';
        File(p.join(mirror.path, relative))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(size, 0));
        return relative;
      }

      File(p.join(mirror.path, 'releases.json')).writeAsStringSync(
        jsonEncode({
          'releases': [
            {
              'tag': 'v8-20261011',
              'assets': [
                {
                  'name': 'seforim.db.zst',
                  'downloadUrl': held('v8-20261011', 'seforim.db.zst', 1000),
                  'size': 1000,
                },
                // נכס קטוע אינו שלם — עדיין נספר.
                {
                  'name': 'patch-v7-v8.db.zst',
                  'downloadUrl': held('v8-20261011', 'patch-v7-v8.db.zst', 60),
                  'size': 100,
                },
              ],
            },
          ],
        }),
      );

      expect(await peekAndBound(library), 2 + 100 + 2 + 50 + 450);
    });

    test(
      'no bound without a successful peek, or for a split full DB',
      () async {
        expect(await manager().peekedDownloadBytesBound(), isNull);

        companionsDown = true;
        expect(await peekAndBound(manager()), isNull);
        companionsDown = false;

        // מצב אישי בלי מחשב רשום מוריד כמו הרגיל — אותו חסם.
        expect(
          await peekAndBound(manager(personal: true)),
          2 + 100 + 1000 + 2 + 50 + 450,
        );

        releases.insert(
          0,
          release('v9-20261011', {'seforim.db.zst.manifest.json': 3}),
        );
        expect(await peekAndBound(manager()), isNull);
      },
    );

    const mib = 1 << 20;

    String manifestJson(
      int from,
      int to, {
      bool fullRebase = false,
      int schema = 6,
      int format = 4,
    }) => jsonEncode({
      'fromVersion': from,
      'toVersion': to,
      'fromSchemaVersion': schema,
      'toSchemaVersion': schema,
      'patchFormatVersion': format,
      'fullRebase': fullRebase,
      'fromContentHash': fullRebase ? 'full-rebase' : 'a$from',
      'toContentHash': fullRebase ? 'full-rebase' : 'a$to',
      'patchFiles': [
        {
          'file': 'patch-v$from-v$to.db.zst',
          'compression': 'zstd',
          'sha256': '0' * 64,
          'size': 1,
          'uncompressedSha256': '0' * 64,
          'uncompressedSize': 1,
        },
      ],
    });

    void putOnDrive(
      LibraryManager library,
      String tag,
      String name,
      Object content,
    ) {
      final file = File(p.join(library.mirrorDir, 'assets', tag, name))
        ..createSync(recursive: true);
      if (content is String) {
        file.writeAsStringSync(content);
      } else {
        file.writeAsBytesSync(List.filled(content as int, 0));
      }
    }

    group('personal mode — the export choice, never below it', () {
      Future<void> registered(int version) => LibraryStateStore(
        p.join(temporary.path, 'drive', LibraryStateStore.fileName),
      ).recordKnownDbVersion('OFFLINE|me', version);

      // manifest שבכונן ותקף — רק הוא מוכיח שהקשת תיבנה.
      void heldManifest(LibraryManager library) {
        final body = manifestJson(7, 8);
        putOnDrive(
          library,
          'v8-20261011',
          'patch-v7-v8.db.zst.manifest.json',
          body,
        );
        releases[0]['assets'] = [
          for (final asset in releases[0]['assets'] as List)
            if ((asset as Map)['name'] == 'patch-v7-v8.db.zst.manifest.json')
              {...asset, 'size': utf8.encode(body).length}
            else
              asset,
        ];
      }

      test(
        'new manifests only by name — the larger of the two routes',
        () async {
          await registered(7);
          expect(await peekAndBound(manager(personal: true)), 1000 + 450);
        },
      );

      test('a held, appliable chain that wins — only its patches', () async {
        await registered(7);
        final library = manager(personal: true);
        heldManifest(library);
        // ה-manifest כבר בכונן: יורד רק קובץ העדכון.
        expect(await peekAndBound(library), 100 + 450);
      });

      test('a held manifest marked fullRebase is not a route', () async {
        await registered(7);
        final library = manager(personal: true);
        final body = manifestJson(7, 8, fullRebase: true);
        putOnDrive(
          library,
          'v8-20261011',
          'patch-v7-v8.db.zst.manifest.json',
          body,
        );
        releases[0]['assets'] = [
          for (final asset in releases[0]['assets'] as List)
            if ((asset as Map)['name'] == 'patch-v7-v8.db.zst.manifest.json')
              {...asset, 'size': utf8.encode(body).length}
            else
              asset,
        ];
        expect(await peekAndBound(library), 1000 + 450);
      });

      void resize(String name, int size, {String? rename}) =>
          releases[0]['assets'] = [
            for (final asset in releases[0]['assets'] as List)
              if ((asset as Map)['name'] == name)
                {...asset, 'size': size, 'name': rename ?? name}
              else
                asset,
          ];

      test(
        'a held, appliable chain that the full DB beats — the full DB',
        () async {
          await registered(7);
          final library = manager(personal: true);
          heldManifest(library);
          resize('patch-v7-v8.db.zst', 900 << 20);
          expect(await peekAndBound(library), 1000 + 450);
        },
      );

      test(
        'by name only, with patches larger than the full DB — the patches',
        () async {
          await registered(7);
          resize('patch-v7-v8.db.zst', 900 << 20);
          expect(
            await peekAndBound(manager(personal: true)),
            2 + (900 << 20) + 450,
          );
        },
      );

      test('a manifest name that is not an edge — never "no chain"', () async {
        await registered(5);
        resize('patch-v7-v8.db.zst', 900 << 20);
        resize(
          'patch-v7-v8.db.zst.manifest.json',
          2,
          rename: 'patch-odd.db.zst.manifest.json',
        );
        // לפי השמות לבדם אין שרשרת מ-5, אבל קשת ששמה אינו מוכר עשויה להיות
        // אחת — ולכן הגדול מבין השניים, לא המסד המלא בלבד.
        expect(
          await peekAndBound(manager(personal: true)),
          2 + (900 << 20) + 2 + 50 + 450,
        );
      });

      test(
        'no chain from the registered version, even by name — the full DB',
        () async {
          await registered(5);
          expect(await peekAndBound(manager(personal: true)), 1000 + 450);
        },
      );

      test('nothing newer — no number, never 0 (a damaged mirror is rebuilt '
          'in full)', () async {
        await registered(8);
        expect(await peekAndBound(manager(personal: true)), isNull);
      });

      test('computed without network or writes to the drive', () async {
        await registered(7);
        final library = manager(personal: true);
        await peekAndBound(library);
        final drive = Directory(p.join(temporary.path, 'drive'));
        final before = drive.listSync(recursive: true).length;
        final again = await http.runWithClient(
          library.peekedDownloadBytesBound,
          () => MockClient((request) async => fail('network: ${request.url}')),
        );
        expect(again, 1000 + 450);
        expect(drive.listSync(recursive: true).length, before);
        expect(Directory(library.mirrorDir).existsSync(), isFalse);
      });
    });

    test('a patch slower to apply than the whole DB is not counted, nor the '
        'dead end it leaves', () async {
      releases = [
        release('v8-20261011', {
          'patch-v7-v8.db.zst.manifest.json': 2,
          'patch-v7-v8.db.zst': 600 * mib,
          'patch-v6-v8.db.zst.manifest.json': 2,
          'patch-v6-v8.db.zst': 30 * mib,
          'seforim.db.zst': 1800 * mib,
        }),
        release('v7-20261011', {
          'patch-v6-v7.db.zst.manifest.json': 2,
          'patch-v6-v7.db.zst': 20 * mib,
          'seforim.db.zst': 1700 * mib,
        }),
      ];

      expect(
        await peekAndBound(manager()),
        1800 * mib + 30 * mib + 3 * 2 + 450,
      );
    });

    test('a chain that continues only through a full-rebase barrier held on '
        'the drive is a dead end', () async {
      final stub = manifestJson(7, 8, fullRebase: true, format: 999);
      final stubSize = utf8.encode(stub).length;
      releases = [
        release('v8-20261011', {
          'patch-v7-v8.db.zst.manifest.json': stubSize,
          'patch-v7-v8.db.zst': 345,
          'seforim.db.zst': 1000,
        }),
        release('v7-20261011', {
          'patch-v6-v7.db.zst.manifest.json': 2,
          'patch-v6-v7.db.zst': 50,
          'seforim.db.zst': 900,
        }),
      ];

      // בלי ה-manifest בכונן — לפי השמות v7 מגיעה ל-v8, ולכן נספר.
      final library = manager();
      expect(await peekAndBound(library), 1000 + stubSize + 345 + 2 + 50 + 450);

      putOnDrive(
        library,
        'v8-20261011',
        'patch-v7-v8.db.zst.manifest.json',
        stub,
      );
      expect(await peekAndBound(library), 1000 + 2 + 450);
    });

    test('patches the drive already knows to be unusable — schema or patch '
        'format — are not counted', () async {
      final library = manager();
      final schema = manifestJson(7, 8, schema: 99);
      final format = manifestJson(6, 8, format: 99);
      putOnDrive(
        library,
        'v8-20261011',
        'patch-v7-v8.db.zst.manifest.json',
        schema,
      );
      putOnDrive(
        library,
        'v8-20261011',
        'patch-v6-v8.db.zst.manifest.json',
        format,
      );
      releases = [
        release('v8-20261011', {
          'patch-v7-v8.db.zst.manifest.json': utf8.encode(schema).length,
          'patch-v7-v8.db.zst': 100,
          'patch-v6-v8.db.zst.manifest.json': utf8.encode(format).length,
          'patch-v6-v8.db.zst': 70,
          'seforim.db.zst': 1000,
        }),
      ];

      expect(await peekAndBound(library), 1000 + 450);
    });

    test('an older complete full DB on the drive that may be reused means no '
        'bound', () async {
      final library = manager();
      putOnDrive(library, 'v7-20261011', 'seforim.db.zst', 900);
      expect(await peekAndBound(library), isNull);

      // בלי מסלול ממנו ל-v8 המייצא אינו בוחר בו; v6→v7 הופכת למבוי סתום.
      releases[0]['assets'] = [
        for (final asset in releases[0]['assets'] as List)
          if ((asset as Map)['name'] != 'patch-v7-v8.db.zst.manifest.json')
            asset,
      ];
      expect(await peekAndBound(library), 1000 + 100 + 2 + 450);
    });

    test(
      'an edge whose files the names do not settle is never dropped',
      () async {
        releases = [
          release('v8-20261011', {
            'patch-v7-v8.db.zst.manifest.json': 2,
            'patch-v7-v8.db.zst': 600 * mib,
            // קובץ נוסף בשם הקשת — אולי ב-manifest, אולי לא: הגודל אינו ודאי.
            'patch-v7-v8.db.zst.sig': 1,
            'seforim.db.zst': 1800 * mib,
          }),
          release('v7-20261011', {
            // ה-patch עוד עולה: המייצא לא יבנה קשת, ומבוי סתום אינו מוסר אותה.
            'patch-v6-v7.db.zst.manifest.json': 2,
            'seforim.db.zst': 1700 * mib,
          }),
        ];

        expect(
          await peekAndBound(manager()),
          1800 * mib + 600 * mib + 1 + 2 + 2 + 450,
        );
      },
    );

    test(
      'an older split full DB assembled on the drive means no bound',
      () async {
        releases = [
          release('v8-20261011', {
            'patch-v7-v8.db.zst.manifest.json': 2,
            'patch-v7-v8.db.zst': 100,
            'seforim.db.zst': 1000,
          }),
          release('v7-20261011', {
            'patch-v6-v7.db.zst.manifest.json': 2,
            'patch-v6-v7.db.zst': 50,
            'seforim.db.zst.manifest.json': 3,
          }),
        ];
        final library = manager();
        expect(await peekAndBound(library), 1000 + 100 + 2 + 50 + 2 + 450);

        // המייצא שומר את המורכב בשם הארכיון; גודלו רק במניפסט שברשת.
        putOnDrive(library, 'v7-20261011', 'seforim.db.zst', 900);
        expect(await peekAndBound(library), isNull);
      },
    );

    group('the v32 release history', () {
      // הנתונים האמיתיים (אוקטובר 2026), הערוץ היציב, רק נכסי המסד.
      const history = <String, Map<String, int>>{
        'v32-20261010190601': {
          'patch-v16-v32.db.zst': 345,
          'patch-v16-v32.db.zst.manifest.json': 547,
          'patch-v24-v32.db.zst': 345,
          'patch-v24-v32.db.zst.manifest.json': 547,
          'patch-v28-v32.db.zst': 345,
          'patch-v28-v32.db.zst.manifest.json': 547,
          'patch-v31-v32.db.zst': 119811206,
          'patch-v31-v32.db.zst.manifest.json': 7475,
          'seforim-schema6.db.zst': 1850679582,
        },
        'v31-20261004170255': {
          'patch-v15-v31.db.zst': 345,
          'patch-v15-v31.db.zst.manifest.json': 547,
          'patch-v23-v31.db.zst': 345,
          'patch-v23-v31.db.zst.manifest.json': 547,
          'patch-v27-v31.db.zst': 345,
          'patch-v27-v31.db.zst.manifest.json': 547,
          'patch-v29-v31.db.zst': 345,
          'patch-v29-v31.db.zst.manifest.json': 547,
          'seforim-schema6.db.zst': 1807139142,
        },
        'v28-20260910220310': {
          'patch-v27-v28.db.zst': 45560268,
          'patch-v27-v28.db.zst.manifest.json': 7128,
          'seforim.db.zst': 1434427227,
        },
        'v27-20260906092829': {
          'patch-v19-v27.db.zst': 598519600,
          'patch-v19-v27.db.zst.manifest.json': 640,
          'patch-v23-v27.db.zst': 584711742,
          'patch-v23-v27.db.zst.manifest.json': 640,
          'patch-v25-v27.db.zst': 495175415,
          'patch-v25-v27.db.zst.manifest.json': 640,
          'patch-v26-v27.db.zst': 475533836,
          'patch-v26-v27.db.zst.manifest.json': 640,
          'seforim.db.zst': 1410034443,
        },
        'v23-20260829032606': {
          'patch-v15-v23.db.zst': 43067770,
          'patch-v15-v23.db.zst.manifest.json': 611,
          'patch-v19-v23.db.zst': 34241928,
          'patch-v19-v23.db.zst.manifest.json': 611,
          'patch-v21-v23.db.zst': 15032646,
          'patch-v21-v23.db.zst.manifest.json': 610,
          'patch-v22-v23.db.zst': 8503129,
          'patch-v22-v23.db.zst.manifest.json': 609,
          'seforim.db.zst': 1373487294,
        },
        'v22-20260821152805': {
          'patch-v14-v22.db.zst': 38622335,
          'patch-v14-v22.db.zst.manifest.json': 611,
          'patch-v18-v22.db.zst': 29648217,
          'patch-v18-v22.db.zst.manifest.json': 611,
          'patch-v20-v22.db.zst': 13615192,
          'patch-v20-v22.db.zst.manifest.json': 610,
          'patch-v21-v22.db.zst': 6826052,
          'patch-v21-v22.db.zst.manifest.json': 609,
          'seforim.db.zst': 1549816972,
        },
        'v21-20260814060554': {
          'patch-v17-v21.db.zst': 23701534,
          'patch-v17-v21.db.zst.manifest.json': 611,
          'patch-v19-v21.db.zst': 22857456,
          'patch-v19-v21.db.zst.manifest.json': 611,
          'patch-v20-v21.db.zst': 6819366,
          'patch-v20-v21.db.zst.manifest.json': 609,
          'seforim.db.zst': 1548130475,
        },
        'v20-20260807110905': {
          'patch-v16-v20.db.zst': 21460084,
          'patch-v16-v20.db.zst.manifest.json': 611,
          'patch-v18-v20.db.zst': 19370803,
          'patch-v18-v20.db.zst.manifest.json': 611,
          'patch-v19-v20.db.zst': 19374632,
          'patch-v19-v20.db.zst.manifest.json': 611,
          'seforim.db.zst': 1547243670,
        },
        'v19-20260731105446': {
          'patch-v15-v19.db.zst': 19820509,
          'patch-v15-v19.db.zst.manifest.json': 611,
          'patch-v17-v19.db.zst': 10001752,
          'patch-v17-v19.db.zst.manifest.json': 610,
          'patch-v18-v19.db.zst': 123061,
          'patch-v18-v19.db.zst.manifest.json': 606,
          'seforim.db.zst': 1546371555,
        },
        'v18-20260728123527': {
          'patch-v14-v18.db.zst': 20258675,
          'patch-v14-v18.db.zst.manifest.json': 611,
          'patch-v16-v18.db.zst': 14045164,
          'patch-v16-v18.db.zst.manifest.json': 610,
          'patch-v17-v18.db.zst': 9887749,
          'patch-v17-v18.db.zst.manifest.json': 609,
          'seforim.db.zst': 1548533728,
        },
      };
      final edgeName = RegExp(
        r'^patch-v(\d+)-v(\d+)\.db\.zst\.manifest\.json$',
      );

      /// ה-manifest כפי שפורסם: patch זעיר הוא מחסום full-rebase.
      String? publishedManifest(String tag, String name) {
        final match = edgeName.firstMatch(name);
        if (match == null) return null;
        final file = name.replaceAll('.manifest.json', '');
        final stub = history[tag]![file]! < 1000;
        return manifestJson(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          fullRebase: stub,
          format: stub ? 999 : 4,
        );
      }

      LibraryManager historyManager() {
        final manager = LibraryManager(
          dataDir: p.join(temporary.path, 'drive'),
          environment: const {},
          processGuard: _FakeGuard(running: false),
          releaseClient: RecentLibraryReleasesClient(
            httpClient: MockClient((request) async {
              final segments = request.url.pathSegments;
              if (request.url.host == 'lib') {
                final body = publishedManifest(segments[0], segments[1]);
                return http.Response(body ?? '', body == null ? 404 : 200);
              }
              final page = request.url.queryParameters['page'];
              return http.Response(
                jsonEncode(page == '1' ? releases : const []),
                200,
              );
            }),
          ),
        );
        addTearDown(manager.dispose);
        return manager;
      }

      setUp(() {
        releases = [
          for (final MapEntry(key: tag, value: assets) in history.entries)
            release(tag, assets),
        ];
      });

      int sizesOf(bool Function(String name) which) => history.values
          .expand((assets) => assets.entries)
          .where((asset) => which(asset.key))
          .fold(0, (sum, asset) => sum + asset.value);

      // מה שהמייצא מוריד לכונן ריק: המסד של v32 ו-patch-v31-v32 (ועוד manifests).
      const fullDb = 1850679582;
      const realLibrary = fullDb + 119811206;

      test('an empty drive: at least the real download, without the v27 '
          'patches that are slower than a DB swap', () async {
        final bound = (await peekAndBound(historyManager()))! - 450;
        final v27Patches = sizesOf(
          (name) => name.startsWith('patch-') && name.endsWith('-v27.db.zst'),
        );

        expect(bound, greaterThanOrEqualTo(realLibrary));
        expect(
          bound,
          fullDb + sizesOf((n) => n.startsWith('patch-')) - v27Patches,
        );
        expect(bound, lessThan(3000 * 1000 * 1000));
      });

      test('the bound is never below what the export plans', () async {
        final library = historyManager();
        final bound = await peekAndBound(library);
        final probed = await http.runWithClient(
          library.probeMirrorDownloadBytes,
          () => companionsApi,
        );

        expect(probed, greaterThanOrEqualTo(realLibrary + 450));
        expect(probed, lessThan(realLibrary + 450 + 20000));
        expect(bound, greaterThanOrEqualTo(probed!));
      });

      test('with the barriers already on the drive the bound is the real '
          'download, up to the manifests', () async {
        final library = historyManager();
        final sizes = <String, Map<String, int>>{};
        for (final MapEntry(key: tag, value: assets) in history.entries) {
          sizes[tag] = {...assets};
          for (final name in assets.keys) {
            final body = publishedManifest(tag, name);
            if (body == null || !body.contains('"fullRebase":true')) continue;
            putOnDrive(library, tag, name, body);
            sizes[tag]![name] = utf8.encode(body).length;
          }
        }
        releases = [
          for (final MapEntry(key: tag, value: assets) in sizes.entries)
            release(tag, assets),
        ];

        final bound = await peekAndBound(library);
        final probed = await http.runWithClient(
          library.probeMirrorDownloadBytes,
          () => companionsApi,
        );
        expect(bound, greaterThanOrEqualTo(probed!));
        // ההפרש: manifests של קשתות שהמייצא הוריד מהתוכנית (~600 בתים כל אחד).
        expect(bound! - probed, lessThan(50000));
      });
    });
  });

  group('smart-search install gate', () {
    late String db;
    late String launch;

    setUp(() async {
      final install = p.join(temporary.path, 'application');
      launch = p.join(install, 'otzaria.exe');
      await File(launch).create(recursive: true);
      await File(
        p.join(install, LibraryDbLocator.portableMarkerFileName),
      ).create();
      db = p.join(temporary.path, 'books', 'seforim.db');
      await File(db).create(recursive: true);
    });

    LibraryManager manager(_FakeGuard guard, OtzariaSettings settings) {
      final manager = LibraryManager(
        dataDir: p.join(temporary.path, 'drive'),
        operatingSystem: Platform.operatingSystem,
        environment: const {},
        otzariaLaunchPath: () async => launch,
        settingsReader: _FixedSettingsReader(settings),
        processGuard: guard,
      );
      addTearDown(manager.dispose);
      return manager;
    }

    LibraryUpdateCheckResult check() => LibraryUpdateCheckResult(
      dbPath: db,
      semanticPending: true,
      semanticConsentGranted: true,
    );

    const granted = OtzariaSettings(
      searchFeedbackConsent: 'granted',
      searchFeedbackConsentVersion: 1,
    );

    test('a running Otzaria stops the install before it starts', () async {
      final guard = _FakeGuard(running: true);
      final warnings = <(String, Object)>[];

      await manager(guard, granted).applyUpdate(
        check(),
        onCompanionWarning: (name, error) => warnings.add((name, error)),
      );

      expect(warnings, hasLength(1));
      expect(
        warnings.single.$1,
        AppL10n.strings.libraryDomain.companionSemanticName,
      );
      expect(warnings.single.$2, isA<OtzariaIsRunningException>());
      expect(guard.asked, [
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      ]);
      expect(
        await Directory(p.join(temporary.path, 'vectors')).exists(),
        false,
      );
    });

    test(
      'consent withdrawn in Otzaria is checked before the process',
      () async {
        final guard = _FakeGuard(running: true);
        final warnings = <(String, Object)>[];

        await manager(
          guard,
          const OtzariaSettings(searchFeedbackConsent: 'declined'),
        ).applyUpdate(
          check(),
          onCompanionWarning: (name, error) => warnings.add((name, error)),
        );

        expect(warnings, hasLength(1));
        expect(
          warnings.single.$2,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.semanticConsentRequired,
          ),
        );
        expect(guard.asked, isEmpty);
      },
    );

    test('a closed Otzaria lets the install go on to the mirror', () async {
      final guard = _FakeGuard(running: false);
      final warnings = <(String, Object)>[];

      await manager(guard, granted).applyUpdate(
        check(),
        onCompanionWarning: (name, error) => warnings.add((name, error)),
      );

      expect(guard.asked, isNotEmpty);
      expect(warnings, hasLength(1));
      expect(warnings.single.$2, isNot(isA<OtzariaIsRunningException>()));
    });

    test(
      "the launcher holding Otzaria's mutex is not a running Otzaria",
      () async {
        const guard = OtzariaProcessGuard();
        final names = OtzariaProcessGuard.processNamesFor(
          Platform.operatingSystem,
        );
        if (await guard.isAnyRunning(names)) {
          markTestSkipped('Otzaria is running on this machine');
          return;
        }
        final warnings = <(String, Object)>[];
        final manager = LibraryManager(
          dataDir: p.join(temporary.path, 'drive'),
          operatingSystem: Platform.operatingSystem,
          environment: const {},
          otzariaLaunchPath: () async => launch,
          settingsReader: const _FixedSettingsReader(granted),
          processGuard: guard,
          instanceLock: const OtzariaInstanceLock(),
        );
        addTearDown(manager.dispose);

        await manager.applyUpdate(
          check(),
          onCompanionWarning: (name, error) => warnings.add((name, error)),
        );

        expect(warnings, hasLength(1));
        expect(warnings.single.$2, isNot(isA<OtzariaIsRunningException>()));
        expect(OtzariaInstanceLock.isHeldByThisProcess, isFalse);
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );
  });

  group('dispose', () {
    test('closes the companions mirror client once it exists', () async {
      final tracking = _TrackingClient(
        MockClient((_) async => http.Response('', 404)),
      );
      final manager = LibraryManager(
        dataDir: p.join(temporary.path, 'drive'),
        environment: const {},
        releaseClient: RecentLibraryReleasesClient(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        ),
      );

      await http.runWithClient(() async {
        try {
          await manager.peekPendingCompanions();
        } catch (_) {}
      }, () => tracking);
      expect(tracking.closed, 0);

      manager.dispose();
      expect(tracking.closed, 1);
    });

    test('does not build a companions mirror only to close it', () {
      var created = 0;
      final manager = LibraryManager(
        dataDir: p.join(temporary.path, 'drive'),
        environment: const {},
      );

      http.runWithClient(manager.dispose, () {
        created++;
        return MockClient((_) async => http.Response('', 404));
      });

      expect(created, 0);
    });
  });
}
