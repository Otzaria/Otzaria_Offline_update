import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/controllers/library_module_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/controllers/search_feedback_controller.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/screens/reports_upload_flow.dart';
import 'package:launcher_app/src/screens/search_feedback_flow.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import 'test_harness.dart';

/// תור קיים בזיכרון: בדיקות הזרימה אינן תלויות בדיסק או בשרת.
class _MemoryFeedback extends SearchFeedbackTransport {
  _MemoryFeedback()
      : super('unused',
            client: MockClient((_) async => http.Response('{}', 200)));

  int sourceEvents = 2;
  int carriedEvents = 0;
  int uploads = 0;
  int stops = 0;

  @override
  Future<int> pending(String sourceDirectory) async => sourceEvents;

  @override
  Future<int> pendingForCollection(String sourceDirectory) async =>
      sourceEvents;

  @override
  Future<int> count() async => carriedEvents;

  @override
  Future<int> collect(String sourceDirectory,
      {required Future<bool> Function() mayCollect}) async {
    if (!await mayCollect()) return 0;
    final collected = sourceEvents;
    carriedEvents += collected;
    sourceEvents = 0;
    return collected;
  }

  @override
  Future<SearchFeedbackUploadResult> upload() async {
    uploads++;
    return (sent: carriedEvents, rejected: 0, remaining: 0);
  }

  @override
  void stop() {
    stops++;
    super.stop();
  }
}

class _RunningOtzaria extends RunningOtzariaLocator {
  const _RunningOtzaria();

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: true, launchPath: null);
}

Future<BuildContext> _host(WidgetTester tester) async {
  late BuildContext context;
  await pumpScreen(
    tester,
    Scaffold(body: Builder(builder: (value) {
      context = value;
      return const SizedBox.shrink();
    })),
  );
  return context;
}

void main() {
  final strings = stringsOf();
  late _MemoryFeedback transport;
  late SearchFeedbackController controller;
  var consent = true;

  setUp(() {
    consent = true;
    transport = _MemoryFeedback();
    controller = SearchFeedbackController(
      transport: transport,
      resolveSource: () async => consent ? 'source' : null,
    );
  });

  tearDown(() => controller.dispose());

  testWidgets('empty feedback does not show a collection offer',
      (tester) async {
    transport.sourceEvents = 0;
    final context = await _host(tester);
    await offerSearchFeedbackCollection(context, controller);
    await tester.pumpAndSettle();
    expect(find.text(strings.libraryDomain.semanticFeedbackCollectTitle),
        findsNothing);
  });

  testWidgets('declining collection keeps source and does not offer again',
      (tester) async {
    final context = await _host(tester);
    unawaited(offerSearchFeedbackCollection(context, controller));
    await tester.pumpAndSettle();
    expect(find.text(strings.libraryDomain.semanticFeedbackCollectTitle),
        findsOneWidget);
    await tester.tap(find.text(strings.errorReports.collectLater));
    await tester.pumpAndSettle();
    expect(transport.sourceEvents, 2);
    expect(transport.carriedEvents, 0);
    unawaited(offerSearchFeedbackCollection(context, controller));
    await tester.pumpAndSettle();
    expect(find.text(strings.libraryDomain.semanticFeedbackCollectTitle),
        findsNothing);
  });

  test('pending offer is empty while uploading or collecting', () async {
    expect(await controller.pendingToOffer(), 2);
    controller.isUploading = true;
    expect(await controller.pendingToOffer(), 0);
    controller
      ..isUploading = false
      ..isCollecting = true;
    expect(await controller.pendingToOffer(), 0);
    controller.isCollecting = false;
    expect(await controller.pendingToOffer(), 2);
  });

  test('the source is resolved with a fresh process probe every time',
      () async {
    final temporary = await Directory.systemTemp.createTemp('feedback-fresh-');
    addTearDown(() => temporary.delete(recursive: true));
    final locator = _CountingOtzaria();
    final drive = SearchFeedbackController.forDrive(
      dataDir: p.join(temporary.path, 'drive'),
      stateDir: temporary.path,
      runningLocator: locator,
      launchPath: () async => null,
    );
    addTearDown(drive.dispose);
    await drive.resolveSource();
    await drive.resolveSource();
    expect(locator.probes, 2);
  });

  test('a source that is unavailable now does not consume the offer', () async {
    final collectible = SearchFeedbackController(
      transport: transport,
      resolveSource: () async => consent ? 'source' : null,
    );
    addTearDown(collectible.dispose);
    consent = false;
    expect(await collectible.pendingToOffer(), 0);
    consent = true;
    expect(await collectible.pendingToOffer(), 2);
    collectible.markDeclined(2);
    expect(await collectible.pendingToOffer(), 0);
  });

  testWidgets(
      'approving collection carries events and updates the pending count',
      (tester) async {
    final context = await _host(tester);
    unawaited(offerSearchFeedbackCollection(context, controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.errorReports.collectConfirm));
    await tester.pumpAndSettle();
    expect(transport.sourceEvents, 0);
    expect(transport.carriedEvents, 2);
    expect(controller.outboxCount, 2);
  });

  testWidgets('revocation while the prompt is open keeps source events',
      (tester) async {
    final context = await _host(tester);
    unawaited(offerSearchFeedbackCollection(context, controller));
    await tester.pumpAndSettle();
    consent = false;
    await tester.tap(find.text(strings.errorReports.collectConfirm));
    await tester.pumpAndSettle();
    expect(transport.sourceEvents, 2);
    expect(transport.carriedEvents, 0);
    expect(await controller.collect(), 0);
  });

  testWidgets('declining upload never reaches the network transport',
      (tester) async {
    transport.carriedEvents = 2;
    final context = await _host(tester);
    unawaited(uploadAllReports(context, searchFeedback: controller));
    await tester.pumpAndSettle();
    expect(find.text(strings.libraryDomain.semanticFeedbackUploadTitle),
        findsOneWidget);
    await tester.tap(find.text(strings.common.cancel));
    await tester.pumpAndSettle();
    expect(transport.uploads, 0);
    expect(transport.carriedEvents, 2);
  });

  testWidgets('read-only drive offers neither collection nor upload',
      (tester) async {
    transport.carriedEvents = 2;
    final context = await _host(tester);
    await offerSearchFeedbackCollection(context, controller, readOnly: true);
    await tester.pumpAndSettle();
    expect(find.text(strings.libraryDomain.semanticFeedbackCollectTitle),
        findsNothing);
    expect(find.text(strings.libraryDomain.semanticFeedbackUploadTitle),
        findsNothing);
    expect(transport.uploads, 0);
    expect(transport.sourceEvents, 2);
  });

  test(
      'grant while Otzaria runs does not touch settings or resolve launch path',
      () async {
    final temporary =
        await Directory.systemTemp.createTemp('feedback-consent-');
    addTearDown(() => temporary.delete(recursive: true));
    final settings = File(p.join(temporary.path, 'settings.hive'));
    await settings.writeAsBytes([1, 2, 3]);
    var launchReads = 0;
    final guarded = SearchFeedbackController.forDrive(
      dataDir: p.join(temporary.path, 'drive'),
      stateDir: temporary.path,
      runningLocator: const _RunningOtzaria(),
      launchPath: () async {
        launchReads++;
        return p.join(temporary.path, 'otzaria.exe');
      },
    );
    addTearDown(guarded.dispose);
    expect(await guarded.grantConsent(), false);
    expect(launchReads, 0);
    expect(await settings.readAsBytes(), [1, 2, 3]);
    expect(await Directory(p.join(temporary.path, 'drive')).exists(), false);
  });

  group('home feedback actions', () {
    late Directory temporary;
    late OtzariaModuleController otzaria;
    late LibraryModuleController library;
    late PluginsModuleController plugins;
    late LauncherUpdateController launcher;
    late SettingsController settings;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('feedback-home-');
      otzaria = OtzariaModuleController(dataDir: temporary.path);
      library = LibraryModuleController(dataDir: temporary.path);
      plugins = PluginsModuleController(mirrorRootDir: temporary.path);
      launcher = LauncherUpdateController(dataDir: temporary.path);
      settings = SettingsController(dataDir: temporary.path);
      otzaria.onlineCheckedAt = DateTime.utc(2026, 9, 1);
    });

    tearDown(() {
      otzaria.dispose();
      library.dispose();
      plugins.dispose();
      launcher.dispose();
      settings.dispose();
      temporary.deleteSync(recursive: true);
    });

    HomeScreen home({bool readOnly = false, VoidCallback? onUpload}) =>
        HomeScreen(
          readOnly: readOnly,
          otzaria: otzaria,
          library: library,
          plugins: plugins,
          launcherUpdate: launcher,
          settings: settings,
          otzariaIsRunning: false,
          onCloseOtzaria: () async => true,
          isDownloading: false,
          isCancellingDownload: false,
          isCheckingOnline: false,
          longTaskRunning: false,
          onProcessStateChanged: () async => false,
          onCheckOnline: () async {},
          onDownloadAll: () async {},
          onCancelDownload: () async {},
          onDownloadLauncherUpdate: () async {},
          onInstallLauncherUpdate: () async {},
          onRequestReindex: () async {},
          onGoToOtzaria: () {},
          onGoToLibrary: () {},
          searchFeedback: controller,
          onUploadReports: () async => onUpload?.call(),
        );

    testWidgets(
        'upload action appears only with carried data and calls handler',
        (tester) async {
      var clicks = 0;
      await pumpScreen(tester, home(onUpload: () => clicks++));
      expect(find.text(strings.errorReports.uploadButton(2)), findsNothing);
      transport.carriedEvents = 2;
      await controller.refreshOutbox();
      await tester.pump();
      expect(find.text(strings.errorReports.uploadButton(2)), findsOneWidget);
      await tester.tap(find.text(strings.errorReports.uploadButton(2)));
      expect(clicks, 1);
    });

    testWidgets('upload in progress exposes a stop action', (tester) async {
      controller
        ..outboxCount = 2
        ..isUploading = true;
      await pumpScreen(tester, home());
      final stops = transport.stops;
      await tester.tap(find.text(strings.errorReports.uploadStopButton));
      expect(transport.stops, stops + 1);
    });

    testWidgets('read-only home hides pending feedback actions',
        (tester) async {
      controller.outboxCount = 2;
      await pumpScreen(tester, home(readOnly: true));
      expect(find.text(strings.errorReports.uploadButton(2)), findsNothing);
    });
  });
}

class _CountingOtzaria extends RunningOtzariaLocator {
  _CountingOtzaria();

  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    probes++;
    return (isRunning: false, launchPath: null);
  }
}
