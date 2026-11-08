import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/android_module_controller.dart';
import 'package:launcher_app/src/screens/android_update_page.dart';
import 'package:launcher_app/src/widgets/action_buttons.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:otzaria_manager/otzaria_manager.dart';

import 'test_harness.dart';

const apk = AndroidApkInfo(
    applicationId: otzariaAndroidApplicationId,
    versionCode: 20,
    versionName: '1.0.0',
    minSdk: 24,
    targetSdk: 36,
    abis: ['arm64-v8a']);
const mirror = AndroidMirroredRelease(
    tagName: 'v1',
    apkPath: '/drive/app.apk',
    size: 100,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    info: apk);
const first =
    AndroidDevice(serial: 'first', state: 'device', model: 'First tablet');
const second =
    AndroidDevice(serial: 'second', state: 'device', model: 'Second tablet');

class MemoryTools extends AndroidTools {
  MemoryTools() : super(mirrorDir: '/drive', stateDir: '/state');
  @override
  Future<String?> resolve() async => '/tools/adb';
}

class MemoryAndroidManager extends AndroidUpdateManager {
  MemoryAndroidManager() : super(dataDir: '/drive', stateDir: '/state');
  final memoryTools = MemoryTools();
  String? installedOn;
  AndroidMirroredRelease? mirrored = mirror;
  Completer<void>? downloadWait;
  Completer<void>? installWait;
  int downloaded = 0;
  int checks = 0;
  bool rejectInstall = false;
  bool rejectMirror = false;
  bool rejectInspection = false;
  int sdk = 36;

  @override
  AndroidTools get tools => memoryTools;
  @override
  Future<AndroidMirroredRelease?> loadMirror() async {
    if (rejectMirror) {
      throw const AndroidUpdateException(AndroidUpdateFailure.invalidApk);
    }
    return mirrored;
  }

  @override
  Future<List<AndroidDevice>> devices(AndroidCancellation cancellation) async =>
      [first, second];
  @override
  Future<AndroidDeviceInfo> inspectDevice(
      String serial, AndroidCancellation cancellation) async {
    checks++;
    if (rejectInspection) {
      throw const AndroidUpdateException(
          AndroidUpdateFailure.deviceUnavailable);
    }
    return AndroidDeviceInfo(
        device: serial == 'first' ? first : second,
        userId: 0,
        sdk: sdk,
        abis: ['arm64-v8a'],
        versionCode: 10,
        versionName: '1.0.0');
  }

  @override
  Future<AndroidDeviceInfo> install(
      String serial, AndroidCancellation cancellation,
      {void Function(String)? onStage}) async {
    installedOn = serial;
    onStage?.call(AppL10n.strings.android.installing);
    if (installWait != null) {
      await Future.any([installWait!.future, cancellation.whenCancelled]);
      cancellation.check();
    }
    if (rejectInstall) {
      throw const AndroidUpdateException(
          AndroidUpdateFailure.signatureMismatch);
    }
    return AndroidDeviceInfo(
        device: serial == 'first' ? first : second,
        userId: 0,
        sdk: 36,
        abis: ['arm64-v8a'],
        versionCode: 20,
        versionName: '1.0.0');
  }

  @override
  Future<AndroidMirroredRelease> downloadLatest(
      AndroidCancellation cancellation,
      {void Function(int, int)? onProgress}) async {
    downloaded++;
    onProgress?.call(40, 100);
    if (downloadWait != null) {
      await Future.any([downloadWait!.future, cancellation.whenCancelled]);
      cancellation.check();
    }
    return mirrored = mirror;
  }
}

void main() {
  testWidgets(
      'selects one of multiple devices and verifies the selected update',
      (tester) async {
    final manager = MemoryAndroidManager();
    final controller = AndroidModuleController(
        dataDir: '/drive', stateDir: '/state', manager: manager);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.selectedSerial, isNull);
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    expect(
        tester
            .widget<ActionButton>(find.byKey(const ValueKey('android-install')))
            .onPressed,
        isNull);
    await tester.tap(find.text('Second tablet'));
    await tester.pumpAndSettle();
    expect(controller.selectedSerial, 'second');
    expect(manager.checks, 1);
    await tester.tap(find.byKey(const ValueKey('android-install')));
    await tester.pumpAndSettle();
    expect(manager.installedOn, 'second');
    expect(controller.deviceInfo!.versionCode, 20);
    expect(find.text(stringsOf().android.installed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers a useful signature error and retries the same device',
      (tester) async {
    final manager = MemoryAndroidManager()..rejectInstall = true;
    final controller = AndroidModuleController(
        dataDir: '/drive', stateDir: '/state', manager: manager);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.selectDevice('first');
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    await tester.tap(find.byKey(const ValueKey('android-install')));
    await tester.pumpAndSettle();
    expect(find.text(stringsOf().android.signatureMismatch), findsOneWidget);
    manager.rejectInstall = false;
    await tester.tap(find.text(stringsOf().common.retry));
    await tester.pumpAndSettle();
    expect(manager.installedOn, 'first');
    expect(find.text(stringsOf().android.installed), findsOneWidget);
  });

  testWidgets(
      'read-only drive keeps install and manual export, disables writes',
      (tester) async {
    final controller = AndroidModuleController(
        dataDir: '/drive',
        stateDir: '/state',
        manager: MemoryAndroidManager(),
        readOnly: true);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.selectDevice('first');
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    ActionButton button(String key) =>
        tester.widget<ActionButton>(find.byKey(ValueKey(key)));
    expect(button('android-download').onPressed, isNull);
    expect(button('android-install').onPressed, isNotNull);
    expect(button('android-export').onPressed, isNotNull);
    final copy =
        find.widgetWithText(ActionButton, stringsOf().android.copyTools);
    expect(tester.widget<ActionButton>(copy).onPressed, isNull);
  });

  testWidgets('cancelled installation requires a fresh device check',
      (tester) async {
    final manager = MemoryAndroidManager()..installWait = Completer<void>();
    final controller = AndroidModuleController(
        dataDir: '/drive', stateDir: '/state', manager: manager);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.selectDevice('first');
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    await tester.tap(find.byKey(const ValueKey('android-install')));
    await tester.pump();
    expect(find.text(stringsOf().android.installing), findsOneWidget);
    await tester.tap(find.text(stringsOf().common.cancel));
    await tester.pumpAndSettle();
    expect(find.text(stringsOf().android.cancelled), findsOneWidget);
    expect(controller.deviceInfo, isNull);
    expect(controller.canInstall, isFalse);
    expect(controller.canRetry, isFalse);
    await tester.tap(find.byKey(const ValueKey('android-refresh')));
    await tester.pumpAndSettle();
    expect(controller.canInstall, isTrue);
  });

  testWidgets('failed refresh clears previously installable device state',
      (tester) async {
    final manager = MemoryAndroidManager();
    final controller = AndroidModuleController(
        dataDir: '/drive', stateDir: '/state', manager: manager);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.selectDevice('first');
    expect(controller.canInstall, isTrue);
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    manager.rejectMirror = true;
    await tester.tap(find.byKey(const ValueKey('android-refresh')));
    await tester.pumpAndSettle();
    expect(controller.deviceInfo, isNull);
    expect(controller.release, isNull);
    expect(controller.canInstall, isFalse);
    manager.rejectMirror = false;
    manager.rejectInspection = true;
    await tester.tap(find.text(stringsOf().common.retry));
    await tester.pumpAndSettle();
    expect(controller.deviceInfo, isNull);
    expect(controller.canInstall, isFalse);
  });

  testWidgets('explains incompatible Android before installation',
      (tester) async {
    final manager = MemoryAndroidManager()..sdk = 23;
    final controller = AndroidModuleController(
        dataDir: '/drive', stateDir: '/state', manager: manager);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.selectDevice('first');
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    expect(controller.canInstall, isFalse);
    expect(find.text(stringsOf().android.incompatibleSdk), findsOneWidget);
    expect(
        tester
            .widget<ActionButton>(find.byKey(const ValueKey('android-install')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'download progress can be cancelled and retried without losing the mirror',
      (tester) async {
    final manager = MemoryAndroidManager()..downloadWait = Completer<void>();
    final controller = AndroidModuleController(
        dataDir: '/drive', stateDir: '/state', manager: manager);
    addTearDown(controller.dispose);
    await controller.refresh();
    await pumpScreen(tester, AndroidUpdatePage(controller: controller));
    await tester.tap(find.byKey(const ValueKey('android-download')));
    await tester.pump();
    expect(controller.isDownloading, isTrue);
    expect(controller.received, 40);
    await tester.tap(find.text(stringsOf().common.cancel));
    await tester.pumpAndSettle();
    expect(controller.isBusy, isFalse);
    expect(controller.release, same(mirror));
    expect(find.text(stringsOf().android.cancelled), findsOneWidget);
    manager.downloadWait!.complete();
    await tester.tap(find.byKey(const ValueKey('android-download')));
    await tester.pumpAndSettle();
    expect(manager.downloaded, 2);
    expect(controller.error, isNull);
  });

  for (final language in AppLanguage.values) {
    testWidgets('page fits minimum window in ${language.name}', (tester) async {
      final controller = AndroidModuleController(
          dataDir: '/drive',
          stateDir: '/state',
          manager: MemoryAndroidManager());
      addTearDown(controller.dispose);
      await controller.refresh();
      await pumpScreen(tester, AndroidUpdatePage(controller: controller),
          language: language, size: const Size(760, 560));
      for (var i = 0; i < 7; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
