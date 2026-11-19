import 'dart:async';
import 'dart:io';

import 'package:launcher_app/src/services/background_priority.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:plugins_manager/plugins_manager.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final sandbox = Directory.systemTemp.createTempSync('otzaria-test-sandbox-');
  LibraryDbLocator.sandboxForTests(sandbox.path);
  OtzariaManager.sandboxForTests(sandbox.path);
  InstalledPluginsScanner.sandboxForTests(sandbox.path);
  // A real session would lower the test runner's own priority on Windows.
  BackgroundPriority.instance = BackgroundPriority(
    platformSwitch: (_) => true,
    onSwitch: (_, __) {},
  );
  await testMain();
}
