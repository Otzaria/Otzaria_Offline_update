import 'dart:async';
import 'dart:io';

import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:launcher_app/src/controllers/app_reports_controller.dart';
import 'package:launcher_app/src/controllers/dispose_guard.dart';
import 'package:launcher_app/src/controllers/error_reports_controller.dart';
import 'package:launcher_app/src/controllers/otzaria_module_controller.dart';
import 'package:launcher_app/src/controllers/progress_notifier.dart';
import 'package:launcher_app/src/controllers/search_feedback_controller.dart';
import 'package:launcher_app/src/settings/settings_controller.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('r7-dispose-guard-'));
  tearDown(() => temp.deleteSync(recursive: true));

  MockClient offline() =>
      MockClient((request) async => fail('unexpected request ${request.url}'));

  group('DisposeGuard', () {
    test('isDisposed turns true only on dispose', () {
      final guarded = _Guarded();
      expect(guarded.isDisposed, isFalse);
      guarded.ping();
      guarded.dispose();
      expect(guarded.isDisposed, isTrue);
      expect(guarded.ping, throwsFlutterError);
    });

    test('SilentAfterDispose drops notifications after dispose only', () {
      final silent = _Silent();
      var notified = 0;
      silent.addListener(() => notified++);
      silent.ping();
      expect(notified, 1);
      silent.dispose();
      expect(silent.isDisposed, isTrue);
      expect(silent.ping, returnsNormally);
    });
  });

  group('progress controllers keep the debug assert after dispose', () {
    test('notifyListeners after dispose still throws', () {
      final notifier = _Progress()..dispose();
      expect(notifier.isDisposed, isTrue);
      expect(notifier.ping, throwsFlutterError);
      expect(() => notifier.notifyProgress(), returnsNormally);
    });
  });

  group('SearchFeedbackController after dispose', () {
    test('every action is a no-op and nothing is notified', () async {
      var sources = 0;
      var consents = 0;
      final c = SearchFeedbackController(
        transport: SearchFeedbackTransport(
          p.join(temp.path, 'outbox'),
          client: offline(),
        ),
        resolveSource: () async {
          sources++;
          return null;
        },
        grantConsent: () async {
          consents++;
          return ConsentWrite.granted;
        },
      );
      var notified = 0;
      c.addListener(() => notified++);
      c.dispose();

      expect(await c.grantConsent(), ConsentWrite.failed);
      expect(await c.pendingToCollect(), 0);
      expect(await c.synchronize(), isNull);
      expect(await c.collect(), 0);
      expect(await c.upload(), isNull);
      await c.refreshOutbox();

      expect(sources, 0);
      expect(consents, 0);
      expect(notified, 0);
    });

    test('a collect that ends after dispose does not notify', () async {
      final gate = Completer<String?>();
      final c = SearchFeedbackController(
        transport: SearchFeedbackTransport(
          p.join(temp.path, 'outbox'),
          client: offline(),
        ),
        resolveSource: () => gate.future,
      );
      var notified = 0;
      c.addListener(() => notified++);

      final collecting = c.collect();
      expect(notified, 1);
      c.dispose();
      gate.complete(null);

      expect(await collecting, 0);
      expect(notified, 1);
    });
  });

  group('ErrorReportsController after dispose', () {
    test('upload is refused and refreshing the outbox is silent', () async {
      final c = ErrorReportsController(
        outbox: DirectoryReportOutbox(p.join(temp.path, 'reports')),
        resolveQueue: () async => null,
        uploader: ErrorReportUploader(httpClient: offline()),
      );
      var notified = 0;
      c.addListener(() => notified++);
      c.dispose();

      expect(await c.upload(), isNull);
      await c.refreshOutbox();

      expect(c.isUploading, isFalse);
      expect(notified, 0);
    });
  });

  group('OtzariaModuleController after dispose', () {
    test('a close that ends after dispose neither re-probes nor notifies',
        () async {
      final locator = _CountingLocator();
      final closer = _GatedCloser();
      final c = OtzariaModuleController(
        dataDir: temp.path,
        runningLocator: locator,
        processCloser: closer,
      );
      var notified = 0;
      c.addListener(() => notified++);

      final closing = c.closeRunning();
      expect(notified, 1);
      c.dispose();
      closer.gate.complete(true);

      expect(await closing, isTrue);
      expect(locator.probes, 0);
      expect(notified, 1);
    });
  });

  group('AppReportsController after dispose', () {
    test('a refresh that ends after dispose leaves the counts alone', () async {
      final service = _GatedService();
      final c = AppReportsController(
        service: service,
        collector: _NoAttachments(),
        settings: SettingsController(dataDir: temp.path),
        logsDirectory: temp.path,
        redactor: AppReportRedactor(environment: const {}),
        host: 'PC1',
        isProcessAlive: (_) => false,
      );
      var notified = 0;
      c.addListener(() => notified++);

      final refreshing = c.refresh();
      c.dispose();
      service.gate.complete();
      await refreshing;

      expect(c.pendingCount, 0);
      expect(c.sentTotal, 0);
      expect(notified, 0);
    });
  });
}

class _Guarded extends ChangeNotifier with DisposeGuard {
  void ping() => notifyListeners();
}

class _Silent extends ChangeNotifier with DisposeGuard, SilentAfterDispose {
  void ping() => notifyListeners();
}

class _Progress extends ChangeNotifier with DisposeGuard, ProgressNotifier {
  void ping() => notifyListeners();
}

class _CountingLocator extends RunningOtzariaLocator {
  int probes = 0;

  @override
  Future<RunningOtzariaProbe> probe() async {
    probes++;
    return (isRunning: false, launchPath: null);
  }
}

class _GatedCloser extends OtzariaProcessCloser {
  final gate = Completer<bool>();

  @override
  Future<bool> close({Duration timeout = const Duration(seconds: 8)}) =>
      gate.future;
}

class _GatedService extends AppReportService {
  _GatedService()
      : super(
          directory: '',
          client: MockClient((_) async => http.Response('', 500)),
        );

  final gate = Completer<void>();

  @override
  Future<int> getPendingReportsCount() async {
    await gate.future;
    return 3;
  }

  @override
  Future<int> getSentReportsTotal() async => 2;
}

class _NoAttachments implements AppReportAttachmentsCollector {
  @override
  Future<AppReportAttachments> collect() async =>
      const AppReportAttachments(diagnostics: {}, errorLog: '');
}
