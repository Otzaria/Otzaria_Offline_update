import 'dart:async';

import 'package:custom_apps_manager/custom_apps_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/custom_apps_controller.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_detail_view.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_app_store_card.dart';
import 'package:launcher_app/src/screens/custom_apps/custom_apps_screen.dart';
import 'package:launcher_app/src/services/byte_size.dart';
import 'package:launcher_app/src/widgets/info_rows.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';

import 'test_harness.dart';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('הורדה מהכרטיס: 10% → 50% בלי שינוי מצב (${language.code})',
        (tester) async {
      final controller = _DownloadController(total: 10240);
      addTearDown(controller.dispose);
      await pumpScreen(tester, CustomAppsScreen(controller: controller),
          language: language);
      expect(find.byType(InfoProgressRow), findsNothing);
      await tester
          .tap(find.text(stringsOf(language).customApps.downloadButton));
      await tester.pump();

      expect(controller.downloadingId, 'demo');
      expect(find.byType(CustomAppDetailView), findsNothing);
      expect(find.text('10%'), findsOneWidget);
      var stateChanges = 0;
      controller.addListener(() => stateChanges++);
      controller.reportProgress(5120);
      await tester.pump();

      expect(find.text('50%'), findsOneWidget);
      expect(find.text(formatBytesProgress(5120, 10240)!), findsOneWidget);
      expect(stateChanges, 0);

      controller.finish();
      await tester.pump();
      expect(controller.downloadingId, isNull);
      expect(find.byType(InfoProgressRow), findsNothing);
    });

    testWidgets('הורדה מהכרטיס בגודל לא ידוע מציגה בייטים (${language.code})',
        (tester) async {
      final controller = _DownloadController(total: null);
      addTearDown(controller.dispose);
      await pumpScreen(tester, CustomAppsScreen(controller: controller),
          language: language);
      await tester
          .tap(find.text(stringsOf(language).customApps.downloadButton));
      await tester.pump();

      expect(
          tester.widget<InfoProgressRow>(find.byType(InfoProgressRow)).progress,
          isNull);
      expect(find.text(formatBytes(1024)), findsOneWidget);
      controller.reportProgress(2048);
      await tester.pump();
      expect(find.text(formatBytes(2048)), findsOneWidget);
      expect(find.text('0%'), findsNothing);

      controller.finish();
      await tester.pump();
      expect(find.byType(InfoProgressRow), findsNothing);
    });
  }

  testWidgets('download progress stays visible after selecting a scrolled card',
      (tester) async {
    final controller = _DownloadController(total: 10240, count: 30);
    addTearDown(controller.dispose);
    await pumpScreen(tester, CustomAppsScreen(controller: controller),
        size: const Size(760, 560));
    await tester.scrollUntilVisible(
      find.text('Demo 24'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.widgetWithText(CustomAppStoreCard, 'Demo 24');
    await tester.tap(find.descendant(
      of: card,
      matching: find.text(stringsOf().customApps.downloadButton),
    ));
    await tester.pump();

    try {
      expect(controller.downloadingId, 'demo-24');
      controller.reportProgress(5120);
      await tester.pump();
      expect(find.text('50%').hitTestable(), findsOneWidget);
    } finally {
      controller.finish();
      await tester.pump();
    }
  });

  for (final language in AppLanguage.values) {
    testWidgets('ההתקדמות נגלית בהורדה מדף פרטים ארוך (${language.code})',
        (tester) async {
      final controller = _DownloadController(
        total: 10240,
        description: List.filled(30, 'Demo description').join('\n'),
      );
      addTearDown(controller.dispose);
      await pumpScreen(
        tester,
        CustomAppsScreen(
            controller: controller, detailId: 'demo', onDetailChanged: (_) {}),
        language: language,
        size: const Size(760, 560),
      );
      final download = find.text(stringsOf(language).customApps.downloadButton);
      await Scrollable.ensureVisible(tester.element(download), alignment: 1);
      await tester.pump();
      expect(download.hitTestable(), findsOneWidget);
      await tester.tap(download);
      await tester.pump();
      await tester.pump();

      try {
        expect(find.text('10%').hitTestable(), findsOneWidget);
        controller.reportProgress(5120);
        await tester.pump();
        expect(find.text('50%').hitTestable(), findsOneWidget);
      } finally {
        controller.finish();
        await tester.pump();
      }
    });
  }
}

class _DownloadController extends CustomAppsController {
  _DownloadController({required this.total, int count = 1, String? description})
      : super(mirrorRootDir: '') {
    apps = [
      for (var i = 0; i < count; i++)
        CustomAppView(
          entry: CustomAppEntry(
            descriptor: AppDescriptor(
              id: count == 1 ? 'demo' : 'demo-$i',
              name: count == 1 ? 'Demo' : 'Demo $i',
              description: description,
              sourceKind: AppSourceKind.github,
              github: const GithubSource(
                owner: 'example',
                repo: 'demo',
                assetPattern: r'demo\.exe$',
              ),
              detect: const AppDetectRules(),
              autoIcon: false,
            ),
          ),
        ),
    ];
  }

  final int? total;
  final _completion = Completer<StoredInstaller>();

  @override
  Future<void> fillMissingIcons({bool readOnly = false}) async {}

  @override
  Future<StoredInstaller?> download(String id) async {
    downloadingId = id;
    downloadReceived = 1024;
    downloadTotal = total;
    notifyListeners();
    final installer = await _completion.future;
    downloadingId = null;
    notifyListeners();
    return installer;
  }

  void reportProgress(int received) {
    downloadReceived = received;
    notifyProgress();
  }

  void finish() => _completion.complete(StoredInstaller(
        fileName: 'demo.exe',
        version: '1.0',
        sizeBytes: 10240,
        addedAt: DateTime(2026, 11, 3),
      ));
}
