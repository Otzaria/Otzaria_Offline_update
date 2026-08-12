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
}) =>
    OtzariaRelease(
      tagName: tagName,
      name: 'Otzaria $tagName',
      isPrerelease: isPrerelease,
      isDraft: false,
      publishedAt: DateTime.utc(2026, 1, 1),
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria-$tagName-windows.exe',
      installerDownloadUrl: 'https://example/otzaria-$tagName-windows.exe',
      installerSizeBytes: size,
    );

/// רשומת ערוץ אחת בקובץ המטא־דאטה, אחרי כתיבת קובץ ההתקנה שלה.
Future<Map<String, dynamic>> _writeInstaller(
  Directory dir,
  OtzariaRelease release, {
  String installerContents = 'abcd',
  bool writeInstaller = true,
}) async {
  final installersDir = Directory(p.join(dir.path, 'installers'));
  await installersDir.create(recursive: true);
  final installer =
      File(p.join(installersDir.path, release.installerAssetName));
  if (writeInstaller) await installer.writeAsString(installerContents);

  return release.toJson()
    ..['installerPath'] = p.relative(installer.path, from: dir.path);
}

/// כותב מראה "ידנית" בפורמט הנוכחי — sync() האמיתי דורש רשת, ומה שנבדק
/// כאן הוא צד הקריאה: מה load() מקבלת ומה היא פוסלת.
Future<void> _writeMirror(
  Directory dir, {
  OtzariaRelease? stable,
  OtzariaRelease? prerelease,
  String installerContents = 'abcd',
  bool writeInstaller = true,
}) async {
  final json = <String, dynamic>{
    'schemaVersion': 2,
    if (stable != null)
      'stable': await _writeInstaller(dir, stable,
          installerContents: installerContents, writeInstaller: writeInstaller),
    if (prerelease != null)
      'prerelease': await _writeInstaller(dir, prerelease,
          installerContents: installerContents, writeInstaller: writeInstaller),
  };
  await File(p.join(dir.path, 'latest-release.json'))
      .writeAsString(jsonEncode(json));
}

void main() {
  late Directory temp;
  late OtzariaAppMirror mirror;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-mirror-test');
    // sync() לא נקרא בבדיקות האלה, ולכן הלקוח וה-installer לא בשימוש.
    mirror = OtzariaAppMirror(
      mirrorDir: temp.path,
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

  group('OtzariaAppMirror.load', () {
    test('ריק כשאין מראה בכלל', () async {
      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('מחזירה את הגרסה וקובץ ההתקנה כשהמראה שלמה', () async {
      await _writeMirror(temp, stable: _release(isPrerelease: false));

      final loaded = (await mirror.load()).stable;

      expect(loaded, isNotNull);
      expect(loaded!.release.tagName, '0.9.96+736');
      expect(
          loaded.release.installerKind, OtzariaInstallerKind.windowsSetupExe);
      expect(File(loaded.installerPath).existsSync(), isTrue);
    });

    test('מחזירה את שני הערוצים כששניהם במראה', () async {
      await _writeMirror(
        temp,
        stable: _release(tagName: '0.9.90', isPrerelease: false),
        prerelease: _release(tagName: '0.9.97'),
      );

      final loaded = await mirror.load();

      expect(loaded.hasChoice, isTrue);
      expect(loaded.stable!.release.tagName, '0.9.90');
      expect(loaded.prerelease!.release.tagName, '0.9.97');
      expect(loaded.select(preferPrerelease: true)!.release.tagName, '0.9.97');
      expect(loaded.select(preferPrerelease: false)!.release.tagName, '0.9.90');
    });

    // הורדה שנקטעה משאירה קובץ בגודל שגוי. להתקין אותו = להתקין זבל.
    test('null כשגודל קובץ ההתקנה לא תואם למטא־דאטה', () async {
      await _writeMirror(temp, stable: _release(size: 999));

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('null כשקובץ ההתקנה חסר לגמרי', () async {
      await _writeMirror(temp, stable: _release(), writeInstaller: false);

      expect((await mirror.load()).isEmpty, isTrue);
    });

    // ערוץ פגום לא אמור לפסול את השני — עדיין יש מה להתקין.
    test('ערוץ אחד פגום משאיר את השני שמיש', () async {
      final stable = _release(tagName: '0.9.90', isPrerelease: false);
      final broken = _release(tagName: '0.9.97', size: 999);
      await File(p.join(temp.path, 'latest-release.json')).writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'stable': await _writeInstaller(temp, stable),
          'prerelease': await _writeInstaller(temp, broken),
        }),
      );

      final loaded = await mirror.load();

      expect(loaded.stable!.release.tagName, '0.9.90');
      expect(loaded.prerelease, isNull);
    });

    // מראה שנבנתה בווינדוס נקראת ב-macOS ולהיפך — הנתיב בקטלוג נשמר עם `/`,
    // אבל גם `\` היסטורי חייב להמשיך להיפתח.
    test('נתיב עם מפריד של הפלטפורמה האחרת נפתח בכל זאת', () async {
      final release = _release(isPrerelease: false);
      final installersDir = Directory(p.join(temp.path, 'installers'));
      await installersDir.create(recursive: true);
      await File(p.join(installersDir.path, release.installerAssetName))
          .writeAsString('abcd');

      for (final separator in ['/', r'\']) {
        final json = {
          'schemaVersion': 2,
          'stable': release.toJson()
            ..['installerPath'] =
                'installers$separator${release.installerAssetName}',
        };
        await File(p.join(temp.path, 'latest-release.json'))
            .writeAsString(jsonEncode(json));

        final loaded = (await mirror.load()).stable;
        expect(loaded, isNotNull, reason: 'מפריד: $separator');
        expect(File(loaded!.installerPath).existsSync(), isTrue);
      }
    });

    // כונן שנוצר לפני מעבר לשני ערוצים מחזיק רשומה בודדת בשורש הקובץ.
    test('פורמט ישן (רשומה בודדת) עדיין נקרא ומשויך לערוץ לפי הדגל', () async {
      final release = _release();
      final entry = await _writeInstaller(temp, release);
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString(jsonEncode(entry));

      final loaded = await mirror.load();

      expect(loaded.stable, isNull);
      expect(loaded.prerelease!.release.tagName, '0.9.96+736');
    });

    test('null כשהמטא־דאטה פגומה', () async {
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString('{ this is not json');

      expect((await mirror.load()).isEmpty, isTrue);
    });

    test('JSON תקין שאינו אובייקט נקרא כמראה ריקה', () async {
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString(jsonEncode([1, 2, 3]));

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
        await File(p.join(temp.path, 'latest-release.json'))
            .writeAsString(jsonEncode({'schemaVersion': 2, 'stable': entry}));

        expect((await mirror.load()).isEmpty, isTrue, reason: 'נתיב: $path');
      }
    });

    test('רשומת ערוץ שאינה אובייקט נפסלת', () async {
      await File(p.join(temp.path, 'latest-release.json')).writeAsString(
        jsonEncode({'schemaVersion': 2, 'stable': 'לא רשומה'}),
      );

      expect((await mirror.load()).isEmpty, isTrue);
    });

    // פורמט ישן שקובץ ההתקנה שלו נעלם — בדיוק כמו רשומה חדשה חסרה.
    test('פורמט ישן בלי קובץ התקנה נפסל', () async {
      final entry =
          await _writeInstaller(temp, _release(), writeInstaller: false);
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString(jsonEncode(entry));

      expect((await mirror.load()).isEmpty, isTrue);
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
    }) =>
        {
          'tag_name': tag,
          'name': 'Otzaria $tag',
          'prerelease': prerelease,
          'draft': false,
          'published_at': '2026-01-01T00:00:00Z',
          'body': body,
          'assets': [
            {
              'name': 'otzaria-$tag-windows.exe',
              'browser_download_url': 'https://example/installer-$tag.exe',
              'size': installerBytes.length,
            },
          ],
        };

    http.Client mockReleases(List<Map<String, dynamic>> releases) =>
        MockClient((_) async => http.Response(
              jsonEncode(releases),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8'
              },
            ));

    http.Client mockReleaseWithBody(String body) =>
        mockReleases([releaseJson('0.9.96', prerelease: false, body: body)]);

    http.Client mockInstallerDownload() =>
        MockClient((_) async => http.Response(installerBytes, 200));

    Future<OtzariaAppMirror> mirrorFor({
      required http.Client releasesHttpClient,
      required http.Client changelogHttpClient,
      required Directory tempDir,
      http.Client? installerHttpClient,
    }) async {
      return OtzariaAppMirror(
        mirrorDir: tempDir.path,
        releaseClient: OtzariaReleaseClient(
          platform: OtzariaTargetPlatform.windows,
          httpClient: releasesHttpClient,
        ),
        installer: OtzariaInstaller(
          cacheDir: p.join(tempDir.path, 'installers'),
          httpClient: installerHttpClient ?? mockInstallerDownload(),
          appLocator: const OtzariaAppLocator(
            platform: OtzariaTargetPlatform.windows,
          ),
        ),
        changelogClient:
            OtzariaChangelogClient(httpClient: changelogHttpClient),
      );
    }

    test('מעדיפה את הפסקה מיומן השינויים המרוכז על פני תיאור ה-release',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
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

      expect(result.stable!.release.releaseNotes,
          contains('יומן השינויים המרוכז'));
      expect(
          result.stable!.release.releaseNotes, isNot(contains('תיאור גולמי')));
    });

    test('נופלת חזרה לתיאור ה-release כשהגרסה לא מופיעה ביומן השינויים',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
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

      expect(result.stable!.release.releaseNotes, 'תיאור גולמי מ-GitHub');
    });

    // הלב של הבקשה: הורדה אחת מביאה את שתי הגרסאות, ושתיהן נשמרות בכונן
    // כך שאפשר לבחור ביניהן במחשב המנותק.
    test('מורידה גם את היציבה וגם את ה-pre-release החדש ממנה', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
      addTearDown(() => tempDir.delete(recursive: true));

      final mirror = await mirrorFor(
        releasesHttpClient: mockReleases([
          releaseJson('0.9.97', prerelease: true),
          releaseJson('0.9.90', prerelease: false),
        ]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        tempDir: tempDir,
      );

      final downloaded = await mirror.sync();
      final channels = <OtzariaReleaseChannel>[];
      await mirror.sync(onChannelStart: channels.add);

      expect(downloaded.hasChoice, isTrue);
      expect(downloaded.stable!.release.tagName, '0.9.90');
      expect(downloaded.prerelease!.release.tagName, '0.9.97');
      // היציבה קודם — כישלון ב-pre-release לא משאיר את הכונן בלי כלום.
      expect(channels, [
        OtzariaReleaseChannel.stable,
        OtzariaReleaseChannel.prerelease,
      ]);

      // המטא־דאטה שנכתבה נקראת חזרה כשני ערוצים, עם שני קובצי התקנה.
      final reloaded = await mirror.load();
      expect(reloaded.hasChoice, isTrue);
      expect(File(reloaded.stable!.installerPath).existsSync(), isTrue);
      expect(File(reloaded.prerelease!.installerPath).existsSync(), isTrue);
    });

    // מראה שנבנית בווינדוס חייבת להיפתח ב-macOS: הנתיב במטא־דאטה נכתב
    // תמיד עם `/`, גם כש-p.relative מחזיר כאן `\`.
    test('המטא־דאטה נכתבת עם מפריד POSIX ובמבנה installers/<tag>/', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
      addTearDown(() => tempDir.delete(recursive: true));

      final mirror = await mirrorFor(
        releasesHttpClient:
            mockReleases([releaseJson('0.9.96', prerelease: false)]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        tempDir: tempDir,
      );

      await mirror.sync();

      final raw = await File(p.join(tempDir.path, 'latest-release.json'))
          .readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final entry = json['stable'] as Map<String, dynamic>;

      expect(json['schemaVersion'], 2);
      expect(json['syncedAt'], isA<String>());
      expect(json.containsKey('prerelease'), isFalse);
      expect(entry['installerPath'],
          'installers/0.9.96/otzaria-0.9.96-windows.exe');
      expect(raw, isNot(contains(r'\\')));
    });

    test('סנכרון חוזר לא מוריד שוב את מה שכבר בכונן', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
      addTearDown(() => tempDir.delete(recursive: true));

      var downloads = 0;
      final mirror = await mirrorFor(
        releasesHttpClient:
            mockReleases([releaseJson('0.9.96', prerelease: false)]),
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

    // קובץ התקנה של גרסה שכבר אינה במטא־דאטה סתם תופס מקום על הכונן הנייד.
    test('סנכרון מנקה קובצי התקנה של גרסאות שכבר לא רלוונטיות', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
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

      final kept = Directory(p.join(tempDir.path, 'installers'))
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();
      expect(kept, ['0.9.90', '0.9.97']);
      expect(stale.existsSync(), isFalse);
    });

    // אין יציב בעמוד הראשון — אז ה-pre-release הוא הגרסה היחידה, והתווית
    // אומרת את זה במפורש.
    test('בלי יציב, רק ה-pre-release יורד ומתויג ככזה', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
      addTearDown(() => tempDir.delete(recursive: true));

      final mirror = await mirrorFor(
        releasesHttpClient: mockReleases([
          releaseJson('0.9.97', prerelease: true),
          releaseJson('0.9.96', prerelease: true),
        ]),
        changelogHttpClient: MockClient((_) async => http.Response('', 404)),
        tempDir: tempDir,
      );

      final channels = <OtzariaReleaseChannel>[];
      final result = await mirror.sync(onChannelStart: channels.add);

      expect(channels, [OtzariaReleaseChannel.prerelease]);
      expect(result.stable, isNull);
      expect(result.hasChoice, isFalse);

      final reloaded = await mirror.load();
      expect(
          reloaded.select(preferPrerelease: false)!.release.tagName, '0.9.97');
      expect(reloaded.selectedChannel(preferPrerelease: false),
          OtzariaReleaseChannel.prerelease);
    });
  });
}
