import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/online_check.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart'
    show
        OtzariaArch,
        OtzariaInstallerKind,
        OtzariaManager,
        OtzariaRelease,
        OtzariaTargetPlatform;
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
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
    controller = LibraryModuleController(
      dataDir: tempDir.path,
      manager: LibraryManager(
        dataDir: tempDir.path,
        operatingSystem: 'linux',
        environment: {'HOME': p.join(tempDir.path, 'home')},
      ),
    );
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

    test('releases.json פגום — הודעה ברורה, וההורדה ברשת מוצעת (issue #127)',
        () async {
      final releases = File(
        p.join(tempDir.path, 'mirror', 'library', 'releases.json'),
      )..parent.createSync(recursive: true);
      releases.writeAsBytesSync([0x52, 0x49, 0x46, 0x46, 0xFF, 0xFE, 0x00]);

      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'picked', 32));

      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.mirrorDamaged, isTrue);
      expect(
        controller.errorMessage,
        AppL10n.strings.libraryDomain.mirrorDamaged,
      );
      expect(controller.localVersion, 32);

      // גרסה ישנה שנשארה מבדיקה קודמת אינה "הכונן כבר מחזיק את 32".
      controller.targetVersion = 32;
      controller.onlineLatestVersion = 32;
      controller.onlineCheckedAt = DateTime.now();
      expect(controller.hasOnlineUpdate, isTrue);
    });

    test('mirrorDamaged נשאר דלוק בזמן בדיקה חוזרת, ואין גרסת יעד', () async {
      controller.dispose();
      final manager = _DamagedMirrorManager(tempDir.path);
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );
      controller.targetVersion = 31;
      await controller.checkForUpdate();
      expect(controller.mirrorDamaged, isTrue);
      expect(controller.targetVersion, isNull);

      final gate = manager.gate = Completer<void>();
      final recheck = controller.checkForUpdate();
      await manager.entered.future;
      expect(controller.mirrorDamaged, isTrue);
      gate.complete();
      await recheck;
      expect(controller.mirrorDamaged, isTrue);
    });

    void useShortBusyTimeout() {
      controller.dispose();
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: LibraryManager(
          dataDir: tempDir.path,
          operatingSystem: 'linux',
          environment: {'HOME': p.join(tempDir.path, 'home')},
          versionReader: const LocalDbVersionReader(
            busyTimeout: Duration(milliseconds: 50),
          ),
        ),
      );
    }

    test(
      'locked local DB is an error flagged as local, not a mirror fault',
      () async {
        useShortBusyTimeout();
        final dbPath = _dbWithVersion(tempDir, 'locked', 26);
        await controller.setCustomDbPath(dbPath);
        expect(controller.localDbUnreadable, isFalse);

        final writer = sqlite3.sqlite3.open(dbPath);
        try {
          writer.execute('BEGIN EXCLUSIVE');
          writer.execute(
            "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'",
          );
          await controller.checkForUpdate();
        } finally {
          writer.execute('ROLLBACK');
          writer.close();
        }
        expect(controller.status, LibraryModuleStatus.error);
        expect(controller.localDbUnreadable, isTrue);
        expect(controller.needsElevation, isFalse);
        expect(
          controller.errorMessage,
          AppL10n.strings.libraryDomain.localDbLocked,
        );

        await controller.checkForUpdate();
        expect(controller.localDbUnreadable, isFalse);
        expect(controller.status, LibraryModuleStatus.needsDownload);
      },
    );

    test(
        'only a write-protected location offers elevation, not a hot '
        'journal the read-only reader hit or a lock', () {
      bool offers(LocalDbUnreadableReason reason) =>
          LibraryModuleController.unreadableDbNeedsElevation(
            LocalDbUnreadableException(reason, 0, ''),
          );
      expect(offers(LocalDbUnreadableReason.interruptedWrite), isFalse);
      expect(offers(LocalDbUnreadableReason.readOnlyLocation), isTrue);
      expect(offers(LocalDbUnreadableReason.locked), isFalse);
      expect(
        LibraryModuleController.unreadableDbNeedsElevation(StateError('other')),
        isFalse,
      );
    });

    test(
        'a hot journal offers elevation only when the read-write health '
        'check hit it on a write-protected DB', () {
      final crashed = _hotJournalDb(tempDir);
      Object thrownBy(void Function() body) {
        try {
          body();
        } catch (e) {
          return e;
        }
        fail('expected an exception');
      }

      final fromReader = thrownBy(
        () => const LocalDbVersionReader().read(crashed),
      );
      expect(
        fromReader,
        isA<LocalDbUnreadableException>().having(
          (e) => e.reason,
          'reason',
          LocalDbUnreadableReason.interruptedWrite,
        ),
      );
      expect(
        LibraryModuleController.unreadableDbNeedsElevation(fromReader),
        isFalse,
      );

      _setReadOnly(crashed, true);
      try {
        final fromHealthCheck = thrownBy(
          () => const OfflineLibraryDbRecoveryService()
              .checkDbHealthAfterCrash(crashed),
        );
        expect(
          fromHealthCheck,
          isA<LocalDbUnreadableException>().having(
            (e) => e.reason,
            'reason',
            LocalDbUnreadableReason.readOnlyLocation,
          ),
        );
        expect(
          LibraryModuleController.unreadableDbNeedsElevation(fromHealthCheck),
          isTrue,
        );
      } finally {
        _setReadOnly(crashed, false);
      }
    });

    // "No DB found" would be wrong here: the DB exists but is locked.
    test(
      'capturing from a locked DB reports the lock, not "not found"',
      () async {
        useShortBusyTimeout();
        final dbPath = _dbWithVersion(tempDir, 'locked-capture', 26);
        await controller.setCustomDbPath(dbPath);

        final writer = sqlite3.sqlite3.open(dbPath);
        try {
          writer.execute('BEGIN EXCLUSIVE');
          writer.execute(
            "UPDATE schema_meta SET value = '27' WHERE key = 'db_version'",
          );
          expect(await controller.capturePersonalVersion(), isFalse);
        } finally {
          writer.execute('ROLLBACK');
          writer.close();
        }
        expect(
          controller.personalCaptureError,
          AppL10n.strings.libraryDomain.localDbLocked,
        );
        expect(controller.personalFromVersion, isNull);

        expect(await controller.capturePersonalVersion(), isTrue);
        expect(controller.personalCaptureError, isNull);
      },
    );

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

  group('ספרייה שדורשת אוצריא חדשה יותר', () {
    Future<String?> blockedMessage(String? mirroredOtzaria) async {
      controller.dispose();
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        mirroredOtzariaUpdate: () async => mirroredOtzaria,
        manager: _NeedsNewerOtzariaManager(tempDir.path),
      );
      await controller.checkForUpdate();
      expect(controller.status, LibraryModuleStatus.error);
      return controller.errorMessage;
    }

    test('אוצריא חדשה בכונן שקוראת את הספרייה — מוצע הסדר הנכון', () async {
      expect(
        await blockedMessage('0.9.98'),
        AppL10n.strings.libraryDomain.libraryNeedsOtzariaUpdateFromDrive(
          '0.9.98',
        ),
      );
    });

    test('בלי אוצריא מתאימה בכונן — נשאר ההסבר של התוכנית', () async {
      final reason = AppL10n.strings.libraryDomain.planOtzariaTooOldForLibrary(
        5,
        31,
      );
      expect(await blockedMessage(null), reason);
      expect(await blockedMessage('0.9.97+800'), reason);
    });
  });

  group('checkOnline — כשל רשת נבלע', () {
    test(
      'אין חיבור: נשמר ב-onlineCheckError ואינו הופך לשגיאת מודול',
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
      },
    );

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

    test('בדיקת המסד ובדיקת הנלווים רצות במקביל', () async {
      controller.dispose();
      final manager = _ConcurrentPeekManager(tempDir.path);
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );

      await controller.checkOnline();

      expect(controller.onlineCheckError, isNull);
      expect(controller.onlineLatestVersion, 30);
      expect(controller.onlineCompanionsCheckError, isNull);
      expect(controller.onlinePendingCompanions, {CompanionAsset.talmud});
    });

    // "לא ידוע איזה פרסום יותקן" אינו "אין חיפוש חכם להוריד".
    test('יעד חיפוש חכם לא ידוע אינו נחשב בדיקה מעודכנת', () async {
      controller.dispose();
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: _UnknownSemanticManager(tempDir.path),
      );
      controller.targetVersion = 30;

      await controller.checkOnline();

      expect(controller.onlineCheckError, isNull);
      expect(controller.onlineSemanticPending, isFalse);
      expect(
        controller.onlineSemanticCheckError,
        contains(AppL10n.strings.libraryDomain.semanticTargetUnknown),
      );
      expect(controller.shouldOfferSemanticDownload, isTrue);
      expect(
        provenUpToDateOnline(
          checkedAt: controller.onlineCheckedAt,
          error: controller.onlineProofError,
          hasUpdate: controller.hasOnlineUpdate,
        ),
        isFalse,
      );
    });

    test('כשל בשתי הבדיקות המקבילות נשמר בכל אחת בנפרד', () async {
      controller.dispose();
      final manager = _ConcurrentPeekManager(tempDir.path, fail: true);
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );

      await controller.checkOnline();

      expect(controller.onlineLatestVersion, isNull);
      expect(controller.onlineCheckError, contains('version down'));
      expect(controller.onlinePendingCompanions, isEmpty);
      expect(
        controller.onlineCompanionsCheckError,
        contains('companions down'),
      );
      expect(controller.onlineSemanticPending, isFalse);
      expect(controller.onlineCheckedAt, isNotNull);
    });
  });

  group('מצב הרשת אחרי הורדה', () {
    for (final remaining in [
      <CompanionAsset>{},
      {CompanionAsset.dictionary},
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
        // נלווה שנכשל אינו מוצע שוב בכל פתיחה — רק אחרי "נסה שוב" או בדיקה.
        expect(controller.failedCompanions, remaining);
        expect(controller.hasOnlineUpdate, isFalse);
        expect(controller.onlinePendingCompanionNames, isEmpty);
        expect(controller.hasDownloadFailures, remaining.isNotEmpty);

        controller.forgetDownloadFailures();
        expect(controller.hasOnlineUpdate, remaining.isNotEmpty);
      });
    }

    test('במצב אישי הבדיקה ברשת אינה מריצה את הייצוא — רק החסם', () async {
      controller.dispose();
      final manager = _DownloadManager(tempDir.path, const {})..bound = 77;
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      )..personalUpdateMode = true;

      await controller.checkOnline();
      controller.personalUpdateMode = false;
      controller.personalUpdateMode = true;
      await Future<void>.delayed(Duration.zero);

      expect(manager.probes, 0);
      expect(controller.onlineDownloadBytesBound, 77);
    });

    test('חישוב שמסתיים אחרי dispose אינו נוגע בקונטרולר', () async {
      final manager = _DownloadManager(tempDir.path, const {});
      final c = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );
      await c.checkOnline();
      c.personalUpdateMode = true;
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('מראה פגומה שתוקנה במצב אישי נאמרת בהערת ההורדה', () async {
      controller.dispose();
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: _DownloadManager(
          tempDir.path,
          const {},
          outcome: const MirrorDownloadOutcome(repairedDamagedMirror: true),
        ),
      )..personalUpdateMode = true;

      await controller.download();

      expect(
        controller.personalDownloadNote,
        LibraryPersonalDownloadNote.mirrorRepaired,
      );
    });

    test('חיפוש חכם שנכשל בהורדה אינו מוצע שוב, גם לא כשורה משנית', () async {
      controller.dispose();
      final manager = _DownloadManager(tempDir.path, const {})
        ..semanticPending = true;
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );
      controller.targetVersion = 30;
      await controller.checkOnline();
      expect(controller.onlineSemanticOffer, isTrue);

      await controller.download(includeSemanticSearch: true);

      expect(controller.semanticDownloadFailed, isTrue);
      expect(controller.onlineSemanticOffer, isFalse);
      expect(
        controller.failedDownloadNames,
        AppL10n.strings.libraryDomain.companionSemanticName,
      );
      controller.semanticPreference = SemanticDownloadPreference.always;
      expect(controller.hasOnlineUpdate, isFalse);

      // הורדה בלי החיפוש החכם אינה הוכחה שהוא כבר לא נכשל.
      await controller.download();
      expect(controller.semanticDownloadFailed, isTrue);

      controller.forgetDownloadFailures();
      expect(controller.hasOnlineUpdate, isTrue);
    });
  });

  group('העדפת החיפוש החכם', () {
    void semanticOnly() {
      controller
        ..onlineCheckedAt = DateTime.now()
        ..onlineLatestVersion = 30
        ..targetVersion = 30
        ..onlineSemanticPending = true
        ..semanticChecked = true;
    }

    test('"לשאול": לבדו אינו עדכון — רק onlineSemanticOffer', () {
      semanticOnly();
      expect(controller.semanticPreference, SemanticDownloadPreference.ask);
      expect(controller.hasOnlineUpdate, isFalse);
      expect(controller.onlinePendingCompanionNames, isEmpty);
      expect(controller.onlineSemanticOffer, isTrue);
      expect(controller.shouldOfferSemanticDownload, isTrue);

      controller.semanticChecked = false;
      expect(controller.onlineSemanticOffer, isFalse);
    });

    test('"תמיד": עדכון רגיל, עם השם ברשימה ובלי שורה משנית', () {
      semanticOnly();
      controller.semanticPreference = SemanticDownloadPreference.always;
      expect(controller.hasOnlineUpdate, isTrue);
      expect(
        controller.onlinePendingCompanionNames,
        AppL10n.strings.libraryDomain.companionSemanticName,
      );
      expect(controller.onlineSemanticOffer, isFalse);
    });

    test('"לא להוריד": לא עדכון ולא שורה משנית', () {
      semanticOnly();
      controller.semanticPreference = SemanticDownloadPreference.never;
      expect(controller.hasOnlineUpdate, isFalse);
      expect(controller.onlinePendingCompanionNames, isEmpty);
      expect(controller.onlineSemanticOffer, isFalse);
    });

    test('ה-setter מודיע רק על שינוי', () {
      var notified = 0;
      controller.addListener(() => notified++);
      controller.semanticPreference = SemanticDownloadPreference.ask;
      expect(notified, 0);
      controller.semanticPreference = SemanticDownloadPreference.never;
      expect(notified, 1);
    });

    test('"לא להוריד" — אין בדיקה ברשת לחיפוש החכם, והיא "לא נבדקה"', () async {
      controller.dispose();
      final manager = _DownloadManager(tempDir.path, const {})
        ..semanticPending = true;
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      )..semanticPreference = SemanticDownloadPreference.never;

      await controller.checkOnline();

      expect(manager.semanticPeeks, 0);
      expect(controller.semanticChecked, isFalse);
      expect(controller.onlineSemanticPending, isFalse);
      // דילוג אינו הוכחה: מעבר ל"תמיד" תוך רבע שעה עדיין מוריד.
      expect(controller.shouldOfferSemanticDownload, isTrue);

      final answers = controller.onlineAnswers;
      controller.semanticChecked = true;
      controller.restoreOnlineAnswers(answers);
      expect(controller.semanticChecked, isFalse);
      expect(controller.shouldOfferSemanticDownload, isTrue);

      controller.semanticPreference = SemanticDownloadPreference.ask;
      await controller.checkOnline();
      expect(manager.semanticPeeks, 1);
      expect(controller.semanticChecked, isTrue);
      expect(controller.onlineSemanticOffer, isTrue);
    });
  });

  group('"עד X" — החסם שבבית', () {
    _DownloadManager manager({bool semantic = false}) {
      controller.dispose();
      final manager = _DownloadManager(tempDir.path, const {})
        ..semanticPending = semantic
        ..bound = 900
        ..semanticBytes = 300;
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );
      return manager;
    }

    test('הספרייה בלבד; החיפוש החכם נוסף רק ב"תמיד"', () async {
      manager(semantic: true);
      await controller.checkOnline();
      expect(controller.onlineDownloadUpperBound, 900);

      controller.semanticPreference = SemanticDownloadPreference.always;
      expect(controller.onlineDownloadUpperBound, 1200);

      controller.semanticPreference = SemanticDownloadPreference.never;
      expect(controller.onlineDownloadUpperBound, 900);
    });

    test('"תמיד" בלי גודל ידוע לחיפוש החכם — אין חסם', () async {
      manager(semantic: true).semanticBytes = null;
      controller.semanticPreference = SemanticDownloadPreference.always;
      await controller.checkOnline();
      expect(controller.onlineDownloadUpperBound, isNull);
    });

    test('בדיקה שנכשלה — אין חסם, ולא שואלים עליו', () async {
      controller.dispose();
      final failing = _ConcurrentPeekManager(tempDir.path, fail: true);
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: failing,
      );
      await controller.checkOnline();
      expect(controller.onlineDownloadBytesBound, isNull);
      expect(controller.onlineDownloadUpperBound, isNull);
    });

    test('"תמיד" וכשל בבדיקת החיפוש החכם — ההורדה תביא אותו, ולכן אין חסם',
        () async {
      manager().semanticFails = true;
      controller.semanticPreference = SemanticDownloadPreference.always;
      await controller.checkOnline();
      expect(controller.shouldOfferSemanticDownload, isTrue);
      expect(controller.onlineDownloadUpperBound, isNull);

      controller.semanticPreference = SemanticDownloadPreference.ask;
      expect(controller.onlineDownloadUpperBound, 900);
    });

    test('כשל בחיפוש החכם מכשיל את בדיקת הספרייה בבית רק ב"תמיד"', () async {
      manager().semanticFails = true;
      await controller.checkOnline();
      expect(controller.onlineSemanticCheckError, isNotNull);
      expect(controller.onlineAnswerError, isNull);
      controller.semanticPreference = SemanticDownloadPreference.never;
      expect(controller.onlineAnswerError, isNull);
      controller.semanticPreference = SemanticDownloadPreference.always;
      expect(controller.onlineAnswerError, isNotNull);
    });

    test('בדיקה חוזרת שומרת את הכשל הקודם עד שהתשובה החדשה מגיעה', () async {
      controller.dispose();
      final gated = _GatedPeekManager(tempDir.path);
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: gated,
      );
      gated.next = Completer<int>()..completeError(StateError('offline'));
      await controller.checkOnline();
      expect(controller.onlineCheckError, isNotNull);
      final failedAt = controller.onlineCheckedAt;

      gated.next = Completer<int>();
      final retry = controller.checkOnline();
      await Future<void>.delayed(Duration.zero);
      expect(controller.onlineCheckError, isNotNull);
      expect(controller.onlineCheckedAt, failedAt);

      gated.next.complete(31);
      await retry;
      expect(controller.onlineCheckError, isNull);
      expect(controller.onlineLatestVersion, 31);
    });

    test('החסם חוזר עם תשובות הרשת אחרי ביטול', () async {
      final m = manager();
      await controller.checkOnline();
      expect(m.boundAsked, 1);
      final answers = controller.onlineAnswers;
      controller.onlineDownloadBytesBound = 5;
      controller.restoreOnlineAnswers(answers);
      expect(controller.onlineDownloadUpperBound, 900);
    });

    group('Otzaria installers on the drive', () {
      test('a verified compatible mirror stops offering the blocked newer DB',
          () async {
        controller.dispose();
        final manager = _DownloadManager(tempDir.path, const {})
          ..downloaded = true
          ..settled = true;
        controller =
            LibraryModuleController(dataDir: tempDir.path, manager: manager);
        controller.targetVersion = 29;
        await controller.checkOnline();
        expect(controller.hasOnlineLibraryUpdate, isFalse);
        expect(controller.newerLibraryNeedsOtzaria, 30);
        final answers = controller.onlineAnswers;
        manager.settled = false;
        await controller.checkOnline();
        expect(controller.hasOnlineLibraryUpdate, isTrue);
        controller.restoreOnlineAnswers(answers);
        expect(controller.hasOnlineLibraryUpdate, isFalse);
        controller.personalUpdateMode = true;
        expect(controller.hasOnlineLibraryUpdate, isTrue);
      });
      test('no installer: the library download never starts', () async {
        controller.dispose();
        final manager = _DownloadManager(tempDir.path, const {});
        controller = LibraryModuleController(
          dataDir: tempDir.path,
          manager: manager,
          mirroredReadableDbSchema: () async => null,
        );

        await controller.download();

        expect(manager.downloaded, isFalse);
        expect(controller.downloadNeedsOtzariaInstaller, isTrue);
        expect(controller.downloadNeedsRetry, isTrue);
        expect(controller.downloadError, isNotNull);
      });

      test('the schema is read at download time and passed on', () async {
        controller.dispose();
        final manager = _DownloadManager(
          tempDir.path,
          const {},
          outcome: const MirrorDownloadOutcome(newerNeedsOtzaria: 31),
        );
        var schema = 5;
        controller = LibraryModuleController(
          dataDir: tempDir.path,
          manager: manager,
          mirroredReadableDbSchema: () async => schema,
        );
        // An installer that lands after construction must count.
        schema = 6;

        await controller.download();

        expect(manager.passedReadableSchema, 6);
        expect(controller.downloadStatus, MirrorDownloadStatus.done);
        expect(controller.downloadNeedsOtzariaInstaller, isFalse);
        expect(controller.newerLibraryNeedsOtzaria, 31);
      });

      group('read from the app mirror after the app download', () {
        late String dataDir;
        late OtzariaManager otzaria;

        setUp(() {
          dataDir = p.join(tempDir.path, 'drive');
          otzaria = OtzariaManager(
            dataDir: dataDir,
            platform: OtzariaTargetPlatform.windows,
            environment: const {},
            machineArch: OtzariaArch.x64,
          );
          addTearDown(otzaria.dispose);
        });

        /// What the app download leaves; [installerLanded] false = it failed
        /// after the metadata named the installer.
        void appDownloaded(String tag, {required bool installerLanded}) {
          final mirror = p.join(dataDir, 'mirror', 'app');
          final relative = 'installers/$tag/otzaria-$tag-windows.exe';
          if (installerLanded) {
            File(p.join(mirror, relative))
              ..createSync(recursive: true)
              ..writeAsStringSync('installer');
          }
          File(p.join(mirror, 'latest-release.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              jsonEncode({
                'schemaVersion': 2,
                'stable': OtzariaRelease(
                  tagName: tag,
                  name: tag,
                  isPrerelease: false,
                  isDraft: false,
                  publishedAt: DateTime.utc(2026),
                  installerKind: OtzariaInstallerKind.windowsSetupExe,
                  installerAssetName: 'otzaria-$tag-windows.exe',
                  installerDownloadUrl: 'https://example/$tag',
                  installerSizeBytes: 'installer'.length,
                ).toJson()
                  ..['installerPath'] = relative,
              }),
            );
        }

        Future<_DownloadManager> downloadLibrary() async {
          controller.dispose();
          final manager = _DownloadManager(tempDir.path, const {});
          controller = LibraryModuleController(
            dataDir: tempDir.path,
            manager: manager,
            mirroredReadableDbSchema: otzaria.mirroredReadableDbSchema,
          );
          await controller.download();
          return manager;
        }

        test('the installer just downloaded opens the newer library', () async {
          appDownloaded('0.9.98+801', installerLanded: true);

          final manager = await downloadLibrary();

          expect(manager.passedReadableSchema, 6);
        });

        test('a failed installer download proves nothing', () async {
          appDownloaded('0.9.98+801', installerLanded: false);

          final manager = await downloadLibrary();

          expect(manager.downloaded, isFalse);
          expect(controller.downloadNeedsOtzariaInstaller, isTrue);
        });

        test('the Otzaria on this machine does not lift the limit', () async {
          appDownloaded('0.9.97+789', installerLanded: true);
          controller.dispose();
          final manager = _DownloadManager(tempDir.path, const {});
          controller = LibraryModuleController(
            dataDir: tempDir.path,
            manager: manager,
            otzariaAppVersion: () async => '0.9.98+801',
            mirroredReadableDbSchema: otzaria.mirroredReadableDbSchema,
          );

          await controller.download();

          expect(manager.passedReadableSchema, 5);
        });
      });

      test('each outcome has its own note', () async {
        Future<List<String>> notesFor(MirrorDownloadOutcome outcome) async {
          controller.dispose();
          controller = LibraryModuleController(
            dataDir: tempDir.path,
            manager: _DownloadManager(tempDir.path, const {}, outcome: outcome),
            mirroredReadableDbSchema: () async => 5,
          );
          await controller.download();
          return controller.downloadNotes;
        }

        final t = AppL10n.strings.libraryScreen;
        expect(await notesFor(const MirrorDownloadOutcome()), isEmpty);
        expect(
          await notesFor(const MirrorDownloadOutcome(newerNeedsOtzaria: 31)),
          [t.downloadNewerNeedsOtzaria('31')],
        );
        expect(
          await notesFor(
            const MirrorDownloadOutcome(
              keptNewerMirror: true,
              libraryLeftAsIs: true,
            ),
          ),
          [t.downloadKeptNewerMirror],
        );
        expect(
          await notesFor(
            const MirrorDownloadOutcome(
              libraryLeftAsIs: true,
              unreadableManifests: {'patch-v30-v31.db.zst.manifest.json'},
            ),
          ),
          [t.downloadMetadataUnreadable],
        );
        expect(controller.libraryMetadataUnreadable, isTrue);
      });

      test('a later download clears the previous verdict', () async {
        controller.dispose();
        int? schema;
        final manager = _DownloadManager(tempDir.path, const {});
        controller = LibraryModuleController(
          dataDir: tempDir.path,
          manager: manager,
          mirroredReadableDbSchema: () async => schema,
        );
        await controller.download();
        expect(controller.downloadNeedsOtzariaInstaller, isTrue);

        schema = 6;
        await controller.download();

        expect(manager.downloaded, isTrue);
        expect(controller.downloadNeedsOtzariaInstaller, isFalse);
        expect(controller.downloadError, isNull);
      });
    });
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
      final archive = File(
        p.join(controller.mirrorDir, 'assets', 'v31', 'seforim-schema6.db.zst'),
      );
      await archive.parent.create(recursive: true);
      await File(p.join(controller.mirrorDir, 'releases.json')).writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'releases': [
            {
              'tag': 'v31',
              'assets': [
                {
                  'name': 'seforim-schema6.db.zst',
                  'downloadUrl': 'assets/v31/seforim-schema6.db.zst',
                  'size': 4,
                },
              ],
            },
          ],
        }),
      );
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
      _writeMirror(
        tempDir,
        releases: [
          const _MirrorRelease(
            'v31-20261004170255',
            patches: [_MirrorPatch(29, 31, toSchema: _futureSchema)],
          ),
        ],
      );
      final index = File(p.join(controller.mirrorDir, 'releases.json'));
      final metadata = jsonDecode(await index.readAsString()) as Map;
      final assets = (metadata['releases'] as List).single['assets'] as List;
      assets.removeWhere(
        (asset) => !(asset['name'] as String).endsWith('.json'),
      );
      for (final asset in assets) {
        asset['size'] = await File(
          p.join(controller.mirrorDir, asset['downloadUrl'] as String),
        ).length();
      }
      await index.writeAsString(jsonEncode(metadata));
      final partial = File(
        p.join(
          controller.mirrorDir,
          'assets',
          'v31-20261004170255',
          'seforim-schema6.db.zst',
        ),
      );
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
      controller.semanticPreference = SemanticDownloadPreference.always;
      controller.onlineLatestVersion = 30;
      controller.targetVersion = 30;
      controller.onlineSemanticPending = true;

      expect(controller.hasOnlineUpdate, isTrue);
      expect(controller.onlineUpdateVersion, isNull);
      expect(
        controller.onlinePendingCompanionNames,
        AppL10n.strings.libraryDomain.companionSemanticName,
      );
    });

    // חיפוש חכם שכבר בכונן הוצע בכל הורדה, ו"כן" הוריד מחדש את כל הספרייה.
    test('שאלת החיפוש החכם רק כשהבדיקה לא הוכיחה שהוא בכונן', () {
      expect(
        controller.shouldOfferSemanticDownload,
        isTrue,
        reason: 'בדיקה שלא רצה אינה הוכחה',
      );

      controller.onlineCheckedAt = DateTime.now();
      expect(
        controller.shouldOfferSemanticDownload,
        isTrue,
        reason: 'בדיקה שלא הגיעה לחיפוש החכם אינה הוכחה',
      );
      controller.semanticChecked = true;
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

    test('סירוב לחיפוש החכם מאפשר לדלג על ספרייה שהוכחה כמעודכנת', () {
      controller.semanticPreference = SemanticDownloadPreference.always;
      controller.onlineCheckedAt = DateTime.now();
      controller.onlineLatestVersion = 30;
      controller.targetVersion = 30;
      controller.onlineSemanticPending = true;

      expect(controller.hasOnlineUpdate, isTrue);
      expect(controller.hasOnlineLibraryUpdate, isFalse);
      expect(
        provenUpToDateOnline(
          checkedAt: controller.onlineCheckedAt,
          error: controller.onlineLibraryProofError,
          hasUpdate: controller.hasOnlineLibraryUpdate,
        ),
        isTrue,
      );

      controller.onlineSemanticPending = false;
      controller.onlineSemanticCheckError = 'rate limit';
      expect(controller.onlineProofError, 'rate limit');
      expect(controller.onlineLibraryProofError, isNull);

      controller.onlineCompanionsCheckError = 'companions';
      expect(controller.onlineLibraryProofError, 'companions');

      controller.onlineCompanionsCheckError = null;
      controller.onlinePendingCompanions = {CompanionAsset.talmud};
      expect(controller.hasOnlineLibraryUpdate, isTrue);
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
    Future<void> writeNotice({
      String route = ExternalUpdateNotice.routeDelta,
    }) =>
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
    test('מסד מלא ישן מזה שמותקן וסכמה חוסמת: חסימה עם הסבר הסכמה', () async {
      _writeMirror(
        tempDir,
        releases: [
          const _MirrorRelease('v21', hasFullDb: true),
          const _MirrorRelease('v22', patches: [_MirrorPatch(21, 22)]),
          const _MirrorRelease(
            'v26',
            patches: [_MirrorPatch(22, 26, toSchema: _futureSchema)],
          ),
        ],
      );
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.error);
      expect(
        controller.errorMessage,
        AppL10n.strings.libraryDomain.planPatchSchemaTooNew(_futureSchema, 26),
      );
    });

    test('מסד מלא של הגרסה החדשה מורד, עם נימוק שמוצג למשתמש', () async {
      _writeMirror(
        tempDir,
        releases: [
          const _MirrorRelease('v21', hasFullDb: true),
          const _MirrorRelease(
            'v26',
            patches: [_MirrorPatch(22, 26, toSchema: _futureSchema)],
            hasFullDb: true,
          ),
        ],
      );
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.updateAvailable);
      expect(controller.targetVersion, 26);
      expect(
        controller.updateRouteNote,
        AppL10n.strings.libraryDomain
            .planNewSchemaNeedsFullDb(26, _futureSchema),
      );
    });

    // צורת המראה שעל הכונן בפועל: מסד מלא של v21, קובצי עדכון עד v23,
    // ומעליהם גרסה בסכמה שאיננו מכירים. מסד v22 חייב לטפס ל-23, לא להיחסם.
    test('מסד שיכול לטפס בקובצי עדכון עושה זאת, ומקבל הסבר', () async {
      _writeMirror(
        tempDir,
        releases: [
          const _MirrorRelease('v21', hasFullDb: true),
          const _MirrorRelease(
            'v23',
            patches: [_MirrorPatch(21, 23), _MirrorPatch(22, 23)],
          ),
          const _MirrorRelease(
            'v26',
            patches: [_MirrorPatch(22, 26, toSchema: _futureSchema)],
          ),
        ],
      );
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 22));

      expect(controller.status, LibraryModuleStatus.updateAvailable);
      expect(controller.targetVersion, 23);
      expect(
        controller.updateRouteNote,
        AppL10n.strings.libraryDomain
            .planPartialDeltaSchemaStop(23, 26, _futureSchema),
      );
    });

    test('כשכל הסכמות מוכרות אין נימוק מיוחד — מסלול דלתא רגיל', () async {
      _writeMirror(
        tempDir,
        releases: [
          const _MirrorRelease('v21', hasFullDb: true),
          const _MirrorRelease('v24', patches: [_MirrorPatch(23, 24)]),
        ],
      );
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
    void writePersonalMirror() => _writeMirror(
          tempDir,
          releases: [
            const _MirrorRelease('v31', patches: [_MirrorPatch(30, 31)]),
          ],
        );

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

    test('כיבוי המצב בודק מחדש ומסיר את ההסבר', () async {
      controller.personalUpdateMode = true;
      writePersonalMirror();
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));
      expect(controller.status, LibraryModuleStatus.personalTargetElsewhere);

      controller.personalUpdateMode = false;
      expect(controller.status, LibraryModuleStatus.checking);
      await controller.checkForUpdate();

      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.personalTargetIsThisMachine, isTrue);
    });

    test('שינוי המצב לפני בדיקה ראשונה אינו מריץ בדיקה', () {
      controller.personalUpdateMode = true;

      expect(controller.status, LibraryModuleStatus.idle);
    });

    test('כשהמצב כבוי כל מחשב הוא יעד, והחסימה נשארת שגיאה', () async {
      writePersonalMirror();
      await controller.setCustomDbPath(_dbWithVersion(tempDir, 'live', 23));

      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.personalTargetIsThisMachine, isTrue);
    });
  });

  test('"מה חדש" של העדכון המוצע, ואחרי ההחלה של מה שהותקן', () async {
    controller.dispose();
    final manager = _ChangesNotesManager(tempDir.path);
    controller = LibraryModuleController(
      dataDir: tempDir.path,
      manager: manager,
    );

    await controller.checkForUpdate();
    expect(controller.changesNotes.map((n) => n.releaseTag), ['v33', 'v32']);
    expect(controller.changesNotesApplied, isFalse);
    expect(controller.changesNotesVersion, 33);

    await controller.update();

    expect(controller.status, LibraryModuleStatus.upToDate);
    expect(manager.between, [(31, 33)]);
    expect(controller.changesNotes.map((n) => n.releaseTag), ['v33', 'v32']);
    expect(controller.changesNotesApplied, isTrue);
    expect(controller.changesNotesVersion, 33);
    expect(controller.changesNotesRange, 2);
    expect(controller.changesNotesPartial, isFalse);

    // החלה חוזרת שלא העלתה גרסה (נלווים בלבד) אינה מציגה שוב "מה חדש".
    await controller.update();

    expect(controller.changesNotesApplied, isFalse);
    expect(controller.changesNotes, isEmpty);
  });

  group('החלה שרצה', () {
    late _ApplyManager manager;

    setUp(() async {
      controller.dispose();
      manager = _ApplyManager(tempDir.path);
      controller = LibraryModuleController(
        dataDir: tempDir.path,
        manager: manager,
      );
      await controller.checkForUpdate();
      expect(controller.status, LibraryModuleStatus.updateAvailable);
    });

    test('בדיקה, החלה שנייה ושינוי מצב אישי אינם נוגעים בה', () async {
      final gate = manager.applyGate = Completer<void>();
      final apply = controller.update();
      expect(controller.isApplying, isTrue);
      expect(controller.status, LibraryModuleStatus.updating);

      await controller.checkForUpdate();
      controller.personalUpdateMode = true;
      await controller.update();
      await controller.updateWithFullDownload();

      expect(manager.checks, 1);
      expect(manager.applies, 1);
      expect(controller.status, LibraryModuleStatus.updating);

      gate.complete();
      await apply;

      expect(controller.isApplying, isFalse);
      expect(manager.checks, 2);
    });

    test('החלה שנלחצה בזמן בדיקה ממתינה לסופה', () async {
      final checkGate = manager.checkGate = Completer<void>();
      final check = controller.checkForUpdate();
      final apply = controller.update();
      await pumpEventQueue();
      expect(manager.applies, 0);

      checkGate.complete();
      await check;
      await apply;

      expect(manager.applies, 1);
    });

    // אחרי כתיבת ההסכמה: בדיקה שכבר רצה לא ראתה אותה.
    test('בדיקה "טרייה" אינה מצטרפת לבדיקה שכבר רצה', () async {
      final gate = manager.checkGate = Completer<void>();
      final older = controller.checkForUpdate();
      final joined = controller.checkForUpdate();
      final fresh = controller.checkForUpdate(fresh: true);

      // setUp בדק פעם אחת; המצטרפת אינה בדיקה, והטרייה כן.
      manager.checkGate = null;
      gate.complete();
      await Future.wait([older, joined, fresh]);
      expect(manager.checks, 3);
    });

    test('בדיקה "טרייה" בזמן החלה חוזרת מיד, וההחלה בודקת בסופה', () async {
      final gate = manager.applyGate = Completer<void>();
      final apply = controller.update();
      await controller.checkForUpdate(fresh: true);
      expect(manager.checks, 1);
      gate.complete();
      await apply;
      expect(manager.checks, 2);
    });

    test('החלה שהמתינה לבדיקה שנכשלה משחררת את המסך', () async {
      final checkGate = manager.checkGate = Completer<void>();
      manager.checkError = StateError('drive');
      final check = controller.checkForUpdate();
      final apply = controller.update();
      await pumpEventQueue();
      expect(controller.isApplying, isTrue);

      final seen = <bool>[];
      void listener() => seen.add(controller.isApplying);
      controller.addListener(listener);
      checkGate.complete();
      await check;
      await apply;
      controller.removeListener(listener);

      expect(manager.applies, 0);
      expect(controller.isApplying, isFalse);
      expect(controller.status, LibraryModuleStatus.error);
      expect(seen, isNotEmpty);
      expect(seen.last, isFalse);
    });

    test('בזמן החלה בקשת האינדקס הממתינה אינה נמחקת', () async {
      const pending = ExternalUpdateNoticeData(route: 'full');
      final gate = manager.applyGate = Completer<void>();
      final apply = controller.update();
      controller.pendingReindex = pending;

      await controller.markReindexRequestDelivered();
      expect(controller.pendingReindex, same(pending));

      gate.complete();
      await apply;
    });

    test('ניסיון המסד המלא מנקה את השגיאה הקודמת כשהוא מתחיל', () async {
      manager.applyError = StateError('delta');
      await controller.update();
      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.canRetryWithFullDownload, isTrue);

      manager.applyError = null;
      final gate = manager.applyGate = Completer<void>();
      final apply = controller.updateWithFullDownload();

      expect(controller.errorMessage, isNull);
      expect(controller.canRetryWithFullDownload, isFalse);
      gate.complete();
      await apply;
    });

    test('בדיקה שנכשלה מבטלת את הצעת המסד המלא ואת התוכנית הישנה', () async {
      manager.applyError = StateError('delta');
      await controller.update();
      expect(controller.canRetryWithFullDownload, isTrue);

      manager.checkError = StateError('drive');
      await controller.checkForUpdate();

      expect(controller.status, LibraryModuleStatus.error);
      expect(controller.canRetryWithFullDownload, isFalse);
      expect(controller.errorMessage, contains('drive'));
      expect(controller.fullDownloadFallbackSize, isNull);

      await controller.updateWithFullDownload();
      expect(manager.applies, 1);
    });
  });
}

LibraryUpdateCheckResult _deltaWithFallback() => LibraryUpdateCheckResult(
      dbPath: '/db/seforim.db',
      plan: LibraryUpdatePlan.delta(
        localVersion: 1,
        targetVersion: 2,
        steps: const [],
        fullDownloadFallback: LibraryUpdatePlan.fullDownload(
          localVersion: 1,
          targetVersion: 2,
          asset: const ReleaseAsset(
            name: 'seforim.db.zst',
            downloadUrl: 'seforim.db.zst',
            size: 10,
          ),
          releaseTag: 'v2',
        ),
      ),
    );

class _ApplyManager extends LibraryManager {
  _ApplyManager(String dataDir) : super(dataDir: dataDir);

  int checks = 0;
  int applies = 0;
  Completer<void>? checkGate;
  Completer<void>? applyGate;
  Object? checkError;
  Object? applyError;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    checks++;
    await checkGate?.future;
    if (checkError case final error?) throw error;
    return _deltaWithFallback();
  }

  @override
  Future<Set<int>> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
    void Function(String reason)? onLibraryLocationFailure,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    applies++;
    await applyGate?.future;
    if (applyError case final error?) throw error;
    return const {};
  }
}

class _DamagedMirrorManager extends LibraryManager {
  _DamagedMirrorManager(String dataDir) : super(dataDir: dataDir);

  Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    if (gate case final gate?) {
      entered.complete();
      await gate.future;
    }
    throw LibraryMirrorDamagedException(mirrorDir, 'releases.json');
  }
}

class _NeedsNewerOtzariaManager extends LibraryManager {
  _NeedsNewerOtzariaManager(String dataDir) : super(dataDir: dataDir);

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async =>
      LibraryUpdateCheckResult(
        dbPath: 'seforim.db',
        localVersion: const LocalDbVersion(
          dbVersion: 30,
          schemaVersion: 5,
          hasVersionMeta: true,
        ),
        latestVersion: 31,
        readableDbSchemaVersion: 5,
        needsNewerOtzaria: true,
        plan: LibraryUpdatePlan.blocked(
          localVersion: 30,
          targetVersion: 31,
          reason: AppL10n.strings.libraryDomain.planOtzariaTooOldForLibrary(
            5,
            31,
          ),
        ),
      );
}

class _DownloadManager extends LibraryManager {
  _DownloadManager(
    String dataDir,
    this.remaining, {
    this.outcome = const MirrorDownloadOutcome(),
  }) : super(dataDir: dataDir);

  final Set<CompanionAsset> remaining;
  final MirrorDownloadOutcome outcome;
  bool downloaded = false;
  bool settled = false;

  @override
  Future<bool> isReadableMirrorCurrent() async => settled;
  bool semanticPending = false;
  bool semanticFails = false;
  int semanticPeeks = 0;
  int? bound;
  int? semanticBytes;
  var boundAsked = 0;

  @override
  Future<int?> peekedDownloadBytesBound() async {
    boundAsked++;
    return bound;
  }

  var probes = 0;

  @override
  Future<int?> probeMirrorDownloadBytes({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    probes++;
    return 1;
  }

  @override
  int? get peekedSemanticBytes => semanticBytes;
  int? passedReadableSchema;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async =>
      const LibraryUpdateCheckResult(dbPath: null);

  @override
  Future<int> peekLatestOnlineVersion() async => 30;

  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async =>
      downloaded ? remaining : {CompanionAsset.dictionary};

  @override
  Future<bool> peekPendingSemanticSearch() async {
    semanticPeeks++;
    if (semanticFails) throw StateError('semantic down');
    return semanticPending;
  }

  @override
  Future<MirrorDownloadOutcome> downloadToMirror({
    bool includeSemanticSearch = false,
    int? readableDbSchema,
    void Function(String stage)? onStage,
    void Function(String? stage)? onCompanionStage,
    void Function(int doneAssets, int totalAssets)? onAssetProgress,
    void Function(int downloaded, int? total)? onBytesProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(String warning)? onWarning,
    bool Function()? isCancelled,
  }) async {
    downloaded = true;
    passedReadableSchema = readableDbSchema;
    return outcome;
  }
}

class _GatedPeekManager extends LibraryManager {
  _GatedPeekManager(String dataDir) : super(dataDir: dataDir);

  late Completer<int> next;

  @override
  Future<int> peekLatestOnlineVersion() => next.future;

  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async => const {};

  @override
  Future<bool> peekPendingSemanticSearch() async => false;
}

class _ConcurrentPeekManager extends LibraryManager {
  _ConcurrentPeekManager(String dataDir, {this.fail = false})
      : super(dataDir: dataDir);

  final bool fail;
  final _versionStarted = Completer<void>();
  final _companionsStarted = Completer<void>();

  @override
  Future<int> peekLatestOnlineVersion() async {
    _versionStarted.complete();
    await _companionsStarted.future.timeout(const Duration(seconds: 5));
    if (fail) throw StateError('version down');
    return 30;
  }

  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async {
    _companionsStarted.complete();
    await _versionStarted.future.timeout(const Duration(seconds: 5));
    if (fail) throw StateError('companions down');
    return {CompanionAsset.talmud};
  }

  @override
  Future<bool> peekPendingSemanticSearch() async => false;
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
void _writeMirror(Directory tempDir, {required List<_MirrorRelease> releases}) {
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
          if (patch.toSchema >= 4) 'patchFormatVersion': 4,
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
  File(p.join(root.path, 'releases.json')).writeAsStringSync(
    jsonEncode({
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'releases': json,
    }),
  );
}

/// סכמה שהחבילה עוד אינה מכירה, בכל גרסה שלה.
const _futureSchema = kSupportedDbSchemaVersion + 1;

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

String _hotJournalDb(Directory tempDir) {
  final live = p.join(tempDir.path, 'live.db');
  final writer = sqlite3.sqlite3.open(live);
  try {
    writer.execute('PRAGMA journal_mode = DELETE');
    writer.execute('CREATE TABLE filler (blob BLOB)');
    for (var i = 0; i < 50; i++) {
      writer.execute('INSERT INTO filler VALUES (zeroblob(4096))');
    }
    writer.execute('PRAGMA cache_size = 1');
    writer.execute('BEGIN');
    writer.execute('UPDATE filler SET blob = randomblob(4096)');
    final crashed = p.join(tempDir.path, 'crashed.db');
    File(live).copySync(crashed);
    File('$live-journal').copySync('$crashed-journal');
    return crashed;
  } finally {
    writer.execute('ROLLBACK');
    writer.close();
  }
}

void _setReadOnly(String path, bool readOnly) {
  final result = Platform.isWindows
      ? Process.runSync('attrib', [readOnly ? '+R' : '-R', path])
      : Process.runSync('chmod', [readOnly ? '444' : '644', path]);
  expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
}

class _ChangesNotesManager extends LibraryManager {
  _ChangesNotesManager(String dataDir) : super(dataDir: dataDir);

  int _version = 31;
  final between = <(int, int)>[];

  static const _notes = [
    LibraryChangesNote(releaseTag: 'v33', path: 'v33.md'),
    LibraryChangesNote(releaseTag: 'v32', path: 'v32.md'),
  ];

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async =>
      LibraryUpdateCheckResult(
        dbPath: '/db/seforim.db',
        localVersion: LocalDbVersion(
          dbVersion: _version,
          schemaVersion: 6,
          hasVersionMeta: true,
        ),
        latestVersion: 33,
        plan: _version < 33
            ? LibraryUpdatePlan.delta(
                localVersion: _version,
                targetVersion: 33,
                steps: const [],
              )
            : LibraryUpdatePlan.none(localVersion: 33),
      );

  @override
  Future<List<LibraryChangesNote>> pendingChangesNotes(
    LibraryUpdateCheckResult check,
  ) async =>
      check.dbUpdateAvailable ? _notes : const [];

  @override
  Future<List<LibraryChangesNote>> changesNotesBetween(
    int fromVersion,
    int toVersion,
  ) async {
    between.add((fromVersion, toVersion));
    return _notes;
  }

  @override
  Future<Set<int>> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
    void Function(String reason)? onLibraryLocationFailure,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    _version = 33;
    return const {};
  }
}

class _UnknownSemanticManager extends LibraryManager {
  _UnknownSemanticManager(String dataDir) : super(dataDir: dataDir);

  @override
  Future<int> peekLatestOnlineVersion() async => 30;

  @override
  Future<Set<CompanionAsset>> peekPendingCompanions() async => const {};

  @override
  Future<bool> peekPendingSemanticSearch() async =>
      throw StateError(AppL10n.strings.libraryDomain.semanticTargetUnknown);
}
