import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/online_check.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import 'test_support.dart';

class _OutcomeManager extends PluginsManager {
  _OutcomeManager(String dir, this.outcome)
      : super(resolveMirrorDir: () async => dir);

  final PluginSyncOutcome outcome;

  @override
  Future<PluginSyncOutcome> sync({
    List<String> appVersions = const [],
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async =>
      outcome;
}

PluginSyncOutcome _outcome({
  List<String> failed = const [],
  List<String> incompleteMedia = const [],
  StorageFullException? storageFailure,
  bool cancelled = false,
}) =>
    PluginSyncOutcome(
      catalog: PluginCatalog.empty,
      fetched: 1,
      skipped: 0,
      failed: failed,
      incompleteMedia: incompleteMedia,
      storageFailure: storageFailure,
      cancelled: cancelled,
    );

void main() {
  late Directory temporary;
  late PluginsModuleController controller;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('plugins-outcome-');
    AppLogger.resetForTest();
    await AppLogger.init(temporary.path);
  });

  tearDown(() async {
    controller.dispose();
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temporary);
  });

  /// [before] הוא מה שהבדיקה הקלה הוכיחה לפני הסנכרון.
  Future<void> syncWith(
    PluginSyncOutcome outcome, {
    required PluginsOnlineStatus before,
  }) async {
    controller = PluginsModuleController(
      mirrorRootDir: temporary.path,
      manager: _OutcomeManager(temporary.path, outcome),
    )
      ..onlineStatus = before
      ..onlineCheckedAt = DateTime.now();
    await controller.sync(isCancelled: () => outcome.cancelled);
  }

  bool provenUpToDate() => provenUpToDateOnline(
        checkedAt: controller.onlineCheckedAt,
        error: controller.onlineCheckError,
        hasUpdate: controller.hasCatalogOnlineUpdate,
      );

  const hasUpdates = PluginsOnlineStatus(updatedPlugins: ['a'], totalOnline: 1);

  test('סנכרון נקי מאפס את התשובה הישנה של הבדיקה ברשת', () async {
    await syncWith(_outcome(), before: hasUpdates);
    expect(controller.onlineStatus?.hasUpdates, isFalse);
    expect(provenUpToDate(), isTrue);
  });

  for (final (name, outcome) in [
    ('כשל מדיה בלבד', _outcome(incompleteMedia: ['a'])),
    (
      'כשל אחסון',
      _outcome(storageFailure: const StorageFullException(dir: 'E:'))
    ),
    ('תוסף שלא ירד', _outcome(failed: ['a'])),
    ('ביטול', _outcome(cancelled: true)),
  ]) {
    test('$name: התשובה שהייתה "יש עדכונים" נשמרת', () async {
      await syncWith(outcome, before: hasUpdates);
      expect(controller.onlineStatus?.hasUpdates, isTrue);
    });

    test('$name: הוכחת "אין שינוי" קודמת מבוטלת, ואין דילוג בהורדה הבאה',
        () async {
      await syncWith(outcome, before: PluginsOnlineStatus.empty);
      expect(provenUpToDate(), isFalse);
    });
  }

  test('כשל אחסון מהסנכרון: סיבה מובנית וכשל', () async {
    await syncWith(
      _outcome(storageFailure: const StorageFullException(dir: 'E:')),
      before: hasUpdates,
    );
    expect(controller.storageFull, isTrue);
    expect(controller.lastSyncFailed, isTrue);
  });

  test('כשל מדיה אינו כשל התקנה של תוסף', () async {
    await syncWith(_outcome(incompleteMedia: ['a']), before: hasUpdates);
    expect(controller.lastSyncFailed, isFalse);
  });
}
