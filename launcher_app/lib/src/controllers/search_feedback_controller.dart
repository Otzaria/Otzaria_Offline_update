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
    String? Function()? sourceSkipReason,
  })  : _grantConsent = grantConsent,
        _consentState = consentState,
        _sourceSkipReason = sourceSkipReason;

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

    String? skipReason;

    Future<({LibraryDbLocator locator, String root})?> locate({
      bool fresh = false,
    }) async {
      if (await isRunning(fresh: fresh)) {
        skipReason = 'otzaria-running';
        return null;
      }
      final launch = await launchPath();
      if (launch == null) {
        skipReason = 'no-launch-path';
        return null;
      }
      final locator = LibraryDbLocator.forLaunch(
        stateDir: stateFilesDir ?? stateDir,
        launchPath: launch,
        dataDir: dataDir,
      );
      final root = await locator.otzariaSettingsRoot(launch);
      if (root == null) {
        skipReason = 'no-settings-root';
        return null;
      }
      return (locator: locator, root: root);
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
      sourceSkipReason: () => skipReason,
      resolveSource: () async {
        skipReason = null;
        final location = await locate(fresh: true);
        if (location == null) return null;
        final settings = await location.locator.settingsReader.read(
          location.root,
        );
        if (settings?.searchFeedbackGranted != true) {
          skipReason = settings == null ? 'settings-unreadable' : 'no-consent';
          return null;
        }
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
  final String? Function()? _sourceSkipReason;
  String? _lastQuietLine;
  bool isCollecting = false;
  bool isUploading = false;
  int outboxCount = 0;
  bool hasCollected = false;
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

  Future<int> pendingToCollect({void Function(String reason)? onSkip}) async {
    if (isDisposed || isUploading || isCollecting) return 0;
    try {
      final source = await resolveSource();
      if (source == null) {
        onSkip?.call(_sourceSkipReason?.call() ?? 'no-source');
        return 0;
      }
      final pending = await transport.pendingForCollection(source);
      if (pending == 0 && onSkip != null) {
        onSkip(await transport.noCollectionReason(source));
      }
      return pending;
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
      final collected = await transport.collect(
        source,
        mayCollect: () async => await resolveSource() == source,
      );
      if (collected > 0) hasCollected = true;
      return collected;
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

  /// איסוף ואז העלאה ברקע; כשל נרשם בלוג בלבד. מחזיר מתי לנסות שוב,
  /// או null כשלא נשאר מה לשלוח.
  Future<Duration?> synchronize() async {
    if (isDisposed) return null;
    if (isCollecting || isUploading || _run != null) {
      _logRun(_SyncOutcome()..skip = 'already-running');
      return null;
    }
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
    final outcome = _SyncOutcome();
    final delay = await _synchronizeSteps(outcome);
    if (!isDisposed && !outcome.failed) _logRun(outcome);
    return delay;
  }

  /// שורה אחת לכל ריצה; ריצה שלא עשתה דבר נרשמת רק כשהשורה השתנתה.
  void _logRun(_SyncOutcome outcome) {
    final parts = <String>[];
    if (outcome.collected > 0) {
      parts.add('collected ${outcome.collected}');
    } else if (outcome.skip != null) {
      parts.add('not collected (${outcome.skip})');
    }
    if (outcome.uploadSkip != null) {
      parts.add('not uploaded (${outcome.uploadSkip})');
    } else if (outcome.uploadAttempted) {
      parts.add('uploaded ${outcome.sent}, rejected ${outcome.rejected}, '
          'remaining ${outcome.remaining}');
    }
    final line = 'search feedback: ${parts.join(', ')}';
    final quiet =
        outcome.collected == 0 && outcome.sent == 0 && outcome.rejected == 0;
    if (quiet) {
      if (line == _lastQuietLine) return;
      _lastQuietLine = line;
    } else {
      _lastQuietLine = null;
    }
    AppLogger.maybeInstance?.info(line);
  }

  Future<Duration?> _synchronizeSteps(_SyncOutcome outcome) async {
    try {
      final pending = await pendingToCollect(onSkip: (r) => outcome.skip = r);
      if (pending > 0 && !_stopRequested) {
        outcome.collected = await collect();
        if (outcome.collected == 0) outcome.skip = 'nothing-collected';
      } else if (pending > 0) {
        outcome.skip = 'stopped';
      }
    } catch (error) {
      outcome.failed = true;
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
        outcome.uploadSkip = 'consent-revoked';
        return null;
      }
      if (_stopRequested) return minRetry;
      final result = await upload();
      if (isDisposed) return null;
      if (_stopRequested) return minRetry;
      if (result == null) {
        outcome.uploadSkip = 'already-running';
      } else {
        outcome
          ..uploadAttempted = true
          ..sent = result.sent
          ..rejected = result.rejected
          ..remaining = result.remaining;
      }
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
      outcome.failed = true;
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

/// מה ריצת סנכרון אחת עשתה, לשורת הלוג שלה: מספרים וסיבות בלבד.
class _SyncOutcome {
  int collected = 0;
  String? skip;
  bool uploadAttempted = false;
  String? uploadSkip;
  int sent = 0;
  int rejected = 0;
  int remaining = 0;
  bool failed = false;
}
