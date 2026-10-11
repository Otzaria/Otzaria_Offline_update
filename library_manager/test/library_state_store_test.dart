import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

/// ה-state הזה הוא מה שמבדיל בין "מסד שהותקן על ידינו" לבין "מסד שמצאנו":
/// בלי רשומת `appliedReleases` של המחשב הזה, `LibraryUpdatePlanner` **לא**
/// מנחש שמדובר בפרסום מחדש — אחרת כל פתיחה הייתה מציעה הורדה של ~1GB.
void main() {
  late Directory tempDir;
  late String statePath;
  late LibraryStateStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library-state-test-');
    statePath = p.join(tempDir.path, 'state', 'library_state.json');
    store = LibraryStateStore(statePath);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('LibraryStateStore', () {
    test('קובץ שלא קיים מחזיר null לשני השדות, בלי לזרוק', () async {
      expect(await store.loadCustomDbPath(), isNull);
      expect(await store.loadAppliedRelease(), isNull);
      expect(File(statePath).existsSync(), isFalse);
    });

    test('inDir יושב על library_state.json — השם שעל הכונן', () async {
      final dir = p.dirname(statePath);
      expect(LibraryStateStore.fileName, 'library_state.json');
      expect(LibraryStateStore.inDir(dir).stateFilePath, statePath);

      await store.saveAppliedRelease(tag: 'v7', dbVersion: 7);
      expect(
        (await LibraryStateStore.inDir(dir).loadAppliedRelease())?.tag,
        'v7',
      );
    });

    test('סבב כתיבה/קריאה של נתיב מותאם אישית, כולל יצירת התיקייה', () async {
      final dbPath = p.join(tempDir.path, 'lib', 'seforim.db');
      await store.saveCustomDbPath(dbPath);

      expect(await LibraryStateStore(statePath).loadCustomDbPath(), dbPath);
      expect(File(statePath).existsSync(), isTrue);
    });

    test('סבב כתיבה/קריאה של appliedRelease — tag וגרסה יחד', () async {
      await store.saveAppliedRelease(tag: 'v42', dbVersion: 42);

      final loaded = await LibraryStateStore(statePath).loadAppliedRelease();
      expect(loaded?.tag, 'v42');
      expect(loaded?.dbVersion, 42);
    });

    test('כתיבת שדה אחד לא מוחקת את השני', () async {
      await store.saveCustomDbPath(r'C:\somewhere\seforim.db');
      await store.saveAppliedRelease(tag: 'v7', dbVersion: 7);
      await store.saveCustomDbPath(r'C:\elsewhere\seforim.db');

      expect((await store.loadAppliedRelease())?.tag, 'v7');
      expect(await store.loadCustomDbPath(), r'C:\elsewhere\seforim.db');
    });

    test('JSON פגום נחשב "לא הוגדר" ולא זורק', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('{ this is not json');

      expect(await store.loadCustomDbPath(), isNull);
      expect(await store.loadAppliedRelease(), isNull);
    });

    test('JSON תקין שאינו אובייקט נחשב "לא הוגדר"', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('["not", "a", "map"]');

      expect(await store.loadCustomDbPath(), isNull);
      expect(await store.loadAppliedRelease(), isNull);
    });

    test('כתיבה על קובץ פגום משחזרת אותו במקום להיתקע', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('}{');

      await store.saveAppliedRelease(tag: 'v9', dbVersion: 9);
      expect((await store.loadAppliedRelease())?.tag, 'v9');
    });

    test('רשומה חסרת tag או חסרת גרסה נחשבת "לא ידוע" — לא מנחשים', () async {
      final key = await LibraryStateStore.currentMachineKey();
      await File(statePath).parent.create(recursive: true);

      await File(statePath).writeAsString(
        jsonEncode({
          'appliedReleases': {
            key: {'tag': '', 'dbVersion': 9},
          },
        }),
      );
      expect(await store.loadAppliedRelease(), isNull);

      await File(statePath).writeAsString(
        jsonEncode({
          'appliedReleases': {
            key: {'tag': 'v9'},
          },
        }),
      );
      expect(await store.loadAppliedRelease(), isNull);
    });

    // הבאג של "עדכון מגרסה 22 לגרסה 22": רשומה גלובלית אחת על כונן שנוסע בין
    // מחשבים נקראה מול מסד של מחשב אחר לגמרי.
    test(
      'רשומה של מחשב אחר אינה נקראת כאן, והישנה הגלובלית מתעלמים ממנה',
      () async {
        await File(statePath).parent.create(recursive: true);
        await File(statePath).writeAsString(
          jsonEncode({
            'appliedReleaseTag': 'v21-carrier',
            'appliedReleases': {
              'OTHER-PC|someone': {'tag': 'v20', 'dbVersion': 20},
            },
          }),
        );

        expect(await store.loadAppliedRelease(), isNull);
      },
    );

    test('כתיבה מסירה מהכונן את הרשומה הגלובלית הישנה', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('{"appliedReleaseTag": "v21"}');

      await store.saveAppliedRelease(tag: 'v22', dbVersion: 22);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json.containsKey('appliedReleaseTag'), isFalse);
      expect((await store.loadAppliedRelease())?.dbVersion, 22);
    });

    test('הכתיבה עוברת דרך קובץ זמני ולא משאירה אותו', () async {
      await store.saveAppliedRelease(tag: 'v1', dbVersion: 1);

      expect(Directory(p.dirname(statePath)).listSync().map((e) => e.path), [
        statePath,
      ]);
    });

    test('קובץ פגום מועבר הצידה לפני שהכתיבה הבאה דורסת אותו', () async {
      await File(statePath).parent.create(recursive: true);
      const torn = '{"appliedReleases": {"OTHER-PC|someone": {"tag": "v2';
      await File(statePath).writeAsString(torn);

      await store.saveAppliedRelease(tag: 'v9', dbVersion: 9);

      expect(File('$statePath.corrupt').readAsStringSync(), torn);
      expect((await store.loadAppliedRelease())?.tag, 'v9');
    });

    test('קובץ שאינו UTF-8 נחשב פגום ומועבר הצידה', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsBytes([0xff, 0xfe, 0x00]);

      expect(await store.loadAppliedRelease(), isNull);
      expect(File('$statePath.corrupt').readAsBytesSync(), [0xff, 0xfe, 0x00]);
    });

    test('קובץ קיים שאינו קריא אינו נדרס ברשומת המחשב הנוכחי בלבד', () async {
      await File(statePath).parent.create(recursive: true);
      final original = jsonEncode({
        'customDbPaths': {'OTHER-PC|someone': r'D:\lib\seforim.db'},
        'appliedReleases': {
          'OTHER-PC|someone': {'tag': 'v2', 'dbVersion': 2},
        },
        'deliveredCompanions': {
          'OTHER-PC|someone': {'semantic': 'm1'},
        },
        'knownDbVersions': {'OTHER-PC|someone': 2},
      });
      await File(statePath).writeAsString(original);
      await Process.run('chmod', ['000', statePath]);
      addTearDown(() => Process.run('chmod', ['644', statePath]));
      expect(() => File(statePath).readAsBytesSync(), throwsA(anything));

      expect(await store.loadAppliedRelease(), isNull);
      expect(await store.loadKnownDbVersions(), isEmpty);
      await expectLater(
        store.saveCustomDbPath(r'C:\x\seforim.db'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.saveAppliedRelease(tag: 'v9', dbVersion: 9),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.saveDeliveredCompanions({'semantic': 'm9'}),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        store.recordKnownDbVersion('THIS-PC|me', 9),
        throwsA(isA<FileSystemException>()),
      );

      await Process.run('chmod', ['644', statePath]);
      expect(File(statePath).readAsStringSync(), original);
      expect(File('$statePath.corrupt').existsSync(), isFalse);
    }, skip: Platform.isWindows);

    test('קובץ תקין אינו מועבר הצידה', () async {
      await store.saveAppliedRelease(tag: 'v1', dbVersion: 1);

      await store.loadAppliedRelease();
      await store.saveCustomDbPath(r'C:\x\seforim.db');

      expect(File('$statePath.corrupt').existsSync(), isFalse);
    });

    test('כתיבות במקביל אינן מתנגשות על קובץ זמני משותף', () async {
      await Future.wait([
        for (var i = 1; i <= 20; i++)
          store.saveAppliedRelease(tag: 'v$i', dbVersion: i),
      ]);

      expect(await store.loadAppliedRelease(), isNotNull);
      expect(Directory(p.dirname(statePath)).listSync().map((e) => e.path), [
        statePath,
      ]);
    });
  });

  // issue #23: הקובץ נוסע על הכונן, ורשומה גלובלית אחת הצביעה במחשב הבא אל
  // `C:\Users\<שם החשבון של המחשב הראשון>` — תיקייה שאין שם ואי אפשר ליצור.
  group('LibraryStateStore — נתיב מותאם אישית הוא פר-מחשב', () {
    test('הנתיב נשמר תחת מזהה המחשב, ולא כשדה גלובלי', () async {
      final dbPath = p.join(tempDir.path, 'lib', 'seforim.db');
      await store.saveCustomDbPath(dbPath);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['customDbPath'], isNull);
      expect(json['customDbPaths'], {
        await LibraryStateStore.currentMachineKey(): dbPath,
      });
    });

    test('רשומה של מחשב אחר אינה נקראת כאן', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'customDbPaths': {
            'OTHER-PC|user': p.join(tempDir.path, 'elsewhere', 'seforim.db'),
          },
        }),
      );

      expect(await store.loadCustomDbPath(), isNull);
    });

    test('שמירה כאן אינה מוחקת את הרשומה של מחשב אחר', () async {
      final other = p.join(tempDir.path, 'elsewhere', 'seforim.db');
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'customDbPaths': {'OTHER-PC|user': other},
        }),
      );

      final mine = p.join(tempDir.path, 'mine', 'seforim.db');
      await store.saveCustomDbPath(mine);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['customDbPaths'], {
        'OTHER-PC|user': other,
        await LibraryStateStore.currentMachineKey(): mine,
      });
      expect(await store.loadCustomDbPath(), mine);
    });

    test('רשומה גלובלית ישנה נחשבת רק אם התיקייה שלה קיימת כאן', () async {
      final living = Directory(p.join(tempDir.path, 'living'));
      await living.create(recursive: true);
      await File(statePath).parent.create(recursive: true);

      await File(statePath).writeAsString(
        jsonEncode({'customDbPath': p.join(living.path, 'seforim.db')}),
      );
      expect(await store.loadCustomDbPath(), p.join(living.path, 'seforim.db'));

      // אותה רשומה, אבל התיקייה שייכת למחשב שממנו הכונן הגיע.
      await File(statePath).writeAsString(
        jsonEncode({
          'customDbPath': p.join(tempDir.path, 'no-such-user', 'seforim.db'),
        }),
      );
      expect(await store.loadCustomDbPath(), isNull);
    });

    test('רשומה גלובלית שאינה נתיב מוחלט בפלטפורמה הזו נדחית', () async {
      await File(statePath).parent.create(recursive: true);
      // ב-POSIX נתיב ווינדוס אינו מוחלט, ו-`dirname` שלו היה מחזיר "." הקיים.
      final foreign = Platform.isWindows
          ? '/home/dov/otzaria'
          : r'C:\Users\user\otzaria';
      await File(statePath).writeAsString(
        jsonEncode({'customDbPath': p.join(foreign, 'seforim.db')}),
      );

      expect(await store.loadCustomDbPath(), isNull);
    });

    test('רשומת המחשב הזה מנצחת רשומה גלובלית קיימת', () async {
      final mine = p.join(tempDir.path, 'mine', 'seforim.db');
      await Directory(p.dirname(mine)).create(recursive: true);
      await store.saveCustomDbPath(mine);

      final json = jsonDecode(
        await File(statePath).readAsString(),
      ) as Map<String, dynamic>;
      json['customDbPath'] = p.join(tempDir.path, 'legacy', 'seforim.db');
      await Directory(p.join(tempDir.path, 'legacy')).create(recursive: true);
      await File(statePath).writeAsString(jsonEncode(json));

      expect(await store.loadCustomDbPath(), mine);
    });

    test('רשומה גלובלית על הכונן נדחית גם כשהמצב יושב ב-logs', () async {
      final dataDir = p.join(tempDir.path, 'OtzariaData');
      final logsState = p.join(dataDir, 'logs', 'library_state.json');
      final onDrive = p.join(dataDir, 'library', 'seforim.db');
      await Directory(p.dirname(onDrive)).create(recursive: true);
      await File(logsState).parent.create(recursive: true);
      await File(logsState)
          .writeAsString(jsonEncode({'customDbPath': onDrive}));

      final drive = LibraryStateStore(logsState, dataDir: dataDir);
      expect(drive.isInsideDataDir(onDrive), isTrue);
      expect(await drive.loadCustomDbPath(), isNull);
    });

    test('רשומה גלובלית מחוץ לתיקיית הנתונים עדיין נקראת', () async {
      final dataDir = p.join(tempDir.path, 'OtzariaData');
      final logsState = p.join(dataDir, 'logs', 'library_state.json');
      final elsewhere = p.join(tempDir.path, 'books', 'seforim.db');
      await Directory(p.dirname(elsewhere)).create(recursive: true);
      await File(logsState).parent.create(recursive: true);
      await File(logsState)
          .writeAsString(jsonEncode({'customDbPath': elsewhere}));

      expect(
        await LibraryStateStore(logsState, dataDir: dataDir).loadCustomDbPath(),
        elsewhere,
      );
    });
  });

  group('LibraryStateStore — מזהה המחשב', () {
    test('MachineGuid נקרא מהפלט של reg query', () {
      const output =
          'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Cryptography\r\n'
          '    MachineGuid    REG_SZ    3f2504e0-4f89-11d3-9a0c-0305e82c3301\r\n';
      expect(
        LibraryStateStore.parseMachineId(output),
        '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
      );
    });

    test('IOPlatformUUID נקרא מהפלט של ioreg', () {
      const output =
          '+-o J314sAP  <class IOPlatformExpertDevice>\n'
          '    "IOPlatformSerialNumber" = "C02XXXXXXXXX"\n'
          '    "IOPlatformUUID" = "A1B2C3D4-E5F6-7890-ABCD-EF0123456789"\n';
      expect(
        LibraryStateStore.parseMachineId(output),
        'A1B2C3D4-E5F6-7890-ABCD-EF0123456789',
      );
    });

    test('פלט לא מוכר אינו מניב מזהה', () {
      expect(LibraryStateStore.parseMachineId('ERROR: not found'), isNull);
    });

    test('התקציר יציב, אינו תלוי רישיות ואינו חושף את המזהה', () {
      const id = 'A1B2C3D4-E5F6-7890-ABCD-EF0123456789';
      final digest = LibraryStateStore.machineIdDigest(id);
      expect(digest, LibraryStateStore.machineIdDigest(id.toLowerCase()));
      expect(digest, hasLength(16));
      expect(digest.toUpperCase().contains('A1B2C3D4'), isFalse);
    });

    test('מחשבים משוכפלים עם אותו מזהה ושמות שונים נשארים נפרדים', () {
      const id = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
      final a = LibraryStateStore.machineKeyFor(
        machineId: id,
        hostname: 'LAB-01',
        account: 'student',
        hostnameIsStable: true,
      );
      final b = LibraryStateStore.machineKeyFor(
        machineId: id,
        hostname: 'LAB-02',
        account: 'student',
        hostnameIsStable: true,
      );
      expect(a, isNot(b));
      expect(a.endsWith('|student'), isTrue);
      expect(LibraryStateStore.isHostnameKey(a), isFalse);
      expect(a.contains('LAB-01'), isFalse);
    });

    test('ב-macOS שם המחשב אינו חלק מהמפתח', () {
      const id = 'A1B2C3D4-E5F6-7890-ABCD-EF0123456789';
      final before = LibraryStateStore.machineKeyFor(
        machineId: id,
        hostname: 'Johns-MBP',
        account: 'me',
        hostnameIsStable: false,
      );
      final after = LibraryStateStore.machineKeyFor(
        machineId: id,
        hostname: 'MacBook-Pro-3',
        account: 'me',
        hostnameIsStable: false,
      );
      expect(before, after);
    });

    test('בלי מזהה המפתח נופל לשם המחשב', () {
      final key = LibraryStateStore.machineKeyFor(
        machineId: null,
        hostname: 'PC',
        account: 'me',
        hostnameIsStable: true,
      );
      expect(key, 'PC|me');
      expect(LibraryStateStore.isHostnameKey(key), isTrue);
    });

    test('המפתח יציב בתוך הרצה ומסתיים בשם החשבון', () async {
      final key = await LibraryStateStore.currentMachineKey();
      expect(await LibraryStateStore.currentMachineKey(), key);
      final account = LibraryStateStore.legacyMachineKey().split('|').last;
      expect(key.split('|').last, account);
    });

    test('רשומות לפי שם המחשב נקראות ועוברות למפתח החדש בכתיבה', () async {
      final legacy = LibraryStateStore.legacyMachineKey();
      final current = await LibraryStateStore.currentMachineKey();
      final dbPath = p.join(tempDir.path, 'lib', 'seforim.db');
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'customDbPaths': {legacy: dbPath, 'OTHER-PC|user': 'x'},
          'appliedReleases': {
            legacy: {'tag': 'v20', 'dbVersion': 20},
          },
          'deliveredCompanions': {
            legacy: {'a': '1'},
          },
          'knownDbVersions': {legacy: 20, 'OTHER-PC|user': 22},
        }),
      );

      expect(await store.loadCustomDbPath(), dbPath);
      expect((await store.loadAppliedRelease())?.tag, 'v20');
      expect(await store.loadDeliveredCompanions(), {'a': '1'});
      expect(await store.hasOwnKnownDbVersion(), isTrue);

      await store.saveCustomDbPath(dbPath);
      await store.saveAppliedRelease(tag: 'v21', dbVersion: 21);
      await store.saveDeliveredCompanions({'b': '2'});
      await store.recordOwnDbVersion(21);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['customDbPaths'], {'OTHER-PC|user': 'x', current: dbPath});
      expect(json['appliedReleases'], {
        current: {'tag': 'v21', 'dbVersion': 21},
      });
      expect(json['deliveredCompanions'], {
        current: {'a': '1', 'b': '2'},
      });
      expect(json['knownDbVersions'], {'OTHER-PC|user': 22, current: 21});
    });
  });

  // נקודת המוצא של ההורדה במצב "עדכון אישי". הרשומה נוסעת על הכונן בין
  // מחשבים, ולכן היא מפתח-לכל-מחשב והמינימום הוא מה שנקרא.
  group('LibraryStateStore — גרסאות המסד שנרשמו', () {
    test('בלי רשומות — null, בלי לזרוק', () async {
      expect(await store.loadKnownDbVersions(), isEmpty);
      expect(await store.lowestKnownDbVersion(), isNull);
    });

    test('הנמוכה מבין המחשבים היא זו שנקראת', () async {
      await store.recordKnownDbVersion(r'HOME|C:\a\seforim.db', 20);
      await store.recordKnownDbVersion(r'ONLINE|D:\b\seforim.db', 22);

      expect(await LibraryStateStore(statePath).lowestKnownDbVersion(), 20);
    });

    test('רישום חוזר לאותו מחשב מעדכן אותו ומרים את המינימום', () async {
      await store.recordKnownDbVersion('HOME', 20);
      await store.recordKnownDbVersion('ONLINE', 22);
      // המחשב הביתי עודכן — מכאן אין למי למשוך את המינימום למטה.
      await store.recordKnownDbVersion('HOME', 22);

      expect(await store.loadKnownDbVersions(), {'HOME': 22, 'ONLINE': 22});
      expect(await store.lowestKnownDbVersion(), 22);
    });

    test('רישום גרסה אינו מוחק את שאר ה-state', () async {
      await store.saveAppliedRelease(tag: 'v20', dbVersion: 20);
      await store.saveCustomDbPath(r'C:\lib\seforim.db');
      await store.recordKnownDbVersion('HOME', 20);

      expect((await store.loadAppliedRelease())?.tag, 'v20');
      expect(await store.loadCustomDbPath(), r'C:\lib\seforim.db');
    });

    test('חשבון אחר באותו מחשב שומר על הרשומה שלו', () async {
      await store.recordKnownDbVersion('PC|student', 20);
      await store.recordKnownDbVersion('PC|teacher', 22);

      expect(await store.loadKnownDbVersions(), {
        'PC|student': 20,
        'PC|teacher': 22,
      });
      expect(await store.lowestKnownDbVersion(), 20);

      await store.recordKnownDbVersion('PC|student', 22);
      expect(await store.loadKnownDbVersions(), {
        'PC|student': 22,
        'PC|teacher': 22,
      });
    });

    test('רשומות ישנות לפי נתיב המסד של המחשב הזה נמחקות', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {
            r'PC|C:\Users\a\seforim.db': 18,
            'PC|/home/a/otzaria/seforim.db': 17,
            'PC|student': 20,
            r'OTHER|D:\b\seforim.db': 19,
          },
        }),
      );

      await store.recordKnownDbVersion('PC|teacher', 22);

      expect(await store.loadKnownDbVersions(), {
        'PC|student': 20,
        r'OTHER|D:\b\seforim.db': 19,
        'PC|teacher': 22,
      });
    });

    test('כינוי ישן של המחשב הזה מוחלף במפתח שלו', () async {
      await store.recordKnownDbVersion('OLD-HOST|me', 20);
      await store.recordKnownDbVersion('OTHER|me', 21);
      await store.recordKnownDbVersion('id|me', 22, aliases: ['OLD-HOST|me']);

      expect(await store.loadKnownDbVersions(), {'OTHER|me': 21, 'id|me': 22});
    });

    test('רשומה לפי שם מחשב שלא חודשה זמן רב מתעלמים ממנה וגוזמים', () async {
      final fresh = DateTime.now().toUtc();
      final old = fresh.subtract(const Duration(days: 200));
      final digestKey =
          '${LibraryStateStore.machineIdDigest('x', hostname: 'h')}|me';
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {'Johns-MBP|me': 20, digestKey: 21, 'NEW|me': 23},
          'knownDbVersionsSeen': {
            'Johns-MBP|me': old.toIso8601String(),
            digestKey: old.toIso8601String(),
            'NEW|me': fresh.toIso8601String(),
          },
        }),
      );

      expect(await store.lowestKnownDbVersion(), 21);

      await store.recordKnownDbVersion('OTHER|me', 22);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['knownDbVersions'], {
        digestKey: 21,
        'NEW|me': 23,
        'OTHER|me': 22,
      });
      expect((json['knownDbVersionsSeen'] as Map).keys.toSet(), {
        digestKey,
        'NEW|me',
        'OTHER|me',
      });
      expect(json['knownDbVersionsSeen'][digestKey], old.toIso8601String());
    });

    test('רשומה לפי מזהה מחשב פגה רק אחרי שנה', () async {
      final fresh = DateTime.now().toUtc();
      final old = fresh.subtract(const Duration(days: 400));
      final digestKey =
          '${LibraryStateStore.machineIdDigest('x', hostname: 'h')}|me';
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {digestKey: 18, 'PC|me': 22},
          'knownDbVersionsSeen': {
            digestKey: old.toIso8601String(),
            'PC|me': fresh.toIso8601String(),
          },
        }),
      );

      expect(await store.lowestKnownDbVersion(), 22);
    });

    test('רשומה של המחשב הזה שפגה אינה נחשבת רישום', () async {
      final own = await LibraryStateStore.currentMachineKey();
      final fresh = DateTime.now().toUtc();
      final old = fresh.subtract(const Duration(days: 400));
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {own: 20, 'OTHER|me': 22},
          'knownDbVersionsSeen': {
            own: old.toIso8601String(),
            'OTHER|me': fresh.toIso8601String(),
          },
        }),
      );

      expect(await store.hasOwnKnownDbVersion(), isFalse);
      expect(await store.lowestKnownDbVersion(), 22);

      await store.recordOwnDbVersion(21);
      expect(await store.hasOwnKnownDbVersion(), isTrue);
      expect(await store.lowestKnownDbVersion(), 21);
    });

    test('רשומה ישנה בלי חותמת נספרת ומקבלת חותמת בכתיבה הבאה', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {'OLD|me': 20},
        }),
      );

      expect(await store.lowestKnownDbVersion(), 20);

      await store.recordKnownDbVersion('PC|me', 22);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['knownDbVersions'], {'OLD|me': 20, 'PC|me': 22});
      final stamp = DateTime.parse(
        json['knownDbVersionsSeen']['OLD|me'] as String,
      );
      expect(DateTime.now().toUtc().difference(stamp).inMinutes, lessThan(5));
      expect(await store.lowestKnownDbVersion(), 20);
    });

    test('התפוגה נמדדת מול החותמת החדשה בקובץ ולא מול השעון המקומי', () async {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 800));
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {'A|me': 20, 'B|me': 21},
          'knownDbVersionsSeen': {
            'A|me': old.toIso8601String(),
            'B|me': old.toIso8601String(),
          },
        }),
      );

      expect(await store.lowestKnownDbVersion(), 20);
      expect(await store.hasOwnKnownDbVersion(), isFalse);
    });

    test('מחשב ששעונו מפגר אינו כותב לעצמו חותמת פגה', () async {
      final ahead = DateTime.now().toUtc().add(const Duration(days: 800));
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {'OTHER|me': 22},
          'knownDbVersionsSeen': {'OTHER|me': ahead.toIso8601String()},
          'knownDbVersionsLocalTime': {'OTHER|me': ahead.toIso8601String()},
        }),
      );

      await store.recordKnownDbVersion('LAG|me', 20);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(
        DateTime.parse(json['knownDbVersionsSeen']['LAG|me'] as String),
        ahead,
      );
      expect(await store.loadKnownDbVersions(), {'OTHER|me': 22, 'LAG|me': 20});
      expect(await store.lowestKnownDbVersion(), 20);

      await store.recordKnownDbVersion('LAG|me', 21);
      expect(await store.lowestKnownDbVersion(), 21);
    });

    test('מחשב ששעונו מקדים אינו גוזם את רשומות האחרים', () async {
      final behind = DateTime.now().toUtc().subtract(const Duration(days: 800));
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {'A|me': 20, 'B|me': 21},
          'knownDbVersionsSeen': {
            'A|me': behind.toIso8601String(),
            'B|me': behind.toIso8601String(),
          },
          'knownDbVersionsLocalTime': {
            'A|me': behind.toIso8601String(),
            'B|me': behind.toIso8601String(),
          },
        }),
      );

      await store.recordKnownDbVersion('FAST|me', 22);
      await store.recordKnownDbVersion('FAST|me', 23);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['knownDbVersions'], {'A|me': 20, 'B|me': 21, 'FAST|me': 23});
      final fastSeen = DateTime.parse(
        json['knownDbVersionsSeen']['FAST|me'] as String,
      );
      expect(fastSeen.difference(behind).inMinutes, lessThan(1));
      expect(await store.lowestKnownDbVersion(), 20);
    });

    test('השעון הלוגי מתקדם לפי הזמן שעבר בשעון של הכותב עצמו', () async {
      final now = DateTime.now().toUtc();
      final logical = now.subtract(const Duration(days: 1000));
      Future<DateTime> advanceFrom(DateTime ownLocalTime) async {
        await File(statePath).parent.create(recursive: true);
        await File(statePath).writeAsString(
          jsonEncode({
            'knownDbVersions': {'PC|me': 20, 'OTHER|me': 21},
            'knownDbVersionsSeen': {
              'PC|me': logical.toIso8601String(),
              'OTHER|me': logical.toIso8601String(),
            },
            'knownDbVersionsLocalTime': {
              'PC|me': ownLocalTime.toIso8601String(),
            },
          }),
        );
        await store.recordKnownDbVersion('PC|me', 22);
        final json = jsonDecode(await File(statePath).readAsString()) as Map;
        return DateTime.parse(json['knownDbVersionsSeen']['PC|me'] as String);
      }

      final tenDays = await advanceFrom(now.subtract(const Duration(days: 10)));
      expect(
        tenDays.difference(logical).inHours,
        closeTo(const Duration(days: 10).inHours, 1),
      );
      expect(
        await advanceFrom(now.subtract(const Duration(days: 3000))),
        logical.add(LibraryStateStore.maxClockStep),
      );
      expect(await advanceFrom(now.add(const Duration(days: 3000))), logical);
    });

    test('הגיזום בכתיבה נמדד מול השעון הלוגי', () async {
      final now = DateTime.now().toUtc();
      final logical = now.subtract(const Duration(days: 1000));
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        jsonEncode({
          'knownDbVersions': {'PC|me': 22, 'ORPHAN|me': 18},
          'knownDbVersionsSeen': {
            'PC|me': logical.toIso8601String(),
            'ORPHAN|me': logical
                .subtract(const Duration(days: 170))
                .toIso8601String(),
          },
          'knownDbVersionsLocalTime': {
            'PC|me': now.subtract(const Duration(days: 20)).toIso8601String(),
          },
        }),
      );

      expect(await store.lowestKnownDbVersion(), 18);

      await store.recordKnownDbVersion('PC|me', 22);

      expect(await store.loadKnownDbVersions(), {'PC|me': 22});
    });

    test('ערכים פגומים בקובץ מסוננים ואינם מפילים את הקריאה', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath)
          .writeAsString('{"knownDbVersions": {"a": 0, "b": "x", "c": 18}}');

      expect(await store.loadKnownDbVersions(), {'c': 18});
      expect(await store.lowestKnownDbVersion(), 18);
    });

    test('knownDbVersions שאינו אובייקט נחשב "אין רשומות"', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('{"knownDbVersions": 7}');

      expect(await store.lowestKnownDbVersion(), isNull);
    });
  });
}
