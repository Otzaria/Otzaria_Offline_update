import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;

/// ה-state הזה הוא מה שמבדיל בין "מסד שהותקן על ידינו" לבין "מסד שמצאנו":
/// בלי `appliedReleaseTag` ידוע, `LibraryUpdatePlanner` **לא** מנחש שמדובר
/// בפרסום מחדש — אחרת כל פתיחה הייתה מציעה הורדה של ~1GB.
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
      expect(await store.loadAppliedReleaseTag(), isNull);
      expect(File(statePath).existsSync(), isFalse);
    });

    test('סבב כתיבה/קריאה של נתיב מותאם אישית, כולל יצירת התיקייה', () async {
      final dbPath = p.join(tempDir.path, 'lib', 'seforim.db');
      await store.saveCustomDbPath(dbPath);

      expect(await LibraryStateStore(statePath).loadCustomDbPath(), dbPath);
      expect(File(statePath).existsSync(), isTrue);
    });

    test('סבב כתיבה/קריאה של appliedReleaseTag', () async {
      await store.saveAppliedReleaseTag('v42');
      expect(await LibraryStateStore(statePath).loadAppliedReleaseTag(), 'v42');
    });

    test('כתיבת שדה אחד לא מוחקת את השני', () async {
      await store.saveCustomDbPath(r'C:\somewhere\seforim.db');
      await store.saveAppliedReleaseTag('v7');
      await store.saveCustomDbPath(r'C:\elsewhere\seforim.db');

      expect(await store.loadAppliedReleaseTag(), 'v7');
      expect(await store.loadCustomDbPath(), r'C:\elsewhere\seforim.db');
    });

    test('JSON פגום נחשב "לא הוגדר" ולא זורק', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('{ this is not json');

      expect(await store.loadCustomDbPath(), isNull);
      expect(await store.loadAppliedReleaseTag(), isNull);
    });

    test('JSON תקין שאינו אובייקט נחשב "לא הוגדר"', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('["not", "a", "map"]');

      expect(await store.loadCustomDbPath(), isNull);
      expect(await store.loadAppliedReleaseTag(), isNull);
    });

    test('כתיבה על קובץ פגום משחזרת אותו במקום להיתקע', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('}{');

      await store.saveAppliedReleaseTag('v9');
      expect(await store.loadAppliedReleaseTag(), 'v9');
    });

    test('tag ריק או מסוג לא-מחרוזת נחשב "לא ידוע" — לא מנחשים', () async {
      await File(statePath).parent.create(recursive: true);
      await File(statePath).writeAsString('{"appliedReleaseTag": ""}');
      expect(await store.loadAppliedReleaseTag(), isNull);

      await File(statePath).writeAsString('{"appliedReleaseTag": 5}');
      expect(await store.loadAppliedReleaseTag(), isNull);
    });

    test('הכתיבה עוברת דרך קובץ זמני ולא משאירה אותו', () async {
      await store.saveAppliedReleaseTag('v1');

      expect(File('$statePath.tmp').existsSync(), isFalse);
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
      await store.saveAppliedReleaseTag('v20');
      await store.saveCustomDbPath(r'C:\lib\seforim.db');
      await store.recordKnownDbVersion('HOME', 20);

      expect(await store.loadAppliedReleaseTag(), 'v20');
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
