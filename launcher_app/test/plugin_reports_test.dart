import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/error_reports_controller.dart';
import 'package:launcher_app/src/controllers/plugins_module_controller.dart';
import 'package:launcher_app/src/screens/plugins/plugin_report_dialog.dart';
import 'package:launcher_app/src/screens/plugins/plugins_screen.dart';
import 'package:launcher_app/src/widgets/widgets_exports.dart';
import 'package:otzaria_l10n/otzaria_l10n.dart';
import 'package:plugins_manager/plugins_manager.dart';

import 'test_harness.dart';

final plugin = StorePlugin.fromJson(const {
  'id': 'catalog-id',
  'manifestId': 'manifest-id',
  'pluginUid': 'manifest-id',
  'name': 'תוסף לבדיקה',
  'version': '1.2.3',
});

void main() {
  late Directory dir;
  late DirectoryReportOutbox outbox;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plugin-reports-');
    outbox = DirectoryReportOutbox(dir.path);
  });
  tearDown(() async => dir.delete(recursive: true));

  ErrorReportsController controller(MockClientHandler handler) =>
      ErrorReportsController(
          outbox: outbox,
          resolveQueue: () async => null,
          uploader: ErrorReportUploader(httpClient: MockClient(handler)));

  test('offline report survives restart and auto sends only authored reports',
      () async {
    final offline =
        controller((_) async => throw const SocketException('offline'));
    await offline.queuePluginReport(
        pluginUid: 'manifest-id',
        pluginName: plugin.name,
        pluginVersion: plugin.version,
        reportType: 'content',
        details: '  בעיה בתוכן  ');
    final failed = await offline.uploadAutomaticPluginReports();
    expect(failed!.remaining, 1);
    offline.dispose();
    await outbox.write(
        'collected',
        OutboxReport.encodeFile(OutboxReport.fileJson(
          reportId: 'collected',
          bookTitle: 'collected',
          createdAt: '',
          endpoint: OutboxReport.pluginReportingEndpoint,
          body: {'reportId': 'collected'},
        )));
    final sent = Completer<Map<String, dynamic>>();
    final online = controller((request) async {
      expect(request.url.toString(), OutboxReport.pluginReportingEndpoint);
      sent.complete(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"success":true}', 200);
    });
    addTearDown(online.dispose);
    online.startAutomaticPluginUpload();
    final body = await sent.future;
    expect(body, containsPair('pluginUid', 'manifest-id'));
    expect(body, containsPair('pluginVersion', '1.2.3'));
    expect(body, containsPair('reportType', 'content'));
    expect(body, containsPair('details', 'בעיה בתוכן'));
    expect(body.containsKey('reporterEmail'), isFalse);
    expect(body.containsKey('auto_upload'), isFalse);
    while (online.isUploading) {
      await Future<void>.delayed(Duration.zero);
    }
    expect((await outbox.list()).map((r) => r.reportId), ['collected']);
  });

  test('409 renewal preserves automatic retry across restart', () async {
    var attempts = 0;
    final first =
        controller((_) async => http.Response('', ++attempts == 1 ? 409 : 500));
    await first.queuePluginReport(
        pluginUid: 'legacy-id',
        pluginName: plugin.name,
        pluginVersion: plugin.version,
        reportType: 'bug',
        details: 'תקלה',
        reporterEmail: ' user@example.com ');
    await first.uploadAutomaticPluginReports();
    first.dispose();
    expect((await outbox.list()).single.autoUpload, isTrue);
    final retry = controller((request) async {
      expect(jsonDecode(request.body)['reporterEmail'], 'user@example.com');
      return http.Response('{"success":true}', 200);
    });
    addTearDown(retry.dispose);
    expect((await retry.uploadAutomaticPluginReports())!.sent, 1);
    expect(await outbox.count(), 0);
  });

  testWidgets(
      'report entry is available without installation, hidden on locked drive',
      (tester) async {
    final plugins = PluginsModuleController(mirrorRootDir: dir.path)
      ..plugins = [plugin];
    final reports =
        controller((_) async => http.Response('{"success":true}', 200));
    addTearDown(plugins.dispose);
    addTearDown(reports.dispose);
    Widget screen(bool readOnly) => PluginsScreen(
          controller: plugins,
          reports: reports,
          readOnly: readOnly,
          otzariaInstalled: false,
          online: false,
          detailId: plugin.id,
          onDetailChanged: (_) {},
        );
    await pumpScreen(tester, screen(false));
    expect(find.text(stringsOf().plugins.reportButton), findsOneWidget);
    await pumpScreen(tester, screen(true));
    expect(find.text(stringsOf().plugins.reportButton), findsNothing);
  });

  for (final language in [AppLanguage.hebrew, AppLanguage.english]) {
    testWidgets('website form validates and sends in $language',
        (tester) async {
      final bodies = <Map<String, dynamic>>[];
      // Real file I/O stays outside the widget test's fake clock.
      final reports = controller((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"success":true}', 200);
      });
      addTearDown(reports.dispose);
      final t = stringsOf(language).plugins;
      final selectedPlugin = language == AppLanguage.hebrew
          ? plugin
          : StorePlugin.fromJson(const {
              'id': 'legacy-id',
              'manifestId': 'inferred-from-archive',
              'name': 'Legacy plugin',
              'version': '2.0',
            });
      Future<void>? closed;
      await pumpScreen(
          tester,
          Builder(
              builder: (context) => ActionButton.neutral(
                    text: t.reportButton,
                    onPressed: () {
                      closed = showPluginReportDialog(context,
                          plugin: selectedPlugin, reports: reports);
                    },
                  )),
          language: language,
          size: const Size(800, 900));
      await tester.tap(find.text(t.reportButton));
      await tester.pumpAndSettle();
      expect(find.text(t.reportTitle), findsOneWidget);
      for (final label in [
        t.reportBug,
        t.reportCrash,
        t.reportContent,
        t.reportOther
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(t.reportSend));
      await tester.pumpAndSettle();
      expect(find.text(t.reportEmpty), findsOneWidget);
      await tester.enterText(find.byType(RtlTextField).first, 'a' * 5001);
      expect(
          tester
              .widget<RtlTextField>(find.byType(RtlTextField).first)
              .controller!
              .text
              .length,
          5000);
      await tester.enterText(find.byType(RtlTextField).first, 'בעיה לבדיקה');
      await tester.enterText(find.byType(RtlTextField).last, 'invalid');
      await tester.tap(find.text(t.reportSend));
      await tester.pumpAndSettle();
      expect(find.text(stringsOf(language).appReports.emailInvalid),
          findsOneWidget);
      await tester.enterText(
          find.byType(RtlTextField).last, 'name@example.com');
      await tester.tap(find.text(t.reportContent));
      await tester.runAsync(() async {
        final finished = Completer<void>();
        void onChange() {
          if (bodies.isNotEmpty &&
              !reports.isUploading &&
              !finished.isCompleted) {
            finished.complete();
          }
        }

        reports.addListener(onChange);
        await tester.tap(find.text(t.reportSend));
        await finished.future;
        await Future<void>.delayed(Duration.zero);
        reports.removeListener(onChange);
      });
      await tester.pumpAndSettle();
      await closed;
      expect(find.byType(PluginReportDialog), findsNothing);
      expect(bodies.single['pluginUid'],
          language == AppLanguage.hebrew ? 'manifest-id' : 'legacy-id');
      expect(bodies.single['reportType'], 'content');
      expect(tester.takeException(), isNull);
    });
  }
}
