import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_support.dart';

class _FailingManager extends LibraryManager {
  _FailingManager(String directory, this.error)
      : super(dataDir: directory, environment: const {});

  final Object error;

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
  }) async =>
      throw error;
}

void main() {
  late Directory temporary;
  late LibraryModuleController controller;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('storage-full-');
    AppLogger.resetForTest();
    await AppLogger.init(temporary.path);
  });

  tearDown(() async {
    controller.dispose();
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  LibraryModuleController build(Object error) =>
      controller = LibraryModuleController(
          dataDir: temporary.path,
          manager: _FailingManager(temporary.path, error));

  test('כונן מלא בהורדת הספרייה נשמר כסיבה מובנית, ולא כ"הורדה שהצליחה"',
      () async {
    build(const StorageFullException(dir: 'E:'));
    await controller.download();
    expect(controller.downloadStatus, MirrorDownloadStatus.error);
    expect(controller.downloadStorageFull, isTrue);
    expect(controller.downloadCause, isA<StorageFullException>());
    expect(controller.downloadError, isNotNull);
  });

  test('FileSystemException גולמי עם קוד "הכונן מלא" מזוהה גם בלי עטיפה',
      () async {
    build(FileSystemException(
      'Writing failed',
      r'E:\mirror\x',
      OSError('', Platform.isWindows ? 112 : 28),
    ));
    await controller.download();
    expect(controller.downloadStorageFull, isTrue);
  });

  test('כשל אחר אינו "כונן מלא"', () async {
    build(StateError('boom'));
    await controller.download();
    expect(controller.downloadStatus, MirrorDownloadStatus.error);
    expect(controller.downloadStorageFull, isFalse);
    expect(controller.downloadCause, isA<StateError>());
  });
}
