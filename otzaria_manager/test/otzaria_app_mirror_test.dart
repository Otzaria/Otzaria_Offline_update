import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

OtzariaRelease _release({int size = 4}) => OtzariaRelease(
      tagName: '0.9.96+736',
      name: 'Otzaria 0.9.96',
      isPrerelease: true,
      isDraft: false,
      publishedAt: DateTime.utc(2026, 1, 1),
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria-0.9.96-windows.exe',
      installerDownloadUrl: 'https://example/otzaria-0.9.96-windows.exe',
      installerSizeBytes: size,
    );

/// כותב מראה "ידנית" — sync() האמיתי דורש רשת, ומה שנבדק כאן הוא צד
/// הקריאה: מה load() מקבלת ומה היא פוסלת.
Future<void> _writeMirror(
  Directory dir, {
  required OtzariaRelease release,
  String installerContents = 'abcd',
  bool writeInstaller = true,
}) async {
  final installersDir = Directory(p.join(dir.path, 'installers'));
  await installersDir.create(recursive: true);
  final installer =
      File(p.join(installersDir.path, release.installerAssetName));
  if (writeInstaller) await installer.writeAsString(installerContents);

  final json = release.toJson()
    ..['installerPath'] = p.relative(installer.path, from: dir.path);
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
        defaultInstallDir: p.join(temp.path, 'install'),
        cacheDir: p.join(temp.path, 'installers'),
        appLocator: const OtzariaAppLocator(
          platform: OtzariaTargetPlatform.windows,
        ),
      ),
    );
  });

  tearDown(() async => temp.delete(recursive: true));

  group('OtzariaAppMirror.load', () {
    test('null כשאין מראה בכלל', () async {
      expect(await mirror.load(), isNull);
    });

    test('מחזירה את הגרסה וקובץ ההתקנה כשהמראה שלמה', () async {
      await _writeMirror(temp, release: _release());

      final loaded = await mirror.load();

      expect(loaded, isNotNull);
      expect(loaded!.release.tagName, '0.9.96+736');
      expect(
          loaded.release.installerKind, OtzariaInstallerKind.windowsSetupExe);
      expect(File(loaded.installerPath).existsSync(), isTrue);
    });

    // הורדה שנקטעה משאירה קובץ בגודל שגוי. להתקין אותו = להתקין זבל.
    test('null כשגודל קובץ ההתקנה לא תואם למטא־דאטה', () async {
      await _writeMirror(temp, release: _release(size: 999));

      expect(await mirror.load(), isNull);
    });

    test('null כשקובץ ההתקנה חסר לגמרי', () async {
      await _writeMirror(temp, release: _release(), writeInstaller: false);

      expect(await mirror.load(), isNull);
    });

    // מראה שנבנתה בווינדוס נקראת ב-macOS ולהיפך — הנתיב בקטלוג נשמר עם `/`,
    // אבל גם `\` היסטורי חייב להמשיך להיפתח.
    test('נתיב עם מפריד של הפלטפורמה האחרת נפתח בכל זאת', () async {
      final release = _release();
      final installersDir = Directory(p.join(temp.path, 'installers'));
      await installersDir.create(recursive: true);
      await File(p.join(installersDir.path, release.installerAssetName))
          .writeAsString('abcd');

      for (final separator in ['/', r'\']) {
        final json = release.toJson()
          ..['installerPath'] =
              'installers$separator${release.installerAssetName}';
        await File(p.join(temp.path, 'latest-release.json'))
            .writeAsString(jsonEncode(json));

        final loaded = await mirror.load();
        expect(loaded, isNotNull, reason: 'מפריד: $separator');
        expect(File(loaded!.installerPath).existsSync(), isTrue);
      }
    });

    test('null כשהמטא־דאטה פגומה', () async {
      await File(p.join(temp.path, 'latest-release.json'))
          .writeAsString('{ this is not json');

      expect(await mirror.load(), isNull);
    });
  });

  test('OtzariaRelease עובר round-trip דרך JSON', () {
    final original = _release();

    expect(OtzariaRelease.fromJson(original.toJson()), original);
  });

  group('OtzariaAppMirror.sync', () {
    const installerBytes = 'installer-bytes';

    http.Client _mockReleaseWithBody(String body) => MockClient((_) async {
          return http.Response(
            jsonEncode([
              {
                'tag_name': '0.9.96',
                'name': 'Otzaria 0.9.96',
                'prerelease': false,
                'draft': false,
                'published_at': '2026-01-01T00:00:00Z',
                'body': body,
                'assets': [
                  {
                    'name': 'otzaria-0.9.96-windows.exe',
                    'browser_download_url': 'https://example/installer.exe',
                    'size': installerBytes.length,
                  },
                ],
              },
            ]),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        });

    http.Client _mockInstallerDownload() =>
        MockClient((_) async => http.Response(installerBytes, 200));

    Future<OtzariaAppMirror> _mirrorFor({
      required String releaseBody,
      required http.Client changelogHttpClient,
      required Directory tempDir,
    }) async {
      return OtzariaAppMirror(
        mirrorDir: tempDir.path,
        releaseClient: OtzariaReleaseClient(
          platform: OtzariaTargetPlatform.windows,
          httpClient: _mockReleaseWithBody(releaseBody),
        ),
        installer: OtzariaInstaller(
          defaultInstallDir: p.join(tempDir.path, 'install'),
          cacheDir: p.join(tempDir.path, 'installers'),
          httpClient: _mockInstallerDownload(),
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

      final mirror = await _mirrorFor(
        releaseBody: 'תיאור גולמי מ-GitHub',
        changelogHttpClient: MockClient(
          (_) async => http.Response(
            '* **0.9.96**\n  - פריט מיומן השינויים המרוכז\n',
            200,
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          ),
        ),
        tempDir: tempDir,
      );

      final result = await mirror.sync(allowPrerelease: false);

      expect(result.release.releaseNotes, contains('יומן השינויים המרוכז'));
      expect(result.release.releaseNotes, isNot(contains('תיאור גולמי')));
    });

    test('נופלת חזרה לתיאור ה-release כשהגרסה לא מופיעה ביומן השינויים',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('otzaria-mirror-sync-test');
      addTearDown(() => tempDir.delete(recursive: true));

      final mirror = await _mirrorFor(
        releaseBody: 'תיאור גולמי מ-GitHub',
        changelogHttpClient: MockClient(
          (_) async => http.Response(
            '* **0.1.0**\n  - גרסה אחרת בלבד\n',
            200,
            headers: const {'content-type': 'text/plain; charset=utf-8'},
          ),
        ),
        tempDir: tempDir,
      );

      final result = await mirror.sync(allowPrerelease: false);

      expect(result.release.releaseNotes, 'תיאור גולמי מ-GitHub');
    });
  });
}
