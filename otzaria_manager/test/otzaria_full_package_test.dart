import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// חבילת ה-FULL: מה נשמר במראה, מתי היא נקראת ממנה, ומתי הלאנצ'ר ממליץ
/// עליה. ההורדה עצמה דורשת רשת ואינה נבדקת כאן — מה שנבדק הוא צד הקריאה
/// וההחלטה, שהם מה שרץ במחשב המנותק.

const _fullAssetName = 'otzaria-0.9.96-windows-full.exe';
const _fullContents = 'full-installer-bytes';

OtzariaRelease _stable({bool withFull = true}) => OtzariaRelease(
      tagName: '0.9.96+736',
      name: 'Otzaria 0.9.96',
      isPrerelease: false,
      isDraft: false,
      publishedAt: DateTime.utc(2026, 7, 28),
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria-0.9.96-windows.exe',
      installerDownloadUrl: 'https://example/otzaria-0.9.96-windows.exe',
      installerSizeBytes: 4,
      fullPackage: withFull
          ? const OtzariaFullPackage(
              assetName: _fullAssetName,
              downloadUrl: 'https://example/$_fullAssetName',
              sizeBytes: _fullContents.length,
              installerKind: OtzariaInstallerKind.windowsSetupExe,
            )
          : null,
    );

/// כותב מראה "ידנית" בפורמט הנוכחי, כמו ב-`otzaria_app_mirror_test`.
Future<void> _writeMirror(
  Directory dir, {
  required OtzariaRelease stable,
  bool writeFullFile = true,
  String fullContents = _fullContents,
}) async {
  final installersDir = Directory(p.join(dir.path, 'installers'));
  await installersDir.create(recursive: true);
  await File(p.join(installersDir.path, stable.installerAssetName))
      .writeAsString('abcd');

  final entry = stable.toJson()
    ..['installerPath'] = 'installers/${stable.installerAssetName}';

  if (stable.fullPackage != null) {
    if (writeFullFile) {
      await File(p.join(installersDir.path, _fullAssetName))
          .writeAsString(fullContents);
    }
    entry['fullInstallerPath'] = 'installers/$_fullAssetName';
  }

  await File(p.join(dir.path, 'latest-release.json')).writeAsString(
    jsonEncode({'schemaVersion': 2, 'stable': entry}),
  );
}

OtzariaAppMirror _mirrorAt(Directory dir) => OtzariaAppMirror(
      mirrorDir: dir.path,
      releaseClient: OtzariaReleaseClient(
        platform: OtzariaTargetPlatform.windows,
      ),
      installer: OtzariaInstaller(cacheDir: p.join(dir.path, 'installers')),
    );

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-full-test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('המראה', () {
    test('רשומה עם חבילת FULL שקובץ ההתקנה שלה שם — נקראת', () async {
      await _writeMirror(temp, stable: _stable());

      final loaded = await _mirrorAt(temp).load();
      expect(loaded.stable!.hasFullPackage, isTrue);
      expect(p.basename(loaded.stable!.fullInstallerPath!), _fullAssetName);
    });

    test('קובץ FULL חסר אינו פוסל את הרשומה — רק את ה-FULL', () async {
      await _writeMirror(temp, stable: _stable(), writeFullFile: false);

      final loaded = await _mirrorAt(temp).load();
      // המתקין הרגיל עדיין שם, ולכן יש מה להתקין.
      expect(loaded.stable, isNotNull);
      expect(loaded.stable!.hasFullPackage, isFalse);
    });

    test('קובץ FULL בגודל שגוי (הורדה שנקטעה) נפסל', () async {
      await _writeMirror(temp, stable: _stable(), fullContents: 'חלקי');

      final loaded = await _mirrorAt(temp).load();
      expect(loaded.stable, isNotNull);
      expect(loaded.stable!.hasFullPackage, isFalse);
    });

    test('מראה שנכתבה בגרסה קודמת (בלי השדה) נקראת כרגיל', () async {
      await _writeMirror(temp, stable: _stable(withFull: false));

      final loaded = await _mirrorAt(temp).load();
      expect(loaded.stable, isNotNull);
      expect(loaded.stable!.hasFullPackage, isFalse);
    });
  });

  group('ההמלצה', () {
    OtzariaUpdateCheckResult check({
      OtzariaInstallState? installed,
      bool mirroredFull = true,
    }) =>
        OtzariaUpdateCheckResult(
          currentState: installed,
          stableRelease: _stable(),
          mirroredFullPackage: mirroredFull ? _stable().fullPackage : null,
        );

    test('אין אוצריא ויש חבילה — ממליצים', () {
      expect(check().fullPackageRecommended, isTrue);
    });

    test('אוצריא מותקנת — לא ממליצים, גם כשהחבילה על הכונן', () {
      final installed = OtzariaInstallState(
        installedTagName: '0.9.96',
        installDir: r'C:\Otzaria',
        launchPath: r'C:\Otzaria\otzaria.exe',
      );
      expect(check(installed: installed).fullPackageRecommended, isFalse);
    });

    test('אין חבילה על הכונן — אין מה להמליץ עליו', () {
      expect(check(mirroredFull: false).fullPackageRecommended, isFalse);
    });
  });

  group('סריאליזציה', () {
    test('חבילת FULL שורדת הלוך ושוב דרך JSON', () {
      final restored = OtzariaRelease.fromJson(_stable().toJson());
      expect(restored.fullPackage, _stable().fullPackage);
    });

    test('רשומת FULL פגומה נקראת כ-null ולא מפילה את ה-release', () {
      final json = _stable().toJson()..['fullPackage'] = {'assetName': 5};
      expect(OtzariaRelease.fromJson(json).fullPackage, isNull);
    });
  });

  group('sync → load, המסלול המלא', () {
    const installerBytes = 'regular installer';

    /// לקוח מדומה שעונה כמו GitHub: רשימת ה-releases, ושני האסטים.
    MockClient client() => MockClient((request) async {
          final url = request.url.toString();
          if (url.contains('api.github.com')) {
            return http.Response(
              jsonEncode([
                {
                  'tag_name': '0.9.96+736',
                  'name': 'Otzaria 0.9.96',
                  'prerelease': false,
                  'draft': false,
                  'published_at': '2026-07-28T19:47:04Z',
                  'body': 'מה התחדש',
                  'assets': [
                    {
                      'name': 'otzaria-0.9.96-windows-full.exe',
                      'browser_download_url': 'https://example/full.exe',
                      'size': _fullContents.length,
                    },
                    {
                      'name': 'otzaria-0.9.96-windows.exe',
                      'browser_download_url': 'https://example/setup.exe',
                      'size': installerBytes.length,
                    },
                  ],
                }
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (url.contains('full.exe')) {
            return http.Response(_fullContents, 200);
          }
          if (url.contains('setup.exe')) {
            return http.Response(installerBytes, 200);
          }
          // יומן השינויים — נכשל בשקט, כמו בלי רשת.
          return http.Response('', 404);
        });

    OtzariaAppMirror mirror(http.Client c) => OtzariaAppMirror(
          mirrorDir: temp.path,
          releaseClient: OtzariaReleaseClient(
            httpClient: c,
            platform: OtzariaTargetPlatform.windows,
          ),
          installer: OtzariaInstaller(
            cacheDir: p.join(temp.path, 'installers'),
            httpClient: c,
          ),
          changelogClient: OtzariaChangelogClient(httpClient: c),
        );

    test('חבילה שהתבקשה יורדת, ו-load מוצאת אותה אחריה', () async {
      final c = client();
      await mirror(c).sync(includeFullPackage: true);

      // זה מה שנשבר בפועל: הקובץ ירד במלואו, אבל הנתיב שלו לא נרשם
      // במטא־דאטה — ולכן המראה לא ידעה עליו, הכרטיס לא הופיע, ו"יש מה
      // להוריד" נשאר דלוק לנצח.
      final loaded = await mirror(c).load();
      expect(loaded.stable!.hasFullPackage, isTrue);
      expect(
        File(loaded.stable!.fullInstallerPath!).lengthSync(),
        _fullContents.length,
      );
      expect(loaded.stable!.fullPackageKnown, isTrue);
    });

    test('בלי בקשה — החבילה אינה יורדת, אבל ידוע שהיא קיימת', () async {
      final c = client();
      await mirror(c).sync();

      final loaded = await mirror(c).load();
      expect(loaded.stable!.hasFullPackage, isFalse);
      // המטא־דאטה נכתבה בפורמט החדש, ולכן "אין חבילה" הוא תשובה ודאית.
      expect(loaded.stable!.fullPackageKnown, isTrue);
      expect(loaded.stable!.release.fullPackage, isNotNull);
    });

    test('כיבוי אחרי הורדה מוחק את הקובץ מהכונן', () async {
      final c = client();
      await mirror(c).sync(includeFullPackage: true);
      final path = (await mirror(c).load()).stable!.fullInstallerPath!;
      expect(File(path).existsSync(), isTrue);

      await mirror(c).sync();

      expect(File(path).existsSync(), isFalse);
      expect((await mirror(c).load()).stable!.hasFullPackage, isFalse);
    });
  });
}
