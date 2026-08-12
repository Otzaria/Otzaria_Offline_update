import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/zstd_fixtures.dart';

/// בדיקות ל-[LibraryUpdateApplier] — הרכיב היחיד שכותב בפועל ל-`seforim.db`
/// החי. שלושת הדברים שנשמרים כאן הם בדיוק אלה שכבר נשברו פעם: כלל ה-isolate
/// (ארגומנטים שניתן לשלוח + `AppL10n` שאינו נורש), מסלול ה-fullDownload
/// שזורם לקובץ צדדי ורק אז מחליף, וחסימת עדכון כשאוצריא פתוחה.
void main() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();

  late Directory tempDir;
  late String dbPath;
  late LibraryUpdateApplier applier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library-applier-test-');
    dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    applier = LibraryUpdateApplier(processGuard: const _FakeGuard(false));
  });

  tearDown(() async {
    applier.dispose();
    AppL10n.use(AppLanguage.hebrew);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// מייצר תוכנית fullDownload שמצביעה על קובץ `.zst` **מקומי** — בדיוק כמו
  /// מראה offline, שבה ה-`downloadUrl` הוא נתיב על הדיסק ולא כתובת רשת.
  LibraryUpdatePlan fullPlanFor(
    String compressedPath, {
    int localVersion = 4,
    int? targetVersion = 5,
    String? digest,
  }) {
    return LibraryUpdatePlan.fullDownload(
      localVersion: localVersion,
      targetVersion: targetVersion,
      asset: ReleaseAsset(
        name: 'seforim.db.zst',
        downloadUrl: compressedPath,
        size: File(compressedPath).lengthSync(),
        id: 12345,
        digest: digest,
      ),
      releaseTag: 'v${targetVersion ?? 0}',
    );
  }

  String writeCompressed(String name, Uint8List payload) {
    final path = p.join(tempDir.path, name);
    File(path).writeAsBytesSync(compressWithZstd(bindings!, payload));
    return path;
  }

  group('כלל ה-isolate', () {
    test('הארגומנטים של _isolateApplyPatch ניתנים לשליחה ל-isolate', () async {
      final manifest = _manifest();
      final args = (dbPath, '$dbPath.patch', manifest, AppLanguage.english);

      // סבב מלא: שליחה ל-isolate וחזרה. אם אחד מהטיפוסים לא היה sendable,
      // כאן הייתה נזרקת "Illegal argument in isolate message" — הקריסה
      // שהפילה את המנגנון בעבר.
      final back = await _roundTripThroughIsolate(args);

      expect(back.$1, dbPath);
      expect(back.$2, '$dbPath.patch');
      expect(back.$3, manifest);
      expect(back.$4, AppLanguage.english);
    });

    test('בקרה שלילית: סוגר שתופס אובייקט שאינו ניתן לשליחה אכן נכשל',
        () async {
      // מוכיח שהבדיקה שלמעלה באמת מבחינה: סוגר שגורר איתו אובייקט לא-sendable
      // (כאן ReceivePort) זורק בדיוק את השגיאה שהפילה את המנגנון בעבר.
      final port = ReceivePort();
      await expectLater(
        Isolate.run(() => port.hashCode),
        throwsArgumentError,
      );
      port.close();
    });

    test('Isolate.run אינו יורש את AppL10n — חייבים להעביר שפה ולהפעילה',
        () async {
      AppL10n.use(AppLanguage.english);

      // בלי העברה מפורשת ההודעה שנוצרת בתוך ה-isolate חוזרת לעברית.
      expect(
        await _mirrorMissingInIsolate(null),
        AppL10n.stringsFor(AppLanguage.hebrew).libraryDomain.mirrorMissing,
      );
      // עם `AppL10n.use(language)` בראש הפונקציה — התרגום הנכון.
      expect(
        await _mirrorMissingInIsolate(AppLanguage.english),
        AppL10n.stringsFor(AppLanguage.english).libraryDomain.mirrorMissing,
      );
    });
  });

  group('חסימה כשאוצריא רצה', () {
    test('applyFullDownload נחסם ולא נוגע בדיסק', () async {
      applier = LibraryUpdateApplier(processGuard: const _FakeGuard(true));
      File(dbPath).writeAsStringSync('OLD');
      final compressedPath = p.join(tempDir.path, 'seforim.db.zst');
      File(compressedPath).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
        ),
        throwsA(isA<OtzariaIsRunningException>()),
      );
      expect(File(dbPath).readAsStringSync(), 'OLD');
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
    });

    test('applyDelta נחסם לפני ההורדה הראשונה', () async {
      applier = LibraryUpdateApplier(processGuard: const _FakeGuard(true));

      await expectLater(
        applier.applyDelta(
          plan: LibraryUpdatePlan.delta(
            localVersion: 4,
            targetVersion: 5,
            steps: [_edge()],
          ),
          dbPath: dbPath,
        ),
        throwsA(isA<OtzariaIsRunningException>()),
      );
    });
  });

  group('שמירת סוג התוכנית', () {
    setUp(() {
      applier = LibraryUpdateApplier(processGuard: const _FakeGuard(false));
    });

    test('applyDelta על תוכנית שאינה delta נכשל מיד', () async {
      await expectLater(
        applier.applyDelta(
          plan: LibraryUpdatePlan.none(localVersion: 5),
          dbPath: dbPath,
        ),
        throwsA(isA<LibraryApplyException>()),
      );
    });

    test('applyFullDownload על תוכנית שאינה fullDownload נכשל מיד', () async {
      await expectLater(
        applier.applyFullDownload(
          plan: LibraryUpdatePlan.none(localVersion: 5),
          dbPath: dbPath,
        ),
        throwsA(isA<LibraryApplyException>()),
      );
    });
  });

  group('applyDelta', () {
    setUp(() {
      applier = LibraryUpdateApplier(processGuard: const _FakeGuard(false));
    });

    test('קובץ patch שאין לו כתובת — ההודעה מגיעה מ-otzaria_l10n', () async {
      final edge = PatchEdge(
        manifest: _manifest(),
        patchFileUrls: const {}, // אין כתובת לקובץ שה-manifest דורש
        manifestUrl: 'manifest.json',
      );

      await expectLater(
        applier.applyDelta(
          plan: LibraryUpdatePlan.delta(
            localVersion: 4,
            targetVersion: 5,
            steps: [edge],
          ),
          dbPath: dbPath,
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.patchUrlMissing('patch-v4-v5.db.zst'),
          ),
        ),
      );
    });

    test('ביטול נבדק לפני כל שלב, עם ההודעה מ-otzaria_l10n', () async {
      await expectLater(
        applier.applyDelta(
          plan: LibraryUpdatePlan.delta(
            localVersion: 4,
            targetVersion: 5,
            steps: [_edge()],
          ),
          dbPath: dbPath,
          isCancelled: () => true,
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.updateCancelled,
          ),
        ),
      );
    });

    test('תוכנית delta ריקה מסיימת בשלב done בלי לגעת ב-DB', () async {
      final stages = <LibraryApplyStage>[];
      await applier.applyDelta(
        plan: LibraryUpdatePlan.delta(
          localVersion: 5,
          targetVersion: 5,
          steps: const [],
        ),
        dbPath: dbPath,
        onProgress: (progress) => stages.add(progress.stage),
      );

      expect(stages, [LibraryApplyStage.done]);
      expect(File(dbPath).existsSync(), isFalse);
    });
  });

  group('applyFullDownload (מסלול זרימה)', () {
    setUp(() {
      applier = LibraryUpdateApplier(
        processGuard: const _FakeGuard(false),
        verifyExtractedDb: _fakeVerifier(5),
      );
    });

    test('מחלץ לקובץ צדדי ומחליף ב-rename — ה-DB הישן שלם עד הרגע האחרון',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // 3MB — מספיק כדי שהחילוץ יעבור כמה סבבי חוצץ, כלומר מסלול הזרימה
      // האמיתי ולא one-shot בזיכרון.
      final payload = pseudoRandomBytes(3 * 1024 * 1024);
      final compressedPath = writeCompressed('seforim.db.zst', payload);
      File(dbPath).writeAsStringSync('OLD DB');
      // שאריות של אוצריא שקרסה — חייבות להיעלם יחד עם ה-DB הישן.
      File('$dbPath-wal').writeAsStringSync('wal');
      File('$dbPath-shm').writeAsStringSync('shm');

      final stages = <LibraryApplyStage>[];
      var stagedFileLength = -1;
      var dbStillOldWhileStaging = false;
      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath),
        dbPath: dbPath,
        onProgress: (progress) {
          // שלב ההורדה מדווח פר-צ'אנק; מעניין כאן רק סדר השלבים.
          if (stages.isEmpty || stages.last != progress.stage) {
            stages.add(progress.stage);
          }
          if (progress.stage == LibraryApplyStage.writingFullDb) {
            // ברגע הזה החילוץ כבר הסתיים אל `<db>.new`, וה-DB הישן עדיין
            // במקומו — זה מה שהופך את ההחלפה ל-rename ולא לכתיבה על החי.
            stagedFileLength = File('$dbPath.new').lengthSync();
            dbStillOldWhileStaging =
                File(dbPath).readAsStringSync() == 'OLD DB';
          }
        },
      );

      expect(stagedFileLength, payload.length);
      expect(dbStillOldWhileStaging, isTrue);
      expect(File(dbPath).readAsBytesSync(), payload);
      // האימות קודם לכתיבה — מסד פגום נעצר בעוד ה-DB החי שלם, כמו באוצריא.
      expect(stages, [
        LibraryApplyStage.downloadingFullDb,
        LibraryApplyStage.decompressingFullDb,
        LibraryApplyStage.verifying,
        LibraryApplyStage.writingFullDb,
        LibraryApplyStage.done,
      ]);

      // אין שאריות: לא הקובץ הדחוס, לא הצדדי, לא גיבוי/סימון, ולא wal/shm.
      expect(File('$dbPath.new').existsSync(), isFalse);
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File('$dbPath.applying').existsSync(), isFalse);
      expect(File('$dbPath-wal').existsSync(), isFalse);
      expect(File('$dbPath-shm').existsSync(), isFalse);
    });

    test('התקנה טרייה: יוצר את התיקייה וכותב DB חדש בלי גיבוי', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final payload = pseudoRandomBytes(64 * 1024);
      final compressedPath = writeCompressed('fresh.db.zst', payload);
      final freshDbPath = p.join(tempDir.path, 'new-library', 'seforim.db');

      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath, localVersion: 0),
        dbPath: freshDbPath,
      );

      expect(File(freshDbPath).readAsBytesSync(), payload);
      // אין DB קודם — אין מה לגבות, ולכן גם אין סימון/גיבוי בכלל.
      expect(File('$freshDbPath.backup').existsSync(), isFalse);
      expect(File('$freshDbPath.applying').existsSync(), isFalse);
    });

    test('שאריות `<db>.new` מריצה שקרסה נדרסות במקום להיכתב לתוך ה-DB',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final payload = pseudoRandomBytes(128 * 1024);
      final compressedPath = writeCompressed('seforim.db.zst', payload);
      File(dbPath).writeAsStringSync('OLD DB');
      // בדיוק מה שנשאר אחרי קריסה באמצע apply קודם.
      File('$dbPath.new').writeAsStringSync('חצי מסד מריצה שקרסה');
      File('$dbPath.download.zst').writeAsStringSync('הורדה חלקית');

      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath),
        dbPath: dbPath,
      );

      expect(File(dbPath).readAsBytesSync(), payload);
      expect(File('$dbPath.new').existsSync(), isFalse);
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
    });

    // אין גיבוי בשום שלב — גם לא באמצע ההחלה, כשה-DB הישן עוד קיים.
    test('החלפת DB קיים אינה יוצרת עותק גיבוי בשום שלב', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final payload = pseudoRandomBytes(32 * 1024);
      final compressedPath = writeCompressed('seforim.db.zst', payload);
      File(dbPath).writeAsStringSync('OLD DB');
      var sawBackup = false;

      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath),
        dbPath: dbPath,
        onProgress: (progress) {
          if (File('$dbPath.backup').existsSync()) sawBackup = true;
        },
      );

      expect(sawBackup, isFalse);
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File(dbPath).readAsBytesSync(), payload);
    });

    test('קובץ דחוס פגום: זורק ומנקה את שני הקבצים הזמניים', () async {
      final compressedPath = p.join(tempDir.path, 'corrupt.db.zst');
      // ראש frame תקין של zstd ואחריו זבל — עובר את בדיקת הגודל ונופל בחילוץ.
      File(compressedPath).writeAsBytesSync(Uint8List.fromList([
        0x28,
        0xB5,
        0x2F,
        0xFD,
        ...List<int>.filled(64, 0x5A),
      ]));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
        ),
        throwsA(anyOf(
          isA<ZstdStreamException>(),
          isA<LibraryApplyException>(),
        )),
      );

      expect(File(dbPath).readAsStringSync(), 'OLD DB');
      expect(File('$dbPath.new').existsSync(), isFalse);
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
    });

    test('חילוץ שמפיק קובץ ריק נדחה עם ההודעה מ-otzaria_l10n', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // frame תקין לגמרי שתוכנו אפס בתים — חילוץ "מצליח" ומשאיר DB ריק.
      final compressedPath = writeCompressed('empty.db.zst', Uint8List(0));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.fullDbExtractionFailed,
          ),
        ),
      );

      expect(File(dbPath).readAsStringSync(), 'OLD DB');
      expect(File('$dbPath.new').existsSync(), isFalse);
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
    });

    test('ביטול לפני ההורדה עוצר בלי לגעת ב-DB', () async {
      final compressedPath = p.join(tempDir.path, 'seforim.db.zst');
      File(compressedPath).writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
          isCancelled: () => true,
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );
      expect(File(dbPath).readAsStringSync(), 'OLD DB');
    });

    test('digest פגום נאכף — ה-sha256 מועבר מהתוכנית להורדה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressedPath =
          writeCompressed('seforim.db.zst', pseudoRandomBytes(4096));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath, digest: 'sha256:${'a' * 64}'),
          dbPath: dbPath,
        ),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(dbPath).readAsStringSync(), 'OLD DB');
    });

    test('digest בפורמט אחר מתעלמים ממנו במקום להיכשל', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final payload = pseudoRandomBytes(4096);
      final compressedPath = writeCompressed('seforim.db.zst', payload);
      File(dbPath).writeAsStringSync('OLD DB');

      // רק `sha256:` נתמך; כל דבר אחר אינו אימות שאנחנו יודעים לבצע.
      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath, digest: 'md5:${'a' * 32}'),
        dbPath: dbPath,
      );

      expect(File(dbPath).readAsBytesSync(), payload);
    });
  });

  group('applyFullDownload — אימות לפני ההחלפה', () {
    test('גרסה שאינה תואמת נעצרת וה-DB הישן נשאר במקומו', () async {
      if (bindings == null) {
        applier = LibraryUpdateApplier(processGuard: const _FakeGuard(false));
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      // האימות קורא 4 בעוד התוכנית מבטיחה 5 — "המסד שהורד אינו מה שהובטח".
      // האימות קודם להחלפה, ולכן ה-DB החי כלל לא נגע.
      applier = LibraryUpdateApplier(
        processGuard: const _FakeGuard(false),
        verifyExtractedDb: _fakeVerifier(4),
      );
      final compressedPath =
          writeCompressed('seforim.db.zst', pseudoRandomBytes(64 * 1024));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.versionMismatchAfterWrite(4, 5),
          ),
        ),
      );

      expect(File(dbPath).readAsStringSync(), 'OLD DB');
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File('$dbPath.applying').existsSync(), isFalse);
      // הכשל מגיע לפני ההחלפה, ולכן שני הזמניים כבר נוקו כאן.
      expect(File('$dbPath.new').existsSync(), isFalse);
      expect(File('$dbPath.download.zst').existsSync(), isFalse);
    });

    test('תוכנית בלי גרסת יעד מדלגת על האימות', () async {
      if (bindings == null) {
        applier = LibraryUpdateApplier(processGuard: const _FakeGuard(false));
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      applier = LibraryUpdateApplier(
        processGuard: const _FakeGuard(false),
        verifyExtractedDb: _fakeVerifier(1),
      );
      final payload = pseudoRandomBytes(4096);
      final compressedPath = writeCompressed('seforim.db.zst', payload);
      File(dbPath).writeAsStringSync('OLD DB');

      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath, targetVersion: null),
        dbPath: dbPath,
      );

      expect(File(dbPath).readAsBytesSync(), payload);
    });
  });

  // האימות האמיתי (בלי הזרקה): `PRAGMA quick_check` + גרסה, כמו
  // `LibraryUpdateRepository._verifyFullDb` באוצריא.
  group('applyFullDownload — האימות האמיתי לפני ההחלפה', () {
    Uint8List buildRealDb(int dbVersion) {
      final path = p.join(tempDir.path, 'built-$dbVersion.db');
      final db = sqlite3.sqlite3.open(path);
      db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute(
        "INSERT INTO schema_meta VALUES ('db_version', '$dbVersion'), "
        "('db_schema_version', '1')",
      );
      db.close();
      return File(path).readAsBytesSync();
    }

    test('מסד תקין בגרסה הצפויה עובר ומוחלף', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final payload = buildRealDb(5);
      final compressedPath = writeCompressed('seforim.db.zst', payload);
      File(dbPath).writeAsStringSync('OLD DB');

      await applier.applyFullDownload(
        plan: fullPlanFor(compressedPath),
        dbPath: dbPath,
      );

      expect(File(dbPath).readAsBytesSync(), payload);
    });

    test('קובץ שאינו מסד sqlite נעצר ב-quick_check וה-DB החי נשאר', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressedPath =
          writeCompressed('seforim.db.zst', pseudoRandomBytes(64 * 1024));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
        ),
        throwsA(anything),
      );

      expect(File(dbPath).readAsStringSync(), 'OLD DB');
      // האימות קודם להחלפה, ולכן לא נוצרו כלל סימון/גיבוי.
      expect(File('$dbPath.applying').existsSync(), isFalse);
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File('$dbPath.new').existsSync(), isFalse);
    });

    test('מסד תקין בגרסה שאינה הצפויה נדחה לפני ההחלפה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }

      final compressedPath = writeCompressed('seforim.db.zst', buildRealDb(4));
      File(dbPath).writeAsStringSync('OLD DB');

      await expectLater(
        applier.applyFullDownload(
          plan: fullPlanFor(compressedPath),
          dbPath: dbPath,
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.versionMismatchAfterWrite(4, 5),
          ),
        ),
      );

      expect(File(dbPath).readAsStringSync(), 'OLD DB');
    });
  });

  // אימות ה-hash רץ פעם אחת, בצעד האחרון — הוא מוכיח את כל השרשרת. כאן
  // נבדק גם מה שמונע ממסד שנקטע להישאר לא-מאומת בשקט: סימון + `verifyFromHash`
  // בהחלה הבאה.
  group('applyDelta — אימות אחד בסוף השרשרת', () {
    const recovery = LibraryDbRecoveryService();
    const hasher = LogicalContentHasher();

    String buildDb(String path,
        {required int version, required List<List> rows}) {
      final db = sqlite3.sqlite3.open(path);
      db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute("INSERT INTO schema_meta VALUES ('db_version','$version'),"
          "('db_schema_version','2')");
      db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
      for (final row in rows) {
        db.execute('INSERT INTO source VALUES (?,?)', [row[0], row[1]]);
      }
      db.close();
      return path;
    }

    String hashOf(String path) {
      final db = sqlite3.sqlite3.open(path, mode: sqlite3.OpenMode.readOnly);
      try {
        return hasher.compute(db);
      } finally {
        db.close();
      }
    }

    // אותה קשת נבנית יותר מפעם אחת באותה בדיקה (שרשרת שנקטעה ואז ממשיכה),
    // ולכן שם הקובץ חייב להיות ייחודי לכל בנייה.
    var edgeSeq = 0;

    /// בונה patch אמיתי, דוחס אותו ב-libzstd ומחזיר קשת עם URL מקומי —
    /// בדיוק כמו מראה offline.
    PatchEdge buildEdge({
      required int from,
      required int to,
      required List<List> upsertRows,
      required String fromHash,
      required String toHash,
      String? urlOverride,
    }) {
      final raw = p.join(tempDir.path, 'patch_${from}_${to}_${edgeSeq++}.db');
      final db = sqlite3.sqlite3.open(raw);
      db.execute('CREATE TABLE patch_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute("INSERT INTO patch_meta VALUES ('schema_version','2'),"
          "('from_version','$from'),('to_version','$to')");
      db.execute(
          'CREATE TABLE migrations (version INTEGER PRIMARY KEY, sql TEXT)');
      db.execute(
          'CREATE TABLE upsert_schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute("INSERT INTO upsert_schema_meta VALUES ('db_version','$to')");
      db.execute(
          'CREATE TABLE upsert_source (id INTEGER PRIMARY KEY, name TEXT)');
      for (final row in upsertRows) {
        db.execute('INSERT INTO upsert_source VALUES (?,?)', [row[0], row[1]]);
      }
      db.close();

      final rawBytes = File(raw).readAsBytesSync();
      final compressed = compressWithZstd(bindings!, rawBytes);
      final zstPath = '$raw.zst';
      File(zstPath).writeAsBytesSync(compressed);
      final fileName = 'patch_$from-$to.db.zst';

      return PatchEdge(
        manifest: DeltaManifest(
          fromVersion: from,
          toVersion: to,
          fromSchemaVersion: 2,
          toSchemaVersion: 2,
          fromContentHash: fromHash,
          toContentHash: toHash,
          patchFiles: [
            PatchFileEntry(
              file: fileName,
              compression: 'zstd',
              sha256: sha256.convert(compressed).toString(),
              size: compressed.length,
              uncompressedSha256: sha256.convert(rawBytes).toString(),
              uncompressedSize: rawBytes.length,
            ),
          ],
        ),
        patchFileUrls: {fileName: urlOverride ?? zstPath},
        manifestUrl: 'manifest.json',
      );
    }

    /// שלושת מצבי ה-DB בשרשרת 1→2→3, וה-hashes שלהם.
    ({String h1, String h2, String h3}) buildChainHashes() {
      final v1 = buildDb(p.join(tempDir.path, 'expect1.db'), version: 1, rows: [
        [1, 'aleph'],
      ]);
      final v2 = buildDb(p.join(tempDir.path, 'expect2.db'), version: 2, rows: [
        [1, 'aleph'],
        [2, 'bet'],
      ]);
      final v3 = buildDb(p.join(tempDir.path, 'expect3.db'), version: 3, rows: [
        [1, 'aleph'],
        [2, 'bet'],
        [3, 'gimel'],
      ]);
      return (h1: hashOf(v1), h2: hashOf(v2), h3: hashOf(v3));
    }

    /// אוסף את תת-השלבים שדווחו, לפי אינדקס הצעד.
    Map<int, List<String>> stagesRecorder(List<LibraryApplyProgress> log) {
      final byStep = <int, List<String>>{};
      for (final p in log) {
        final stage = p.patchStage;
        if (stage == null) continue;
        (byStep[p.stepIndex ?? 0] ??= []).add(stage);
      }
      return byStep;
    }

    setUp(() {
      if (bindings == null) return;
      buildDb(dbPath, version: 1, rows: [
        [1, 'aleph'],
      ]);
    });

    test('שני צעדים → verifyToHash רק באחרון, והמסד מגיע ליעד', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final h = buildChainHashes();
      final log = <LibraryApplyProgress>[];

      await applier.applyDelta(
        plan: LibraryUpdatePlan.delta(
          localVersion: 1,
          targetVersion: 3,
          steps: [
            buildEdge(
                from: 1,
                to: 2,
                upsertRows: [
                  [2, 'bet']
                ],
                fromHash: h.h1,
                toHash: h.h2),
            buildEdge(
                from: 2,
                to: 3,
                upsertRows: [
                  [3, 'gimel']
                ],
                fromHash: h.h2,
                toHash: h.h3),
          ],
        ),
        dbPath: dbPath,
        onProgress: log.add,
      );

      final stages = stagesRecorder(log);
      expect(stages[1], isNot(contains('verifyToHash')),
          reason: 'הצעד הראשון אינו מאמת');
      expect(stages[2], contains('verifyToHash'),
          reason: 'הצעד האחרון כן מאמת');
      expect(stages[1], isNot(contains('verifyFromHash')));

      // ה-hash של הצעד האחרון תואם ⇒ כל השרשרת נכונה.
      expect(hashOf(dbPath), h.h3);
      expect(recovery.unverifiedVersion(dbPath), isNull);
    });

    test('צעד אחד — מאמת כמו קודם, בלי סימון', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final h = buildChainHashes();
      final log = <LibraryApplyProgress>[];

      await applier.applyDelta(
        plan: LibraryUpdatePlan.delta(
          localVersion: 1,
          targetVersion: 2,
          steps: [
            buildEdge(
                from: 1,
                to: 2,
                upsertRows: [
                  [2, 'bet']
                ],
                fromHash: h.h1,
                toHash: h.h2),
          ],
        ),
        dbPath: dbPath,
        onProgress: log.add,
      );

      expect(stagesRecorder(log)[1], contains('verifyToHash'));
      expect(recovery.unverifiedVersion(dbPath), isNull);
    });

    test('שרשרת שנקטעה מסמנת את המסד כלא-מאומת, וההחלה הבאה מאמתת אותו',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final h = buildChainHashes();

      // הצעד השני מצביע על קובץ שאינו קיים — הראשון מוחל, השני נכשל.
      await expectLater(
        applier.applyDelta(
          plan: LibraryUpdatePlan.delta(
            localVersion: 1,
            targetVersion: 3,
            steps: [
              buildEdge(
                  from: 1,
                  to: 2,
                  upsertRows: [
                    [2, 'bet']
                  ],
                  fromHash: h.h1,
                  toHash: h.h2),
              buildEdge(
                from: 2,
                to: 3,
                upsertRows: [
                  [3, 'gimel']
                ],
                fromHash: h.h2,
                toHash: h.h3,
                urlOverride: p.join(tempDir.path, 'missing.db.zst'),
              ),
            ],
          ),
          dbPath: dbPath,
        ),
        throwsA(anything),
      );

      // הצעד הראשון הוחל אך לא אומת — וזה מתועד.
      expect(recovery.unverifiedVersion(dbPath), 2);

      // ההחלה הבאה מתחילה מאותה גרסה ⇒ מאמתת את המסד לפני שהיא בונה עליו.
      final log = <LibraryApplyProgress>[];
      await applier.applyDelta(
        plan: LibraryUpdatePlan.delta(
          localVersion: 2,
          targetVersion: 3,
          steps: [
            buildEdge(
                from: 2,
                to: 3,
                upsertRows: [
                  [3, 'gimel']
                ],
                fromHash: h.h2,
                toHash: h.h3),
          ],
        ),
        dbPath: dbPath,
        onProgress: log.add,
      );

      expect(stagesRecorder(log)[1], contains('verifyFromHash'));
      expect(hashOf(dbPath), h.h3);
      expect(recovery.unverifiedVersion(dbPath), isNull);
    });

    test('מסד שסומן כלא-מאומת ותוכנו שגוי נדחה לפני שממשיכים לבנות עליו',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final h = buildChainHashes();

      // מסד בגרסה 2, אבל עם תוכן שאינו מה ש-h2 מתאר — בדיוק המצב שהסימון
      // קיים בשבילו. בלי `verifyFromHash` היינו בונים עליו בשקט.
      buildDb(p.join(tempDir.path, 'tampered.db'), version: 2, rows: [
        [1, 'aleph'],
        [2, 'WRONG'],
      ]);
      File(p.join(tempDir.path, 'tampered.db')).copySync(dbPath);
      recovery.markUnverified(dbPath, 2);

      await expectLater(
        applier.applyDelta(
          plan: LibraryUpdatePlan.delta(
            localVersion: 2,
            targetVersion: 3,
            steps: [
              buildEdge(
                  from: 2,
                  to: 3,
                  upsertRows: [
                    [3, 'gimel']
                  ],
                  fromHash: h.h2,
                  toHash: h.h3),
            ],
          ),
          dbPath: dbPath,
        ),
        throwsA(isA<PatchApplyException>().having(
          (e) => e.message,
          'message',
          AppL10n.strings.libraryDomain.contentHashMismatchNeedsFullDownload,
        )),
      );
    });
  });
}

/// שולח את הארגומנטים של ההחלה ל-isolate ומחזיר אותם — פונקציית top-level
/// **בנפרד** מגוף הבדיקה, בדיוק כמו `_isolateApplyPatch`: frame לקסיקלי משלה,
/// כדי שלא תשתף Context עם סוגרים אחרים בבדיקה.
Future<(String, String, DeltaManifest, AppLanguage)> _roundTripThroughIsolate(
  (String, String, DeltaManifest, AppLanguage) args,
) {
  return Isolate.run(() => _echo(args));
}

(String, String, DeltaManifest, AppLanguage) _echo(
  (String, String, DeltaManifest, AppLanguage) args,
) =>
    args;

/// קורא מחרוזת מתורגמת בתוך isolate, עם או בלי הצבת השפה בכניסה.
Future<String> _mirrorMissingInIsolate(AppLanguage? language) {
  return Isolate.run(() => _readMirrorMissing(language));
}

String _readMirrorMissing(AppLanguage? language) {
  if (language != null) AppL10n.use(language);
  return AppL10n.strings.libraryDomain.mirrorMissing;
}

DeltaManifest _manifest() => const DeltaManifest(
      fromVersion: 4,
      toVersion: 5,
      fromSchemaVersion: 1,
      toSchemaVersion: 1,
      fromContentHash:
          '0000000000000000000000000000000000000000000000000000000000000001',
      toContentHash:
          '0000000000000000000000000000000000000000000000000000000000000002',
      patchFiles: [
        PatchFileEntry(
          file: 'patch-v4-v5.db.zst',
          compression: 'zstd',
          sha256:
              '0000000000000000000000000000000000000000000000000000000000000003',
          size: 128,
          uncompressedSha256:
              '0000000000000000000000000000000000000000000000000000000000000004',
          uncompressedSize: 512,
        ),
      ],
    );

PatchEdge _edge() => PatchEdge(
      manifest: _manifest(),
      patchFileUrls: const {'patch-v4-v5.db.zst': 'patch-v4-v5.db.zst'},
      manifestUrl: 'manifest.json',
    );

/// גרסת "אוצריא רצה?" קבועה — הבדיקה לא אמורה להיות תלויה במה שפתוח על
/// מכונת המפתח.
class _FakeGuard extends OtzariaProcessGuard {
  const _FakeGuard(this.running);

  final bool running;

  @override
  Future<bool> isAnyRunning(List<String> processNames) async => running;

  @override
  Future<bool> isRunning(String processName) async => running;
}

/// קורא גרסה שמחזיר ערך קבוע — כדי לבדוק את מסלול האימות/השחזור בלי לייצר
/// מסד SQLite אמיתי בכל בדיקה.
/// מדמה את אימות המסד המחולץ: המטענים בבדיקות הם בייטים אקראיים ולא מסד
/// sqlite, ולכן ה-`quick_check` האמיתי לא רלוונטי כאן. [version] הוא מה
/// שהאימות "קורא" מהמסד — שונה מהיעד ⇒ כשל, בדיוק כמו במימוש האמיתי.
Future<void> Function(String, int?) _fakeVerifier(int version) {
  return (newDbPath, expectedVersion) async {
    if (expectedVersion != null && version != expectedVersion) {
      throw LibraryApplyException(
        AppL10n.strings.libraryDomain
            .versionMismatchAfterWrite(version, expectedVersion),
      );
    }
  };
}
