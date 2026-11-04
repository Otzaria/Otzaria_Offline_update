import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_detail_view.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_store_card.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('only the app with an update is labelled (${language.code})',
        (tester) async {
      final controller = CustomAppsController(mirrorRootDir: '');
      addTearDown(controller.dispose);
      controller.apps = [
        _app('Update', installed: '1.0'),
        _app('Missing'),
        _app('Current', installed: '2.0'),
        _app('Newer', installed: '3.0'),
        _app('Unknown', installed: 'unknown'),
      ];
      await pumpScreen(tester, CustomAppsScreen(controller: controller),
          language: language, size: const Size(1100, 1000));

      final label = stringsOf(language).common.updateAvailable;
      expect(find.text(label), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(CustomAppStoreCard, 'Update'),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomAppDetailView), findsOneWidget);
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('update label fits the store grid (${language.code})',
        (tester) async {
      final controller = CustomAppsController(mirrorRootDir: '');
      addTearDown(controller.dispose);
      controller.apps = [_app('Update', installed: '1.0')];
      for (final width in [760.0, 820.0, 1100.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          await pumpScreen(
            tester,
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: CustomAppsScreen(controller: controller),
            ),
            language: language,
            size: Size(width, 1000),
          );
          expect(find.text(stringsOf(language).common.updateAvailable),
              findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: 'width=$width, scale=$scale');
        }
      }
    });
  }
}

CustomAppView _app(String name, {String? installed}) => CustomAppView(
      entry: CustomAppEntry(
        descriptor: AppDescriptor(
          id: name.toLowerCase(),
          name: name,
          sourceKind: AppSourceKind.manual,
          detect: const AppDetectRules(exeName: 'demo.exe'),
          autoIcon: false,
        ),
        installer: StoredInstaller(
          fileName: 'setup.exe',
          version: '2.0',
          sizeBytes: 10,
          addedAt: DateTime(2026),
        ),
      ),
      installed: installed == null
          ? null
          : CustomAppInstallState(
              version: installed,
              installDir: r'C:\Demo',
              launchPath: r'C:\Demo\demo.exe',
            ),
    );
