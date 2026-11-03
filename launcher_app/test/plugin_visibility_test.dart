import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/plugins/plugin_store_card.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/services/known_plugins_store.dart';
import 'package:path/path.dart' as p;
import 'package:plugins_manager/plugins_manager.dart';

import 'test_harness.dart';

StorePlugin _plugin(String id) => StorePlugin.fromJson({
      'id': id,
      'name': id,
      'manifestId': id,
      'version': '1.0.0',
    });

void main() {
  late Directory dir;
  late PluginsModuleController controller;
  late PluginMirrorStore mirror;
  late KnownPluginsStore known;
  late ValueNotifier<bool> active;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plugin-visibility-');
    final mirrorDir = p.join(dir.path, 'mirror');
    final stateDir = p.join(dir.path, 'state');
    mirror = PluginMirrorStore(mirrorDir);
    known = KnownPluginsStore(stateDir);
    controller = PluginsModuleController(
      mirrorRootDir: mirrorDir,
      stateDir: stateDir,
      manager: PluginsManager(
        resolveMirrorDir: () async => mirrorDir,
        resolvePluginsDir: () async => p.join(dir.path, 'installed'),
        locatePluginsDb: (_) async => null,
      ),
    );
    active = ValueNotifier(true);
    await mirror.save(PluginCatalog(plugins: [_plugin('old')]));
    await controller.load();
  });

  tearDown(() async {
    await known.recordSeen(const []);
    controller.dispose();
    active.dispose();
    await dir.delete(recursive: true);
  });

  Widget screen({bool taskOverStore = false}) => ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (context, visible, child) => Stack(
          children: [
            IndexedStack(
              index: visible || taskOverStore ? 1 : 0,
              children: [
                const SizedBox.shrink(),
                PluginsScreen(controller: controller, active: visible),
              ],
            ),
            if (taskOverStore && !visible)
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
          ],
        ),
      );

  Future<void> visit(WidgetTester tester, bool visible) async {
    active.value = visible;
    await tester.runAsync(() async {
      await tester.pumpAndSettle();
      await known.recordSeen(const []);
    });
  }

  Future<void> addNewPlugin(WidgetTester tester) async {
    await tester.runAsync(() async {
      await mirror
          .save(PluginCatalog(plugins: [_plugin('old'), _plugin('new')]));
      await controller.load();
      await known.recordSeen(const []);
    });
    await tester.pumpAndSettle();
  }

  for (final taskOverStore in [false, true]) {
    testWidgets(
        '${taskOverStore ? 'task-covered' : 'hidden'} store keeps new plugins pending until the next visit',
        (tester) async {
      await tester.runAsync(
          () => pumpScreen(tester, screen(taskOverStore: taskOverStore)));
      final storeState = tester.state(find.byType(PluginsScreen));

      await visit(tester, false);
      await addNewPlugin(tester);

      expect(controller.newPluginsForHome.map((plugin) => plugin.id), ['new']);
      expect(controller.newPlugins.map((plugin) => plugin.id), ['new']);
      expect(await tester.runAsync(known.loadSeen), {'old'});
      expect(controller.isNewThisRun(_plugin('new')), isFalse);

      await visit(tester, true);

      expect(tester.state(find.byType(PluginsScreen)), same(storeState));
      expect(controller.newPluginsForHome, isEmpty);
      expect(await tester.runAsync(known.loadSeen), {'old', 'new'});
      expect(
        find.descendant(
          of: find.widgetWithText(PluginStoreCard, 'new'),
          matching: find.text(stringsOf().plugins.newChip),
        ),
        findsOneWidget,
      );

      await visit(tester, false);
      await visit(tester, true);
      expect(controller.isNewThisRun(_plugin('new')), isTrue);
      expect(controller.newPluginsForHome, isEmpty);
    });
  }

  testWidgets('initially hidden store does not mark plugins as seen',
      (tester) async {
    await addNewPlugin(tester);
    active.value = false;
    await tester.runAsync(() async {
      await pumpScreen(tester, screen());
      await known.recordSeen(const []);
    });

    expect(controller.newPluginsForHome.map((plugin) => plugin.id), ['new']);
    expect(await tester.runAsync(known.loadSeen), {'old'});

    await visit(tester, true);

    expect(controller.newPluginsForHome, isEmpty);
    expect(controller.isNewThisRun(_plugin('new')), isTrue);
  });

  testWidgets('leaving the store before a catalog load finishes keeps notices',
      (tester) async {
    await tester.runAsync(() => pumpScreen(tester, screen()));
    active.value = false;
    await addNewPlugin(tester);

    expect(controller.newPluginsForHome.map((plugin) => plugin.id), ['new']);
    expect(await tester.runAsync(known.loadSeen), {'old'});
  });
}
