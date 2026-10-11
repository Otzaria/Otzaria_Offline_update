import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/shell_module_ports.dart';
import 'package:launcher_app/src/services/app_logger.dart';
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

  test('the library port reports failures and retries', () {
    final port = LibraryModulePort(library);
    expect(port.downloadFailed, isFalse);
    expect(port.downloadNeedsRetry, isFalse);

    library.downloadError = 'boom';
    expect(port.downloadFailed, isTrue);
    expect(port.downloadNeedsRetry, isTrue);
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
