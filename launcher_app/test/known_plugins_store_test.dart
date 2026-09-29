import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/known_plugins_store.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

/// "אילו תוספים כבר נראו" הוא נתון של המחשב: הקובץ נוסע על הכונן, והמפתח
/// הוא שם המחשב. קובץ חסר או פגום פירושו "אין נקודת התחלה" — לא רשימה ריקה.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('known-plugins-');
  });

  tearDown(() => deleteTempDir(tempDir));

  test('בלי קובץ אין נקודת התחלה', () async {
    final store = KnownPluginsStore(tempDir.path, hostName: 'a');

    expect(await store.loadSeen(), isNull);
    expect(await store.loadNotified(), isNull);
  });

  test('רישום נשמר וממוזג, ושתי הרשימות נפרדות', () async {
    final store = KnownPluginsStore(tempDir.path, hostName: 'a');

    await store.recordSeen(['1', '2']);
    await store.recordSeen(['2', '3']);
    await store.recordNotified(['9']);

    expect(await store.loadSeen(), {'1', '2', '3'});
    expect(await store.loadNotified(), {'9'});
  });

  test('רשימה ריקה שנרשמה היא נקודת התחלה — לא "אין נתון"', () async {
    final store = KnownPluginsStore(tempDir.path, hostName: 'a');

    await store.recordSeen(const []);

    expect(await store.loadSeen(), isEmpty);
    expect(await store.loadNotified(), isNull);
  });

  test('כל מחשב רואה את הרשימה שלו בלבד', () async {
    await KnownPluginsStore(tempDir.path, hostName: 'a').recordSeen(['1']);

    final other = KnownPluginsStore(tempDir.path, hostName: 'b');
    expect(await other.loadSeen(), isNull);

    await other.recordSeen(['2']);
    expect(
      await KnownPluginsStore(tempDir.path, hostName: 'a').loadSeen(),
      {'1'},
    );
  });

  test('קובץ פגום נקרא כ"אין נקודת התחלה" ואינו קורס', () async {
    await File(p.join(tempDir.path, 'plugins_known.json'))
        .writeAsString('{not json');
    final store = KnownPluginsStore(tempDir.path, hostName: 'a');

    expect(await store.loadSeen(), isNull);

    await store.recordSeen(['1']);
    expect(await store.loadSeen(), {'1'});
  });
}
