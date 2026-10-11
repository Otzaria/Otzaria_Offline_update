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
