import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/shell_module_ports.dart';
import 'package:launcher_app/src/flows/update_here_flow.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/shell/home_guidance.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:library_manager/library_manager.dart' show CompanionAsset;
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import 'test_support.dart';

void main() {
  late Directory tempDir;
  late OtzariaModuleController otzaria;
  late LibraryModuleController library;
  late PluginsModuleController plugins;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shell-ports-');
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
    otzaria = OtzariaModuleController(
      dataDir: tempDir.path,
      runningLocator: const _NeverRunningLocator(),
    );
    library = LibraryModuleController(dataDir: tempDir.path);
    plugins =
        PluginsModuleController(mirrorRootDir: p.join(tempDir.path, 'mirror'));
  });

  tearDown(() async {
    otzaria.dispose();
    library.dispose();
    plugins.dispose();
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  for (final installedPlugin in ['1.0.0', '1.5.0']) {
    test(
        'app update selects the newly compatible plugin build '
        '(installed $installedPlugin)', () async {
      final app = _UpdatedApp(tempDir.path)
        ..currentVersion = '0.9.96'
        ..latestVersion = '0.9.97'
        ..status = OtzariaModuleStatus.updateAvailable;
      final store = _DeliveredPlugins(tempDir.path, app)
        ..appVersion = '0.9.96'
        ..status = PluginsModuleStatus.ready
        ..plugins = [_versionedPlugin()]
        ..installed = {'test': installedPlugin};
      final host = _UpdateHost();
      addTearDown(app.dispose);
      addTearDown(store.dispose);
      addTearDown(host.tasks.dispose);
      final flow = UpdateHereFlow(
        app: OtzariaModulePort(app),
        library: LibraryModulePort(library),
        plugins: PluginsModulePort(store),
        host: host,
      );

      await flow.run(const [GuidanceItem.app, GuidanceItem.plugins]);

      expect(app.currentVersion, '0.9.97');
      expect(store.delivered, ['2.0.0']);
      expect((host.tasks.current! as UpdateHereTask).outcomes,
          containsPair(GuidanceItem.plugins, StageOutcome.done));
    });
  }

  test('app-only install refreshes dependent state without installing it',
      () async {
    final app = _UpdatedApp(tempDir.path)
      ..currentVersion = '0.9.96'
      ..latestVersion = '0.9.97'
      ..status = OtzariaModuleStatus.updateAvailable;
    final store = _DeliveredPlugins(tempDir.path, app)
      ..appVersion = '0.9.96'
      ..status = PluginsModuleStatus.ready
      ..plugins = [_versionedPlugin()]
      ..installed = {'test': '1.5.0'};
    final dependentLibrary = _RecheckedLibrary(tempDir.path)
      ..status = LibraryModuleStatus.error;
    final host = _UpdateHost();
    addTearDown(app.dispose);
    addTearDown(store.dispose);
    addTearDown(dependentLibrary.dispose);
    addTearDown(host.tasks.dispose);
    final refreshed = Completer<void>();
    var finished = false;
    final flow = UpdateHereFlow(
      app: OtzariaModulePort(app, onInstalled: () async {
        await refreshed.future;
        await dependentLibrary.checkForUpdate(fresh: true);
        await store.refreshAppVersion();
      }),
      library: LibraryModulePort(dependentLibrary),
      plugins: PluginsModulePort(store),
      host: host,
    );
    final run =
        flow.run(const [GuidanceItem.app]).whenComplete(() => finished = true);
    await pumpEventQueue();
    expect(finished, isFalse);
    refreshed.complete();
    await run;

    expect(store.appVersion, '0.9.97');
    expect(store.deliverableUpdates, hasLength(1));
    expect(dependentLibrary.status, LibraryModuleStatus.updateAvailable);
    expect(dependentLibrary.freshChecks, 1);
    expect(dependentLibrary.lastApplyCompleted, isFalse);
    expect(store.delivered, isEmpty);
    expect((host.tasks.current! as UpdateHereTask).stages, [GuidanceItem.app]);
  });

  for (final result in [
    OtzariaInstallResult.cancelled,
    OtzariaInstallResult.wizardStillOpen,
    OtzariaInstallResult.failed,
  ]) {
    test('unsuccessful app install does not refresh dependents ($result)',
        () async {
      final app = _UpdatedApp(tempDir.path)..result = result;
      addTearDown(app.dispose);
      var refreshed = false;
      final port =
          OtzariaModulePort(app, onInstalled: () async => refreshed = true);
      expect(
          await port.installWithWizard(), isNot(AppInstallOutcome.installed));
      expect(refreshed, isFalse);
    });
  }

  test('the app port installs only an installed app with an update', () {
    final port = OtzariaModulePort(otzaria);

    otzaria
      ..currentVersion = null
      ..status = OtzariaModuleStatus.updateAvailable;
    expect(port.isInstalled, isFalse);
    expect(port.hasUpdateAvailable, isTrue);

    otzaria
      ..currentVersion = '1.0.0'
      ..status = OtzariaModuleStatus.upToDate;
    expect(port.isInstalled, isTrue);
    expect(port.hasUpdateAvailable, isFalse);
  });

  test('the app port reads the online check and the download error', () {
    final port = OtzariaModulePort(otzaria);
    final at = DateTime(2026, 10, 11);
    otzaria
      ..onlineCheckedAt = at
      ..onlineCheckError = 'offline'
      ..hasStaleFullPackage = true
      ..downloadError = 'boom';

    expect(port.onlineProof.checkedAt, at);
    expect(port.onlineProof.error, 'offline');
    expect(port.onlineProof.hasUpdate, otzaria.hasOnlineUpdate);
    expect(port.hasStaleFullPackage, isTrue);
    expect(port.downloadFailed, isTrue);

    otzaria.downloadError = null;
    expect(port.downloadFailed, isFalse);
  });

  test('the library port auto-updates only an existing database', () {
    final port = LibraryModulePort(library);

    library
      ..isFreshInstall = true
      ..status = LibraryModuleStatus.updateAvailable;
    expect(port.isFreshInstall, isTrue);
    expect(port.hasUpdateAvailable, isTrue);

    library
      ..isFreshInstall = false
      ..status = LibraryModuleStatus.updating;
    expect(port.isFreshInstall, isFalse);
    expect(port.hasUpdateAvailable, isFalse);
  });

  test('the library proof ignores the smart-search answers', () {
    final port = LibraryModulePort(library);
    library
      ..semanticPreference = SemanticDownloadPreference.always
      ..onlineCheckedAt = DateTime.now()
      ..onlineCheckError = null
      ..onlineCompanionsCheckError = null
      ..onlineSemanticPending = true
      ..onlineSemanticCheckError = 'semantic offline';

    expect(library.hasOnlineUpdate, isTrue);
    expect(library.onlineProofError, isNotNull);
    expect(port.libraryOnlineProof.provenUpToDate, isTrue);

    library.onlineCompanionsCheckError = 'companions offline';
    expect(port.libraryOnlineProof.error, 'companions offline');
    expect(port.libraryOnlineProof.provenUpToDate, isFalse);
  });

  test('a companion that failed is hidden from the home, not proven', () {
    final port = LibraryModulePort(library);
    library
      ..onlineCheckedAt = DateTime.now()
      ..onlinePendingCompanions = {CompanionAsset.talmud}
      ..failedCompanions = {CompanionAsset.talmud};

    expect(library.hasOnlineUpdate, isFalse);
    expect(port.libraryOnlineProof.provenUpToDate, isFalse);
  });

  test('"never" then "always" within the check age still downloads', () {
    final port = LibraryModulePort(library);
    library
      ..semanticPreference = SemanticDownloadPreference.never
      ..onlineCheckedAt = DateTime.now()
      ..semanticChecked = false;
    expect(port.libraryOnlineProof.provenUpToDate, isTrue);

    library.semanticPreference = SemanticDownloadPreference.always;
    expect(port.shouldOfferSemanticDownload, isTrue);

    // גם אחרי שחזור התשובות (ביטול הורדה) ה"לא נבדק" נשמר — והספרייה רצה.
    final answers = library.onlineAnswers;
    library.semanticChecked = true;
    library.restoreOnlineAnswers(answers);
    expect(port.shouldOfferSemanticDownload, isTrue);
    expect(
      DownloadPlan.shouldSkipLibrary(
        const AppSettings(semanticDownload: SemanticDownloadPreference.always),
        includeSemanticSearch: port.shouldOfferSemanticDownload,
        personalUpdateMode: false,
        online: port.libraryOnlineProof,
      ),
      isFalse,
    );
  });

  test('the library port reports failures and retries', () {
    final port = LibraryModulePort(library);
    expect(port.downloadFailed, isFalse);
    expect(port.downloadNeedsRetry, isFalse);

    library.downloadError = 'boom';
    expect(port.downloadFailed, isTrue);
    expect(port.downloadNeedsRetry, isTrue);
  });

  test(
      'a raw error after a completed apply is not a note on the success screen',
      () async {
    final applied = _AppliedLibrary(tempDir.path);
    addTearDown(applied.dispose);
    final port = LibraryModulePort(applied);

    // checkForUpdate שאחרי ההחלה זרק — ההודעה גולמית, והמסד כבר הוחלף.
    applied.after = (l) => l.errorMessage = 'SqliteException(5): locked';
    expect(await port.apply(), LibraryApplyResult.applied);
    expect(port.applyNote, isNull);

    applied.after = (l) => l
      ..errorMessage = 'כוונו את אוצריא לספרייה'
      ..applyNote = 'כוונו את אוצריא לספרייה';
    expect(await port.apply(), LibraryApplyResult.appliedWithNote);
    expect(port.applyNote, 'כוונו את אוצריא לספרייה');
  });

  test('the plugins port keeps the catalog and store-app checks apart', () {
    final port = PluginsModulePort(plugins);
    final catalogAt = DateTime(2026, 10, 1);
    final storeAt = DateTime(2026, 10, 2);
    plugins
      ..onlineCheckedAt = catalogAt
      ..onlineCheckError = 'catalog offline'
      ..storeAppCheckedAt = storeAt
      ..storeAppCheckError = null
      ..storeAppOnline = const StoreAppRelease(
        tagName: 'v6',
        version: 6,
        assetName: 'store-v6.zip',
        downloadUrl: 'https://example.invalid/store-v6.zip',
        sizeBytes: 1,
      );

    expect(port.catalogOnlineProof.checkedAt, catalogAt);
    expect(port.catalogOnlineProof.error, 'catalog offline');
    expect(port.catalogOnlineProof.hasUpdate, isFalse);
    expect(port.storeAppOnlineProof.checkedAt, storeAt);
    expect(port.storeAppOnlineProof.error, isNull);
    expect(port.storeAppOnlineProof.hasUpdate, isTrue);
    expect(port.lastSyncFailed, plugins.lastSyncFailed);
  });
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}

/// החלה שהגיעה לסופה, ו-[after] קובע מה נשאר אחריה.
class _AppliedLibrary extends LibraryModuleController {
  _AppliedLibrary(String dataDir) : super(dataDir: dataDir);

  void Function(LibraryModuleController library) after = (_) {};

  @override
  Future<void> update() async {
    lastApplyCompleted = true;
    errorMessage = applyNote = null;
    after(this);
  }
}

class _UpdatedApp extends OtzariaModuleController {
  _UpdatedApp(String dir) : super(dataDir: dir);

  OtzariaInstallResult result = OtzariaInstallResult.installed;

  @override
  Future<void> install({bool useWizard = true}) async {
    if (result == OtzariaInstallResult.installed) {
      currentVersion = '0.9.97';
      status = OtzariaModuleStatus.upToDate;
    }
    lastInstallResult = result;
  }
}

class _DeliveredPlugins extends PluginsModuleController {
  _DeliveredPlugins(String dir, _UpdatedApp app)
      : super(
            mirrorRootDir: dir,
            installedAppVersion: () async => app.currentVersion);

  final delivered = <String>[];

  @override
  Future<PluginInstallResult> directInstall(StorePlugin plugin) async {
    delivered.add(versionOf(plugin));
    return const PluginInstallResult.ok();
  }
}

class _UpdateHost implements UpdateHereHost {
  @override
  final tasks = ShellTasks();

  @override
  bool get isActive => true;

  @override
  Future<bool> isOtzariaRunning() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected update call: ${invocation.memberName}');
}

StorePlugin _versionedPlugin() => StorePlugin.fromApi(const {
      'id': 'test',
      'name': 'test',
      'version': '2.0.0',
      'compatibleWith': '0.9.97',
      'supportsDirectInstall': true,
      'versions': [
        {
          'version': '2.0.0',
          'compatibleWith': '0.9.97',
          'supportsDirectInstall': true,
          'downloadUrl': '/new',
          'isLatest': true,
        },
        {
          'version': '1.5.0',
          'compatibleWith': '0.9.95',
          'supportsDirectInstall': true,
          'downloadUrl': '/old',
        },
      ],
    }, 'https://otzaria.org')
        .copyWith(
      manifestId: 'test',
      localFiles: {
        for (final v in ['2.0.0', '1.5.0'])
          v: PluginLocalFile(
            relativePath: 'files/$v.otzplugin',
            fileName: '$v.otzplugin',
            ext: '.otzplugin',
            size: 1,
          ),
      },
    );

class _RecheckedLibrary extends LibraryModuleController {
  _RecheckedLibrary(String dir) : super(dataDir: dir);

  int freshChecks = 0;

  @override
  Future<void> checkForUpdate({bool fresh = false}) async {
    if (fresh) freshChecks++;
    status = LibraryModuleStatus.updateAvailable;
  }
}
