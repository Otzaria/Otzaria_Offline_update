import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/app_shell.dart';
import 'package:launcher_app/src/screens/home_screen.dart';
import 'package:launcher_app/src/services/app_logger.dart';
import 'package:launcher_app/src/services/notices_seen_store.dart';
import 'package:launcher_app/src/settings/app_settings.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'test_harness.dart';
import 'test_support.dart';

void main() {
  late Directory tempDir;
  late SettingsController settings;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('report-lifecycle-');
    await AppLogger.init(tempDir.path);
    settings = SettingsController(dataDir: tempDir.path);
    await settings.update(const AppSettings(autoCheckUpdates: false));
  });

  tearDown(() async {
    settings.dispose();
    AppLogger.resetForTest();
    await deleteTempDir(tempDir);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    required RunningOtzariaLocator locator,
  }) async {
    useViewSize(tester, const Size(1400, 1000));
    await tester.pumpWidget(wrap(AppShell(
      dataDir: tempDir.path,
      settings: settings,
      runningLocator: locator,
      noticesStore:
          MemoryNoticesStore(seen: {NoticesSeenStore.errorReportsIntro}),
      showWindowButtons: false,
    )));
    await tester.pump();
  }

  testWidgets('סגירה שזוהתה ברענון המחזורי מציעה לאסוף גם בלי בדיקה אוטומטית',
      (tester) async {
    final install = Directory(p.join(tempDir.path, 'install'))..createSync();
    final launch = File(p.join(install.path, 'otzaria.exe'))
      ..writeAsStringSync('');
    File(p.join(install.path, 'portable.marker')).writeAsStringSync('');
    final databases =
        Directory(p.join(install.path, 'otzaria_data', 'databases'))
          ..createSync(recursive: true);
    final dbPath = p.join(databases.path, 'user_state.db');
    final db = sqlite3.open(dbPath);
    try {
      db.execute('CREATE TABLE lists (box TEXT, key TEXT, payload_json TEXT, '
          'updated_at INTEGER, PRIMARY KEY (box, key))');
      db.execute('CREATE TABLE pending_reports (id INTEGER PRIMARY KEY, '
          'kind TEXT, payload_json TEXT, created_at INTEGER)');
      db.execute('PRAGMA user_version = 1');
      db.execute('INSERT INTO pending_reports VALUES (1, ?, ?, 0)', [
        UserStateReportQueue.pendingKind,
        jsonEncode({
          'id': 'report-one',
          'senderEmail': 'a@b.co',
          'subject': 'subject',
          'bookTitle': 'book',
          'currentRef': 'ref',
          'lineNumber': 3,
          'errorDetails': 'error',
          'createdAt': '2026-10-13T10:00:00.000Z',
          'schemaVersion': 2,
        }),
      ]);
    } finally {
      db.close();
    }
    File(p.join(tempDir.path, 'logs', 'otzaria_install_state.json'))
        .writeAsStringSync(jsonEncode(OtzariaInstallState(
      installedTagName: 'v0.9.99',
      installDir: install.path,
      launchPath: launch.path,
    ).toJson()));
    expect(
        await tester
            .runAsync(() => UserStateReportQueue(dbPath).countSendable()),
        1);
    final exitSignal = Completer<bool?>();
    final locator = _CollectionLocator(isRunning: true, exitSignal: exitSignal);
    await pumpShell(tester, locator: locator);
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    Future<void> finishIo({bool Function()? until}) async {
      final attempts = until == null ? 100 : 500;
      for (var i = 0; i < attempts; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
        if (until?.call() == true) return;
      }
    }

    await finishIo(until: () => home.otzaria.launchPath != null);
    expect(home.otzaria.launchPath, launch.path);
    final t = stringsOf().errorReports;
    expect(find.text(t.collectDialogTitle), findsNothing);
    locator.isRunning = false;
    exitSignal.complete(true);
    await tester.pump(const Duration(seconds: 4));
    await finishIo(
        until: () => find.text(t.collectDialogTitle).evaluate().isNotEmpty);
    expect(find.text(t.collectDialogTitle), findsOneWidget);
    await tester.tap(find.text(t.collectLater));
    await tester.pumpAndSettle();
    locator.exitSignal = Completer<bool?>();
    locator.isRunning = true;
    await tester
        .widget<HomeScreen>(find.byType(HomeScreen))
        .onProcessStateChanged();
    await tester.pump();
    locator.isRunning = false;
    locator.exitSignal.complete(true);
    await tester.pump(const Duration(seconds: 4));
    await finishIo();
    expect(find.text(t.collectDialogTitle), findsNothing);
  });
}

class _CollectionLocator extends RunningOtzariaLocator {
  _CollectionLocator({required this.isRunning, required this.exitSignal});

  bool isRunning;
  Completer<bool?> exitSignal;

  @override
  Future<RunningOtzariaProbe> probe() async =>
      (isRunning: isRunning, launchPath: null);

  @override
  Future<bool?> waitForExit(Duration timeout) => exitSignal.future;
}
