import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import 'test_support.dart';

/// מנוע שכל פעולה שלו על המראה ממתינה למחסום משלה. הסנכרון מוחק את קובץ
/// המקור — כמו סנכרון אמיתי שמחליף גרסה וגוזם את הישנה.
class _GatedManager extends PluginsManager {
  _GatedManager(this.dir) : super(resolveMirrorDir: () async => dir);

  final String dir;
  final calls = <String>[];
  Completer<void>? deliverGate;

  /// מחסום לכל קריאה ל-directInstall לפי הסדר; אחריהן — [deliverGate].
  final deliverGates = <Completer<void>>[];
  Completer<void>? saveGate;
  Completer<void>? exportGate;
  Completer<void>? syncGate;

  File get source => File(p.join(dir, 'plugins', 'a.otzplugin'));

  @override
  Future<PluginInstallResult> directInstall(
    StorePlugin plugin, {
    String? appVersion,
    void Function(StorePlugin updated)? onPluginUpdated,
  }) async {
    final call = calls.where((c) => c.startsWith('deliver')).length;
    calls.add('deliver');
    await (call < deliverGates.length
        ? deliverGates[call].future
        : deliverGate?.future);
    return PluginInstallResult.ok(source.readAsStringSync());
  }

  @override
  Future<PluginInstallResult> saveCopy(
    StorePlugin plugin,
    String destPath, {
    String? appVersion,
  }) async {
    calls.add('save');
    await saveGate?.future;
    return const PluginInstallResult.ok();
  }

  @override
  Future<StoreAppExportOutcome> exportStoreApp(
    String destinationDir, {
    void Function(StoreAppExportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls.add('export');
    await exportGate?.future;
    return StoreAppExportOutcome(
      destinationDir: destinationDir,
      appPath: destinationDir,
      plugins: 0,
      files: 0,
      bytes: 0,
    );
  }

  @override
  Future<PluginSyncOutcome> sync({
    List<String> appVersions = const [],
    void Function(PluginSyncProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls.add('sync');
    await syncGate?.future;
    if (source.existsSync()) source.deleteSync();
    return const PluginSyncOutcome(
      catalog: PluginCatalog.empty,
      fetched: 0,
      skipped: 0,
    );
  }
}

void main() {
  late Directory temp;
  late _GatedManager manager;
  late PluginsModuleController controller;
  final t = AppL10n.strings.plugins;
  final plugin = StorePlugin.fromApi(
    const {'id': 'a', 'name': 'א'},
    'https://example.invalid',
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('plugin-claim-');
    AppLogger.resetForTest();
    await AppLogger.init(temp.path);
    manager = _GatedManager(p.join(temp.path, 'mirror'));
    manager.source
      ..createSync(recursive: true)
      ..writeAsStringSync('מקור');
    controller = PluginsModuleController(
      mirrorRootDir: p.join(temp.path, 'mirror'),
      manager: manager,
    );
  });

  tearDown(() async {
    controller.dispose();
    await AppLogger.maybeInstance?.flush();
    AppLogger.resetForTest();
    await deleteTempDir(temp);
  });

  group('קורא פעיל, ואז כותב', () {
    test('סנכרון בזמן מסירה נדחה, וקובץ המקור נשאר עד שהמסירה קוראת אותו',
        () async {
      manager.deliverGate = Completer<void>();
      final delivery = controller.deliver(plugin);
      expect(controller.isDeliveringAny, isTrue);

      expect(controller.syncBlockedReason(), t.syncBlockedSnack);
      expect(await controller.sync(), isFalse);
      expect(controller.isSyncing, isFalse);

      manager.deliverGate!.complete();
      final result = await delivery;
      expect(result.deliveredPath, 'מקור');
      expect(manager.calls, ['deliver']);

      expect(await controller.sync(), isTrue);
      expect(manager.calls, ['deliver', 'sync']);
    });

    test(
        'שתי מסירות חופפות של אותו תוסף: אוצריא מקבלת אותו פעם אחת, וסנכרון '
        'שבא אחרי הראשונה אינו מוחק את המקור של השנייה', () async {
      // בלי ההצטרפות השנייה הייתה נחסמת כאן, אחרי שהראשונה שחררה את המראה.
      manager.deliverGates.addAll([Completer<void>(), Completer<void>()]);
      final first = controller.deliver(plugin);
      final second = controller.deliver(plugin);
      expect(identical(first, second), isTrue);

      manager.deliverGates[0].complete();
      await first;
      expect(manager.calls, ['deliver']);
      expect(controller.isReadingMirror, isFalse);
      expect(await controller.sync(), isTrue);

      expect((await second).deliveredPath, 'מקור');
      expect(manager.calls, ['deliver', 'sync']);
    });

    test('אחרי שהסגירה אושרה: מסירה חדשה נכשלת בלי לפנות למנוע', () async {
      await controller.stopDeliveriesAndWait();
      final result = await controller.deliver(plugin);
      expect(result.success, isFalse);
      expect(controller.isDeliveringAny, isFalse);
      expect(manager.calls, isEmpty);
    });

    test('מסירות של תוספים שונים עדיין רצות במקביל', () async {
      final other = StorePlugin.fromApi(
        const {'id': 'b', 'name': 'ב'},
        'https://example.invalid',
      );
      manager.deliverGates.addAll([Completer<void>(), Completer<void>()]);
      final a = controller.deliver(plugin);
      final b = controller.deliver(other);
      await pumpEventQueue();
      expect(manager.calls, ['deliver', 'deliver']);
      expect(controller.isDelivering(plugin), isTrue);
      expect(controller.isDelivering(other), isTrue);

      manager.deliverGates[0].complete();
      await a;
      expect(controller.isDelivering(other), isTrue);
      expect(controller.isReadingMirror, isTrue);
      manager.deliverGates[1].complete();
      await b;
      expect(controller.isReadingMirror, isFalse);
    });

    test('סנכרון בזמן שמירת עותק נדחה', () async {
      manager.saveGate = Completer<void>();
      final save = controller.saveCopy(plugin, p.join(temp.path, 'out'));
      expect(controller.isReadingMirror, isTrue);
      expect(await controller.sync(), isFalse);
      manager.saveGate!.complete();
      await save;
      expect(controller.isReadingMirror, isFalse);
      expect(manager.calls, ['save']);
    });

    test('סנכרון בזמן העתקת החנות נדחה', () async {
      manager.exportGate = Completer<void>();
      final export = controller.exportStoreApp(p.join(temp.path, 'out'));
      expect(await controller.sync(), isFalse);
      manager.exportGate!.complete();
      await export;
      expect(manager.calls, ['export']);
    });

    test('סנכרון ברווח שבין שתי מסירות של "עדכון הכול" נדחה', () async {
      final first = StorePlugin.fromApi(
        const {'id': 'b', 'name': 'ב'},
        'https://example.invalid',
      );
      final all = controller.updateAll([plugin, first]);
      await pumpEventQueue();
      expect(controller.isDeliveringAny, isFalse);
      expect(controller.isUpdatingAll, isTrue);
      expect(await controller.sync(), isFalse);
      controller.stopUpdateAll();
      await all;
      expect(manager.calls, ['deliver']);
    });

    test(
        'מסירה רציפה ("עדכון כאן" שהמשיך ברקע): סנכרון נדחה גם ברווח שבין '
        'המסירות', () async {
      final second = StorePlugin.fromApi(
        const {'id': 'b', 'name': 'ב'},
        'https://example.invalid',
      );
      var stop = false;
      final run = controller.deliverUpdates(
        plugins: [plugin, second],
        isCancelled: () => stop,
      );
      await pumpEventQueue();
      expect(controller.isDeliveringAny, isFalse);
      expect(controller.isUpdatingAll, isFalse);
      expect(controller.isReadingMirror, isTrue);
      expect(await controller.sync(), isFalse);
      // גם העתקת החנות — המסירה הבאה ברצף הייתה נכשלת בגללה.
      await expectLater(
        controller.exportStoreApp(p.join(temp.path, 'out')),
        throwsA(isA<PluginMirrorBusy>()
            .having((e) => e.message, 'message', t.actionsBlockedDelivering)),
      );
      expect(controller.isDeliveryRunActive, isTrue);
      final seen = <bool>[];
      controller.addListener(() => seen.add(controller.isDeliveryRunActive));
      stop = true;
      await run;
      expect(controller.isReadingMirror, isFalse);
      expect(controller.isDeliveryRunActive, isFalse);
      // סוף הרצף מודיע — אחרת הבית והיציאה נשארים "חסומים".
      expect(seen.last, isFalse);
      expect(manager.calls, ['deliver']);
    });

    test(
        'סנכרון ההורדה שנדחה: כשל של הרכיב בלי שגיאה בכרטיס, ונמחק בסנכרון '
        'הבא', () async {
      manager.deliverGate = Completer<void>();
      final delivery = controller.deliver(plugin);
      expect(await controller.sync(forDownload: true), isFalse);
      expect(controller.lastSyncFailed, isTrue);
      expect(controller.syncRefusal, t.syncBlockedSnack);
      expect(controller.errorMessage, isNull);
      manager.deliverGate!.complete();
      await delivery;

      expect(await controller.sync(forDownload: true), isTrue);
      expect(controller.syncRefusal, isNull);
    });
  });

  group('כותב פעיל, ואז קורא', () {
    test('מסירה, שמירה והעתקה בזמן סנכרון נדחות בלי לגעת במראה', () async {
      manager.syncGate = Completer<void>();
      final sync = controller.sync();
      expect(controller.isSyncing, isTrue);

      final delivered = await controller.deliver(plugin);
      expect(delivered.success, isFalse);
      expect(delivered.error, t.actionsBlockedSyncing);
      final saved = await controller.saveCopy(plugin, p.join(temp.path, 'x'));
      expect(saved.error, t.actionsBlockedSyncing);
      await expectLater(
        controller.exportStoreApp(p.join(temp.path, 'y')),
        throwsA(isA<PluginMirrorBusy>()),
      );
      expect(controller.isDeliveringAny, isFalse);

      manager.syncGate!.complete();
      expect(await sync, isTrue);
      expect(manager.calls, ['sync']);
    });

    test('מראה שההורדה כותבת: הקוראים נדחים, הסנכרון של ההורדה עצמה עובר',
        () async {
      var writing = true;
      controller.mirrorWrittenElsewhere = () => writing;
      controller.syncBlockedElsewhere = () => writing;

      expect(
          (await controller.deliver(plugin)).error, t.actionsBlockedElsewhere);
      expect((await controller.saveCopy(plugin, 'x')).error,
          t.actionsBlockedElsewhere);
      await expectLater(
          controller.exportStoreApp('y'), throwsA(isA<PluginMirrorBusy>()));
      expect(await controller.sync(), isFalse);
      expect(manager.calls, isEmpty);

      expect(await controller.sync(forDownload: true), isTrue);
      expect(manager.calls, ['sync']);

      writing = false;
      manager.source.writeAsStringSync('מקור');
      expect((await controller.deliver(plugin)).success, isTrue);
    });

    test('מסירה בזמן העתקת החנות נדחית — היא עשויה להוריד קובץ חסר', () async {
      manager.exportGate = Completer<void>();
      final export = controller.exportStoreApp(p.join(temp.path, 'out'));
      expect(
          (await controller.deliver(plugin)).error, t.actionsBlockedExporting);
      manager.exportGate!.complete();
      await export;
      expect(manager.calls, ['export']);
    });
  });
}
