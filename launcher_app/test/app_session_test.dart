import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/app_report/launcher_crash_session.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/launcher_update_flow.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/search_feedback_controller.dart';
import 'package:launcher_app/src/screens/home/home_view_model.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/self_update/launcher_release_client.dart'
    show LauncherDownloadCancelled;
import 'package:launcher_app/src/self_update/launcher_self_updater.dart';
import 'package:launcher_app/src/self_update/launcher_update_mirror.dart'
    show MirroredLauncherRelease;
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/services/sleep_inhibitor.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/safer_mode.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/app_session.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/home_guidance_session.dart';
import 'package:launcher_app/src/shell/session_prompts.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:library_manager/library_manager.dart'
    show
        CompanionAsset,
        LibraryManager,
        LibraryStateStore,
        LibraryUpdateCheckResult,
        MirrorDownloadOutcome;
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart'
    show
        MirroredStoreApp,
        PluginCatalog,
        PluginInstallResult,
        PluginSyncOutcome,
        PluginSyncProgress,
        PluginsManager,
        PluginsOnlineStatus,
        StoreAppRelease,
        StorePlugin;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'storage_real_engine_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _TrackedSettings settings;
  late _FakePrompts prompts;
  final sessions = <AppSession>[];

  setUp(() async {
    HttpOverrides.global = NoNetworkHttpOverrides();
    tempDir = Directory.systemTemp.createTempSync('app_session_test');
    await AppLogger.init(tempDir.path);
    settings = _TrackedSettings(dataDir: tempDir.path);
    await settings.update(const AppSettings(autoCheckUpdates: false));
    prompts = _FakePrompts();
  });

  tearDown(() async {
    for (final s in sessions) {
      s.dispose();
    }
    sessions.clear();
    LauncherCrashSession.resetForTest();
    await settings.pending;
    settings.dispose();
    AppLogger.resetForTest();
    HttpOverrides.global = null;
    await deleteTempDir(tempDir);
  });

  AppSession session({
    bool readOnly = false,
    SleepInhibitor? sleep,
    NoticesSeenStore? notices,
    OtzariaLauncher launcher = const _FailingLauncher(),
    OtzariaManager? otzariaManager,
    LibraryManager? libraryManager,
    PluginsManager? pluginsManager,
    LauncherSelfUpdater? launcherUpdater,
    SearchFeedbackController? searchFeedback,
    Duration closeDeliveryPatience = const Duration(seconds: 10),
  }) {
    final s = AppSession(
      dataDir: tempDir.path,
      stateDir: tempDir.path,
      settings: settings,
      prompts: prompts,
      readOnly: readOnly,
      runningLocator: const _NeverRunningLocator(),
      noticesStore: notices ??
          MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
      sleepInhibitor: sleep,
      otzariaLauncher: launcher,
      otzariaManager: otzariaManager,
      libraryManager: libraryManager,
      pluginsManager: pluginsManager,
      launcherUpdater: launcherUpdater,
      searchFeedback: searchFeedback,
      closeDeliveryPatience: closeDeliveryPatience,
    );
    sessions.add(s);
    return s;
  }

  Future<void> waitFor(bool Function() done) async {
    WidgetsBinding.instance
      ..handleBeginFrame(null)
      ..handleDrawFrame();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('startup reads wait for the first frame', () async {
    await settings.update(const AppSettings(autoCheckUpdates: true));
    final s = _RecordingStartupSession(
      dataDir: tempDir.path,
      stateDir: tempDir.path,
      settings: settings,
      prompts: prompts,
      runningLocator: const _NeverRunningLocator(),
      noticesStore: MemoryNoticesStore(),
    );
    sessions.add(s);
    s.start();
    expect(s.checks, isEmpty);
    expect(s.plugins.status, PluginsModuleStatus.idle);
    expect(s.launcherUpdate.status, LauncherUpdateStatus.idle);

    WidgetsBinding.instance
      ..handleBeginFrame(null)
      ..handleDrawFrame();
    await waitFor(() => s.plugins.status == PluginsModuleStatus.ready);
    expect(s.checks, ['local', 'online']);
  });

  test('startup uses settings changed before the first frame', () async {
    final s = _RecordingStartupSession(
      dataDir: tempDir.path,
      stateDir: tempDir.path,
      settings: settings,
      prompts: prompts,
      runningLocator: const _NeverRunningLocator(),
      noticesStore: MemoryNoticesStore(),
    );
    sessions.add(s);
    s.start();
    await settings.update(const AppSettings(autoCheckUpdates: true));
    expect(s.checks, isEmpty);
    await waitFor(() => s.plugins.status == PluginsModuleStatus.ready);
    expect(s.checks, ['local', 'online']);
  });

  test('disposing before the first frame skips startup reads', () async {
    final s = _RecordingStartupSession(
      dataDir: tempDir.path,
      stateDir: tempDir.path,
      settings: settings,
      prompts: prompts,
      runningLocator: const _NeverRunningLocator(),
    );
    s.start();
    s.dispose();
    WidgetsBinding.instance
      ..handleBeginFrame(null)
      ..handleDrawFrame();
    await Future<void>.delayed(Duration.zero);
    expect(s.checks, isEmpty);
    expect(s.plugins.status, PluginsModuleStatus.idle);
    expect(LauncherCrashSession.closeGuard, isNull);
  });

  test('home offers new custom apps once, and installed updates until applied',
      () async {
    final s = session();
    final entry = CustomAppEntry(
      descriptor: const AppDescriptor(
        id: 'zayit',
        name: 'Zayit',
        sourceKind: AppSourceKind.manual,
        detect: AppDetectRules(exeName: 'zayit.exe'),
      ),
      installer: StoredInstaller(
        fileName: 'setup.exe',
        version: '0.6.10',
        sizeBytes: 1,
        addedAt: DateTime(2026),
      ),
    );
    s.customApps.apps = [CustomAppView(entry: entry)];
    expect(guidanceFactsFromSession(s).customAppsPending, isTrue);
    await s.customApps.markAnnounced(s.customApps.apps);
    expect(s.customApps.pendingApps, hasLength(1));
    expect(guidanceFactsFromSession(s).customAppsPending, isFalse);
    s.customApps.apps = [
      CustomAppView(
        entry: entry,
        installed: const CustomAppInstallState(
          version: '0.6.9',
          installDir: r'C:\App',
          launchPath: r'C:\App\zayit.exe',
        ),
      )
    ];
    expect(guidanceFactsFromSession(s).customAppsPending, isTrue);
  });

  test('session library download requires an installer actually on the drive',
      () async {
    final s = session();
    await s.library.download();
    expect(s.library.downloadNeedsOtzariaInstaller, isTrue);
    expect(s.library.downloadStatus, MirrorDownloadStatus.error);

    const relative = 'installers/0.9.98/otzaria.exe';
    final mirror = p.join(tempDir.path, 'mirror', 'app');
    final installer = File(p.join(mirror, relative));
    await installer.parent.create(recursive: true);
    await installer.writeAsString('installer');
    const release = OtzariaRelease(
      tagName: '0.9.98+801',
      name: 'Otzaria',
      isPrerelease: false,
      isDraft: false,
      publishedAt: null,
      installerKind: OtzariaInstallerKind.windowsSetupExe,
      installerAssetName: 'otzaria.exe',
      installerDownloadUrl: 'https://example.test/installer',
      installerSizeBytes: 9,
    );
    await File(p.join(mirror, 'latest-release.json')).writeAsString(jsonEncode({
      'schemaVersion': 2,
      'stable': release.toJson()..['installerPath'] = relative,
    }));
    if (Platform.isWindows) {
      await s.library.download();
      expect(s.library.downloadNeedsOtzariaInstaller, isFalse);
      expect(s.library.downloadError, isNotNull,
          reason: 'Network is forbidden in this test');
    }
  });

  group('השאלה "מחשבים מרובים או רק המחשב שלי"', () {
    // בלי פריים השאלה אינה יוצאת — היא מחכה לפריים הראשון, כמו באפליקציה.
    void frame() => WidgetsBinding.instance
      ..handleBeginFrame(null)
      ..handleDrawFrame();

    Future<void> settled(AppSession s) async {
      frame();
      await waitFor(
        () =>
            prompts.personalAsks > 0 &&
            s.plugins.status != PluginsModuleStatus.loading,
      );
    }

    test('נשאלת בהפעלה הראשונה; סגירה בלי תשובה — שוב בהפעלה הבאה', () async {
      final first = session()..start();
      await settled(first);
      expect(prompts.personalAsks, 1);
      expect(settings.settings.personalModeAsked, isFalse);

      final second = session()..start();
      frame();
      await waitFor(() => prompts.personalAsks > 1);
      expect(prompts.personalAsks, 2);
      await waitFor(() => second.plugins.status != PluginsModuleStatus.loading);
    });

    for (final mine in [true, false]) {
      test('תשובה (רק שלי: $mine) נשמרת, ולא נשאלת שוב', () async {
        prompts.personalAnswer = mine;
        final s = session()..start();
        await settled(s);
        await waitFor(() => settings.settings.personalModeAsked);
        await settings.pending;
        expect(settings.settings.personalUpdateMode, mine);
        expect(settings.settings.personalModeAsked, isTrue);
        // בלי אוצריא במחשב הזה — אין רישום עכשיו.
        expect(s.preparedForThisMachine, isFalse);

        final again = session()..start();
        frame();
        await waitFor(
            () => again.plugins.status != PluginsModuleStatus.loading);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(prompts.personalAsks, 1);
      });
    }

    test('בכונן מוגן מפני כתיבה אינה נשאלת', () async {
      final s = session(readOnly: true)..start();
      frame();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(prompts.personalAsks, 0);
      expect(s.shouldAskPersonalScope, isFalse);
    });

    test('כשההגדרות נעולות בסיסמה אינה נשאלת', () async {
      await settings.update(
        AppSettings(
          autoCheckUpdates: false,
          saferModeEnabled: true,
          saferModePassword: SaferModePassword.encode('1234'),
        ),
      );
      final s = session()..start();
      frame();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(prompts.personalAsks, 0);
    });

    test('כונן שעדכון אישי כבר פעיל בו אינו נשאל', () async {
      await settings.update(
        AppSettings.fromJson({
          'sync': {'personalMode': true},
          'automation': {'checkUpdates': false},
        }),
      );
      final s = session()..start();
      frame();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(prompts.personalAsks, 0);
    });
  });

  group('רישום אוטומטי במחשב הראשון שבו אוצריא מותקנת', () {
    Future<AppSession> withLibrary({required int version}) async {
      final db = File(p.join(tempDir.path, 'books', 'seforim.db'))
        ..parent.createSync(recursive: true);
      final sql = sqlite3.sqlite3.open(db.path);
      sql.execute(
          'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      sql.execute("INSERT INTO schema_meta VALUES ('db_version', '$version')");
      sql.close();
      final s = session();
      await s.library.setCustomDbPath(db.path);
      s.otzaria.currentVersion = '0.10.4';
      // הבדיקה ברשת רצה ונכשלה — המחשב הלא מחובר.
      s.library
        ..onlineCheckedAt = DateTime.now()
        ..onlineCheckError = 'offline';
      return s;
    }

    LibraryStateStore store(AppSession s) =>
        LibraryStateStore.inDir(s.stateFilesDir);

    const pending = AppSettings(
      autoCheckUpdates: false,
      personalUpdateMode: true,
      personalModeAsked: true,
      personalAutoRegisterPending: true,
    );

    test('ממתין לרישום — המחשב הלא מחובר הראשון עם אוצריא נרשם, פעם אחת',
        () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      await s.registerPendingMachine();
      await settings.pending;
      expect(await store(s).lowestKnownDbVersion(), 140);
      expect(await store(s).hasOwnKnownDbVersion(), isTrue);
      expect(s.preparedForThisMachine, isTrue);
      expect(homeViewModelOf(s).personalPreparedHere, isTrue);
      expect(settings.settings.personalAutoRegisterPending, isFalse);
    });

    test('בלי הדגל — בדיקה ועלייה אינן רושמות (גם אחרי שהרשומות פגו)',
        () async {
      await settings.update(
        const AppSettings(autoCheckUpdates: false, personalUpdateMode: true),
      );
      final s = await withLibrary(version: 140);
      await s.registerPendingMachine();
      await s.library.checkForUpdate();
      expect(await store(s).lowestKnownDbVersion(), isNull);
      expect(s.preparedForThisMachine, isFalse);
    });

    test('מחשב מחובר אינו נרשם מעצמו, והדגל נשאר', () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      s.library.onlineCheckError = null;
      await s.registerPendingMachine();
      expect(await store(s).lowestKnownDbVersion(), isNull);
      expect(settings.settings.personalAutoRegisterPending, isTrue);
      expect(homeViewModelOf(s).personalPending, isTrue);
    });

    test('בלי בדיקה ברשת (למשל בדיקה בעלייה כבויה) — לא נרשם, הדגל נשאר',
        () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      s.library.onlineCheckedAt = null;
      await s.registerPendingMachine();
      await s.choosePersonalScope(personal: true);
      expect(await store(s).lowestKnownDbVersion(), isNull);
      expect(settings.settings.personalAutoRegisterPending, isTrue);
    });

    test('בלי בדיקה ברשת — הבית מציע "רישום המחשב הזה" ולא מבטיח רישום',
        () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      s.library.onlineCheckedAt = null;
      expect(homeViewModelOf(s).personalPendingNeedsClick, isTrue);

      // הלחיצה רושמת, והדגל נמחק כדי שמחשב אחר לא יירשם מעצמו.
      expect(await s.library.capturePersonalVersion(), isTrue);
      await s.afterManualRegistration();
      await settings.pending;
      expect(settings.settings.personalAutoRegisterPending, isFalse);
      expect(homeViewModelOf(s).personalPendingNeedsClick, isFalse);
    });

    test('מחשב מחובר — ההערה מבטיחה את המחשב האחר, בלי כפתור', () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      s.library.onlineCheckError = null;
      expect(homeViewModelOf(s).personalPending, isTrue);
      expect(homeViewModelOf(s).personalPendingNeedsClick, isFalse);
    });

    test('"בדוק עכשיו" שנכשל ברשת — הרישום הממתין רץ ורושם', () async {
      await settings.update(pending);
      final db = File(p.join(tempDir.path, 'books', 'seforim.db'))
        ..parent.createSync(recursive: true);
      final sql = sqlite3.sqlite3.open(db.path);
      sql.execute(
          'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      sql.execute("INSERT INTO schema_meta VALUES ('db_version', '142')");
      sql.close();
      final s = _OfflineCheckSession(
        dataDir: tempDir.path,
        stateDir: tempDir.path,
        settings: settings,
        prompts: prompts,
        runningLocator: const _NeverRunningLocator(),
        noticesStore:
            MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
      );
      sessions.add(s);
      await s.library.setCustomDbPath(db.path);
      s.otzaria.currentVersion = '0.10.4';
      expect(homeViewModelOf(s).personalPendingNeedsClick, isTrue);

      await s.checkNow();
      await settings.pending;

      expect(await store(s).lowestKnownDbVersion(), 142);
      expect(settings.settings.personalAutoRegisterPending, isFalse);
      expect(s.preparedForThisMachine, isTrue);
    });

    test('מחשב אחר כבר נרשם — אין רישום, והדגל נמחק', () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      await store(s).recordKnownDbVersion('OTHER|me', 145);
      await s.registerPendingMachine();
      await settings.pending;
      expect(await store(s).hasOwnKnownDbVersion(), isFalse);
      expect(settings.settings.personalAutoRegisterPending, isFalse);
    });

    test('הסרת המחשב האחרון אינה רושמת אותו מחדש', () async {
      await settings.update(pending);
      final s = await withLibrary(version: 140);
      s.library.personalUpdateMode = true;
      await s.registerPendingMachine();
      final key = await LibraryStateStore.currentMachineKey();
      await s.forgetRegisteredMachine(key);
      await settings.pending;
      expect(await store(s).lowestKnownDbVersion(), isNull);

      await s.registerPendingMachine();
      expect(await store(s).lowestKnownDbVersion(), isNull);
      expect(settings.settings.personalAutoRegisterPending, isFalse);
    });

    test('"רק המחשב שלי" במחשב לא מחובר עם אוצריא — נרשם מיד', () async {
      final s = await withLibrary(version: 141);
      await s.choosePersonalScope(personal: true);
      expect(settings.settings.personalUpdateMode, isTrue);
      expect(settings.settings.personalAutoRegisterPending, isFalse);
      expect(await store(s).lowestKnownDbVersion(), 141);
      expect(s.preparedForThisMachine, isTrue);
    });

    test('"רק המחשב שלי" במחשב מחובר — לא נרשם, וממתין למחשב אחר', () async {
      final s = await withLibrary(version: 141);
      s.library.onlineCheckError = null;
      await s.choosePersonalScope(personal: true);
      expect(await store(s).lowestKnownDbVersion(), isNull);
      expect(settings.settings.personalAutoRegisterPending, isTrue);
      expect(s.preparedForThisMachine, isFalse);
    });

    test('"רק המחשב שלי" בשאלה, כשבכונן ספרייה מלאה — קודם האזהרה', () async {
      final s = session();
      final full = File(
        p.join(s.library.mirrorDir, 'assets', 'v8-1', 'seforim.db.zst'),
      )
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(64, 1));
      File(p.join(s.library.mirrorDir, 'releases.json')).writeAsStringSync(
        jsonEncode({
          'releases': [
            {
              'tag': 'v8-1',
              'assets': [
                {
                  'name': 'seforim.db.zst',
                  'downloadUrl': 'assets/v8-1/seforim.db.zst',
                  'size': full.lengthSync(),
                },
              ],
            },
          ],
        }),
      );
      prompts.personalModeConfirm = false;
      await s.choosePersonalScope(personal: true, fromQuestion: true);
      expect(prompts.personalModeConfirms, 1);
      expect(settings.settings.personalModeAsked, isFalse);

      prompts.personalModeConfirm = true;
      await s.choosePersonalScope(personal: true, fromQuestion: true);
      expect(settings.settings.personalUpdateMode, isTrue);

      // בהגדרות האזהרה כבר נשאלה — אין שנייה.
      await s.choosePersonalScope(personal: true);
      expect(prompts.personalModeConfirms, 2);
    });

    test('הסרת מחשב מזיזה את גרסת ההתחלה', () async {
      await settings.update(
        const AppSettings(autoCheckUpdates: false, personalUpdateMode: true),
      );
      final s = session();
      s.library.personalUpdateMode = true;
      await store(s).recordKnownDbVersion('A|me', 140, name: 'A');
      await store(s).recordKnownDbVersion('B|me', 145, name: 'B');
      await s.library.refreshRegisteredMachines();
      expect(s.library.registeredMachines.map((m) => m.key), ['A|me', 'B|me']);

      await s.forgetRegisteredMachine('A|me');
      expect(await store(s).lowestKnownDbVersion(), 145);
      expect(s.library.registeredMachines.map((m) => m.key), ['B|me']);
    });
  });

  group('הודעות הבית במקום דיאלוגים בעלייה', () {
    test('ההסבר על הדיווחים: הודעה עד "הבנתי", ורק אז נרשם', () async {
      final notices = MemoryNoticesStore();
      final s = session(notices: notices)..start();
      await waitFor(() => s.showsReportsIntro);
      expect(s.showsReportsIntro, isTrue);
      expect(notices.marked, isEmpty);

      await s.dismissReportsIntro();
      expect(s.showsReportsIntro, isFalse);
      expect(notices.marked, [NoticesSeenStore.errorReportsIntro]);
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
    });

    test('ההסבר שכבר הוצג במחשב הזה אינו חוזר', () async {
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      expect(s.showsReportsIntro, isFalse);
    });

    test('כונן לקריאה בלבד אינו סופר דיווחים לאיסוף', () async {
      final s = session(readOnly: true);
      await s.recountReportsToCollect();
      expect(s.reportsToCollect, 0);
    });

    test('בלי בעיית הרשאות אין פס "הפעלה מחדש כמנהל"', () {
      expect(session().offersElevation, isFalse);
    });

    // נגזר מהמצב הנוכחי — לא מדגל שנלכד בכשל.
    test('canRestartElevated עוקב אחרי הקונטרולרים, ו"לא עכשיו" רק בבית', () {
      final s = session();
      expect(s.canRestartElevated, isFalse);
      s.library.needsElevation = true;
      expect(s.canRestartElevated, Platform.isWindows);
      s.dismissElevation();
      expect(s.offersElevation, isFalse);
      expect(s.canRestartElevated, Platform.isWindows);
      s.library.status = LibraryModuleStatus.updating;
      expect(s.canRestartElevated, isFalse);
      s.library.status = LibraryModuleStatus.upToDate;
      s.library.needsElevation = false;
      expect(s.canRestartElevated, isFalse);
    });

    test('בלי קטלוג אין תוספים חדשים לפס, והביקור אינו נכשל', () async {
      final s = session();
      expect(s.newPluginsForHome, isEmpty);
      await s.markPluginsVisited();
    });
  });

  group('checkOnline', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    test('בודק את ארבעת המודולים, ומדליק את הדגל רק בזמן הבדיקה', () async {
      final s = session();
      final flags = <bool>[];
      s.addListener(() => flags.add(s.isCheckingOnline));

      await s.checkOnline();

      expect(s.otzaria.onlineCheckedAt, isNotNull);
      expect(s.library.onlineCheckedAt, isNotNull);
      expect(s.plugins.onlineCheckedAt, isNotNull);
      expect(s.launcherUpdate.onlineCheckedAt, isNotNull);
      expect(flags.first, isTrue);
      expect(s.isCheckingOnline, isFalse);
      expect(s.lastCheckedAt, isNotNull);
      // בלי רשת אין גרסה חדשה של הכלי, ולכן גם אין שאלה על התקנה.
      expect(prompts.calls, isNot(contains('confirmLauncherInstall')));
      // המקום הפנוי בכונן נמדד ב-isolate אחרי הבדיקה, לרשימת ההורדה.
      for (var i = 0; i < 250 && s.driveFreeBytes == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(s.driveFreeBytes, greaterThan(0));
    });

    // בדיקה חוזרת במחשב לא מחובר: עד שהתשובה החדשה מגיעה, הכשל הקודם הוא
    // התשובה — לא "מחובר" ולא "הכול מעודכן" לכמה שניות.
    test('בדיקה חוזרת אחרי כשל: הבית לא נראה מחובר או מעודכן באמצע', () async {
      final s = session();
      await s.checkOnline();
      expect(homeViewModelOf(s).online, isFalse);

      final seen = <HomeViewModel>[];
      s.addListener(() => seen.add(homeViewModelOf(s)));
      await s.checkOnline();

      expect(seen, isNotEmpty);
      for (final model in seen) {
        expect(model.online, isNot(isTrue));
        expect(model.guidance.onlineProven, isFalse);
        expect(model.guidance.primary, isNot(GuidancePrimary.checkFailed));
      }
      expect(s.library.onlineCheckError, isNotNull);
      expect(s.otzaria.onlineCheckError, isNotNull);
    });

    test('כונן לקריאה בלבד: אינו בודק כלום ואינו מודיע', () async {
      final s = session(readOnly: true);
      var notified = 0;
      s.addListener(() => notified++);

      await s.checkOnline();

      expect(s.otzaria.onlineCheckedAt, isNull);
      expect(s.library.onlineCheckedAt, isNull);
      expect(s.plugins.onlineCheckedAt, isNull);
      expect(s.launcherUpdate.onlineCheckedAt, isNull);
      expect(notified, 0);
    });
  });

  group('checkNow', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    // checkAll מחכה לפריים (ההצעות שאחרי הבדיקה), ולכן רץ עם פריימים. כל
    // התרחישים בבדיקה אחת: בדיקת הספרייה זוכרת מצב סטטי בין אזורי זמן מדומה.
    testWidgets('מקומית ואז ברשת; כונן מוגן — מקומית; בלי כפילות; העלייה נחשבת',
        (tester) async {
      Future<void> drive(bool Function() done) async {
        for (var i = 0; i < 300 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> finish(Future<void> run) async {
        var done = false;
        unawaited(run.whenComplete(() => done = true));
        await drive(() => done);
        expect(done, isTrue);
      }

      // מקומית ואז ברשת, מחוון רק בזמן הבדיקה, ולחיצה שנייה אינה מוסיפה.
      final s = session();
      var starts = 0;
      DateTime? localFirst;
      var was = false;
      s.addListener(() {
        if (s.isCheckingOnline && !was) {
          starts++;
          localFirst ??= s.lastCheckedAt;
        }
        was = s.isCheckingOnline;
      });
      final run = s.checkNow();
      expect(s.isCheckingNow, isTrue);
      await finish(s.checkNow());
      await finish(run);
      expect(starts, 1);
      expect(localFirst, isNotNull);
      expect(s.otzaria.onlineCheckedAt, isNotNull);
      expect(s.isCheckingNow, isFalse);

      // כונן מוגן: "בדוק שוב" בודק מקומית בלבד — לא כלום, ולא ברשת.
      final locked = session(readOnly: true);
      var lockedOnline = false;
      locked.addListener(() => lockedOnline |= locked.isCheckingOnline);
      final lockedRun = locked.checkNow();
      expect(locked.isCheckingNow, isTrue);
      await finish(lockedRun);
      expect(locked.lastCheckedAt, isNotNull);
      expect(lockedOnline, isFalse);
      expect(locked.otzaria.onlineCheckedAt, isNull);

      // הבדיקה המקומית שבעלייה נחשבת בדיקה רצה.
      await tester.runAsync(
        () => settings.update(const AppSettings(autoCheckUpdates: true)),
      );
      final started = session();
      var startupWasChecking = false;
      started.addListener(() => startupWasChecking |= started.isCheckingNow);
      started.start();
      tester.binding.scheduleFrame();
      await drive(() => started.lastCheckedAt != null);
      expect(startupWasChecking, isTrue);
      await drive(() => !started.isCheckingNow);
      expect(started.isCheckingNow, isFalse);
      expect(started.lastCheckedAt, isNotNull);
      await drive(() => started.plugins.status != PluginsModuleStatus.loading);
      started.dispose();
      sessions.remove(started);
    });

    test('משימה ארוכה (ייצוא) חוסמת: אין בדיקה, והבית רואה את אותו תנאי',
        () async {
      final s = session();
      s.plugins.isExporting = true;
      expect(s.checkNowBlocked, isTrue);
      expect(homeViewModelOf(s).checkBlocked, isTrue);

      await s.checkNow();

      expect(s.lastCheckedAt, isNull);
      expect(s.isCheckingNow, isFalse);
      s.plugins.isExporting = false;
      expect(homeViewModelOf(s).checkBlocked, isFalse);
    });

    test('הבית מקבל את הערוץ כשממתינים לגרסה חדשה יותר בערוץ שנבחר', () {
      final s = session();
      s.otzaria
        ..status = OtzariaModuleStatus.installedIsNewer
        ..awaitsNewerInSelectedChannel = true;
      expect(
        homeViewModelOf(s).appAwaitsNewerStable,
        !s.otzaria.preferPrerelease,
      );

      s.otzaria.awaitsNewerInSelectedChannel = false;
      expect(homeViewModelOf(s).appAwaitsNewerStable, isNull);
    });

    test('שגיאת התוכנה והאשף שלא ידוע אם הסתיים — בבית', () {
      final s = session();
      s.otzaria
        ..status = OtzariaModuleStatus.error
        ..errorMessage = 'broken';
      expect(homeViewModelOf(s).appError, 'broken');

      s.otzaria
        ..status = OtzariaModuleStatus.updateAvailable
        ..lastInstallResult = OtzariaInstallResult.wizardStillOpen
        ..lastInstallNotice = 'still open';
      final m = homeViewModelOf(s);
      expect(m.appError, isNull);
      expect(m.appSetupNotice, 'still open');

      // ההתקנה זוהתה — אין עוד מה לומר על האשף.
      s.otzaria.status = OtzariaModuleStatus.upToDate;
      expect(homeViewModelOf(s).appSetupNotice, isNull);
    });

    test('האשף שבוטל או עוד פתוח — הנוסח של ההתקנה, לא סירוב מאוחר יותר', () {
      final s = session();
      for (final result in [
        OtzariaInstallResult.cancelled,
        OtzariaInstallResult.wizardStillOpen,
      ]) {
        s.otzaria
          ..status = OtzariaModuleStatus.updateAvailable
          ..lastInstallResult = result
          ..lastInstallNotice = 'wizard'
          // סירוב להפעיל בזמן עדכון ספרייה כותב לשם — ואינו נוגע בהערה.
          ..noticeMessage = 'library apply active';
        expect(homeViewModelOf(s).appSetupNotice, 'wizard', reason: '$result');
      }
    });

    test('התקנה שלא נמצאה — הבית מציע את "אוצריא — מתקדם"', () {
      final s = session();
      s.otzaria
        ..status = OtzariaModuleStatus.error
        ..errorMessage = 'not found'
        ..installNotDetected = true;
      expect(homeViewModelOf(s).appErrorPicksFolder, isTrue);
      s.otzaria.installNotDetected = false;
      expect(homeViewModelOf(s).appErrorPicksFolder, isFalse);
    });

    test('פתיחת אוצריא שנכשלה — הודעת שגיאה, לא שקט', () async {
      final messages = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('UiSnack') ?? false) messages.add(message!);
      };
      addTearDown(() => debugPrint = previousPrint);
      final s = session();

      await s.launchOtzaria();

      expect(s.otzaria.errorMessage, isNotNull);
      expect(messages, hasLength(1));
      expect(
        messages.single,
        contains(s.otzaria.errorMessage!.split('\n').first),
      );
      // הנוסח מתורגם ב-`otzaria_manager`; הקידומת של `StateError` אינה למשתמש.
      expect(messages.single, isNot(contains('Bad state')));
      expect(s.otzaria.errorMessage, isNot(contains('Bad state')));
    });

    test('הפעלה שנכשלה אינה דורסת את שגיאת ההתקנה שבגיבור', () async {
      final messages = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('UiSnack') ?? false) messages.add(message!);
      };
      addTearDown(() => debugPrint = previousPrint);
      final s = session();
      s.otzaria
        ..status = OtzariaModuleStatus.error
        ..errorMessage = 'install failed'
        ..installNotDetected = true;

      await s.launchOtzaria();

      expect(s.otzaria.errorMessage, 'install failed');
      expect(homeViewModelOf(s).appErrorPicksFolder, isTrue);
      expect(messages, hasLength(1));
      expect(messages.single, isNot(contains('install failed')));
    });

    test('הודעות הספרייה שדורשות פעולה מגיעות לבית', () async {
      final s = session();
      s.otzaria.currentVersion = '0.9.90';
      await s.loadSemanticConsentAnswer();
      final l = s.library
        ..status = LibraryModuleStatus.updateAvailable
        ..unavailableCompanions = {CompanionAsset.talmud}
        ..semanticPending = true;
      var m = homeViewModelOf(s);
      expect(m.libraryMissingNames, l.unavailableCompanionNames);
      expect(m.semanticConsent, isTrue);
      expect(m.libraryNotFound, isFalse);
      expect(m.libraryElsewhereFrom, isNull);

      l
        ..unavailableCompanions = const {}
        ..semanticConsentGranted = true
        ..status = LibraryModuleStatus.needsManualPath;
      m = homeViewModelOf(s);
      expect(m.libraryMissingNames, isNull);
      expect(m.semanticConsent, isFalse);
      expect(m.libraryNotFound, isTrue);

      l
        ..status = LibraryModuleStatus.personalTargetElsewhere
        ..personalFromVersion = 145;
      expect(homeViewModelOf(s).libraryElsewhereFrom, '145');
      l.personalFromVersion = null;
      expect(homeViewModelOf(s).libraryElsewhereFrom, '');
    });
  });

  group('בדיקת המראה בעלייה', () {
    test('רצה גם כשבדיקת העדכונים האוטומטית כבויה', () async {
      final s = session()..start();
      await waitFor(() => s.launcherUpdate.status != LauncherUpdateStatus.idle);
      expect(s.launcherUpdate.status, isNot(LauncherUpdateStatus.idle));
      expect(LauncherCrashSession.closeGuard, s.confirmClose);
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
    });

    test('כונן לקריאה בלבד: אינה רצה', () async {
      final s = session(readOnly: true)..start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(s.launcherUpdate.status, LauncherUpdateStatus.idle);
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
    });

    test('הפירוק מסיר את שומר הסגירה', () async {
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      sessions.remove(s);
      s.dispose();
      expect(LauncherCrashSession.closeGuard, isNull);
    });
  });

  group('דגלי משימה ארוכה', () {
    test(
        'עדכון ספרייה והתקנת אוצריא חוסמים יציאה ומסירת תוספים — '
        'לא את סנכרון המראה ולא שליחת דיווחים', () {
      final s = session();
      expect(s.longTaskRunning, isFalse);
      expect(s.exitWouldInterrupt, isFalse);
      expect(s.pluginActionsBlockedElsewhere, isFalse);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
      expect(s.exitPending, isFalse);

      s.library.status = LibraryModuleStatus.updating;
      expect(s.longTaskRunning, isTrue);
      expect(s.exitWouldInterrupt, isTrue);
      expect(s.pluginActionsBlockedElsewhere, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
      expect(s.reportsCollectBlocked, isTrue);
      expect(s.reportsUploadBlocked, isFalse);

      s.library.status = LibraryModuleStatus.upToDate;
      s.otzaria.status = OtzariaModuleStatus.installing;
      expect(s.longTaskRunning, isTrue);
      expect(s.pluginActionsBlockedElsewhere, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
      expect(s.libraryApplyBlocked, isTrue);

      s.otzaria.status = OtzariaModuleStatus.upToDate;
      expect(s.longTaskRunning, isFalse);
    });

    // סגירה באמצע הייתה עוצרת את המסירות בלי אזהרה.
    test('"עדכון הכול" בחנות התוספים הוא משימה ארוכה', () {
      final s = session();
      s.plugins.updateAllRun = (done: 0, total: 2);
      expect(s.longTaskRunning, isTrue);
      expect(s.exitWouldInterrupt, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
      s.plugins.updateAllRun = null;
      expect(s.longTaskRunning, isFalse);
    });

    test('החלפת קובץ ההרצה היא exitPending וחלק ממשימה ארוכה', () {
      final s = session();
      s.launcherUpdate.status = LauncherUpdateStatus.installing;
      expect(s.exitPending, isTrue);
      expect(s.longTaskRunning, isTrue);
      expect(s.pluginSyncBlockedElsewhere, isFalse);
    });

    test('Ctrl+R/F5 לא רצים כשמסך משימה רץ, גם בלי משימה ארוכה', () async {
      final s = session();
      s.tasks.prepareDownload();
      expect(s.longTaskRunning, isFalse);
      // חוזר מיד, בלי לבדוק דבר — אחרת `_markChecked` היה רושם בדיקה.
      await s.refreshFromKeyboard();
      expect(s.lastCheckedAt, isNull);
      expect(s.otzaria.status, isNot(OtzariaModuleStatus.checking));
    });

    test('"הורדה" בלי בחירה בהגדרות — הודעה, בלי "מתכונן"', () async {
      final s = session();
      await settings.update(settings.settings.copyWith(
        syncApp: false,
        syncPlugins: false,
        syncLibrary: false,
        personalUpdateMode: false,
      ));
      expect(s.settings.settings.hasSyncSelection, isFalse);
      await s.downloadAll();
      expect(prompts.calls, ['noSyncSelection']);
      expect(s.tasks.hasTask, isFalse);

      // גם מ"נסה שוב" במסך שהסתיים: המסך נשאר, וההודעה מסבירה למה.
      prompts.calls.clear();
      s.tasks
        ..prepareDownload()
        ..downloadFailed(const DownloadFailure(DownloadFailureKind.other));
      await s.downloadAll();
      expect(prompts.calls, ['noSyncSelection']);
      expect(
          (s.tasks.current! as DownloadTask).phase, DownloadTaskPhase.failed);
    });

    test('"הורדה" בזמן שמשימה אחרת רצה — לא נפתח "מתכונן" שנסגר בשקט', () {
      final s = session();
      s.otzaria.status = OtzariaModuleStatus.installing;
      unawaited(s.downloadAll());
      expect(s.tasks.hasTask, isFalse);
    });

    test(
        '"ביטול", "הורדה" ו"ביטול" שוב — הבקשה שבוטלה לא סוגרת את המסך '
        'החדש, והביטול השני נשמר', () async {
      final s = session();
      final abandoned = s.downloadAll();
      s.abandonPreparingDownload();
      expect(s.tasks.hasTask, isFalse);

      final again = s.downloadAll();
      expect(s.tasks.hasTask, isTrue);
      s.abandonPreparingDownload();
      expect(s.tasks.hasTask, isFalse);

      await abandoned;
      await again;
      expect(s.tasks.hasTask, isFalse);
      expect(s.longTaskRunning, isFalse);
    });

    test('שומר הסגירה שואל רק בזמן משימה, ומכבד את התשובה', () async {
      final s = session();
      expect(await s.confirmClose(), isTrue);
      expect(prompts.calls, isEmpty);

      s.otzaria.status = OtzariaModuleStatus.installing;
      prompts.closeAnswer = false;
      expect(await s.confirmClose(), isFalse);
      prompts.closeAnswer = true;
      expect(await s.confirmClose(), isTrue);
      expect(prompts.calls, ['confirmClose', 'confirmClose']);
      expect(prompts.closeDownloading, [false, false]);
    });

    group('החלון על החיפוש החכם לפני "עדכון המחשב הזה"', () {
      const answered = NoticesSeenStore.semanticConsentAnswered;

      AppSession withPendingConsent(MemoryNoticesStore notices) {
        final s = session(notices: notices);
        s.otzaria.currentVersion = '0.9.90';
        s.library
          ..status = LibraryModuleStatus.updateAvailable
          ..semanticPending = true;
        return s;
      }

      test('לא בעלייה; שואל בלחיצה, ו"המשך בלי" משקיט את הבית', () async {
        final notices = MemoryNoticesStore(
          seen: {NoticesSeenStore.errorReportsIntro},
        );
        final s = withPendingConsent(notices)..start();
        await s.otzaria.ensureChecked();
        await s.loadSemanticConsentAnswer();
        s.otzaria.currentVersion = '0.9.90';
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        expect(prompts.calls, isNot(contains('askSemantic')));
        expect(homeViewModelOf(s).semanticConsent, isTrue);

        await s.updateHere(const [GuidanceItem.library]);
        expect(prompts.calls, contains('askSemantic'));
        expect(notices.marked, [answered]);
        expect(s.tasks.hasTask, isTrue);
        expect(s.semanticConsentUnanswered, isFalse);
        expect(homeViewModelOf(s).semanticConsent, isFalse);
        expect(
          guidanceFactsFromSession(s).semanticConsentRequired,
          isFalse,
        );
      });

      test('תשובה שנשמרה במחשב הזה — אינו שואל שוב, והבית שקט', () async {
        final notices = MemoryNoticesStore(
          seen: {NoticesSeenStore.errorReportsIntro, answered},
        );
        final s = withPendingConsent(notices)..start();
        await waitFor(() => !s.semanticConsentUnanswered);
        expect(homeViewModelOf(s).semanticConsent, isFalse);
        await s.updateHere(const [GuidanceItem.library]);
        expect(prompts.calls, isNot(contains('askSemantic')));
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      });

      test('"חזרה" — שום דבר לא מתחיל ולא נרשם', () async {
        final notices = MemoryNoticesStore();
        final s = withPendingConsent(notices);
        prompts.semanticAnswer = null;
        await s.updateHere(const [GuidanceItem.library]);
        expect(s.tasks.hasTask, isFalse);
        expect(notices.marked, isEmpty);
        expect(s.semanticConsentUnanswered, isTrue);
      });

      test('הסכמה שלא נכתבה (אין אוצריא לכתוב אליה) — לא נרשמת', () async {
        final notices = MemoryNoticesStore();
        final s = withPendingConsent(notices);
        prompts.semanticAnswer = true;
        await s.updateHere(const [GuidanceItem.library]);
        await waitFor(() => s.tasks.current?.isFinished ?? true);
        expect(notices.marked, isEmpty);
        expect(s.semanticConsentUnanswered, isTrue);
      });

      test('כונן לקריאה בלבד — אותו חלון, והתשובה ב-stateFilesDir', () async {
        // כמו AppPaths בכונן מוגן: המצב במחשב, הכונן (dataDir) נשאר כמו שהוא.
        final drive = Directory(p.join(tempDir.path, 'drive'))..createSync();
        final machine = Directory(p.join(tempDir.path, 'machine'))
          ..createSync();
        final s = AppSession(
          dataDir: drive.path,
          stateDir: machine.path,
          settings: settings,
          prompts: prompts,
          readOnly: true,
          runningLocator: const _NeverRunningLocator(),
          otzariaLauncher: const _FailingLauncher(),
        );
        sessions.add(s);
        s.otzaria.currentVersion = '0.9.90';
        s.library
          ..status = LibraryModuleStatus.updateAvailable
          ..semanticPending = true;
        await s.updateHere(const [GuidanceItem.library]);
        expect(prompts.calls, contains('askSemantic'));

        final file = File(p.join(s.stateFilesDir, 'notices_seen.json'));
        expect(p.isWithin(machine.path, file.path), isTrue);
        expect(await file.readAsString(), contains(answered));
        expect(
            await NoticesSeenStore(s.stateFilesDir).hasSeen(answered), isTrue);
        expect(
          drive.listSync(recursive: true).whereType<File>().map(
                (f) => p.basename(f.path),
              ),
          isNot(contains('notices_seen.json')),
        );
        await waitFor(() => s.tasks.current?.isFinished ?? true);
      });

      group('רק החיפוש החכם בכונן', () {
        AppSession semanticOnly(MemoryNoticesStore notices) {
          final s = session(notices: notices);
          s.otzaria
            ..currentVersion = '0.9.90'
            ..status = OtzariaModuleStatus.upToDate;
          s.library
            ..status = LibraryModuleStatus.upToDate
            ..semanticPending = true;
          s.plugins.status = PluginsModuleStatus.ready;
          return s;
        }

        test('לפני שהתשובה נקראה — הבית שקט, בלי "עדכון" שמהבהב', () async {
          final s = semanticOnly(MemoryNoticesStore(seen: {answered}));
          expect(homeViewModelOf(s).guidance.hereItems, isEmpty);
          await s.loadSemanticConsentAnswer();
          expect(homeViewModelOf(s).guidance.hereItems, isEmpty);

          final fresh = semanticOnly(MemoryNoticesStore());
          expect(homeViewModelOf(fresh).guidance.hereItems, isEmpty);
          await fresh.loadSemanticConsentAnswer();
          expect(homeViewModelOf(fresh).guidance.hereItems, [
            GuidanceItem.library,
          ]);
        });

        for (final (write, recorded) in [
          (ConsentWrite.blocked, true),
          (ConsentWrite.failed, false),
        ]) {
          test('${write.name} — במשימה הסיבה; נרשם רק כשחסום', () async {
            final notices = MemoryNoticesStore();
            final s = AppSession(
              dataDir: tempDir.path,
              stateDir: tempDir.path,
              settings: settings,
              prompts: prompts,
              runningLocator: const _NeverRunningLocator(),
              noticesStore: notices,
              otzariaLauncher: const _FailingLauncher(),
              searchFeedback: SearchFeedbackController(
                transport: SearchFeedbackTransport(p.join(tempDir.path, 'sf')),
                resolveSource: () async => null,
                grantConsent: () async => write,
              ),
            );
            sessions.add(s);
            s.otzaria
              ..currentVersion = '0.9.90'
              ..status = OtzariaModuleStatus.upToDate;
            s.library
              ..status = LibraryModuleStatus.upToDate
              ..semanticPending = true;
            prompts.semanticAnswer = true;
            await s.updateHere(const [GuidanceItem.library]);
            await waitFor(() => s.tasks.current?.isFinished ?? false);

            final t = AppL10n.strings.libraryDomain;
            expect(notices.marked, recorded ? [answered] : isEmpty);
            final task = s.tasks.current! as UpdateHereTask;
            expect(task.outcomes[GuidanceItem.library], StageOutcome.skipped);
            expect(
              task.libraryNote,
              recorded ? t.semanticConsentBlocked : t.semanticConsentNotSaved,
            );
          });
        }

        test('חסימת שרת — הודעה מפורשת, התשובה נרשמת, ובמשימה הסיבה', () async {
          final notices = MemoryNoticesStore();
          final s = AppSession(
            dataDir: tempDir.path,
            stateDir: tempDir.path,
            settings: settings,
            prompts: prompts,
            runningLocator: const _NeverRunningLocator(),
            noticesStore: notices,
            otzariaLauncher: const _FailingLauncher(),
            searchFeedback: SearchFeedbackController(
              transport: SearchFeedbackTransport(p.join(tempDir.path, 'sf')),
              resolveSource: () async => null,
              grantConsent: () async => ConsentWrite.blocked,
            ),
          );
          sessions.add(s);
          s.otzaria
            ..currentVersion = '0.9.90'
            ..status = OtzariaModuleStatus.upToDate;
          s.library
            ..status = LibraryModuleStatus.upToDate
            ..semanticPending = true;
          prompts.semanticAnswer = true;
          await s.updateHere(const [GuidanceItem.library]);
          await waitFor(() => s.tasks.current?.isFinished ?? false);

          expect(notices.marked, [answered]);
          expect(s.semanticConsentUnanswered, isFalse);
          final task = s.tasks.current! as UpdateHereTask;
          expect(task.outcomes[GuidanceItem.library], StageOutcome.skipped);
          expect(
            task.libraryNote,
            AppL10n.strings.libraryDomain.semanticConsentBlocked,
          );
        });

        test('בלי אוצריא — בלי הודעה, והכפתור אינו מריץ את המתקין', () async {
          final notices = MemoryNoticesStore();
          final s = session(notices: notices);
          s.otzaria.status = OtzariaModuleStatus.updateAvailable;
          s.library
            ..status = LibraryModuleStatus.upToDate
            ..semanticPending = true;
          await s.loadSemanticConsentAnswer();
          expect(homeViewModelOf(s).semanticConsent, isFalse);
          await s.answerSemanticConsent();
          expect(s.tasks.hasTask, isFalse);
          expect(prompts.calls, isEmpty);
        });

        test('הגיבור מציע "עדכון המחשב הזה" עם החיפוש החכם, בלי הודעה כפולה',
            () async {
          final s = semanticOnly(MemoryNoticesStore());
          await s.loadSemanticConsentAnswer();
          final m = homeViewModelOf(s);
          expect(m.guidance.primary, GuidancePrimary.updateHere);
          expect(m.guidance.hereItems, [GuidanceItem.library]);
          expect(
            m.driveCompanionNames,
            AppL10n.strings.libraryDomain.companionSemanticName,
          );
          expect(m.semanticConsent, isFalse);
          expect(m.libraryTile, TileStatus.updateHere);
          expect(prompts.calls, isNot(contains('askSemantic')));
        });

        test('"המשך בלי" מהגיבור — בלי משימה, והבית שקט', () async {
          final notices = MemoryNoticesStore();
          final s = semanticOnly(notices);
          await s.loadSemanticConsentAnswer();
          await s.updateHere(homeViewModelOf(s).guidance.hereItems);
          expect(prompts.calls, ['askSemantic']);
          expect(notices.marked, [answered]);
          expect(s.tasks.hasTask, isFalse);
          final m = homeViewModelOf(s);
          expect(m.guidance.hereItems, isEmpty);
          expect(m.semanticConsent, isFalse);
          expect(m.libraryTile, TileStatus.upToDate);
        });

        test('הכפתור שבהודעה פותח את אותו חלון', () async {
          final notices = MemoryNoticesStore();
          final s = semanticOnly(notices);
          await s.answerSemanticConsent();
          expect(prompts.calls, ['askSemantic']);
          expect(notices.marked, [answered]);
        });

        test('עדכון לבד: בלי חלון, והגיבור עדיין מציע אחריו', () async {
          await settings.update(
            settings.settings.copyWith(autoInstall: true),
          );
          final s = semanticOnly(MemoryNoticesStore());
          await s.loadSemanticConsentAnswer();
          // ההתקנה האוטומטית מחילה רק "עדכון"; החיפוש החכם אינו כזה בלי הסכמה.
          expect(s.library.status, LibraryModuleStatus.upToDate);
          expect(prompts.calls, isNot(contains('askSemantic')));
          expect(
            homeViewModelOf(s).guidance.primary,
            GuidancePrimary.updateHere,
          );
        });
      });
    });

    test('"נסה שוב" כשאין עוד מה להתקין — חוזרים לבית, לא כפתור מת', () async {
      final s = session();
      s.tasks.startUpdateHere(
        const [GuidanceItem.library],
        request: (
          items: const [GuidanceItem.library],
          reinstallApp: false,
          fullLibrary: true,
        ),
      );
      s.tasks.updateFailed(const UpdateFailure(GuidanceItem.library));
      await s.retryUpdateHere();
      expect(s.tasks.hasTask, isFalse);
    });

    test('שומר הסגירה שואל גם בשלבי "עדכון כאן" שאינם משימה ארוכה', () async {
      final s = session();
      s.tasks.startUpdateHere(const [GuidanceItem.plugins]);
      expect(s.longTaskRunning, isFalse);
      prompts.closeAnswer = false;
      expect(await s.confirmClose(), isFalse);
      expect(prompts.calls, ['confirmClose']);

      // שאלת "לסגור את אוצריא?" — עוד לא רץ דבר, ולכן אין אזהרה.
      unawaited(s.tasks.askToCloseOtzaria());
      expect(await s.confirmClose(), isTrue);
      expect(prompts.calls, ['confirmClose']);
      s.tasks.respond(true);

      s.tasks.updateDone();
      expect(await s.confirmClose(), isTrue);
      expect(prompts.calls, ['confirmClose']);
    });
  });

  group('הורדה: חיפוש חכם, בדיקה מחודשת וקבצים שנכשלו', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    /// כל בדיקה ברשת רצה זה עתה ולא מצאה דבר — אין רענון לפני ההורדה.
    void allProven(AppSession s) {
      final now = DateTime.now();
      s.otzaria.onlineCheckedAt = now;
      s.library
        ..onlineCheckedAt = now
        ..semanticChecked = true;
      s.plugins
        ..onlineCheckedAt = now
        ..storeAppCheckedAt = now;
    }

    Future<DownloadTask> question(AppSession s) async {
      for (var i = 0; i < 200; i++) {
        final task = s.tasks.current;
        if (task is DownloadTask && task.phase == DownloadTaskPhase.question) {
          return task;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('השאלה לא נפתחה');
    }

    test('אין מה להוריד — אין מסך משימה, והבית אומר זאת', () async {
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      allProven(s);
      await s.downloadAll();
      expect(s.tasks.hasTask, isFalse);
      expect(s.isDownloading, isFalse);
      // הבדיקות היו טריות: "אין חדש" לפי הבדיקה הקודמת, לא "בדקתי שוב".
      expect(s.foundNothing, FoundNothing.earlierCheck);
      final model = homeViewModelOf(s);
      expect(model.foundNothing, FoundNothing.earlierCheck);
      expect(model.onlineCheckedAt, isNotNull);

      // שעה לכל רכיב: הספרייה החדשה ביותר, אבל בדיקת הנלווים שלה נכשלה.
      final base = DateTime.now();
      final appAt = base.add(const Duration(minutes: 1));
      final libraryAt = base.add(const Duration(minutes: 2));
      s.otzaria.onlineCheckedAt = appAt;
      s.library
        ..onlineCheckedAt = libraryAt
        ..onlineCompanionsCheckError = 'companions';
      s.plugins
        ..onlineCheckedAt = base
        ..storeAppCheckedAt = base;
      expect(homeViewModelOf(s).onlineCheckedAt, appAt);

      // רכיב שלא נבחר אינו נספר, גם כשהבדיקה שלו מאוחרת יותר.
      await settings.update(settings.settings.copyWith(syncPlugins: false));
      s.plugins.onlineCheckedAt = base.add(const Duration(minutes: 5));
      expect(homeViewModelOf(s).onlineCheckedAt, appAt);

      // "לא להוריד": החיפוש החכם לא נבדק — וזה אינו כשל של הספרייה.
      s.library.onlineCompanionsCheckError = null;
      await settings.update(settings.settings.copyWith(
        semanticDownload: SemanticDownloadPreference.never,
      ));
      s.library.semanticChecked = false;
      expect(s.library.onlineSemanticCheckError, isNull);
      expect(homeViewModelOf(s).onlineCheckedAt, libraryAt);

      await settings.update(settings.settings.copyWith(
        syncPlugins: true,
        semanticDownload: SemanticDownloadPreference.ask,
      ));
      allProven(s);
      await s.downloadAll();
      expect(s.foundNothing, FoundNothing.earlierCheck);

      // ההורדה הבאה מוחקת אותו מיד, עוד לפני שהיא מחליטה.
      final next = s.downloadAll();
      expect(s.foundNothing, isNull);
      await next;
      expect(s.foundNothing, FoundNothing.earlierCheck);

      // שינוי בקונטרולר (לא בהגדרות) אינו מוחק אותו.
      s.library
        ..failedCompanions = {CompanionAsset.talmud}
        ..forgetDownloadFailures();
      expect(s.foundNothing, FoundNothing.earlierCheck);

      await settings.update(settings.settings.copyWith(textScale: 1.15));
      expect(s.foundNothing, isNull);

      await s.downloadAll();
      expect(s.foundNothing, isNotNull);
      await s.checkOnline();
      expect(s.foundNothing, isNull);
    });

    test('"אל תציג שוב" עם "כן" שומר "תמיד להוריד"', () async {
      await settings.update(settings.settings.copyWith(
        personalUpdateMode: true,
      ));
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      allProven(s);
      s.library.semanticChecked = false;

      final run = s.downloadAll();
      await question(s);
      s.otzaria.status = OtzariaModuleStatus.installing;
      s.tasks.answer((download: true, remember: true));
      await run;
      expect(
        settings.settings.semanticDownload,
        SemanticDownloadPreference.always,
      );
      expect(s.library.semanticPreference, SemanticDownloadPreference.always);
    });

    test('"נסה שוב" על חיפוש חכם שנכשל מוריד אותו בלי לשאול', () async {
      final s = session();
      allProven(s);
      s.library
        ..onlineSemanticPending = true
        ..semanticDownloadFailed = true;
      expect(s.library.semanticPreference, SemanticDownloadPreference.ask);
      // בלי force: אין הורדה אמיתית, ולכן גם אין שאלה.
      await s.downloadAll();
      expect(s.foundNothing, isNotNull);

      await s.retryFailedDownloads();
      expect(s.foundNothing, isNull);
      final task = s.tasks.current;
      expect(task, isA<DownloadTask>());
      expect((task! as DownloadTask).components, [MirrorComponent.library]);
      expect(s.library.downloadStatus, isNot(MirrorDownloadStatus.idle));
    });

    // הורדה אחת חסמה כל פעולה אחרת. מחסומים מחזיקים פעולות פתוחות יחד.
    group('פעולות עצמאיות בזמן הורדה', () {
      late _Engines engines;

      Future<(AppSession, Future<void>)> downloading({
        bool plugins = true,
        LauncherSelfUpdater? launcher,
      }) async {
        await settings.update(settings.settings.copyWith(
          semanticDownload: SemanticDownloadPreference.never,
          syncPlugins: plugins,
        ));
        engines = _Engines(tempDir.path);
        final s = session(
          otzariaManager: engines.otzaria,
          libraryManager: engines.library,
          pluginsManager: engines.plugins,
          launcherUpdater: launcher,
          // ההתקנה העצמית ממתינה לעצירתו; בלי מקור הוא אינו פונה להתקנת
          // אוצריא האמיתית שבמחשב.
          searchFeedback: SearchFeedbackController(
            transport: SearchFeedbackTransport(p.join(tempDir.path, 'sf')),
            resolveSource: () async => null,
          ),
        )..start();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.library.downloadGate = Completer<void>();
        engines.plugins.syncGate = Completer<void>();
        final run = s.downloadAll();
        await waitFor(
            () => s.runningDownloads.contains(MirrorComponent.library));
        if (plugins) {
          await waitFor(
              () => s.runningDownloads.contains(MirrorComponent.plugins));
        }
        return (s, run);
      }

      Future<void> release(Future<void> run) async {
        for (final gate in [
          engines.library.downloadGate!,
          engines.plugins.syncGate!,
        ]) {
          if (!gate.isCompleted) gate.complete();
        }
        await run;
      }

      test('הספרייה והתוספים רצים יחד, אחרי התוכנה', () async {
        final (s, run) = await downloading();
        expect(s.runningDownloads,
            {MirrorComponent.library, MirrorComponent.plugins});
        expect(s.finishedDownloads, {MirrorComponent.app});
        expect(engines.plugins.syncCalls, 1);
        await release(run);
        expect(
            (s.tasks.current! as DownloadTask).phase, DownloadTaskPhase.done);
      });

      test(
          "הורדת הלאנצ'ר שנמשכת אחרי המראה: סגירה, מנהל והתקנה עצמית מחכים "
          'לה, ואחריה ההתקנה פתוחה', () async {
        final launcher = _SteppedLauncher();
        final (s, run) = await downloading(launcher: launcher);
        await waitFor(() => s.launcherUpdate.hasUpdateReady);
        final launcherRun = s.downloadLauncherUpdate();
        await waitFor(() => s.launcherUpdate.isDownloading);
        await release(run);
        expect(s.isDownloading, isFalse);
        expect(launcher.downloading, isTrue);

        expect(s.exitWouldInterrupt, isTrue);
        s.launcherUpdate.needsElevation = true;
        expect(s.canRestartElevated, isFalse);
        s.launcherUpdate.needsElevation = false;

        prompts.launcherInstallAnswer = true;
        await s.installLauncherUpdate();
        expect(launcher.calls, isNot(contains('apply')));
        expect(launcher.downloading, isTrue);

        // סגירה: נשאלת, עוצרת את ההעברה ומחכה לה לפני שהחלון נסגר.
        expect(await s.confirmClose(), isTrue);
        expect(prompts.closeDownloading.last, isTrue);
        expect(launcher.calls.last, 'stopped');
        expect(s.launcherUpdate.isDownloading, isFalse);
        await launcherRun;

        // הורדה חדשה שמסתיימת אינה חוסמת את ההתקנה של עצמה.
        launcher.gate.complete();
        await s.downloadLauncherUpdate();
        expect(launcher.calls, containsAllInOrder(['downloaded', 'apply']));
        expect(s.exitWouldInterrupt, isFalse);
      });

      test(
          'התקנת אוצריא לצד הורדה ברקע: הבית מציג את ההתקנה, וההורדה נגישה '
          'בלי לעצור אף אחת', () async {
        final (s, run) = await downloading(plugins: false);
        s.tasks.hideDownload();
        s.otzaria.status = OtzariaModuleStatus.installing;

        final model = homeViewModelOf(s);
        expect(model.task, HomeTask.installingApp);
        expect(model.downloadBehind, isTrue);

        s.tasks.showDownload();
        expect(s.tasks.current, isA<DownloadTask>());
        s.tasks.hideDownload();
        expect(s.isDownloading, isTrue);
        expect(s.otzaria.status, OtzariaModuleStatus.installing);

        s.otzaria.status = OtzariaModuleStatus.upToDate;
        expect(homeViewModelOf(s).task, HomeTask.downloading);
        expect(homeViewModelOf(s).downloadBehind, isFalse);
        await release(run);
      });

      test('החנות שואלת את הסשן: מראת תוספים שההורדה כותבת חוסמת קוראים',
          () async {
        final (s, run) = await downloading();
        expect(s.plugins.mirrorWrittenElsewhere!(), isTrue);
        expect(s.plugins.syncBlockedElsewhere!(), isTrue);
        expect(s.plugins.syncBlockedReason(forDownload: true), isNull);
        await release(run);
        await waitFor(() => !s.plugins.mirrorWrittenElsewhere!());
        expect(s.plugins.syncBlockedElsewhere!(), isFalse);
      });

      test('רצף מסירות שממשיך ברקע: "עדכון כאן" חדש אינו שולח אותם שוב',
          () async {
        final s = session();
        StorePlugin entry(String id) => StorePlugin.fromApi(
              {'id': id, 'name': id},
              'https://example.invalid',
            );
        final run = s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
        await waitFor(() => !s.plugins.isDeliveringAny);
        expect(s.plugins.isDeliveryRunActive, isTrue);
        expect(s.installsBlockedByDownload, contains(GuidanceItem.plugins));
        await run;
        expect(
            s.installsBlockedByDownload, isNot(contains(GuidanceItem.plugins)));
      });

      test('רצף מסירות ברקע: סגירה שואלת, והחלפת קובץ ההרצה ממתינה', () async {
        final s = session();
        StorePlugin entry(String id) => StorePlugin.fromApi(
              {'id': id, 'name': id},
              'https://example.invalid',
            );
        expect(s.exitWouldInterrupt, isFalse);
        final run = s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
        await waitFor(() => !s.plugins.isDeliveringAny);
        expect(s.exitWouldInterrupt, isTrue);
        prompts.closeAnswer = false;
        expect(await s.confirmClose(), isFalse);
        expect(prompts.calls, contains('confirmClose'));
        await run;
        expect(s.exitWouldInterrupt, isFalse);
      });

      group('סגירה מאושרת בזמן רצף מסירות', () {
        late _GatedDeliveries engine;
        StorePlugin entry(String id) => StorePlugin.fromApi(
              {'id': id, 'name': id},
              'https://example.invalid',
            );
        AppSession withEngine() {
          engine = _GatedDeliveries(tempDir.path);
          return session(
            pluginsManager: engine,
            closeDeliveryPatience: const Duration(milliseconds: 100),
          );
        }

        /// אחרי שהסגירה הסתיימה, שום מסירה נוספת — גם אחרי המרווח.
        Future<void> expectNothingMore(AppSession s, List<String> sent) async {
          await Future<void>.delayed(pluginUpdateDeliverySpacing * 2);
          expect(engine.delivered, sent);
          expect(s.plugins.isDeliveryRunActive, isFalse);
          expect(s.plugins.isDeliveringAny, isFalse);
          expect(s.plugins.isReadingMirror, isFalse);
        }

        test('סירוב: הרצף ממשיך עד הסוף', () async {
          final s = withEngine();
          final run =
              s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(() => !s.plugins.isDeliveringAny);
          prompts.closeAnswer = false;
          expect(await s.confirmClose(), isFalse);
          expect((await run).map((p) => p.id), ['a', 'b']);
        });

        test('אישור באמצע מסירה: ממתין לה, ולא מתחיל את הבאה', () async {
          final s = withEngine();
          final gate = engine.gates['a'] = Completer<void>();
          final run =
              s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(() => s.plugins.isDeliveringAny);
          bool? closed;
          final close = s.confirmClose().then((ok) => closed = ok);
          await pumpEventQueue();
          expect(prompts.calls, contains('confirmClose'));
          expect(closed, isNull);

          gate.complete();
          expect(await close, isTrue);
          expect(s.plugins.isDeliveryRunActive, isFalse);
          expect((await run).map((p) => p.id), ['a']);
          await expectNothingMore(s, ['a']);
        });

        test('אישור ברווח שבין מסירות: חוזר רק אחרי שהרצף נעצר', () async {
          final s = withEngine();
          final run =
              s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(
              () => engine.delivered.isNotEmpty && !s.plugins.isDeliveringAny);
          expect(s.plugins.isDeliveryRunActive, isTrue);

          expect(await s.confirmClose(), isTrue);
          expect(s.plugins.isDeliveryRunActive, isFalse);
          expect((await run).map((p) => p.id), ['a']);
          await expectNothingMore(s, ['a']);
        });

        test('מסירה שזורקת או נכשלת משחררת את כל המצבים', () async {
          final s = withEngine();
          engine.throwing.add('a');
          final gate = engine.gates['a'] = Completer<void>();
          final run =
              s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(() => s.plugins.isDeliveringAny);
          final close = s.confirmClose();
          await pumpEventQueue();
          gate.complete();
          expect(await close, isTrue);
          expect(await run, isEmpty);
          await expectNothingMore(s, ['a']);

          final s2 = withEngine();
          engine.failing.add('a');
          final run2 =
              s2.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(
              () => engine.delivered.isNotEmpty && !s2.plugins.isDeliveringAny);
          expect(await s2.confirmClose(), isTrue);
          expect(await run2, isEmpty);
          await expectNothingMore(s2, ['a']);
        });

        test(
            'מסירה שאינה חוזרת: הסגירה אינה יוצאת; "חזרה לכלי" מחזירה מצב '
            'תקין', () async {
          final s = withEngine();
          final gate = engine.gates['a'] = Completer<void>();
          final run =
              s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(() => s.plugins.isDeliveringAny);
          prompts.keepWaitingAnswers.add(false);

          expect(await s.confirmClose(), isFalse);
          expect(prompts.calls, contains('keepWaitingForDeliveries'));
          // המסירה עדיין באוויר, ואין מה שמעמיד פנים אחרת.
          expect(s.plugins.isDelivering(entry('a')), isTrue);
          expect(s.plugins.isReadingMirror, isTrue);
          // מסירות חדשות מותרות שוב.
          final other = s.plugins.deliver(entry('c'));
          expect((await other).success, isTrue);

          gate.complete();
          // הרצף עוד לא הגיע לבדיקה הבאה שלו, ולכן ממשיך כרגיל.
          expect((await run).map((p) => p.id), ['a', 'b']);
          await expectNothingMore(s, ['a', 'c', 'b']);
        });

        test('מסירה שאינה חוזרת: "להמשיך לחכות" סוגר רק כשהיא מסתיימת',
            () async {
          final s = withEngine();
          final gate = engine.gates['a'] = Completer<void>();
          final run =
              s.plugins.deliverUpdates(plugins: [entry('a'), entry('b')]);
          await waitFor(() => s.plugins.isDeliveringAny);
          prompts.keepWaitingAnswers.addAll([true, true]);

          bool? closed;
          final close = s.confirmClose().then((ok) => closed = ok);
          await waitFor(() =>
              prompts.calls
                  .where((c) => c == 'keepWaitingForDeliveries')
                  .length ==
              2);
          expect(prompts.calls.where((c) => c == 'keepWaitingForDeliveries'),
              hasLength(2));
          expect(closed, isNull);

          gate.complete();
          expect(await close, isTrue);
          expect((await run).map((p) => p.id), ['a']);
          await expectNothingMore(s, ['a']);
        });

        test('מסירה בודדת מהחנות: בלי שאלה, אבל הסגירה ממתינה לה', () async {
          final s = withEngine();
          final gate = engine.gates['a'] = Completer<void>();
          final delivery = s.plugins.deliver(entry('a'));
          bool? closed;
          final close = s.confirmClose().then((ok) => closed = ok);
          await pumpEventQueue();
          expect(closed, isNull);
          expect(prompts.calls, isNot(contains('confirmClose')));
          gate.complete();
          expect(await close, isTrue);
          expect((await delivery).success, isTrue);
          expect(s.plugins.isReadingMirror, isFalse);
        });
      });

      test('העתקת החנות: שלב התוספים של "עדכון כאן" ממתין', () async {
        final s = session();
        expect(
            s.installsBlockedByDownload, isNot(contains(GuidanceItem.plugins)));
        s.plugins.isExporting = true;
        expect(s.installsBlockedByDownload, contains(GuidanceItem.plugins));
        s.plugins.isExporting = false;
      });

      test('סוף הניקוי שאחרי ההורדה משחרר את הכפתורים ומודיע למסך', () async {
        final (s, run) = await downloading();
        final seen = <bool>[];
        s.addListener(() =>
            seen.add(s.libraryApplyBlocked || s.pluginSyncBlockedElsewhere));
        await release(run);
        await waitFor(
            () => !s.libraryApplyBlocked && !s.pluginSyncBlockedElsewhere);
        await pumpEventQueue();
        expect(seen.last, isFalse);
      });

      test('שליחת דיווחים בזמן הורדת הספרייה וסנכרון התוספים — פעם אחת',
          () async {
        final (s, run) = await downloading();
        expect(s.plugins.isSyncing, isTrue);
        expect(s.reportsUploadBlocked, isFalse);

        prompts.uploadGate = Completer<void>();
        final upload = s.uploadReports();
        expect(prompts.calls.where((c) => c == 'uploadReports'), hasLength(1));
        // לחיצה שנייה בזמן הראשונה אינה פותחת שליחה נוספת.
        await s.uploadReports();
        expect(prompts.calls.where((c) => c == 'uploadReports'), hasLength(1));

        prompts.uploadGate!.complete();
        await upload;
        expect(s.isDownloading, isTrue);
        await release(run);
        expect(
            (s.tasks.current! as DownloadTask).phase, DownloadTaskPhase.done);
      });

      test('איסוף דיווחים אינו נחסם בהורדה, רק בהתקנה כאן', () async {
        final (s, run) = await downloading();
        expect(s.reportsCollectBlocked, isFalse);
        s.otzaria.status = OtzariaModuleStatus.installing;
        expect(s.reportsCollectBlocked, isTrue);
        expect(s.reportsUploadBlocked, isFalse);
        s.otzaria.status = OtzariaModuleStatus.upToDate;
        await release(run);
      });

      test(
          'בזמן הורדת הספרייה: התקנת אוצריא ותוספים פתוחה, ההחלה של הספרייה '
          'סגורה', () async {
        final (s, run) = await downloading(plugins: false);
        expect(s.installsBlockedByDownload, {GuidanceItem.library});
        expect(s.appInstallBlocked, isFalse);
        expect(s.pluginActionsBlockedElsewhere, isFalse);
        expect(s.pluginSyncBlockedElsewhere, isFalse);
        expect(s.libraryApplyBlocked, isTrue);

        await release(run);
        await waitFor(() => s.installsBlockedByDownload.isEmpty);
        expect(s.libraryApplyBlocked, isFalse);
      });

      test('בזמן סנכרון התוספים בהורדה: מסירה ורענון בחנות סגורים', () async {
        final (s, run) = await downloading();
        engines.library.downloadGate!.complete();
        await waitFor(
            () => !s.runningDownloads.contains(MirrorComponent.library));
        expect(s.installsBlockedByDownload, {GuidanceItem.plugins});
        expect(s.pluginActionsBlockedElsewhere, isTrue);
        expect(s.pluginSyncBlockedElsewhere, isTrue);
        expect(s.libraryApplyBlocked, isFalse);
        expect(s.appInstallBlocked, isFalse);
        await release(run);
      });

      test('"עדכון כאן" בזמן הורדת הספרייה מתקין את התוכנה בלבד', () async {
        final (s, run) = await downloading(plugins: false);
        s.tasks.hideDownload();
        s.otzaria
          ..currentVersion = 'v1'
          ..latestVersion = 'v2'
          ..status = OtzariaModuleStatus.updateAvailable;
        s.library.status = LibraryModuleStatus.updateAvailable;

        // הבית מציע רק את מה שהמראה שלו כבר נכתבה.
        final guidance = homeViewModelOf(s).guidance;
        expect(guidance.primary, GuidancePrimary.taskInProgress);
        expect(guidance.hereItems, [GuidanceItem.app]);

        unawaited(s.updateHere(const [GuidanceItem.library, GuidanceItem.app]));
        await waitFor(() => s.tasks.updateTask != null);
        expect(s.tasks.updateTask!.stages, [GuidanceItem.app]);
        expect(s.tasks.current, isA<UpdateHereTask>());
        expect(s.isDownloading, isTrue);
        // עכשיו הורדה חדשה אינה מתחילה: "עדכון כאן" קורא את המראה.
        expect(s.downloadBlocked, isTrue);

        await waitFor(() => s.tasks.updateTask!.isFinished);
        expect(s.isDownloading, isTrue);
        s.tasks.dismiss();
        await release(run);
        expect(
            (s.tasks.current! as DownloadTask).phase, DownloadTaskPhase.done);
      });

      test('"עדכון כאן" רק לספרייה בזמן שהיא יורדת — הודעה, בלי משימה',
          () async {
        final messages = <String>[];
        final previousPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message?.startsWith('UiSnack') ?? false) messages.add(message!);
        };
        addTearDown(() => debugPrint = previousPrint);
        final (s, run) = await downloading(plugins: false);
        s.tasks.hideDownload();
        s.otzaria.currentVersion = 'v1';
        s.library.status = LibraryModuleStatus.updateAvailable;
        await s.updateHere(const [GuidanceItem.library]);
        expect(s.tasks.updateTask, isNull);
        expect(messages.single,
            contains(AppL10n.strings.task.installWaitsForDownloadSnack));
        await release(run);
      });

      test('"עדכון כאן" לתוספים בזמן העתקת החנות — ההודעה מהחנות, לא מהורדה',
          () async {
        final messages = <String>[];
        final previousPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message?.startsWith('UiSnack') ?? false) messages.add(message!);
        };
        addTearDown(() => debugPrint = previousPrint);
        final s = session();
        s.otzaria.currentVersion = 'v1';
        s.plugins.isExporting = true;
        await s.updateHere(const [GuidanceItem.plugins]);
        expect(s.tasks.updateTask, isNull);
        expect(messages.single,
            contains(AppL10n.strings.plugins.actionsBlockedExporting));
        s.plugins.isExporting = false;
      });

      test('"ביטול" ב"מתכונן" — הזרימה שחוזרת אינה חוסמת התקנה', () async {
        await settings.update(settings.settings
            .copyWith(semanticDownload: SemanticDownloadPreference.never));
        engines = _Engines(tempDir.path);
        final s = session(
          otzariaManager: engines.otzaria,
          libraryManager: engines.library,
          pluginsManager: engines.plugins,
        )..start();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        // הבדיקה המקוונת שלפני ההורדה ממתינה, כדי ללחוץ "ביטול" בזמנה.
        final gate = engines.otzaria.peekGate = Completer<void>();
        final run = s.downloadAll();
        await waitFor(() => s.isCheckingOnline);
        expect(s.installsBlockedByDownload, GuidanceItem.values.toSet());

        s.abandonPreparingDownload();
        expect(s.installsBlockedByDownload, isEmpty);
        expect(s.pluginSyncBlockedElsewhere, isFalse);
        gate.complete();
        await run;
        expect(engines.library.downloadCalls, 0);
      });

      test('"עדכון כאן" אינו נפתח כשמסך ההורדה בחזית', () async {
        final (s, run) = await downloading(plugins: false);
        s.otzaria
          ..currentVersion = 'v1'
          ..status = OtzariaModuleStatus.updateAvailable;
        await s.updateHere(const [GuidanceItem.app]);
        expect(s.tasks.updateTask, isNull);
        await release(run);
      });

      test('רענון התוספים נחסם כל עוד המתקין יורד — הוא בוחר גרסאות לפיו',
          () async {
        await settings.update(settings.settings
            .copyWith(semanticDownload: SemanticDownloadPreference.never));
        engines = _Engines(tempDir.path);
        final s = session(
          otzariaManager: engines.otzaria,
          libraryManager: engines.library,
          pluginsManager: engines.plugins,
        )..start();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.otzaria.downloadGate = Completer<void>();
        final run = s.downloadAll();
        await waitFor(() => s.runningDownloads.contains(MirrorComponent.app));
        expect(s.pluginSyncBlockedElsewhere, isTrue);
        engines.otzaria.downloadGate!.complete();
        await run;
        // הניקוי שבסוף ההורדה חוסם גם הוא, עד שנגמר.
        await waitFor(() => !s.pluginSyncBlockedElsewhere);
        expect(s.pluginSyncBlockedElsewhere, isFalse);
      });

      test('"הורדה" עם תוכנה בזמן רענון תוספים עצמאי — מסורבת, לא רצה',
          () async {
        await settings.update(settings.settings.copyWith(
          semanticDownload: SemanticDownloadPreference.never,
          syncPlugins: false,
        ));
        engines = _Engines(tempDir.path);
        final s = session(
          otzariaManager: engines.otzaria,
          libraryManager: engines.library,
          pluginsManager: engines.plugins,
        )..start();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.plugins.syncGate = Completer<void>();
        final sync = s.plugins.sync();
        await waitFor(() => s.plugins.isSyncing);

        await s.downloadAll();
        expect(engines.library.downloadCalls, 0);
        expect(s.isDownloading, isFalse);
        expect(s.tasks.hasTask, isFalse);

        engines.plugins.syncGate!.complete();
        await sync;
      });

      test('ביטול אחרי שהספרייה הסתיימה מחזיר רק את התוספים', () async {
        final (s, run) = await downloading();
        engines.library.downloadGate!.complete();
        await waitFor(
            () => s.finishedDownloads.contains(MirrorComponent.library));
        s.tasks.hideDownload();
        prompts.cancelAnswer = true;
        await s.cancelDownload();
        await release(run);
        final task = s.tasks.current! as DownloadTask;
        expect(task.phase, DownloadTaskPhase.cancelled);
        expect(task.kept, [MirrorComponent.app, MirrorComponent.library]);
      });

      test('"הורדה" שנייה בזמן ההורדה אינה מריצה את הספרייה פעמיים', () async {
        final (s, run) = await downloading();
        s.tasks.hideDownload();
        await s.downloadAll();
        expect(engines.library.downloadCalls, 1);
        await release(run);
        expect(engines.library.downloadCalls, 1);
      });

      test('ביטול בזמן שהספרייה והתוספים רצים מחזיר את שניהם', () async {
        final (s, run) = await downloading();
        s.tasks.hideDownload();
        prompts.cancelAnswer = true;
        await s.cancelDownload();
        expect(s.isCancellingDownload, isTrue);
        await release(run);
        final task = s.tasks.current! as DownloadTask;
        expect(task.phase, DownloadTaskPhase.cancelled);
        expect(task.kept, [MirrorComponent.app]);
        expect(s.isDownloading, isFalse);
      });

      test(
          'סגירה בזמן הורדה ושליחה: שואלת פעם אחת, ממתינה להורדה ושומרת '
          'את ההתקדמות', () async {
        final (s, run) = await downloading();
        s.tasks.hideDownload();
        prompts.uploadGate = Completer<void>();
        unawaited(s.uploadReports());
        expect(s.exitWouldInterrupt, isTrue);

        var closed = false;
        final close = s.confirmClose().then((ok) => closed = ok);
        await waitFor(() => prompts.calls.contains('confirmClose'));
        expect(prompts.closeDownloading, [true]);
        expect(s.isCancellingDownload, isTrue);
        expect(closed, isFalse);

        await release(run);
        await close;
        expect(closed, isTrue);
        // נעצרה בלי שחזור: לא "בוטל", והקבצים החלקיים נשארו להמשך.
        expect(
            (s.tasks.downloadTask!).phase, isNot(DownloadTaskPhase.cancelled));
        prompts.uploadGate!.complete();
      });
    });

    group('כונן מלא באמצע ההורדה — מסלול מלא', () {
      late _Engines engines;

      Future<AppSession> fullSession() async {
        await settings.update(settings.settings
            .copyWith(semanticDownload: SemanticDownloadPreference.never));
        engines = _Engines(tempDir.path);
        final s = session(
          otzariaManager: engines.otzaria,
          libraryManager: engines.library,
          pluginsManager: engines.plugins,
        )..start();
        return s;
      }

      DownloadTask task(AppSession s) => s.tasks.current! as DownloadTask;

      test('בדיקת ביקורת: בלי כשל אחסון גם תוכנת החנות מתחילה', () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        await s.library.checkForUpdate();
        final checksBefore = engines.library.checkCalls;
        await s.downloadAll();
        expect(engines.library.checkCalls, greaterThan(checksBefore));
        expect(engines.plugins.syncCalls, 1);
        expect(engines.plugins.storeAppCalls, greaterThanOrEqualTo(1));
      });

      /// הספרייה והתוספים מתחילים יחד; התוספים נעצרים עד שהספרייה נכשלה.
      Future<void> downloadWhileLibraryFails(AppSession s) async {
        engines.plugins.syncGate = Completer<void>();
        final run = s.downloadAll();
        await waitFor(
            () => s.library.downloadStatus == MirrorDownloadStatus.error);
        engines.plugins.syncGate!.complete();
        await run;
      }

      test(
          'כשל אחסון בספרייה (חריג אמיתי): התוספים שרצו לצידה מסתיימים, '
          'תוכנת החנות לא מתחילה', () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.library.error =
            await realDownloadFailure(tempDir, diskFullErrno);
        await downloadWhileLibraryFails(s);
        expect(engines.plugins.syncCalls, 1);
        expect(engines.plugins.storeAppCalls, 0);
        expect(task(s).phase, DownloadTaskPhase.failed);
        expect(task(s).failure!.kind, DownloadFailureKind.diskSpace);
      });

      test('כשל אחסון בסנכרון התוספים עצמו עוצר את תוכנת החנות', () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.plugins.outcome = const PluginSyncOutcome(
          catalog: PluginCatalog.empty,
          fetched: 0,
          skipped: 0,
          storageFailure: StorageFullException(dir: 'E:'),
        );
        await s.downloadAll();
        expect(engines.plugins.syncCalls, 1);
        expect(engines.plugins.storeAppCalls, 0);
        expect(task(s).failure!.kind, DownloadFailureKind.diskSpace);
      });

      test(
          'PatchDownloadException אמיתי בספרייה: אין תוכנת חנות, כשל diskSpace',
          () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.library.error =
            await realDownloadFailure(tempDir, diskFullErrno);
        await downloadWhileLibraryFails(s);

        expect(engines.plugins.storeAppCalls, 0);
        final t = task(s);
        expect(t.phase, DownloadTaskPhase.failed);
        expect(t.failure!.kind, DownloadFailureKind.diskSpace);
        expect(t.failure!.components, [MirrorComponent.library]);
        // האפליקציה שירדה לפני הספרייה אינה כשלה, ולכן נשארת.
        expect(t.failure!.components, isNot(contains(MirrorComponent.app)));
        expect(s.library.downloadStatus, MirrorDownloadStatus.error);
        expect(s.isDownloading, isFalse);
      });

      test('StateError אמיתי של בדיקת המקום: נדרש ופנוי מוצגים', () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.library.error = StateError(AppL10n.strings.libraryDomain
            .mirrorNotEnoughDiskSpace('E:', '2 GB', '1 GB'));
        await downloadWhileLibraryFails(s);
        expect(engines.plugins.storeAppCalls, 0);
        expect(task(s).failure!.kind, DownloadFailureKind.diskSpace);
        expect(task(s).failure!.needed, '2 GB');
      });

      test('כשל אחסון בסנכרון התוספים: כשל diskSpace על התוספים', () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.plugins.outcome = const PluginSyncOutcome(
          catalog: PluginCatalog.empty,
          fetched: 0,
          skipped: 0,
          storageFailure: StorageFullException(dir: 'E:'),
        );
        await s.downloadAll();
        final t = task(s);
        expect(t.phase, DownloadTaskPhase.failed);
        expect(t.failure!.kind, DownloadFailureKind.diskSpace);
        expect(t.failure!.components, [MirrorComponent.plugins]);
      });

      test('ניסיון נוסף אחרי שהכונן התפנה אינו תקוע על הכשל הישן', () async {
        final s = await fullSession();
        await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
        engines.library.error =
            await realDownloadFailure(tempDir, diskFullErrno);
        await s.downloadAll();
        expect(task(s).phase, DownloadTaskPhase.failed);

        engines.library.error = null;
        await s.downloadAll();
        expect(engines.plugins.syncCalls, 1);
        expect(task(s).phase, DownloadTaskPhase.done);
      });
    });

    test('"אל תציג שוב" עם "לא" שומר "לא להוריד"; "חזרה" לא שומרת', () async {
      await settings.update(settings.settings.copyWith(
        personalUpdateMode: true,
      ));
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      allProven(s);
      s.library.semanticChecked = false;

      final back = s.downloadAll();
      await question(s);
      s.tasks.answer(null);
      await back;
      expect(
        settings.settings.semanticDownload,
        SemanticDownloadPreference.ask,
      );

      final run = s.downloadAll();
      await question(s);
      // נחסם אחרי התשובה, כדי שלא תרוץ הורדה אמיתית.
      s.otzaria.status = OtzariaModuleStatus.installing;
      s.tasks.answer((download: false, remember: true));
      await run;
      expect(
        settings.settings.semanticDownload,
        SemanticDownloadPreference.never,
      );
      expect(s.library.semanticPreference, SemanticDownloadPreference.never);
    });

    test('השורה המשנית רק ב"לשאול", כשהספרייה נבחרת להורדה', () async {
      final s = session()..start();
      await waitFor(() => s.plugins.status != PluginsModuleStatus.loading);
      s.library
        ..onlineSemanticPending = true
        ..semanticChecked = true;
      expect(s.onlineSemanticOffer, isTrue);
      expect(homeViewModelOf(s).semanticOffer, isTrue);
      expect(s.library.hasOnlineUpdate, isFalse);

      await settings.update(settings.settings.copyWith(syncLibrary: false));
      expect(s.onlineSemanticOffer, isFalse);

      await settings.update(settings.settings.copyWith(
        syncLibrary: true,
        semanticDownload: SemanticDownloadPreference.always,
      ));
      expect(s.onlineSemanticOffer, isFalse);
      expect(s.library.hasOnlineUpdate, isTrue);
    });

    test('קובץ שנכשל — הערה בבית עד שנשכח', () async {
      final s = session();
      allProven(s);
      s.library
        ..onlinePendingCompanions = {CompanionAsset.talmud}
        ..failedCompanions = {CompanionAsset.talmud};
      expect(homeViewModelOf(s).failedDownloads, isNotNull);
      expect(s.library.hasOnlineUpdate, isFalse);

      // בדיקה מאוחרת יותר מצאה שהוא כבר בכונן — אין עוד מה לומר.
      s.library.onlinePendingCompanions = const {};
      expect(homeViewModelOf(s).failedDownloads, isNull);

      s.library.onlinePendingCompanions = {CompanionAsset.talmud};
      s.library.forgetDownloadFailures();
      expect(homeViewModelOf(s).failedDownloads, isNull);
      expect(s.library.hasOnlineUpdate, isTrue);
    });
  });

  group('ההכוונה רואה כל משימה ארוכה', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    GuidancePrimary primary(AppSession s) =>
        deriveHomeGuidance(guidanceFactsFromSession(s)).primary;

    test('ייצוא, תוכנה מותאמת והחלפת קובץ ההרצה', () {
      final s = session();
      expect(primary(s), isNot(GuidancePrimary.taskInProgress));

      s.plugins.isExporting = true;
      expect(primary(s), GuidancePrimary.taskInProgress);
      expect(homeViewModelOf(s).task, HomeTask.exportingStore);
      s.plugins.isExporting = false;

      s.customApps.isLearning = true;
      expect(primary(s), GuidancePrimary.taskInProgress);
      expect(homeViewModelOf(s).task, HomeTask.customApps);
      s.customApps.isLearning = false;

      s.customApps.downloadAllTotal = 2;
      expect(primary(s), GuidancePrimary.taskInProgress);
      expect(homeViewModelOf(s).task, HomeTask.downloadingCustomApps);
      s.customApps.downloadAllTotal = null;

      s.launcherUpdate.status = LauncherUpdateStatus.installing;
      expect(primary(s), GuidancePrimary.taskInProgress);
      expect(homeViewModelOf(s).task, HomeTask.installingLauncher);
    });

    test('סנכרון החנות', () async {
      final s = session();
      final run = s.plugins.sync();
      expect(s.plugins.isSyncing, isTrue);
      expect(primary(s), GuidancePrimary.taskInProgress);
      expect(homeViewModelOf(s).task, HomeTask.syncingPlugins);
      try {
        await run;
      } catch (_) {}
      expect(s.plugins.isSyncing, isFalse);
    });
  });

  group('אחרי פירוק הסשן אינו מודיע', () {
    setUp(() => HttpOverrides.global = NoNetworkHttpOverrides());
    tearDown(() => HttpOverrides.global = null);

    // notifyListeners אחרי dispose זורק ב-debug. הקונטרולרים עצמם עוד מודיעים
    // אחרי פירוק (כמו לפני החילוץ), ולכן נבדקות רק השגיאות של הסשן.
    Future<List<String>> sessionErrors(
      Future<void> Function(AppSession s) body,
    ) async {
      final errors = <String>[];
      final done = Completer<void>();
      unawaited(runZonedGuarded(
        () async {
          final s = session();
          sessions.remove(s);
          try {
            await body(s);
          } catch (error) {
            errors.add('$error');
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
          done.complete();
        },
        (error, _) => errors.add('$error'),
      ));
      await done.future;
      return errors.where((e) => e.contains('AppSession')).toList();
    }

    test('פירוק באמצע checkOnline', () async {
      final errors = await sessionErrors((s) async {
        final check = s.checkOnline();
        s.dispose();
        await check;
      });
      expect(errors, isEmpty);
      expect(prompts.calls, isNot(contains('confirmLauncherInstall')));
    });

    test('פירוק מיד אחרי start', () async {
      final errors = await sessionErrors((s) async {
        s
          ..start()
          ..dispose();
      });
      expect(errors, isEmpty);
      expect(LauncherCrashSession.closeGuard, isNull);
    });
  });

  test('מניעת שינה רק בזמן עבודה', () {
    var acquired = 0;
    var released = 0;
    final inhibitor = SleepInhibitor(acquire: () {
      acquired++;
      return () => released++;
    });
    final s = session(sleep: inhibitor);

    s.otzaria.status = OtzariaModuleStatus.upToDate;
    s.otzaria.notifyListeners();
    expect(acquired, 0);

    s.library.downloadStatus = MirrorDownloadStatus.downloading;
    s.library.notifyListeners();
    expect(inhibitor.isActive, isTrue);
    s.library.downloadStatus = MirrorDownloadStatus.done;
    s.library.notifyListeners();
    expect(inhibitor.isActive, isFalse);

    s.otzaria.status = OtzariaModuleStatus.installing;
    s.otzaria.notifyListeners();
    expect(inhibitor.isActive, isTrue);
    s.otzaria.status = OtzariaModuleStatus.upToDate;
    s.otzaria.notifyListeners();
    expect(inhibitor.isActive, isFalse);
    expect((acquired, released), (2, 2));

    s.launcherUpdate.status = LauncherUpdateStatus.downloading;
    s.launcherUpdate.notifyListeners();
    expect(inhibitor.isActive, isTrue);
    sessions.remove(s);
    s.dispose();
    expect(inhibitor.isActive, isFalse);
    expect((acquired, released), (3, 3));
  });
}

/// הורדת לאנצ'ר מדומה: מתקדמת בצעדים, בודקת עצירה בין צעד לצעד, ומסתיימת
/// רק כשהבדיקה משחררת את [gate]. [ready] — גרסה שכבר יושבת במראה.
class _SteppedLauncher implements LauncherSelfUpdater {
  String? ready = 'v8.0.0';
  final calls = <String>[];
  Completer<void> gate = Completer<void>();
  bool get downloading => calls.last == 'download';

  static LauncherRelease _release(String tag) => LauncherRelease(
        tagName: tag,
        name: tag,
        assetName: 'launcher.exe',
        downloadUrl: 'https://example.invalid/launcher.exe',
        sizeBytes: 4,
      );

  @override
  String get currentVersion => '1.0.0';

  @override
  String get mirrorDir => 'mirror/launcher';

  @override
  Future<LauncherUpdateCheck> checkForUpdate({
    bool cleanupLeftovers = true,
  }) async =>
      LauncherUpdateCheck(
        currentVersion: currentVersion,
        mirrored: switch (ready) {
          final tag? =>
            MirroredLauncherRelease(release: _release(tag), filePath: 'f'),
          null => null,
        },
        canInstall: true,
      );

  @override
  Future<MirroredLauncherRelease?> downloadToMirror({
    LauncherRelease? release,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls.add('download');
    for (var received = 0; !gate.isCompleted; received++) {
      if (isCancelled?.call() ?? false) {
        calls.add('stopped');
        throw const LauncherDownloadCancelled();
      }
      onProgress?.call(received, 1000);
      await Future.any(
          [gate.future, Future<void>.delayed(const Duration(milliseconds: 2))]);
    }
    ready = 'v9.0.0';
    calls.add('downloaded');
    return MirroredLauncherRelease(release: _release('v9.0.0'), filePath: 'f');
  }

  @override
  Future<LauncherRelease?> peekLatestOnline() async => null;

  @override
  Future<bool> applyUpdate() async {
    calls.add('apply');
    return false;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

class _FakePrompts implements SessionPrompts {
  final calls = <String>[];
  bool closeAnswer = true;
  final closeDownloading = <bool>[];

  @override
  Future<T?> runDialog<T>(Future<T> Function() body, {bool forever = false}) =>
      body();

  @override
  Future<bool> confirmClose({required bool downloading}) async {
    calls.add('confirmClose');
    closeDownloading.add(downloading);
    return closeAnswer;
  }

  /// התשובות לפי הסדר; כשנגמרו — ממשיכים לחכות.
  final keepWaitingAnswers = <bool>[];

  @override
  Future<bool> keepWaitingForDeliveries() async {
    calls.add('keepWaitingForDeliveries');
    return keepWaitingAnswers.isEmpty ? true : keepWaitingAnswers.removeAt(0);
  }

  @override
  Future<bool?> showCrashPrompt(
    AppReportsController reports,
    CrashCandidate candidate,
  ) async =>
      false;

  @override
  Future<bool> confirmLauncherInstall(String version,
      {String? whatsNew}) async {
    calls.add('confirmLauncherInstall');
    return launcherInstallAnswer;
  }

  bool launcherInstallAnswer = false;

  @override
  void notifyLauncherUpdate(LauncherUpdateNotice notice, String detail) {}

  bool cancelAnswer = false;

  @override
  Future<bool> confirmCancelDownload() async => cancelAnswer;

  @override
  void notifyNoSyncSelection() => calls.add('noSyncSelection');

  @override
  Future<bool> confirmSemanticConsent() async => false;

  bool? semanticAnswer = false;

  @override
  Future<bool?> askSemanticConsentBeforeUpdate() async {
    calls.add('askSemantic');
    return semanticAnswer;
  }

  @override
  Future<bool> confirmLibraryReindex() async => false;

  int personalAsks = 0;
  bool? personalAnswer;
  int personalModeConfirms = 0;
  bool personalModeConfirm = true;

  @override
  Future<bool> confirmPersonalMode() async {
    personalModeConfirms++;
    return personalModeConfirm;
  }

  @override
  Future<bool?> askPersonalScope() async {
    personalAsks++;
    return personalAnswer;
  }

  @override
  Future<void> uploadReports({
    required bool Function() isCancelled,
    required void Function(bool active) onActiveChanged,
    required void Function(bool uploading) onUploadingChanged,
  }) async {
    calls.add('uploadReports');
    // כמו `uploadAllReports`: הסימון נדלק לפני כל await.
    onActiveChanged(true);
    try {
      await uploadGate?.future;
    } finally {
      onActiveChanged(false);
    }
  }

  Completer<void>? uploadGate;
}

class _RecordingStartupSession extends AppSession {
  _RecordingStartupSession({
    required super.dataDir,
    required super.stateDir,
    required super.settings,
    required super.prompts,
    super.runningLocator,
    super.noticesStore,
  });

  final checks = <String>[];

  @override
  Future<void> checkAll() async => checks.add('local');

  @override
  Future<void> checkOnline() async => checks.add('online');
}

/// "בדוק עכשיו" בלי בדיקות אמיתיות: המקומית לא נוגעת בדבר, והמקוונת נכשלת
/// כמו במחשב לא מחובר.
class _OfflineCheckSession extends AppSession {
  _OfflineCheckSession({
    required super.dataDir,
    required super.stateDir,
    required super.settings,
    required super.prompts,
    super.runningLocator,
    super.noticesStore,
  });

  @override
  Future<void> checkAll() async {}

  @override
  Future<void> checkOnline() async {
    library
      ..onlineCheckedAt = DateTime.now()
      ..onlineCheckError = 'offline';
  }
}

/// "ההפעלה נכשלה" — בלי להפעיל את אוצריא האמיתית של מי שמריץ את הבדיקה.
class _FailingLauncher extends OtzariaLauncher {
  const _FailingLauncher();

  @override
  Future<void> launch(String launchPath, {String? withUri}) async =>
      throw OtzariaUserError('הפעלה מדומה שנכשלה');
}

class _TrackedSettings extends SettingsController {
  _TrackedSettings({required super.dataDir});

  Future<void> pending = Future<void>.value();

  @override
  Future<void> update(AppSettings next) => pending = super.update(next);
}

class _QuietOtzaria extends OtzariaManager {
  _QuietOtzaria(String dir) : super(dataDir: dir);

  @override
  Future<void> downloadToMirror({
    OtzariaChannelReleases? online,
    void Function(int received, int total)? onProgress,
    void Function(OtzariaReleaseChannel channel)? onChannel,
    bool Function()? isCancelled,
  }) async {
    await downloadGate?.future;
  }

  /// מחסום: הורדת המתקין ממתינה לו.
  Completer<void>? downloadGate;

  /// מחסום לבדיקה המקוונת; בלעדיו — כאילו אין רשת.
  Completer<void>? peekGate;

  @override
  Future<OtzariaChannelReleases> peekOnlineChannels() async {
    await peekGate?.future;
    throw const SocketException('no network');
  }

  @override
  Future<int?> mirroredReadableDbSchema() async => 1;
}

class _ScriptedLibrary extends LibraryManager {
  _ScriptedLibrary(String dir) : super(dataDir: dir, environment: const {});

  /// מחסום: ההורדה ממתינה לו — כדי להחזיק אותה פתוחה בזמן פעולה אחרת.
  Completer<void>? downloadGate;
  int downloadCalls = 0;

  /// מה שהמוריד האמיתי זרק; `null` = ההורדה מצליחה.
  Object? error;
  int checkCalls = 0;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async {
    checkCalls++;
    return LibraryUpdateCheckResult(
      dbPath: p.join(dataDir, 'library', 'seforim.db'),
    );
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
    downloadCalls++;
    await downloadGate?.future;
    if (error case final failure?) throw failure;
    return const MirrorDownloadOutcome();
  }
}

const _storeRelease = StoreAppRelease(
  tagName: 'v6',
  version: 6,
  assetName: 'store.exe',
  downloadUrl: 'https://example.invalid/store.exe',
  sizeBytes: 1,
);

/// מסירה שמצליחה (או נכשלת / זורקת) כשהבדיקה משחררת את המחסום של התוסף —
/// בלי תהליך ובלי קובץ.
class _GatedDeliveries extends PluginsManager {
  _GatedDeliveries(String dir)
      : super(resolveMirrorDir: () async => p.join(dir, 'mirror'));

  final delivered = <String>[];
  final gates = <String, Completer<void>>{};
  final failing = <String>{};
  final throwing = <String>{};

  @override
  Future<PluginInstallResult> directInstall(
    StorePlugin plugin, {
    String? appVersion,
    void Function(StorePlugin updated)? onPluginUpdated,
  }) async {
    delivered.add(plugin.id);
    await gates[plugin.id]?.future;
    if (throwing.contains(plugin.id)) {
      throw const FileSystemException('הקובץ נעול');
    }
    if (failing.contains(plugin.id)) {
      return const PluginInstallResult.failure('אוצריא לא נפתחה');
    }
    return const PluginInstallResult.ok();
  }
}

class _CountingPlugins extends PluginsManager {
  _CountingPlugins(String dir)
      : super(resolveMirrorDir: () async => p.join(dir, 'mirror'));

  int syncCalls = 0;
  int storeAppCalls = 0;

  /// מחסום: הסנכרון ממתין לו, כדי לקבוע מה הסתיים קודם.
  Completer<void>? syncGate;
  PluginSyncOutcome outcome = const PluginSyncOutcome(
    catalog: PluginCatalog.empty,
    fetched: 0,
    skipped: 0,
  );

  @override
  Future<PluginSyncOutcome> sync({
    List<String> appVersions = const [],
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    syncCalls++;
    await syncGate?.future;
    return outcome;
  }

  // הבדיקה הקלה מראה גם אחרי הרענון שיש תוספים וגרסה חדשה של החנות.
  @override
  Future<PluginsOnlineStatus> peekOnlineUpdates({
    List<String> appVersions = const [],
  }) async =>
      const PluginsOnlineStatus(updatedPlugins: ['a'], totalOnline: 1);

  @override
  Future<StoreAppRelease?> peekStoreApp() async => _storeRelease;

  @override
  Future<MirroredStoreApp> syncStoreApp(
    StoreAppRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    storeAppCalls++;
    throw StateError('store app download stubbed');
  }
}

class _Engines {
  _Engines(String dir)
      : otzaria = _QuietOtzaria(dir),
        library = _ScriptedLibrary(dir),
        plugins = _CountingPlugins(dir);

  final _QuietOtzaria otzaria;
  final _ScriptedLibrary library;
  final _CountingPlugins plugins;
}
