import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/cancelled_download_refresh.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/online_check.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/shell_module_ports.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import 'test_support.dart';

void main() {
  late Directory tempDir;
  late OtzariaModuleController otzaria;
  late LibraryModuleController library;
  late PluginsModuleController plugins;

  const tag = '1.0.0';
  final kind = Platform.isMacOS
      ? OtzariaInstallerKind.macAppZip
      : OtzariaInstallerKind.windowsSetupExe;
  final onlineStable = OtzariaRelease(
    tagName: tag,
    name: 'Otzaria $tag',
    isPrerelease: false,
    isDraft: false,
    publishedAt: null,
    installerKind: kind,
    installerAssetName: 'otzaria-$tag.exe',
    installerDownloadUrl: 'https://example.invalid/otzaria-$tag.exe',
    installerSizeBytes: 1,
  );

  String appMirrorDir() => p.join(tempDir.path, 'mirror', 'app');

  void writeAppMirror() {
    const relative = 'installers/$tag/otzaria-$tag.exe';
    final installer =
        File(p.join(appMirrorDir(), p.joinAll(relative.split('/'))))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('installer for $tag');
    File(p.join(appMirrorDir(), 'latest-release.json'))
        .writeAsStringSync(jsonEncode({
      'schemaVersion': 2,
      'syncedAt': '2026-08-01T00:00:00.000Z',
      'stable': {
        'tagName': tag,
        'name': 'Otzaria $tag',
        'isPrerelease': false,
        'isDraft': false,
        'publishedAt': '2026-08-01T00:00:00.000Z',
        'installerKind': kind.name,
        'installerAssetName': 'otzaria-$tag.exe',
        'installerDownloadUrl': 'https://example.invalid/otzaria-$tag.exe',
        'installerSizeBytes': installer.lengthSync(),
        'installerPath': relative,
      },
    }));
  }

  late OnlineAnswersBeforeDownload before;

  const storeAppRelease = StoreAppRelease(
    tagName: 'v6',
    version: 6,
    assetName: 'store-v6.zip',
    downloadUrl: 'https://example.invalid/store-v6.zip',
    sizeBytes: 1,
  );

  void startDownload() {
    before = OnlineAnswersBeforeDownload.capture(
      library: library,
      plugins: plugins,
    );
  }

  Future<void> refresh(MirrorComponent? reverted) =>
      refreshAfterCancelledDownload(
        otzaria: otzaria,
        library: library,
        plugins: plugins,
        before: before,
        reverted: reverted,
      );

  bool cardOffersDownload({
    required DateTime? checkedAt,
    required String? error,
    required bool hasUpdate,
  }) =>
      checkedAt != null && error == null && hasUpdate;

  bool libraryProvenUpToDate() => provenUpToDateOnline(
        checkedAt: library.onlineCheckedAt,
        error: library.onlineProofError,
        hasUpdate: library.hasOnlineUpdate,
      );

  bool pluginsProvenUpToDate() => provenUpToDateOnline(
        checkedAt: plugins.onlineCheckedAt,
        error: plugins.onlineCheckError,
        hasUpdate: plugins.hasCatalogOnlineUpdate,
      );

  bool storeAppProvenUpToDate() => provenUpToDateOnline(
        checkedAt: plugins.storeAppCheckedAt,
        error: plugins.storeAppCheckError,
        hasUpdate: plugins.hasStoreAppOnlineUpdate,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cancel-refresh-');
    HttpOverrides.global = NoNetworkHttpOverrides();
    AppLogger.resetForTest();
    await AppLogger.init(tempDir.path);
    otzaria = OtzariaModuleController(
      dataDir: tempDir.path,
      runningLocator: const _NeverRunningLocator(),
    );
    library = LibraryModuleController(dataDir: tempDir.path);
    plugins =
        PluginsModuleController(mirrorRootDir: p.join(tempDir.path, 'mirror'));
    final fakeDb = File(p.join(tempDir.path, 'library', 'seforim.db'))
      ..parent.createSync(recursive: true)
      ..createSync();
    await library.setCustomDbPath(fakeDb.path);
  });

  tearDown(() async {
    otzaria.dispose();
    library.dispose();
    plugins.dispose();
    HttpOverrides.global = null;
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  test('the refresh runs even when the revert throws', () {
    final source =
        File('lib/src/controllers/shell_module_ports.dart').readAsStringSync();
    final start = source
        .indexOf('Future<void> rollback(MirrorComponent? inProgress) async {');
    final body = source.substring(start);
    final revert = body.indexOf('await _undo.revert(');
    final finallyAt = body.indexOf('finally {', revert);
    final refresh = body.indexOf('refreshAfterCancelledDownload(', finallyAt);

    expect(start, greaterThan(-1));
    expect(body.lastIndexOf('try {', revert), greaterThan(-1));
    expect(finallyAt, greaterThan(revert));
    expect(refresh, greaterThan(finallyAt));
  });

  group('cancel keeps the components that finished', () {
    Future<CancelledDownloadRollback> capture() =>
        CancelledDownloadRollback.capture(
          otzaria: otzaria,
          library: library,
          plugins: plugins,
          mirrorDirs: {
            MirrorComponent.app: [appMirrorDir()],
            MirrorComponent.library: [library.mirrorDir],
            MirrorComponent.plugins: plugins.mirrorDirs,
          },
        );

    File libraryAsset(String name) => File(p.join(library.mirrorDir, name));

    test('during the second component: the first stays, the second reverts',
        () async {
      final earlier = libraryAsset('assets/earlier.bin')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('from an earlier download');
      final rollback = await capture();

      writeAppMirror();
      final partial = libraryAsset('assets/new.bin')..writeAsStringSync('half');
      await rollback.rollback(MirrorComponent.library);

      expect(File(p.join(appMirrorDir(), 'latest-release.json')).existsSync(),
          isTrue);
      expect(partial.existsSync(), isFalse);
      expect(earlier.readAsStringSync(), 'from an earlier download');
      expect(otzaria.stableVersion, tag);
    });

    test('during the first component: the drive is as before', () async {
      final earlier = libraryAsset('assets/earlier.bin')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('from an earlier download');
      final rollback = await capture();

      writeAppMirror();
      await rollback.rollback(MirrorComponent.app);

      expect(Directory(appMirrorDir()).existsSync(), isFalse);
      expect(earlier.readAsStringSync(), 'from an earlier download');
      expect(
          Directory(library.mirrorDir).listSync(recursive: true), hasLength(2));
      expect(otzaria.stableVersion, isNull);
    });
  });

  test('a reverted app download is no longer proven up to date', () async {
    writeAppMirror();
    await otzaria.checkForUpdate();
    otzaria
      ..onlineChannels = OtzariaChannelReleases(stable: onlineStable)
      ..onlineCheckedAt = DateTime.now();
    expect(otzaria.errorMessage, isNull);
    expect(otzaria.stableVersion, tag);
    expect(otzaria.hasOnlineUpdate, isFalse);
    startDownload();

    Directory(appMirrorDir()).deleteSync(recursive: true);
    await refresh(MirrorComponent.app);

    expect(otzaria.stableVersion, isNull);
    expect(otzaria.hasOnlineUpdate, isTrue);
  });

  test('a library proof made during the download is invalidated', () async {
    startDownload();
    library
      ..downloadStatus = MirrorDownloadStatus.done
      ..onlineCheckedAt = DateTime.now();
    expect(libraryProvenUpToDate(), isTrue);

    await refresh(MirrorComponent.library);

    expect(library.onlineCheckedAt, isNull);
    expect(library.onlineCheckError, isNull);
    expect(libraryProvenUpToDate(), isFalse);
  });

  test('a library proof from before the download is kept', () async {
    final checkedBefore = DateTime.now().subtract(const Duration(minutes: 1));
    library
      ..downloadStatus = MirrorDownloadStatus.done
      ..onlineCheckedAt = checkedBefore;
    startDownload();

    await refresh(MirrorComponent.library);

    expect(library.onlineCheckedAt, checkedBefore);
    expect(library.onlineCheckError, isNull);
    expect(libraryProvenUpToDate(), isTrue);
  });

  test('a plugins sync proven during the download is invalidated', () async {
    startDownload();
    plugins
      ..onlineStatus = PluginsOnlineStatus.empty
      ..onlineCheckedAt = DateTime.now();
    expect(pluginsProvenUpToDate(), isTrue);

    await refresh(MirrorComponent.plugins);

    expect(plugins.onlineCheckedAt, isNull);
    expect(plugins.onlineCheckError, isNull);
    expect(pluginsProvenUpToDate(), isFalse);
  });

  test('a store app downloaded during the download is pending again', () async {
    plugins.storeAppOnline = storeAppRelease;
    startDownload();
    plugins
      ..storeAppOnline = null
      ..storeAppCheckedAt = DateTime.now();
    expect(storeAppProvenUpToDate(), isTrue);

    await refresh(MirrorComponent.plugins);

    expect(plugins.storeAppCheckedAt, isNull);
    expect(plugins.storeAppCheckError, isNull);
    expect(plugins.storeAppOnline, same(storeAppRelease));
    expect(storeAppProvenUpToDate(), isFalse);
  });

  test('plugins proofs from before the download are kept', () async {
    final checkedBefore = DateTime.now().subtract(const Duration(minutes: 1));
    plugins
      ..onlineStatus = PluginsOnlineStatus.empty
      ..onlineCheckedAt = checkedBefore
      ..storeAppCheckedAt = checkedBefore;
    startDownload();

    await refresh(MirrorComponent.plugins);

    expect(plugins.onlineCheckedAt, checkedBefore);
    expect(plugins.storeAppCheckedAt, checkedBefore);
    expect(plugins.storeAppOnline, isNull);
    expect(pluginsProvenUpToDate(), isTrue);
    expect(storeAppProvenUpToDate(), isTrue);
  });

  test('a library kept on the drive keeps its answers from the download',
      () async {
    library
      ..onlinePendingCompanions = {CompanionAsset.talmud}
      ..onlineCheckedAt = DateTime.now().subtract(const Duration(minutes: 1));
    plugins.storeAppOnline = storeAppRelease;
    startDownload();

    library
      ..downloadStatus = MirrorDownloadStatus.done
      ..onlinePendingCompanions = const {}
      ..onlineCheckedAt = DateTime.now();
    plugins
      ..storeAppOnline = null
      ..storeAppCheckedAt = DateTime.now();

    await refresh(MirrorComponent.plugins);

    expect(library.onlinePendingCompanions, isEmpty);
    expect(libraryProvenUpToDate(), isTrue);
    expect(plugins.storeAppOnline, same(storeAppRelease));
    expect(storeAppProvenUpToDate(), isFalse);
  });

  test('a cancelled companion-only download offers the download again',
      () async {
    final checkedBefore = DateTime.now().subtract(const Duration(minutes: 1));
    library
      ..onlinePendingCompanions = {CompanionAsset.talmud}
      ..onlineCheckedAt = checkedBefore;
    expect(library.hasOnlineUpdate, isTrue);
    startDownload();

    library
      ..downloadStatus = MirrorDownloadStatus.done
      ..onlinePendingCompanions = const {}
      ..onlineCheckedAt = DateTime.now();
    expect(library.hasOnlineUpdate, isFalse);

    await refresh(MirrorComponent.library);

    expect(library.onlinePendingCompanions, {CompanionAsset.talmud});
    expect(library.hasOnlineUpdate, isTrue);
    expect(libraryProvenUpToDate(), isFalse);
    expect(
      cardOffersDownload(
        checkedAt: library.onlineCheckedAt,
        error: library.onlineCheckError,
        hasUpdate: library.hasOnlineUpdate,
      ),
      isTrue,
    );
  });

  test('a cancelled semantic search download offers the download again',
      () async {
    final checkedBefore = DateTime.now().subtract(const Duration(minutes: 1));
    library
      ..semanticPreference = SemanticDownloadPreference.always
      ..onlineSemanticPending = true
      ..semanticChecked = true
      ..onlineCheckedAt = checkedBefore;
    startDownload();

    library
      ..downloadStatus = MirrorDownloadStatus.done
      ..onlineSemanticPending = false
      ..semanticChecked = false
      ..onlineCheckedAt = DateTime.now();
    expect(library.hasOnlineUpdate, isFalse);

    await refresh(MirrorComponent.library);

    expect(library.onlineSemanticPending, isTrue);
    expect(library.semanticChecked, isTrue);
    expect(library.shouldOfferSemanticDownload, isTrue);
    expect(
      cardOffersDownload(
        checkedAt: library.onlineCheckedAt,
        error: library.onlineCheckError,
        hasUpdate: library.hasOnlineUpdate,
      ),
      isTrue,
    );
  });

  test('a cancelled plugins sync offers the catalog download again', () async {
    final checkedBefore = DateTime.now().subtract(const Duration(minutes: 1));
    const pending = PluginsOnlineStatus(newPlugins: ['p'], totalOnline: 1);
    plugins
      ..onlineStatus = pending
      ..onlineCheckedAt = checkedBefore;
    expect(plugins.hasCatalogOnlineUpdate, isTrue);
    startDownload();

    plugins
      ..onlineStatus = PluginsOnlineStatus.empty
      ..onlineCheckedAt = DateTime.now();
    expect(plugins.hasOnlineUpdate, isFalse);

    await refresh(MirrorComponent.plugins);

    expect(plugins.onlineStatus, same(pending));
    expect(plugins.hasCatalogOnlineUpdate, isTrue);
    expect(pluginsProvenUpToDate(), isFalse);
    expect(
      cardOffersDownload(
        checkedAt: plugins.onlineCheckedAt,
        error: plugins.onlineCheckError,
        hasUpdate: plugins.hasOnlineUpdate,
      ),
      isTrue,
    );
  });
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}
