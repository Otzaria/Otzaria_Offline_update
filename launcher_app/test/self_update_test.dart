// בדיקות לעדכון העצמי של הלאנצ'ר — `lib/src/self_update/`.
//
// אף בדיקה כאן לא נוגעת ברשת (הלקוח מקבל [MockClient]) ולא מפעילה תהליך
// אמיתי (`LauncherSelfInstaller` מקבל פונקציית הפעלה מוזרקת). ההחלפה עצמה
// **כן** רצה על קבצים אמיתיים בתיקייה זמנית: זה כל העניין בה, ודמה שלא נוגע
// בדיסק לא היה מגלה שהיא מוחקת משהו שאסור לגעת בו.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/self_update/launcher_install_layout.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/self_update/launcher_release_client.dart';
import 'package:launcher_app/src/self_update/launcher_self_installer.dart';
import 'package:launcher_app/src/self_update/launcher_self_updater.dart';
import 'package:launcher_app/src/self_update/launcher_update_mirror.dart';
import 'package:launcher_app/src/self_update/launcher_version.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

/// תג שתמיד חדש מהגרסה הרצה. חייב להיגזר ממנה: ה-CI מקדם את
/// [launcherVersion] בכל דחיפה ל-main, ותג קבוע היה הופך את הבדיקות שמצפות
/// ל"יש עדכון" לאדומות ביום שהגרסה תשיג אותו — בדיוק בג'וב שמפרסם.
final String _newerTag =
    'v${int.parse(LauncherVersion.normalize(launcherVersion).split('.').first) + 1}.0.0';

/// release כמו שהוא חוזר מ-GitHub, עם אסט אחד לווינדוס.
Map<String, dynamic> _releaseJson({
  String? tag,
  bool prerelease = false,
  bool draft = false,
  String assetName = 'עדכוני.אוצריא.exe',
  int size = 4,
}) =>
    {
      'tag_name': tag ?? _newerTag,
      'name': 'Otzaria Updates ${tag ?? _newerTag}',
      'prerelease': prerelease,
      'draft': draft,
      'published_at': '2026-08-01T10:00:00Z',
      'body': 'מה התחדש',
      'assets': [
        {
          'name': assetName,
          'browser_download_url': 'https://example/$assetName',
          'size': size,
        },
      ],
    };

LauncherRelease _release({String? tag, int size = 4}) =>
    _releaseFor(tag ?? _newerTag, size);

LauncherRelease _releaseFor(String tag, int size) => LauncherRelease(
      tagName: tag,
      name: 'Otzaria Updates $tag',
      assetName: 'launcher-$tag.exe',
      downloadUrl: 'https://example/launcher-$tag.exe',
      sizeBytes: size,
    );

void main() {
  group('LauncherVersion', () {
    test('מנרמל תג ובנייה — v מוביל ו-+build יורדים', () {
      expect(LauncherVersion.normalize('v1.2.3'), '1.2.3');
      expect(LauncherVersion.normalize('1.2.3+736'), '1.2.3');
      expect(LauncherVersion.normalize(' v0.1.0 '), '0.1.0');
    });

    test('משווה לפי מספרים, וחלק חסר נחשב אפס', () {
      expect(LauncherVersion.isNewer('v0.2.0', '0.1.0'), isTrue);
      expect(LauncherVersion.isNewer('0.1.10', '0.1.9'), isTrue);
      expect(LauncherVersion.isNewer('1.2', '1.2.0'), isFalse);
      expect(LauncherVersion.compare('1.2', '1.2.0'), 0);
    });

    test('גרסה זהה או ותיקה אינה "חדשה" — כדי לא להציע ירידת גרסה', () {
      expect(LauncherVersion.isNewer('v0.1.0', '0.1.0'), isFalse);
      expect(LauncherVersion.isNewer('v0.0.9', '0.1.0'), isFalse);
    });

    test('רק vX.Y (או vX.Y.Z הוותיק) נחשב תג של release', () {
      expect(LauncherVersion.isReleaseTag('v0.2'), isTrue);
      expect(LauncherVersion.isReleaseTag('v0.1.7'), isTrue);
      expect(LauncherVersion.isReleaseTag('0.1.7'), isTrue);
      expect(LauncherVersion.isReleaseTag('v0.1.7+90'), isTrue);
      expect(LauncherVersion.isReleaseTag('V1'), isFalse);
      expect(LauncherVersion.isReleaseTag('גירסת בדיקה'), isFalse);
    });

    test('סיומת -beta קודמת לאותה גרסה בלעדיה', () {
      expect(LauncherVersion.isNewer('1.0.0', '1.0.0-beta'), isTrue);
      expect(LauncherVersion.isNewer('1.0.0-beta', '1.0.0'), isFalse);
    });

    test('הקבוע שווה מספרית לגרסה שב-pubspec.yaml', () {
      // המקור היחיד לגרסה: משם נצרבת גם גרסת ה-payload של ה-stub
      // (windows_stub/build_stub.ps1), ואי-התאמה שוברת את זיהוי העדכון.
      // השוואה מספרית: ב-pubspec יושב `0.2.0` — pub דורש שלושה חלקים —
      // ואילו הקבוע הוא `0.2`.
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      final line = pubspec.firstWhere((l) => l.startsWith('version:'));
      final version = line.split(':')[1].trim().split('+').first;
      expect(LauncherVersion.compare(launcherVersion, version), 0);
    });
  });

  group('LauncherReleaseClient', () {
    Future<LauncherRelease?> fetch(
      List<Map<String, dynamic>> releases, {
      String os = 'windows',
    }) {
      final client = LauncherReleaseClient(
        operatingSystem: os,
        httpClient: MockClient((request) async {
          expect(request.headers['User-Agent'], isNotNull);
          return http.Response(
            jsonEncode(releases),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.dispose);
      return client.fetchLatestStable();
    }

    test('בוחר את היציב האחרון ומדלג על draft ועל pre-release', () async {
      final release = await fetch([
        _releaseJson(tag: 'v0.4.0', draft: true),
        _releaseJson(tag: 'v0.3.0', prerelease: true),
        _releaseJson(tag: 'v0.2.0'),
        _releaseJson(tag: 'v0.1.0'),
      ]);

      expect(release?.tagName, 'v0.2.0');
      expect(release?.version, '0.2.0');
      expect(release?.sizeBytes, 4);
    });

    test('נבחרת הגרסה הגבוהה, גם כשהיא לא הראשונה ברשימה', () async {
      // סדר הפרסום אינו סדר הגרסאות: release ותיק שנערך מחדש עולה לראש.
      final release = await fetch([
        _releaseJson(tag: 'v0.1.0'),
        _releaseJson(tag: 'v0.9.0'),
        _releaseJson(tag: 'v0.2.0'),
      ]);

      expect(release?.tagName, 'v0.9.0');
    });

    test('תג ידני שאינו vX.Y.Z נפסל — "V1" אינו גרסה 1', () async {
      // ⚠️ בריפו יש release ידני ותיק בשם `V1` עם `default.exe`. כל השוואה
      // מספרית הייתה רואה בו גרסה 1, כלומר חדשה לנצח מכל 0.x, ומתקינה
      // בניית בדיקה ותיקה על המשתמשים.
      final ignored = await fetch([
        _releaseJson(tag: 'V1', assetName: 'default.exe'),
      ]);
      expect(ignored, isNull);

      final release = await fetch([
        _releaseJson(tag: 'V1', assetName: 'default.exe'),
        _releaseJson(tag: 'v0.1.2'),
      ]);
      expect(release?.tagName, 'v0.1.2');
    });

    test('release בלי אסט לפלטפורמה מדולג, ולא מפיל את הבדיקה', () async {
      final release = await fetch([
        _releaseJson(tag: 'v0.3.0', assetName: 'launcher_app-macos.zip'),
        _releaseJson(tag: 'v0.2.0'),
      ]);

      expect(release?.tagName, 'v0.2.0');
    });

    test('ב-macOS נבחר ה-zip ולא ה-exe', () async {
      final release = await fetch(
        [
          _releaseJson(tag: 'v0.3.0', assetName: 'launcher_app-macos.zip'),
        ],
        os: 'macos',
      );

      expect(release?.assetName, 'launcher_app-macos.zip');
    });

    test('אין יציב בכלל — null, ולא שגיאה', () async {
      final release = await fetch([_releaseJson(prerelease: true)]);
      expect(release, isNull);
    });

    test('סטטוס שאינו 200 נזרק כ-LauncherUpdateException', () async {
      final client = LauncherReleaseClient(
        operatingSystem: 'windows',
        httpClient: MockClient((_) async => http.Response('nope', 403)),
      );
      addTearDown(client.dispose);

      expect(
        client.fetchLatestStable,
        throwsA(isA<LauncherUpdateException>()),
      );
    });
  });

  group('LauncherUpdateMirror', () {
    late Directory temp;
    late LauncherUpdateMirror mirror;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('launcher-mirror-test');
      mirror = LauncherUpdateMirror(
        mirrorDir: p.join(temp.path, 'mirror', 'launcher'),
        httpClient: MockClient((_) async => http.Response('abcd', 200)),
      );
    });

    tearDown(() async {
      mirror.dispose();
      await deleteTempDir(temp);
    });

    test('מראה ריקה — null, וזו תשובה תקינה ולא שגיאה', () async {
      expect(await mirror.load(), isNull);
    });

    test('sync מוריד, כותב מטא-דאטה, ו-load מחזירה את מה שהורד', () async {
      final synced = await mirror.sync(_release());

      expect(File(synced.filePath).existsSync(), isTrue);
      expect(await File(synced.filePath).readAsString(), 'abcd');

      final loaded = await mirror.load();
      expect(loaded?.release.tagName, _newerTag);
      expect(loaded?.filePath, synced.filePath);

      // הנתיב במטא-דאטה נשמר תמיד עם `/`, כדי שמראה מווינדוס תיפתח ב-macOS.
      final json = jsonDecode(
        await File(p.join(mirror.mirrorDir, 'latest-release.json'))
            .readAsString(),
      ) as Map<String, dynamic>;
      expect(json['filePath'], isNot(contains(r'\')));
    });

    test('קובץ בגודל שגוי (הורדה שנקטעה) נחשב "אין מראה"', () async {
      final synced = await mirror.sync(_release());
      await File(synced.filePath).writeAsString('ab');

      expect(await mirror.load(), isNull);
    });

    test('קובץ שנמחק נחשב "אין מראה"', () async {
      final synced = await mirror.sync(_release());
      await File(synced.filePath).delete();

      expect(await mirror.load(), isNull);
    });

    test('מטא-דאטה פגומה נחשבת "אין מראה"', () async {
      await Directory(mirror.mirrorDir).create(recursive: true);
      await File(p.join(mirror.mirrorDir, 'latest-release.json'))
          .writeAsString('{ not json');

      expect(await mirror.load(), isNull);
    });

    test('sync חדש מנקה את הגרסה הקודמת מהכונן', () async {
      final old = await mirror.sync(_release(tag: 'v0.2.0'));
      await mirror.sync(_release(tag: 'v0.3.0'));

      expect(File(old.filePath).existsSync(), isFalse);
      expect((await mirror.load())?.release.tagName, 'v0.3.0');
    });

    test('גודל שאינו תואם לתשובה נזרק, והקובץ החלקי נמחק', () async {
      final release = _release(size: 999);
      await expectLater(
        () => mirror.sync(release),
        throwsA(isA<LauncherUpdateException>()),
      );

      final expected = p.join(
        mirror.mirrorDir,
        'files',
        release.tagName,
        release.assetName,
      );
      expect(File(expected).existsSync(), isFalse);
      expect(await mirror.load(), isNull);
    });
  });

  group('LauncherInstallLayout', () {
    test('משתנה הסביבה של ה-stub הוא התשובה, כשהקובץ קיים', () async {
      final temp = await Directory.systemTemp.createTemp('launcher-layout');
      addTearDown(() => deleteTempDir(temp));
      final stub = File(p.join(temp.path, 'עדכוני אוצריא.exe'));
      await stub.writeAsString('stub');

      final layout = LauncherInstallLayout.resolve(
        isWindows: true,
        isMacOS: false,
        resolvedExecutable: p.join(temp.path, 'app-files', 'launcher_app.exe'),
        environment: {LauncherInstallLayout.stubPathEnvVar: stub.path},
      );

      expect(layout?.executablePath, stub.path);
      expect(layout?.executableDir, temp.path);
    });

    test('בלי המשתנה — ה-exe הבודד שליד app-files (stub מגרסה קודמת)',
        () async {
      final temp = await Directory.systemTemp.createTemp('launcher-layout');
      addTearDown(() => deleteTempDir(temp));
      await Directory(p.join(temp.path, 'app-files')).create();
      final stub = File(p.join(temp.path, 'משהו אחר.exe'));
      await stub.writeAsString('stub');

      final layout = LauncherInstallLayout.resolve(
        isWindows: true,
        isMacOS: false,
        resolvedExecutable: p.join(temp.path, 'app-files', 'launcher_app.exe'),
        environment: const {},
      );

      expect(layout?.executablePath, stub.path);
    });

    test('כמה exe — נבחר זה שבשם שהאריזה מייצרת', () async {
      final temp = await Directory.systemTemp.createTemp('launcher-layout');
      addTearDown(() => deleteTempDir(temp));
      await Directory(p.join(temp.path, 'app-files')).create();
      await File(p.join(temp.path, 'zzz.exe')).writeAsString('x');
      final ours = File(
        p.join(temp.path, LauncherInstallLayout.packagedExeName),
      );
      await ours.writeAsString('x');

      final layout = LauncherInstallLayout.resolve(
        isWindows: true,
        isMacOS: false,
        resolvedExecutable: p.join(temp.path, 'app-files', 'launcher_app.exe'),
        environment: const {},
      );

      expect(layout?.executablePath, ours.path);
    });

    test('הרצה שאינה מתוך app-files — null, ואין מה להחליף', () {
      final layout = LauncherInstallLayout.resolve(
        isWindows: true,
        isMacOS: false,
        resolvedExecutable: r'C:\src\out\launcher_app.exe',
        environment: const {},
      );

      expect(layout, isNull);
    });

    test('ב-macOS מוחלפת חבילת ה-.app כולה', () {
      final layout = LauncherInstallLayout.resolve(
        isWindows: false,
        isMacOS: true,
        resolvedExecutable:
            '/Volumes/KEY/Otzaria Launcher.app/Contents/MacOS/launcher_app',
        environment: const {},
      );

      expect(layout?.executablePath, '/Volumes/KEY/Otzaria Launcher.app');
      expect(layout?.executableDir, '/Volumes/KEY');
    });
  });

  group('LauncherSelfInstaller', () {
    late Directory temp;
    late File stub;
    late File downloaded;
    late Directory dataDir;
    late LauncherInstallLayout layout;
    var started = <String>[];
    var quits = 0;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('launcher-install');
      stub = File(p.join(temp.path, 'עדכוני אוצריא.exe'));
      await stub.writeAsString('גרסה ישנה');
      // הנתונים יושבים **בתוך** app-files, וזה בדיוק מה שאסור לגעת בו.
      dataDir = Directory(p.join(temp.path, 'app-files', 'OtzariaData'));
      await dataDir.create(recursive: true);
      await File(p.join(dataDir.path, 'launcher_settings.json'))
          .writeAsString('{"keep":true}');
      downloaded = File(p.join(dataDir.path, 'mirror', 'launcher', 'new.exe'));
      await downloaded.parent.create(recursive: true);
      await downloaded.writeAsString('גרסה חדשה');

      layout = LauncherInstallLayout(executablePath: stub.path);
      started = [];
      quits = 0;
    });

    tearDown(() => deleteTempDir(temp));

    LauncherSelfInstaller installer() => LauncherSelfInstaller(
          currentPid: 4242,
          startDetached: (executable, arguments) async {
            started = [executable, ...arguments];
          },
          quit: () => quits++,
        );

    test('מחליף את קובץ ההרצה, ומשאיר את OtzariaData כמו שהיא', () async {
      final restarted = await installer().apply(
        layout: layout,
        downloadedFilePath: downloaded.path,
      );

      expect(restarted, isTrue);
      expect(await stub.readAsString(), 'גרסה חדשה');
      // ההגדרות והמראה — שלא נגעו בהן בכלל.
      expect(
        await File(p.join(dataDir.path, 'launcher_settings.json'))
            .readAsString(),
        '{"keep":true}',
      );
      expect(downloaded.existsSync(), isTrue);
    }, skip: !Platform.isWindows);

    test('אין שאריות: לא הקובץ הזמני ולא הקודם', () async {
      await installer().apply(
        layout: layout,
        downloadedFilePath: downloaded.path,
      );

      expect(
        File(p.join(temp.path, LauncherSelfInstaller.stagedName)).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(temp.path, LauncherSelfInstaller.previousName))
            .existsSync(),
        isFalse,
      );
    }, skip: !Platform.isWindows);

    test('מפעיל את הקובץ החדש עם ה-pid שלנו, ואז מסיים', () async {
      await installer().apply(
        layout: layout,
        downloadedFilePath: downloaded.path,
      );

      expect(started.first, stub.path);
      // ה-stub החדש ממתין שהתהליך הזה ייסגר לפני שהוא מחלץ מחדש.
      expect(started.last, '${LauncherInstallLayout.afterUpdateFlag}=4242');
      expect(quits, 1);
    }, skip: !Platform.isWindows);

    test('שאריות מהחלפה שנקטעה נמחקות בבדיקה הבאה', () async {
      final leftover =
          File(p.join(temp.path, LauncherSelfInstaller.previousName));
      await leftover.writeAsString('שארית');

      await installer().cleanupLeftovers(layout);

      expect(leftover.existsSync(), isFalse);
    });
  });

  group('LauncherSelfUpdater', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('launcher-updater');
    });
    tearDown(() => deleteTempDir(temp));

    LauncherSelfUpdater updater({
      LauncherInstallLayout? layout,
      String body = 'abcd',
      LauncherSelfInstaller? installer,
    }) {
      // `Response.bytes` ולא `Response(...)`: השני מקודד latin1 כשאין
      // content-type, וה-JSON כאן מכיל עברית (שם האסט).
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response.bytes(
              utf8.encode(jsonEncode([_releaseJson()])), 200);
        }
        return http.Response.bytes(utf8.encode(body), 200);
      });
      final made = LauncherSelfUpdater(
        dataDir: temp.path,
        httpClient: client,
        releaseClient: LauncherReleaseClient(
          httpClient: client,
          operatingSystem: 'windows',
        ),
        layout: layout,
        installer: installer,
        resolveLayout: false,
      );
      addTearDown(made.dispose);
      return made;
    }

    test('בדיקה מקומית על תיקייה ריקה: אין עדכון, ואין זריקה', () async {
      final check = await updater().checkForUpdate();

      expect(check.updateAvailable, isFalse);
      expect(check.mirrored, isNull);
      expect(check.currentVersion, launcherVersion);
      // בלי נתיב לקובץ ההרצה אין מה להחליף, וה-UI מסתיר את הכפתור.
      expect(check.canInstall, isFalse);
    });

    test('אחרי הורדה הבדיקה המקומית מדווחת שיש מה להתקין', () async {
      final self = updater();
      await self.downloadToMirror();

      final check = await self.checkForUpdate();
      expect(check.mirroredVersion, LauncherVersion.normalize(_newerTag));
      expect(check.updateAvailable, isTrue);
    });

    test('התקנה בלי מראה נזרקת עם הודעה מנוסחת למשתמש', () async {
      final layout = LauncherInstallLayout(
        executablePath: p.join(temp.path, 'stub.exe'),
      );

      await expectLater(
        updater(layout: layout).applyUpdate,
        throwsA(isA<LauncherUpdateException>()),
      );
    });

    test('בלי נתיב קובץ הרצה — התקנה נזרקת ולא "מצליחה" בשקט', () async {
      await expectLater(
        updater().applyUpdate,
        throwsA(isA<LauncherUpdateException>()),
      );
    });

    group('LauncherUpdateController', () {
      setUp(() => AppLogger.init(temp.path));

      test('כשל התקנה משאיר את הכפתור — במחשב מנותק אין דרך אחרת לנסות שוב',
          () async {
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(
            layout: LauncherInstallLayout(
              executablePath: p.join(temp.path, 'stub.exe'),
            ),
            installer: _FailingInstaller(),
          ),
        );
        addTearDown(controller.dispose);

        await controller.download();
        expect(await controller.install(), isFalse);

        expect(controller.errorMessage, isNotNull);
        expect(controller.hasUpdateReady, isTrue);
        expect(controller.isInstalling, isFalse);
      });

      test('החלפה בלי הפעלה מחדש (macOS) אינה משאירה את המצב על "מתקין"',
          () async {
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(
            layout: LauncherInstallLayout(
              executablePath: p.join(temp.path, 'stub.exe'),
            ),
            installer: _NoRestartInstaller(),
          ),
        );
        addTearDown(controller.dispose);

        await controller.download();
        expect(controller.hasUpdateReady, isTrue);

        // `false` = החבילה הוחלפה אך התוכנה הזאת ממשיכה לרוץ. מצב "מתקין"
        // שנשאר היה מציג מחוון סובב לנצח.
        expect(await controller.install(), isFalse);
        expect(controller.isInstalling, isFalse);
        expect(controller.errorMessage, isNull);
      });
    });
  });
}

/// החלפה שנכשלה — exe נעול, תיקייה לקריאה בלבד.
class _FailingInstaller extends LauncherSelfInstaller {
  @override
  Future<bool> apply({
    required LauncherInstallLayout layout,
    required String downloadedFilePath,
  }) async =>
      throw const LauncherUpdateException('החלפה נכשלה');

  @override
  Future<void> cleanupLeftovers(LauncherInstallLayout layout) async {}
}

/// מדמה את מסלול ה-macOS: ההחלפה הצליחה, ואין הפעלה מחדש.
class _NoRestartInstaller extends LauncherSelfInstaller {
  @override
  Future<bool> apply({
    required LauncherInstallLayout layout,
    required String downloadedFilePath,
  }) async =>
      false;

  @override
  Future<void> cleanupLeftovers(LauncherInstallLayout layout) async {}
}
