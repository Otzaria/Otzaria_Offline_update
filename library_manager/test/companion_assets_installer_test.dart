import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/zstd_fixtures.dart';

/// הפער שנסגר כאן: אוצריא מרעננת בכל עדכון ספרייה שלושה קבצים נלווים
/// **מהרשת**. במחשב הלא-מקוון אין רשת, ולכן הם נוסעים במראה ומותקנים כאן —
/// לאותם יעדים ועם אותם סימוני-גרסה שאוצריא בודקת.
void main() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();

  late Directory tempDir;
  late String mirrorDir;
  late String libraryDir;
  late String dbPath;
  const installer = CompanionAssetsInstaller();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('companions-test-');
    mirrorDir = p.join(tempDir.path, 'mirror', 'companions');
    libraryDir = p.join(tempDir.path, 'books');
    dbPath = p.join(libraryDir, 'seforim.db');
    await Directory(mirrorDir).create(recursive: true);
    await Directory(libraryDir).create(recursive: true);
    await File(dbPath).writeAsString('db');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// אורכו האמיתי של קובץ במראה. הרשומה מצהירה עליו, ו-`pendingWork` פוסלת
  /// רשומה שאינה תואמת — בדיוק כמו שכתיבת המראה מבטיחה.
  int mirrorSize(String fileName) =>
      File(p.join(mirrorDir, fileName)).lengthSync();

  /// הפריטים שהבדיקה תציע. [delivered] הוא מה שהתקנה קודמת כבר מסרה כאן.
  Future<Set<CompanionAsset>> pending([
    Map<CompanionAsset, String> delivered = const {},
  ]) async =>
      (await installer.pendingWork(
        mirrorDir: mirrorDir,
        dbPath: dbPath,
        delivered: delivered,
      ))
          .pending;

  Future<void> writeManifest(Map<String, dynamic> entries) async {
    await File(p.join(mirrorDir, CompanionMirrorManifest.fileName))
        .writeAsString(jsonEncode({
      'formatVersion': 1,
      'exportedAt': '2026-08-09T00:00:00.000Z',
      ...entries,
    }));
  }

  test('אין מראה — דיווח ריק ואין עבודה ממתינה', () async {
    final report = await installer.install(
      mirrorDir: mirrorDir,
      dbPath: dbPath,
    );
    expect(report.outcomes, isEmpty);
    expect(await pending(), isEmpty);
  });

  group('מילון החיפוש', () {
    setUp(() async {
      await File(p.join(mirrorDir, 'lexical.db')).writeAsString('LEXICAL');
      await writeManifest({
        'dictionary': {'fileName': 'lexical.db', 'size': 7, 'tag': 'v2'},
      });
    });

    test('מותקן לצד המסד עם סימון גרסה, ובריצה שנייה כבר מעודכן', () async {
      expect(await pending(), {CompanionAsset.dictionary});

      final first =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(first.outcomes[CompanionAsset.dictionary],
          CompanionInstallOutcome.installed);
      expect(
        File(p.join(libraryDir, 'lexical.db')).readAsStringSync(),
        'LEXICAL',
      );
      // הסימון שאוצריא קוראת (`<dest>.version`).
      expect(
        File(p.join(libraryDir, 'lexical.db.version')).readAsStringSync(),
        'v2',
      );

      final second =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(second.outcomes[CompanionAsset.dictionary],
          CompanionInstallOutcome.alreadyUpToDate);
      expect(await pending(), isEmpty);
      // מה שנרשם כ"נמסר כאן" — הראיה שמונעת הצעה חוזרת בהמשך.
      expect(second.delivered[CompanionAsset.dictionary], 'v2');
    });

    test('תג שונה במראה מחליף את הקובץ המותקן', () async {
      await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      await File(p.join(mirrorDir, 'lexical.db')).writeAsString('NEWER');
      await writeManifest({
        'dictionary': {'fileName': 'lexical.db', 'size': 5, 'tag': 'v3'},
      });

      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.dictionary],
          CompanionInstallOutcome.installed);
      expect(
        File(p.join(libraryDir, 'lexical.db')).readAsStringSync(),
        'NEWER',
      );
    });

    /// הלולאה השקטה: נכס קטוע (הורדה שנקטעה והשאירה 0 בתים) הותקן, סומן,
    /// ודווח `installed` — בעוד הפרדיקט של אוצריא פוסל אותו לנצח. התוצאה
    /// הייתה "יש עדכון לספרייה" בכל פתיחה, בלי שגיאה ובלי שורה בלוג.
    test('מילון ריק במראה מדווח ככשל, לא כהתקנה שהצליחה', () async {
      await File(p.join(mirrorDir, 'lexical.db')).writeAsBytes(const []);
      await writeManifest({
        'dictionary': {'fileName': 'lexical.db', 'size': 0, 'tag': 'v9'},
      });

      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.dictionary],
          CompanionInstallOutcome.failed);
      expect(report.errors[CompanionAsset.dictionary], isNotNull);
      expect(report.delivered, isEmpty);
      // הקובץ שבמראה עצמו קטוע, ולכן זו אינה הצעה שאפשר להשלים כאן: היא
      // מדווחת כ"חסר במראה" ואינה חוזרת כ"יש עדכון" בכל פתיחה.
      final report2 = await installer.pendingWork(
        mirrorDir: mirrorDir,
        dbPath: dbPath,
      );
      expect(report2.pending, isEmpty);
      expect(report2.unavailable, {CompanionAsset.dictionary});
    });
  });

  group('קטלוג otzar-HB', () {
    /// מסד קטלוג אמיתי — האימות קורא ממנו `db_meta.version`, בדיוק כמו
    /// `ExternalCatalogRepository.getCurrentDatabaseVersion`.
    void writeCatalogDb(String path, {int? version}) {
      final db = sqlite3.sqlite3.open(path);
      db.execute('CREATE TABLE IF NOT EXISTS db_meta '
          '(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      if (version != null) {
        db.execute(
          'INSERT OR REPLACE INTO db_meta (key, value) VALUES (?, ?)',
          ['version', '$version'],
        );
      }
      db.close();
    }

    test('מותקן והגרסה מוחתמת ב-db_meta', () async {
      writeCatalogDb(p.join(mirrorDir, 'otzar-HB_catalog.db'));
      await writeManifest({
        'catalog': {
          'fileName': 'otzar-HB_catalog.db',
          'size': 1,
          'version': 42,
        },
      });

      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.catalog],
          CompanionInstallOutcome.installed);

      final installed = p.join(libraryDir, 'otzar-HB_catalog.db');
      final db =
          sqlite3.sqlite3.open(installed, mode: sqlite3.OpenMode.readOnly);
      final rows = db.select("SELECT value FROM db_meta WHERE key = 'version'");
      db.close();
      expect(rows.first.values.first, '42');
    });

    test('גרסה מותקנת חדשה או שווה — לא נוגעים בקובץ', () async {
      writeCatalogDb(p.join(mirrorDir, 'otzar-HB_catalog.db'));
      writeCatalogDb(p.join(libraryDir, 'otzar-HB_catalog.db'), version: 42);
      await writeManifest({
        'catalog': {
          'fileName': 'otzar-HB_catalog.db',
          'size': 1,
          'version': 42,
        },
      });

      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.catalog],
          CompanionInstallOutcome.alreadyUpToDate);
    });
  });

  group('תלמוד בבלי', () {
    /// ארכיון `tar.zst` אמיתי שמכיל את התיקייה `תלמוד בבלי/` — בדיוק המבנה
    /// שאוצריא מחלצת אל תיקיית האב.
    void writeTalmudArchive(String path, List<String> fileNames) {
      final archive = Archive();
      for (final name in fileNames) {
        final bytes = utf8.encode('pdf:$name');
        archive.add(ArchiveFile.bytes('תלמוד בבלי/$name', bytes));
      }
      final tar = TarEncoder().encodeBytes(archive);
      File(path).writeAsBytesSync(
        compressWithZstd(bindings!, Uint8List.fromList(tar)),
      );
    }

    test('מחולץ לתיקיית הספרייה, עם סימון הגרסה בסוף', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      writeTalmudArchive(
        p.join(mirrorDir, 'talmud_bavli_latest.tar.zst'),
        ['ברכות.pdf', 'שבת.pdf'],
      );
      await writeManifest({
        'talmud': {
          'fileName': 'talmud_bavli_latest.tar.zst',
          'size': mirrorSize('talmud_bavli_latest.tar.zst'),
          'tag': 'v1',
          'sha256': 'abc123',
          'compressed': true,
        },
      });

      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.installed);

      final talmudDir = p.join(libraryDir, 'תלמוד בבלי');
      expect(File(p.join(talmudDir, 'ברכות.pdf')).existsSync(), isTrue);
      expect(File(p.join(talmudDir, 'שבת.pdf')).existsSync(), isTrue);
      // הסימון נכתב עם ה-digest, כמו ב-`CompanionAssetsService`.
      expect(
        File(p.join(talmudDir, '.version')).readAsStringSync(),
        'abc123',
      );
      // אין שאריות של ה-tar הזמני.
      expect(
        Directory(libraryDir)
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path)),
        isNot(contains('talmud_bavli_latest.tar.zst.tar')),
      );

      final second =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(second.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.alreadyUpToDate);
    });

    test('סימון "installing" שנשאר מהתקנה שנקטעה מפעיל התקנה מחדש', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      writeTalmudArchive(
        p.join(mirrorDir, 'talmud_bavli_latest.tar.zst'),
        ['ברכות.pdf'],
      );
      await writeManifest({
        'talmud': {
          'fileName': 'talmud_bavli_latest.tar.zst',
          'size': mirrorSize('talmud_bavli_latest.tar.zst'),
          'sha256': 'abc123',
          'compressed': true,
        },
      });
      final talmudDir = Directory(p.join(libraryDir, 'תלמוד בבלי'));
      await talmudDir.create(recursive: true);
      await File(p.join(talmudDir.path, '.version'))
          .writeAsString('installing');

      expect(await pending(), {CompanionAsset.talmud});
      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.installed);
    });

    /// רשומה בלי digest ובלי תג אינה נושאת מידע גרסה. ההתקנה כתבה עבורה סימון
    /// ריק והפרדיקט פסל אותו — כלומר חילוץ של ~450MB בכל פתיחה, לנצח.
    test('רשומה בלי digest ובלי תג — הריצה השנייה כבר מעודכנת', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      writeTalmudArchive(
        p.join(mirrorDir, 'talmud_bavli_latest.tar.zst'),
        ['ברכות.pdf'],
      );
      await writeManifest({
        'talmud': {
          'fileName': 'talmud_bavli_latest.tar.zst',
          'size': mirrorSize('talmud_bavli_latest.tar.zst'),
          'compressed': true,
        },
      });

      final first =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(first.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.installed);
      final second =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(second.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.alreadyUpToDate);
      expect(await pending(), isEmpty);
    });

    /// המחיקה קדמה לחילוץ, ולכן ארכיון קטוע השאיר את המשתמש בלי התלמוד שכבר
    /// היה לו — ועם סימון 'installing' שמזמין את אותו כשל בכל פתיחה.
    test('ארכיון פגום אינו מוחק את התלמוד שכבר מותקן', () async {
      final talmudDir = Directory(p.join(libraryDir, 'תלמוד בבלי'));
      await talmudDir.create(recursive: true);
      await File(p.join(talmudDir.path, 'ברכות.pdf')).writeAsString('ישן');
      await File(p.join(talmudDir.path, '.version')).writeAsString('old');
      await File(p.join(mirrorDir, 'talmud_bavli_latest.tar.zst'))
          .writeAsString('זה בכלל לא zstd');
      await writeManifest({
        'talmud': {
          'fileName': 'talmud_bavli_latest.tar.zst',
          'size': 1,
          'sha256': 'new-digest',
          'compressed': true,
        },
      });

      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.failed);
      expect(
          File(p.join(talmudDir.path, 'ברכות.pdf')).readAsStringSync(), 'ישן');
      expect(
        File(p.join(talmudDir.path, '.version')).readAsStringSync(),
        'old',
      );
    });
  });

  /// **הלולאה של issue הלוג מ-0.14.** המסד מעודכן (`kind=none, 27→27`), ובכל
  /// זאת `status=updateAvailable` בכל פתיחה, כי `companions=true`. הסיבה:
  /// סימוני התלמוד והמילון הם digest/תג ואין ביניהם סדר, ולכן קובץ שאוצריא
  /// עצמה רעננה מהרשת נראה בדיוק כמו קובץ ישן.
  group('קובץ שהוחלף מחוץ ללאנצ׳ר', () {
    setUp(() async {
      await File(p.join(mirrorDir, 'lexical.db')).writeAsString('LEXICAL');
      await writeManifest({
        'dictionary': {'fileName': 'lexical.db', 'size': 7, 'tag': 'v2'},
      });
    });

    test('מראה שכבר נמסרה כאן אינה מוצעת שוב אחרי שאוצריא החליפה את הקובץ',
        () async {
      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.delivered[CompanionAsset.dictionary], 'v2');
      final delivered = {CompanionAsset.dictionary: 'v2'};

      // אוצריא הורידה מהרשת מילון אחר וכתבה סימון משלה.
      await File(p.join(libraryDir, 'lexical.db.version')).writeAsString('v7');

      // בלי הרשומה זו הייתה הצעה שחוזרת בכל פתיחה — ולחיצה עליה הייתה
      // מורידה את המילון בחזרה ל-v2.
      expect(await pending(), {CompanionAsset.dictionary});
      expect(await pending(delivered), isEmpty);
    });

    test('פריט שנמחק אחרי שנמסר כן חוזר להצעה', () async {
      await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      final delivered = {CompanionAsset.dictionary: 'v2'};
      expect(await pending(delivered), isEmpty);

      await File(p.join(libraryDir, 'lexical.db')).delete();
      expect(await pending(delivered), {CompanionAsset.dictionary});
    });

    test('מראה חדשה יותר מוצעת גם אחרי שנמסרה קודמת', () async {
      await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      final delivered = {CompanionAsset.dictionary: 'v2'};
      await File(p.join(mirrorDir, 'lexical.db')).writeAsString('NEWER');
      await writeManifest({
        'dictionary': {'fileName': 'lexical.db', 'size': 5, 'tag': 'v3'},
      });

      expect(await pending(delivered), {CompanionAsset.dictionary});
    });
  });

  /// רשומה שהקובץ שלה לא נסע לכונן: כהצעה היא הייתה חוזרת בכל פתיחה ונכשלת
  /// בכל לחיצה, כי אין כאן ממה להתקין.
  test('רשומה שהקובץ שלה חסר במראה מדווחת כחסרה ולא כהצעה', () async {
    await writeManifest({
      'dictionary': {'fileName': 'lexical.db', 'size': 7, 'tag': 'v2'},
    });

    final report = await installer.pendingWork(
      mirrorDir: mirrorDir,
      dbPath: dbPath,
    );
    expect(report.pending, isEmpty);
    expect(report.unavailable, {CompanionAsset.dictionary});
    expect(report.hasPending, isFalse);
  });

  test('רשומה שהקובץ שלה קטוע במראה (אורך שאינו תואם) אינה הצעה', () async {
    await File(p.join(mirrorDir, 'lexical.db')).writeAsString('חלקי');
    await writeManifest({
      'dictionary': {'fileName': 'lexical.db', 'size': 9999, 'tag': 'v2'},
    });

    final report = await installer.pendingWork(
      mirrorDir: mirrorDir,
      dbPath: dbPath,
    );
    expect(report.pending, isEmpty);
    expect(report.unavailable, {CompanionAsset.dictionary});
  });

  test('כשל בפריט אחד אינו מונע את השאר', () async {
    // התלמוד מוצהר במניפסט אבל הקובץ חסר במראה; המילון קיים ותקין.
    await File(p.join(mirrorDir, 'lexical.db')).writeAsString('LEXICAL');
    await writeManifest({
      'talmud': {
        'fileName': 'talmud_bavli_latest.tar.zst',
        'size': 1,
        'tag': 'v1',
        'compressed': true,
      },
      'dictionary': {'fileName': 'lexical.db', 'size': 7, 'tag': 'v2'},
    });

    final report =
        await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
    expect(
        report.outcomes[CompanionAsset.talmud], CompanionInstallOutcome.failed);
    expect(report.outcomes[CompanionAsset.dictionary],
        CompanionInstallOutcome.installed);
    expect(File(p.join(libraryDir, 'lexical.db')).existsSync(), isTrue);
  });
}
