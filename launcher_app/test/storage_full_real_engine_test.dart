// החריגים הם מה שהמוריד האמיתי של upstream מייצר (כשל כתיבה תחת IOOverrides
// ו-StateError של בדיקת המקום), לא טיפוס נוח שהבדיקה בוחרת.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/storage_failure.dart';
import 'package:launcher_app/src/shell/download_failure.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadException;

import 'storage_real_engine_support.dart';
import 'test_support.dart';

class _ThrowingManager extends LibraryManager {
  _ThrowingManager(String directory, this.error)
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
  LibraryModuleController? controller;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('real-engine-');
    AppLogger.resetForTest();
    await AppLogger.init(temporary.path);
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  Future<LibraryModuleController> download(Object error) async {
    final c = controller = LibraryModuleController(
      dataDir: temporary.path,
      manager: _ThrowingManager(temporary.path, error),
    );
    await c.download();
    return c;
  }

  test('המוריד האמיתי: כתיבה שנכשלת ב"כונן מלא" מזוהה ומסווגת diskSpace',
      () async {
    final error = await realDownloadFailure(temporary, diskFullErrno);
    // אם upstream ישנה את הצורה, הבדיקה הזו אומרת מה הוא זורק עכשיו.
    expect(error, isA<PatchDownloadException>(), reason: '$error');
    expect(findStorageFull(error), isNotNull, reason: '$error');

    final c = await download(error);
    expect(c.downloadStatus, MirrorDownloadStatus.error);
    expect(c.downloadStorageFull, isTrue);

    final failure = classifyDownloadFailure(
      failed: const [MirrorComponent.library],
      errors: {MirrorComponent.library: c.downloadError},
      causes: {MirrorComponent.library: c.downloadCause},
      shabbat: false,
    );
    expect(failure.kind, DownloadFailureKind.diskSpace);
    expect(failure.needed, isNull);
  });

  test('המוריד האמיתי: "גישה נדחתה" אינה חוסר מקום', () async {
    final error = await realDownloadFailure(temporary, accessDeniedErrno);
    expect(findStorageFull(error), isNull, reason: '$error');
    final c = await download(error);
    expect(c.downloadStorageFull, isFalse);
    final failure = classifyDownloadFailure(
      failed: const [MirrorComponent.library],
      errors: {MirrorComponent.library: c.downloadError},
      causes: {MirrorComponent.library: c.downloadCause},
      shabbat: false,
    );
    expect(failure.kind, isNot(DownloadFailureKind.diskSpace));
  });

  test('בדיקת המקום של upstream (StateError) עוצרת ומציגה נדרש ופנוי',
      () async {
    final text = AppL10n.strings.libraryDomain
        .mirrorNotEnoughDiskSpace('E:', '2 GB', '1 GB');
    final c = await download(StateError(text));
    expect(c.downloadStorageFull, isTrue);
    final failure = classifyDownloadFailure(
      failed: const [MirrorComponent.library],
      errors: {MirrorComponent.library: c.downloadError},
      causes: {MirrorComponent.library: c.downloadCause},
      shabbat: false,
    );
    expect(failure.kind, DownloadFailureKind.diskSpace);
    expect(failure.needed, '2 GB');
    expect(failure.free, '1 GB');
  });

  test('אזהרת קובץ נלווה של כונן מלא הופכת לכשל, לא נבלעת', () async {
    final warned = _WarningManager(
      temporary.path,
      PatchDownloadException(
        'save failed: ${FileSystemException('w', r'E:\x', OSError('', diskFullErrno))}',
      ),
    );
    final c = controller = LibraryModuleController(
      dataDir: temporary.path,
      manager: warned,
    );
    await c.download();
    expect(c.downloadStatus, MirrorDownloadStatus.error);
    expect(c.downloadStorageFull, isTrue);
  });

  test('כשל אחר אינו כונן מלא', () async {
    final c = await download(StateError('boom'));
    expect(c.downloadStorageFull, isFalse);
  });
}

class _WarningManager extends _ThrowingManager {
  _WarningManager(super.directory, super.error);

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
    onCompanionWarning?.call('semantic', error);
    return const MirrorDownloadOutcome();
  }
}
