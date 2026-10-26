import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/reports/reports_page.dart';
import 'package:launcher_app/src/shell/shell_keys.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';

import 'test_harness.dart';

void main() {
  final p = stringsOf().pages;
  final g = stringsOf().guide;

  Widget page({
    int reports = 0,
    bool readOnly = false,
    bool driveFull = false,
    bool legacy = false,
    VoidCallback? onDismissLegacy,
    bool busy = false,
  }) =>
      ReportsPage(
        errorReports: null,
        connection: null,
        isUploadingAll: false,
        busy: busy,
        reportsToCollect: reports,
        onCollect: () {},
        onUpload: null,
        readOnly: readOnly,
        driveFull: driveFull,
        legacyNotice: legacy,
        onDismissLegacy: onDismissLegacy,
      );

  testWidgets('אין מה לאסוף ולשלוח — כרטיס רגוע, עם הכותרת וההסבר', (
    tester,
  ) async {
    await pumpScreen(tester, page());
    expect(find.text(g.tileReports), findsOneWidget);
    expect(find.text(p.repDescription), findsOneWidget);
    expect(find.text(p.repNothingTitle), findsOneWidget);
    expect(find.byKey(ShellKeys.reportsCollect), findsNothing);
    expect(find.byKey(ShellKeys.reportsSend), findsNothing);
  });

  testWidgets('כונן מוגן — אין איסוף, ונאמר למה פעם אחת', (tester) async {
    await pumpScreen(tester, page(reports: 3, readOnly: true));
    expect(find.byKey(ShellKeys.reportsCollect), findsNothing);
    expect(find.text(g.reportsLockedNote(driveFull: false)), findsOneWidget);

    await pumpScreen(
      tester,
      page(reports: 3, readOnly: true, driveFull: true),
    );
    expect(find.text(g.reportsLockedNote(driveFull: true)), findsOneWidget);
  });

  testWidgets('דיווחים ישנים (Hive) — הודעה, ו"הבנתי" מסיר אותה', (
    tester,
  ) async {
    var dismissed = 0;
    await pumpScreen(
      tester,
      page(legacy: true, onDismissLegacy: () => dismissed++),
    );
    final t = stringsOf().errorReports;
    expect(find.text(t.legacyReportsDialogTitle), findsOneWidget);
    await tester.tap(find.text(t.introDialogConfirm));
    expect(dismissed, 1);
  });

  testWidgets('משימה רצה — האיסוף מושבת, ונאמר למה', (tester) async {
    await pumpScreen(tester, page(reports: 2, busy: true));
    expect(
      tester
          .widget<ActionButton>(find.byKey(ShellKeys.reportsCollect))
          .onPressed,
      isNull,
    );
    expect(find.text(p.pageBusyNote), findsOneWidget);
  });

  testWidgets('בלי דיווחי הכלי (בדיקות) — אין שורת "דיווח על בעיה"', (
    tester,
  ) async {
    await pumpScreen(tester, page());
    expect(find.byKey(ShellKeys.reportsProblem), findsNothing);
  });
}
