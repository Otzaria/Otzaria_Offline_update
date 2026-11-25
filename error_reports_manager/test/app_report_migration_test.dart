import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late AppReportService source;
  late AppReportService target;

  AppReport report(String id, {String title = 'Original'}) => AppReport(
        reportId: id,
        type: AppReportType.bug,
        trigger: AppReportTrigger.manual,
        title: title,
        description: 'Saved offline',
        reporterEmail: 'qa@example.invalid',
        appVersion: '0.30',
        platform: 'windows',
        createdAt: DateTime.utc(2026, 11, 20),
        diagnostics: const {'attached': 'diagnostics'},
        errorLog: 'attached log',
        images: [
          AppReportImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              fileName: 'example.png',
              mimeType: 'image/png')
        ],
      );

  File pending(AppReportService service) =>
      Directory(p.join(service.directory, 'pending'))
          .listSync()
          .whereType<File>()
          .single;

  void history(AppReportService service, AppReport value) {
    File(p.join(service.directory, 'sent.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'total': 1,
        'reports': [
          value
              .withoutAttachments()
              .copyWith(sentAt: DateTime.utc(2026, 11, 21))
              .toJson()
        ]
      }));
  }

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('app-report-migration-');
    AppReportService service(String name, int day) => AppReportService(
          directory: p.join(sandbox.path, name),
          clock: () => DateTime.utc(2026, 11, day),
          client: MockClient((_) async =>
              throw StateError('Migration must not use the network')),
        );
    source = service('machine', 20);
    target = service('drive', 21);
  });
  tearDown(() {
    source.dispose();
    target.dispose();
    sandbox.deleteSync(recursive: true);
  });

  test('moves the exact envelope, attachments, queue time and id-change budget',
      () async {
    await source.queueReport(report('report'));
    final file = pending(source);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    json['idChanges'] = 2;
    file.writeAsStringSync(jsonEncode(json));
    final bytes = file.readAsBytesSync();

    await target.migratePendingFrom(source.directory);

    expect(await source.getPendingReportsCount(), 0);
    expect(await target.getPendingReportsCount(), 1);
    expect(p.basename(pending(target).path), p.basename(file.path));
    expect(pending(target).readAsBytesSync(), bytes);
    await target.deletePendingReport('report');
    await target.migratePendingFrom(source.directory);
    expect(await target.getPendingReportsCount(), 0);
  });

  test(
      'a valid destination duplicate wins without overwriting its edited payload',
      () async {
    await source.queueReport(report('same'));
    await target.queueReport(report('same', title: 'Newer destination'));
    final bytes = pending(target).readAsBytesSync();

    await target.migratePendingFrom(source.directory);

    expect(await source.getPendingReportsCount(), 0);
    expect(await target.getPendingReportsCount(), 1);
    expect(pending(target).readAsBytesSync(), bytes);
  });

  for (final onSource in [false, true]) {
    test('a sent receipt prevents requeueing (receipt on source: $onSource)',
        () async {
      final value = report('sent');
      await source.queueReport(value);
      history(onSource ? source : target, value);

      await target.migratePendingFrom(source.directory);

      expect(await source.getPendingReportsCount(), 0);
      expect(await target.getPendingReportsCount(), 0);
    });
  }

  for (final broken in [
    '{',
    '{"report":{}}',
    '{"report":{"reportId":"same"}}'
  ]) {
    test(
        'a malformed destination duplicate cannot consume the valid source: $broken',
        () async {
      await source.queueReport(report('same'));
      await target.queueReport(report('same'));
      pending(target).writeAsStringSync(broken);

      await expectLater(
          target.migratePendingFrom(source.directory), throwsFormatException);

      expect(await source.getPendingReportsCount(), 1);
      expect(pending(target).readAsStringSync(), broken);
    });
  }

  test('a duplicate with corrupt image data cannot consume the valid source',
      () async {
    await source.queueReport(report('same'));
    await target.queueReport(report('same'));
    final file = pending(target);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    json['report']['images'][0]['data'] = 'invalid base64!';
    file.writeAsStringSync(jsonEncode(json));

    await expectLater(
        target.migratePendingFrom(source.directory), throwsFormatException);

    expect(await source.getPendingReportsCount(), 1);
  });

  for (final broken in [
    '{',
    '{"reports":42}',
    '{"reports":[{"reportId":"pending"}]}'
  ]) {
    test(
        'corrupt sent history stops the move instead of meaning empty: $broken',
        () async {
      await source.queueReport(report('pending'));
      File(p.join(target.directory, 'sent.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(broken);

      await expectLater(
          target.migratePendingFrom(source.directory), throwsFormatException);

      expect(await source.getPendingReportsCount(), 1);
      expect(await target.getPendingReportsCount(), 0);
    });
  }

  test(
      'a failed destination write retains the source and a retry moves it once',
      () async {
    await source.queueReport(report('pending'));
    final blocker = File(p.join(target.directory, 'pending'))
      ..createSync(recursive: true);

    await expectLater(target.migratePendingFrom(source.directory),
        throwsA(isA<FileSystemException>()));

    expect(await source.getPendingReportsCount(), 1);
    blocker.deleteSync();
    await target.migratePendingFrom(source.directory);
    await target.migratePendingFrom(source.directory);
    expect(await source.getPendingReportsCount(), 0);
    expect(await target.getPendingReportsCount(), 1);
  });

  test(
      'failure after durable copy can be retried without duplicating the report',
      () async {
    await source.queueReport(report('pending'));
    final file = pending(source);

    await expectLater(
        IOOverrides.runWithIOOverrides(
          () => target.migratePendingFrom(source.directory),
          _DenyDelete(file.path),
        ),
        throwsA(isA<FileSystemException>()));

    expect(await source.getPendingReportsCount(), 1);
    expect(await target.getPendingReportsCount(), 1);
    expect(pending(target).readAsBytesSync(), file.readAsBytesSync());
    await target.migratePendingFrom(source.directory);
    expect(await source.getPendingReportsCount(), 0);
    expect(await target.getPendingReportsCount(), 1);
  });

  test('a report queued during a later local session still migrates', () async {
    await source.queueReport(report('first'));
    await target.migratePendingFrom(source.directory);
    await target.deletePendingReport('first');
    await source.queueReport(report('second'));

    await target.migratePendingFrom(source.directory);

    expect(
        (await target.getPendingReports()).map((r) => r.reportId), ['second']);
  });

  test(
      'a report awaiting correction still moves and its identical copy can be retried',
      () async {
    await source.queueReport(report('pending').copyWith(title: ''));
    final file = pending(source);
    await expectLater(
        IOOverrides.runWithIOOverrides(
          () => target.migratePendingFrom(source.directory),
          _DenyDelete(file.path),
        ),
        throwsA(isA<FileSystemException>()));

    await target.migratePendingFrom(source.directory);

    expect(await source.getPendingReportsCount(), 0);
    final saved = (await target.getPendingReports()).single;
    expect(saved.reportId, 'pending');
    expect(saved.title, isEmpty);
  });

  test('a queue never migrates into itself', () async {
    await source.queueReport(report('pending'));
    await source.migratePendingFrom(source.directory);
    expect(await source.getPendingReportsCount(), 1);
  });
}

final class _DenyDelete extends IOOverrides {
  _DenyDelete(this.path);
  final String path;

  @override
  File createFile(String name) =>
      name == path ? _Undeletable(name) : Zone.root.run(() => File(name));
}

class _Undeletable implements File {
  _Undeletable(this.path);
  @override
  final String path;
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async =>
      throw FileSystemException('Injected source cleanup failure', path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
