import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:plugins_manager/plugins_manager.dart';

import 'test_support.dart';

class _FailingOtzariaManager extends OtzariaManager {
  _FailingOtzariaManager(String directory, this.error)
      : super(dataDir: directory);

  final Object error;

  @override
  Future<void> downloadToMirror({
    OtzariaChannelReleases? online,
    void Function(int received, int total)? onProgress,
    void Function(OtzariaReleaseChannel channel)? onChannel,
    bool Function()? isCancelled,
  }) async =>
      throw error;
}

class _StoreAppFailingManager extends PluginsManager {
  _StoreAppFailingManager(String dir, this.error)
      : super(resolveMirrorDir: () async => dir);

  final Object error;

  @override
  Future<MirroredStoreApp> syncStoreApp(
    StoreAppRelease release, {
    void Function(int received, int total)? onProgress,
  }) async =>
      throw error;
}

FileSystemException _diskFull() => FileSystemException(
      'Writing failed',
      r'E:\mirror\store-app\x',
      OSError('', Platform.isWindows ? 112 : 28),
    );

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('storage-full-more-');
    AppLogger.resetForTest();
    await AppLogger.init(temporary.path);
  });

  tearDown(() async {
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  test('הורדת אוצריא: כונן מלא נשמר כסיבה, וכשל אחר לא', () async {
    final full = OtzariaModuleController(
      dataDir: temporary.path,
      manager: _FailingOtzariaManager(temporary.path, _diskFull()),
    );
    addTearDown(full.dispose);
    await full.download();
    expect(full.downloadStatus, OtzariaDownloadStatus.error);
    expect(full.downloadStorageFull, isTrue);
    expect(full.downloadCause, isA<FileSystemException>());

    final other = OtzariaModuleController(
      dataDir: temporary.path,
      manager: _FailingOtzariaManager(temporary.path, StateError('boom')),
    );
    addTearDown(other.dispose);
    await other.download();
    expect(other.downloadStorageFull, isFalse);
  });

  group('תוכנת החנות', () {
    const release = StoreAppRelease(
      tagName: 'v6',
      version: 6,
      assetName: 'store.exe',
      downloadUrl: 'https://example.invalid/store.exe',
      sizeBytes: 1,
    );

    PluginsModuleController build(Object error) {
      final c = PluginsModuleController(
        mirrorRootDir: temporary.path,
        manager: _StoreAppFailingManager(temporary.path, error),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('כתיבה שנכשלה בקוד "הכונן מלא" קובעת את הסיבה ואת הכשל', () async {
      final c = build(_diskFull())..storeAppOnline = release;
      await c.syncStoreApp();
      expect(c.storeAppCause, isA<FileSystemException>());
      expect(c.storageFull, isTrue);
      expect(c.lastSyncFailed, isTrue);
      expect(c.storageFailure?.dir, r'E:\mirror\store-app');
    });

    test('כשל אחר בתוכנת החנות נשאר שקט', () async {
      final c = build(StateError('boom'))..storeAppOnline = release;
      await c.syncStoreApp();
      expect(c.storeAppCause, isNull);
      expect(c.storageFull, isFalse);
      expect(c.lastSyncFailed, isFalse);
    });

    test('הרצה חדשה מאפסת את הסיבות של הקודמת', () async {
      final c = build(_diskFull())
        ..storeAppOnline = release
        ..syncCause = const StorageFullException();
      await c.syncStoreApp();
      expect(c.syncCause, isNull);
      expect(c.storeAppCause, isNotNull);

      c.storeAppOnline = null;
      await c.syncStoreApp();
      expect(c.storeAppCause, isNull);
      expect(c.storageFull, isFalse);
    });
  });
}
