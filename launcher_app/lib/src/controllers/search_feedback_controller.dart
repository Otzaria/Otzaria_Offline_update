import 'package:error_reports_manager/error_reports_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:library_manager/library_manager.dart';
import 'package:otzaria_manager/otzaria_manager.dart';
import 'package:path/path.dart' as p;

import '../services/app_logger.dart';
import 'dispose_guard.dart';

/// מצב ההסכמה במחשב הזה: ביטול מפורש שונה ממחשב שבו היא אינה ידועה.
enum SearchFeedbackConsent { granted, revoked, unknown }

/// איך נגמרה כתיבת ההסכמה לחיפוש החכם.
enum ConsentWrite {
  granted,

  /// השרת חסם את המפתח של המחשב הזה; הסכמה חדשה לא תעזור.
  blocked,
  failed,
}

class SearchFeedbackController extends ChangeNotifier
    with DisposeGuard, SilentAfterDispose {
  static const Duration _probeCacheTtl = Duration(seconds: 2);

  SearchFeedbackController({
    required this.transport,
    required this.resolveSource,
    Future<ConsentWrite> Function()? grantConsent,
    Future<SearchFeedbackConsent> Function()? consentState,
  })  : _grantConsent = grantConsent,
        _consentState = consentState;

  factory SearchFeedbackController.forDrive({
    required String dataDir,
    required String stateDir,
    String? stateFilesDir,
    required Future<String?> Function() launchPath,
    RunningOtzariaLocator runningLocator = const RunningOtzariaLocator(),
  }) {
    final transport = SearchFeedbackTransport(
      SearchFeedbackTransport.dirIn(dataDir),
    );
    bool? cachedRunning;
    var cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
    Future<bool> isRunning({bool fresh = false}) async {
      if (!fresh &&
          cachedRunning != null &&
          DateTime.now().difference(cachedAt) < _probeCacheTtl) {
        return cachedRunning!;
      }
      final running = (await runningLocator.probe()).isRunning;
      cachedRunning = running;
      cachedAt = DateTime.now();
      return running;
    }

    Future<({LibraryDbLocator locator, String root})?> locate({
      bool fresh = false,
    }) async {
      if (await isRunning(fresh: fresh)) return null;
      final launch = await launchPath();
      if (launch == null) return null;
      final locator = LibraryDbLocator.forLaunch(
        stateDir: stateFilesDir ?? stateDir,
        launchPath: launch,
        dataDir: dataDir,
      );
      final root = await locator.otzariaSettingsRoot(launch);
      return root == null ? null : (locator: locator, root: root);
    }

    Future<SearchFeedbackConsent> consent() async {
      final launch = await launchPath();
      if (launch == null) return SearchFeedbackConsent.unknown;
      final locator = LibraryDbLocator.forLaunch(
        stateDir: stateFilesDir ?? stateDir,
        launchPath: launch,
        dataDir: dataDir,
      );
      final root = await locator.otzariaSettingsRoot(launch);
      if (root == null) return SearchFeedbackConsent.unknown;
      final settings = await locator.settingsReader.read(root);
      if (settings == null) return SearchFeedbackConsent.unknown;
      if (settings.searchFeedbackGranted) return SearchFeedbackConsent.granted;
      return settings.searchFeedbackConsent == null
          ? SearchFeedbackConsent.unknown
          : SearchFeedbackConsent.revoked;
    }

    return SearchFeedbackController(
      transport: transport,
      consentState: consent,
      resolveSource: () async {
        final location = await locate(fresh: true);
        if (location == null) return null;
        final settings = await location.locator.settingsReader.read(
          location.root,
        );
        if (settings?.searchFeedbackGranted != true) return null;
        return p.join(location.root, 'search_feedback');
      },
      grantConsent: () async {
        final location = await locate(fresh: true);
        if (location == null) return ConsentWrite.failed;
        final source = p.join(location.root, 'search_feedback');
        if (!await transport.resumeAfterConsent(source)) {
          return await transport.blockedByServer(source)
              ? ConsentWrite.blocked
              : ConsentWrite.failed;
        }
        if (await isRunning(fresh: true)) return ConsentWrite.failed;
        return await const OtzariaSettingsWriter().grantSearchFeedbackConsent(
          dataRootPath: location.root,
        )
            ? ConsentWrite.granted
            : ConsentWrite.failed;
      },
    );
  }

  /// בלי השהיה שמורה אחרי כשל לא צפוי — לא לולאה צפופה.
  static const Duration idleRetry = Duration(minutes: 15);
  static const Duration minRetry = Duration(seconds: 30);

  final SearchFeedbackTransport transport;
  final Future<String?> Function() resolveSource;
  final Future<ConsentWrite> Function()? _grantConsent;
  final Future<SearchFeedbackConsent> Function()? _consentState;
  bool isCollecting = false;
  bool isUploading = false;
  int outboxCount = 0;
  Future<Duration?>? _run;
  bool _stopRequested = false;

  Future<ConsentWrite> grantConsent() async {
    if (isDisposed || isCollecting || isUploading) return ConsentWrite.failed;
    try {
      return await _grantConsent?.call() ?? ConsentWrite.failed;
    } catch (error) {
      AppLogger.maybeInstance?.error('כתיבת הסכמת החיפוש נכשלה', error);
      return ConsentWrite.failed;
    }
  }

  Future<void> refreshOutbox() async {
    try {
      outboxCount = await transport.count();
    } catch (error) {
      AppLogger.maybeInstance?.error('קריאת תיבת משוב החיפוש נכשלה', error);
      outboxCount = 0;
    }
    notifyListeners();
  }

  Future<int> pendingToCollect() async {
    if (isDisposed || isUploading || isCollecting) return 0;
    try {
      final source = await resolveSource();
      if (source == null) return 0;
      return await transport.pendingForCollection(source);
    } catch (error) {
      AppLogger.maybeInstance?.error('קריאת משוב החיפוש באוצריא נכשלה', error);
      return 0;
    }
  }

  Future<int> collect() async {
    if (isCollecting || isUploading || isDisposed) return 0;
    isCollecting = true;
    notifyListeners();
    try {
      final source = await resolveSource();
      if (source == null) return 0;
      return await transport.collect(
        source,
        mayCollect: () async => await resolveSource() == source,
      );
    } finally {
      isCollecting = false;
      await refreshOutbox();
    }
  }

  Future<SearchFeedbackUploadResult?> upload() async {
    if (isCollecting || isUploading || isDisposed) return null;
    isUploading = true;
    notifyListeners();
    try {
      return await transport.upload();
    } finally {
      isUploading = false;
      await refreshOutbox();
    }
  }

  /// איסוף ואז העלאה, בלי ממשק; כשל נרשם בלוג בלבד. מחזיר מתי לנסות שוב,
  /// או null כשלא נשאר מה לשלוח.
  Future<Duration?> synchronize() async {
    if (isDisposed || isCollecting || isUploading || _run != null) return null;
    _stopRequested = false;
    final run = _run = _synchronize();
    try {
      return await run;
    } finally {
      _run = null;
    }
  }

  /// עצירה מסודרת לפני עדכון עצמי או הפעלה כמנהל: הבקשה נקטעת בלי השהיה,
  /// התור נשאר בכונן, והריצה שנעצרה מבקשת ניסיון חוזר קרוב.
  Future<void> stopAndWait() async {
    final run = _run;
    if (run == null) return;
    _stopRequested = true;
    transport.stop();
    await run;
  }

  /// בלי מקור הסכמה — כמו האיסוף: מקור שנפתר פירושו הסכמה קיימת.
  Future<SearchFeedbackConsent> _consent() async {
    final state = _consentState;
    if (state != null) return state();
    return await resolveSource() == null
        ? SearchFeedbackConsent.unknown
        : SearchFeedbackConsent.granted;
  }

  Future<Duration?> _synchronize() async {
    try {
      final pending = await pendingToCollect();
      if (pending > 0 && !_stopRequested) await collect();
    } catch (error) {
      AppLogger.maybeInstance?.error('איסוף משוב החיפוש נכשל', error);
    }
    try {
      if (isDisposed) return null;
      if (_stopRequested) return minRetry;
      await refreshOutbox();
      if (isDisposed || outboxCount <= 0) return null;
      if (_stopRequested) return minRetry;
      final consent = await _consent();
      if (consent == SearchFeedbackConsent.revoked) {
        AppLogger.maybeInstance?.info('משוב החיפוש: ההסכמה בוטלה, אין העלאה');
        return null;
      }
      if (_stopRequested) return minRetry;
      final result = await upload();
      if (isDisposed) return null;
      if (_stopRequested) return minRetry;
      if (result?.remaining == 0) return null;
      final retryAt = await transport.retryAt();
      final wait = retryAt?.difference(DateTime.now());
      if (wait == null || wait <= Duration.zero) {
        // מה שהתעבורה מדלגת עליו תמיד (מפתח חסר) אינו סיבה לנסות שוב.
        final idle = result != null && result.sent + result.rejected == 0;
        return idle ? null : idleRetry;
      }
      return wait < minRetry ? minRetry : wait;
    } catch (error) {
      AppLogger.maybeInstance?.error('העלאת משוב החיפוש נכשלה', error);
      return isDisposed ? null : idleRetry;
    }
  }

  @override
  void dispose() {
    transport.close();
    super.dispose();
  }
}
