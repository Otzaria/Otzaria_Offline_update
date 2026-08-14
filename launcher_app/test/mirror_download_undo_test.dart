// ביטול הורדה מוחק את מה שההורדה הביאה — ולא את מה שכבר היה על הכונן.
// זו ההבחנה היחידה שכל המחלקה קיימת בשבילה, ולכן היא נבדקת מכל הכיוונים.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/mirror_download_undo.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String mirrorDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('undo_test');
    mirrorDir = p.join(tempDir.path, 'mirror', 'library');
    // ה-best-effort של המחלקה כותב ליומן, ובלי אתחול `instance` זורק.
    await AppLogger.init(tempDir.path);
  });

  tearDown(() async {
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    tempDir.deleteSync(recursive: true);
  });

  File file(String relative) => File(p.join(mirrorDir, relative));

  void write(String relative, String content) {
    final f = file(relative);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  test('נכס שירד בהורדה הזו נמחק, ונכס קודם נשאר', () async {
    write('assets/v1/patch-v1-v2.zst', 'קובץ מהורדה קודמת');

    final undo = await MirrorDownloadUndo.capture([mirrorDir]);
    write('assets/v2/patch-v2-v3.zst', 'ירד עכשיו');

    await undo.revert();

    expect(file('assets/v1/patch-v1-v2.zst').existsSync(), isTrue);
    expect(file('assets/v2/patch-v2-v3.zst').existsSync(), isFalse);
    // גם התיקייה שההורדה יצרה נעלמת — לא רק הקובץ שבתוכה.
    expect(Directory(p.join(mirrorDir, 'assets', 'v2')).existsSync(), isFalse);
  });

  test('תיקייה שלא הייתה כלל לפני ההורדה נמחקת כולה', () async {
    final undo = await MirrorDownloadUndo.capture([mirrorDir]);
    write('assets/v3/seforim.db.zst', 'ההורדה הראשונה');

    await undo.revert();

    expect(Directory(mirrorDir).existsSync(), isFalse);
  });

  test('מניפסט שנכתב מחדש חוזר לתוכנו הקודם', () async {
    write('releases.json', '{"releases":["v1"]}');

    final undo = await MirrorDownloadUndo.capture([mirrorDir]);
    write('releases.json', '{"releases":["v1","v2"]}');
    write('assets/v2/patch-v1-v2.zst', 'ירד עכשיו');

    await undo.revert();

    // המניפסט החדש מתאר נכס שנמחק זה עתה; בלי ההחזרה הזו המחשב הלא-מקוון
    // היה קורא מראה שמצביעה על קובץ שאינו שם.
    expect(file('releases.json').readAsStringSync(), '{"releases":["v1"]}');
  });

  test('נכס חלקי שההורדה המשיכה נחתך חזרה לאורכו, ונשאר לחידוש', () async {
    write('assets/v1/seforim.db.zst', '0123456789');
    write('assets/v1/seforim.db.zst.resume', 'token');

    final undo = await MirrorDownloadUndo.capture([mirrorDir]);
    file('assets/v1/seforim.db.zst').writeAsStringSync('0123456789abcdefghij');

    await undo.revert();

    final partial = file('assets/v1/seforim.db.zst');
    expect(partial.existsSync(), isTrue);
    expect(partial.readAsStringSync(), '0123456789');
    expect(file('assets/v1/seforim.db.zst.resume').existsSync(), isTrue);
  });

  test('כמה תיקיות מראה מנוקות באותו ביטול', () async {
    final companionsDir = p.join(tempDir.path, 'mirror', 'companions');
    Directory(companionsDir).createSync(recursive: true);
    write('releases.json', '{}');

    final undo = await MirrorDownloadUndo.capture([mirrorDir, companionsDir]);
    write('assets/v9/patch.zst', 'ירד עכשיו');
    File(p.join(companionsDir, 'lexical.db')).writeAsStringSync('ירד עכשיו');

    await undo.revert();

    expect(file('releases.json').existsSync(), isTrue);
    expect(file('assets/v9/patch.zst').existsSync(), isFalse);
    expect(File(p.join(companionsDir, 'lexical.db')).existsSync(), isFalse);
    // התיקייה עצמה כן הייתה שם לפני ההורדה, ולכן נשארת.
    expect(Directory(companionsDir).existsSync(), isTrue);
  });

  test('ביטול שלא הביא כלום אינו נוגע בדבר', () async {
    write('releases.json', '{"releases":["v1"]}');
    write('assets/v1/patch.zst', 'קובץ קודם');

    final undo = await MirrorDownloadUndo.capture([mirrorDir]);
    await undo.revert();

    expect(file('releases.json').readAsStringSync(), '{"releases":["v1"]}');
    expect(file('assets/v1/patch.zst').readAsStringSync(), 'קובץ קודם');
  });
}
