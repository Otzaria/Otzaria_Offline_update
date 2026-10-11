// בדיקות לעדכון העצמי של הלאנצ'ר — `lib/src/self_update/`.
//
// אף בדיקה כאן לא נוגעת ברשת (הלקוח מקבל [MockClient]) ולא מפעילה תהליך
// אמיתי (`LauncherSelfInstaller` מקבל פונקציית הפעלה מוזרקת). ההחלפה עצמה
// **כן** רצה על קבצים אמיתיים בתיקייה זמנית: זה כל העניין בה, ודמה שלא נוגע
// בדיסק לא היה מגלה שהיא מוחקת משהו שאסור לגעת בו.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/self_update/launcher_changelog.dart';
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
  String? digest,
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
          if (digest != null) 'digest': digest,
        },
      ],
    };

LauncherRelease _release({String? tag, int size = 4, String? sha256}) =>
    _releaseFor(tag ?? _newerTag, size, sha256);

LauncherRelease _releaseFor(String tag, int size, [String? sha256]) =>
    LauncherRelease(
      tagName: tag,
      name: 'Otzaria Updates $tag',
      assetName: 'launcher-$tag.exe',
      downloadUrl: 'https://example/launcher-$tag.exe',
      sizeBytes: size,
      sha256: sha256,
    );

final String _abcdSha256 = sha256.convert(utf8.encode('abcd')).toString();

String _tagAfterNewer() =>
    'v${int.parse(LauncherVersion.normalize(launcherVersion).split('.').first) + 2}.0.0';

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

    test('הגרסה המוצגת מורידה את ה-.0 שבסוף התג', () {
      // התג נשאר בן שלושה חלקים כדי שלאנצ'רים ותיקים יזהו אותו, אבל למשתמש
      // מוצע "0.2" — אותו מספר שהתוכנה מדווחת על עצמה.
      expect(_releaseFor('v0.2.0', 1).version, '0.2');
      expect(_releaseFor('v0.1.15', 1).version, '0.1.15');
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
      expect(release?.version, '0.2');
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

    test('ה-digest של האסט נשמר כ-sha256 ב-hex קטן', () async {
      final withDigest = await fetch([
        _releaseJson(tag: 'v0.2.0', digest: 'sha256:ABCDEF'),
      ]);
      expect(withDigest?.sha256, 'abcdef');
      expect(
        LauncherRelease.fromJson(withDigest!.toJson()).sha256,
        'abcdef',
      );

      final withoutDigest = await fetch([_releaseJson(tag: 'v0.2.0')]);
      expect(withoutDigest?.sha256, isNull);
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

    test('יומן השינויים נשלף מהתג, בנתיב הנכס, ומפוענח כ-UTF-8', () async {
      late Uri requested;
      final client = LauncherReleaseClient(
        operatingSystem: 'windows',
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response.bytes(utf8.encode('* **1.0**\n  - חדש'), 200);
        }),
      );
      addTearDown(client.dispose);

      expect(await client.fetchChangelog('v1.0.0'), contains('חדש'));
      expect(requested.host, 'raw.githubusercontent.com');
      expect(
        requested.pathSegments,
        containsAllInOrder(
            ['refs', 'tags', 'v1.0.0', 'launcher_app', 'assets']),
      );
      expect(requested.pathSegments.last, 'יומן שינויים.md');
    });

    test('תג בלי יומן (404) — null, ולא שגיאה', () async {
      final client = LauncherReleaseClient(
        operatingSystem: 'windows',
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(client.dispose);

      expect(await client.fetchChangelog('v0.5.0'), isNull);
    });
  });

  group('changelogBetweenVersions', () {
    const changelog = '''
  - עוד לא יצא

* **0.24**
  - חדש

* **0.23**
  - ביניים

* **0.22**
  - ישן
''';

    test('רק הגרסאות שאחרי הנוכחית ועד החדשה, עם הכותרות', () {
      final result = changelogBetweenVersions(
        changelog: changelog,
        currentVersion: '0.22',
        latestVersion: 'v0.24.0',
      )!;

      expect(result, startsWith('* **0.24**'));
      expect(result, contains('  - ביניים'));
      expect(result, isNot(contains('ישן')));
      // פריטים בלי כותרת עוד לא יצאו בשום גרסה.
      expect(result, isNot(contains('עוד לא יצא')));
    });

    test('גרסה שאינה חדשה, או אין ביניהן כלום — null', () {
      expect(
        changelogBetweenVersions(
          changelog: changelog,
          currentVersion: '0.24',
          latestVersion: '0.24',
        ),
        isNull,
      );
      expect(
        changelogBetweenVersions(
          changelog: changelog,
          currentVersion: '0.24',
          latestVersion: '0.25',
        ),
        isNull,
      );
    });

    test('היומן הארוז: יש כותרות גרסה, מהחדשה לישנה, והנכס מוצהר', () {
      final text = File(launcherChangelogAsset).readAsStringSync();
      final versions = [
        for (final line in text.split(RegExp(r'\r?\n')))
          if (changelogHeadingVersion(line) case final version?) version,
      ];

      expect(versions, isNotEmpty);
      // סדר הפוך היה חותך בדיאלוג את הגרסאות הלא נכונות.
      for (var i = 1; i < versions.length; i++) {
        expect(LauncherVersion.compare(versions[i - 1], versions[i]),
            greaterThan(0));
      }
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('- $launcherChangelogAsset'));
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
        // מפורש: הנכסים כאן הם `.exe`, ו-`load()` פוסלת נכס של פלטפורמה
        // אחרת — ראו הבדיקה האחרונה בקבוצה.
        operatingSystem: 'windows',
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

    test('יומן השינויים נוסע במטא-דאטה — המחשב המנותק קורא אותו בלי רשת',
        () async {
      await mirror.sync(_release().withChangelog('* **1.0**\n  - חדש'));

      final loaded = await mirror.load();
      expect(loaded?.release.changelog, contains('חדש'));
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

    // הכונן נוסע בין מחשבים: מי שהוריד בווינדוס נושא `.exe`, ומק שקורא
    // אותו היה מוסר אותו ל-`ditto` ונכשל בהודעה שאינה אומרת דבר.
    test('נכס של פלטפורמה אחרת נקרא כ"אין מראה"', () async {
      await mirror.sync(_release());

      final asMac = LauncherUpdateMirror(
        mirrorDir: mirror.mirrorDir,
        httpClient: MockClient((_) async => http.Response('abcd', 200)),
        operatingSystem: 'macos',
      );
      addTearDown(asMac.dispose);

      expect(await asMac.load(), isNull);
      // ובווינדוס אותה מראה בדיוק עדיין תקינה.
      expect(await mirror.load(), isNotNull);
    });

    test('digest תואם — ההורדה נשמרת, וה-sha256 נוסע במטא-דאטה', () async {
      await mirror.sync(_release(sha256: _abcdSha256));

      final loaded = await mirror.load();
      expect(loaded?.release.sha256, _abcdSha256);
      await mirror.verify(loaded!);
    });

    test('digest שאינו תואם נזרק, והקובץ שהורד נמחק', () async {
      final release = _release(sha256: 'f' * 64);
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

    test('קובץ שהשתבש בכונן באותו גודל נפסל באימות שלפני ההתקנה', () async {
      final synced = await mirror.sync(_release(sha256: _abcdSha256));
      await File(synced.filePath).writeAsString('abce');

      final loaded = await mirror.load();
      expect(loaded, isNotNull);
      await expectLater(
        () => mirror.verify(loaded!),
        throwsA(isA<LauncherUpdateException>()),
      );
      expect(File(synced.filePath).existsSync(), isFalse);
      expect(await mirror.load(), isNull);
    });

    test('קובץ קיים בגודל הנכון אך ב-digest שגוי יורד מחדש', () async {
      final release = _release(sha256: _abcdSha256);
      final existing = File(p.join(
        mirror.mirrorDir,
        'files',
        release.tagName,
        release.assetName,
      ));
      await existing.parent.create(recursive: true);
      await existing.writeAsString('abce');

      await mirror.sync(release);

      expect(await existing.readAsString(), 'abcd');
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

    LauncherSelfInstaller installer({Object? startError}) =>
        LauncherSelfInstaller(
          currentPid: 4242,
          operatingSystem: 'windows',
          startDetached: (executable, arguments) async {
            if (startError != null) throw startError;
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
    });

    test('הקובץ הקודם נשמר עד ההפעלה הבאה, ואז נמחק', () async {
      await installer().apply(
        layout: layout,
        downloadedFilePath: downloaded.path,
      );

      expect(
        File(p.join(temp.path, LauncherSelfInstaller.stagedName)).existsSync(),
        isFalse,
      );
      final previous =
          File(p.join(temp.path, LauncherSelfInstaller.previousName));
      expect(await previous.readAsString(), 'גרסה ישנה');

      await installer().cleanupLeftovers(layout);
      expect(previous.existsSync(), isFalse);
    });

    test('הגרסה החדשה לא עלתה — הקודמת חוזרת למקומה', () async {
      await expectLater(
        () => installer(
          startError: const FileSystemException('not a valid Win32 app'),
        ).apply(layout: layout, downloadedFilePath: downloaded.path),
        throwsA(isA<LauncherUpdateException>()),
      );

      expect(await stub.readAsString(), 'גרסה ישנה');
      expect(
        File(p.join(temp.path, LauncherSelfInstaller.previousName))
            .existsSync(),
        isFalse,
      );
      expect(
        File(p.join(temp.path, LauncherSelfInstaller.stagedName)).existsSync(),
        isFalse,
      );
      expect(quits, 0);
    });

    test('מפעיל את הקובץ החדש עם ה-pid שלנו, ואז מסיים', () async {
      await installer().apply(
        layout: layout,
        downloadedFilePath: downloaded.path,
      );

      expect(started.first, stub.path);
      // ה-stub החדש ממתין שהתהליך הזה ייסגר לפני שהוא מחלץ מחדש.
      expect(started.last, '${LauncherInstallLayout.afterUpdateFlag}=4242');
      expect(quits, 1);
    });

    test('שאריות מהחלפה שנקטעה נמחקות בבדיקה הבאה', () async {
      final leftover =
          File(p.join(temp.path, LauncherSelfInstaller.previousName));
      await leftover.writeAsString('שארית');

      await installer().cleanupLeftovers(layout);

      expect(leftover.existsSync(), isFalse);
    });

    // ב-macOS השאריות הן **תיקיות** — תיקיית ה-staging וחבילת ה-.app
    // הקודמת, מאות מגה-בייט כל אחת. הניקוי טיפל רק בקבצים של ווינדוס,
    // ולכן עדכון שנקטע השאיר אותן על הכונן לנצח.
    test('macOS: תיקיית ה-staging וחבילת ה-.app הקודמת נמחקות גם הן', () async {
      final bundle = Directory(p.join(temp.path, 'Otzaria Launcher.app'));
      await bundle.create(recursive: true);
      final macLayout = LauncherInstallLayout(executablePath: bundle.path);

      final staging = Directory(
        p.join(temp.path, LauncherSelfInstaller.macStagingDirName),
      );
      await Directory(p.join(staging.path, 'Otzaria Launcher.app'))
          .create(recursive: true);
      final previous = Directory('${bundle.path}.previous');
      await Directory(p.join(previous.path, 'Contents'))
          .create(recursive: true);

      await installer().cleanupLeftovers(macLayout);

      expect(staging.existsSync(), isFalse);
      expect(previous.existsSync(), isFalse);
      // והחבילה עצמה לא נגעו בה.
      expect(bundle.existsSync(), isTrue);
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
      int downloadStatus = 200,
      String? changelog,
      LauncherSelfInstaller? installer,
    }) {
      // `Response.bytes` ולא `Response(...)`: השני מקודד latin1 כשאין
      // content-type, וה-JSON כאן מכיל עברית (שם האסט).
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response.bytes(
              utf8.encode(jsonEncode([_releaseJson()])), 200);
        }
        if (request.url.host == 'raw.githubusercontent.com') {
          if (changelog == null) return http.Response('', 404);
          return http.Response.bytes(utf8.encode(changelog), 200);
        }
        return http.Response.bytes(utf8.encode(body), downloadStatus);
      });
      final made = LauncherSelfUpdater(
        dataDir: temp.path,
        httpClient: client,
        releaseClient: LauncherReleaseClient(
          httpClient: client,
          operatingSystem: 'windows',
        ),
        mirror: LauncherUpdateMirror(
          mirrorDir: p.join(temp.path, 'mirror', 'launcher'),
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
      expect(check.mirroredVersion, _release().version);
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

    test('קובץ שהשתבש בכונן באותו גודל אינו מותקן', () async {
      final layout = LauncherInstallLayout(
        executablePath: p.join(temp.path, 'stub.exe'),
      );
      final self = updater(layout: layout, installer: _NoRestartInstaller());
      final synced = await self.downloadToMirror(
        release: _release(sha256: _abcdSha256),
      );
      await File(synced!.filePath).writeAsString('abce');

      await expectLater(
        self.applyUpdate,
        throwsA(isA<LauncherUpdateException>()),
      );
    });

    group('LauncherUpdateController', () {
      setUp(() => AppLogger.init(temp.path));

      test('גרסה ותיקה במראה אינה מסתירה שהגרסה שברשת כבר רצה', () {
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(),
        );
        addTearDown(controller.dispose);

        controller.onlineRelease = _release(tag: 'v$launcherVersion');
        controller.downloadedVersion = '0.0.1';
        expect(controller.hasOnlineUpdate, isFalse);

        controller.onlineRelease = _release();
        expect(controller.hasOnlineUpdate, isTrue);

        controller.downloadedVersion = _release().version;
        expect(controller.hasOnlineUpdate, isFalse);
      });

      test('הורדה שנכשלה משאירה את הגרסה שכבר מוכנה בתיקייה', () async {
        final ready = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(),
        );
        addTearDown(ready.dispose);
        expect(await ready.download(), isTrue);

        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(downloadStatus: 500),
        );
        addTearDown(controller.dispose);
        controller.onlineRelease = _release(tag: _tagAfterNewer());

        expect(await controller.download(), isFalse);
        expect(controller.errorMessage, isNotNull);
        expect(controller.hasUpdateReady, isTrue);
        expect(controller.downloadedVersion, _release().version);
      });

      test('הורדה שנכשלה בלי גרסה מוכנה — מצב שגיאה', () async {
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(downloadStatus: 500),
        );
        addTearDown(controller.dispose);
        controller.onlineRelease = _release();

        expect(await controller.download(), isFalse);
        expect(controller.status, LauncherUpdateStatus.error);
        expect(controller.errorMessage, isNotNull);
      });

      test('"מה התחדש" נשלף בהצעה, ואחרי ההורדה נקרא מהמראה', () async {
        final newer = _release().version;
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(
            changelog: '  - עוד לא יצא\n\n* **$newer**\n  - חדש\n\n'
                '* **$launcherVersion**\n  - מה שכבר רץ',
          ),
        );
        addTearDown(controller.dispose);

        await controller.checkOnline();
        expect(controller.onlineWhatsNew, contains('חדש'));
        expect(controller.onlineWhatsNew, isNot(contains('מה שכבר רץ')));

        await controller.download();
        // לאנצ'ר חדש, כמו במחשב המנותק: אין רשת, רק מה שעל הכונן.
        final offline = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(),
        );
        addTearDown(offline.dispose);
        await offline.checkForUpdate();
        expect(offline.downloadedWhatsNew, contains('חדש'));
      });

      test('כשל בשליפת היומן אינו מפיל את ההורדה', () async {
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(), // raw מחזיר 404
        );
        addTearDown(controller.dispose);

        await controller.download();
        expect(controller.hasUpdateReady, isTrue);
        expect(controller.downloadedWhatsNew, isNull);
      });

      test('כשל התקנה משאיר את הכפתור — במחשב מנותק אין דרך אחרת לנסות שוב',
          () async {
        final installer = _FailingInstaller();
        final controller = LauncherUpdateController(
          dataDir: temp.path,
          updater: updater(
            layout: LauncherInstallLayout(
              executablePath: p.join(temp.path, 'stub.exe'),
            ),
            installer: installer,
          ),
        );
        addTearDown(controller.dispose);

        await controller.download();
        expect(await controller.install(), isFalse);

        expect(controller.errorMessage, isNotNull);
        expect(controller.hasUpdateReady, isTrue);
        expect(controller.isInstalling, isFalse);
        expect(installer.cleanupCalls, 1);
      });

      test('קובץ שהשתבש באותו גודל — אחרי ההתקנה שנכשלה מוצעת הורדה מחדש',
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
        final release = _release(sha256: _abcdSha256);
        controller.onlineRelease = release;

        expect(await controller.download(), isTrue);
        expect(controller.hasOnlineUpdate, isFalse);
        await File(p.join(
          temp.path,
          'mirror',
          'launcher',
          'files',
          release.tagName,
          release.assetName,
        )).writeAsString('abce');

        expect(await controller.install(), isFalse);
        expect(controller.errorMessage, isNotNull);
        expect(controller.status, LauncherUpdateStatus.error);
        expect(controller.downloadedVersion, isNull);
        expect(controller.hasOnlineUpdate, isTrue);

        expect(await controller.download(), isTrue);
        expect(controller.hasUpdateReady, isTrue);
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

class _FailingInstaller extends LauncherSelfInstaller {
  @override
  Future<bool> apply({
    required LauncherInstallLayout layout,
    required String downloadedFilePath,
  }) async =>
      throw const LauncherUpdateException('החלפה נכשלה');

  int cleanupCalls = 0;

  @override
  Future<void> cleanupLeftovers(LauncherInstallLayout layout) async {
    cleanupCalls++;
  }
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
