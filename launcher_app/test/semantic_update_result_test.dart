import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;

import 'test_support.dart';

/// מדמה את התוצאה אחרי רענון: כשל התקנה אינו תלוי בכך שהבדיקה מציעה שוב.
class _SemanticUpdateManager extends LibraryManager {
  _SemanticUpdateManager(String directory, {required this.fail})
      : super(dataDir: directory, environment: const {});

  final bool fail;
  bool installed = false;

  @override
  Future<LibraryUpdateCheckResult> checkForUpdate() async =>
      LibraryUpdateCheckResult(
        dbPath: p.join(dataDir, 'books', 'seforim.db'),
        semanticPending: !installed,
        semanticConsentGranted: true,
      );

  @override
  Future<ExternalUpdateNoticeData?> pendingReindexRequest(
          {String? dbPath}) async =>
      null;

  @override
  Future<Set<int>> applyUpdate(
    LibraryUpdateCheckResult check, {
    void Function(LibraryApplyProgress progress)? onProgress,
    void Function(String assetName, Object error)? onCompanionWarning,
    void Function(Object error)? onStateWarning,
    void Function(String dbPath)? onLibraryLocationNotSet,
    bool Function()? isCancelled,
    bool useFullDownloadFallback = false,
  }) async {
    // גם בדיקה שהתעדכנה בינתיים ל"מעודכן" אינה מבטלת כשל שדווח בהחלה.
    installed = true;
    if (fail) {
      onCompanionWarning?.call(
        AppL10n.strings.libraryDomain.companionSemanticName,
        const FileSystemException('semantic engine install failed'),
      );
    }
    return {};
  }
}

void main() {
  late Directory temporary;
  late LibraryModuleController controller;

  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('semantic-update-result-');
    AppLogger.resetForTest();
    await AppLogger.init(temporary.path);
  });

  tearDown(() async {
    controller.dispose();
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  test(
      'successful semantic installation finishes ready without another required action',
      () async {
    controller = LibraryModuleController(
      dataDir: temporary.path,
      manager: _SemanticUpdateManager(temporary.path, fail: false),
    );
    await controller.checkForUpdate();
    expect(controller.status, LibraryModuleStatus.updateAvailable);
    await controller.update();
    expect(controller.status, LibraryModuleStatus.upToDate);
    expect(controller.semanticPending, false);
    expect(controller.semanticConsentRequired, false);
    expect(controller.errorMessage, isNull);
    expect(controller.hasPendingReindex, false);
  });

  test(
      'failed semantic install stays an error even when a later check reports ready',
      () async {
    controller = LibraryModuleController(
      dataDir: temporary.path,
      manager: _SemanticUpdateManager(temporary.path, fail: true),
    );
    await controller.checkForUpdate();
    await controller.update();
    expect(controller.status, LibraryModuleStatus.error);
    expect(
        controller.errorMessage,
        contains(
          AppL10n.strings.libraryDomain.companionSemanticName,
        ));
    expect(controller.canRetryWithFullDownload, false);
  });
}
