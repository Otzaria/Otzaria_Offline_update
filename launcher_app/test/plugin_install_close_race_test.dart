import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:plugins_manager/plugins_manager.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plugin-close-race-');
    await AppLogger.init(dir.path);
  });

  tearDown(() async {
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await dir.delete(recursive: true);
  });

  test('closing Otzaria settles from the version written before process exit',
      () async {
    final manager = _ClosingManager();
    final controller = PluginsModuleController(
      mirrorRootDir: dir.path,
      manager: manager,
      installWatchInterval: const Duration(days: 1),
      installWatchTimeout: Duration.zero,
      isOtzariaRunning: () async {
        manager.version = '1.2.0';
        return false;
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    final completed = <String>[];
    final subscription = controller.installCompletions.listen(completed.add);
    addTearDown(subscription.cancel);
    controller.watchForInstall(StorePlugin.fromJson(const {
      'id': 'catalog-id',
      'manifestId': 'manifest-id',
      'name': 'Example',
      'version': '1.2.0',
    }));

    await controller.refreshInstalled();
    await pumpEventQueue();

    expect(controller.installed['manifest-id'], '1.2.0');
    expect(controller.isAwaitingInstall, isFalse);
    expect(completed, ['Example']);
  });

  test('crossing the initial deadline during a scan keeps watching Otzaria',
      () async {
    final manager = _ClosingManager();
    final controller = PluginsModuleController(
      mirrorRootDir: dir.path,
      manager: manager,
      installWatchInterval: const Duration(days: 1),
      installWatchTimeout: const Duration(milliseconds: 40),
      isOtzariaRunning: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.load();
    manager.beforeScan =
        () => Future<void>.delayed(const Duration(milliseconds: 80));
    controller.watchForInstall(StorePlugin.fromJson(const {
      'id': 'catalog-id',
      'manifestId': 'manifest-id',
      'name': 'Example',
      'version': '1.2.0',
    }));

    await controller.refreshInstalled();

    expect(controller.isInInstallWindow, isFalse);
    expect(controller.isAwaitingInstall, isTrue);
    expect(controller.installed['manifest-id'], '1.0.0');
  });

  test('disposing during app version refresh prevents a native plugin scan',
      () async {
    final manager = _ClosingManager();
    final versionStarted = Completer<void>();
    final version = Completer<String?>();
    var waitForVersion = false;
    final controller = PluginsModuleController(
      mirrorRootDir: dir.path,
      manager: manager,
      installedAppVersion: () async {
        if (!waitForVersion) return null;
        versionStarted.complete();
        return version.future;
      },
    );
    await controller.load();
    waitForVersion = true;
    final refreshing = controller.refreshInstalled();
    await versionStarted.future;

    controller.dispose();
    version.complete('0.9.99');
    await refreshing;

    expect(manager.scans, 0);
  });
}

class _ClosingManager extends PluginsManager {
  _ClosingManager() : super(resolveMirrorDir: () async => '');

  String version = '1.0.0';
  int scans = 0;
  Future<void> Function()? beforeScan;

  @override
  Future<PluginStoreView> load() async => PluginStoreView(
        catalog: const PluginCatalog(plugins: []),
        installed: {'manifest-id': version},
        pluginsDir: '',
      );

  @override
  Future<InstalledPluginsState> scanInstalled() async {
    scans++;
    await beforeScan?.call();
    return InstalledPluginsState(versions: {'manifest-id': version});
  }

  @override
  Future<MirroredStoreApp?> loadStoreApp() async => null;
}
