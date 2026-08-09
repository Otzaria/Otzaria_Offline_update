import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:library_manager/library_manager.dart';
import 'package:library_manager/src/services/zstd_file_decompressor.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/zstd_fixtures.dart';

/// ה-landmine המרכזי של החבילה: **אין נפילה לרשת**. `checkForUpdate` ו-
/// `applyUpdate` קוראים מהמראה המקומית תמיד, גם כשהמכונה מקוונת — ולכן כל
/// בדיקה כאן רצה בתוך [HttpOverrides] שכל שימוש ב-HTTP בתוכו זורק. אם מישהו
/// יחזיר את הנפילה ל-`GithubLibraryReleaseClient`, הבדיקות כאן ייפלו.
void main() {
  final bindings = ZstdFileDecompressor.bindingsOrNull();

  late Directory tempDir;
  late String dataDir;
  late String mirrorDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library-manager-test-');
    dataDir = p.join(tempDir.path, 'OtzariaData');
    mirrorDir = p.join(dataDir, 'mirror', 'library');
    await Directory(dataDir).create(recursive: true);
  });

  tearDown(() async {
    AppL10n.use(AppLanguage.hebrew);
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // קובץ שעדיין נעול — לא מפילים בדיקה על ניקוי.
      }
    }
  });

  /// כותב מראה מקומית בדיוק במבנה ש-`LibraryMirrorExporter` מייצר:
  /// `releases.json` + `assets/<tag>/<name>` עם כתובות **יחסיות**.
  Future<void> writeMirror({
    required String tag,
    Uint8List? compressedDb,
    bool prerelease = false,
  }) async {
    final assets = <Map<String, dynamic>>[];
    if (compressedDb != null) {
      final relative = p.join('assets', tag, 'seforim.db.zst');
      final file = File(p.join(mirrorDir, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(compressedDb, flush: true);
      assets.add({
        'name': 'seforim.db.zst',
        'downloadUrl': relative,
        'size': compressedDb.length,
        'id': 777,
      });
    }
    await Directory(mirrorDir).create(recursive: true);
    await File(p.join(mirrorDir, 'releases.json')).writeAsString(jsonEncode({
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'releases': [
        {
          'tag': tag,
          'isPrerelease': prerelease,
          'isDraft': false,
          'assets': assets,
        }
      ],
    }));
  }

  /// `seforim.db` אמיתי (SQLite עם `schema_meta`) — כדי שהבדיקות ילכו דרך
  /// `LocalDbVersionReader` האמיתי ולא דרך קורא מזויף.
  var builtDbCount = 0;
  Uint8List buildRealDb(int dbVersion) {
    final path = p.join(tempDir.path, 'built-$dbVersion-${builtDbCount++}.db');
    final db = sqlite3.sqlite3.open(path);
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute(
      "INSERT INTO schema_meta VALUES ('db_version', '$dbVersion'), "
      "('db_schema_version', '1')",
    );
    db.close();
    return File(path).readAsBytesSync();
  }

  /// מתקין DB קיים בתיקייה זמנית ומצביע עליו כנתיב המותאם אישית, כדי
  /// שהאיתור יהיה דטרמיניסטי ולא יפגוש אוצריא אמיתית של המפתח.
  Future<String> installExistingDb(int dbVersion, {String? appliedTag}) async {
    final dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    File(dbPath).writeAsBytesSync(buildRealDb(dbVersion));
    final store = LibraryStateStore(p.join(dataDir, 'library_state.json'));
    await store.saveCustomDbPath(dbPath);
    if (appliedTag != null) await store.saveAppliedReleaseTag(appliedTag);
    return dbPath;
  }

  /// האם למפתח שמריץ את הבדיקות יש אוצריא אמיתית במיקום ברירת המחדל —
  /// אז בדיקת "התקנה טרייה" אינה תקפה, ומדלגים עליה במקום לגעת ב-DB אמיתי.
  Future<bool> ambientDbExists() async =>
      await LibraryDbLocator(
        stateStore: LibraryStateStore(p.join(tempDir.path, 'probe.json')),
      ).resolveDbPath() !=
      null;

  group('mirrorDir / hasMirror', () {
    test('המראה יושבת תמיד באותו מקום יחסית לתיקיית הנתונים', () {
      final manager = LibraryManager(dataDir: dataDir);
      expect(manager.mirrorDir, p.join(dataDir, 'mirror', 'library'));
      manager.dispose();
    });

    test('hasMirror נשען על releases.json, לא על קיום התיקייה', () async {
      final manager = LibraryManager(dataDir: dataDir);
      expect(await manager.hasMirror, isFalse);

      // תיקייה + נכסים בלי המניפסט = הורדה שנקטעה, לא מראה שמישה.
      await Directory(p.join(mirrorDir, 'assets', 'v5'))
          .create(recursive: true);
      await File(p.join(mirrorDir, 'assets', 'v5', 'seforim.db.zst'))
          .writeAsString('חלקי');
      expect(await manager.hasMirror, isFalse);

      await writeMirror(tag: 'v5', compressedDb: Uint8List.fromList([1, 2]));
      expect(await manager.hasMirror, isTrue);
      manager.dispose();
    });
  });

  group('אין נפילה לרשת', () {
    test('בלי מראה — LibraryMirrorMissingException, בלי שום פנייה לרשת',
        () async {
      await _withoutNetwork((created) async {
        final manager = LibraryManager(dataDir: dataDir);
        await expectLater(
          manager.checkForUpdate(),
          throwsA(isA<LibraryMirrorMissingException>()
              .having((e) => e.mirrorDir, 'mirrorDir', manager.mirrorDir)),
        );
        manager.dispose();
        // הלקוח של GitHub אכן נוצר בבנאי — אבל אף פעולה לא בוצעה דרכו.
        expect(created(), greaterThan(0));
      });
    });

    test('ההודעה של LibraryMirrorMissingException מגיעה מ-otzaria_l10n', () {
      const exception = LibraryMirrorMissingException(r'C:\mirror');

      AppL10n.use(AppLanguage.english);
      expect(
        exception.toString(),
        AppL10n.stringsFor(AppLanguage.english).libraryDomain.mirrorMissing,
      );
      AppL10n.use(AppLanguage.hebrew);
      expect(
        exception.toString(),
        AppL10n.stringsFor(AppLanguage.hebrew).libraryDomain.mirrorMissing,
      );
    });

    test('מחיקת releases.json בלבד מחזירה את המראה למצב "חסרה"', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      await installExistingDb(5);
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        await manager.checkForUpdate(); // עובד כל עוד המניפסט קיים

        File(p.join(mirrorDir, 'releases.json')).deleteSync();
        await expectLater(
          manager.checkForUpdate(),
          throwsA(isA<LibraryMirrorMissingException>()),
        );
        manager.dispose();
      });
    });
  });

  group('checkForUpdate — קורא מהמראה בלבד', () {
    test('התקנה טרייה מצביעה על נתיב ברירת מחדל משלנו ומתכננת הורדה מלאה',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      if (await ambientDbExists()) {
        markTestSkipped('קיימת אוצריא אמיתית במכונה — הבדיקה אינה מבודדת');
        return;
      }
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();

        expect(check.isFreshInstall, isTrue);
        expect(check.needsManualDbPath, isFalse);
        expect(check.dbPath, p.join(dataDir, 'library', 'seforim.db'));
        expect(check.localVersion!.hasVersionMeta, isFalse);
        expect(check.plan!.kind, LibraryUpdatePlanKind.fullDownload);
        expect(check.latestReleaseTag, 'v5');
        expect(check.updateAvailable, isTrue);
        manager.dispose();
      });
    });

    test('DB עדכני בלי tag ידוע = "מעודכן" — לא מציעים 1GB על סמך ניחוש',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      // מסד שלא הותקן דרך הלאנצ'ר: אין appliedReleaseTag בכלל.
      await installExistingDb(5);
      await writeMirror(
        tag: 'v5-fixed',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();

        expect(check.isFreshInstall, isFalse);
        expect(check.localVersion!.dbVersion, 5);
        expect(check.plan!.kind, LibraryUpdatePlanKind.none);
        expect(check.updateAvailable, isFalse);
        manager.dispose();
      });
    });

    test('אותה גרסה אבל release אחר, כש-ה-tag ידוע = פרסום מחדש של התוכן',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      await installExistingDb(5, appliedTag: 'v5');
      await writeMirror(
        tag: 'v5-fixed',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();

        expect(check.plan!.kind, LibraryUpdatePlanKind.fullDownload);
        expect(check.plan!.fullDbReleaseTag, 'v5-fixed');
        manager.dispose();
      });
    });

    test('אותו tag בדיוק = מעודכן', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      await installExistingDb(5, appliedTag: 'v5');
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();
        expect(check.plan!.kind, LibraryUpdatePlanKind.none);
        manager.dispose();
      });
    });

    test('גרסה ישנה בלי מסלול דלתא נופלת להורדה מלאה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      await installExistingDb(4, appliedTag: 'v4');
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();

        expect(check.plan!.kind, LibraryUpdatePlanKind.fullDownload);
        expect(check.plan!.localVersion, 4);
        expect(check.plan!.targetVersion, 5);
        manager.dispose();
      });
    });

    test('מראה בלי נכס מסד כלל = blocked, לא קריסה', () async {
      await installExistingDb(4, appliedTag: 'v4');
      await writeMirror(tag: 'v9'); // release בלי seforim.db.zst

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();
        // אין נכס להוריד ואין edges — אין מה לתכנן.
        expect(check.plan!.kind, LibraryUpdatePlanKind.none);
        manager.dispose();
      });
    });

    test('ערוץ pre-release: נספר רק כש-allowPrerelease פעיל', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      await installExistingDb(4, appliedTag: 'v4');
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
        prerelease: true,
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        expect(
          (await manager.checkForUpdate()).plan!.kind,
          LibraryUpdatePlanKind.none,
        );

        // ההחלפה תופסת בבדיקה הבאה, בלי לבנות מנהל חדש.
        manager.allowPrerelease = true;
        expect(
          (await manager.checkForUpdate()).plan!.kind,
          LibraryUpdatePlanKind.fullDownload,
        );
        manager.dispose();
      });
    });
  });

  group('checkForUpdate — התאוששות משאריות קריסה', () {
    test('סימון עדכון שנקטע על DB תקין מנוקה והבדיקה ממשיכה', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      final dbPath = await installExistingDb(5, appliedTag: 'v5');
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );
      // מסלול דלתא שנקטע: יש סימון, אין גיבוי — וה-DB עצמו תקין.
      File('$dbPath.applying').writeAsStringSync('{"fromVersion":4}');

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();

        expect(check.localVersion!.dbVersion, 5);
        expect(File('$dbPath.applying').existsSync(), isFalse);
        manager.dispose();
      });
    });

    test('סימון שנקטע על DB פגום נעצר עם ההודעה מ-otzaria_l10n', () async {
      final dbPath = p.join(tempDir.path, 'books', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);
      File(dbPath).writeAsStringSync('זה בכלל לא SQLite');
      await LibraryStateStore(p.join(dataDir, 'library_state.json'))
          .saveCustomDbPath(dbPath);
      File('$dbPath.applying').writeAsStringSync('{"fromVersion":4}');
      await writeMirror(tag: 'v5', compressedDb: Uint8List.fromList([1, 2]));

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        await expectLater(
          manager.checkForUpdate(),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.interruptedUpdateNeedsManualFix(
              AppL10n.strings.libraryDomain.interruptedUpdateNoBackup,
            ),
          )),
        );
        manager.dispose();
      });
    });
  });

  group('applyUpdate', () {
    test('סבב אופליין מלא: בדיקה → הורדה מלאה מהמראה → בדיקה חוזרת "מעודכן"',
        () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      if (await const OtzariaProcessGuard()
          .isAnyRunning(OtzariaProcessGuard.processNamesFor(
        Platform.operatingSystem,
      ))) {
        markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
        return;
      }

      // ה-DB "החי" יושב בתיקייה זמנית ומוצבע דרך נתיב מותאם אישית: הבדיקה
      // לעולם לא נוגעת ב-seforim.db האמיתי של המפתח.
      await installExistingDb(4, appliedTag: 'v4');
      final dbBytes = buildRealDb(5);
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, dbBytes),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        final check = await manager.checkForUpdate();
        expect(check.plan!.kind, LibraryUpdatePlanKind.fullDownload);
        expect(check.plan!.localVersion, 4);

        final stages = <LibraryApplyStage>[];
        await manager.applyUpdate(
          check,
          onProgress: (progress) {
            if (stages.isEmpty || stages.last != progress.stage) {
              stages.add(progress.stage);
            }
          },
        );

        expect(stages.last, LibraryApplyStage.done);
        expect(File(check.dbPath!).readAsBytesSync(), dbBytes);

        // מה שנרשם ב-state הוא מה שמונע הצעת הורדה חוזרת בכל פתיחה.
        final store = LibraryStateStore(p.join(dataDir, 'library_state.json'));
        expect(await store.loadAppliedReleaseTag(), 'v5');
        expect(await store.loadCustomDbPath(), check.dbPath);

        final recheck = await manager.checkForUpdate();
        expect(recheck.isFreshInstall, isFalse);
        expect(recheck.plan!.kind, LibraryUpdatePlanKind.none);
        expect(recheck.updateAvailable, isFalse);
        manager.dispose();
      });
    });

    test('תוכנית none / חסרה — לא עושה כלום', () async {
      final manager = LibraryManager(dataDir: dataDir);
      final dbPath = p.join(tempDir.path, 'books', 'seforim.db');

      await manager.applyUpdate(LibraryUpdateCheckResult(dbPath: dbPath));
      await manager.applyUpdate(LibraryUpdateCheckResult(
        dbPath: dbPath,
        plan: LibraryUpdatePlan.none(localVersion: 5),
      ));
      await manager.applyUpdate(LibraryUpdateCheckResult(
        dbPath: null,
        plan: LibraryUpdatePlan.fullDownload(
          localVersion: 0,
          asset: const ReleaseAsset(
            name: 'seforim.db.zst',
            downloadUrl: 'nowhere.zst',
            size: 1,
          ),
          releaseTag: 'v5',
        ),
      ));

      expect(File(dbPath).existsSync(), isFalse);
      expect(
        await LibraryStateStore(p.join(dataDir, 'library_state.json'))
            .loadAppliedReleaseTag(),
        isNull,
      );
      manager.dispose();
    });

    test('תוכנית blocked זורקת LibraryApplyException עם הסיבה', () async {
      final manager = LibraryManager(dataDir: dataDir);

      await expectLater(
        manager.applyUpdate(LibraryUpdateCheckResult(
          dbPath: p.join(tempDir.path, 'seforim.db'),
          plan: LibraryUpdatePlan.blocked(
            localVersion: 4,
            targetVersion: 9,
            reason: 'אין מסלול',
          ),
        )),
        throwsA(isA<LibraryApplyException>()
            .having((e) => e.message, 'message', 'אין מסלול')),
      );
      manager.dispose();
    });
  });

  group('setCustomDbPath / currentDbPath', () {
    test('נתיב שנבחר ידנית נשמר ומוחזר בבדיקה הבאה', () async {
      final dbPath = p.join(tempDir.path, 'my-library', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);
      File(dbPath).writeAsStringSync('db');

      final manager = LibraryManager(dataDir: dataDir);
      await manager.setCustomDbPath(dbPath);

      expect(await manager.currentDbPath(), dbPath);
      manager.dispose();
    });
  });

  group('peekLatestOnlineVersion — הפעולה היחידה בבדיקה שנוגעת ברשת', () {
    test('כשל רשת הוא תוצאה רגילה: זורק, ולא משאיר את המודול פגום', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      await installExistingDb(5, appliedTag: 'v5');
      await writeMirror(
        tag: 'v5',
        compressedDb: compressWithZstd(bindings, buildRealDb(5)),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);

        // "אין רשת" — הקורא אמור לבלוע את זה, לא להציג שגיאה חוסמת.
        await expectLater(manager.peekLatestOnlineVersion(), throwsA(anything));

        // ובכל זאת הבדיקה האופליינית ממשיכה לעבוד בדיוק כמו קודם.
        final check = await manager.checkForUpdate();
        expect(check.plan!.kind, LibraryUpdatePlanKind.none);
        manager.dispose();
      });
    });
  });
}

/// מריץ [body] בזון שבו כל שימוש ב-HTTP זורק — כך "נפילה לרשת" בקוד הנבדק
/// הופכת לכשל בדיקה ולא לתוצאה שקטה. [body] מקבל פונקציה שמחזירה כמה
/// לקוחות HTTP נוצרו (יצירה מותרת; שימוש אינו).
Future<void> _withoutNetwork(Future<void> Function(int Function()) body) {
  var created = 0;
  return HttpOverrides.runZoned<Future<void>>(
    () => body(() => created),
    createHttpClient: (_) {
      created++;
      return _NoNetworkHttpClient();
    },
  );
}

/// לקוח HTTP שכל פעולה בו זורקת. `close` והצבת מאפיינים מותרים — הם מה
/// שקורה ב-`dispose` ובבנאי, ואינם גישה לרשת.
class _NoNetworkHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter || invocation.memberName == #close) return null;
    throw StateError('הבדיקה ניגשה לרשת: ${invocation.memberName}');
  }
}
