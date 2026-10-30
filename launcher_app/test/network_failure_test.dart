import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:launcher_app/src/controllers/download_plan.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/shell/download_failure.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_downloads/otzaria_downloads.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

void main() {
  LibraryHttpException response(int status) =>
      LibraryHttpException.fromResponse(
        http.Response('blocked by filter', status, headers: {
          'server': 'filter-proxy',
          'set-cookie': 'private-cookie',
        }),
        uri: Uri.parse('https://github.com/m.json?token=private-query'),
        message: 'HTTP $status',
      );

  test('a typed filter block is classified even without an error string', () {
    final cause = NetworkBlockedException(
      uri: Uri.parse('https://github.com/file'),
      statusCode: 418,
    );
    final failure = classifyDownloadFailure(
      failed: const [MirrorComponent.library],
      errors: const {},
      causes: {MirrorComponent.library: cause},
      shabbat: false,
    );
    expect(failure.kind, DownloadFailureKind.blocked);
  });

  test('library 418 is a block; unrelated 403, 429 and 503 are not', () {
    for (final status in [418, 403, 429, 503]) {
      final cause = response(status);
      final failure = classifyDownloadFailure(
        failed: const [MirrorComponent.library],
        errors: {MirrorComponent.library: '$cause'},
        causes: {MirrorComponent.library: cause},
        shabbat: false,
      );
      expect(
          failure.kind,
          status == 418
              ? DownloadFailureKind.blocked
              : DownloadFailureKind.other);
    }
  });

  test('a typed certificate rejection is classified without string guessing',
      () {
    final failure = classifyDownloadFailure(
      failed: const [MirrorComponent.app],
      errors: const {},
      causes: {
        MirrorComponent.app: NetworkCertificateException(
          uri: Uri.parse('https://github.com/file'),
          cause: const HandshakeException('untrusted'),
        ),
      },
      shabbat: false,
    );
    expect(failure.kind, DownloadFailureKind.blocked);
  });

  test('HTTP diagnostics reach the log without cookies or query credentials',
      () async {
    final dir = await Directory.systemTemp.createTemp('http-failure-log-');
    final logger = await AppLogger.init(dir.path);
    addTearDown(() async {
      await logger.flush();
      AppLogger.resetForTest();
      await dir.delete(recursive: true);
    });
    logger.error('download failed', response(418));
    await logger.flush();
    final log = await File(logger.filePath).readAsString();
    expect(log, contains('"statusCode":418'));
    expect(log, contains('"uri":"https://github.com/m.json"'));
    expect(log, contains('filter-proxy'));
    expect(log, contains('blocked by filter'));
    expect(log, isNot(contains('private-cookie')));
    expect(log, isNot(contains('private-query')));
  });

  test('the library controller explains the filter and retains the typed cause',
      () async {
    final dir = await Directory.systemTemp.createTemp('library-filter-');
    final logger = await AppLogger.init(dir.path);
    final previousLanguage = AppL10n.language;
    addTearDown(() async {
      AppL10n.use(previousLanguage);
      await logger.flush();
      AppLogger.resetForTest();
      await dir.delete(recursive: true);
    });
    for (final language in AppLanguage.values) {
      AppL10n.use(language);
      final cause = response(418);
      final controller = LibraryModuleController(
        dataDir: dir.path,
        manager: _BlockedManager(cause),
      );
      await controller.download();
      expect(controller.downloadStatus, MirrorDownloadStatus.error);
      expect(controller.downloadCause, same(cause));
      expect(controller.downloadError,
          AppL10n.strings.appDomain.networkBlockedByFilter(418, 'github.com'));
      expect(
          classifyDownloadFailure(
            failed: const [MirrorComponent.library],
            errors: {MirrorComponent.library: controller.downloadError},
            causes: {MirrorComponent.library: controller.downloadCause},
            shabbat: false,
          ).kind,
          DownloadFailureKind.blocked);
      controller.dispose();
    }
  });
}

class _BlockedManager extends Fake implements LibraryManager {
  _BlockedManager(this.failure);
  final LibraryHttpException failure;

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
      throw failure;

  @override
  void dispose() {}
}
