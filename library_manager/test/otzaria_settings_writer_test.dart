import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:library_manager/library_manager.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('OtzariaSettingsWriter', () {
    late Directory tempDir;
    late String dataRoot;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-settings-w-');
      dataRoot = p.join(tempDir.path, 'otzaria');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    const writer = OtzariaSettingsWriter();
    const reader = OtzariaSettingsReader();

    // הבדיקה האמיתית היא ש**הקורא** — שהוא תרגום של
    // `DatabaseConstants.getDatabasePath` — מוצא אחר כך את אותו קובץ.
    test('כתיבה מייצרת בדיוק את הנתיב שאוצריא תחשב', () async {
      await Directory(dataRoot).create(recursive: true);
      final dbPath = p.join(dataRoot, 'books', 'seforim.db');

      expect(
        await writer.pointLibraryAt(dataRootPath: dataRoot, dbPath: dbPath),
        isTrue,
      );

      final settings = await reader.read(dataRoot);
      expect(settings, isNotNull);
      expect(settings!.libraryPath, p.join(dataRoot, 'books'));
      // נכתב כמחרוזת ריקה (כמו באוצריא), והקורא מנרמל ריק ל-null.
      expect(settings.libraryFolderName, isNull);
      expect(settings.resolveDbPath(path: p.context), dbPath);
    });

    test('הערכים נכתבים לקופסה האמיתית של אוצריא, לא לעותק', () async {
      await Directory(dataRoot).create(recursive: true);
      await writer.pointLibraryAt(
        dataRootPath: dataRoot,
        dbPath: p.join(dataRoot, 'books', 'seforim.db'),
      );

      Hive.init(dataRoot);
      final box = await Hive.openBox<dynamic>(
        OtzariaSettingsReader.boxName,
        path: dataRoot,
      );
      expect(
        box.get(OtzariaSettingsReader.keyLibraryPath),
        p.join(dataRoot, 'books'),
      );
      await box.close();
    });

    // נתיב יחסי היה נכתב כמו שהוא, ואוצריא הייתה מחפשת אותו יחסית לתיקיית
    // העבודה שלה — כלומר במקום אקראי לחלוטין.
    test('נתיב יחסי נדחה ואינו נכתב', () async {
      await Directory(dataRoot).create(recursive: true);

      expect(
        await writer.pointLibraryAt(
          dataRootPath: dataRoot,
          dbPath: p.join('books', 'seforim.db'),
        ),
        isFalse,
      );
      expect(await reader.read(dataRoot), isNull);
    });

    // אוצריא מותקנת אך מעולם לא רצה — שורש הנתונים עוד לא קיים.
    test('allowCreate יוצר את שורש הנתונים; בלעדיו לא נוגעים בדיסק', () async {
      final dbPath = p.join(dataRoot, 'books', 'seforim.db');

      expect(
        await writer.pointLibraryAt(dataRootPath: dataRoot, dbPath: dbPath),
        isFalse,
      );
      expect(await Directory(dataRoot).exists(), isFalse);

      expect(
        await writer.pointLibraryAt(
          dataRootPath: dataRoot,
          dbPath: dbPath,
          allowCreate: true,
        ),
        isTrue,
      );
      expect((await reader.read(dataRoot))?.libraryPath,
          p.join(dataRoot, 'books'));
    });
  });
}
