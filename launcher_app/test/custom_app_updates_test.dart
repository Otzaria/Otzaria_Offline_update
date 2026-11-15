import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_detail_view.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_store_card.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:launcher_app/src/screens/store_kit/store_kit.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  _statusTests();
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

      final label = stringsOf(language).customApps.chipNewerOnDrive;
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
          expect(find.text(stringsOf(language).customApps.chipNewerOnDrive),
              findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: 'width=$width, scale=$scale');
        }
      }
    });
  }
}

CustomAppView _github(
  String id, {
  String? stored = '2.0',
  String? installed,
  String? name,
}) =>
    CustomAppView(
      entry: CustomAppEntry(
        descriptor: AppDescriptor(
          id: id,
          name: name ?? id,
          sourceKind: AppSourceKind.github,
          detect: const AppDetectRules(exeName: 'demo.exe'),
          autoIcon: false,
        ),
        installer: stored == null
            ? null
            : StoredInstaller(
                fileName: 'setup.exe',
                version: stored,
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

void _statusTests() {
  final t = stringsOf().customApps;

  Future<void> pumpCards(
    WidgetTester tester,
    CustomAppsController controller,
    List<CustomAppView> apps, {
    bool readOnly = false,
    bool online = true,
    List<String>? downloads,
  }) =>
      pumpScreen(
        tester,
        SingleChildScrollView(
          child: Column(
            children: [
              for (final app in apps)
                SizedBox(
                  width: 900,
                  child: CustomAppStoreCard(
                    controller: controller,
                    app: app,
                    readOnly: readOnly,
                    online: online,
                    onOpenDetail: () {},
                    onInstall: () {},
                    onLaunch: () {},
                    onDownload: () => downloads?.add(app.descriptor.id),
                  ),
                ),
            ],
          ),
        ),
      );

  Finder card(String id) => find.byWidgetPredicate(
        (w) => w is CustomAppStoreCard && w.app.descriptor.id == id,
      );
  Finder chip(String id, String text) => find.descendant(
        of: card(id),
        matching: find.widgetWithText(StoreMetaChip, text),
      );

  testWidgets('each status chip appears only in its state', (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['online'] = '3.0';
    controller.onlineVersions['both'] = '3.0';
    await pumpCards(tester, controller, [
      _github('online', installed: '2.0'),
      _github('drive', installed: '1.0'),
      _github('missing'),
      _github('both', installed: '1.0'),
      _github('current', installed: '2.0'),
    ]);

    expect(chip('online', t.chipUpdateOnline), findsOneWidget);
    expect(chip('online', t.chipNewerOnDrive), findsNothing);
    expect(chip('online', t.chipOnDriveNotInstalled), findsNothing);
    expect(chip('drive', t.chipNewerOnDrive), findsOneWidget);
    expect(chip('drive', t.chipUpdateOnline), findsNothing);
    expect(chip('missing', t.chipOnDriveNotInstalled), findsOneWidget);
    expect(chip('missing', t.chipNewerOnDrive), findsNothing);
    expect(chip('both', t.chipUpdateOnline), findsOneWidget);
    expect(chip('both', t.chipNewerOnDrive), findsOneWidget);
    expect(
      find.descendant(
          of: card('current'), matching: find.byType(StoreMetaChip)),
      findsNothing,
    );
  });

  testWidgets('online update on a launchable app offers download for it only',
      (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['a'] = '3.0';
    final downloads = <String>[];
    await pumpCards(
      tester,
      controller,
      [_github('a', installed: '2.0'), _github('b', installed: '2.0')],
      downloads: downloads,
    );
    expect(find.text(t.downloadUpdateButton), findsOneWidget);
    await tester.tap(find.text(t.downloadUpdateButton));
    expect(downloads, ['a']);
  });

  testWidgets('nothing on the drive: no update chip, card keeps launch',
      (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['a'] = '2.0';
    final app = _github('a', stored: null, installed: '2.0');
    controller.apps = [app];
    expect(controller.hasOnlineUpdate(app), isFalse);

    await pumpScreen(
      tester,
      CustomAppsScreen(controller: controller, online: true),
      size: const Size(1100, 1000),
    );
    expect(find.text(t.chipUpdateOnline), findsNothing);
    expect(find.text(t.downloadUpdateButton), findsNothing);
    expect(
      find.widgetWithText(ActionButton, stringsOf().common.launch),
      findsOneWidget,
    );

    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomAppDetailView), findsOneWidget);
    expect(find.text(t.downloadButton), findsOneWidget);
    expect(find.text(t.downloadUpdateButton), findsNothing);
    expect(find.text(t.chipUpdateOnline), findsNothing);
  });

  testWidgets('an installable update on the drive stays the primary action',
      (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['a'] = '3.0';
    await pumpCards(tester, controller, [_github('a', installed: '1.0')]);
    expect(find.text(t.updateToButton('2.0')), findsOneWidget);
    expect(find.text(t.downloadUpdateButton), findsNothing);
  });

  testWidgets('no download offer on a read-only drive, offline, or for a file',
      (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['a'] = '3.0';
    final app = _github('a', installed: '2.0');
    await pumpCards(tester, controller, [app], readOnly: true);
    expect(find.text(t.downloadUpdateButton), findsNothing);
    await pumpCards(tester, controller, [app], online: false);
    expect(find.text(t.downloadUpdateButton), findsNothing);

    await pumpCards(tester, controller, [_app('a', installed: '2.0')]);
    expect(find.text(t.downloadUpdateButton), findsNothing);
    expect(find.text(t.chipUpdateOnline), findsNothing);
  });

  testWidgets('the offer is disabled while another download runs',
      (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['a'] = '3.0';
    controller.downloadingId = 'other';
    await pumpCards(tester, controller, [_github('a', installed: '2.0')]);
    final button = tester.widget<ActionButton>(
      find.widgetWithText(ActionButton, t.downloadUpdateButton),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('long name with two chips does not overflow when narrow',
      (tester) async {
    final controller = CustomAppsController(mirrorRootDir: '');
    addTearDown(controller.dispose);
    controller.onlineVersions['a'] = '3.0';
    controller.apps = [
      _github(
        'a',
        installed: '1.0',
        name: 'A very long program name that keeps going and going on',
      ),
    ];
    for (final width in [560.0, 760.0]) {
      for (final scale in [1.0, 2.0]) {
        await pumpScreen(
          tester,
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: CustomAppsScreen(controller: controller),
          ),
          size: Size(width, 1000),
        );
        expect(tester.takeException(), isNull,
            reason: 'width=$width, scale=$scale');
      }
    }
  });
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
