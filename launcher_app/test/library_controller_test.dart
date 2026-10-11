import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'test_support.dart';

/// בדיקות ל-[LibraryModuleController], תחת חסימת רשת מלאה: מסלול הבדיקה
/// חייב לעבוד מהתיקייה המקומית בלבד, ו"אין מראה" הוא מצב תקין ולא שגיאה.
void main() {
  late Directory tempDir;
  late LibraryModuleController controller;

  /// קובץ DB מדומה שמוצבים עליו במפורש, כדי שהבדיקה לא תיגע ב-`seforim.db`
  /// האמיתי של מי שמריץ אותה.
  late File fakeDb;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('library-ctrl-');
    fakeDb = File(p.join(tempDir.path, 'library', 'seforim.db'))
      ..parent.createSync(recursive: true)
      ..createSync();
    HttpOverrides.global = NoNetworkHttpOverrides();
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
    controller = LibraryModuleController(dataDir: tempDir.path);
  });

  tearDown(() async {
    controller.dispose();
    HttpOverrides.global = null;
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  group('checkForUpdate בלי מראה מקומית', () {
    test('אין מראה = needsDownload, לא שגיאה', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.status, LibraryModuleStatus.needsDownload);
      expect(controller.errorMessage, isNull);
      expect(controller.localVersion, isNull);
      expect(controller.targetVersion, isNull);
    });

    test('מסד אמיתי שנבחר ידנית — הגרסה מוצגת גם לפני שהורדה מראה', () async {
      // הדיווח שהוליד את הבדיקה: אחרי בחירה ידנית המסך הראה "לא ידוע",
      // כי הבדיקה קראה את הגרסה ואז נפלה על היעדר מראה.
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'picked', 18));

      expect(controller.status, LibraryModuleStatus.needsDownload);
      expect(controller.localVersion, 18);
    });

    // A locked DB is a local error with its own message; the flag keeps the
    // screen from labelling the mirror as the culprit.
    test('locked local DB is an error flagged as local, not a mirror fault',
        () async {
      final dbPath = _dbWithVersion(tempDir, 'locked', 26);
      await controller.setCustomDbPath(dbPath);
      expect(controller.localDbUnreadable, isFalse);

      final writer = sqlite3.sqlite3.open(dbPath);
      try {
        writer.execute('BEGIN EXCLUSIVE');
        writer.execute(
            "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'");
        await controller.checkForUpdate();
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
      }
      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.localDbUnreadable, isTrue);
      expect(
          controller.errorMessage, AppL10n.strings.libraryDomain.localDbLocked);

      await controller.checkForUpdate();
      expect(controller.localDbUnreadable, isFalse);
      expect(controller.status, LibraryModuleStatus.needsDownload);
    });

    // "No DB found" would be wrong here: the DB exists but is locked.
    test('capturing from a locked DB reports the lock, not "not found"',
        () async {
      final dbPath = _dbWithVersion(tempDir, 'locked-capture', 26);
      await controller.setCustomDbPath(dbPath);

      final writer = sqlite3.sqlite3.open(dbPath);
      try {
        writer.execute('BEGIN EXCLUSIVE');
        writer.execute(
            "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'");
        expect(await controller.capturePersonalVersion(), isFalse);
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
      }
      expect(controller.personalCaptureError,
          AppL10n.strings.libraryDomain.localDbLocked);
      expect(controller.personalFromVersion, isNull);

      expect(await controller.capturePersonalVersion(), isTrue);
      expect(controller.personalCaptureError, isNull);
    });

    test('נתיב ה-DB מתגלה ונשמר — לא מונח מראש', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.dbPath, fakeDb.path);
    });

    // מצב "עדכון אישי": נקודת המוצא נרשמת אך ורק בלחיצה, ולכן בדיקה שגרתית
    // חייבת להשאיר אותה ריקה — אחרת אוצריא שעל המחשב המקוון הייתה נקבעת
    // במקום זו של המחשב שבשבילו מורידים.
    test('בדיקה שגרתית אינה רושמת גרסה לעדכון אישי', () async {
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'auto', 18));

      expect(controller.localVersion, 18);
      expect(controller.personalFromVersion, isNull);
    });

    test('לחיצה על "זהה את גרסת המסד שלי" רושמת, ובדיקה חוזרת קוראת', () async {
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'picked', 18));

      expect(await controller.capturePersonalVersion(), isTrue);
      expect(controller.personalFromVersion, 18);

      // הרשומה יושבת בקובץ ה-state שנוסע על הכונן — ולכן שורדת בדיקה חדשה.
      await controller.checkForUpdate();
      expect(controller.personalFromVersion, 18);
    });

    test('לחיצה על מסד בלי db_version מדווחת כשל, ולא רושמת', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(await controller.capturePersonalVersion(), isFalse);
      expect(controller.personalFromVersion, isNull);
      expect(controller.personalCaptureError, isNull);
    });

    test('update לפני בדיקה אינו עושה דבר', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.update();

      expect(notifications, 0);
      expect(controller.status, LibraryModuleStatus.idle);
    });
  });

  group('checkOnline — כשל רשת נבלע', () {
    test('אין חיבור: נשמר ב-onlineCheckError ואינו הופך לשגיאת מודול',
        () async {
      await controller.checkOnline();

      expect(controller.onlineLatestVersion, isNull);
      expect(controller.onlineCheckError, isNotNull);
      expect(controller.onlineCheckedAt, isNotNull);
      expect(controller.status, LibraryModuleStatus.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.hasOnlineUpdate, isFalse);
      expect(controller.onlineCompanionsCheckError, isNotNull);
      expect(controller.onlinePendingCompanions, isEmpty);
    });

    test('מראה בלי אף נלווה נאמרת, ומראה חסרה — לא', () {
      controller.status = LibraryModuleStatus.upToDate;
      controller.mirrorMissing = false;
      controller.mirroredCompanions = const {};
      expect(controller.mirrorLacksCompanions, isTrue);

      controller.mirroredCompanions = {CompanionAsset.catalog};
      expect(controller.mirrorLacksCompanions, isFalse);

      controller.mirroredCompanions = const {};
      controller.mirrorMissing = true;
      expect(controller.mirrorLacksCompanions, isFalse);
    });

    test('hasOnlineUpdate כבוי כל עוד לא נבדק ברשת', () {
      controller.targetVersion = 5;

      expect(controller.hasOnlineUpdate, isFalse);
    });
  });

  group('מצב הרשת אחרי הורדה', () {
    for (final remaining in [
      <CompanionAsset>{},
      {CompanionAsset.dictionary}
    ]) {
      test('ההורדה מרעננת את הנלווים שנותרו: $remaining', () async {
        controller.dispose();
        final manager = _DownloadManager(tempDir.path, remaining);
        controller = LibraryModuleController(
          dataDir: tempDir.path,
          manager: manager,
        );
        controller.targetVersion = 30;
        await controller.checkOnline();
        expect(controller.hasOnlineUpdate, isTrue);

        await controller.download();

        expect(controller.downloadStatus, MirrorDownloadStatus.done);
        expect(controller.onlinePendingCompanions, remaining);
        expect(controller.hasOnlineUpdate, remaining.isNotEmpty);
      });
    }
  });

  group('downloadProgress — חישוב המד', () {
    test('בלי שום דיווח אין אחוז', () {
      expect(controller.downloadProgress, isNull);
    });

    test('הבייטים מתארים את כל ההורדה, ולכן הם המד', () {
      controller.downloadReceivedBytes = 250;
      controller.downloadTotalBytes = 1000;

      expect(controller.downloadProgress, 0.25);
    });

    test('ספירת הנכסים אינה מדללת את הבייטים', () {
      controller.downloadDoneAssets = 1;
      controller.downloadTotalAssets = 4;
      controller.downloadReceivedBytes = 500;
      controller.downloadTotalBytes = 1000;

      expect(controller.downloadProgress, 0.5);
    });

    test('סה"כ בייטים לא ידוע — מתקדם לפי ספירת הנכסים בלבד', () {
      controller.downloadDoneAssets = 2;
      controller.downloadTotalAssets = 4;

      expect(controller.downloadProgress, 0.5);
    });

    test('יעד 0 (הכול כבר על הכונן) נופל לספירת הנכסים ולא מתפוצץ', () {
      controller.downloadReceivedBytes = 0;
      controller.downloadTotalBytes = 0;
      expect(controller.downloadProgress, isNull);

      controller.downloadDoneAssets = 2;
      controller.downloadTotalAssets = 2;
      expect(controller.downloadProgress, 1.0);
    });

    test('ערכים חריגים נחתכים ל-0..1 ואינם מפילים את המד', () {
      controller.downloadReceivedBytes = 5000;
      controller.downloadTotalBytes = 1000;
      expect(controller.downloadProgress, 1.0);

      controller.downloadTotalBytes = 0;
      expect(controller.downloadProgress, isNull);

      controller.downloadDoneAssets = 9;
      controller.downloadTotalAssets = 4;
      expect(controller.downloadProgress, 1.0);
    });
  });

  group('hasOnlineUpdate נמדד מול המראה', () {
    test('נכס רשום חסר או חלקי דורש הורדה, נכס שלם אינו דורש', () async {
      final archive = File(p.join(
          controller.mirrorDir, 'assets', 'v31', 'seforim-schema6.db.zst'));
      await archive.parent.create(recursive: true);
      await File(p.join(controller.mirrorDir, 'releases.json'))
          .writeAsString(jsonEncode({
        'formatVersion': 1,
        'releases': [
          {
            'tag': 'v31',
            'assets': [
              {
                'name': 'seforim-schema6.db.zst',
                'downloadUrl': 'assets/v31/seforim-schema6.db.zst',
                'size': 4,
              }
            ],
          }
        ],
      }));
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'v31', 31));
      expect(controller.downloadNeedsRetry, isTrue);
      await archive.writeAsBytes([1, 2, 3]);
      await controller.checkForUpdate();
      expect(controller.downloadNeedsRetry, isTrue);
      await archive.writeAsBytes([1, 2, 3, 4]);
      await File('${archive.path}.resume').writeAsString('asset-id\n"etag"');
      await controller.checkForUpdate();
      expect(controller.downloadNeedsRetry, isFalse);
    });
    test('V31 חלקי מחזיר הצעת הורדה גם כשהגרסה הרשומה מעודכנת', () async {
      _writeMirror(tempDir, releases: [
        const _MirrorRelease('v31-20261004170255',
            patches: [_MirrorPatch(29, 31, toSchema: 7)])
      ]);
      final index = File(p.join(controller.mirrorDir, 'releases.json'));
      final metadata = jsonDecode(await index.readAsString()) as Map;
      final assets = (metadata['releases'] as List).single['assets'] as List;
      assets
          .removeWhere((asset) => !(asset['name'] as String).endsWith('.json'));
      for (final asset in assets) {
        asset['size'] = await File(
                p.join(controller.mirrorDir, asset['downloadUrl'] as String))
            .length();
      }
      await index.writeAsString(jsonEncode(metadata));
      final partial = File(p.join(controller.mirrorDir, 'assets',
          'v31-20261004170255', 'seforim-schema6.db.zst'));
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes([1, 2, 3]);
      await File('${partial.path}.resume').writeAsString('610745538\n"etag"');
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'v31', 31));
      controller.onlineLatestVersion = 31;

      expect(controller.hasOnlineUpdate, isTrue);

      await partial.delete();
      await File('${partial.path}.resume').delete();
      await controller.checkForUpdate();
      expect(controller.hasOnlineUpdate, isFalse);

      assets.single['size'] = 0;
      await index.writeAsString(jsonEncode(metadata));
      await controller.checkForUpdate();
      expect(controller.downloadNeedsRetry, isFalse);
    });
    test('חיפוש חכם חדש מדליק עדכון גם כשהספרייה והנלווים מעודכנים', () {
      controller.onlineLatestVersion = 30;
      controller.targetVersion = 30;
      controller.onlineSemanticPending = true;

      expect(controller.hasOnlineUpdate, isTrue);
      expect(controller.onlineUpdateVersion, isNull);
      expect(controller.onlinePendingCompanionNames,
          AppL10n.strings.libraryDomain.companionSemanticName);
    });

    // חיפוש חכם שכבר בכונן הוצע בכל הורדה, ו"כן" הוריד מחדש את כל הספרייה.
    test('שאלת החיפוש החכם רק כשהבדיקה לא הוכיחה שהוא בכונן', () {
      expect(controller.shouldOfferSemanticDownload, isTrue,
          reason: 'בדיקה שלא רצה אינה הוכחה');

      controller.onlineCheckedAt = DateTime.now();
      expect(controller.shouldOfferSemanticDownload, isFalse);

      controller.onlineSemanticPending = true;
      expect(controller.shouldOfferSemanticDownload, isTrue);

      controller.onlineSemanticPending = false;
      controller.onlineSemanticCheckError = 'rate limit';
      expect(controller.shouldOfferSemanticDownload, isTrue);

      controller.onlineSemanticCheckError = null;
      controller.onlineCheckError = 'offline';
      expect(controller.shouldOfferSemanticDownload, isTrue);
    });

    test('כשל בבדיקת החיפוש החכם אינו הוכחה שאין עדכון', () {
      controller.onlineLatestVersion = 30;
      controller.targetVersion = 30;
      controller.onlineSemanticCheckError = 'rate limit';

      expect(controller.onlineProofError, 'rate limit');
      expect(controller.hasOnlineUpdate, isFalse);
    });
    test('גרסה גבוהה יותר ברשת מדליקה, שווה/נמוכה מכבה', () {
      controller.onlineLatestVersion = 20;
      controller.targetVersion = 19;
      expect(controller.hasOnlineUpdate, isTrue);

      controller.targetVersion = 20;
      expect(controller.hasOnlineUpdate, isFalse);

      controller.targetVersion = 21;
      expect(controller.hasOnlineUpdate, isFalse);
    });

    // כונן ריק במחשב שיש עליו אוצריא מעודכנת: השוואה לגרסת המסד החי הייתה
    // מכבה את ההודעה, מסתירה את כפתור ההורדה היחיד, ומדלגת על הספרייה
    // ב-downloadAll — הכונן נוסע ריק בלי שאיש יידע.
    test('בלי מראה בכלל יש מה להוריד, גם כשהמסד החי מעודכן', () {
      controller.onlineLatestVersion = 20;
      controller.targetVersion = null;
      controller.localVersion = 20;
      controller.mirrorMissing = true;

      expect(controller.hasOnlineUpdate, isTrue);
    });

    // issue #33: מסד עדכני בכונן שאין בו תלמוד — בלי זה לא הוצג כפתור הורדה,
    // downloadAll דילג על הספרייה, והנלווים לא הגיעו לכונן לעולם.
    test('נלווה שממתין ברשת מדליק, בלי לטעון לגרסת מסד חדשה', () {
      controller.onlineLatestVersion = 28;
      controller.targetVersion = 28;
      controller.onlinePendingCompanions = {CompanionAsset.talmud};

      expect(controller.hasOnlineUpdate, isTrue);
      expect(controller.onlineUpdateVersion, isNull);
    });

    test('כשל בבדיקת הנלווים שולל את ההוכחה, לא את תשובת המסד', () {
      controller.onlineLatestVersion = 28;
      controller.targetVersion = 28;
      controller.onlineCompanionsCheckError = 'rate limit';

      expect(controller.onlineCheckError, isNull);
      expect(controller.onlineProofError, 'rate limit');
      expect(controller.hasOnlineUpdate, isFalse);
    });

    test('מראה קיימת בלי תוכנית עדיין נמדדת מול הגרסה המקומית', () {
      controller.onlineLatestVersion = 20;
      controller.targetVersion = null;
      controller.localVersion = 20;
      controller.mirrorMissing = false;

      expect(controller.hasOnlineUpdate, isFalse);
    });
  });

  /// עדכון מסד שנעשה כאן משאיר את אינדקס החיפוש של אוצריא על התוכן הישן,
  /// והסימון שלצד המסד הוא מה שמזכיר לנו לבקש ממנה לתקן. ראו AGENTS §5.
  group('בקשת עדכון האינדקס שממתינה', () {
    /// כותב סימון "אמיתי" — דרך אותו שירות שכותב אותו ב-`applyUpdate`.
    Future<void> writeNotice(
            {String route = ExternalUpdateNotice.routeDelta}) =>
        const ExternalUpdateNotice().write(
          dbPath: fakeDb.path,
          route: route,
          booksTouched: {4, 11},
          dbVersion: 30,
        );

    test('בלי סימון אין בקשה ממתינה', () async {
      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.hasPendingReindex, isFalse);
      expect(controller.pendingReindex, isNull);
    });

    // הסימון יושב לצד המסד ולכן שורד הפעלה מחדש של הלאנצ'ר: בדיקה בעלייה
    // חייבת למצוא בקשה שנכתבה בהרצה קודמת ולא נמסרה.
    test('סימון מהרצה קודמת נקרא בבדיקה, ולא רק אחרי עדכון', () async {
      await writeNotice();

      await controller.setCustomDbPath(fakeDb.path);

      expect(controller.hasPendingReindex, isTrue);
      expect(controller.pendingReindex!.booksTouched, {4, 11});
      expect(controller.pendingReindex!.dbVersion, 30);
    });

    test('מסירה מוצלחת מוחקת את הסימון מהדיסק', () async {
      await writeNotice(route: ExternalUpdateNotice.routeFull);
      await controller.setCustomDbPath(fakeDb.path);
      expect(controller.hasPendingReindex, isTrue);

      await controller.markReindexRequestDelivered();

      expect(controller.hasPendingReindex, isFalse);
      expect(
        File(p.join(fakeDb.parent.path, ExternalUpdateNotice.fileName))
            .existsSync(),
        isFalse,
      );
      // ובדיקה חוזרת אינה מחזירה אותה לחיים.
      await controller.checkForUpdate();
      expect(controller.hasPendingReindex, isFalse);
    });

    test('סימון שלא נמסר נשאר גם אחרי בדיקה חוזרת', () async {
      await writeNotice();
      await controller.setCustomDbPath(fakeDb.path);

      await controller.checkForUpdate();

      expect(controller.hasPendingReindex, isTrue);
    });

    test('markReindexRequestDelivered בלי בקשה ממתינה אינו עושה דבר', () async {
      await controller.setCustomDbPath(fakeDb.path);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.markReindexRequestDelivered();

      expect(notifications, 0);
    });
  });

  // הרגרסיה של גרסה 0.11: המראה החזיקה מסד מלא של v21 ושרשרת patches אל
  // v26 חצתה לסכמה 4, והבדיקה תכננה להחליף מסד v23 חי במסד v21 — ואז נכשלה
  // על הצעד שחוצה את הסכמה. סכמה 4 נתמכת מאז; כאן משתמשים בסכמה עתידית כדי
  // לשמר את התרחיש. ראו CHANGELOG.
  group('סכמה שאיננו יודעים להחיל', () {
    test('מסד מלא ישן מזה שמותקן אינו עדכון אלא חסימה מנומקת', () async {
      _writeMirror(tempDir, releases: [
        const _MirrorRelease('v21', hasFullDb: true),
        const _MirrorRelease('v22', patches: [_MirrorPatch(21, 22)]),
        const _MirrorRelease('v26',
            patches: [_MirrorPatch(22, 26, toSchema: 7)]),
      ]);
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.error);
      expect(
        controller.errorMessage,
        AppL10n.strings.libraryDomain.planFullDbWouldNotProgress(21, 23, 26),
      );
    });

    test('מסד מלא של הגרסה החדשה מורד, עם נימוק שמוצג למשתמש', () async {
      _writeMirror(tempDir, releases: [
        const _MirrorRelease('v21', hasFullDb: true),
        const _MirrorRelease('v26',
            patches: [_MirrorPatch(22, 26, toSchema: 7)], hasFullDb: true),
      ]);
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.updateAvailable);
      expect(controller.targetVersion, 26);
      expect(
        controller.updateRouteNote,
        AppL10n.strings.libraryDomain.planNewSchemaNeedsFullDb(26, 7),
      );
    });

    // צורת המראה שעל הכונן בפועל: מסד מלא של v21, קובצי עדכון עד v23,
    // ומעליהם גרסה בסכמה שאיננו מכירים. מסד v22 חייב לטפס ל-23, לא להיחסם.
    test('מסד שיכול לטפס בקובצי עדכון עושה זאת, ומקבל הסבר', () async {
      _writeMirror(tempDir, releases: [
        const _MirrorRelease('v21', hasFullDb: true),
        const _MirrorRelease('v23',
            patches: [_MirrorPatch(21, 23), _MirrorPatch(22, 23)]),
        const _MirrorRelease('v26',
            patches: [_MirrorPatch(22, 26, toSchema: 7)]),
      ]);
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 22));

      expect(controller.status, LibraryModuleStatus.updateAvailable);
      expect(controller.targetVersion, 23);
      expect(
        controller.updateRouteNote,
        AppL10n.strings.libraryDomain.planPartialDeltaSchemaStop(23, 26, 7),
      );
    });

    test('כשכל הסכמות מוכרות אין נימוק מיוחד — מסלול דלתא רגיל', () async {
      _writeMirror(tempDir, releases: [
        const _MirrorRelease('v21', hasFullDb: true),
        const _MirrorRelease('v24', patches: [_MirrorPatch(23, 24)]),
      ]);
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.updateAvailable);
      expect(controller.targetVersion, 24);
      expect(controller.updateRouteNote, isNull);
    });
  });

  // המחשב המקוון: הוריד עדכון אישי בשביל מחשב אחר, ולכן אין במראה מסלול
  // שמתאים לו. זו הייתה הודעה אדומה שהבהילה בלי סיבה.
  group('עדכון אישי שנבנה למחשב אחר', () {
    /// מראה של עדכון אישי: קובצי עדכון מגרסה 30 בלבד, בלי מסד מלא.
    void writePersonalMirror() => _writeMirror(tempDir, releases: [
          const _MirrorRelease('v31', patches: [_MirrorPatch(30, 31)]),
        ]);

    test('מחשב שלא נרשם מקבל מצב מוסבר, לא שגיאה', () async {
      controller.personalUpdateMode = true;
      writePersonalMirror();
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.personalTargetElsewhere);
      expect(controller.errorMessage, isNull);
      expect(controller.personalTargetIsThisMachine, isFalse);
    });

    test('אחרי שנרשם, אותה חסימה חוזרת להיות שגיאה אמיתית', () async {
      controller.personalUpdateMode = true;
      writePersonalMirror();
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(await controller.capturePersonalVersion(), isTrue);

      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.errorMessage, isNotNull);
      expect(controller.personalTargetIsThisMachine, isTrue);
    });

    test('כשהמצב כבוי כל מחשב הוא יעד, והחסימה נשארת שגיאה', () async {
      writePersonalMirror();
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.personalTargetIsThisMachine, isTrue);
    });
  });
}

class _DownloadManager extends LibraryManager {
  _DownloadManager(String dataDir, this.remaining) : super(dataDir: dataDir);

  final Set<CompanionAsset> remaining;
  bool downloaded = false;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async =>
      const LibraryUpdateCheckResult(dbPath: null);

  @override
  Future<int> peekLatestOnlineVersion() async => 30;

  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async =>
      downloaded ? remaining : {CompanionAsset.dictionary};

  @override
  Future<bool> peekPendingSemanticSearch() async => false;

  @override
  Future<MirrorDownloadOutcome> downloadToMirror({
    bool includeSemanticSearch = false,
    void Function(String stage)? onStage,
    void Function(String? stage)? onCompanionStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(String warning)? onWarning,
    bool Function()? isCancelled,
  }) async {
    downloaded = true;
    return const MirrorDownloadOutcome();
  }
}

/// מסד sqlite אמיתי עם `db_version` — הקורא (`LocalDbVersionReader`) פותח
/// את הקובץ בפועל, ולכן קובץ ריק אינו מספיק.
String _dbWithVersion(Directory tempDir, String folder, int version) {
  final file = File(p.join(tempDir.path, folder, 'seforim.db'))
    ..parent.createSync(recursive: true);
  final db = sqlite3.sqlite3.open(file.path);
  db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
  db.execute("INSERT INTO schema_meta VALUES ('db_version', '$version')");
  db.close();
  return file.path;
}

/// כותב מראה מקומית מינימלית תחת `<dataDir>/mirror/library`: `releases.json`
/// וקובצי ה-manifest שהוא מצביע עליהם. קובצי ה-patch עצמם אינם נדרשים —
/// הבדיקה עוצרת בתכנון ולא מחילה דבר.
void _writeMirror(
  Directory tempDir, {
  required List<_MirrorRelease> releases,
}) {
  final root = Directory(p.join(tempDir.path, 'mirror', 'library'))
    ..createSync(recursive: true);
  final json = <Map<String, Object?>>[];
  for (final release in releases) {
    final dir = Directory(p.join(root.path, 'assets', release.tag))
      ..createSync(recursive: true);
    final assets = <Map<String, Object?>>[];
    for (final patch in release.patches) {
      final patchFile = 'patch-v${patch.from}-v${patch.to}.db.zst';
      File(p.join(dir.path, '$patchFile.manifest.json')).writeAsStringSync(
        jsonEncode({
          'fromVersion': patch.from,
          'toVersion': patch.to,
          'fromSchemaVersion': patch.fromSchema,
          'toSchemaVersion': patch.toSchema,
          'fromContentHash': 'from${patch.from}',
          'toContentHash': 'to${patch.to}',
          'patchFiles': [
            {
              'file': patchFile,
              'compression': 'zstd',
              'sha256': 'a' * 64,
              'size': 1000,
              'uncompressedSha256': 'b' * 64,
              'uncompressedSize': 2000,
            },
          ],
        }),
      );
      for (final name in ['$patchFile.manifest.json', patchFile]) {
        assets.add({
          'name': name,
          'downloadUrl': p.join('assets', release.tag, name),
          'size': 1000,
        });
      }
    }
    if (release.hasFullDb) {
      assets.add({
        'name': 'seforim.db.zst',
        'downloadUrl': p.join('assets', release.tag, 'seforim.db.zst'),
        'size': 1500000000,
      });
    }
    json.add({
      'tag': release.tag,
      'isPrerelease': false,
      'isDraft': false,
      'assets': assets,
    });
  }
  File(p.join(root.path, 'releases.json')).writeAsStringSync(jsonEncode({
    'formatVersion': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'releases': json,
  }));
}

class _MirrorPatch {
  const _MirrorPatch(this.from, this.to, {this.toSchema = 2});
  final int from;
  final int to;

  /// סכמת המקור היא תמיד 2 — הגרסאות שבמראה מתחילות ממנה, ומה שמעניין
  /// כאן הוא היעד: v26 היא הראשונה שקפצה לסכמה 4.
  int get fromSchema => 2;
  final int toSchema;
}

class _MirrorRelease {
  const _MirrorRelease(
    this.tag, {
    this.patches = const [],
    this.hasFullDb = false,
  });
  final String tag;
  final List<_MirrorPatch> patches;
  final bool hasFullDb;
}
