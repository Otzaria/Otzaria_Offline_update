import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

/// "אילו הודעות כבר הוצגו" הוא נתון של המחשב: הקובץ נוסע על הכונן, והמפתח
/// הוא שם המחשב. קובץ חסר או פגום פירושו "עוד לא הוצג כלום".
void main() {
  late Directory tempDir;
  const key = NoticesSeenStore.errorReportsIntro;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notices-seen-');
  });

  tearDown(() => deleteTempDir(tempDir));

  test('בלי קובץ שום הודעה לא הוצגה', () async {
    final store = NoticesSeenStore(tempDir.path, hostName: 'a');

    expect(await store.hasSeen(key), isFalse);
  });

  test('אחרי רישום ההודעה נחשבת מוצגת — גם בהרצה חדשה', () async {
    await NoticesSeenStore(tempDir.path, hostName: 'a').markSeen(key);

    final later = NoticesSeenStore(tempDir.path, hostName: 'a');
    expect(await later.hasSeen(key), isTrue);
  });

  test('רישום כפול אינו משכפל, ומפתחות שונים נשמרים יחד', () async {
    final store = NoticesSeenStore(tempDir.path, hostName: 'a');

    await store.markSeen(key);
    await store.markSeen(key);
    await store.markSeen('other_notice');

    expect(await store.hasSeen(key), isTrue);
    expect(await store.hasSeen('other_notice'), isTrue);
    expect(await store.hasSeen('never_shown'), isFalse);
    final text =
        await File(p.join(tempDir.path, 'notices_seen.json')).readAsString();
    expect(RegExp(key).allMatches(text), hasLength(1));
  });

  test('כל מחשב רואה את ההודעות שלו בלבד', () async {
    await NoticesSeenStore(tempDir.path, hostName: 'a').markSeen(key);

    final other = NoticesSeenStore(tempDir.path, hostName: 'b');
    expect(await other.hasSeen(key), isFalse);

    await other.markSeen(key);
    expect(
      await NoticesSeenStore(tempDir.path, hostName: 'a').hasSeen(key),
      isTrue,
    );
  });

  test('קובץ פגום נקרא כ"לא הוצג" ואינו קורס, והרישום מתקן אותו', () async {
    await File(p.join(tempDir.path, 'notices_seen.json'))
        .writeAsString('{not json');
    final store = NoticesSeenStore(tempDir.path, hostName: 'a');

    expect(await store.hasSeen(key), isFalse);

    await store.markSeen(key);
    expect(await store.hasSeen(key), isTrue);
  });

  test('תיקיית המצב שאינה קיימת נוצרת ברישום', () async {
    final dir = p.join(tempDir.path, 'nested', 'state');
    final store = NoticesSeenStore(dir, hostName: 'a');

    await store.markSeen(key);

    expect(await NoticesSeenStore(dir, hostName: 'a').hasSeen(key), isTrue);
  });

  test('כשל כתיבה אינו זורק — ההודעה פשוט תחזור', () async {
    // "תיקייה" שהיא בעצם קובץ: יצירתה נכשלת.
    final blocker = File(p.join(tempDir.path, 'blocked'))
      ..writeAsStringSync('');
    final store = NoticesSeenStore(blocker.path, hostName: 'a');

    await store.markSeen(key);

    expect(await store.hasSeen(key), isFalse);
  });
}
