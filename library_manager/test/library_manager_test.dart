import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/db_fixtures.dart';
import 'support/zstd_fixtures.dart';

/// ה-landmine המרכזי של החבילה: **אין נפילה לרשת**. `checkForUpdate` ו-
/// `applyUpdate` קוראים מהמראה המקומית תמיד, גם כשהמכונה מקוונת — ולכן כל
/// בדיקה כאן רצה בתוך [HttpOverrides] שכל שימוש ב-HTTP בתוכו זורק. אם מישהו
/// יחזיר את הנפילה ל-`GithubLibraryReleaseClient`, הבדיקות כאן ייפלו.
void main() {
  final bindings = nativeZstd();

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
    await File(p.join(mirrorDir, 'releases.json')).writeAsString(
      jsonEncode({
        'formatVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'releases': [
          {
            'tag': tag,
            'isPrerelease': prerelease,
            'isDraft': false,
            'assets': assets,
          },
        ],
      }),
    );
  }

  var builtDbCount = 0;
  Uint8List buildRealDb(int dbVersion) =>
      buildVersionOnlyDb(tempDir.path, dbVersion);

  /// מתקין DB קיים בתיקייה זמנית ומצביע עליו כנתיב המותאם אישית, כדי
  /// שהאיתור יהיה דטרמיניסטי ולא יפגוש אוצריא אמיתית של המפתח.
  Future<String> installExistingDb(int dbVersion, {String? appliedTag}) async {
    final dbPath = p.join(tempDir.path, 'books', 'seforim.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    File(dbPath).writeAsBytesSync(buildRealDb(dbVersion));
    final store = LibraryStateStore(p.join(dataDir, 'library_state.json'));
    await store.saveCustomDbPath(dbPath);
    if (appliedTag != null) {
      await store.saveAppliedRelease(tag: appliedTag, dbVersion: dbVersion);
    }
    return dbPath;
  }

  Map<String, String> hermeticEnvironment() => {
    'HOME': p.join(tempDir.path, 'home'),
  };

  LibraryManager hermeticManager({
    OtzariaSettingsReader settingsReader = const OtzariaSettingsReader(),
  }) => LibraryManager(
    dataDir: dataDir,
    operatingSystem: 'linux',
    environment: hermeticEnvironment(),
    settingsReader: settingsReader,
  );

  Uint8List buildPatchableDb(int dbVersion, List<List> rows) =>
      buildSchema2Db(tempDir.path, dbVersion, rows);

  PatchEdge buildPatchEdge({
    required int from,
    required int to,
    required List<List> upsertRows,
    int toSchemaVersion = 2,
  }) => buildSchema2PatchEdge(
    bindings!,
    tempDir.path,
    from: from,
    to: to,
    upsertRows: upsertRows,
    toSchemaVersion: toSchemaVersion,
  );

  LibraryUpdateCheckResult freshCheck(String dbPath) {
    final compressed = p.join(tempDir.path, 'fresh-${builtDbCount++}.db.zst');
    File(compressed).writeAsBytesSync(
      compressWithZstd(bindings!, buildRealDb(5)),
      flush: true,
    );
    return LibraryUpdateCheckResult(
      dbPath: dbPath,
      isFreshInstall: true,
      latestVersion: 5,
      latestContentTag: 'v5',
      plan: LibraryUpdatePlan.fullDownload(
        localVersion: 0,
        targetVersion: 5,
        asset: ReleaseAsset(
          name: 'seforim.db.zst',
          downloadUrl: compressed,
          size: File(compressed).lengthSync(),
        ),
        releaseTag: 'v5',
      ),
    );
  }

  /// **הלולאה שהלוג מ-0.14 תיעד:** `kind=none local=27 target=27` ובכל זאת
  /// `status=updateAvailable`, כי `companions=true` — בכל פתיחה מחדש.
  group('קבצים נלווים אינם מציעים עדכון בלי סוף', () {
    /// מראה עם מילון בלבד: הקטן משלושת הפריטים, ובלי zstd.
    Future<void> writeCompanionMirror({
      required String tag,
      required String content,
    }) async {
      final dir = p.join(dataDir, 'mirror', 'companions');
      await Directory(dir).create(recursive: true);
      await File(p.join(dir, 'lexical.db')).writeAsString(content);
      await File(p.join(dir, 'companions.json')).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'exportedAt': DateTime.now().toIso8601String(),
          'dictionary': {
            'fileName': 'lexical.db',
            'size': utf8.encode(content).length,
            'tag': tag,
          },
        }),
      );
    }

    test('אחרי התקנה, קובץ שאוצריא החליפה מהרשת אינו מחזיר את ההצעה', () async {
      final dbPath = await installExistingDb(27, appliedTag: 'v27');
      await writeMirror(tag: 'v27');
      await writeCompanionMirror(tag: 'v2', content: 'LEXICAL');

      final manager = LibraryManager(dataDir: dataDir);
      addTearDown(manager.dispose);

      // המסד מעודכן, ורק המילון ממתין — וזה נאמר בשמו.
      final first = await manager.checkForUpdate();
      expect(first.dbUpdateAvailable, isFalse);
      expect(first.pendingCompanions, {CompanionAsset.dictionary});

      await manager.applyUpdate(first);
      expect((await manager.checkForUpdate()).updateAvailable, isFalse);

      // אוצריא הורידה מהרשת מילון אחר וכתבה סימון משלה. עד עכשיו זה נראה
      // בדיוק כמו מילון ישן: הצעה בכל פתיחה, ולחיצה שמורידה אותו אחורה.
      await File(
        p.join(p.dirname(dbPath), 'lexical.db.version'),
      ).writeAsString('v7');

      final after = await manager.checkForUpdate();
      expect(after.pendingCompanions, isEmpty);
      expect(after.updateAvailable, isFalse);

      await manager.applyUpdate(first);
      expect(
        await File(
          p.join(p.dirname(dbPath), 'lexical.db.version'),
        ).readAsString(),
        'v7',
      );
      expect((await manager.checkForUpdate()).pendingCompanions, isEmpty);
    });

    test('רשומה שהקובץ שלה חסר במראה אינה הצעה, אבל כן מדווחת', () async {
      await installExistingDb(27, appliedTag: 'v27');
      await writeMirror(tag: 'v27');
      await writeCompanionMirror(tag: 'v2', content: 'LEXICAL');
      await File(
        p.join(dataDir, 'mirror', 'companions', 'lexical.db'),
      ).delete();

      final manager = LibraryManager(dataDir: dataDir);
      addTearDown(manager.dispose);

      final check = await manager.checkForUpdate();
      expect(check.pendingCompanions, isEmpty);
      expect(check.unavailableCompanions, {CompanionAsset.dictionary});
      expect(check.updateAvailable, isFalse);
    });
  });

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
      await Directory(
        p.join(mirrorDir, 'assets', 'v5'),
      ).create(recursive: true);
      await File(
        p.join(mirrorDir, 'assets', 'v5', 'seforim.db.zst'),
      ).writeAsString('חלקי');
      expect(await manager.hasMirror, isFalse);

      await writeMirror(tag: 'v5', compressedDb: Uint8List.fromList([1, 2]));
      expect(await manager.hasMirror, isTrue);
      manager.dispose();
    });
  });

  group('אין נפילה לרשת', () {
    test(
      'בלי מראה — LibraryMirrorMissingException, בלי שום פנייה לרשת',
      () async {
        await _withoutNetwork((created) async {
          final manager = LibraryManager(dataDir: dataDir);
          await expectLater(
            manager.checkForUpdate(),
            throwsA(
              isA<LibraryMirrorMissingException>().having(
                (e) => e.mirrorDir,
                'mirrorDir',
                manager.mirrorDir,
              ),
            ),
          );
          manager.dispose();
          // הלקוח של GitHub אכן נוצר בבנאי — אבל אף פעולה לא בוצעה דרכו.
          expect(created(), greaterThan(0));
        });
      },
    );

    test(
      'גרסת המסד המקומי נקראת גם בלי מראה — בחירה ידנית לפני הורדה',
      () async {
        await installExistingDb(17);
        final manager = LibraryManager(dataDir: dataDir);
        addTearDown(manager.dispose);

        // הבדיקה נכשלת (אין מראה), אבל הגרסה שנקראה מהמסד לא הולכת לאיבוד.
        await expectLater(
          manager.checkForUpdate(),
          throwsA(isA<LibraryMirrorMissingException>()),
        );

        expect((await manager.readLocalVersion())?.dbVersion, 17);
      },
    );

    test('בלי מסד כלל — readLocalVersion מחזירה null ולא זורקת', () async {
      final manager = hermeticManager();
      addTearDown(manager.dispose);

      expect(await manager.readLocalVersion(), isNull);
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
    test(
      'התקנה טרייה מצביעה על מיקום ברירת המחדל של אוצריא ומתכננת הורדה מלאה',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }
        await writeMirror(
          tag: 'v5',
          compressedDb: compressWithZstd(bindings, buildRealDb(5)),
        );

        await _withoutNetwork((_) async {
          final manager = hermeticManager();
          final check = await manager.checkForUpdate();

          expect(check.isFreshInstall, isTrue);
          expect(check.needsManualDbPath, isFalse);
          // המסד מותקן למיקום שאוצריא עצמה מחפשת בו, **לא** לתיקיית הלאנצ'ר:
          // לאנצ'ר שרץ מכונן נייד היה מתקין עליו את הספרייה, והיא הייתה
          // נוסעת איתו ונעלמת מהמחשב ברגע שנשלף.
          expect(check.dbPath, isNot(startsWith(dataDir)));
          expect(check.dbPath, await manager.installDbPath());
          expect(
            check.dbPath,
            p.posix.join(
              LibraryDbLocator.defaultDbDirs(
                operatingSystem: 'linux',
                environment: hermeticEnvironment(),
              ).first,
              'seforim.db',
            ),
          );
          expect(check.localVersion!.hasVersionMeta, isFalse);
          expect(check.plan!.kind, LibraryUpdatePlanKind.fullDownload);
          expect(check.latestContentTag, 'v5');
          expect(check.updateAvailable, isTrue);
          manager.dispose();
        });
      },
    );

    test(
      'DB עדכני בלי tag ידוע = "מעודכן" — לא מציעים 1GB על סמך ניחוש',
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
      },
    );

    test(
      'אותה גרסה אבל release אחר, כש-ה-tag ידוע = פרסום מחדש של התוכן',
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
      },
    );

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

    // A locked live v26 must not read as "no version": that skipped the
    // no-downgrade guard and planned the mirror's older v21 full DB over it.
    test(
      'locked local DB fails the check instead of planning a downgrade',
      () async {
        final dbPath = await installExistingDb(26, appliedTag: 'v26');
        await writeMirror(
          tag: 'v21',
          compressedDb: Uint8List.fromList(const [1, 2, 3]),
        );

        await _withoutNetwork((_) async {
          final manager = LibraryManager(
            dataDir: dataDir,
            versionReader: const LocalDbVersionReader(
              busyTimeout: Duration(milliseconds: 50),
            ),
          );
          addTearDown(manager.dispose);
          // Unlocked, the guard holds: no plan installs the older v21.
          final unlocked = await manager.checkForUpdate();
          expect(
            unlocked.plan!.kind,
            isNot(LibraryUpdatePlanKind.fullDownload),
          );

          final writer = sqlite3.sqlite3.open(dbPath);
          try {
            writer.execute('BEGIN EXCLUSIVE');
            writer.execute(
              "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'",
            );
            await expectLater(
              manager.checkForUpdate(),
              throwsA(
                isA<LocalDbUnreadableException>().having(
                  (e) => e.reason,
                  'reason',
                  LocalDbUnreadableReason.locked,
                ),
              ),
            );
          } finally {
            writer.execute('ROLLBACK');
            writer.close();
          }
        });
      },
    );

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

    test('הורדה שנקטעה במראה מסומנת בתוצאת הבדיקה', () async {
      await installExistingDb(5, appliedTag: 'v5');
      await writeMirror(
        tag: 'v5',
        compressedDb: Uint8List.fromList([1, 2, 3, 4]),
      );
      final archive = File(p.join(mirrorDir, 'assets', 'v5', 'seforim.db.zst'));
      final orphan = File(
        p.join(mirrorDir, 'assets', 'v6', 'seforim.db.zst.resume'),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        Future<bool> incomplete() async =>
            (await manager.checkForUpdate()).mirrorDownloadIncomplete;

        expect(await incomplete(), isFalse);

        await File('${archive.path}.resume').writeAsString('777\n"etag"');
        expect(await incomplete(), isFalse);

        await orphan.parent.create(recursive: true);
        await orphan.writeAsString('778\n"etag"');
        expect(await incomplete(), isTrue);

        await orphan.delete();
        await archive.writeAsBytes([1, 2, 3]);
        expect(await incomplete(), isTrue);

        await archive.delete();
        expect(await incomplete(), isTrue);
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
      await LibraryStateStore(
        p.join(dataDir, 'library_state.json'),
      ).saveCustomDbPath(dbPath);
      File('$dbPath.applying').writeAsStringSync('{"fromVersion":4}');
      await writeMirror(tag: 'v5', compressedDb: Uint8List.fromList([1, 2]));

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        await expectLater(
          manager.checkForUpdate(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              AppL10n.strings.libraryDomain.interruptedUpdateNeedsManualFix(
                AppL10n.strings.libraryDomain.interruptedUpdateFound,
              ),
            ),
          ),
        );
        manager.dispose();
      });
    });
  });

  group('checkForUpdate בזמן החלה', () {
    test(
      'אינו מריץ התאוששות מתחת להחלה חיה, ומריץ אותה אחרי שהסתיימה',
      () async {
        final dbPath = await installExistingDb(4, appliedTag: 'v4');
        final dbBytes = buildRealDb(5);
        await writeMirror(tag: 'v5', compressedDb: Uint8List.fromList([1, 2]));
        final applier = _GatedApplier(dbBytes);

        await _withoutNetwork((_) async {
          final manager = LibraryManager(dataDir: dataDir, applier: applier);
          final check = await manager.checkForUpdate();
          expect(check.plan!.kind, LibraryUpdatePlanKind.fullDownload);

          final apply = manager.applyUpdate(check);
          await applier.staged.future;

          final midApply = await manager.checkForUpdate();
          expect(midApply.localVersion!.dbVersion, 4);
          expect(File('$dbPath.new').existsSync(), isTrue);
          expect(File('$dbPath.applying').existsSync(), isTrue);
          expect(File('$dbPath.download.zst').existsSync(), isTrue);

          applier.gate.complete();
          await apply;
          expect(File(dbPath).readAsBytesSync(), dbBytes);
          expect(File('$dbPath.new').existsSync(), isFalse);
          expect(File('$dbPath.applying').existsSync(), isFalse);
          expect(File('$dbPath.download.zst').existsSync(), isTrue);

          final after = await manager.checkForUpdate();
          expect(after.localVersion!.dbVersion, 5);
          expect(File('$dbPath.download.zst').existsSync(), isFalse);
          manager.dispose();
        });
      },
    );
  });

  group('applyUpdate', () {
    test(
      'סבב אופליין מלא: בדיקה → הורדה מלאה מהמראה → בדיקה חוזרת "מעודכן"',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }
        if (await const OtzariaProcessGuard().isAnyRunning(
          OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
        )) {
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
          final store = LibraryStateStore(
            p.join(dataDir, 'library_state.json'),
          );
          expect((await store.loadAppliedRelease())?.tag, 'v5');
          expect(await store.loadCustomDbPath(), check.dbPath);

          final recheck = await manager.checkForUpdate();
          expect(recheck.isFreshInstall, isFalse);
          expect(recheck.plan!.kind, LibraryUpdatePlanKind.none);
          expect(recheck.updateAvailable, isFalse);
          manager.dispose();
        });
      },
    );

    // המראה שומרת בכוונה מסד מלא ישן מ-latest כשיש ממנו מסלול patches (ראו
    // `LibraryMirrorExporter._chooseFullDbCarrier`), ולכן ההשלמה רצה באותה
    // החלה — ומה שנרשם הוא הגרסה והתגית של סופה, לא של המסד שירד.
    test('הורדה מלאה + followUpDelta נרשמות לפי הגרסה הסופית', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      if (await const OtzariaProcessGuard().isAnyRunning(
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      )) {
        markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
        return;
      }

      final dbPath = await installExistingDb(3, appliedTag: 'v3');
      final dbBytes = buildRealDb(5);
      final compressed = p.join(tempDir.path, 'old-full.db.zst');
      File(
        compressed,
      ).writeAsBytesSync(compressWithZstd(bindings, dbBytes), flush: true);

      final check = LibraryUpdateCheckResult(
        dbPath: dbPath,
        latestVersion: 6,
        latestContentTag: 'v6',
        plan: LibraryUpdatePlan.fullDownload(
          localVersion: 3,
          // היעד של ההורדה עצמה הוא מה שהנכס מביא — האימות שאחריה בודק אותו.
          targetVersion: 5,
          asset: ReleaseAsset(
            name: 'seforim.db.zst',
            downloadUrl: compressed,
            size: File(compressed).lengthSync(),
          ),
          releaseTag: 'v5',
          // שרשרת ריקה: כאן נבדק החיווט, לא החלת ה-patches עצמה (מכוסה
          // ב-library_update_applier_test).
          followUpDelta: LibraryUpdatePlan.delta(
            localVersion: 5,
            targetVersion: 6,
            steps: const [],
          ),
        ),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        await manager.applyUpdate(check);

        expect(File(dbPath).readAsBytesSync(), dbBytes);
        final store = LibraryStateStore(p.join(dataDir, 'library_state.json'));
        // 'v5' כאן היה מסמן את המראה כ"תוכן אחר" ומציע 1GB בכל פתיחה.
        expect((await store.loadAppliedRelease())?.tag, 'v6');
        final notice = await manager.pendingReindexRequest(dbPath: dbPath);
        expect(notice!.dbVersion, 6);
        manager.dispose();
      });
    });

    test('הורדה מלאה בלי השלמה נרשמת לפי ה-release של המסד המלא', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      if (await const OtzariaProcessGuard().isAnyRunning(
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      )) {
        markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
        return;
      }

      final dbPath = await installExistingDb(4, appliedTag: 'v4');
      final dbBytes = buildRealDb(5);
      final compressed = p.join(tempDir.path, 'full-5a.db.zst');
      File(
        compressed,
      ).writeAsBytesSync(compressWithZstd(bindings, dbBytes), flush: true);

      final check = LibraryUpdateCheckResult(
        dbPath: dbPath,
        latestVersion: 5,
        latestContentTag: 'v5-b',
        plan: LibraryUpdatePlan.fullDownload(
          localVersion: 4,
          targetVersion: 5,
          asset: ReleaseAsset(
            name: 'seforim.db.zst',
            downloadUrl: compressed,
            size: File(compressed).lengthSync(),
          ),
          releaseTag: 'v5-a',
        ),
      );

      await _withoutNetwork((_) async {
        final manager = LibraryManager(dataDir: dataDir);
        await manager.applyUpdate(check);

        final applied = await LibraryStateStore(
          p.join(dataDir, 'library_state.json'),
        ).loadAppliedRelease();
        expect(applied?.tag, 'v5-a');
        expect(applied?.dbVersion, 5);
        manager.dispose();
      });
    });

    // v26 של SeforimLibrary פורסמה עם patches בסכמה שהמחיל אינו יודע להחיל:
    // המסד המלא הישן הותקן, הצעד הראשון בשרשרת ההשלמה הצליח והשני נדחה.
    // הרישום חייב להיות הגרסה שהמסד באמת הגיע אליה ולא זו של המסד המלא —
    // אחרת ה-state מצהיר על גרסה אחת בעוד המסד בגרסה אחרת.
    test(
      'שרשרת השלמה שנקטעה נרשמת לפי הצעד שהצליח, לא לפי המסד המלא',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }
        if (await const OtzariaProcessGuard().isAnyRunning(
          OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
        )) {
          markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
          return;
        }

        // המסד החי מתקדם מהמסד המלא שבמראה — בדיוק המצב שבו הבאג התגלה.
        final dbPath = await installExistingDb(23, appliedTag: 'v23');
        final compressed = p.join(tempDir.path, 'full-21.db.zst');
        File(compressed).writeAsBytesSync(
          compressWithZstd(
            bindings,
            buildPatchableDb(21, [
              [1, 'aleph'],
            ]),
          ),
          flush: true,
        );

        final check = LibraryUpdateCheckResult(
          dbPath: dbPath,
          latestVersion: 26,
          latestContentTag: 'v26',
          plan: LibraryUpdatePlan.fullDownload(
            localVersion: 23,
            targetVersion: 21,
            asset: ReleaseAsset(
              name: 'seforim.db.zst',
              downloadUrl: compressed,
              size: File(compressed).lengthSync(),
            ),
            releaseTag: 'v21',
            followUpDelta: LibraryUpdatePlan.delta(
              localVersion: 21,
              targetVersion: 26,
              steps: [
                buildPatchEdge(
                  from: 21,
                  to: 22,
                  upsertRows: [
                    [2, 'bet'],
                  ],
                ),
                buildPatchEdge(
                  from: 22,
                  to: 26,
                  upsertRows: [
                    [3, 'gimel'],
                  ],
                  toSchemaVersion: 7,
                ),
              ],
            ),
          ),
        );

        await _withoutNetwork((_) async {
          final manager = LibraryManager(dataDir: dataDir);
          await expectLater(
            manager.applyUpdate(check),
            throwsA(isA<PatchApplyException>()),
          );

          // המסד נעצר ב-22, וזו הגרסה שנרשמה — 21 כאן היה שקר על הדיסק.
          expect(const LocalDbVersionReader().read(dbPath).dbVersion, 22);
          final store = LibraryStateStore(
            p.join(dataDir, 'library_state.json'),
          );
          expect((await store.loadAppliedRelease())?.dbVersion, 22);
          expect(
            (await manager.pendingReindexRequest(dbPath: dbPath))?.dbVersion,
            22,
          );
          manager.dispose();
        });
      },
    );

    test('תוכנית none / חסרה — לא עושה כלום', () async {
      final manager = LibraryManager(dataDir: dataDir);
      final dbPath = p.join(tempDir.path, 'books', 'seforim.db');

      await manager.applyUpdate(LibraryUpdateCheckResult(dbPath: dbPath));
      await manager.applyUpdate(
        LibraryUpdateCheckResult(
          dbPath: dbPath,
          plan: LibraryUpdatePlan.none(localVersion: 5),
        ),
      );
      await manager.applyUpdate(
        LibraryUpdateCheckResult(
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
        ),
      );

      expect(File(dbPath).existsSync(), isFalse);
      expect(
        await LibraryStateStore(
          p.join(dataDir, 'library_state.json'),
        ).loadAppliedRelease(),
        isNull,
      );
      manager.dispose();
    });

    // ההתאוששות מ-issue #19: מסלול דלתא שנכשל (patch שאינו מתאים למסד) אינו
    // מותיר את המשתמש תקוע — אותה בדיקה מותקנת דרך המסד המלא שבמראה.
    test(
      'useFullDownloadFallback מתקין את המסד המלא במקום ה-patches',
      () async {
        if (bindings == null) {
          markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
          return;
        }
        if (await const OtzariaProcessGuard().isAnyRunning(
          OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
        )) {
          markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
          return;
        }

        final dbPath = await installExistingDb(4, appliedTag: 'v4');
        final dbBytes = buildRealDb(5);
        final compressed = p.join(tempDir.path, 'full.db.zst');
        File(
          compressed,
        ).writeAsBytesSync(compressWithZstd(bindings, dbBytes), flush: true);

        final check = LibraryUpdateCheckResult(
          dbPath: dbPath,
          latestVersion: 5,
          latestContentTag: 'v5',
          plan: LibraryUpdatePlan.delta(
            localVersion: 4,
            targetVersion: 5,
            steps: const [],
            fullDownloadFallback: LibraryUpdatePlan.fullDownload(
              localVersion: 4,
              targetVersion: 5,
              asset: ReleaseAsset(
                name: 'seforim.db.zst',
                downloadUrl: compressed,
                size: File(compressed).lengthSync(),
              ),
              releaseTag: 'v5',
            ),
          ),
        );
        expect(check.canFallBackToFullDownload, isTrue);

        await _withoutNetwork((_) async {
          final manager = LibraryManager(dataDir: dataDir);
          await manager.applyUpdate(check, useFullDownloadFallback: true);

          expect(File(dbPath).readAsBytesSync(), dbBytes);
          expect(
            (await LibraryStateStore(
              p.join(dataDir, 'library_state.json'),
            ).loadAppliedRelease())?.tag,
            'v5',
          );
          manager.dispose();
        });
      },
    );

    test('בקשת מסלול חלופי שאינו קיים נכשלת במקום לא לעשות כלום', () async {
      final manager = LibraryManager(dataDir: dataDir);

      await expectLater(
        manager.applyUpdate(
          LibraryUpdateCheckResult(
            dbPath: p.join(tempDir.path, 'seforim.db'),
            plan: LibraryUpdatePlan.delta(
              localVersion: 4,
              targetVersion: 5,
              steps: const [],
            ),
          ),
          useFullDownloadFallback: true,
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            AppL10n.strings.libraryDomain.fullDbAssetMissingFromPlan,
          ),
        ),
      );
      manager.dispose();
    });

    test('תוכנית blocked זורקת LibraryApplyException עם הסיבה', () async {
      final manager = LibraryManager(dataDir: dataDir);

      await expectLater(
        manager.applyUpdate(
          LibraryUpdateCheckResult(
            dbPath: p.join(tempDir.path, 'seforim.db'),
            plan: LibraryUpdatePlan.blocked(
              localVersion: 4,
              targetVersion: 9,
              reason: 'אין מסלול',
            ),
          ),
        ),
        throwsA(
          isA<LibraryApplyException>().having(
            (e) => e.message,
            'message',
            'אין מסלול',
          ),
        ),
      );
      manager.dispose();
    });
  });

  group('קופסת ההגדרות של אוצריא נקראת פעם אחת בכל בדיקה', () {
    test('התקנה טרייה', () async {
      await writeMirror(tag: 'v5');
      final reader = _CountingSettingsReader();

      await _withoutNetwork((_) async {
        final manager = hermeticManager(settingsReader: reader);
        addTearDown(manager.dispose);
        expect((await manager.checkForUpdate()).isFreshInstall, isTrue);
      });

      expect(reader.reads, isNotEmpty);
      expect(reader.reads.values, everyElement(1));
    });

    test('מסד קיים', () async {
      await installExistingDb(5, appliedTag: 'v5');
      await writeMirror(tag: 'v5');
      final reader = _CountingSettingsReader();

      await _withoutNetwork((_) async {
        final manager = hermeticManager(settingsReader: reader);
        addTearDown(manager.dispose);
        expect((await manager.checkForUpdate()).isFreshInstall, isFalse);
      });

      expect(reader.reads, isNotEmpty);
      expect(reader.reads.values, everyElement(1));
    });

    test('סיום התקנה טרייה ב-applyUpdate', () async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return;
      }
      if (await const OtzariaProcessGuard().isAnyRunning(
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      )) {
        markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
        return;
      }
      final dbPath = p.join(tempDir.path, 'fresh-books', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);
      final check = freshCheck(dbPath);
      final reader = _CountingSettingsReader();
      final settingsRoot = p.posix.join(
        hermeticEnvironment()['HOME']!,
        '.local',
        'share',
        'otzaria',
      );

      await _withoutNetwork((_) async {
        final manager = hermeticManager(settingsReader: reader);
        addTearDown(manager.dispose);
        final notSet = <String>[];
        await manager.applyUpdate(check, onLibraryLocationNotSet: notSet.add);
        expect(notSet, [dbPath]);
      });

      expect(await File(dbPath).exists(), isTrue);
      expect(reader.reads, {settingsRoot: 1});
    });

    test('החיפוש החכם ב-applyUpdate', () async {
      if (await const OtzariaProcessGuard().isAnyRunning(
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      )) {
        markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
        return;
      }
      final dbPath = await installExistingDb(5, appliedTag: 'v5');
      final reader = _CountingSettingsReader(
        settings: const OtzariaSettings(
          searchFeedbackConsent: 'granted',
          searchFeedbackConsentVersion: 1,
        ),
      );
      final warnings = <String>[];

      await _withoutNetwork((_) async {
        final manager = hermeticManager(settingsReader: reader);
        addTearDown(manager.dispose);
        await manager.applyUpdate(
          LibraryUpdateCheckResult(
            dbPath: dbPath,
            semanticPending: true,
            semanticConsentGranted: true,
          ),
          onCompanionWarning: (_, error) => warnings.add('$error'),
        );
      });

      expect(
        warnings,
        isNot(
          anyElement(
            contains(AppL10n.strings.libraryDomain.semanticConsentRequired),
          ),
        ),
      );
      expect(reader.reads, isNotEmpty);
      expect(reader.reads.values, everyElement(1));
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

  /// אוצריא אינה סורקת את ברירת המחדל שלה (`getDatabasePath` נופל ל-`'.'`
  /// כשההגדרה ריקה), ולכן ספרייה טרייה חייבת להיכתב להגדרות שלה — אחרת היא
  /// נפתחת על ספרייה ריקה. הסביבה נדרסת לתיקייה זמנית: הבדיקה לא תיגע
  /// בהגדרות האמיתיות של מי שמריץ אותה.
  group('התקנה טרייה מכוונת את ההגדרות של אוצריא', () {
    late String otzariaRoot;
    late LibraryManager manager;

    /// מנהל עם סביבה מבודדת — `%APPDATA%` ו-`HOME` מצביעים לתיקייה זמנית.
    LibraryManager isolatedManager() {
      otzariaRoot = Platform.isWindows
          ? p.join(tempDir.path, 'Roaming', 'otzaria')
          : p.join(
              tempDir.path,
              'home',
              'Library',
              'Application Support',
              'otzaria',
            );
      return LibraryManager(
        dataDir: dataDir,
        operatingSystem: Platform.isWindows ? 'windows' : 'macos',
        environment: Platform.isWindows
            ? {'APPDATA': p.join(tempDir.path, 'Roaming')}
            : {'HOME': p.join(tempDir.path, 'home')},
      );
    }

    setUp(() {
      manager = isolatedManager();
      addTearDown(manager.dispose);
    });

    /// הבדיקות כאן מחילות בפועל, ולכן הן תלויות ב-zstd ובאוצריא סגורה —
    /// בדיוק כמו שאר בדיקות ה-`applyUpdate`.
    Future<bool> canApply() async {
      if (bindings == null) {
        markTestSkipped('אין ספריית zstd לטעינה בסביבה הזו');
        return false;
      }
      if (await const OtzariaProcessGuard().isAnyRunning(
        OtzariaProcessGuard.processNamesFor(Platform.operatingSystem),
      )) {
        markTestSkipped('אוצריא פתוחה — ההחלה נחסמת בכוונה');
        return false;
      }
      return true;
    }

    test('ההגדרה נכתבת, והקורא מוצא אחר כך את אותו מסד', () async {
      if (!await canApply()) return;
      final dbPath = p.join(otzariaRoot, 'books', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);

      final notSet = <String>[];
      await manager.applyUpdate(
        freshCheck(dbPath),
        onLibraryLocationNotSet: notSet.add,
      );

      expect(notSet, isEmpty);
      final settings = await const OtzariaSettingsReader().read(otzariaRoot);
      expect(settings?.resolveDbPath(path: p.context), dbPath);
    });

    // בחירה קיימת של המשתמש אינה נדרסת — אבל אז היא גם מצביעה למקום אחר,
    // וזה בדיוק המצב שבו צריך לומר לו להצביע ידנית.
    test('הגדרה קיימת שמצביעה למקום אחר מייצרת התרעה ולא נדרסת', () async {
      if (!await canApply()) return;
      await Directory(otzariaRoot).create(recursive: true);
      final other = p.join(tempDir.path, 'old-library', 'books');
      await const OtzariaSettingsWriter().pointLibraryAt(
        dataRootPath: otzariaRoot,
        dbPath: p.join(other, 'seforim.db'),
      );

      final dbPath = p.join(tempDir.path, 'usb', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);

      final notSet = <String>[];
      await manager.applyUpdate(
        freshCheck(dbPath),
        onLibraryLocationNotSet: notSet.add,
      );

      expect(notSet, [dbPath]);
      final settings = await const OtzariaSettingsReader().read(otzariaRoot);
      expect(settings?.libraryPath, other);
    });

    // קופסה פגומה/מוצפנת מוחזרת מהקורא כ-`null`, בדיוק כמו קופסה שאינה
    // קיימת. כתיבה לתוכה עלולה להחמיר, ולכן היא נחסמת.
    test('קופסה שלא ניתן לקרוא אינה נכתבת', () async {
      if (!await canApply()) return;
      await Directory(otzariaRoot).create(recursive: true);
      final boxFile = File(p.join(otzariaRoot, 'app_preferences.hive'));
      await boxFile.writeAsString('לא קופסת Hive בכלל');
      final before = await boxFile.readAsString();

      final dbPath = p.join(otzariaRoot, 'books', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);

      final notSet = <String>[];
      await manager.applyUpdate(
        freshCheck(dbPath),
        onLibraryLocationNotSet: notSet.add,
      );

      expect(notSet, [dbPath]);
      expect(await boxFile.readAsString(), before);
    });

    test('שורש נתונים שאינו קיים ואוצריא אינה מותקנת — לא נוצר כלום', () async {
      if (!await canApply()) return;
      final dbPath = p.join(tempDir.path, 'books', 'seforim.db');
      await Directory(p.dirname(dbPath)).create(recursive: true);

      final notSet = <String>[];
      await manager.applyUpdate(
        freshCheck(dbPath),
        onLibraryLocationNotSet: notSet.add,
      );

      expect(notSet, [dbPath]);
      expect(await Directory(otzariaRoot).exists(), isFalse);
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

    Map<String, Object?> release(
      String tag,
      List<String> assets, {
      bool draft = false,
      bool prerelease = false,
    }) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        for (final name in assets)
          {
            'name': name,
            'size': 10,
            'browser_download_url': 'https://example.invalid/$tag/$name',
          },
      ],
    };

    Future<List<String>> withReleases(
      List<Map<String, Object?>> releases,
      Future<void> Function() body,
    ) async {
      final vectorTags = <String>[];
      await http.runWithClient(
        body,
        () => MockClient((request) async {
          final path = request.url.path;
          if (path == '/repos/Otzaria/SeforimLibrary/releases') {
            return http.Response(jsonEncode(releases), 200);
          }
          const vectorsPrefix =
              '/repos/Otzaria/SeforimLibrary/releases/tags/vectors-';
          if (path.startsWith(vectorsPrefix)) {
            vectorTags.add(path.substring(vectorsPrefix.length));
            return http.Response('', 404);
          }
          fail('unexpected request ${request.url}');
        }),
      );
      return vectorTags;
    }

    test(
      'הגרסה הגבוהה שנושאת תוכן מסד נבחרת, והתג שלה עובר לחיפוש החכם',
      () async {
        final vectorTags = await withReleases(
          [
            release('v40-20261010000000', ['seforim.db.zst'], draft: true),
            release('v35-20261005000000', ['notes.txt']),
            release('lines-snapshot-sha256-abc', ['lines.json']),
            release('v33-20261003000000', [
              'patch-v31-v33.db.zst.manifest.json',
            ], prerelease: true),
            release('v29-20260920000000', ['seforim.db.zst']),
            release('v30-20260930165019', [
              'patch-v30-v31.db.zst.manifest.json',
            ]),
          ],
          () async {
            final manager = LibraryManager(dataDir: dataDir);
            try {
              expect(await manager.peekLatestOnlineVersion(), 31);
              expect(await manager.peekPendingSemanticSearch(), isFalse);
              manager.allowPrerelease = true;
              expect(await manager.peekLatestOnlineVersion(), 33);
              expect(await manager.peekPendingSemanticSearch(), isFalse);
            } finally {
              manager.dispose();
            }
          },
        );
        expect(vectorTags, ['v30-20260930165019', 'v33-20261003000000']);
      },
    );

    test('בלי release שנושא תוכן מסד — null, ואין בדיקת חיפוש חכם', () async {
      final vectorTags = await withReleases(
        [
          release('v35-20261005000000', ['notes.txt']),
          release('v34-20261004000000', ['seforim.db.zst'], draft: true),
        ],
        () async {
          final manager = LibraryManager(dataDir: dataDir);
          try {
            expect(await manager.peekLatestOnlineVersion(), isNull);
            expect(await manager.peekPendingSemanticSearch(), isFalse);
          } finally {
            manager.dispose();
          }
        },
      );
      expect(vectorTags, isEmpty);
    });
  });
}

class _CountingSettingsReader extends OtzariaSettingsReader {
  _CountingSettingsReader({this.settings});

  final OtzariaSettings? settings;
  final Map<String, int> reads = {};

  @override
  Future<OtzariaSettings?> read(String dataRootPath) {
    reads.update(dataRootPath, (count) => count + 1, ifAbsent: () => 1);
    final fixed = settings;
    return fixed != null ? Future.value(fixed) : super.read(dataRootPath);
  }
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

class _GatedApplier extends LibraryUpdateApplier {
  _GatedApplier(this.newDbBytes);

  final Uint8List newDbBytes;
  final staged = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<void> applyFullDownload({
    required LibraryUpdatePlan plan,
    required String dbPath,
    void Function(LibraryApplyProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    File('$dbPath.new').writeAsBytesSync(newDbBytes);
    File('$dbPath.applying').writeAsStringSync('{"fromVersion":4}');
    File('$dbPath.download.zst').writeAsStringSync('staged');
    staged.complete();
    await gate.future;
    File('$dbPath.new').renameSync(dbPath);
    File('$dbPath.applying').deleteSync();
  }
}
