import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/controllers/launcher_update_controller.dart';
import 'package:launcher_app/src/screens/launcher/launcher_update_page.dart';
import 'package:launcher_app/src/self_update/launcher_release.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

import 'test_harness.dart';

const _release = LauncherRelease(
  tagName: 'v99.1.2',
  name: 'v99.1.2',
  assetName: 'OtzariaUpdates.exe',
  downloadUrl: 'https://example.invalid/OtzariaUpdates.exe',
  sizeBytes: 38 * 1024 * 1024,
);

void main() {
  late Directory tempDir;
  late LauncherUpdateController c;
  late List<String> calls;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('launcher_page_test');
    c = LauncherUpdateController(dataDir: tempDir.path)
      ..status = LauncherUpdateStatus.upToDate;
    calls = [];
  });

  tearDown(() {
    c.dispose();
    tempDir.deleteSync(recursive: true);
  });

  Widget page({
    bool readOnly = false,
    bool busy = false,
    bool admin = true,
    bool checking = false,
  }) =>
      LauncherUpdatePage(
        controller: c,
        readOnly: readOnly,
        busy: busy,
        onCheck: busy ? null : () => calls.add('check'),
        checking: checking,
        onDownload: () => calls.add('download'),
        onInstall: () => calls.add('install'),
        onOpenFolder: () => calls.add('folder'),
        onRestartElevated: admin ? () => calls.add('admin') : null,
      );

  ActionButton primary(WidgetTester tester) =>
      tester.widget<ActionButton>(find.byKey(ShellKeys.statusPrimary));

  final p = stringsOf().pages;

  testWidgets('מעודכן — שבב רגוע, בלי פעולה ובלי "מה חדש"', (tester) async {
    await pumpScreen(tester, page());
    expect(find.text(p.selfTitle), findsOneWidget);
    expect(find.text(p.selfChipUpToDate), findsOneWidget);
    expect(find.text(c.currentVersion), findsOneWidget);
    expect(find.byKey(ShellKeys.statusPrimary), findsNothing);
  });

  testWidgets('"יומן שינויים" בדף הכלי פותח את היומן הארוז', (tester) async {
    final u = stringsOf().launcherUpdate;
    await pumpScreen(tester, page());

    await tester.tap(find.byKey(const ValueKey('launcher.changelog')));
    // טעינת הנכס היא I/O אמיתי — ראו AGENTS.md §3.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text(u.changelogDialogTitle), findsOneWidget);
    expect(find.text(u.changelogNotFound), findsNothing);
  });

  testWidgets('גרסה באתר — מה חדש בדף, ו"הורדה והפעלה מחדש"', (tester) async {
    c.onlineRelease = const LauncherRelease(
      tagName: 'v99.1.2',
      name: 'v99.1.2',
      assetName: 'OtzariaUpdates.exe',
      downloadUrl: 'https://example.invalid/OtzariaUpdates.exe',
      sizeBytes: 38 * 1024 * 1024,
      changelog: '## 99.1.2\n- תיקון בהורדה',
    );
    await pumpScreen(tester, page());

    expect(find.text(p.selfChipOnline('99.1.2')), findsOneWidget);
    expect(find.text(p.selfWhatsNew('99.1.2')), findsOneWidget);
    expect(
      find.textContaining('תיקון בהורדה', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('38'), findsWidgets);
    expect(primary(tester).text, p.selfDownloadButton);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(calls, ['download']);
  });

  // כותרת "מה חדש" בלי תוכן מטעה — בלי הערות אין גם כותרת.
  testWidgets('גרסה בלי תיאור — אין "מה חדש" בכלל', (tester) async {
    c.onlineRelease = _release;
    await pumpScreen(tester, page());

    expect(find.text(p.selfChipOnline('99.1.2')), findsOneWidget);
    expect(find.text(p.selfWhatsNew('99.1.2')), findsNothing);
    expect(find.byType(ReleaseNotesCard), findsNothing);
  });

  testWidgets('טרם נבדק — לא "מעודכן"', (tester) async {
    c.status = LauncherUpdateStatus.idle;
    await pumpScreen(tester, page());

    expect(find.text(stringsOf().common.notCheckedYet), findsOneWidget);
    expect(find.text(p.selfChipUpToDate), findsNothing);
    // "בדוק עכשיו" כמו בבית — לא מבוי סתום.
    expect(primary(tester).text, stringsOf().guide.checkNowLink);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(calls, ['check']);

    await pumpScreen(tester, page(checking: true));
    expect(primary(tester).onPressed, isNull);
    await pumpScreen(tester, page(busy: true));
    expect(primary(tester).onPressed, isNull);
  });

  testWidgets('כונן מוגן — ההורדה מושבתת, עם הסבר', (tester) async {
    c.onlineRelease = _release;
    await pumpScreen(tester, page(readOnly: true));
    expect(primary(tester).onPressed, isNull);
    expect(find.text(p.selfReadOnly), findsOneWidget);
  });

  testWidgets('בזמן משימה — ההתקנה ממתינה לסופה, עם הסבר', (tester) async {
    c
      ..status = LauncherUpdateStatus.readyToInstall
      ..downloadedVersion = '99.1.2'
      ..canInstall = true;
    await pumpScreen(tester, page(busy: true));
    expect(primary(tester).onPressed, isNull);
    expect(
      find.text(stringsOf().launcherUpdate.busyNotice),
      findsOneWidget,
    );
  });

  testWidgets('גרסה בכונן — "התקנה והפעלה מחדש"', (tester) async {
    c
      ..status = LauncherUpdateStatus.readyToInstall
      ..downloadedVersion = '99.1.2'
      ..canInstall = true;
    await pumpScreen(tester, page());
    expect(find.text(p.selfChipOnDrive('99.1.2')), findsOneWidget);
    expect(primary(tester).text, stringsOf().launcherUpdate.installButton);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(calls, ['install']);
  });

  testWidgets('אין קובץ להחלפה — החלפה ידנית ו"פתח את התיקייה"', (
    tester,
  ) async {
    c
      ..status = LauncherUpdateStatus.readyToInstall
      ..downloadedVersion = '99.1.2'
      ..canInstall = false;
    await pumpScreen(tester, page());
    expect(find.text(p.selfManualTitle), findsOneWidget);
    expect(
      find.text(stringsOf().launcherUpdate.installUnavailableNotice),
      findsOneWidget,
    );
    // הנתיב מוצג בנפרד, לא בתוך המשפט.
    expect(find.text(c.mirrorDir), findsOneWidget);
    expect(primary(tester).text, p.selfOpenFolder);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(calls, ['folder']);
  });

  testWidgets('כשל — הסבר רגוע, הסיבה הטכנית בפרטים, ו"נסה שוב"', (
    tester,
  ) async {
    c
      ..onlineRelease = _release
      ..status = LauncherUpdateStatus.error
      ..errorMessage = 'סטטוס 503';
    await pumpScreen(tester, page());
    expect(find.text(p.selfErrorTitle), findsOneWidget);
    expect(find.textContaining(p.selfDownloadFailed), findsOneWidget);
    expect(find.textContaining(p.selfErrorKeepsWorking), findsOneWidget);
    expect(find.textContaining('503'), findsNothing);
    expect(primary(tester).text, stringsOf().common.retry);

    await tester.tap(find.text(stringsOf().common.errorDetailsButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('503'), findsOneWidget);
  });

  testWidgets('ההודעה מתארת את השלב שנכשל, גם כשיש גרסה מוכנה', (
    tester,
  ) async {
    c
      ..status = LauncherUpdateStatus.readyToInstall
      ..downloadedVersion = '99.1.2'
      ..canInstall = true
      ..errorMessage = 'x';
    for (final (failure, text) in [
      (LauncherUpdateFailure.download, p.selfDownloadFailed),
      (LauncherUpdateFailure.install, p.selfInstallFailed),
      (LauncherUpdateFailure.check, p.selfCheckFailed),
    ]) {
      c.failure = failure;
      await pumpScreen(tester, page());
      expect(find.textContaining(text), findsOneWidget, reason: '$failure');
    }
  });

  testWidgets('הרשאות מנהל — "הפעלה מחדש כמנהל" ראשי', (tester) async {
    c
      ..status = LauncherUpdateStatus.readyToInstall
      ..downloadedVersion = '99.1.2'
      ..canInstall = true
      ..needsElevation = true
      ..errorMessage = 'Access denied';
    await pumpScreen(tester, page());
    expect(find.text(p.selfAdminTitle), findsOneWidget);
    expect(primary(tester).text, stringsOf().elevation.bannerConfirm);
    await tester.tap(find.byKey(ShellKeys.statusPrimary));
    expect(calls, ['admin']);

    // בלי הפעלה כמנהל (לא Windows) — חוזרים להתקנה.
    await pumpScreen(tester, page(admin: false));
    expect(primary(tester).text, stringsOf().common.retry);
  });

  testWidgets('מוריד — אחוז ופס', (tester) async {
    c
      ..onlineRelease = _release
      ..status = LauncherUpdateStatus.downloading
      ..downloadReceived = 38
      ..downloadTotal = 100;
    await pumpScreen(tester, page());
    expect(find.text(p.selfDownloading(38)), findsOneWidget);
    // השבב אומר מה יש; ההורדה נאמרת רק בשורת ההתקדמות.
    expect(find.text(p.selfChipOnline('99.1.2')), findsOneWidget);
    expect(find.byType(AppProgressBar), findsOneWidget);
    expect(find.byKey(ShellKeys.statusPrimary), findsNothing);
  });
}
