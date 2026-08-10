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
    expect(
      await installer.hasPendingWork(mirrorDir: mirrorDir, dbPath: dbPath),
      isFalse,
    );
  });

  group('מילון החיפוש', () {
    setUp(() async {
      await File(p.join(mirrorDir, 'lexical.db')).writeAsString('LEXICAL');
      await writeManifest({
        'dictionary': {'fileName': 'lexical.db', 'size': 7, 'tag': 'v2'},
      });
    });

    test('מותקן לצד המסד עם סימון גרסה, ובריצה שנייה כבר מעודכן', () async {
      expect(
        await installer.hasPendingWork(mirrorDir: mirrorDir, dbPath: dbPath),
        isTrue,
      );

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
      expect(
        await installer.hasPendingWork(mirrorDir: mirrorDir, dbPath: dbPath),
        isFalse,
      );
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
          'size': 1,
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
          'size': 1,
          'sha256': 'abc123',
          'compressed': true,
        },
      });
      final talmudDir = Directory(p.join(libraryDir, 'תלמוד בבלי'));
      await talmudDir.create(recursive: true);
      await File(p.join(talmudDir.path, '.version'))
          .writeAsString('installing');

      expect(
        await installer.hasPendingWork(mirrorDir: mirrorDir, dbPath: dbPath),
        isTrue,
      );
      final report =
          await installer.install(mirrorDir: mirrorDir, dbPath: dbPath);
      expect(report.outcomes[CompanionAsset.talmud],
          CompanionInstallOutcome.installed);
    });
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
