import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:launcher_app/src/shell/app_session.dart';
import 'package:launcher_app/src/shell/home_guidance.dart' show GuidanceItem;
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/shell/shell_navigator.dart';
import 'package:launcher_app/src/shell/shell_tasks.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:plugins_manager/plugins_manager.dart';

import 'test_harness.dart';
import 'test_support.dart';

void main() {
  late Directory tempDir;
  late SettingsController settings;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ui_snack_shell_test');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    await settings.update(
      const AppSettings(personalModeAsked: true, autoCheckUpdates: false),
    );
  });

  tearDown(() async {
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
    AppL10n.use(AppLanguage.hebrew);
  });

  for (final language in AppLanguage.values) {
    for (final size in [const Size(760, 560), const Size(1000, 720)]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
            'plugin confirmation leaves shell actions usable: '
            '$language / $size / $scale', (tester) async {
          useViewSize(tester, size);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          AppL10n.use(language);
          await tester.pumpWidget(wrap(
            AppShell(
              dataDir: tempDir.path,
              settings: settings,
              runningLocator: const _NeverRunningLocator(),
              showWindowButtons: false,
              noticesStore: MemoryNoticesStore(
                seen: {NoticesSeenStore.errorReportsIntro},
              ),
            ),
            language: language,
            navigatorKey: navigatorKey,
          ));
          await tester.pump();
          final shell = tester.state(find.byType(AppShell)) as dynamic;
          final session = shell.session as AppSession;
          final navigator = shell.navigator as ShellNavigator;
          final plugin = StorePlugin.fromApi(const {
            'id': 'example',
            'pluginUid': 'example.manifest',
            'name': 'Example',
            'version': '1.0.0',
          }, 'https://otzaria.org');
          session.tasks
            ..startUpdateHere(
              const [GuidanceItem.plugins],
              pluginNames: [plugin.name],
            )
            ..stageRunning(GuidanceItem.plugins);
          await tester.pump();

          // מפת ההתקנה מוזרקת; שעון הבקר מוסר את האישור דרך AppSession.
          session.plugins
            ..status = PluginsModuleStatus.loading
            ..watchForInstall(plugin)
            ..installed = {plugin.manifestId!: plugin.version};
          final message =
              stringsOf(language).plugins.installDoneSnack(plugin.name);
          try {
            await tester.pump(const Duration(seconds: 1));
            expect(find.text(message), findsOneWidget);
            expect(session.plugins.isAwaitingInstall, isFalse);

            Rect toastRect() => tester.getRect(find
                .ancestor(
                    of: find.text(message), matching: find.byType(Material))
                .first);
            final footer = tester.getRect(find.byType(UiSnackAnchor));
            expect(toastRect().bottom, lessThanOrEqualTo(footer.top));

            session.tasks
              ..pluginDeliveries([
                PluginDelivery(plugin.name, PluginDeliveryState.sent),
              ])
              ..stageFinished(GuidanceItem.plugins, StageOutcome.done)
              ..updateDone();
            await tester.pump();

            final actions = tester.getRect(
              find.byKey(const ValueKey('task.result.actions')),
            );
            expect(toastRect().overlaps(actions), isFalse);
            expect(navigator.showsTask, isTrue);
            await tester.tap(find.text(stringsOf(language).task.backHome));
            await tester.pump();

            expect(session.tasks.hasTask, isFalse);
            expect(navigator.stack, [const HomeRoute()]);
            expect(find.byKey(ShellKeys.taskLayer), findsNothing);
            expect(find.text(message), findsOneWidget);
            expect(toastRect().bottom, closeTo(size.height - 20, 0.1));
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pump(const Duration(seconds: 7));
            await tester.pumpWidget(const SizedBox.shrink());
          }
        });
      }
    }
  }
}

class _NeverRunningLocator extends RunningOtzariaLocator {
  const _NeverRunningLocator();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: false, launchPath: null);
}
