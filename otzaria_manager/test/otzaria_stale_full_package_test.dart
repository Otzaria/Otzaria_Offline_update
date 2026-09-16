import 'dart:io';

import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// חבילת ה-FULL אינה נתמכת יותר. מה שנבדק כאן הוא **הניקוי**: קובץ של 2GB
/// שירד בגרסה ישנה של הלאנצ'ר חייב להימצא ולהימחק, ולא להישאר על הכונן
/// לנצח — ומנגד, אסור שהניקוי ייגע במתקין הרגיל.

/// `<mirror>/installers/<tag>/` — איפה שהמתקינים יושבים בפועל.
String _tagDir(Directory mirror, String tag) =>
    p.join(mirror.path, 'installers', tag);

Future<File> _write(String path, String contents) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
  return file;
}

void main() {
  late Directory temp;
  late OtzariaManager manager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-stale-full-');
    manager = OtzariaManager(
      dataDir: temp.path,
      platform: OtzariaTargetPlatform.windows,
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('מוצא חבילת FULL שנשארה לצד המתקין הרגיל', () async {
    final tag = _tagDir(Directory(manager.mirrorDir), '0.9.96+736');
    await _write(p.join(tag, 'otzaria-0.9.96-windows.exe'), 'setup');
    final full =
        await _write(p.join(tag, 'otzaria-0.9.96-windows-full.exe'), 'full');

    final check = await manager.checkForUpdate();
    expect(check.hasStaleFullPackage, isTrue);
    // הניקוי הוא של ההורדה; הבדיקה רק מדווחת.
    expect(await full.exists(), isTrue);
  });

  test('מתקין רגיל בלבד — אין מה לנקות', () async {
    final tag = _tagDir(Directory(manager.mirrorDir), '0.9.96+736');
    await _write(p.join(tag, 'otzaria-0.9.96-windows.exe'), 'setup');

    expect((await manager.checkForUpdate()).hasStaleFullPackage, isFalse);
  });

  test('מראה ריקה אינה שגיאה', () async {
    expect((await manager.checkForUpdate()).hasStaleFullPackage, isFalse);
  });

  test('אסט אנדרואיד אינו נמחק בטעות', () async {
    final tag = _tagDir(Directory(manager.mirrorDir), '0.9.96+736');
    await _write(p.join(tag, 'otzaria-android-full.zip'), 'apk');

    expect((await manager.checkForUpdate()).hasStaleFullPackage, isFalse);
  });
}
