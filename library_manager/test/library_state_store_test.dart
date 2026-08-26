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
      final key = LibraryStateStore.currentMachineKey();
      await File(statePath).parent.create(recursive: true);

      await File(statePath).writeAsString(jsonEncode({
        'appliedReleases': {
          key: {'tag': '', 'dbVersion': 9}
        }
      }));
      expect(await store.loadAppliedRelease(), isNull);

      await File(statePath).writeAsString(jsonEncode({
        'appliedReleases': {
          key: {'tag': 'v9'}
        }
      }));
      expect(await store.loadAppliedRelease(), isNull);
    });

    // הבאג של "עדכון מגרסה 22 לגרסה 22": רשומה גלובלית אחת על כונן שנוסע בין
    // מחשבים נקראה מול מסד של מחשב אחר לגמרי.
    test('רשומה של מחשב אחר אינה נקראת כאן, והישנה הגלובלית מתעלמים ממנה',
        () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(jsonEncode({
        'appliedReleaseTag': 'v21-carrier',
        'appliedReleases': {
          'OTHER-PC|someone': {'tag': 'v20', 'dbVersion': 20},
        },
      }));

      expect(await store.loadAppliedRelease(), isNull);
    });

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

      expect(File('$statePath.tmp').existsSync(), isFalse);
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
      expect(
        json['customDbPaths'],
        {LibraryStateStore.currentMachineKey(): dbPath},
      );
    });

    test('רשומה של מחשב אחר אינה נקראת כאן', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(jsonEncode({
        'customDbPaths': {
          'OTHER-PC|user': p.join(tempDir.path, 'elsewhere', 'seforim.db'),
        },
      }));

      expect(await store.loadCustomDbPath(), isNull);
    });

    test('שמירה כאן אינה מוחקת את הרשומה של מחשב אחר', () async {
      final other = p.join(tempDir.path, 'elsewhere', 'seforim.db');
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(jsonEncode({
        'customDbPaths': {'OTHER-PC|user': other},
      }));

      final mine = p.join(tempDir.path, 'mine', 'seforim.db');
      await store.saveCustomDbPath(mine);

      final json = jsonDecode(await File(statePath).readAsString()) as Map;
      expect(json['customDbPaths'], {
        'OTHER-PC|user': other,
        LibraryStateStore.currentMachineKey(): mine,
      });
      expect(await store.loadCustomDbPath(), mine);
    });

    test('רשומה גלובלית ישנה נחשבת רק אם התיקייה שלה קיימת כאן', () async {
      final living = Directory(p.join(tempDir.path, 'living'));
      await living.create(recursive: true);
      await File(statePath).parent.create(recursive: true);

      await File(statePath).writeAsString(jsonEncode({
        'customDbPath': p.join(living.path, 'seforim.db'),
      }));
      expect(
        await store.loadCustomDbPath(),
        p.join(living.path, 'seforim.db'),
      );

      // אותה רשומה, אבל התיקייה שייכת למחשב שממנו הכונן הגיע.
      await File(statePath).writeAsString(jsonEncode({
        'customDbPath': p.join(tempDir.path, 'no-such-user', 'seforim.db'),
      }));
      expect(await store.loadCustomDbPath(), isNull);
    });

    test('רשומה גלובלית שאינה נתיב מוחלט בפלטפורמה הזו נדחית', () async {
      await File(statePath).parent.create(recursive: true);
      // ב-POSIX נתיב ווינדוס אינו מוחלט, ו-`dirname` שלו היה מחזיר "." הקיים.
      final foreign =
          Platform.isWindows ? '/home/dov/otzaria' : r'C:\Users\user\otzaria';
      await File(statePath).writeAsString(
        jsonEncode({'customDbPath': p.join(foreign, 'seforim.db')}),
      );

      expect(await store.loadCustomDbPath(), isNull);
    });

    test('רשומת המחשב הזה מנצחת רשומה גלובלית קיימת', () async {
      final mine = p.join(tempDir.path, 'mine', 'seforim.db');
      await Directory(p.dirname(mine)).create(recursive: true);
      await store.saveCustomDbPath(mine);

      final json = jsonDecode(await File(statePath).readAsString())
          as Map<String, dynamic>;
      json['customDbPath'] = p.join(tempDir.path, 'legacy', 'seforim.db');
      await Directory(p.join(tempDir.path, 'legacy')).create(recursive: true);
      await File(statePath).writeAsString(jsonEncode(json));

      expect(await store.loadCustomDbPath(), mine);
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

    test('ערכים פגומים בקובץ מסוננים ואינם מפילים את הקריאה', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString(
        '{"knownDbVersions": {"a": 0, "b": "x", "c": 18}}',
      );

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
