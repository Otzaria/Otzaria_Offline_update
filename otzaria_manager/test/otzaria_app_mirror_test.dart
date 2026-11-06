import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

OtzariaRelease _release({
  int size = 4,
  String tagName = '0.9.96+736',
  bool isPrerelease = true,
  DateTime? publishedAt,
  bool unknownDate = false,
}) =>
    OtzariaRelease(
      tagName: tagName,
      name: 'Otzaria $tagName',
      isPrerelease: isPrerelease,
      isDraft: false,
      publishedAt: unknownDate ? null : publishedAt ?? DateTime.utc(2026, 1, 1),
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria-$tagName-windows.exe',
      installerDownloadUrl: 'https://example/otzaria-$tagName-windows.exe',
      installerSizeBytes: size,
    );

Future<Map<String, dynamic>> _writeInstaller(
  Directory dir,
  OtzariaRelease release, {
  String installerContents = 'abcd',
  bool writeInstaller = true,
}) async {
  final installersDir = Directory(p.join(dir.path, 'installers'));
  await installersDir.create(recursive: true);
  final installer = File(
    p.join(installersDir.path, release.installerAssetName),
  );
  if (writeInstaller) await installer.writeAsString(installerContents);

  return release.toJson()
    ..['installerPath'] = p.relative(installer.path, from: dir.path);
}

Future<void> _writeMirror(
  Directory dir, {
  OtzariaRelease? stable,
  OtzariaRelease? prerelease,
  String installerContents = 'abcd',
  bool writeInstaller = true,
}) async {
  final json = <String, dynamic>{
    'schemaVersion': 3,
    'source': 'github-latest',
    if (stable != null)
      'latest': await _writeInstaller(
        dir,
        stable,
        installerContents: installerContents,
        writeInstaller: writeInstaller,
      ),
    if (prerelease != null)
      'prerelease': await _writeInstaller(
        dir,
        prerelease,
        installerContents: installerContents,
        writeInstaller: writeInstaller,
      ),
  };
  await File(p.join(dir.path, 'latest-release.json'))
      .writeAsString(_encodeLatestFixture(json));
}

void main() {
  late Directory temp;
  late OtzariaAppMirror mirror;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-mirror-test');

    mirror = OtzariaAppMirror(
      mirrorDir: temp.path,
      platform: OtzariaTargetPlatform.windows,
      releaseClient: OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
      ),
      installer: OtzariaInstaller(
        cacheDir: p.join(temp.path, 'installers'),
        appLocator: const OtzariaAppLocator(
          platform: OtzariaTargetPlatform.windows,
        ),
      ),
    );
  });

  tearDown(() async => temp.delete(recursive: true));

  test('legacy mirror cannot supply an update and its files survive', () async {
    await _writeMirror(temp, stable: _release(isPrerelease: false));
    final file = File(p.join(temp.path, 'latest-release.json'));
    final metadata =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    metadata.remove('source');
    await file.writeAsString(jsonEncode(metadata));
    final before = await file.readAsString();
    final installerFiles =
        Directory(p.join(temp.path, 'installers')).listSync();
    expect((await mirror.load()).isEmpty, isTrue);
    expect(await file.readAsString(), before);
    expect(
        installerFiles.whereType<File>().every((f) => f.existsSync()), isTrue);
  });

  group('OtzariaAppMirror.load', () {
    test('ריק כשאין מראה בכלל', () async {
      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('מחזירה את הגרסה וקובץ ההתקנה כשהמראה שלמה', () async {
      await _writeMirror(temp, stable: _release(isPrerelease: false));

      final loaded = (await mirror.load()).latest;

      expect(loaded, isNotNull);
      expect(loaded!.release.tagName, '0.9.96+736');
      expect(
        loaded.release.installerKind,
        OtzariaInstallerKind.windowsSetupExe,
      );
      expect(File(loaded.installerPath).existsSync(), isTrue);
    });

    test('null כשגודל קובץ ההתקנה לא תואם למטא־דאטה', () async {
      await _writeMirror(temp, stable: _release(size: 999));

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('null כשקובץ ההתקנה חסר לגמרי', () async {
      await _writeMirror(temp, stable: _release(), writeInstaller: false);

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('נתיב עם מפריד של הפלטפורמה האחרת נפתח בכל זאת', () async {
      final release = _release(isPrerelease: false);
      final installersDir = Directory(p.join(temp.path, 'installers'));
      await installersDir.create(recursive: true);
      await File(p.join(installersDir.path, release.installerAssetName))
          .writeAsString('abcd');

      for (final separator in ['/', r'\']) {
        final json = {
          'schemaVersion': 3,
          'source': 'github-latest',
          'latest': release.toJson()
            ..['installerPath'] =
                'installers$separator${release.installerAssetName}',
        };
        await File(p.join(temp.path, 'latest-release.json'))
            .writeAsString(_encodeLatestFixture(json));

        final loaded = (await mirror.load()).latest;
        expect(loaded, isNotNull, reason: 'מפריד: $separator');
        expect(File(loaded!.installerPath).existsSync(), isTrue);
      }
    });

    test('null כשהמטא־דאטה פגומה', () async {
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString('{ this is not json');

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('JSON תקין שאינו אובייקט נקרא כמראה ריקה', () async {
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString(_encodeLatestFixture([1, 2, 3]));

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('רשומה בלי installerPath (או ריק) נפסלת', () async {
      final release = _release(isPrerelease: false);
      for (final path in [null, '']) {
        final entry = await _writeInstaller(temp, release);
        if (path == null) {
          entry.remove('installerPath');
        } else {
          entry['installerPath'] = path;
        }
        await File(p.join(temp.path, 'latest-release.json')).writeAsString(
            _encodeLatestFixture({
          'schemaVersion': 3,
          'source': 'github-latest',
          'latest': entry
        }));

        expect((await mirror.load()).isEmpty, isTrue, reason: 'נתיב: $path');
      }
    });

    test('רשומת ערוץ שאינה אובייקט נפסלת', () async {
      await File(
        p.join(temp.path, 'latest-release.json'),
      ).writeAsString(_encodeLatestFixture({
        'schemaVersion': 3,
        'source': 'github-latest',
        'latest': 'לא רשומה'
      }));

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('פורמט ישן בלי קובץ התקנה נפסל', () async {
      final entry = await _writeInstaller(
        temp,
        _release(),
        writeInstaller: false,
      );
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString(_encodeLatestFixture(entry));

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('מראה של ווינדוס נקראת כריקה במק, ולא כהתקנה שאפשר להריץ', () async {
      await _writeMirror(temp, stable: _release(isPrerelease: false));

      final macMirror = OtzariaAppMirror(
        mirrorDir: temp.path,
        platform: OtzariaTargetPlatform.macos,
        releaseClient: OtzariaReleaseClient(
          platform: OtzariaTargetPlatform.macos,
        ),
        installer: OtzariaInstaller(
          cacheDir: p.join(temp.path, 'installers'),
          appLocator: const OtzariaAppLocator(
            platform: OtzariaTargetPlatform.macos,
          ),
        ),
      );

      expect((await macMirror.load()).isEmpty, isTrue);
    });
  });

  test('OtzariaRelease עובר round-trip דרך JSON', () {
    final original = _release();

    expect(OtzariaRelease.fromJson(original.toJson()), original);
  });

  group('OtzariaAppMirror.sync', () {
    const installerBytes = 'installer-bytes';

    Map<String, dynamic> releaseJson(
      String tag, {
      required bool prerelease,
      String body = '',
      String publishedAt = '2026-01-01T00:00:00Z',
      bool withMac = false,
    }) =>
        {
          'tag_name': tag,
          'name': 'Otzaria $tag',
          'prerelease': prerelease,
          'draft': false,
          'published_at': publishedAt,
          'body': body,
          'assets': [
            {
              'name': 'otzaria-$tag-windows.exe',
              'browser_download_url': 'https://example/installer-$tag.exe',
              'size': installerBytes.length,
            },
            if (withMac)
              {
                'name': 'otzaria-$tag-macos.zip',
                'browser_download_url': 'https://example/installer-$tag.zip',
                'size': installerBytes.length,
              },
          ],
        };

    http.Client mockReleases(List<Map<String, dynamic>> releases) => MockClient(
          (_) async => http.Response(
            _encodeLatestFixture(releases),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        );

    http.Client mockReleaseWithBody(String body) =>
        mockReleases([releaseJson('0.9.96', prerelease: false, body: body)]);

    http.Client mockInstallerDownload() =>
        MockClient((_) async => http.Response(installerBytes, 200));

    Future<OtzariaAppMirror> mirrorFor({
      required http.Client releasesHttpClient,
      required http.Client changelogHttpClient,
      required Directory tempDir,
      http.Client? installerHttpClient,
      OtzariaTargetPlatform platform = OtzariaTargetPlatform.windows,
    }) async {
      return OtzariaAppMirror(
        mirrorDir: tempDir.path,
        platform: platform,
        releaseClient: OtzariaReleaseClient(
          platform: platform,
          httpClient: releasesHttpClient,
        ),
        installer: OtzariaInstaller(
          cacheDir: p.join(tempDir.path, 'installers'),
          httpClient: installerHttpClient ?? mockInstallerDownload(),
          appLocator: OtzariaAppLocator(platform: platform),
        ),
        changelogClient: OtzariaChangelogClient(
          httpClient: changelogHttpClient,
        ),
      );
    }

    test(
      'מעדיפה את הפסקה מיומן השינויים המרוכז על פני תיאור ה-release',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-mirror-sync-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final mirror = await mirrorFor(
          releasesHttpClient: mockReleaseWithBody('תיאור גולמי מ-GitHub'),
          changelogHttpClient: MockClient(
            (_) async => http.Response(
              '* **0.9.96**\n  - פריט מיומן השינויים המרוכז\n',
              200,
              headers: const {'content-type': 'text/plain; charset=utf-8'},
            ),
          ),
          tempDir: tempDir,
        );

        final result = await mirror.sync();

        expect(
          result.latest!.release.releaseNotes,
          contains('יומן השינויים המרוכז'),
        );
        expect(
          result.latest!.release.releaseNotes,
          isNot(contains('תיאור גולמי')),
        );
      },
    );

    test(
      'נופלת חזרה לתיאור ה-release כשהגרסה לא מופיעה ביומן השינויים',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-mirror-sync-test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final mirror = await mirrorFor(
          releasesHttpClient: mockReleaseWithBody('תיאור גולמי מ-GitHub'),
          changelogHttpClient: MockClient(
            (_) async => http.Response(
              '* **0.1.0**\n  - גרסה אחרת בלבד\n',
              200,
              headers: const {'content-type': 'text/plain; charset=utf-8'},
            ),
          ),
          tempDir: tempDir,
        );

        final result = await mirror.sync();

        expect(result.latest!.release.releaseNotes, 'תיאור גולמי מ-GitHub');
      },
    );

    test('המטא־דאטה נכתבת עם מפריד POSIX ובמבנה installers/<tag>/', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-mirror-sync-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final mirror = await mirrorFor(
        releasesHttpClient: mockReleases([
          releaseJson('0.9.96', prerelease: false),
        ]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        tempDir: tempDir,
      );

      await mirror.sync();

      final raw = await File(p.join(tempDir.path, 'latest-release.json'))
          .readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final entry = json['latest'] as Map<String, dynamic>;

      expect(json['schemaVersion'], 3);
      expect(json['syncedAt'], isA<String>());
      expect(json.containsKey('prerelease'), isFalse);
      expect(
        entry['installerPath'],
        'installers/0.9.96/otzaria-0.9.96-windows.exe',
      );
      expect(raw, isNot(contains(r'\\')));
    });

    test('סנכרון חוזר לא מוריד שוב את מה שכבר בכונן', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-mirror-sync-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      var downloads = 0;
      final mirror = await mirrorFor(
        releasesHttpClient: mockReleases([
          releaseJson('0.9.96', prerelease: false),
        ]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        installerHttpClient: MockClient((_) async {
          downloads++;
          return http.Response(installerBytes, 200);
        }),
        tempDir: tempDir,
      );

      await mirror.sync();
      await mirror.sync();

      expect(downloads, 1);
    });

    test('אימות מראה ישן משתמש במתקין הקיים בלי להורידו שוב (#193)', () async {
      final release = _release(
        tagName: '0.9.96',
        isPrerelease: false,
        size: installerBytes.length,
      );
      final relative =
          'installers/${release.tagName}/${release.installerAssetName}';
      final installer = File(p.join(temp.path, p.joinAll(relative.split('/'))));
      await installer.parent.create(recursive: true);
      await installer.writeAsString(installerBytes);
      await installer.setLastModified(DateTime.utc(2026, 8, 1));
      final modified = await installer.lastModified();
      final channels = {
        'stable': release.toJson()..['installerPath'] = relative,
      };
      final metadata = File(p.join(temp.path, 'latest-release.json'));
      await metadata.writeAsString(jsonEncode({
        'schemaVersion': 2,
        ...channels,
        'platforms': {'windows': channels},
      }));
      var downloads = 0;
      final mirror = await mirrorFor(
        releasesHttpClient: mockReleases([
          releaseJson(release.tagName, prerelease: false),
        ]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        installerHttpClient: MockClient((_) async {
          downloads++;
          return http.Response(installerBytes, 200);
        }),
        tempDir: temp,
      );

      expect((await mirror.load()).isEmpty, isTrue);
      await mirror.sync();

      expect(downloads, 0);
      expect(await installer.readAsString(), installerBytes);
      expect(await installer.lastModified(), modified);
      expect((await mirror.load()).latest!.installerPath, installer.path);
      final updated = jsonDecode(await metadata.readAsString()) as Map;
      expect(updated['schemaVersion'], 3);
      expect(updated['source'], 'github-latest');
      expect(await mirror.lacksArm64Installers(), isFalse);
    });

    test('סנכרון מנקה קובצי התקנה של גרסאות שכבר לא רלוונטיות', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-mirror-sync-test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final stale = Directory(p.join(tempDir.path, 'installers', '0.0.1'));
      await stale.create(recursive: true);

      final mirror = await mirrorFor(
        releasesHttpClient: mockReleases([
          releaseJson('0.9.97', prerelease: true),
          releaseJson('0.9.90', prerelease: false),
        ]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        tempDir: tempDir,
      );

      await mirror.sync();

      final kept = Directory(
        p.join(tempDir.path, 'installers'),
      ).listSync().map((e) => p.basename(e.path)).toList()
        ..sort();
      expect(kept, ['0.9.90']);
      expect(stale.existsSync(), isFalse);
    });

    group('one drive synced from Windows and macOS', () {
      late Directory tempDir;
      late int downloads;

      final releases = [
        releaseJson(
          '0.9.97',
          prerelease: true,
          publishedAt: '2026-01-02T00:00:00Z',
          withMac: true,
        ),
        releaseJson(
          '0.9.96',
          prerelease: false,
          publishedAt: '2026-01-01T00:00:00Z',
          withMac: true,
        ),
      ];

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'otzaria-mirror-sync-test',
        );
        downloads = 0;
      });
      tearDown(() => tempDir.delete(recursive: true));

      Future<OtzariaAppMirror> on(OtzariaTargetPlatform platform) => mirrorFor(
            releasesHttpClient: mockReleases(releases),
            changelogHttpClient:
                MockClient((_) async => http.Response('', 404)),
            installerHttpClient: MockClient((_) async {
              downloads++;
              return http.Response(installerBytes, 200);
            }),
            tempDir: tempDir,
            platform: platform,
          );

      Future<void> expectBothUsable(
        OtzariaAppMirror windows,
        OtzariaAppMirror mac,
      ) async {
        for (final mirror in [windows, mac]) {
          final loaded = await mirror.load();
          expect(loaded.latest, isNotNull);
          for (final entry in loaded.all) {
            expect(File(entry.installerPath).existsSync(), isTrue);
          }
        }
      }

      test(
          'corrupt top-level metadata does not block sync or remove another platform',
          () async {
        final mac = await on(OtzariaTargetPlatform.macos);
        await mac.sync();
        final file = File(p.join(tempDir.path, 'latest-release.json'));
        final metadata =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        metadata['latest'] = <String, dynamic>{};
        await file.writeAsString(jsonEncode(metadata));
        final windows = await on(OtzariaTargetPlatform.windows);
        expect(await windows.otherPlatformTagNames(), {'0.9.96'});
        await windows.sync();
        await expectBothUsable(windows, mac);
        expect(downloads, 2);
      });

      test("each platform keeps the other one's installers", () async {
        final windows = await on(OtzariaTargetPlatform.windows);
        final mac = await on(OtzariaTargetPlatform.macos);

        await windows.sync();
        await mac.sync();
        await windows.sync();
        await mac.sync();

        expect(downloads, 2);
        await expectBothUsable(windows, mac);
        expect(await windows.otherPlatformTagNames(), {'0.9.96'});
        expect(await mac.otherPlatformTagNames(), {'0.9.96'});
      });

      test(
        'a drive written before per-platform metadata keeps its entries',
        () async {
          final windows = await on(OtzariaTargetPlatform.windows);
          await windows.sync();
          final metadata = File(p.join(tempDir.path, 'latest-release.json'));
          final legacy = jsonDecode(await metadata.readAsString())
              as Map<String, dynamic>
            ..remove('platforms');
          await metadata.writeAsString(_encodeLatestFixture(legacy));

          final mac = await on(OtzariaTargetPlatform.macos);
          await mac.sync();

          expect(downloads, 2);
          await expectBothUsable(windows, mac);
        },
      );
    });
  });
}

String _encodeLatestFixture(Object? value) {
  if (value is List &&
      value.isNotEmpty &&
      value.first is Map &&
      (value.first as Map).containsKey('tag_name')) {
    final candidates = value
        .whereType<Map>()
        .where((r) => r['prerelease'] != true && r['draft'] != true);
    value = candidates.isEmpty ? value.first : candidates.first;
  }
  return jsonEncode(value);
}
